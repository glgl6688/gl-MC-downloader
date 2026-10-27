class_name InstallPlan
extends RefCounted
## 安装计划：把一份「版本 JSON」展开成待下载的文件清单。
##
## 计划里保存的永远是 **官方 URL**，下载时再由 DownloadSource.resolve() 改写，
## 因此同一个计划可以随时切换下载源，不必重新生成。
##
## 生成的文件项（字典）字段：
##   url     官方下载地址（内置文件为空）
##   path    目标绝对路径
##   size    期望字节数（0 表示未知）
##   sha1    期望 SHA-1（空表示不校验）
##   kind    client / library / asset / logging / meta
##   label   给界面看的中文说明
##   content 仅内置文件使用：要写入的文本内容

var version_id := ""
var version_type := ""
var main_class := ""
var java_major := 0
## 官方给这个版本指定的 Java 组件名（例如 java-runtime-delta），仅用于提示
var java_component := ""
var asset_index_id := ""
var total_bytes := 0

var files: Array[Dictionary] = []
## 需要解压的本地库（老版本的原生库）：[{zip, dest, exclude}]
var natives: Array[Dictionary] = []
var error := ""
## 自定义版本名（留空 = 用官方的版本号）
var custom_name := ""
## 父版本被改过名时，用它替掉 JSON 里的 inheritsFrom
var parent_override := ""

## ---- 启动游戏要用的东西（build 时顺带算好）----
## 合并 inheritsFrom 之后的完整版本 JSON
var resolved: Dictionary = {}
## 父版本 id（Forge / Fabric / OptiFine 这类加载器版本会指向原版）
var inherits_from := ""
## 父版本的原始 JSON（要单独写到 versions/<父>/ 里，启动器才认得）
var parent_json: Dictionary = {}
## 启动 classpath（依赖库 + 客户端 jar），绝对路径
var classpath: Array[String] = []
## 原生库目录（-Djava.library.path）
var natives_dir := ""
## log4j 配置路径（-Dlog4j.configurationFile）
var logging_config := ""
var assets_root := ""
var client_jar := ""


## 版本清单 id → 版本 JSON 地址；界面加载完清单后调一次，供解析 inheritsFrom 用
static var version_index: Dictionary = {}


func is_valid() -> bool:
	return error.is_empty() and not files.is_empty()


## 从版本清单条目出发，生成完整计划。
## 失败时返回 error 非空的计划（不抛异常，方便界面直接展示原因）。
static func build(host: Node, source: DownloadSource, version: McVersion, game_dir: String, p_custom_name := "", p_parent_override := "") -> InstallPlan:
	var plan := InstallPlan.new()
	plan.version_id = version.id
	plan.version_type = version.type
	plan.custom_name = p_custom_name.strip_edges()
	plan.parent_override = p_parent_override.strip_edges()

	if version.url.is_empty():
		# 加载器版本（Fabric/Forge 装完留在本地）按 id 读本地 JSON
		var local := await fetch_version_json(host, source, version.id, game_dir)
		if local.is_empty():
			plan.error = "该版本没有提供版本 JSON 地址，本地也找不到"
			return plan
		return await plan.finish_build(host, source, local, game_dir)

	var res := await HttpUtil.fetch_json(host, source.resolve(version.url))
	if not bool(res.get("ok", false)):
		plan.error = "获取版本信息失败：%s" % String(res.get("error", "未知错误"))
		return plan

	return await plan.finish_build(host, source, res["data"], game_dir)


## 只用 id 构造一个 McVersion（加载器版本、已安装版本都走这条）
static func local_version(version_id: String) -> McVersion:
	var v := McVersion.new()
	v.id = version_id
	v.type = "release"
	return v


