class_name ModpackInstaller
extends RefCounted
## .mrpack（Modrinth 整合包格式）安装器。
##
## 一个 mrpack 就是个 zip：
##   modrinth.index.json  —— 依赖的 mc / 加载器版本 + 每个文件从哪下、放哪、hash
##   overrides/**         —— 直接覆盖到实例目录的配置、资源包等
##   client-overrides/**  —— 只在客户端生效的覆盖
##
## 安装流程：解压 overrides → 按 index 下载所有文件 → 返回加载器信息（由调用方去装加载器）。


## 打开 mrpack，读 index。返回 {ok, index, zip, error}
static func open_pack(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {"ok": false, "index": {}, "zip": null, "error": "打不开整合包（不是有效的 zip/mrpack）"}
	if not zip.file_exists("modrinth.index.json"):
		zip.close()
		return {"ok": false, "index": {}, "zip": null, "error": "整合包里没有 modrinth.index.json"}
	var raw := zip.read_file("modrinth.index.json")
	var text := raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		zip.close()
		return {"ok": false, "index": {}, "zip": null, "error": "modrinth.index.json 格式不对"}
	return {"ok": true, "index": parsed, "zip": zip, "error": ""}


## 把 mrpack 装到 target_dir。返回 {ok, files, loader, loader_version, minecraft, error}
## loader / loader_version 由调用方拿去装对应的加载器。
static func install(host: Node, path: String, target_dir: String, on_progress := Callable()) -> Dictionary:
	var opened := open_pack(path)
	if not bool(opened.get("ok", false)):
		return {"ok": false, "files": 0, "loader": "", "loader_version": "", "minecraft": "", "error": String(opened.get("error", ""))}

	var zip: ZIPReader = opened["zip"]
	var index: Dictionary = opened["index"]
	DirAccess.make_dir_recursive_absolute(target_dir)

	# 1) 解压 overrides / client-overrides
	on_progress.call("正在解压配置覆盖…", 0.05)
	var extracted := 0
	for entry in zip.get_files():
		var rel := String(entry)
		var dest_rel := ""
		if rel.begins_with("overrides/"):
			dest_rel = rel.substr("overrides/".length())
		elif rel.begins_with("client-overrides/"):
			dest_rel = rel.substr("client-overrides/".length())
		else:
			continue
		if dest_rel.is_empty() or dest_rel.ends_with("/"):
			continue
		var out_path := target_dir.path_join(dest_rel)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var data := zip.read_file(rel)
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(data)
			f.close()
			extracted += 1

	# 2) 依赖信息
	var deps: Dictionary = index.get("dependencies", {})
	var mc := String(deps.get("minecraft", ""))
	var loader := ""
	var loader_version := ""
	for key in ["fabric-loader", "quilt-loader", "neoforge", "forge"]:
		if deps.has(key):
			loader = key.replace("-loader", "")
			loader_version = String(deps[key])
			break

	# 3) 按 index 下载所有文件
	var files: Array = index.get("files", [])
	var total := maxi(files.size(), 1)
	var failed: Array[String] = []
	var done := 0
	for i in files.size():
		if typeof(files[i]) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = files[i]
		var env: Dictionary = item.get("env", {})
		# 只装客户端要的
		if String(env.get("client", "required")) == "unsupported":
			continue
		var rel_path := String(item.get("path", ""))
		if rel_path.is_empty():
			continue
		var urls: Array = item.get("downloads", [])
		if urls.is_empty():
			continue
		var out_path := target_dir.path_join(rel_path)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		on_progress.call("正在下载 %s（%d/%d）…" % [rel_path.get_file(), i + 1, total], 0.1 + 0.85 * float(i) / float(total))
		var dl := await HttpUtil.download_file(host, String(urls[0]), out_path, int(item.get("fileSize", 0)), Callable(), Modrinth.USER_AGENT)
		if bool(dl.get("ok", false)):
			done += 1
		else:
			failed.append(rel_path)

	zip.close()
	on_progress.call("整合包文件就绪", 1.0)
	return {
		"ok": failed.is_empty(),
		"files": done,
		"extracted": extracted,
		"loader": loader,
		"loader_version": loader_version,
		"minecraft": mc,
		"failed": failed,
		"error": "" if failed.is_empty() else "有 %d 个文件没下下来" % failed.size(),
	}
