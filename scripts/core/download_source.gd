class_name DownloadSource
extends RefCounted
## 下载源描述。
##
## 官方源直接用官方的地址；镜像源（BMCLAPI）则把官方域名整体替换成镜像域名。
## 所以「计划阶段」永远只生成官方 URL，真正发请求前用 resolve() 做一次改写，
## 这样一个计划可以被任意下载源复用。

const ID_AUTO := "auto"
const ID_OFFICIAL := "official"
const ID_BMCLAPI := "bmclapi"

const MANIFEST_OFFICIAL := "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
const MIRROR_DEFAULT := "https://bmclapi2.bangbang93.com"
const MANIFEST_BMCLAPI := MIRROR_DEFAULT + "/mc/game/version_manifest_v2.json"

const ASSET_OBJECT_PREFIX := "https://resources.download.minecraft.net/"

## 自定义镜像根地址（在「下载设置」里填）。留空则使用 BMCLAPI 默认地址。
## 自定义镜像必须遵循 BMCLAPI 的路径布局：/mc、/v1、/assets、/maven。
static var custom_mirror_base := ""

var id: String = ID_OFFICIAL
var display_name: String = "官方源"
var manifest_url: String = MANIFEST_OFFICIAL
## 测速用的地址：用版本清单本身（几百 KB，足够反映线路质量）
var probe_url: String = MANIFEST_OFFICIAL

## 该镜像是不是用户在设置里自己填的
var is_custom := false
## [官方前缀, 镜像前缀]，按顺序匹配
var _rewrite: Array = []


## 当前生效的镜像根地址（去掉末尾斜杠，缺协议时补 https://）
static func mirror_base() -> String:
	var base := custom_mirror_base.strip_edges().trim_suffix("/")
	if base.is_empty():
		return MIRROR_DEFAULT
	if not base.begins_with("http://") and not base.begins_with("https://"):
		base = "https://" + base
	return base


static func create(source_id: String) -> DownloadSource:
	var s := DownloadSource.new()
	if source_id == ID_BMCLAPI:
		var base := mirror_base()
		s.id = ID_BMCLAPI
		s.is_custom = base != MIRROR_DEFAULT
		s.display_name = "自定义镜像" if s.is_custom else "BMCLAPI 镜像"
		s.manifest_url = base + "/mc/game/version_manifest_v2.json"
		s.probe_url = s.manifest_url
		s._rewrite = [
			# 资源文件单独放在 /assets 下
			["https://resources.download.minecraft.net", base + "/assets"],
			# 依赖库走 /maven
			["https://libraries.minecraft.net", base + "/maven"],
			# 元数据：路径本身就带 /mc 或 /v1 前缀，直接拼接即可
			["https://launchermeta.mojang.com", base],
			["https://piston-meta.mojang.com", base],
			["https://piston-data.mojang.com", base],
			["https://launcher.mojang.com", base],
		]
	return s


func is_mirror() -> bool:
	return id != ID_OFFICIAL


## 把官方 URL 改写成当前源可用的 URL（官方源原样返回）
func resolve(url: String) -> String:
	if _rewrite.is_empty() or url.is_empty():
		return url
	for rule in _rewrite:
		var from: String = rule[0]
		if url.begins_with(from):
			return String(rule[1]) + url.substr(from.length())
	return url


## 同时测两个源的速，返回每个源的结果数组：
## [{id, name, ok, seconds, bytes, speed, error}]
## 两个探测请求是并发发出的，所以总耗时约等于较慢的那一个。
static func measure_all(host: Node, sources: Array, timeout: float = 20.0) -> Array:
	var fired: Array = []
	for s in sources:
		var src: DownloadSource = s
		var http := HTTPRequest.new()
		http.timeout = timeout
		http.use_threads = true
		http.max_redirects = 8
		host.add_child(http)
		var started := Time.get_ticks_usec()
		var err := http.request(src.probe_url, PackedStringArray(["User-Agent: " + HttpUtil.USER_AGENT]))
		if err != OK:
			http.queue_free()
			fired.append({"node": null, "source": src, "start": started})
		else:
			fired.append({"node": http, "source": src, "start": started})

	var out: Array = []
	for item in fired:
		var src: DownloadSource = item["source"]
		var http: Variant = item["node"]
		if http == null:
			out.append({
				"id": src.id, "name": src.display_name, "ok": false,
				"seconds": 0.0, "bytes": 0, "speed": 0.0, "error": "无法发起请求",
			})
			continue
		var resp: Array = await (http as HTTPRequest).request_completed
		var seconds := float(Time.get_ticks_usec() - int(item["start"])) / 1000000.0
		(http as HTTPRequest).queue_free()
		var result := int(resp[0])
		var code := int(resp[1])
		var body: PackedByteArray = resp[3]
		var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
		var bytes := body.size()
		out.append({
			"id": src.id,
			"name": src.display_name,
			"ok": ok,
			"seconds": seconds,
			"bytes": bytes,
			"speed": (float(bytes) / maxf(seconds, 0.001)) if ok else 0.0,
			"error": "" if ok else HttpUtil.describe_error(result, code),
		})
	return out