## 拿到版本 JSON 之后的完整构建（含 inheritsFrom 合并）
func finish_build(host: Node, source: DownloadSource, raw_data: Dictionary, game_dir: String) -> InstallPlan:
	var plan := self
	var data: Dictionary = raw_data

	# 处理 inheritsFrom：加载器版本（Forge / Fabric / OptiFine）本质是「原版 + 补丁」
	var guard := 0
	while data.has("inheritsFrom") and guard < 5:
		guard += 1
		var raw_parent_id := String(data.get("inheritsFrom", ""))
		var parent_id := raw_parent_id
		# 原版被改成自定义名字时，父版本要指向那个文件夹名
		if not plan.parent_override.is_empty():
			parent_id = plan.parent_override
			data["inheritsFrom"] = parent_id
		if parent_id.is_empty():
			break
		plan.inherits_from = parent_id
		var parent := await fetch_version_json(host, source, parent_id, game_dir)
		if parent.is_empty() and parent_id != raw_parent_id:
			# 改了名但本地还没有那份 JSON，就用官方 id 去拿，再按新名字写盘
			parent = await fetch_version_json(host, source, raw_parent_id, game_dir)
		if parent.is_empty():
			plan.error = "找不到父版本 %s 的版本信息" % parent_id
			return plan
		plan.parent_json = parent
		data = merge_version(parent, data)

	plan.resolved = data
	var vid := String(data.get("id", plan.version_id))
	if vid.is_empty():
		vid = plan.version_id
	# 自定义版本名：文件夹名和 JSON 里的 id 必须一起改，启动器才认
	if not plan.custom_name.is_empty():
		vid = plan.custom_name
	plan.version_id = vid
	data["id"] = vid
	if not raw_data.is_empty():
		raw_data["id"] = vid
	plan.main_class = String(data.get("mainClass", ""))
	var java_info: Dictionary = data.get("javaVersion", {})
	plan.java_major = int(java_info.get("majorVersion", 0))
	plan.java_component = String(java_info.get("component", ""))

	var version_dir := game_dir.path_join("versions").path_join(vid)
	var libraries_dir := game_dir.path_join("libraries")
	var assets_dir := game_dir.path_join("assets")
	plan.assets_root = assets_dir
	plan.natives_dir = version_dir.path_join("natives")

	# 版本 JSON 本身的副本。
	# 加载器版本必须保留 inheritsFrom，启动器才能顺着父版本找到客户端 jar；
	# 同时把父版本的 JSON 也写进去，否则启动器只看到一个「找不到父版本」的残版本。
	var json_to_write: Dictionary = raw_data if not plan.inherits_from.is_empty() else data
	plan._add_content(
		version_dir.path_join(vid + ".json"),
		JSON.stringify(json_to_write, "\t"),
		"meta", "版本元数据"
	)
	if not plan.parent_json.is_empty() and not plan.inherits_from.is_empty():
		var pdir := game_dir.path_join("versions").path_join(plan.inherits_from)
		plan._add_content(
			pdir.path_join(plan.inherits_from + ".json"),
			JSON.stringify(plan.parent_json, "\t"),
			"meta", "原版版本信息"
		)

	# 1) 客户端主 jar
	#    带 inheritsFrom 的加载器版本没有自己的 jar，客户端 jar 属于父版本
	var downloads: Dictionary = data.get("downloads", {})
	var client: Dictionary = downloads.get("client", {})
	if client.is_empty() or String(client.get("url", "")).is_empty():
		plan.error = "该版本没有提供客户端下载地址"
		return plan
	var jar_owner := vid
	if not plan.inherits_from.is_empty():
		jar_owner = plan.inherits_from
	var jar_dir := game_dir.path_join("versions").path_join(jar_owner)
	plan.client_jar = jar_dir.path_join(jar_owner + ".jar")
	plan._add(
		String(client.get("url", "")),
		plan.client_jar,
		int(client.get("size", 0)),
		String(client.get("sha1", "")),
		"client", "客户端主文件"
	)

	# 2) 依赖库 + 原生库
	await plan._build_libraries(data, libraries_dir, version_dir)

	# 3) 资源索引 + 资源文件
	await plan._build_assets(host, source, data, assets_dir)

	# 4) 日志配置
	var logging_client: Dictionary = data.get("logging", {}).get("client", {})
	if not logging_client.is_empty():
		var log_file: Dictionary = logging_client.get("file", {})
		if not log_file.is_empty():
			var log_name := String(log_file.get("id", "log4j.xml"))
			plan.logging_config = assets_dir.path_join("log_configs").path_join(log_name)
			plan._add(
				String(log_file.get("url", "")),
				plan.logging_config,
				int(log_file.get("size", 0)),
				String(log_file.get("sha1", "")),
				"logging", "日志配置"
			)

	plan._finish_launch_fields()
	plan._recount()
	return plan


