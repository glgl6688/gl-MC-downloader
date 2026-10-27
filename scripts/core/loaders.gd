class_name McLoaders
extends RefCounted
## 模组加载器安装：Fabric / Quilt / Forge
##
## Fabric / Quilt：官方 meta 接口直接给一份带 inheritsFrom 的版本 JSON，
## 保存到 versions/<id>/<id>.json 后，按普通版本走安装流程即可。
##
## Forge：官方只提供安装器 jar，安装过程包含大量 processor 步骤；
## 这里直接调用官方安装器（`--installClient`），装完再从 versions/ 里读结果。

const FABRIC_LOADERS := "https://meta.fabricmc.net/v2/versions/loader"
const FABRIC_MIRROR := "https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader"
const FABRIC_PROFILE := "https://meta.fabricmc.net/v2/versions/loader/%s/%s/profile/json"
const QUILT_LOADERS := "https://meta.quiltmc.org/v3/versions/loader"
const QUILT_PROFILE := "https://meta.quiltmc.org/v3/versions/loader/%s/%s/profile/json"
const FORGE_PROMOS := "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json"
const FORGE_INSTALLER := "https://maven.minecraftforge.net/net/minecraftforge/forge/%s-%s/forge-%s-%s-installer.jar"
const NEOFORGE_META := "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml"
const NEOFORGE_INSTALLER := "https://maven.neoforged.net/releases/net/neoforged/neoforge/%s/neoforge-%s-installer.jar"


## Fabric 加载器版本列表：[{version, stable}]
static func fabric_loader_versions(host: Node) -> Array:
	# 官方 meta 拉不到就换 BMCLAPI 的 fabric-meta 镜像
	var res := await HttpUtil.fetch_json_any(host, FABRIC_LOADERS, 20.0, 1)
	if not bool(res.get("ok", false)):
		res = await HttpUtil.fetch_json_any(host, FABRIC_MIRROR, 20.0, 1)
	if not bool(res.get("ok", false)):
		return []
	var out: Array = []
	var raw: Variant = res["data"]
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		out.append({
			"version": String(d.get("version", "")),
			"stable": bool(d.get("stable", false)),
		})
	return out


## Quilt 加载器版本列表
static func quilt_loader_versions(host: Node) -> Array:
	var res := await HttpUtil.fetch_json_any(host, QUILT_LOADERS, 20.0, 1)
	if not bool(res.get("ok", false)):
		return []
	var out: Array = []
	var raw: Variant = res["data"]
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		out.append({
			"version": String(d.get("version", "")),
			"stable": bool(d.get("stable", false)),
		})
	return out


## 安装 Fabric / Quilt：只写版本 JSON，依赖库交给后续安装计划
static func install_fabric_like(host: Node, source: DownloadSource, mc_id: String, loader: String, game_dir: String, kind: String, on_progress: Callable) -> Dictionary:
	var url := (QUILT_PROFILE if kind == "quilt" else FABRIC_PROFILE) % [mc_id, loader]
	on_progress.call("正在获取 %s 版本信息…" % kind.capitalize(), 0.1)
	var res := await HttpUtil.fetch_json(host, source.resolve(url), 30.0, 2)
	if not bool(res.get("ok", false)) and kind != "quilt":
		# Fabric 走镜像再试一次
		var mirror_url := FABRIC_MIRROR + ("/%s/%s/profile/json" % [mc_id, loader])
		res = await HttpUtil.fetch_json(host, mirror_url, 30.0, 1)
	if not bool(res.get("ok", false)):
		return {"ok": false, "error": "获取加载器版本失败：%s" % String(res.get("error", "未知错误"))}

	var data: Dictionary = res["data"]
	var id := String(data.get("id", ""))
	if id.is_empty():
		return {"ok": false, "error": "加载器返回的数据里没有版本 id"}

	var dir := game_dir.path_join("versions").path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(id + ".json"), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "无法写入版本 JSON"}
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return {"ok": true, "id": id}


