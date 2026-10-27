class_name JavaRuntime
extends RefCounted
## Java 运行时（OpenJDK）。
##
## 版权/授权说明
## ------------
## 这里用的是 Eclipse Temurin（OpenJDK 的一个开源发行版）。按 Adoptium 官方 FAQ：
##   "The Eclipse Temurin binaries are provided at no cost to you ... under the terms of
##    the GNU General Public License, version 2 with the Classpath Exception.
##    You may freely use, modify, and share the code."
## 也就是说 GPLv2 + Classpath Exception 允许自由使用与再分发。
##
## 不过本工程**不打包、不预置**任何 JRE：只在用户需要时，通过 Adoptium 官方下载 API
## 现取 zip（带 SHA-256 校验），解压到「游戏目录/runtime/」下。
## 这样既不涉及再分发，也保证用户拿到的是官方原版。
##
## 商标：「Java」「OpenJDK」是 Oracle 的商标，「Temurin」「Adoptium」是 Eclipse 基金会的商标，
## 本软件只在说明文字里做客观引用，不用它们做产品名或图标。

const API_LATEST := "https://api.adoptium.net/v3/assets/latest/%d/hotspot?os=%s&architecture=%s&image_type=jre"
const RUNTIME_DIR := "runtime"

## 国内镜像（清华 TUNA 同步的 Adoptium 目录），路径结构与文件名和官方发行包完全一致。
## 官方下载走 GitHub Releases，国内经常连不上，所以默认先试镜像、再回退官方。
const MIRROR_DEFAULT := "https://mirrors.tuna.tsinghua.edu.cn/Adoptium"

## 想用自己的镜像就设置这里（留空用默认镜像）
static var custom_mirror_base := ""

## 用户在设置里手动指定的 Java 主目录（留空表示没指定）
static var custom_home := ""

## 扫描结果字段：home / exe / major / version / source
var home := ""
var exe := ""
var major := 0
var version := ""
var source := ""


static func exe_name() -> String:
	return "java.exe" if OS.get_name() == "Windows" else "java"


static func os_key() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "mac"
		"Linux":
			return "linux"
	return "linux"


static func arch_key() -> String:
	match Engine.get_architecture_name():
		"x86_64":
			return "x64"
		"arm64":
			return "aarch64"
		"x86":
			return "x32"
	return "x64"


## 当前生效的镜像根地址（留空则用内置的国内镜像）
static func mirror_base() -> String:
	var base := custom_mirror_base.strip_edges().trim_suffix("/")
	if base.is_empty():
		return MIRROR_DEFAULT
	return base


## 按「镜像 → 官方」的顺序给出可尝试的下载地址
## prefer_official = true 时反过来（用户明确选了官方源）
static func candidate_links(pkg: Dictionary, required_major: int, prefer_official: bool) -> Array[String]:
	var mirror_urls: Array[String] = []
	var official_urls: Array[String] = []

	var name := String(pkg.get("name", ""))
	var mirror := mirror_base()
	if not mirror.is_empty() and not name.is_empty():
		# 镜像的目录结构：/{major}/jre/{arch}/{os}/{文件名}
		mirror_urls.append("%s/%d/jre/%s/%s/%s" % [mirror, required_major, arch_key(), os_key(), name])

	var official := String(pkg.get("link", ""))
	if not official.is_empty():
		official_urls.append(official)

	if prefer_official:
		return official_urls + mirror_urls
	return mirror_urls + official_urls


# ---------------------------------------------------------------- 扫描

