class_name DownloadQueue
extends Node
## 限并发下载队列（下载模块的心脏）。
##
## 特点：
##   * 每个任务一个独立的 HTTPRequest，互不阻塞，完成后立即释放；
##   * 先写 <文件>.part，校验通过才改名，避免半截文件；
##   * 已存在且大小一致的文件直接跳过（增量下载/断点续传的基础）；
##   * 失败自动重试，重试仍失败则记录并继续，不中断整批；
##   * 停滞看门狗：45 秒没有任何字节增长就判失败重试；
##   * 暂停 = 不再开新任务（正在传的会传完），取消 = 立即中断并丢弃队列。

signal progressed(snapshot: Dictionary)
signal file_failed(path: String, message: String)
signal batch_finished(ok: bool, failed_count: int)

const MAX_RETRY := 3
const STALL_TIMEOUT := 45.0
const EMIT_INTERVAL := 0.15
const SPEED_WINDOW := 0.6

## 同时下载的文件数。家里宽带 16 已经能吃满，太大反而被限速/触发防刷。
var max_concurrent := 16
## 新下载的文件是否校验 SHA-1（老文件跳过时只比大小，避免启动时卡顿）
var verify_sha1 := true
## true = 无视本地已有文件，全部重新下载
var force_overwrite := false

var _tasks: Array[Dictionary] = []
var _retry: Array[Dictionary] = []
var _cursor := 0
var _inflight: Array[Dictionary] = []

var _running := false
var _paused := false

var _total_files := 0
var _done_files := 0
var _failed_files := 0
var _total_bytes := 0
var _done_bytes := 0

var _speed := 0.0
var _speed_bytes := 0
var _speed_elapsed := 0.0
var _emit_elapsed := 0.0

var _failures: Array[Dictionary] = []


func start(tasks: Array) -> void:
	if _running:
		return
	_tasks.clear()
	for t in tasks:
		if typeof(t) == TYPE_DICTIONARY:
			_tasks.append((t as Dictionary).duplicate())

	_retry.clear()
	_inflight.clear()
	_cursor = 0
	_failures.clear()

	_total_files = _tasks.size()
	_done_files = 0
	_failed_files = 0
	_total_bytes = 0
	_done_bytes = 0
	for t in _tasks:
		_total_bytes += maxi(int(t.get("size", 0)), 0)

	_speed = 0.0
	_speed_bytes = 0
	_speed_elapsed = 0.0
	_emit_elapsed = 0.0
	_paused = false
	_running = _total_files > 0

	if not _running:
		batch_finished.emit(true, 0)
		return
	_emit_progress()


func set_paused(value: bool) -> void:
	if not _running:
		return
	_paused = value
	_emit_progress()


func is_paused() -> bool:
	return _paused


func is_running() -> bool:
	return _running


func cancel() -> void:
	if not _running and _inflight.is_empty():
		return
	_running = false
	_paused = false
	for item in _inflight:
		var http: Variant = item.get("node")
		if is_instance_valid(http):
			(http as HTTPRequest).cancel_request()
			(http as HTTPRequest).queue_free()
	_inflight.clear()

	# 清掉半截文件，避免下次误判
	for t in _tasks:
		var part := String(t.get("path", "")) + ".part"
		if FileAccess.file_exists(part):
			DirAccess.remove_absolute(part)

	_tasks.clear()
	_retry.clear()
	_cursor = 0
	_speed = 0.0


func failures() -> Array[Dictionary]:
	return _failures