## Forge 可用版本：{"1.20.1-latest": "47.2.0", ...}
static func forge_promotions(host: Node) -> Dictionary:
	var res := await HttpUtil.fetch_json(host, FORGE_PROMOS, 20.0, 1)
	if not bool(res.get("ok", false)):
		return {}
	var data: Dictionary = res["data"]
	var promos: Variant = data.get("promos", {})
	if typeof(promos) != TYPE_DICTIONARY:
		return {}
	return promos


## 某个 MC 版本推荐的 Forge 版本（recommended 优先，其次 latest）
static func forge_versions_for(promos: Dictionary, mc_id: String) -> Array:
	var out: Array = []
	for kind in ["recommended", "latest"]:
		var v := String(promos.get("%s-%s" % [mc_id, kind], ""))
		if not v.is_empty() and not out.has(v):
			out.append(v)
	return out


## 用官方安装器装 Forge（会创建 launcher_profiles.json，然后调用 java -jar ... --installClient）
static func install_forge(host: Node, java_exe: String, game_dir: String, mc_id: String, forge_version: String, on_progress: Callable) -> Dictionary:
	var id := "%s-forge-%s" % [mc_id, forge_version]
	var target_dir := game_dir.path_join("versions").path_join(id)
	if FileAccess.file_exists(target_dir.path_join(id + ".json")):
		return {"ok": true, "id": id}

	if java_exe.is_empty() or not FileAccess.file_exists(java_exe):
		return {"ok": false, "error": "没有可用的 Java，无法运行 Forge 安装器（先装个 Java）"}

	# 官方安装器要求游戏目录里有 launcher_profiles.json
	var profiles := game_dir.path_join("launcher_profiles.json")
	if not FileAccess.file_exists(profiles):
		var pf := FileAccess.open(profiles, FileAccess.WRITE)
		if pf != null:
			pf.store_string('{"profiles":{},"settings":{},"version":3}')
			pf.close()

	var installer := game_dir.path_join("forge-installer-%s.jar" % id)
	on_progress.call("正在下载 Forge 安装器…", 0.05)
	var dl := await HttpUtil.download_file(host, FORGE_INSTALLER % [mc_id, forge_version, mc_id, forge_version], installer, 0, on_progress)
	if not bool(dl.get("ok", false)):
		return {"ok": false, "error": "下载 Forge 安装器失败：%s" % String(dl.get("error", "未知错误"))}

	on_progress.call("正在运行 Forge 官方安装器（可能要几分钟）…", 0.2)
	var pid := OS.create_process(java_exe, ["-jar", installer, "--installClient", game_dir])
	if pid <= 0:
		return {"ok": false, "error": "无法启动 Java 进程运行 Forge 安装器"}

	var waited := 0.0
	while waited < 300.0:
		await host.get_tree().create_timer(1.0).timeout
		waited += 1.0
		if FileAccess.file_exists(target_dir.path_join(id + ".json")):
			if FileAccess.file_exists(installer):
				DirAccess.remove_absolute(installer)
			on_progress.call("Forge 安装完成", 1.0)
			return {"ok": true, "id": id}
		on_progress.call("正在运行 Forge 安装器… %d 秒" % int(waited), clampf(0.2 + waited / 300.0 * 0.75, 0.0, 0.95))

	return {
		"ok": false,
		"error": "Forge 安装器 5 分钟内没有结束。可以手动运行：%s" % installer,
	}

# ---------------------------------------------------------------- NeoForge

## 1.21.1 → "21.1."，1.20.4 → "20.4."
static func neoforge_prefix(mc_id: String) -> String:
	var parts := mc_id.split(".")
	if parts.size() < 2:
		return ""
	return "%s.%s." % [parts[1], parts[2] if parts.size() > 2 else "0"]


