class_name McVersion
extends RefCounted
## 版本清单里的一条记录。

const TYPE_LABELS := {
	"release": "正式版",
	"snapshot": "快照",
	"old_beta": "远古 Beta",
	"old_alpha": "远古 Alpha",
	"pending": "待发布",
}

## 愚人节版本的 id。清单里它们和普通快照一样标成 snapshot，没有专门字段，
## 所以只能靠 id 名单 + 发布日期兜底来识别。
## 这份名单是按官方清单里「4 月 1 日发布」的条目核对出来的，新版本出来后加一行即可。
const APRIL_FOOLS_IDS := [
	"15w14a",               # 2015 爱的抱抱
	"1.RV-Pre1",            # 2016 时尚更新
	"3D Shareware v1.34",   # 2019 3D 共享软件
	"20w14infinite",        # 2020 无限维度
	"22w13oneblockatatime", # 2022 一个方块
	"23w13a_or_b",          # 2023 投票更新
	"24w14potato",          # 2024 毒马铃薯
	"25w14craftmine",       # 2025 合成我的世界
]

var id := ""
var type := ""
var url := ""
var sha1 := ""
## 形如 "2024-12-03T08:19:06+00:00"
var release_time := ""


static func from_dict(d: Dictionary) -> McVersion:
	var v := McVersion.new()
	v.id = String(d.get("id", ""))
	v.type = String(d.get("type", ""))
	v.url = String(d.get("url", ""))
	v.sha1 = String(d.get("sha1", ""))
	v.release_time = String(d.get("releaseTime", d.get("time", "")))
	return v


func type_label() -> String:
	return String(TYPE_LABELS.get(type, type if type != "" else "未知"))


## 列表里显示的类别：愚人节版本优先显示成「愚人节」
func display_type_label() -> String:
	if is_april_fools():
		return "愚人节"
	return type_label()


func is_release() -> bool:
	return type == "release"


func is_old() -> bool:
	return type == "old_beta" or type == "old_alpha"


## 是不是愚人节版本。
## 1) 先查上面的 id 名单；
## 2) 兜底：快照且发布日期是 4 月 1 日、且不是 rc / pre（未来年份没来得及加名单时也能认出来）。
func is_april_fools() -> bool:
	if id in APRIL_FOOLS_IDS:
		return true
	if type != "snapshot":
		return false
	if release_date().substr(5) != "04-01":
		return false
	var lowered := id.to_lower()
	if lowered.contains("pre") or lowered.contains("rc"):
		return false
	return true


## "2024-12-03"
func release_date() -> String:
	if release_time.length() >= 10:
		return release_time.substr(0, 10)
	return release_time