## 扫一遍本机所有能找到的 Java，返回候选列表（按路径+主版本去重）。
## 只要这个 Java 能跑起来就行，不要求它装在游戏目录里——装在哪都算数。
## extra_runtime_root：用户自定义的 Java 安装位置（会优先扫）
static func scan(game_dir: String, extra_runtime_root := "") -> Array[Dictionary]:
	var found: Array[Dictionary] = []

	# 0) 用户自定义的 Java 安装位置
	if not extra_runtime_root.strip_edges().is_empty():
		_scan_container(found, extra_runtime_root, "自定义位置", 2)

	# 1) 游戏目录下的 runtime/（本软件下载的、别的启动器装的）
	if not game_dir.strip_edges().is_empty():
		_scan_container(found, game_dir.path_join(RUNTIME_DIR), "游戏目录", 2)

	# 2) 官方启动器放在 .minecraft/runtime 里的（用户可能没把游戏目录设成 .minecraft）
	var appdata := OS.get_environment("APPDATA")
	if not appdata.is_empty():
		var official_mc := appdata.replace("\\", "/").path_join(".minecraft")
		if official_mc.to_lower() != game_dir.to_lower():
			_scan_container(found, official_mc.path_join(RUNTIME_DIR), "官方启动器", 2)

	# 3) 手动指定的 Java（在设置里选过）
	if not custom_home.is_empty():
		_add_home(found, custom_home, "手动指定")

	# 4) JAVA_HOME
	_add_home(found, OS.get_environment("JAVA_HOME"), "JAVA_HOME")

	# 5) PATH 里的 java
	for dir in _path_dirs():
		if FileAccess.file_exists(dir.path_join(exe_name())):
			_add_home(found, dir.get_base_dir(), "PATH")

	# 6) 常见安装位置（含 IDE 自带 JRE、.jdks、scoop 等）
	for root in _common_roots():
		_scan_container(found, root, "系统安装", 2)
	for home_dir in _direct_homes():
		_add_home(found, home_dir, "系统安装")

	# 7) 全盘扫：D 盘、E 盘…盘根下名字像 java/jdk/工具目录的地方，最多下探 2 层
	_scan_drives(found)

	return _dedupe(found)


## 扫所有盘符根目录：只看名字像 Java / JDK / 开发工具 / Minecraft 的文件夹，最多下探 2 层，
## 并且有目录数上限，避免在超大磁盘上卡住。
static func _scan_drives(out: Array[Dictionary]) -> void:
	if OS.get_name() != "Windows":
		return
	var hints := ["java", "jdk", "jre", "jbr", "openjdk", "temurin", "zulu", "graal",
		"minecraft", "mc", "tool", "dev", "program", "soft", "game", "app"]
	var budget := 600   # 最多列 600 个目录就收手

	for letter in ["C", "D", "E", "F", "G", "H", "I", "J", "K"]:
		var root := "%s:/" % letter
		if not DirAccess.dir_exists_absolute(root):
			continue
		for child in _subdirs(root):
			budget -= 1
			if budget <= 0:
				return
			var name := child.get_file().to_lower()
			var relevant := false
			for h in hints:
				if name.contains(h):
					relevant = true
					break
			if not relevant:
				continue
			if _add_home(out, child, "全盘扫描"):
				continue
			for sub in _subdirs(child):
				budget -= 1
				if budget <= 0:
					return
				if _add_home(out, sub, "全盘扫描"):
					continue
				# 再下一层，例如 D:/tools/java/jdk-21
				for sub2 in _subdirs(sub):
					budget -= 1
					if budget <= 0:
						return
					if _add_home(out, sub2, "全盘扫描"):
						break


## 只在指定目录及其子目录里找 Java（供「检测这个目录」用）
static func scan_dir(path: String, depth := 2) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var p := path.replace("\\", "/").trim_suffix("/")
	if p.is_empty():
		return found
	if _add_home(found, p, "指定目录"):
		return _dedupe(found)
	for sub in _subdirs(p):
		if _add_home(found, sub, "指定目录"):
			continue
		if depth > 1:
			for sub2 in _subdirs(sub):
				if _add_home(found, sub2, "指定目录"):
					break
	return _dedupe(found)


## 手动指定一个 Java 主目录（也可传 bin 所在目录或 java 可执行文件路径）
static func set_custom_home(path: String) -> Dictionary:
	var p := path.replace("\\", "/").trim_suffix("/")
	if p.to_lower().ends_with("/java") or p.to_lower().ends_with("/java.exe"):
		p = p.get_base_dir()
	if p.get_file().to_lower() == "bin":
		p = p.get_base_dir()
	custom_home = p
	return from_home(p, "手动指定")