func snapshot() -> Dictionary:
	return {
		"running": _running,
		"paused": _paused,
		"total_files": _total_files,
		"done_files": _done_files,
		"failed_files": _failed_files,
		"total_bytes": _total_bytes,
		"done_bytes": _current_bytes(),
		"speed": _speed,
		"active": _active_labels(),
	}


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	if not _running:
		return

	_tick_inflight(delta)
	if not _paused:
		_pump()

	_speed_elapsed += delta
	if _speed_elapsed >= SPEED_WINDOW:
		var now := _current_bytes()
		_speed = maxf(float(now - _speed_bytes), 0.0) / maxf(_speed_elapsed, 0.001)
		_speed_bytes = now
		_speed_elapsed = 0.0

	_emit_elapsed += delta
	if _emit_elapsed >= EMIT_INTERVAL:
		_emit_elapsed = 0.0
		_emit_progress()

	if _running and _inflight.is_empty() and _retry.is_empty() and _cursor >= _tasks.size():
		_finish()


func _pump() -> void:
	var guard := 0
	while _running and not _paused and _inflight.size() < max_concurrent:
		guard += 1
		if guard > 4096:
			break
		var ti := _next_task()
		if ti < 0:
			break
		_begin(ti)


## 取出下一个真正需要下载的任务下标；已存在的文件在这里就地「完成」掉。
func _next_task() -> int:
	while not _retry.is_empty():
		_tasks.append(_retry.pop_front())
		return _tasks.size() - 1

	while _cursor < _tasks.size():
		var ti := _cursor
		_cursor += 1
		var task: Dictionary = _tasks[ti]
		if _already_present(task):
			_done_files += 1
			_done_bytes += maxi(int(task.get("size", 0)), 0)
			continue
		return ti
	return -1


func _already_present(task: Dictionary) -> bool:
	if force_overwrite:
		return false
	var path := String(task.get("path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	# 内置文件（版本 JSON / 资源索引）：磁盘上已经有这一份就不再覆盖，
	# 免得把别的启动器写的版本信息冲掉（内容语义相同，只是格式可能不同）
	if task.has("content"):
		return true
	var expected := int(task.get("size", 0))
	if expected <= 0:
		return true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var actual := f.get_length()
	f.close()
	return actual == expected


func _begin(ti: int) -> void:
	var task: Dictionary = _tasks[ti]
	var path := String(task.get("path", ""))
	if path.is_empty():
		_fail_task(ti, "任务缺少目标路径")
		return

	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			_fail_task(ti, "无法创建目录：%s（%s）" % [dir, error_string(mk)])
			return

	# 内置文件（版本 JSON / 资源索引）不用联网，直接写盘
	if task.has("content"):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_fail_task(ti, "无法写入文件：%s（%s）" % [path, error_string(FileAccess.get_open_error())])
			return
		f.store_string(String(task["content"]))
		f.close()
		_done_files += 1
		_done_bytes += maxi(int(task.get("size", 0)), 0)
		return

	var url := String(task.get("url", ""))
	if url.is_empty():
		_fail_task(ti, "任务缺少下载地址")
		return

	var part := path + ".part"
	if FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)

	var http := HTTPRequest.new()
	# 0 = 不设整体超时，改由停滞看门狗判断（大文件在慢速网络上不该被误杀）
	http.timeout = 0.0
	http.use_threads = true
	http.download_file = part
	http.download_chunk_size = 131072
	http.max_redirects = 8
	add_child(http)

	var err := http.request(url, PackedStringArray(["User-Agent: " + HttpUtil.USER_AGENT]))
	if err != OK:
		http.queue_free()
		_fail_task(ti, "无法发起下载：%s" % error_string(err))
		return

	http.request_completed.connect(_on_request_completed.bind(http, ti))
	_inflight.append({"node": http, "task": ti, "bytes": 0, "idle": 0.0, "label": String(task.get("label", ""))})


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest, ti: int) -> void:
	var idx := _index_of(http)
	if idx >= 0:
		_inflight.remove_at(idx)
	if is_instance_valid(http):
		http.queue_free()

	if not _running:
		return
	if ti < 0 or ti >= _tasks.size():
		return

	if result == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 206):
		if _verify_part(ti):
			_promote(ti)
			_pump()
			return
		_retry_or_fail(ti, "文件校验失败（内容不完整）")
		_pump()
		return

	_retry_or_fail(ti, HttpUtil.describe_error(result, code))
	_pump()


