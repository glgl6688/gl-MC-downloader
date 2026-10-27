class_name GLog
extends RefCounted
## 运行日志：g-log-l.md，程序同目录，最新记录在最上面。
## 正常操作用绿色、报错用红色、时间用白色。

const FILE_NAME := "g-log-l.md"
const HEADER := "# g-log-l 运行日志\n\n> 最新记录在最上面。绿色 = 正常操作，红色 = 报错，白色 = 时间。\n\n"
const MAX_LINES := 600

static var _path := ""
static var _ready := false


## 启动时调用一次：定位可执行文件所在目录，没有日志文件就新建
static func init() -> void:
	if _ready:
		return
	_ready = true
	var base := OS.get_executable_path().get_base_dir()
	if base.is_empty() or OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://")
	_path = base.path_join(FILE_NAME)
	if not FileAccess.file_exists(_path):
		var f := FileAccess.open(_path, FileAccess.WRITE)
		if f != null:
			f.store_string(HEADER)
			f.close()
	info("程序启动，日志文件位置：%s" % _path)


static func log_path() -> String:
	return _path


## 正常操作（绿）
static func info(text: String) -> void:
	_write(text, "#3fb950")


## 报错（红）
static func error(text: String) -> void:
	_write("【出错】" + text, "#f85149")


## 警告（黄）
static func warn(text: String) -> void:
	_write("【注意】" + text, "#d29922")


static func _write(text: String, color: String) -> void:
	if not _ready:
		init()
	if _path.is_empty():
		return
	var stamp := Time.get_datetime_string_from_system(false, true)
	var line := "<span style=\"color:#ffffff\">%s</span> <span style=\"color:%s\">%s</span>\n" % [
		stamp, color, text.replace("\n", " ")
	]

	var old := ""
	if FileAccess.file_exists(_path):
		var f := FileAccess.open(_path, FileAccess.READ)
		if f != null:
			old = f.get_as_text()
			f.close()

	var body := old
	if body.begins_with(HEADER):
		body = body.substr(HEADER.length())

	var rows := body.split("\n", false)
	if rows.size() > MAX_LINES:
		rows = rows.slice(0, MAX_LINES)
	body = "\n".join(rows)
	if not body.is_empty() and not body.ends_with("\n"):
		body += "\n"

	var out := FileAccess.open(_path, FileAccess.WRITE)
	if out == null:
		return
	out.store_string(HEADER + line + body)
	out.close()