static func _add_home(out: Array[Dictionary], path: String, source_tag: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	var hit := from_home(path, source_tag)
	if hit.is_empty():
		return false
	out.append(hit)
	return true


## 扫一个「容器目录」：它下面的子目录可能是 JRE 主目录，也可能再套一层（jbr / jre / Contents/Home）
static func _scan_container(out: Array[Dictionary], root: String, source_tag: String, depth: int) -> void:
	if root.strip_edges().is_empty():
		return
	for dir in _subdirs(root):
		if _add_home(out, dir, source_tag):
			continue
		var nested := false
		for sub in ["jbr", "jre", "Contents/Home", "Contents/Home/jre"]:
			if _add_home(out, dir.path_join(sub), source_tag):
				nested = true
				break
		if nested or depth <= 0:
			continue
		_scan_container(out, dir, source_tag, depth - 1)


static func _path_dirs() -> Array[String]:
	var out: Array[String] = []
	var sep := ";" if OS.get_name() == "Windows" else ":"
	for entry in OS.get_environment("PATH").split(sep, false):
		var d := entry.strip_edges().replace("\\", "/").trim_suffix("/")
		if not d.is_empty():
			out.append(d)
	return out


## 从某个 Java 主目录读出版本信息；不是有效 JRE 就返回空字典
static func from_home(home_dir: String, source_tag: String) -> Dictionary:
	if home_dir.strip_edges().is_empty():
		return {}
	var h := home_dir.replace("\\", "/").trim_suffix("/")
	var java_exe := h.path_join("bin").path_join(exe_name())
	if not FileAccess.file_exists(java_exe):
		return {}

	var ver := ""
	var release := h.path_join("release")
	if FileAccess.file_exists(release):
		var f := FileAccess.open(release, FileAccess.READ)
		if f != null:
			while not f.eof_reached():
				var line := f.get_line()
				if line.begins_with("JAVA_VERSION="):
					ver = line.split("=", true, 1)[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
					break
			f.close()

	var major := version_to_major(ver)
	if major <= 0:
		# 读不到 release 就从目录名猜，例如 jdk-21.0.2+13-jre / jdk8u392
		var re := RegEx.new()
		re.compile("(\\d+)")
		var best := ""
		for m in re.search_all(h.get_file()):
			var num := m.get_string(1)
			if num.length() > 0 and num.length() <= 2 and (best.is_empty() or num.length() > best.length()):
				best = num
		major = int(best)

	# 连目录名都猜不出来，就真的跑一次 java -version 兜底（最可靠，也最慢）
	if major <= 0:
		major = _major_from_exec(java_exe)
		if ver.is_empty() and major > 0:
			ver = "Java %d" % major

	return {
		"home": h,
		"exe": java_exe,
		"major": major,
		"version": ver,
		"source": source_tag,
	}


## 直接执行 java -version 读取版本（输出在 stderr 里，所以 read_stderr = true）
static func _major_from_exec(java_exe: String) -> int:
	if not FileAccess.file_exists(java_exe):
		return 0
	var out: Array = []
	var code := OS.execute(java_exe, ["-version"], out, true)
	if out.is_empty():
		return 0
	var text := "\n".join(out)
	var re := RegEx.new()
	re.compile("version \"([0-9][^\"]*)\"")
	var m := re.search(text)
	if m == null:
		return 0
	return version_to_major(m.get_string(1))


## "21.0.12" → 21；"1.8.0_392" → 8
static func version_to_major(ver: String) -> int:
	if ver.strip_edges().is_empty():
		return 0
	var v := ver.strip_edges()
	if v.begins_with("1."):
		return int(v.substr(2).split(".")[0])
	return int(v.split(".")[0])


## 从候选里挑一个能跑 required_major 的：优先完全一致，其次是最接近的更高版本
static func pick(candidates: Array, required_major: int) -> Dictionary:
	var exact := {}
	var higher := {}
	for c in candidates:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cand: Dictionary = c
		var major := int(cand.get("major", 0))
		if major <= 0:
			continue
		if required_major <= 0 or major == required_major:
			if exact.is_empty() or major > int(exact.get("major", 0)):
				exact = cand
		elif major > required_major:
			if higher.is_empty() or major < int(higher.get("major", 0)):
				higher = cand
	if not exact.is_empty():
		return exact
	return higher


static func _subdirs(path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			out.append(path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	return out


static func _common_roots() -> Array[String]:
	var roots: Array[String] = []
	var user_home := OS.get_environment("USERPROFILE")
	if user_home.is_empty():
		user_home = OS.get_environment("HOME")
	user_home = user_home.replace("\\", "/")

	if OS.get_name() == "Windows":
		roots.append("C:/Program Files/Java")
		roots.append("C:/Program Files/Eclipse Adoptium")
		roots.append("C:/Program Files/Zulu")
		roots.append("C:/Program Files/BellSoft")
		roots.append("C:/Program Files/Amazon Corretto")
		roots.append("C:/Program Files/IBM")
		roots.append("C:/Program Files/SapMachine")
		roots.append("C:/Program Files/Microsoft")
		roots.append("C:/Program Files/JetBrains")       # IDE 自带的 jbr
		roots.append("C:/Program Files/Common Files/Oracle/Java")
		var local := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
		if not local.is_empty():
			roots.append(local.path_join("Programs/Eclipse Adoptium"))
			roots.append(local.path_join("Programs/Zulu"))
			roots.append(local.path_join("Programs/JetBrains"))     # Toolbox 里的 jbr
			roots.append(local.path_join("JetBrains/Toolbox/apps"))
		if not user_home.is_empty():
			roots.append(user_home.path_join(".jdks"))              # IDEA 下载的 JDK
			roots.append(user_home.path_join("scoop/apps"))
			roots.append(user_home.path_join(".gradle/jdks"))
	elif OS.get_name() == "Linux":
		roots.append("/usr/lib/jvm")
		roots.append("/usr/java")
		roots.append("/opt/java")
		roots.append("/opt/jdk")
		roots.append("/opt")
		if not user_home.is_empty():
			roots.append(user_home.path_join(".sdkman/candidates/java"))
			roots.append(user_home.path_join(".jdks"))
	else:
		roots.append("/Library/Java/JavaVirtualMachines")
		if not user_home.is_empty():
			roots.append(user_home.path_join("Library/Java/JavaVirtualMachines"))
	return roots


## 本身就是 JRE 主目录的位置（不需要再往下找）
static func _direct_homes() -> Array[String]:
	var homes: Array[String] = []
	if OS.get_name() == "Windows":
		homes.append("C:/Program Files/Android/Android Studio/jbr")
		homes.append("C:/Program Files/JetBrains/Toolbox/apps")
	var user_home := OS.get_environment("USERPROFILE").replace("\\", "/")
	if not user_home.is_empty():
		homes.append(user_home.path_join("AppData/Local/Programs/Android Studio/jbr"))
		homes.append(user_home.path_join("AppData/Local/JetBrains/Toolbox/apps"))
	return homes


static func _dedupe(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for item in list:
		var key := "%s|%d" % [String(item.get("home", "")).to_lower(), int(item.get("major", 0))]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(item)
	return out


# ---------------------------------------------------------------- 下载安装

## 查 Adoptium 官方 API，拿到对应主版本的 JRE 包信息
static func fetch_package(host: Node, required_major: int) -> Dictionary:
	var url := API_LATEST % [required_major, os_key(), arch_key()]
	var res := await HttpUtil.fetch_json_any(host, url, 30.0, 2)
	if not bool(res.get("ok", false)):
		return {"ok": false, "error": "获取 Java 下载信息失败：%s" % String(res.get("error", "未知错误"))}

	var raw: Variant = res["data"]
	var entries: Array = raw if typeof(raw) == TYPE_ARRAY else [raw]
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = e
		var binary: Dictionary = entry.get("binary", {})
		var pkg: Dictionary = binary.get("package", {})
		var link := String(pkg.get("link", ""))
		if link.is_empty():
			continue
		var ver_info: Dictionary = entry.get("version", {})
		return {
			"ok": true,
			"link": link,
			"sha256": String(pkg.get("checksum", "")).to_lower(),
			"size": int(pkg.get("size", 0)),
			"name": String(pkg.get("name", "")),
			"major": int(ver_info.get("major", required_major)),
			"openjdk_version": String(ver_info.get("openjdk_version", "")),
		}
	return {"ok": false, "error": "官方接口没有返回可用的 JRE 包"}


## 下载并解压到 <runtime_root>/temurin-<major>/
## runtime_root 由调用方决定（默认是「游戏目录/runtime」，也可以在设置里改成别处）
## on_progress: func(text: String, fraction: float)
## prefer_official: 是否优先走官方 GitHub 下载（默认走国内镜像，失败再回退官方）
static func install(host: Node, runtime_root: String, required_major: int, on_progress: Callable, prefer_official := false) -> Dictionary:
	if runtime_root.strip_edges().is_empty():
		return {"ok": false, "error": "没有指定 Java 安装位置"}
	var dest := runtime_root.path_join("temurin-%d" % required_major)

	# 已经装过就直接复用
	var existing := from_home(dest, "自动下载")
	if not existing.is_empty():
		return {"ok": true, "home": existing.home, "exe": existing.exe, "major": existing.major, "version": existing.version}

	var pkg := await fetch_package(host, required_major)
	if not bool(pkg.get("ok", false)):
		return {"ok": false, "error": String(pkg.get("error", "未知错误"))}

	DirAccess.make_dir_recursive_absolute(runtime_root)
	var zip_path := runtime_root.path_join("temurin-%d.zip" % required_major)

	var links := candidate_links(pkg, required_major, prefer_official)
	if links.is_empty():
		return {"ok": false, "error": "没有可用的 Java 下载地址"}

	var want_sha := String(pkg.get("sha256", ""))
	var size := int(pkg.get("size", 0))
	var errors: Array[String] = []
	var got_file := false

	for link in links:
		var host_name := String(link).get_slice("/", 2)
		var tag := "官方" if host_name.contains("github") else "镜像"
		if FileAccess.file_exists(zip_path):
			DirAccess.remove_absolute(zip_path)

		on_progress.call("正在下载 Java %d 运行时（%s，约 %s）…" % [required_major, tag, _mb(size)], 0.02)
		var dl := await _download_file(host, link, zip_path, size, on_progress)
		if not bool(dl.get("ok", false)):
			errors.append("%s：%s" % [tag, String(dl.get("error", "下载失败"))])
			continue

		on_progress.call("正在校验 Java 安装包…", 0.6)
		if want_sha.length() == 64 and sha256_of_file(zip_path) != want_sha:
			DirAccess.remove_absolute(zip_path)
			errors.append("%s：安装包校验失败（SHA-256 不一致）" % tag)
			continue

		got_file = true
		break

	if not got_file:
		return {"ok": false, "error": "；".join(errors)}

	on_progress.call("正在解压 Java 运行时…", 0.65)
	var err := await _extract_zip(host, zip_path, dest, on_progress)
	if FileAccess.file_exists(zip_path):
		DirAccess.remove_absolute(zip_path)
	if not err.is_empty():
		return {"ok": false, "error": err}

	var hit := from_home(dest, "自动下载")
	if hit.is_empty():
		return {"ok": false, "error": "解压后没有找到 java 可执行文件"}

	on_progress.call("Java %s 已就绪" % String(hit.get("version", "")), 1.0)
	return {"ok": true, "home": hit.home, "exe": hit.exe, "major": hit.major, "version": hit.version}


static func _download_file(host: Node, url: String, path: String, expected_size: int, on_progress: Callable) -> Dictionary:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var http := HTTPRequest.new()
	http.timeout = 0.0
	http.use_threads = true
	http.max_redirects = 8
	http.download_file = path
	host.add_child(http)

	var err := http.request(url, PackedStringArray(["User-Agent: " + HttpUtil.USER_AGENT]))
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
		if expected_size > 0:
			var got := int(http.get_downloaded_bytes())
			var ratio := clampf(float(got) / float(expected_size), 0.0, 1.0)
			# 每 5% 汇报一次就够了，别每帧都刷界面
			var bucket := int(ratio * 20.0)
			if bucket != last_bucket:
				last_bucket = bucket
				on_progress.call("正在下载 Java 运行时… %d%%" % int(ratio * 100.0), 0.02 + 0.55 * ratio)
		await host.get_tree().process_frame

	var result := int(state["result"])
	var code := int(state["code"])
	if is_instance_valid(http):
		http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 206):
		return {"ok": false, "error": HttpUtil.describe_error(result, code)}
	return {"ok": true}


static func _extract_zip(host: Node, zip_path: String, dest: String, on_progress: Callable) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return "无法读取 Java 压缩包"

	var entries := reader.get_files()
	# Temurin 的 zip 里所有文件都在同一个顶层目录下，解压时剥掉它
	var prefix := ""
	if not entries.is_empty():
		var first := String(entries[0])
		var slash := first.find("/")
		if slash > 0:
			var candidate := first.substr(0, slash) + "/"
			var all_same := true
			for e in entries:
				if not String(e).begins_with(candidate):
					all_same = false
					break
			if all_same:
				prefix = candidate

	DirAccess.make_dir_recursive_absolute(dest)
	var total := maxi(entries.size(), 1)
	var index := 0
	for entry in entries:
		index += 1
		var name := String(entry)
		if name.ends_with("/"):
			continue
		var rel := name
		if not prefix.is_empty():
			rel = rel.substr(prefix.length())
		if rel.is_empty() or rel.contains(".."):
			continue
		var out_path := dest.path_join(rel)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var buf := reader.read_file(name)
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			reader.close()
			return "无法写入文件：%s" % out_path
		f.store_buffer(buf)
		f.close()
		if index % 40 == 0:
			on_progress.call("正在解压 Java 运行时…", 0.65 + 0.33 * float(index) / float(total))
			await host.get_tree().process_frame

	reader.close()
	return ""


static func sha256_of_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		var chunk := f.get_buffer(65536)
		if chunk.is_empty():
			break
		ctx.update(chunk)
	f.close()
	return ctx.finish().hex_encode()


static func _mb(bytes: int) -> String:
	if bytes <= 0:
		return "未知大小"
	return "%.0f MB" % (float(bytes) / 1048576.0)