## NeoForge 版本列表（从 maven 的 maven-metadata.xml 里挑出对应 MC 版本的）
static func neoforge_versions(host: Node, mc_id: String) -> Array:
	var prefix := neoforge_prefix(mc_id)
	if prefix.is_empty():
		return []
	var res := await HttpUtil.fetch_bytes(host, NEOFORGE_META, 20.0, 1)
	if not bool(res.get("ok", false)):
		return []
	var text := (res["body"] as PackedByteArray).get_string_from_utf8()
	var re := RegEx.new()
	if re.compile("<version>([^<]+)</version>") != OK:
		return []
	var out: Array = []
	for m in re.search_all(text):
		var v := m.get_string(1)
		if v.begins_with(prefix):
			out.append(v)
	out.reverse()
	return out


## 用 NeoForge 官方安装器安装
static func install_neoforge(host: Node, java_exe: String, game_dir: String, mc_id: String, ver: String, on_progress: Callable) -> Dictionary:
	var id := "neoforge-%s" % ver
	var target := game_dir.path_join("versions").path_join(id)
	if FileAccess.file_exists(target.path_join(id + ".json")):
		return {"ok": true, "id": id}
	if java_exe.is_empty() or not FileAccess.file_exists(java_exe):
		return {"ok": false, "error": "没有可用的 Java，无法运行 NeoForge 安装器"}

	var profiles := game_dir.path_join("launcher_profiles.json")
	if not FileAccess.file_exists(profiles):
		var pf := FileAccess.open(profiles, FileAccess.WRITE)
		if pf != null:
			pf.store_string('{"profiles":{},"settings":{},"version":3}')
			pf.close()

	var installer := game_dir.path_join("neoforge-installer-%s.jar" % ver)
	on_progress.call("正在下载 NeoForge 安装器…", 0.05)
	var dl := await HttpUtil.download_file(host, NEOFORGE_INSTALLER % [ver, ver], installer, 0, on_progress)
	if not bool(dl.get("ok", false)):
		return {"ok": false, "error": "下载 NeoForge 安装器失败：%s" % String(dl.get("error", "未知错误"))}

	on_progress.call("正在运行 NeoForge 安装器…", 0.2)
	var pid := OS.create_process(java_exe, ["-jar", installer, "--installClient", game_dir])
	if pid <= 0:
		return {"ok": false, "error": "无法启动 Java 进程"}

	var waited := 0.0
	while waited < 300.0:
		await host.get_tree().create_timer(1.0).timeout
		waited += 1.0
		if FileAccess.file_exists(target.path_join(id + ".json")):
			if FileAccess.file_exists(installer):
				DirAccess.remove_absolute(installer)
			on_progress.call("NeoForge 安装完成", 1.0)
			return {"ok": true, "id": id}
		on_progress.call("正在运行 NeoForge 安装器… %d 秒" % int(waited), clampf(0.2 + waited / 300.0 * 0.75, 0.0, 0.95))
	return {"ok": false, "error": "NeoForge 安装器 5 分钟内没结束：%s" % installer}

## NeoForge 版本：官方源经常连不上，依次试多个入口
static func neoforge_versions_multi(host: Node, mc_id: String) -> Array:
	var prefix := neoforge_prefix(mc_id)
	var urls := [
		"https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge",
		"https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml",
	]
	for url in urls:
		var res := await HttpUtil.fetch_bytes(host, url, 25.0, 1)
		if not bool(res.get("ok", false)):
			continue
		var text := (res["body"] as PackedByteArray).get_string_from_utf8()
		var out: Array = []
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			for v in (parsed as Dictionary).get("versions", []):
				var s := String(v)
				if prefix.is_empty() or s.begins_with(prefix):
					out.append(s)
		if out.is_empty():
			var re := RegEx.new()
			re.compile("<version>([^<]+)</version>")
			for m in re.search_all(text):
				var s2 := m.get_string(1)
				if prefix.is_empty() or s2.begins_with(prefix):
					out.append(s2)
		if not out.is_empty():
			out.reverse()
			return out
	return []
