class_name HttpUtil
extends RefCounted
## 极简 HTTP 工具层。
## 在任意节点下发起请求并 await 结果，自带重试与中文错误文案。
## 注意：调用方节点必须在场景树中（内部会用 create_timer 做重试间隔）。



const USER_AGENT := "gl-downloader/0.2 (Godot Engine)"

## 把 HTTPRequest.Result 与状态码翻译成给人看的文案
static func describe_error(result: int, code: int) -> String:
	if result == HTTPRequest.RESULT_CANT_CONNECT:
		return "无法连接到服务器"
	if result == HTTPRequest.RESULT_CANT_RESOLVE:
		return "域名解析失败"
	if result == HTTPRequest.RESULT_CONNECTION_ERROR:
		return "连接被中断"
	if result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
		return "HTTPS 握手失败"
	if result == HTTPRequest.RESULT_NO_RESPONSE:
		return "服务器没有响应"
	if result == HTTPRequest.RESULT_TIMEOUT:
		return "请求超时"
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return "响应内容超出限制"
	if result == HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
		return "响应解压失败"
	if result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
		return "重定向次数过多"
	if result == HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
		return "无法创建下载文件"
	if result == HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
		return "写入下载文件失败"
	if result == HTTPRequest.RESULT_REQUEST_FAILED:
		return "请求失败"
	if code == 403:
		return "服务器拒绝访问（HTTP 403）"
	if code == 404:
		return "地址不存在（HTTP 404）"
	if code == 429:
		return "请求太频繁被限流（HTTP 429），等一会儿再试"
	if code >= 500:
		return "服务器出错（HTTP %d）" % code
	if code > 0:
		return "服务器返回 HTTP %d" % code
	return "网络错误（代码 %d）" % result


## 拉取一段原始字节
## 返回 {ok, code, body, error}
static func fetch_bytes(host: Node, url: String, timeout: float = 30.0, retries: int = 2, ua_override := "") -> Dictionary:
	var last_error := "未知错误"
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return {"ok": false, "code": 0, "body": PackedByteArray(), "error": "内部错误：宿主节点不在场景树中"}

	for attempt in range(maxi(retries, 0) + 1):
		var http := HTTPRequest.new()
		http.timeout = timeout
		http.use_threads = true
		http.max_redirects = 8
		host.add_child(http)

		var ua := ua_override if not ua_override.is_empty() else USER_AGENT
		var err := http.request(url, PackedStringArray(["User-Agent: " + ua]))
		if err != OK:
			http.queue_free()
			last_error = "无法发起请求：%s" % error_string(err)
		else:
			var resp: Array = await http.request_completed
			http.queue_free()
			var result := int(resp[0])
			var code := int(resp[1])
			var body: PackedByteArray = resp[3]
			if result == HTTPRequest.RESULT_SUCCESS and code == 200:
				return {"ok": true, "code": code, "body": body}
			last_error = describe_error(result, code)

		if attempt < retries:
			await host.get_tree().create_timer(0.6 * float(attempt + 1)).timeout

	return {"ok": false, "code": 0, "body": PackedByteArray(), "error": last_error}


## 拉取并解析 JSON
## 返回 {ok, data, error}
static func fetch_json(host: Node, url: String, timeout: float = 30.0, retries: int = 2, ua_override := "") -> Dictionary:
	var res := await fetch_bytes(host, url, timeout, retries, ua_override)
	if not bool(res.get("ok", false)):
		return {"ok": false, "data": {}, "error": String(res.get("error", "未知错误"))}

	var text := (res["body"] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "data": {}, "error": "返回内容不是有效的 JSON"}
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "返回内容格式异常"}
	return {"ok": true, "data": parsed, "error": ""}


## 同 fetch_json，但允许顶层是数组（有些接口直接返回数组，例如 Java 运行时清单）
## 返回 {ok, data(任意类型), error}
static func fetch_json_any(host: Node, url: String, timeout: float = 30.0, retries: int = 2, ua_override := "") -> Dictionary:
	var res := await fetch_bytes(host, url, timeout, retries, ua_override)
	if not bool(res.get("ok", false)):
		return {"ok": false, "data": null, "error": String(res.get("error", "未知错误"))}

	var text := (res["body"] as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "data": null, "error": "返回内容不是有效的 JSON"}
	return {"ok": true, "data": parsed, "error": ""}


## 通用文件下载（流式写盘 + 进度回调）。on_progress: func(text, ratio)
static func download_file(host: Node, url: String, path: String, expected_size := 0, on_progress := Callable(), ua_override := "") -> Dictionary:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var http := HTTPRequest.new()
	http.timeout = 0.0
	http.use_threads = true
	http.max_redirects = 8
	http.download_file = path
	host.add_child(http)

	var ua2 := ua_override if not ua_override.is_empty() else USER_AGENT
	var err := http.request(url, PackedStringArray(["User-Agent: " + ua2]))
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "无法发起下载：%s" % error_string(err)}

	var state := {"done": false, "result": -1, "code": 0}
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		state["done"] = true
		state["result"] = result
		state["code"] = code
	)

	var last_bucket := -1
	while not bool(state["done"]) and is_instance_valid(http):
		if expected_size > 0 and on_progress.is_valid():
			var got := int(http.get_downloaded_bytes())
			var ratio := clampf(float(got) / float(expected_size), 0.0, 1.0)
			var bucket := int(ratio * 20.0)
			if bucket != last_bucket:
				last_bucket = bucket
				on_progress.call("下载中… %d%%" % int(ratio * 100.0), ratio)
		await host.get_tree().process_frame

	var result := int(state["result"])
	var code := int(state["code"])
	if is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 206):
		return {"ok": false, "error": describe_error(result, code)}
	return {"ok": true}
