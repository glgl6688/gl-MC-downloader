class_name Modrinth
extends RefCounted
## Modrinth 开放 API 客户端（模组 / 整合包）。
##
## 授权：Modrinth 官方文档允许第三方客户端调用其公开 API，要求带上能识别应用的
## User-Agent、不要高频刷接口（官方限制约 300 次/分钟）。所有内容（模组、整合包）
## 都由 Modrinth 的 CDN 直接分发，本软件不缓存、不打包、不再分发任何文件。
##
## 支持自定义镜像根地址（设置里填），方便走自建反代。

const BASE_DEFAULT := "https://api.modrinth.com/v2"
const PROBE_PATH := "/search?limit=1"
const USER_AGENT := "gl-downloader/0.3 (Godot)"

static var custom_base := ""
## 0 = 只搜名称（本地过滤标题）；1 = 名称+简介（接口默认）；2 = 翻译后搜索
static var search_mode := 1


static func base_url() -> String:
	var b := custom_base.strip_edges().trim_suffix("/")
	return b if not b.is_empty() else BASE_DEFAULT


static func is_custom() -> bool:
	return not custom_base.strip_edges().is_empty()


# ---------------------------------------------------------------- 搜索

## 返回 {ok, hits: Array, total: int, error}
static func search(host: Node, query: String, project_type: String, loader: String, index: String, limit := 30, offset := 0, category := "", game_version := "") -> Dictionary:
	var facets: Array = [["project_type:%s" % project_type]]
	if not loader.is_empty() and loader != "all":
		facets.append(["categories:%s" % loader])
	if not category.is_empty():
		facets.append(["categories:%s" % category])
	if not game_version.is_empty():
		facets.append(["versions:%s" % game_version])
	var path := "/search?query=%s&limit=%d&offset=%d&index=%s&facets=%s" % [
		query.uri_encode(), limit, offset, index, JSON.stringify(facets).uri_encode(),
	]
	var res := await HttpUtil.fetch_json(host, base_url() + path, 25.0, 1, USER_AGENT)
	if not bool(res.get("ok", false)):
		return {"ok": false, "hits": [], "total": 0, "error": String(res.get("error", "未知错误"))}
	var data: Dictionary = res["data"]
	return {
		"ok": true,
		"hits": data.get("hits", []),
		"total": int(data.get("total_hits", 0)),
		"error": "",
	}


## 某个项目可用的版本列表（可按游戏版本 / 加载器过滤）
static func versions(host: Node, project_id: String, game_version := "", loader := "") -> Array:
	var path := "/project/%s/version" % project_id
	var params: Array[String] = []
	if not game_version.is_empty():
		params.append("game_versions=%s" % JSON.stringify([game_version]).uri_encode())
	if not loader.is_empty():
		params.append("loaders=%s" % JSON.stringify([loader]).uri_encode())
	if not params.is_empty():
		path += "?" + "&".join(params)

	var res := await HttpUtil.fetch_json_any(host, base_url() + path, 25.0, 1, USER_AGENT)
	if not bool(res.get("ok", false)):
		return []
	var raw: Variant = res["data"]
	return raw if typeof(raw) == TYPE_ARRAY else []


## 取「主文件」信息：{url, filename, size, sha1, version_name, game_versions, loaders}
static func primary_file(version: Dictionary) -> Dictionary:
	var files: Array = version.get("files", [])
	var chosen: Dictionary = {}
	for f in files:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var file: Dictionary = f
		if bool(file.get("primary", false)):
			chosen = file
			break
	if chosen.is_empty() and not files.is_empty():
		chosen = files[0]
	if chosen.is_empty():
		return {}
	var hashes: Dictionary = chosen.get("hashes", {})
	return {
		"url": String(chosen.get("url", "")),
		"filename": String(chosen.get("filename", "")),
		"size": int(chosen.get("size", 0)),
		"sha1": String(hashes.get("sha1", "")).to_lower(),
		"version_name": String(version.get("version_number", "")),
		"name": String(version.get("name", "")),
		"game_versions": version.get("game_versions", []),
		"loaders": version.get("loaders", []),
	}