## 收尾：把客户端 jar 追加到 classpath 末尾
func _finish_launch_fields() -> void:
	if not client_jar.is_empty() and not classpath.has(client_jar):
		classpath.append(client_jar)


## 设置「版本 id → 版本 JSON 地址」索引，解析 inheritsFrom 时用
static func set_version_index(index: Dictionary) -> void:
	version_index = index


## 取某个版本的版本 JSON：优先用本地已存在的，其次按清单地址拉
static func fetch_version_json(host: Node, source: DownloadSource, vid: String, game_dir: String) -> Dictionary:
	var local := game_dir.path_join("versions").path_join(vid).path_join(vid + ".json")
	if FileAccess.file_exists(local):
		var f := FileAccess.open(local, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				return parsed

	var url := String(version_index.get(vid, ""))
	if url.is_empty():
		return {}
	var res := await HttpUtil.fetch_json(host, source.resolve(url))
	if not bool(res.get("ok", false)):
		return {}
	return res["data"]


## 把父版本和子版本（加载器）合并成一份完整版本 JSON
static func merge_version(parent: Dictionary, child: Dictionary) -> Dictionary:
	var merged := parent.duplicate(true)
	for raw_key in child:
		var key := String(raw_key)
		if key == "inheritsFrom":
			continue
		match key:
			"libraries":
				var all: Array = []
				all.append_array(merged.get("libraries", []) as Array)
				all.append_array((child[key] as Array).duplicate())
				var out: Array = []
				var at := {}
				for lib in all:
					if typeof(lib) != TYPE_DICTIONARY:
						continue
					var lib_name := String((lib as Dictionary).get("name", ""))
					if at.has(lib_name):
						out[int(at[lib_name])] = lib
					else:
						at[lib_name] = out.size()
						out.append(lib)
				merged["libraries"] = out
			"arguments":
				var pargs: Dictionary = merged.get("arguments", {})
				var cargs: Dictionary = child[key]
				var merged_args: Dictionary = {}
				for k in ["game", "jvm"]:
					var arr: Array = []
					arr.append_array(pargs.get(k, []) as Array)
					arr.append_array(cargs.get(k, []) as Array)
					merged_args[k] = arr
				merged["arguments"] = merged_args
			_:
				merged[key] = child[key]
	return merged


func _build_libraries(data: Dictionary, libraries_dir: String, version_dir: String) -> void:
	var libs: Array = data.get("libraries", [])
	var seen_paths := {}
	var natives_dest := version_dir.path_join("natives")

	for entry in libs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var lib: Dictionary = entry
		if not _rules_allow(lib.get("rules", [])):
			continue

		var dl: Dictionary = lib.get("downloads", {})

		# 普通依赖
		var artifact: Dictionary = dl.get("artifact", {})
		# Fabric / Quilt 的库没有 downloads 字段，只有 name + url（maven 风格）
		if artifact.is_empty() and not String(lib.get("name", "")).is_empty():
			var parts := String(lib["name"]).split(":")
			if parts.size() >= 3:
				var rel := "%s/%s/%s/%s-%s.jar" % [
					String(parts[0]).replace(".", "/"), parts[1], parts[2], parts[1], parts[2],
				]
				var maven := String(lib.get("url", ""))
				if maven.is_empty():
					maven = "https://maven.fabricmc.net/"
				maven = maven.trim_suffix("/")
				if not seen_paths.has(rel):
					seen_paths[rel] = true
					_add(
						maven + "/" + rel,
						libraries_dir.path_join(rel),
						int(lib.get("size", 0)),
						String(lib.get("sha1", "")),
						"library", "依赖库"
					)
					classpath.append(libraries_dir.path_join(rel))
				continue
		if not artifact.is_empty():
			var rel := String(artifact.get("path", ""))
			if not rel.is_empty() and not seen_paths.has(rel):
				seen_paths[rel] = true
				_add(
					String(artifact.get("url", "")),
					libraries_dir.path_join(rel),
					int(artifact.get("size", 0)),
					String(artifact.get("sha1", "")),
					"library", "依赖库"
				)
				classpath.append(libraries_dir.path_join(rel))

		# 老版本（约 1.19 之前）的原生库：按当前系统取分类器
		var natives_map: Dictionary = lib.get("natives", {})
		if natives_map.is_empty():
			continue
		var os_key := _os_key()
		var classifier_key := String(natives_map.get(os_key, ""))
		if classifier_key.is_empty():
			continue
		# 部分版本写成 natives-windows-${arch}
		if classifier_key.contains("${arch}"):
			classifier_key = classifier_key.replace("${arch}", "64" if _is_64_bit() else "32")

		var classifiers: Dictionary = dl.get("classifiers", {})
		var native_file: Dictionary = classifiers.get(classifier_key, {})
		if native_file.is_empty():
			continue

		var native_rel := String(native_file.get("path", ""))
		if native_rel.is_empty():
			continue
		var zip_path := libraries_dir.path_join(native_rel)
		if not seen_paths.has(native_rel):
			seen_paths[native_rel] = true
			_add(
				String(native_file.get("url", "")),
				zip_path,
				int(native_file.get("size", 0)),
				String(native_file.get("sha1", "")),
				"library", "原生库"
			)

		var extract: Dictionary = lib.get("extract", {})
		var exclude: Array = extract.get("exclude", [])
		natives.append({
			"zip": zip_path,
			"dest": natives_dest,
			"exclude": exclude,
			"name": String(lib.get("name", "")),
		})


func _build_assets(host: Node, source: DownloadSource, data: Dictionary, assets_dir: String) -> void:
	var asset_index: Dictionary = data.get("assetIndex", {})
	if asset_index.is_empty():
		return
	asset_index_id = String(asset_index.get("id", ""))
	if asset_index_id.is_empty():
		asset_index_id = "legacy"
		return

	var idx_path := assets_dir.path_join("indexes").path_join(asset_index_id + ".json")
	var idx_url := String(asset_index.get("url", ""))
	if idx_url.is_empty():
		return

	var idx_res := await HttpUtil.fetch_json(host, source.resolve(idx_url), 60.0, 2)
	if not bool(idx_res.get("ok", false)):
		error = "获取资源索引失败：%s" % String(idx_res.get("error", "未知错误"))
		return
	var idx: Dictionary = idx_res["data"]

	# 索引文件本身也落盘（用已下载到的内容，省一次请求）
	_add_content(idx_path, JSON.stringify(idx, "\t"), "meta", "资源索引")

	var objects: Dictionary = idx.get("objects", {})
	var seen_hashes := {}
	for key in objects:
		var obj: Dictionary = objects[key]
		var hash := String(obj.get("hash", ""))
		if hash.length() < 4:
			continue
		if seen_hashes.has(hash):
			continue
		seen_hashes[hash] = true
		var prefix := hash.substr(0, 2)
		_add(
			DownloadSource.ASSET_OBJECT_PREFIX + prefix + "/" + hash,
			assets_dir.path_join("objects").path_join(prefix).path_join(hash),
			int(obj.get("size", 0)),
			hash,
			"asset", "资源文件"
		)


func _recount() -> void:
	total_bytes = 0
	for f in files:
		total_bytes += maxi(int(f.get("size", 0)), 0)


func _add(url: String, path: String, size: int, sha1: String, kind: String, label: String) -> void:
	if url.strip_edges().is_empty() or path.is_empty():
		return
	files.append({
		"url": url,
		"path": path,
		"size": size,
		"sha1": sha1,
		"kind": kind,
		"label": label,
	})


func _add_content(path: String, text: String, kind: String, label: String) -> void:
	files.append({
		"url": "",
		"path": path,
		"size": text.to_utf8_buffer().size(),
		"sha1": "",
		"kind": kind,
		"label": label,
		"content": text,
	})


# ---------------------------------------------------------------- 规则判定

static func _os_key() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "osx"
		"Linux":
			return "linux"
	return OS.get_name().to_lower()


static func _is_64_bit() -> bool:
	return Engine.get_architecture_name() != "x86"


## 官方的 rules：空数组表示全部允许；命中 disallow 立即否决；
## 命中 allow 才允许（若只有 disallow 规则，默认允许）。
static func _rules_allow(rules: Variant) -> bool:
	if rules == null:
		return true
	if typeof(rules) != TYPE_ARRAY:
		return true
	var arr: Array = rules
	if arr.is_empty():
		return true

	var allowed := false
	var has_allow := false
	for r in arr:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = r
		if String(rule.get("action", "allow")) == "allow":
			has_allow = true
		if not _rule_matches(rule):
			continue
		if String(rule.get("action", "allow")) == "disallow":
			return false
		allowed = true
	return allowed or not has_allow


static func _rule_matches(rule: Dictionary) -> bool:
	# 我们不支持 demo 模式 / 自定义分辨率等特性，带特性要求的规则一律视为不匹配
	if rule.has("features") and rule["features"] != null:
		return false

	var os_info: Variant = rule.get("os")
	if os_info == null or typeof(os_info) != TYPE_DICTIONARY:
		return true
	var osd: Dictionary = os_info

	if osd.has("name"):
		var want := String(osd["name"])
		if want != _os_key() and not (want == "osx" and _os_key() == "macos"):
			return false

	if osd.has("arch"):
		var want_arch := String(osd["arch"])
		var current := Engine.get_architecture_name()
		if want_arch == "x86" and current != "x86":
			return false
		if want_arch == "arm64" and current != "arm64":
			return false
	return true


# ---------------------------------------------------------------- 后续步骤

## 把所有原生库压缩包解压到 versions/<id>/natives。返回解压的文件数。
static func extract_natives(plan: InstallPlan) -> int:
	if plan == null:
		return 0
	var count := 0
	for n in plan.natives:
		var zip_path := String(n.get("zip", ""))
		if not FileAccess.file_exists(zip_path):
			continue
		var dest := String(n.get("dest", ""))
		if dest.is_empty():
			continue
		DirAccess.make_dir_recursive_absolute(dest)

		var reader := ZIPReader.new()
		if reader.open(zip_path) != OK:
			push_warning("无法读取原生库压缩包：%s" % zip_path)
			continue
		var exclude: Array = n.get("exclude", [])
		for entry in reader.get_files():
			if entry.ends_with("/"):
				continue
			if _excluded(entry, exclude):
				continue
			var buf := reader.read_file(entry)
			var out_path := dest.path_join(entry)
			DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
			var f := FileAccess.open(out_path, FileAccess.WRITE)
			if f == null:
				continue
			f.store_buffer(buf)
			f.close()
			count += 1
		reader.close()
	return count


static func _excluded(entry: String, exclude: Array) -> bool:
	for ex in exclude:
		var prefix := String(ex)
		if prefix.is_empty():
			continue
		if entry.begins_with(prefix):
			return true
	return false