func _tick_inflight(delta: float) -> void:
	for item in _inflight:
		var http: Variant = item.get("node")
		if not is_instance_valid(http):
			continue
		var got := int((http as HTTPRequest).get_downloaded_bytes())
		if got > int(item["bytes"]):
			item["bytes"] = got
			item["idle"] = 0.0
		else:
			item["idle"] = float(item["idle"]) + delta
			if float(item["idle"]) > STALL_TIMEOUT:
				# 交给 request_completed 不好处理，这里主动断掉并当作失败重试
				var ti := int(item["task"])
				item["idle"] = -1.0e9  # 标记，避免重复触发
				(http as HTTPRequest).cancel_request()
				(http as HTTPRequest).queue_free()
				var idx := _index_of(http)
				if idx >= 0:
					_inflight.remove_at(idx)
				_retry_or_fail(ti, "下载停滞超过 %d 秒" % int(STALL_TIMEOUT))
				return


func _index_of(http: HTTPRequest) -> int:
	for i in _inflight.size():
		if _inflight[i].get("node") == http:
			return i
	return -1


# ---------------------------------------------------------------- 校验与落盘

func _verify_part(ti: int) -> bool:
	var task: Dictionary = _tasks[ti]
	var part := String(task.get("path", "")) + ".part"
	if not FileAccess.file_exists(part):
		return false

	var expected := int(task.get("size", 0))
	if expected > 0:
		var f := FileAccess.open(part, FileAccess.READ)
		if f == null:
			return false
		var actual := f.get_length()
		f.close()
		if actual != expected:
			return false

	var sha1 := String(task.get("sha1", ""))
	if verify_sha1 and sha1.length() == 40:
		if sha1_of_file(part) != sha1.to_lower():
			return false
	return true


func _promote(ti: int) -> void:
	var task: Dictionary = _tasks[ti]
	var path := String(task.get("path", ""))
	var part := path + ".part"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(part, path)
	if err != OK:
		_fail_task(ti, "无法重命名临时文件：%s" % error_string(err))
		return
	_done_files += 1
	_done_bytes += maxi(int(task.get("size", 0)), 0)


func _retry_or_fail(ti: int, message: String) -> void:
	var task: Dictionary = _tasks[ti]
	var attempt := int(task.get("attempt", 0)) + 1
	task["attempt"] = attempt

	var part := String(task.get("path", "")) + ".part"
	if FileAccess.file_exists(part):
		DirAccess.remove_absolute(part)

	if attempt <= MAX_RETRY and _running:
		_retry.append(task)
		return
	_fail_task(ti, message)


func _fail_task(ti: int, message: String) -> void:
	_failed_files += 1
	var path := String(_tasks[ti].get("path", "")) if ti >= 0 and ti < _tasks.size() else ""
	_failures.append({"path": path, "message": message})
	file_failed.emit(path, message)


func _finish() -> void:
	_running = false
	_paused = false
	_speed = 0.0
	_emit_progress()
	batch_finished.emit(_failed_files == 0, _failed_files)


# ---------------------------------------------------------------- 统计

func _current_bytes() -> int:
	var total := _done_bytes
	for item in _inflight:
		total += maxi(int(item["bytes"]), 0)
	return total


func _active_labels() -> Array:
	var out: Array = []
	for item in _inflight:
		var label := String(item.get("label", ""))
		if not label.is_empty() and not out.has(label):
			out.append(label)
	return out


func _emit_progress() -> void:
	progressed.emit(snapshot())


func sha1_of_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	while f.get_position() < f.get_length():
		var chunk := f.get_buffer(65536)
		if chunk.is_empty():
			break
		ctx.update(chunk)
	f.close()
	return ctx.finish().hex_encode()