## 下载到目录（保留原文件名）。返回 {ok, path, error}
static func download_version_file(host: Node, version: Dictionary, target_dir: String, on_progress := Callable()) -> Dictionary:
	var f := primary_file(version)
	if f.is_empty() or String(f.get("url", "")).is_empty():
		return {"ok": false, "path": "", "error": "这个版本没有可下载的文件"}
	DirAccess.make_dir_recursive_absolute(target_dir)
	var path := target_dir.path_join(String(f.get("filename", "download.jar")))
	var dl := await HttpUtil.download_file(host, String(f.get("url", "")), path, int(f.get("size", 0)), on_progress, USER_AGENT)
	if not bool(dl.get("ok", false)):
		return {"ok": false, "path": "", "error": String(dl.get("error", "下载失败"))}
	return {"ok": true, "path": path, "error": ""}


## 测速：拉一次最小的搜索请求
static func probe(host: Node) -> Dictionary:
	var started := Time.get_ticks_usec()
	var res := await HttpUtil.fetch_json(host, base_url() + PROBE_PATH, 12.0, 0, USER_AGENT)
	var seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	if not bool(res.get("ok", false)):
		return {"ok": false, "seconds": seconds, "error": String(res.get("error", "失败"))}
	return {"ok": true, "seconds": seconds, "error": ""}


# ---------------------------------------------------------------- Fabric API

## 找 Fabric API 对应版本（大部分 Fabric 模组都依赖它）
static func fabric_api_version(host: Node, game_version: String) -> Dictionary:
	var list := await versions(host, "fabric-api", game_version, "fabric")
	if list.is_empty():
		# 有些版本号写法不一致，放宽一次
		list = await versions(host, "fabric-api", "", "fabric")
	if list.is_empty():
		return {}
	return list[0]

# ---------------------------------------------------------------- 依赖解析

## 递归解析「必需」依赖。返回需要一起下载的版本对象数组（已去重）。
static func resolve_dependencies(host: Node, version: Dictionary, game_version: String, loader: String, seen: Dictionary = {}) -> Array:
	var out: Array = []
	var deps: Array = version.get("dependencies", [])
	for d in deps:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var dep: Dictionary = d
		if String(dep.get("dependency_type", "")) != "required":
			continue
		var pid := String(dep.get("project_id", ""))
		if pid.is_empty() or seen.has(pid):
			continue
		seen[pid] = true
		var list := await versions(host, pid, game_version, loader)
		if list.is_empty():
			continue
		var picked: Dictionary = list[0]
		out.append(picked)
		out.append_array(await resolve_dependencies(host, picked, game_version, loader, seen))
	return out


## 下载一组版本文件到同一个目录，返回 {ok, paths, failed}
static func download_versions(host: Node, list: Array, target_dir: String, on_progress := Callable()) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(target_dir)
	var paths: Array[String] = []
	var failed: Array[String] = []
	var total := maxi(list.size(), 1)
	for i in list.size():
		if typeof(list[i]) != TYPE_DICTIONARY:
			continue
		var v: Dictionary = list[i]
		var label := String(v.get("name", v.get("version_number", "文件")))
		if on_progress.is_valid():
			on_progress.call("正在下载 %s（%d/%d）…" % [label, i + 1, total], float(i) / float(total))
		var res := await download_version_file(host, v, target_dir)
		if bool(res.get("ok", false)):
			paths.append(String(res.get("path", "")))
		else:
			failed.append(label)
	if on_progress.is_valid():
		on_progress.call("下载完成", 1.0)
	return {"ok": failed.is_empty(), "paths": paths, "failed": failed}

## 中文 → 英文（免费接口，失败了就原样返回）
static func translate_to_english(host: Node, text: String) -> String:
	var q := text.strip_edges()
	if q.is_empty():
		return ""
	if q.is_valid_ascii_identifier() or _is_ascii(q):
		return q
	var url := "https://api.mymemory.translated.net/get?q=%s&langpair=zh-CN%%7Cen" % q.uri_encode()
	var res := await HttpUtil.fetch_json(host, url, 12.0, 0)
	if not bool(res.get("ok", false)):
		return q
	var data: Dictionary = res["data"]
	var rd: Dictionary = data.get("responseData", {})
	var out := String(rd.get("translatedText", "")).strip_edges()
	return out if not out.is_empty() else q


static func _is_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) > 127:
			return false
	return true