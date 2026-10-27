extends Control
## 下载页：版本选择 + 下载源（官方 / 镜像 / 自动测速）+ 安装目录 + 并发下载。
##
## 交互流程：
##   启动 → 读设置 → （自动模式则先测速）→ 拉版本清单 → 选版本 → 生成安装计划
##   点「开始下载」→ 下载队列跑起来 → 进度/速度实时刷新 → 完成后解压原生库
##
## 这一层只负责“界面与流程”，真正的网络与文件逻辑在 scripts/core 下。

const SETTINGS_PATH := "user://mc_downloader_settings.cfg"
const ERROR_LOG_PATH := "user://mc_downloader_errors.log"

const APP_NAME := "gl下载器"
## 页脚免责声明（改文案只改这里）
const DISCLAIMER := "第三方非官方工具，与官方无关"

## 下载设置默认值
const DEFAULT_CONCURRENCY := 16
const MIN_CONCURRENCY := 1
const MAX_CONCURRENCY := 64

## 窗口最小尺寸，防止缩到布局挤坏
const MIN_WINDOW_SIZE := Vector2i(900, 560)

## 设计基准尺寸（= 工程里的 viewport 大小），界面缩放的 100% 就是它
const BASE_SIZE := Vector2i(1180, 720)
## 界面缩放下拉项。0 = 跟着窗口自动等比放大；其余为在自动缩放之上再放大/缩小
const ZOOM_LABELS := ["自适应（跟随窗口）", "80%", "90%", "110%", "125%"]
const ZOOM_SCALES := [1.0, 0.8, 0.9, 1.1, 1.25]

## 下拉框顺序与 DownloadSource 的 id 对应
const SOURCE_IDS := [DownloadSource.ID_AUTO, DownloadSource.ID_OFFICIAL, DownloadSource.ID_BMCLAPI]
const SOURCE_LABELS := ["自动（测速择优）", "官方源", "BMCLAPI 镜像"]

## 版本筛选（顺序必须与 _match_filter 里的分支对应）
const FILTER_LABELS := ["全部版本", "正式版", "快照", "愚人节", "远古版本"]

## 版本排序方式
const SORT_LABELS := ["发布时间 ↓", "发布时间 ↑", "版本号 A→Z", "版本号 Z→A"]
const SORT_TOOLTIPS := ["最新的排在前面", "最旧的排在前面", "按版本号字符升序", "按版本号字符降序"]

@onready var _source_option: OptionButton = %SourceOption
@onready var _speed_button: Button = %SpeedTestButton
@onready var _source_status: Label = %SourceStatus
@onready var _settings_button: Button = %SettingsButton
@onready var _settings_popup: PopupPanel = %SettingsPopup
@onready var _settings_close_button: Button = %SettingsCloseButton
@onready var _concurrency_spin: SpinBox = %ConcurrencySpin
@onready var _verify_check: CheckBox = %VerifyCheck
@onready var _force_check: CheckBox = %ForceCheck
@onready var _mirror_edit: LineEdit = %MirrorEdit
@onready var _filter_option: OptionButton = %FilterOption
@onready var _sort_option: OptionButton = %SortOption
@onready var _refresh_button: Button = %RefreshButton
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _reset_defaults_button: Button = %ResetDefaultsButton
@onready var _zoom_option: OptionButton = %ZoomOption
@onready var _scale_readout: Label = %ScaleReadout
@onready var _root_box: VBoxContainer = $Margin/Root
@onready var _java_status: Label = %JavaStatus
@onready var _java_spinner: Control = %JavaSpinner
@onready var _detect_java_button: Button = %DetectJavaButton
@onready var _install_java_button: Button = %InstallJavaButton
@onready var _loader_option: OptionButton = %LoaderOption
@onready var _loader_version_option: OptionButton = %LoaderVersionOption
@onready var _loader_manual_edit: LineEdit = %LoaderManualEdit
@onready var _search_mode_option: OptionButton = %SearchModeOption
@onready var _java_mirror_option: OptionButton = %JavaMirrorOption
@onready var _mod_mirror_edit: LineEdit = %ModMirrorEdit
@onready var _version_name_edit: LineEdit = %VersionNameEdit
@onready var _loader_status: Label = %LoaderStatus
@onready var _auto_java_check: CheckBox = %AutoJavaCheck
@onready var _settings_margin: Control = $SettingsPopup/SettingsMargin
@onready var _version_list: ItemList = %VersionList
@onready var _version_count: Label = %VersionCount
@onready var _version_name: Label = %VersionName
@onready var _version_type: Label = %VersionType
@onready var _version_date: Label = %VersionDate
@onready var _preview_hint: Label = %PreviewHint
@onready var _path_edit: LineEdit = %PathEdit
@onready var _browse_button: Button = %BrowseButton
@onready var _default_dir_button: Button = %DefaultDirButton
@onready var _ask_on_start_check: CheckBox = %AskOnStartCheck
@onready var _default_dir_edit: LineEdit = %DefaultDirSettingEdit
@onready var _find_button: Button = %FindButton
@onready var _path_hint: Label = %PathHint
@onready var _java_target_edit: LineEdit = %JavaTargetEdit
@onready var _pick_java_target_button: Button = %PickJavaTargetButton
@onready var _java_target_dialog: FileDialog = %JavaTargetDialog
@onready var _progress_label: Label = %ProgressLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _speed_label: Label = %SpeedLabel
@onready var _start_button: Button = %StartButton
@onready var _pause_button: Button = %PauseButton
@onready var _cancel_button: Button = %CancelButton
@onready var _status_label: Label = %StatusLabel
@onready var _disclaimer_label: Label = %DisclaimerLabel
@onready var _folder_dialog: FileDialog = %FolderDialog

var _queue: DownloadQueue

var _versions: Array[McVersion] = []
var _selected: McVersion = null
var _plan: InstallPlan = null
var _plan_key := ""

## 自动模式下测速选出来的源
var _auto_source := DownloadSource.ID_BMCLAPI
var _speed_testing := false
var _loading_versions := false
var _busy := false
var _preview_token := 0
var _failures: Array[Dictionary] = []

## 本机检测到的 Java 列表，以及当前选中的那个
var _java_candidates: Array[Dictionary] = []
var _java_chosen: Dictionary = {}
## 当前版本要求的 Java 主版本
var _required_java := 0
## 用户手动指定的 Java 主目录（空 = 自动找）
var _custom_java_home := ""
var _java_scanning := false
## 已经因为哪个版本弹过「要不要装 Java」的提示，避免反复弹
var _java_prompted_version := ""
var _pending_java := 0

## ---- 代码构建的弹窗（避免改场景文件出错）----
var _java_notice: PopupPanel
var _java_notice_label: Label
var _java_notice_timer := 0.0

## ---- 加载器 ----
var _loader_kind := "none"
var _loader_versions: Array = []
var _fabric_api_option: OptionButton
var _fabric_api_list: Array = []

## ---- Mod / 整合包页面 ----
var _catalog: Control = null

var _wizard: Control = null
var _help_dialog: PopupPanel
var _links_dialog: PopupPanel
var _java_mirror_index := 0
var _java_auto_prefer_official := false
var _ui_locked := false
var _create_default_dialog: PopupPanel
var _create_default_text: Label
var _bar_loader: ProgressBar
var _bar_fabric: ProgressBar
var _bar_extras: ProgressBar
var _default_hint: Label
var _default_dir_override := ""
var _default_dir_dialog: FileDialog
var _default_prompt_mode := "create_root"
var _missing_dirs: Array[String] = []
var _extras_box: VBoxContainer
var _extra_bars: Array = []
## 正在安装的加载器版本 id（装完要校验文件到底有没有落盘）
var _loader_pending_id := ""
## 点开始下载时选的加载器（下完原版自动装）
var _pending_loader_kind := ""
## 快速安装向导选的附加内容，等加载器装完再下
var _pending_extras: Array = []
var _wizard_java_auto := true
var _wizard_extras_total := 0
var _wizard_extras_done := 0

var _notice_dialog: AcceptDialog
var _create_dir_dialog: ConfirmationDialog
var _pending_create_dir := ""

## 进度条平滑用的显示值 / 目标值
var _target_progress := 0.0
var _shown_progress := 0.0
## 「加载中…」点点动画
var _dot_time := 0.0
var _dot_index := 0


func _ready() -> void:
	theme = UiTheme.build()
	_setup_window()

	_queue = DownloadQueue.new()
	_queue.name = "DownloadQueue"
	add_child(_queue)
	_queue.progressed.connect(_on_progress)
	_queue.batch_finished.connect(_on_batch_finished)
	_queue.file_failed.connect(_on_file_failed)

	for i in SOURCE_IDS.size():
		_source_option.add_item(SOURCE_LABELS[i], i)
	for i in FILTER_LABELS.size():
		_filter_option.add_item(FILTER_LABELS[i], i)
	for i in SORT_LABELS.size():
		_sort_option.add_item(SORT_LABELS[i], i)
		_sort_option.set_item_tooltip(i, SORT_TOOLTIPS[i])
	_sort_option.select(0)
	for i in ZOOM_LABELS.size():
		_zoom_option.add_item(ZOOM_LABELS[i], i)
	_zoom_option.select(0)

	_load_settings()
	_apply_download_settings()
	_refresh_path_hint()
	_disclaimer_label.text = "%s · %s · 游戏文件在下载时从官方或镜像源获取，本软件不附带任何游戏文件，请使用自己的正版账号" % [APP_NAME, DISCLAIMER]

	_source_option.item_selected.connect(_on_source_changed)
	_speed_button.pressed.connect(_on_speed_test_pressed)
	_filter_option.item_selected.connect(func(_index: int) -> void: _apply_filter())
	_sort_option.item_selected.connect(func(_index: int) -> void: _apply_filter())
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_search_edit.text_changed.connect(func(_text: String) -> void: _apply_filter())
	_version_list.item_selected.connect(_on_version_selected)
	_browse_button.pressed.connect(_on_browse_pressed)
	_default_dir_button.pressed.connect(_on_use_default_dir)
	_find_button.pressed.connect(_on_find_pressed)
	_folder_dialog.dir_selected.connect(_on_folder_selected)
	_java_target_dialog.dir_selected.connect(_on_java_target_selected)
	_pick_java_target_button.pressed.connect(_on_pick_java_target_pressed)
	_path_edit.text_submitted.connect(func(_text: String) -> void: _on_path_changed())
	_path_edit.focus_exited.connect(_on_path_changed)
	_start_button.pressed.connect(_on_start_pressed)
	_pause_button.pressed.connect(_on_pause_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)

	# 下载设置
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_close_button.pressed.connect(func() -> void: _settings_popup.hide())
	_concurrency_spin.value_changed.connect(func(_v: float) -> void: _on_download_setting_changed())
	_verify_check.toggled.connect(func(_p: bool) -> void: _on_download_setting_changed())
	_force_check.toggled.connect(func(_p: bool) -> void: _on_download_setting_changed())
	_mirror_edit.text_changed.connect(func(_t: String) -> void: _on_mirror_changed())
	_mirror_edit.text_submitted.connect(func(_t: String) -> void: _save_settings())
	_mirror_edit.focus_exited.connect(_save_settings)
	_reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

	# Java 运行时
	_detect_java_button.pressed.connect(_on_detect_java_pressed)
	_install_java_button.pressed.connect(_on_install_java_pressed)
	_auto_java_check.toggled.connect(func(_p: bool) -> void: _save_settings())
	_ask_on_start_check.toggled.connect(func(_p: bool) -> void: _save_settings())
	_default_dir_edit.text_changed.connect(func(text: String) -> void:
		_default_dir_override = text.strip_edges()
		_save_settings()
		_update_default_hint()
	)
	_default_dir_edit.text_submitted.connect(func(_t: String) -> void: _save_settings())
	_default_dir_edit.get_node("../DefaultDirSettingBrowse").pressed.connect(func() -> void:
		_default_dir_dialog.popup_centered()
	)
	for i in 5:
		_loader_option.add_item(["不装", "Fabric", "Quilt", "Forge", "NeoForge"][i], i)
	_loader_option.item_selected.connect(_on_loader_kind_changed)
	for i in 3:
		_search_mode_option.add_item(["只搜名称", "名称 + 简介", "翻译后搜索"][i], i)
	_search_mode_option.item_selected.connect(func(i: int) -> void:
		Modrinth.search_mode = i
		_save_settings()
	)
	_search_mode_option.select(clampi(Modrinth.search_mode, 0, 2))

	for i in 3:
		_java_mirror_option.add_item(["自动测速", "清华 TUNA", "官方 GitHub"][i], i)
	_java_mirror_option.item_selected.connect(func(_i: int) -> void: _apply_mirror_settings(); _save_settings())
	if _java_mirror_option.item_count > 0:
		_java_mirror_option.select(clampi(_java_mirror_index, 0, 2))
	_mod_mirror_edit.text_changed.connect(func(text: String) -> void:
		Modrinth.custom_base = text.strip_edges()
		_save_settings()
	)
	_build_dialogs()
	_build_default_dir_dialog()
	_default_dir_dialog = FileDialog.new()
	_default_dir_dialog.title = "选择默认游戏目录"
	_default_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_default_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_default_dir_dialog.use_native_dialog = true
	_default_dir_dialog.dir_selected.connect(func(p: String) -> void:
		_default_dir_edit.text = p.replace("\\", "/")
		_default_dir_override = _default_dir_edit.text
		_save_settings()
		_update_default_hint()
	)
	add_child(_default_dir_dialog)
	_build_nav()
	_build_loader_extra()
	_build_task_bars()
	_settings_popup.about_to_popup.connect(func() -> void: UiFx.fade_in(_settings_margin, 0.22))

	GLog.init()
	UiFx.install(self)
	var root_margin := get_node_or_null("Margin") as Control
	if root_margin != null:
		UiFx.launch_intro(root_margin)
	call_deferred("_check_default_dir_on_start")
	# 界面缩放：窗口尺寸一变就重新算一次，读数也跟着刷新
	_zoom_option.item_selected.connect(_on_zoom_changed)
	var win := get_window()
	if win != null:
		win.size_changed.connect(_on_window_resized)

	# 等一帧让容器算出最小尺寸，再应用缩放，避免首次被裁
	await get_tree().process_frame
	_apply_ui_zoom()
	UiFx.fade_in(self, 0.4)
	await _check_java(_required_java)

	await _bootstrap()


# ---------------------------------------------------------------- 初始化

## 列表 / 计数 / 状态栏三处统一的「加载中…」提示
func _show_loading_state() -> void:
	_version_list.clear()
	_version_list.add_item("加载中…")
	_version_list.set_item_disabled(0, true)
	_version_count.text = "加载中…"
	_status("加载中…")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		# 不替用户挑目录：第一次启动就是空着，让用户自己选
		_path_edit.text = ""
		_source_option.select(0)
		_reset_download_settings_ui()
		return

	var saved_dir := String(cfg.get_value("general", "game_dir_user", "")).replace("\\", "/").trim_suffix("/")
	# 不替用户挑目录：没存过或存的路径不合法就留空
	_path_edit.text = saved_dir if _looks_like_game_dir(saved_dir) else ""
	_auto_source = String(cfg.get_value("general", "auto_source", DownloadSource.ID_BMCLAPI))
	_ask_on_start_check.button_pressed = bool(cfg.get_value("general", "ask_on_start", true))
	_default_dir_override = String(cfg.get_value("general", "default_dir", ""))
	_default_dir_edit.text = _default_dir_override
	Modrinth.search_mode = int(cfg.get_value("search", "mode", 1))
	Modrinth.custom_base = String(cfg.get_value("mod", "mirror", ""))
	var jm := int(cfg.get_value("java", "mirror", 0))
	_java_mirror_index = jm
	_mod_mirror_edit.text = Modrinth.custom_base
	if _java_mirror_option.item_count > 0:
		_java_mirror_option.select(clampi(jm, 0, 2))
	var mode := String(cfg.get_value("general", "source_mode", DownloadSource.ID_AUTO))
	var idx := SOURCE_IDS.find(mode)
	_source_option.select(idx if idx >= 0 else 0)

	_concurrency_spin.value = clampf(
		float(cfg.get_value("download", "concurrency", DEFAULT_CONCURRENCY)),
		float(MIN_CONCURRENCY), float(MAX_CONCURRENCY)
	)
	_verify_check.button_pressed = bool(cfg.get_value("download", "verify_sha1", true))
	_force_check.button_pressed = bool(cfg.get_value("download", "force_overwrite", false))
	_mirror_edit.text = String(cfg.get_value("download", "mirror_base", ""))

	var zoom := int(cfg.get_value("display", "ui_zoom", 0))
	_zoom_option.select(clampi(zoom, 0, ZOOM_LABELS.size() - 1))

	_auto_java_check.button_pressed = bool(cfg.get_value("java", "prompt_on_missing", true))
	_custom_java_home = String(cfg.get_value("java", "custom_home", ""))
	JavaRuntime.custom_home = _custom_java_home
	_java_target_edit.text = String(cfg.get_value("java", "install_root", ""))


func _reset_download_settings_ui() -> void:
	_concurrency_spin.value = DEFAULT_CONCURRENCY
	_verify_check.button_pressed = true
	_force_check.button_pressed = false
	_mirror_edit.text = ""
	_zoom_option.select(0)
	_auto_java_check.button_pressed = true
	_custom_java_home = ""
	_java_target_edit.text = ""
	JavaRuntime.custom_home = ""


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "game_dir_user", _game_dir())
	cfg.set_value("general", "source_mode", _current_mode())
	cfg.set_value("general", "auto_source", _auto_source)
	cfg.set_value("download", "concurrency", int(_concurrency_spin.value))
	cfg.set_value("download", "verify_sha1", _verify_check.button_pressed)
	cfg.set_value("download", "force_overwrite", _force_check.button_pressed)
	cfg.set_value("download", "mirror_base", _mirror_edit.text.strip_edges())
	cfg.set_value("display", "ui_zoom", _zoom_option.selected)
	cfg.set_value("java", "prompt_on_missing", _auto_java_check.button_pressed)
	cfg.set_value("java", "custom_home", _custom_java_home)
	cfg.set_value("java", "install_root", _java_target_edit.text.strip_edges())
	if _search_mode_option != null:
		cfg.set_value("search", "mode", _search_mode_option.selected)


## 把设置面板上的值推给下载队列 / 下载源
func _apply_download_settings() -> void:
	if _queue != null:
		_queue.max_concurrent = clampi(int(_concurrency_spin.value), MIN_CONCURRENCY, MAX_CONCURRENCY)
		_queue.verify_sha1 = _verify_check.button_pressed
		_queue.force_overwrite = _force_check.button_pressed
	DownloadSource.custom_mirror_base = _mirror_edit.text.strip_edges()
	JavaRuntime.custom_home = _custom_java_home

	# 用了自定义镜像时，下拉框里的称呼也跟着变
	var custom := not DownloadSource.custom_mirror_base.is_empty()
	var mirror_index: int = SOURCE_IDS.find(DownloadSource.ID_BMCLAPI)
	if mirror_index >= 0 and _source_option.item_count > mirror_index:
		_source_option.set_item_text(mirror_index, "自定义镜像" if custom else "BMCLAPI 镜像")
		_source_option.set_item_tooltip(
			mirror_index,
			DownloadSource.mirror_base() if custom else "https://bmclapi2.bangbang93.com"
		)


func _on_download_setting_changed() -> void:
	_apply_download_settings()
	_save_settings()


func _on_mirror_changed() -> void:
	_apply_download_settings()
	# 镜像根地址只影响下载时的 URL 改写，文件清单与体积不变，
	# 所以缓存里的安装计划（_plan）依然有效，不需要重建。


func _on_settings_pressed() -> void:
	_settings_popup.popup_centered()


## 设置面板里的「恢复默认」
func _on_reset_defaults_pressed() -> void:
	_reset_download_settings_ui()
	_apply_download_settings()
	_save_settings()
	_status("下载设置已恢复默认值。")


func _default_game_dir() -> String:
	if not _default_dir_override.is_empty():
		return _default_dir_override.replace("\\", "/").trim_suffix("/")
	var appdata := OS.get_environment("APPDATA")
	if not appdata.is_empty():
		return appdata.replace("\\", "/").path_join(".minecraft")
	return OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).replace("\\", "/").path_join("minecraft")


# ---------------------------------------------------------------- 下载源

func _current_mode() -> String:
	var idx := _source_option.selected
	if idx < 0 or idx >= SOURCE_IDS.size():
		return DownloadSource.ID_AUTO
	return String(SOURCE_IDS[idx])


func _effective_source() -> DownloadSource:
	var mode := _current_mode()
	if mode == DownloadSource.ID_AUTO:
		return DownloadSource.create(_auto_source)
	return DownloadSource.create(mode)


func _on_source_changed(index: int) -> void:
	if index < 0 or index >= SOURCE_IDS.size():
		return
	_save_settings()
	_plan = null
	# 换源后版本列表要从新源重取，加载/失败的提示由 _reload_versions 负责
	await _reload_versions()
	if _selected != null:
		await _preview_plan()


func _on_speed_test_pressed() -> void:
	await _run_speed_test(false)


func _run_speed_test(silent: bool) -> void:
	if _speed_testing:
		return
	_speed_testing = true
	_speed_button.disabled = true
	_source_status.text = "正在测速…"
	if not silent:
		_status("正在同时探测官方源与镜像源…")

	var sources: Array = [
		DownloadSource.create(DownloadSource.ID_OFFICIAL),
		DownloadSource.create(DownloadSource.ID_BMCLAPI),
	]
	var results: Array = await DownloadSource.measure_all(self, sources, 15.0)

	var official := {}
	var mirror := {}
	for r in results:
		var item: Dictionary = r
		if String(item.get("id", "")) == DownloadSource.ID_OFFICIAL:
			official = item
		elif String(item.get("id", "")) == DownloadSource.ID_BMCLAPI:
			mirror = item

	_source_status.text = "官方 %s ｜ 镜像 %s" % [_speed_text(official), _speed_text(mirror)]

	var best := _pick_best(official, mirror)
	if not best.is_empty():
		_auto_source = best
		_source_status.text += "（用%s）" % ("官方" if best == DownloadSource.ID_OFFICIAL else "镜像")

	_speed_testing = false
	_speed_button.disabled = false
	_save_settings()

	if not silent:
		_status("测速完成：%s" % _source_status.text)
		_plan = null
		if _selected != null:
			await _preview_plan()


func _pick_best(official: Dictionary, mirror: Dictionary) -> String:
	var o_ok := bool(official.get("ok", false))
	var m_ok := bool(mirror.get("ok", false))
	var o_speed := float(official.get("speed", 0.0))
	var m_speed := float(mirror.get("speed", 0.0))
	if o_ok and m_ok:
		return DownloadSource.ID_OFFICIAL if o_speed >= m_speed else DownloadSource.ID_BMCLAPI
	if o_ok:
		return DownloadSource.ID_OFFICIAL
	if m_ok:
		return DownloadSource.ID_BMCLAPI
	return ""


func _speed_text(result: Dictionary) -> String:
	if result.is_empty():
		return "未测"
	if not bool(result.get("ok", false)):
		return "不可用"
	return "%s/s" % _format_size(int(float(result.get("speed", 0.0))))


# ---------------------------------------------------------------- 版本列表

func _reload_versions() -> void:
	if _loading_versions:
		return
	_loading_versions = true

	# 加载中：列表、计数、状态栏三处都给出同一个提示
	_versions.clear()
	_show_loading_state()
	_refresh_button.disabled = true

	# 首选当前生效的源，失败就自动换另一个源再来一次（单源挂掉不至于整个页面空着）
	var preferred := _effective_source()
	var fallback_id := DownloadSource.ID_BMCLAPI if preferred.id == DownloadSource.ID_OFFICIAL else DownloadSource.ID_OFFICIAL
	var candidates: Array[DownloadSource] = [preferred, DownloadSource.create(fallback_id)]

	var list: Array = []
	var errors: Array[String] = []
	var used_source: DownloadSource = null

	for src in candidates:
		var res := await HttpUtil.fetch_json(self, src.manifest_url, 25.0, 1)
		var ok := bool(res.get("ok", false))
		var data: Dictionary = res.get("data", {}) if ok else {}
		var got: Array = data.get("versions", [])
		if ok and not got.is_empty():
			list = got
			used_source = src
			break
		var reason := String(res.get("error", "清单为空"))
		if ok and got.is_empty():
			reason = "清单为空"
		errors.append("%s → %s" % [src.display_name, reason])
		if src != candidates[candidates.size() - 1]:
			_status("从 %s 获取失败，正在换 %s 重试…" % [src.display_name, candidates[1].display_name])

	_loading_versions = false
	_refresh_button.disabled = _busy

	if list.is_empty():
		_version_list.clear()
		_version_count.text = "加载失败"
		GLog.error("版本列表加载失败（两个源都没连上）")
		_status("两个下载源都连不上：%s。　排查：①点「刷新」再试 ②「测速」看哪个源通 ③如果开了代理/VPN，Godot 不走系统代理，需要让它整体走代理。" % "；".join(errors))
		return

	_versions.clear()
	for item in list:
		if typeof(item) == TYPE_DICTIONARY:
			_versions.append(McVersion.from_dict(item))

	_apply_filter()

	# 给安装计划一个「版本 id → 版本 JSON 地址」的索引，解析 inheritsFrom 时要用
	var index := {}
	for v in _versions:
		index[v.id] = v.url
	InstallPlan.set_version_index(index)

	# 自动模式下记住「这次真的能用的源」，后续生成计划、下载都走它
	if used_source != null and _current_mode() == DownloadSource.ID_AUTO and _auto_source != used_source.id:
		_auto_source = used_source.id
		_save_settings()

	# 成功就不打扰了，状态栏清空（列表与计数已经说明一切）
	_status("")


func _bootstrap() -> void:
	# 一开始就先亮出「加载中…」，别让用户面对空白列表
	_show_loading_state()
	# 测速放到后台跑（不 await），列表立刻用当前源开始拉，能省几十秒等待
	_run_speed_test(true)
	await _reload_versions()


func _on_refresh_pressed() -> void:
	await _reload_versions()


func _apply_filter() -> void:
	var filter := _filter_option.selected
	var query := _search_edit.text.strip_edges().to_lower()

	var picked: Array[McVersion] = []
	for v in _versions:
		if not _match_filter(v, filter):
			continue
		if not query.is_empty() and not v.id.to_lower().contains(query):
			continue
		picked.append(v)

	_sort_versions(picked)

	_version_list.clear()
	for v in picked:
		var idx := _version_list.add_item("%s    ·    %s    ·    %s" % [v.id, v.display_type_label(), v.release_date()])
		_version_list.set_item_metadata(idx, v)

	_version_count.text = "共 %d 个版本（显示 %d 个）" % [_versions.size(), picked.size()]
	UiFx.fade_swap(_version_list, 0.16)


func _sort_versions(picked: Array[McVersion]) -> void:
	match _sort_option.selected:
		1:  # 发布时间 旧→新
			picked.sort_custom(func(a: McVersion, b: McVersion) -> bool: return a.release_time < b.release_time)
		2:  # 版本号 A→Z
			picked.sort_custom(func(a: McVersion, b: McVersion) -> bool: return a.id.naturalnocasecmp_to(b.id) < 0)
		3:  # 版本号 Z→A
			picked.sort_custom(func(a: McVersion, b: McVersion) -> bool: return a.id.naturalnocasecmp_to(b.id) > 0)
		_:  # 发布时间 新→旧
			picked.sort_custom(func(a: McVersion, b: McVersion) -> bool: return a.release_time > b.release_time)


## filter 与 FILTER_LABELS 一一对应：
## 0 全部 / 1 正式版 / 2 快照（不含愚人节）/ 3 愚人节 / 4 远古版本
func _match_filter(v: McVersion, filter: int) -> bool:
	match filter:
		1:
			return v.is_release()
		2:
			return v.type == "snapshot" and not v.is_april_fools()
		3:
			return v.is_april_fools()
		4:
			return v.is_old()
		_:
			return true


func _on_version_selected(index: int) -> void:
	var meta: Variant = _version_list.get_item_metadata(index)
	if meta is McVersion:
		await _select_version(meta)


func _select_version(v: McVersion) -> void:
	_selected = v
	_version_name.text = v.id
	_version_type.text = "类型：%s" % v.display_type_label()
	_version_date.text = "发布时间：%s" % v.release_date()
	_start_button.disabled = _busy or _game_dir().is_empty()
	_pop_in(_version_name)
	await _preview_plan()


# ---------------------------------------------------------------- 安装计划

## 当前生效的游戏目录；路径非法（空、盘符根、太短）时返回空串，调用方必须自己处理，
## 不再"悄悄"回退到 %APPDATA%\.minecraft —— 那样用户会以为路径被写死了。
## 这次安装最终会生成的版本 id（自定义名字优先，否则用官方的）
func _custom_version_id() -> String:
	var custom := ""
	if _version_name_edit != null:
		custom = _version_name_edit.text.strip_edges()
	if not custom.is_empty():
		return custom
	return _selected.id if _selected != null else ""


## 字节数转成 12.3 MB 这种
func _fmt_size(n: int) -> String:
	if n <= 0:
		return "0 B"
	var units := ["B", "KB", "MB", "GB", "TB"]
	var v := float(n)
	var i := 0
	while v >= 1024.0 and i < units.size() - 1:
		v /= 1024.0
		i += 1
	return "%.1f %s" % [v, units[i]]


func _game_dir() -> String:
	var p := _path_edit.text.strip_edges().replace("\\", "/").trim_suffix("/")
	if not _looks_like_game_dir(p):
		return ""
	return p


## 太短的路径（盘符根 "C:"、"/"、空串）都不算有效游戏目录
func _looks_like_game_dir(path: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	if path.length() < 4:
		return false
	if path.ends_with(":"):
		return false
	return true


## 还没选游戏目录时用这个占位目录来算「文件数 / 体积」——
## 统计体积不需要真实路径，等用户选好目录，计划会因为 key 变化自动重建。
const PREVIEW_DIR := "__preview__"


## 生成计划用的目录：没选就用占位目录，保证体积照样能显示
func _plan_dir() -> String:
	var d := _game_dir()
	return d if not d.is_empty() else PREVIEW_DIR


func _plan_key_for(v: McVersion) -> String:
	var name := _version_name_edit.text.strip_edges() if _version_name_edit != null else ""
	return "%s|%s|%s|%s" % [v.id, _effective_source().id, _plan_dir(), name]


## 生成（或复用）安装计划。返回是否成功。
func _ensure_plan(force: bool = false) -> bool:
	if _selected == null:
		return false
	var key := _plan_key_for(_selected)
	if not force and _plan != null and _plan.is_valid() and _plan_key == key:
		return true

	var cname := _version_name_edit.text.strip_edges() if _version_name_edit != null else ""
	if not cname.is_empty():
		var bad := ""
		for ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
			if cname.contains(ch):
				bad = ch
				break
		if not bad.is_empty():
			_plan = null
			_plan_key = ""
			_status("版本名字里不能有 %s 这种符号" % bad)
			return false
		if DirAccess.dir_exists_absolute(_plan_dir().path_join("versions").path_join(cname)) and cname != _selected.id:
			_status("已经有一个叫「%s」的版本了，换个名字" % cname)
			_plan = null
			_plan_key = ""
			return false
	var plan := await InstallPlan.build(self, _effective_source(), _selected, _plan_dir(), cname)
	_plan = plan
	_plan_key = key
	return plan.is_valid()


func _preview_plan() -> void:
	_preview_token += 1
	var token := _preview_token
	if _selected == null:
		return
	_preview_hint.text = "正在统计文件与体积…"

	var ok := await _ensure_plan()
	if token != _preview_token:
		return  # 用户已经换选了别的版本，丢弃这次结果
	if not ok:
		var reason := "未知错误"
		if _plan != null and not _plan.error.is_empty():
			reason = _plan.error
		_preview_hint.text = "统计失败：%s" % reason
		return

	var extra := ""
	if _plan.java_major > 0:
		extra = "，需要 Java %d" % _plan.java_major
	_preview_hint.text = "共 %d 个文件，约 %s%s" % [_plan.files.size(), _format_size(_plan.total_bytes), extra]
	UiFx.fade_swap(_preview_hint)
	# 换版本就自动检测一次 Java；版本不够会弹窗问要不要装
	await _check_java(_plan.java_major, true)


func _on_path_changed() -> void:
	call_deferred("_check_subdirs_hint")
	_refresh_path_hint()
	_save_settings()
	_plan = null
	_java_prompted_version = ""
	# 目录变了 Java 可能也跟着变，顺手重扫；计划里的绝对路径失效，需要重新统计
	_scan_java()
	_refresh_java_status()
	_validate_game_dir_interactive()
	if _selected != null and not _busy:
		await _preview_plan()


func _on_browse_pressed() -> void:
	var dir := _game_dir()
	if not dir.is_empty() and DirAccess.dir_exists_absolute(dir):
		_folder_dialog.current_dir = dir
	_folder_dialog.popup_centered()


func _on_folder_selected(path: String) -> void:
	_path_edit.text = path.replace("\\", "/").trim_suffix("/")
	await _on_path_changed()


## 目录那一行下面的提示：有效就显示实际路径，无效就明确警告（不再偷偷回退到默认目录）
func _refresh_path_hint() -> void:
	_update_default_hint()
	if _path_hint == null:
		return
	var dir := _game_dir()
	if dir.is_empty():
		_path_hint.text = "请选择游戏目录：点「查找」自动搜索，或「浏览…」手动选"
		_path_hint.add_theme_color_override("font_color", Color("e0a33a"))
		_path_hint.tooltip_text = ""
	else:
		var exists := DirAccess.dir_exists_absolute(dir)
		_path_hint.text = ("已存在：" if exists else "不存在，开始下载时会自动创建：") + dir
		_path_hint.add_theme_color_override("font_color", Color("98a0ae"))
		_path_hint.tooltip_text = dir
	_start_button.disabled = _busy or _selected == null or dir.is_empty()


## 「查找」：在常见位置里找已经存在的 .minecraft
func _on_find_pressed() -> void:
	UiFx.tap(_find_button)
	var found := _find_existing_game_dirs()
	if found.is_empty():
		_status("常见位置里没找到已有的 .minecraft，请用「浏览…」手动指定。")
		return
	if found.size() == 1:
		_path_edit.text = found[0]
		await _on_path_changed()
		_status("已找到游戏目录：%s" % found[0])
		return

	# 找到多个就让用户点一个
	var menu := PopupMenu.new()
	menu.theme = theme
	add_child(menu)
	for i in found.size():
		menu.add_item(found[i], i)
	menu.id_pressed.connect(func(id: int) -> void:
		_path_edit.text = String(found[id])
		_on_path_changed()
		_status("已切换游戏目录：%s" % String(found[id]))
	)
	menu.popup_hide.connect(menu.queue_free)
	var pos := _find_button.get_screen_position() + Vector2(0.0, _find_button.size.y)
	menu.popup(Rect2i(Vector2i(pos), Vector2i(440, 0)))
	menu.reset_size()


func _find_existing_game_dirs() -> Array[String]:
	var out: Array[String] = []
	var seen := {}

	var candidates: Array[String] = []
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	if not appdata.is_empty():
		candidates.append(appdata.path_join(".minecraft"))
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).replace("\\", "/")
	if not docs.is_empty():
		candidates.append(docs.path_join(".minecraft"))
	if OS.get_name() == "Windows":
		candidates.append("C:/Program Files (x86)/Minecraft")
		# 各盘根下随便一个文件夹（不一定叫 .minecraft），或者它下面的 .minecraft
		for letter in ["C", "D", "E", "F", "G", "H"]:
			var root := "%s:/" % letter
			if not DirAccess.dir_exists_absolute(root):
				continue
			for child in _subdirs_of(root):
				var name := child.get_file().to_lower()
				if name == ".minecraft" or name.contains("minecraft") or name == "mc" or name.begins_with("mc_"):
					candidates.append(child)
				elif _looks_like_mc_dir(child):
					candidates.append(child)
				# 常见再下一层：D:/Games/MC
				for sub in _subdirs_of(child):
					var sub_name := sub.get_file().to_lower()
					if sub_name == ".minecraft" or sub_name.contains("minecraft") or sub_name == "mc":
						candidates.append(sub)
	# 官方启动器里配置过的自定义游戏目录
	candidates.append_array(_official_launcher_dirs())

	for c in candidates:
		var p := String(c).replace("\\", "/").trim_suffix("/")
		if not _looks_like_game_dir(p):
			continue
		var key := p.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		if DirAccess.dir_exists_absolute(p) and _looks_like_mc_dir(p):
			out.append(p)
	return out


## 列出一个目录下所有子目录（包含 .minecraft 这种点开头的）
func _subdirs_of(path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			out.append(path.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	return out


## 从官方启动器的 launcher_profiles.json 里读用户自定义过的游戏目录
func _official_launcher_dirs() -> Array[String]:
	var out: Array[String] = []
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	if appdata.is_empty():
		return out
	var cfg_path := appdata.path_join(".minecraft").path_join("launcher_profiles.json")
	if not FileAccess.file_exists(cfg_path):
		return out
	var f := FileAccess.open(cfg_path, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var profiles: Variant = (parsed as Dictionary).get("profiles", {})
	if typeof(profiles) != TYPE_DICTIONARY:
		return out
	for key in profiles:
		var prof: Variant = profiles[key]
		if typeof(prof) != TYPE_DICTIONARY:
			continue
		var gd := String((prof as Dictionary).get("gameDirectory", "")).replace("\\", "/").trim_suffix("/")
		if not gd.is_empty():
			out.append(gd)
	return out


## 目录里有 Minecraft 的「硬标志」内容才算游戏目录。
## 只用这几样：太宽松的（logs / saves / mods）会把 C:/Windows、C:/inetpub 也误判进来。
func _looks_like_mc_dir(path: String) -> bool:
	var d := DirAccess.open(path)
	if d == null:
		return false
	for marker in ["launcher_profiles.json", "versions", "assets", "libraries", "runtime"]:
		if d.dir_exists(marker) or d.file_exists(marker):
			return true
	return false


## Java 装到哪：设置里指定了就用它，否则用「游戏目录/runtime」
func _java_install_root() -> String:
	var custom := _java_target_edit.text.strip_edges().replace("\\", "/").trim_suffix("/")
	if not custom.is_empty() and _looks_like_game_dir(custom):
		# 用户如果直接选了 …/runtime，就别再套一层
		if custom.get_file().to_lower() == "runtime":
			return custom
		return custom.path_join("runtime")
	var dir := _game_dir()
	if dir.is_empty():
		return ""
	return dir.path_join("runtime")


func _on_pick_java_target_pressed() -> void:
	UiFx.tap(_pick_java_target_button)
	var start := _java_install_root()
	if start.is_empty():
		start = _game_dir()
	if not start.is_empty() and DirAccess.dir_exists_absolute(start):
		_java_target_dialog.current_dir = start
	_java_target_dialog.popup_centered()




# ---------------------------------------------------------------- 下载

func _on_start_pressed() -> void:
	GLog.info("点击开始下载，选中版本：%s" % (_selected.id if _selected != null else "（未选）"))
	if _busy or _queue.is_running():
		return
	# 记下这次要顺带装的 mod 支持器（原版下完之后自动装）
	_pending_loader_kind = ""
	if _loader_kind != "none":
		var lv := _loader_manual_edit.text.strip_edges()
		if not _loader_versions.is_empty() or not lv.is_empty():
			_pending_loader_kind = _loader_kind
	if _selected == null:
		_status("请先在左侧选择一个版本")
		return

	var dir := _game_dir()
	if dir.is_empty():
		_status("请先选择游戏目录：点「浏览…」或「默认路径」，也可以用「查找」扫描已有目录")
		_path_edit.grab_focus()
		return
	var mk := DirAccess.make_dir_recursive_absolute(dir)
	if mk != OK and not DirAccess.dir_exists_absolute(dir):
		_status("无法创建安装目录：%s（%s）" % [dir, error_string(mk)])
		return

	_set_busy(true)
	_set_ui_locked(true)
	_failures.clear()
	_shown_progress = 0.0
	_target_progress = 0.0
	_progress_bar.value = 0.0
	_progress_label.text = "正在下载游戏文件…"
	_status("正在准备 %s 的文件列表…" % _selected.id)

	if not await _ensure_plan():
		var reason := "未知错误"
		if _plan != null and not _plan.error.is_empty():
			reason = _plan.error
		_status("准备失败：%s" % reason)
		GLog.error("准备下载失败：%s" % reason)
		_set_busy(false)
		_set_ui_locked(false)
		return

	# 注意：这里不会再顺带下载 Java，Java 只在用户自己点「安装」并确认后才会下载
	_shown_progress = 0.0
	_target_progress = 0.0
	_progress_bar.value = 0.0

	_save_settings()
	_apply_download_settings()
	_progress_label.text = "0 / %d 个文件" % _plan.files.size()
	var mode := "强制重下" if _queue.force_overwrite else "跳过已有文件"
	_status("开始下载 %s（%d 个文件，%s，%s，%d 路并发）…" % [
		_plan.version_id, _plan.files.size(), _format_size(_plan.total_bytes), mode, _queue.max_concurrent,
	])
	_queue.start(_plan.files)


func _on_pause_pressed() -> void:
	GLog.info("点击暂停")
	if not _queue.is_running():
		return
	var paused := not _queue.is_paused()
	_queue.set_paused(paused)
	_pause_button.text = "继续" if paused else "暂停"
	if paused:
		_status("已暂停：正在传输的文件会传完，之后不再开新任务。")
	else:
		_status("继续下载…")


func _on_cancel_pressed() -> void:
	GLog.info("点击取消")
	_queue.cancel()
	_set_busy(false)
	_set_ui_locked(false)
	_target_progress = 0.0
	_shown_progress = 0.0
	_progress_bar.value = 0.0
	_progress_label.text = "已取消"
	_speed_label.text = ""
	_status("已取消下载，已下载完成的文件会保留下来。")


func _on_progress(snap: Dictionary) -> void:
	if _wizard != null and _wizard.is_visible_in_tree():
		_wizard.call("set_progress", "%d / %d 个文件" % [int(snap.get("done_files", 0)), int(snap.get("total_files", 0))], float(snap.get("ratio", 0.0)))
		_wizard.call("wiz_progress", "game", float(snap.get("ratio", 0.0)),
			"%s / %s" % [_fmt_size(int(snap.get("done_bytes", 0))), _fmt_size(int(snap.get("total_bytes", 0)))])
	var total_bytes := int(snap.get("total_bytes", 0))
	var done_bytes := int(snap.get("done_bytes", 0))
	var total_files := int(snap.get("total_files", 0))
	var done_files := int(snap.get("done_files", 0))

	var percent := 0.0
	if total_bytes > 0:
		percent = clampf(float(done_bytes) / float(total_bytes) * 100.0, 0.0, 100.0)
	elif total_files > 0:
		percent = clampf(float(done_files) / float(total_files) * 100.0, 0.0, 100.0)
	# 交给 _process 平滑推进，进度条不会一顿一顿跳
	_target_progress = percent

	var failed := int(snap.get("failed_files", 0))
	var failed_suffix := ""
	if failed > 0:
		failed_suffix = "，失败 %d" % failed
	_progress_label.text = "%d / %d 个文件 ｜ %s / %s%s" % [
		done_files, total_files,
		_format_size(done_bytes), _format_size(total_bytes),
		failed_suffix,
	]

	if bool(snap.get("running", false)) and not bool(snap.get("paused", false)):
		_speed_label.text = "速度：%s/s ｜ 同时下载 %d 个文件" % [
			_format_size(int(float(snap.get("speed", 0.0)))), _queue.max_concurrent,
		]
	elif bool(snap.get("paused", false)):
		_speed_label.text = "已暂停：等在传的文件传完"


func _on_file_failed(path: String, message: String) -> void:
	_failures.append({"path": path, "message": message})


func _on_batch_finished(ok: bool, failed_count: int) -> void:
	_set_busy(false)
	_set_ui_locked(false)
	_pause_button.text = "暂停"

	# 原版下完，自动装所选 mod 支持器
	if ok and failed_count == 0 and not _pending_loader_kind.is_empty():
		var lk := _pending_loader_kind
		_pending_loader_kind = ""
		var kinds := ["none", "fabric", "quilt", "forge", "neoforge"]
		var ki := kinds.find(lk)
		_loader_kind = lk
		_loader_option.select(maxi(ki, 0))
		_loader_version_option.clear()
		_loader_versions.clear()
		_status("原版装好了，接着装 %s…" % lk.capitalize())
		await _on_loader_kind_changed(maxi(ki, 0))
		_on_install_loader_pressed()

	if ok and _plan != null:
		_target_progress = 100.0
		_progress_bar.value = 100.0
		_shown_progress = 100.0
		_speed_label.text = ""
		_progress_label.text = "%d 个文件已全部完成" % _plan.files.size()
		UiFx.glow(_progress_bar, Color(1.35, 1.95, 1.45), 1.1)
		var extracted := InstallPlan.extract_natives(_plan)
		var extra := ""
		if extracted > 0:
			extra = "（另外解压了 %d 个原生库文件）" % extracted
		_status("完成 ✅ %s 已下载到 %s%s。现在可以用启动器启动它了。" % [_plan.version_id, _game_dir(), extra])
		# 装完再扫一遍 Java，界面上就能看到实际用的哪个
		_scan_java()
		_refresh_java_status(_required_java)
	elif failed_count > 0:
		_write_error_log()
		_status("有 %d 个文件下载失败，明细已写入 %s。再点一次「开始下载」会跳过已完成的文件并只补缺失的。" % [failed_count, ERROR_LOG_PATH])
		GLog.error("本次有 %d 个文件下载失败" % failed_count)
	else:
		_status("下载已结束。")


# ---------------------------------------------------------------- 杂项

func _set_busy(busy: bool) -> void:
	_busy = busy
	_start_button.disabled = busy or _selected == null or _game_dir().is_empty()
	_pause_button.disabled = not busy
	_cancel_button.disabled = not busy
	_source_option.disabled = busy
	_speed_button.disabled = busy or _speed_testing
	_browse_button.disabled = busy
	_path_edit.editable = not busy
	_filter_option.disabled = busy
	_sort_option.disabled = busy
	_search_edit.editable = not busy
	_refresh_button.disabled = busy or _loading_versions


func _status(text: String) -> void:
	if _status_label.text == text:
		return
	_status_label.text = text
	if not text.is_empty():
		print("[下载] ", text)
		UiFx.fade_swap(_status_label, 0.15)


func _write_error_log() -> void:
	var lines := PackedStringArray()
	lines.append("# %s  下载失败明细" % Time.get_datetime_string_from_system())
	for f in _failures:
		lines.append("%s  <-  %s" % [String(f.get("path", "")), String(f.get("message", ""))])
	var file := FileAccess.open(ERROR_LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(lines))
	file.close()


static func _format_size(bytes: int) -> String:
	if bytes <= 0:
		return "0 B"
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (float(bytes) / 1048576.0)
	return "%.2f GB" % (float(bytes) / 1073741824.0)


# ---------------------------------------------------------------- 窗口与界面缩放
#
# 缩放原理（canvas_items + expand）：
#   实际缩放 = min(窗口宽/基准宽, 窗口高/基准高) × 界面缩放倍率
# 所以窗口按比例变大时整个界面等比放大；多出来的那一部分不会变成黑边，
# 而是变成"更多空间"——更宽就加宽版面，更高就多显示版本行。

## 启动时把窗口撑到屏幕可用区域的 80%（不小于设计尺寸、不超过上限），并居中
func _setup_window() -> void:
	var win := get_window()
	if win == null:
		return
	win.min_size = MIN_WINDOW_SIZE

	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return

	var limit := Vector2i(1600, 1000)
	var target := Vector2i(
		clampi(int(float(usable.size.x) * 0.8), BASE_SIZE.x, limit.x),
		clampi(int(float(usable.size.y) * 0.8), BASE_SIZE.y, limit.y),
	)
	# 只在窗口比目标小时才撑大，用户自己调过的尺寸不覆盖
	if win.size.x < target.x or win.size.y < target.y:
		win.size = target
		win.position = usable.position + (usable.size - target) / 2


## 应用「界面缩放」：0 = 跟随窗口自动；其余在自动缩放的基础再放大/缩小
func _apply_ui_zoom() -> void:
	var win := get_window()
	if win == null or _zoom_option == null:
		return
	var index := clampi(_zoom_option.selected, 0, ZOOM_SCALES.size() - 1)
	var zoom: float = ZOOM_SCALES[index]
	var base := Vector2(BASE_SIZE) / zoom

	# 只有"放大"（zoom > 1）才有被裁的风险，这时才需要用版面最小尺寸兜底。
	# 注意：布局还没算完时最小尺寸会给出离谱的大值，所以过大就当作没算好、跳过兜底。
	if zoom > 1.0 and _root_box != null:
		var need := _root_box.get_combined_minimum_size()
		if need.x > 1.0 and need.y > 1.0 and need.x < float(BASE_SIZE.x) and need.y < float(BASE_SIZE.y):
			base = base.max(need).min(Vector2(BASE_SIZE))

	win.content_scale_size = Vector2i(roundi(base.x), roundi(base.y))
	_update_scale_readout()


func _on_zoom_changed(_index: int) -> void:
	_apply_ui_zoom()
	_save_settings()


func _on_window_resized() -> void:
	# 窗口尺寸变了就重算一次（读数的倍率也会随之变化）
	_apply_ui_zoom()


## 把「窗口多大 / 逻辑多大 / 实际放大多少倍」显示在设置里，便于确认缩放真的生效
func _update_scale_readout() -> void:
	if _scale_readout == null:
		return
	var win := get_window()
	if win == null:
		return
	var vis := get_viewport().get_visible_rect().size
	if vis.x <= 0.0:
		return
	var factor := float(win.size.x) / vis.x
	_scale_readout.text = "窗口 %d×%d ｜ 逻辑尺寸 %d×%d ｜ 实际缩放 %.2f×" % [
		win.size.x, win.size.y, int(vis.x), int(vis.y), factor,
	]
	# 同时写进窗口标题：不用打开设置就能确认缩放到底有没有生效
	win.title = "%s — 窗口 %d×%d ｜ 缩放 %.2f×" % [APP_NAME, win.size.x, win.size.y, factor]


# ---------------------------------------------------------------- Java 运行时

func _scan_java() -> void:
	JavaRuntime.custom_home = ""
	_java_candidates = JavaRuntime.scan(_game_dir(), _java_install_root())


## 扫描并刷新界面：只检测，不下载、不弹按钮。
## prompt_if_low = true 且版本不够时，弹一个纯文字提示（无按钮，几秒后自动消失）。
func _check_java(required_major: int, prompt_if_low := false) -> void:
	if required_major > 0:
		_required_java = required_major

	# 设置里关掉了自动检测
	if _auto_java_check != null and not _auto_java_check.button_pressed:
		_java_spinner.visible = false
		_java_scanning = false
		_java_status.text = "已取消自动检测 Java"
		_java_status.tooltip_text = "在「设置」里重新打开「切换版本时自动检测 Java」"
		return

	if _java_scanning:
		return

	_java_scanning = true
	_java_spinner.visible = true
	_java_status.text = "正在检测 Java…"
	await get_tree().process_frame

	_scan_java()
	_java_spinner.visible = false
	_java_scanning = false
	_refresh_java_status()

	if not prompt_if_low:
		return
	var need := _required_java
	if need <= 0 or _selected == null:
		return
	if not JavaRuntime.pick(_java_candidates, need).is_empty():
		return
	if _java_prompted_version == _selected.id:
		return
	_java_prompted_version = _selected.id
	var found := _java_major_list()
	_status("「%s」需要 Java %d，本机现在是 %s —— 在右边选好安装路径后点「安装 Java」" % [
		_selected.id, need, found if not found.is_empty() else "没有",
	])

## 纯文字提示：只说明「版本不够」，没有任何按钮
func _show_java_notice_unused(need: int) -> void:
	if _java_notice == null:
		return
	var found := _java_major_list()
	_java_notice_label.text = "「%s」需要 Java %d，本机检测到：%s。\n请在右侧「Java 运行时」选好安装路径，再点「安装 Java」。" % [
		_selected.id if _selected != null else "当前版本", need,
		("Java " + found) if not found.is_empty() else "没有",
	]
	_java_notice.popup_centered()
	_java_notice_timer = 6.0


func _on_detect_java_pressed() -> void:
	_java_prompted_version = ""
	UiFx.tap(_detect_java_button)
	await _check_java(-1)
	if _java_chosen.is_empty():
		_status("已重新检测 Java：没找到合适的版本。" if _required_java > 0 else "已重新检测本机 Java。")
	else:
		_status("已重新检测 Java：%s" % String(_java_chosen.get("version", "")))


## 「安装 Java」：直接装到右侧显示的路径
func _on_install_java_pressed() -> void:
	UiFx.tap(_install_java_button)
	if _required_java <= 0:
		_status("先选一个版本，才知道要装哪个 Java。")
		return
	await _install_java(_required_java)


## 真正下载安装，带转圈和进度
func _install_java(required_major: int) -> bool:
	if required_major <= 0:
		return false

	var root := _java_install_root()
	if root.is_empty():
		_status("先在右侧填/选一个 Java 安装路径。")
		return false

	_java_scanning = true
	_java_spinner.visible = true
	_java_status.text = "正在安装 Java %d…" % required_major
	_progress_label.text = "正在安装 Java %d…" % required_major
	_status("正在安装 Java %d 到 %s …" % [required_major, root])

	# Java 下载源：自动测速 / 清华 / 官方
	var prefer_official := _java_mirror_index == 2 or (_java_mirror_index == 0 and _java_auto_prefer_official)
	_set_ui_locked(true)
	var progress_cb := func(info: String, fraction: float) -> void:
		_status(info)
		_java_status.text = info
		_progress_label.text = info
		_target_progress = fraction * 100.0
		if _wizard != null and _wizard.is_visible_in_tree():
			_wizard.call("wiz_progress", "java", fraction, "%d%%" % int(fraction * 100.0))
	var res: Dictionary = await JavaRuntime.install(self, root, required_major, progress_cb, prefer_official)
	_java_spinner.visible = false
	_java_scanning = false
	_target_progress = 0.0
	_shown_progress = 0.0
	_progress_bar.value = 0.0

	if not bool(res.get("ok", false)):
		var err := String(res.get("error", "未知错误"))
		_status("Java 安装失败：%s" % err)
		GLog.error("Java 安装失败：%s" % err)
		_java_status.text = "安装失败：%s" % err
		return false

	_scan_java()
	_refresh_java_status()
	_progress_label.text = "Java 装好了"
	_progress_bar.value = 0.0
	_status("Java %s 已装到：%s" % [String(res.get("version", "")), String(res.get("home", ""))])
	return true


## 刷新界面上的 Java 状态
func _refresh_java_status(required_major := -1) -> void:
	if required_major > 0:
		_required_java = required_major
	if _java_candidates.is_empty():
		_scan_java()

	var need := _required_java
	var chosen := JavaRuntime.pick(_java_candidates, need)
	var root := _java_install_root()
	if not chosen.is_empty():
		_java_chosen = chosen
		var ver := String(chosen.get("version", ""))
		if ver.is_empty():
			ver = "Java %d" % int(chosen.get("major", 0))
		_java_status.text = "%s ｜ %s" % [ver, String(chosen.get("source", ""))]
		_java_status.tooltip_text = String(chosen.get("home", ""))
	else:
		_java_chosen = {}
		var found := _java_major_list()
		if need <= 0:
			_java_status.text = "未检测到 Java（选版本后显示所需版本）" if found.is_empty() else "检测到 Java %s" % found
		else:
			_java_status.text = "需要 Java %d（检测到 %s）· 点「安装 Java」" % [need, found if not found.is_empty() else "无"]
		_java_status.tooltip_text = "安装路径：%s" % (root if not root.is_empty() else "未设置")
	UiFx.fade_swap(_java_status, 0.15)


func _java_major_list() -> String:
	var majors: Array[String] = []
	for c in _java_candidates:
		var m := str(int(c.get("major", 0)))
		if m != "0" and not majors.has(m):
			majors.append(m)
	majors.sort()
	return ", ".join(majors)


func _on_java_target_selected(path: String) -> void:
	_java_target_edit.text = path.replace("\\", "/").trim_suffix("/")
	_save_settings()
	_refresh_java_status()
	_status("Java 会装到：%s" % _java_install_root())


# ---------------------------------------------------------------- 加载器

## 加载器下拉：给「当前选中的版本」装 Fabric / Quilt / Forge
func _on_loader_kind_changed(index: int) -> void:
	_loader_kind = ["none", "fabric", "quilt", "forge", "neoforge"][clampi(index, 0, 4)]
	_loader_version_option.clear()
	_loader_versions.clear()
	# Fabric API 只在 Fabric 时出现
	if _fabric_api_option != null:
		_fabric_api_option.visible = _loader_kind == "fabric"
		if _loader_kind == "fabric":
			_fill_fabric_api_list()
	if _loader_kind == "none":
		return
	if _selected == null:
		_loader_version_option.add_item("先选版本", 0)
		return

	var base_id := _selected.id
	if _loader_kind == "neoforge":
		_status("正在获取 NeoForge 版本…")
		var nf: Array = await McLoaders.neoforge_versions_multi(self, base_id)
		for v in nf:
			_loader_versions.append(String(v))
	elif _loader_kind == "forge":
		_status("正在获取 Forge 版本…")
		var promos := await McLoaders.forge_promotions(self)
		for v in McLoaders.forge_versions_for(promos, base_id):
			_loader_versions.append(String(v))
	else:
		_status("正在获取 %s 版本…" % _loader_kind.capitalize())
		var list: Array = []
		if _loader_kind == "fabric":
			list = await McLoaders.fabric_loader_versions(self)
		else:
			list = await McLoaders.quilt_loader_versions(self)
		for item in list:
			_loader_versions.append(String((item as Dictionary).get("version", "")))
		if _loader_versions.size() > 30:
			_loader_versions.resize(30)

	for i in _loader_versions.size():
		_loader_version_option.add_item(String(_loader_versions[i]), i)
	if _loader_versions.is_empty():
		_loader_version_option.add_item("没有可用版本", 0)
		_status("没拿到 %s 的版本列表" % _loader_kind)
	else:
		_status("%s：%d 个版本可选" % [_loader_kind.capitalize(), _loader_versions.size()])


func _on_install_loader_pressed() -> void:

	if _loader_kind == "none":
		_status("先在「加载器」里选 Fabric / Quilt / Forge。")
		return
	if _selected == null:
		_status("先在左边选一个要装加载器的版本。")
		return
	var dir := _game_dir()
	if dir.is_empty():
		_status("先选游戏目录。")
		return
	var idx := _loader_version_option.selected
	if _loader_versions.is_empty():
		_loader_status.text = "先去「加载器」下拉选一个类型，等版本列表出来"
		_status(_loader_status.text)
		return
	if idx < 0 or idx >= _loader_versions.size():
		idx = 0
		_loader_version_option.select(0)
	var progress := func(text: String, ratio: float) -> void:
		_status(text)
		_loader_status.text = text
		_target_progress = ratio * 100.0

	var base_id := _selected.id
	var res: Dictionary = {}
	if _loader_kind == "forge":
		var java_exe := String(_java_chosen.get("exe", ""))
		if java_exe.is_empty():
			_loader_status.text = "Forge 安装器需要 Java，先装 Java"
			return
		res = await McLoaders.install_forge(self, java_exe, dir, base_id, String(_loader_versions[idx]), progress)
	elif _loader_kind == "neoforge":
		var java_exe2 := String(_java_chosen.get("exe", ""))
		if java_exe2.is_empty():
			_loader_status.text = "NeoForge 安装器需要 Java，先装 Java"
			return
		res = await McLoaders.install_neoforge(self, java_exe2, dir, base_id, String(_loader_versions[idx]), progress)
	else:
		res = await McLoaders.install_fabric_like(self, _effective_source(), base_id, String(_loader_versions[idx]), dir, _loader_kind, progress)

	if not bool(res.get("ok", false)):
		_loader_status.text = "安装失败：%s" % String(res.get("error", "未知错误"))
		_status(_loader_status.text)
		return

	var new_id := String(res.get("id", ""))
	# Fabric API（大部分 Fabric 模组都依赖）
	if _loader_kind == "fabric" and _fabric_api_option != null and _fabric_api_option.selected > 0:
		await _install_fabric_api(base_id)
	_loader_status.text = "已装 %s，正在补依赖库…" % new_id
	_status(_loader_status.text)

	# 原版如果用了自定义名字，加载器的 inheritsFrom 要跟着指向它
	var cname := _version_name_edit.text.strip_edges() if _version_name_edit != null else ""
	var parent_override := ""
	if not cname.is_empty() and DirAccess.dir_exists_absolute(dir.path_join("versions").path_join(cname)):
		parent_override = cname
	var plan := await InstallPlan.build(self, _effective_source(), InstallPlan.local_version(new_id), dir, "", parent_override)
	if not plan.is_valid():
		_loader_status.text = "生成清单失败：%s" % plan.error
		return
	_plan = plan
	_plan_key = "%s|%s|%s" % [new_id, _effective_source().id, dir]
	_set_busy(true)
	_set_ui_locked(true)
	_shown_progress = 0.0
	_target_progress = 0.0
	_queue.start(plan.files)
	_set_ui_locked(true)
	_loader_status.text = "正在下载 %d 个依赖文件…" % plan.files.size()

# ---------------------------------------------------------------- 目录校验 / 弹窗

## 代码构建弹窗，避免手改场景文件出错
func _build_dialogs() -> void:
	_notice_dialog = AcceptDialog.new()
	_notice_dialog.title = "提示"
	_notice_dialog.theme = theme
	_notice_dialog.min_size = Vector2i(460, 0)
	add_child(_notice_dialog)

	_create_dir_dialog = ConfirmationDialog.new()
	_create_dir_dialog.title = "创建目录"
	_create_dir_dialog.theme = theme
	_create_dir_dialog.ok_button_text = "创建"
	_create_dir_dialog.cancel_button_text = "取消"
	_create_dir_dialog.min_size = Vector2i(500, 0)
	_create_dir_dialog.confirmed.connect(_on_create_dir_confirmed)
	add_child(_create_dir_dialog)

	# Java 提示：纯文字，没有按钮，几秒后自动消失
	_java_notice = PopupPanel.new()
	_java_notice.theme = theme
	add_child(_java_notice)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_java_notice.add_child(margin)

	_java_notice_label = Label.new()
	_java_notice_label.custom_minimum_size = Vector2(430, 0)
	_java_notice_label.add_theme_color_override("font_color", Color("e0a33a"))
	margin.add_child(_java_notice_label)

func _show_notice(title: String, text: String) -> void:
	if _notice_dialog == null:
		return
	_notice_dialog.title = title
	_notice_dialog.dialog_text = text
	_notice_dialog.popup_centered()


## 输入/选择目录后校验：不合规就弹提示，不存在就问要不要创建。绝不替用户决定用哪个目录。
func _validate_game_dir_interactive() -> void:
	var raw := _path_edit.text.strip_edges().replace("\\", "/").trim_suffix("/")
	if raw.is_empty():
		return
	if not _looks_like_game_dir(raw):
		_show_notice("目录不合法", "「%s」不是一个具体文件夹。\n请选一个文件夹，例如 D:/MC。" % raw)
		return
	if FileAccess.file_exists(raw):
		_show_notice("不是文件夹", "「%s」是一个文件。" % raw)
		return
	if not DirAccess.dir_exists_absolute(raw):
		_pending_create_dir = raw
		_create_dir_dialog.dialog_text = "目录不存在：\n%s\n\n要现在创建吗？" % raw
		_create_dir_dialog.popup_centered()
		return
	_refresh_path_hint()


func _on_create_dir_confirmed() -> void:
	if _pending_create_dir.is_empty():
		return
	var target := _pending_create_dir
	_pending_create_dir = ""
	var err := DirAccess.make_dir_recursive_absolute(target)
	if err != OK and not DirAccess.dir_exists_absolute(target):
		_show_notice("创建失败", "无法创建：\n%s\n\n%s" % [target, error_string(err)])
		return
	_status("已创建目录：%s" % target)
	_refresh_path_hint()


# ---------------------------------------------------------------- 每帧动画

## 弹一下：轻微放大回弹 + 淡入（用于切换版本时的标题）
func _pop_in(node: Control) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.94, 0.94)
	node.modulate.a = 0.2
	var t := node.create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", Vector2.ONE, 0.3)
	t.tween_property(node, "modulate:a", 1.0, 0.2)


func _process(delta: float) -> void:
	# 进度条平滑推进，避免一格一格地跳
	if absf(_target_progress - _shown_progress) > 0.05:
		_shown_progress = move_toward(_shown_progress, _target_progress, maxf(delta * 120.0, 1.5))
		_progress_bar.value = _shown_progress

	# Java 提示：几秒后自动消失（没有按钮）
	if _java_notice != null and _java_notice.visible:
		_java_notice_timer -= delta
		if _java_notice_timer <= 0.0:
			_java_notice.hide()

	# 「加载中…」点点动画
	if _loading_versions:
		_dot_time += delta
		if _dot_time >= 0.35:
			_dot_time = 0.0
			_dot_index = (_dot_index + 1) % 3
			var dots := ".".repeat(_dot_index + 1)
			_version_count.text = "加载中" + dots
			if _version_list.item_count > 0:
				_version_list.set_item_text(0, "加载中" + dots)

# ---------------------------------------------------------------- 顶部导航 / Mod 页面
## 顶部导航：原版游戏 / Mod / 整合包 / 资源包 / 光影包 / 数据包（常驻，不会被页面盖住）
func _build_nav() -> void:
	var root: Node = get_node_or_null("Margin/Root")
	if root == null:
		return
	var bar := HBoxContainer.new()
	bar.name = "NavBar"
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	root.move_child(bar, 1)

	var specs := [
		["原版游戏", "原版游戏下载", func() -> void: _close_catalog()],
		["Mod", "浏览下载 Mod", func() -> void: _open_catalog("mod")],
		["整合包", "浏览下载整合包", func() -> void: _open_catalog("modpack")],
		["资源包", "浏览下载资源包", func() -> void: _open_catalog("resourcepack")],
		["光影包", "浏览下载光影包", func() -> void: _open_catalog("shader")],
		["数据包", "浏览下载数据包", func() -> void: _open_catalog("datapack")],
		["快速安装", "分步向导：游戏版本 → 支持器 → 附加内容 → 一键安装", func() -> void: _open_wizard()],
		["说明书", "路径须知、注意事项、常见问题", func() -> void: _open_help()],
	]

	for spec in specs:
		var b := Button.new()
		b.text = String(spec[0])
		b.tooltip_text = String(spec[1])
		b.pressed.connect(spec[2])
		bar.add_child(b)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(fill)

	var links := Button.new()
	links.text = "启动器下载"
	links.tooltip_text = "PCL / HMCL / Prism 等第三方启动器的官方地址"
	links.pressed.connect(_on_open_launcher_links)
	bar.add_child(links)


## 加载器那一行末尾加一个「Fabric API」勾选
func _build_loader_extra() -> void:
	var row: Node = get_node_or_null("Margin/Root/Body/RightPanel/RightMargin/RightScroll/RightBox/LoaderVerRow")
	if row == null:
		return
	_fabric_api_option = OptionButton.new()
	_fabric_api_option.tooltip_text = "顺便装的 Fabric API 版本（大部分 Fabric 模组都依赖它）"
	_fabric_api_option.custom_minimum_size = Vector2(150, 0)
	_fabric_api_option.add_item("不装 Fabric API", 0)
	_fabric_api_option.visible = false
	row.add_child(_fabric_api_option)


func _open_catalog(kind: String) -> void:
	GLog.info("打开浏览页：%s（目录 %s）" % [kind, _game_dir()])
	if _catalog == null:
		var page: Control = load("res://scripts/ui/catalog_page.gd").new()
		page.name = "CatalogPage"
		add_child(page)
		page.close_requested.connect(_close_catalog)
		_catalog = page
	UiFx.install(_catalog)
	_catalog.setup(kind, _game_dir())
	UiFx.page_in(_catalog)
	_catalog.show()
	_catalog.move_to_front()
	_hide_vanilla_header(true)


func _close_catalog() -> void:
	if _catalog != null:
		_catalog.hide()
	if _wizard != null:
		_wizard.hide()
	_hide_vanilla_header(false)


## 下载 Fabric API 到 <游戏目录>/mods
func _install_fabric_api(mc_id: String) -> void:
	_loader_status.text = "正在获取 Fabric API…"
	var version := await Modrinth.fabric_api_version(self, mc_id)
	if version.is_empty():
		_loader_status.text = "没找到 Fabric API 对应版本"
		return
	var dir := _game_dir().path_join("mods")
	var res := await Modrinth.download_version_file(self, version, dir)
	if bool(res.get("ok", false)):
		_loader_status.text = "Fabric API 已下载到 mods"
	else:
		_loader_status.text = "Fabric API 下载失败：%s" % String(res.get("error", "未知错误"))


## 第三方启动器官方地址（只做跳转，不代下、不打包）
func _on_open_launcher_links() -> void:
	if _links_dialog == null:
		_links_dialog = PopupPanel.new()
		_links_dialog.theme = theme
		add_child(_links_dialog)
		var m := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 18)
		_links_dialog.add_child(m)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(460, 0)
		box.add_theme_constant_override("separation", 8)
		m.add_child(box)
		var title := Label.new()
		title.text = "第三方启动器（免费开源/免费使用）"
		title.add_theme_font_size_override("font_size", 16)
		box.add_child(title)
		var tip := Label.new()
		tip.text = "只提供官方/GitHub 地址，点开会用系统浏览器打开。"
		tip.add_theme_font_size_override("font_size", 12)
		tip.add_theme_color_override("font_color", Color("98a0ae"))
		box.add_child(tip)
		var entries := [
			["PCL2（GitHub Releases）", "https://github.com/Hex-Dragon/PCL2"],
			["HMCL 官网", "https://hmcl.huangyuhui.net/"],
			["HMCL（GitHub）", "https://github.com/HMCL-dev/HMCL"],
			["Bakaxl", "https://www.bakaxl.com/"],
			["Prism Launcher 官网", "https://prismlauncher.org/"],
			["Prism Launcher（GitHub）", "https://github.com/PrismLauncher/PrismLauncher"],
			["PCL 官网", "https://meloong.com/"],
		]
		for e in entries:
			var b := Button.new()
			b.text = "%s  →  %s" % [String(e[0]), String(e[1])]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = String(e[1])
			b.pressed.connect(func() -> void: OS.shell_open(String(e[1])))
			box.add_child(b)
		var close := Button.new()
		close.text = "关闭"
		close.pressed.connect(func() -> void: _links_dialog.hide())
		box.add_child(close)
	_links_dialog.popup_centered()


## 目录页打开时，把原版那套「下载源 + 测速」收起来（设置按钮留着）
func _hide_vanilla_header(hide: bool) -> void:
	var header: Node = get_node_or_null("Margin/Root/Header")
	if header == null:
		return
	var idx := 0
	for c in header.get_children():
		var first := idx == 0
		idx += 1
		if first:
			continue
		if c is Button and (c as Button).text == "设置":
			continue
		if c is Control:
			(c as Control).visible = not hide

## 应用镜像设置：Java 下载源 + Mod 接口镜像
func _apply_mirror_settings() -> void:
	_java_mirror_index = _java_mirror_option.selected
	Modrinth.custom_base = _mod_mirror_edit.text.strip_edges()
	if _java_mirror_index == 1:
		_java_auto_prefer_official = false
	elif _java_mirror_index == 2:
		_java_auto_prefer_official = true
	else:
		_probe_java_mirrors()


## 自动模式：比一下清华和官方的响应，谁快用谁
func _probe_java_mirrors() -> void:
	var t0 := Time.get_ticks_msec()
	var tuna := await HttpUtil.fetch_bytes(self, "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/", 8.0, 0)
	var tuna_ms := Time.get_ticks_msec() - t0
	var t1 := Time.get_ticks_msec()
	var api := await HttpUtil.fetch_bytes(self, "https://api.adoptium.net/v3/info/available_releases", 8.0, 0)
	var api_ms := Time.get_ticks_msec() - t1
	_java_auto_prefer_official = bool(api.get("ok", false)) and (not bool(tuna.get("ok", false)) or api_ms + 300 < tuna_ms)
	_status("Java 源测速：清华 %d ms ｜ 官方 %d ms → 用%s" % [
		tuna_ms, api_ms, "官方" if _java_auto_prefer_official else "清华镜像",
	])


## 下载时锁住界面：除了暂停 / 取消，其他都不给点
func _set_ui_locked(locked: bool) -> void:
	_ui_locked = locked
	var keep: Array = []
	if _pause_button != null:
		keep.append(_pause_button)
	if _cancel_button != null:
		keep.append(_cancel_button)
	_lock_walk(self, locked, keep)


func _lock_walk(node: Node, locked: bool, keep: Array) -> void:
	for c in node.get_children():
		if keep.has(c):
			continue
		if c is BaseButton:
			if c.has_meta("always_enabled"):
				(c as BaseButton).disabled = false
			else:
				(c as BaseButton).disabled = locked
			_lock_walk(c, locked, keep)
			continue
		elif c is LineEdit:
			(c as LineEdit).editable = not locked
		elif c is ItemList:
			(c as ItemList).mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
		_lock_walk(c, locked, keep)

## 加载器装完自检：把落盘路径直接告诉用户，省得猜
func _verify_loader_install(failed_count: int) -> void:
	if _loader_pending_id.is_empty():
		return
	var vid := _loader_pending_id
	_loader_pending_id = ""
	var dir := _game_dir()
	if dir.is_empty():
		return
	var json_path := dir.path_join("versions").path_join(vid).path_join(vid + ".json")
	var parent := _parent_of_loader(vid)
	var parent_json := dir.path_join("versions").path_join(parent).path_join(parent + ".json")
	var lines := []
	lines.append("版本目录：%s" % dir.path_join("versions").path_join(vid))
	lines.append("版本 JSON：%s" % ("有" if FileAccess.file_exists(json_path) else "缺失！"))
	if not parent.is_empty():
		lines.append("父版本 %s：%s" % [parent, "有" if FileAccess.file_exists(parent_json) else "缺失！"])
	if failed_count > 0:
		lines.append("有 %d 个文件没下下来" % failed_count)
	_loader_status.text = "\n".join(lines)
	if FileAccess.file_exists(json_path):
		_status("加载器装好了：%s（用别的启动器时刷新一下版本列表就能看到）" % vid)
	else:
		_status("加载器没写成功，检查游戏目录是否可写：%s" % json_path)


## 从版本 JSON 里读父版本 id（读不到就空）
func _parent_of_loader(vid: String) -> String:
	var p := _game_dir().path_join("versions").path_join(vid).path_join(vid + ".json")
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	return String((parsed as Dictionary).get("inheritsFrom", ""))

## 拉 Fabric API 的可选版本，填进下拉框（第 0 项 = 不装）
func _fill_fabric_api_list() -> void:
	if _fabric_api_option == null or _selected == null:
		return
	_fabric_api_option.clear()
	_fabric_api_option.add_item("不装 Fabric API", 0)
	_fabric_api_list.clear()
	var list := await Modrinth.versions(self, "fabricapi", "", "")
	if list.is_empty():
		list = await Modrinth.versions(self, "fabric-api", _selected.id, "fabric")
	if list.is_empty():
		list = await Modrinth.versions(self, "fabric-api", "", "fabric")
	_fabric_api_list = list
	for i in mini(list.size(), 20):
		var v: Dictionary = list[i]
		_fabric_api_option.add_item("Fabric API %s" % String(v.get("version_number", "")), i + 1)
	_fabric_api_option.select(1 if _fabric_api_option.item_count > 1 else 0)

## 打开快速安装向导
func _open_wizard() -> void:
	GLog.info("打开快速安装向导（目录 %s）" % _game_dir())
	if _wizard == null:
		var page: Control = load("res://scripts/ui/quick_wizard.gd").new()
		page.name = "QuickWizard"
		page.install_requested.connect(_on_wizard_install)
		add_child(page)
		_wizard = page
	if _catalog != null:
		_catalog.hide()
	UiFx.install(_wizard)
	_wizard.call("setup", _game_dir(), _versions)
	UiFx.page_in(_wizard)
	_wizard.show()
	_wizard.move_to_front()
	_hide_vanilla_header(true)


## 向导点「安装」：按它的配置走完整流程
func _on_wizard_install(cfg: Dictionary) -> void:
	var dir := String(cfg.get("dir", ""))
	if dir.is_empty():
		return
	_path_edit.text = dir
	_on_path_changed()
	var vid := String(cfg.get("version", ""))
	for v in _versions:
		if v.id == vid:
			_selected = v
			break
	if _selected == null:
		_status("找不到版本 %s" % vid)
		return
	_version_name_edit.text = String(cfg.get("name", ""))
	_pending_extras = cfg.get("extras", [])
	_wizard_java_auto = bool(cfg.get("java_auto", true))
	var lk := String(cfg.get("loader", "不装"))
	_loader_kind = "none" if lk == "不装" else lk
	var lvi := ["none", "fabric", "quilt", "forge", "neoforge"].find(_loader_kind)
	_loader_option.select(maxi(lvi, 0))
	var lv := String(cfg.get("loader_ver", ""))
	if not lv.is_empty():
		_loader_versions = [lv]
		_loader_manual_edit.text = lv
	var target_id := _custom_version_id()
	if not target_id.is_empty() and DirAccess.dir_exists_absolute(_game_dir().path_join("versions").path_join(target_id)):
		GLog.error("同名版本已存在，无法安装：%s" % target_id)
		_status("已经有叫「%s」的版本了，换个名字或先删掉再装" % target_id)
		if _wizard != null:
			_wizard.call("_say", "已经有叫「%s」的版本，请回到第 2 步改名" % target_id)
			_wizard.call("_goto", 1)
		return
	GLog.info("快速安装开始：版本 %s，支持器 %s，附加内容 %d 项" % [vid, lk, _pending_extras.size()])
	if _wizard != null:
		_wizard.call("prepare_install", _wizard_java_auto, _pending_extras)
	_hide_vanilla_header(false)
	_status("快速安装：开始装 %s…" % vid)
	_on_start_pressed()


## 向导装的附加内容：全部落到游戏目录下
func _install_wizard_extras(extras: Array) -> void:
	var dir := _game_dir()
	if dir.is_empty() or extras.is_empty():
		return
	for item in extras:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var kind := String((item as Dictionary).get("kind", ""))
		var hit: Dictionary = (item as Dictionary).get("hit", {})
		var pid := String(hit.get("project_id", hit.get("slug", "")))
		if pid.is_empty():
			continue
		var target := dir.path_join("mods")
		match kind:
			"shader": target = dir.path_join("shaderpacks")
			"resourcepack": target = dir.path_join("resourcepacks")
			"datapack": target = dir.path_join("saves").path_join("datapacks")
		var list := await Modrinth.versions(self, pid, _selected.id if _selected != null else "", "")
		if list.is_empty():
			continue
		var label := "正在下载 %s…" % String(hit.get("title", ""))
		_loader_status.text = label
		if _wizard != null:
			_wizard.call("set_progress", label, float(_wizard_extras_done) / float(maxi(_wizard_extras_total, 1)))
		await Modrinth.download_version_file(self, list[0], target)
		if _wizard_extras_done < _extra_bars.size():
			(_extra_bars[_wizard_extras_done] as ProgressBar).value = 100.0
		if _wizard != null:
			_wizard.call("wiz_progress", "extra:%d" % _wizard_extras_done, 1.0, "已完成")
	_loader_status.text = "附加内容已全部装好"
	if _wizard != null:
		_wizard.call("reset_progress")

## 启动时检查默认目录（%APPDATA%/.minecraft）在不在
func _check_default_dir_on_start() -> void:
	if not _ask_on_start_enabled():
		GLog.info("启动检查：设置里已关闭，跳过")
		return
	var cur := _game_dir()
	GLog.info("启动检查：当前路径=[%s] 默认目录=[%s]" % [cur, _default_game_dir()])
	if not cur.is_empty() and DirAccess.dir_exists_absolute(cur):
		GLog.info("启动检查：当前路径已存在，跳过")
		return
	var def := _default_game_dir()
	if not DirAccess.dir_exists_absolute(def):
		GLog.info("启动检查：默认目录不存在，弹窗询问是否创建")
		_default_prompt_mode = "create_root"
		_set_default_dialog_text("没找到默认游戏目录：\n%s\n\n要现在创建吗？" % def)
		_show_default_dialog()
		return
	_path_edit.text = def
	_on_path_changed()
	_status("已自动填上默认目录：%s" % def)
	_missing_dirs.clear()
	for s in ["versions", "libraries", "assets", "mods", "runtime", "resourcepacks", "shaderpacks", "saves"]:
		if not DirAccess.dir_exists_absolute(def.path_join(s)):
			_missing_dirs.append(s)
	GLog.info("启动检查：默认目录存在，缺 %d 个子文件夹" % _missing_dirs.size())
	if not _missing_dirs.is_empty():
		_default_prompt_mode = "fix_subdirs"
		_set_default_dialog_text("默认目录里缺这些文件夹：\n%s\n\n要现在创建吗？" % ", ".join(_missing_dirs))
		_show_default_dialog()


## 真正把弹窗显示出来（延迟一帧，等窗口布局完成）
func _show_default_dialog() -> void:
	if _create_default_dialog == null:
		GLog.error("启动检查：弹窗对象不存在，无法显示")
		return
	_create_default_dialog.popup_centered_clamped(Vector2i(560, 0), 0.9)
func _on_create_default_confirmed() -> void:

	var def := _default_game_dir()
	if _default_prompt_mode == "fix_subdirs":
		for s in _missing_dirs:
			DirAccess.make_dir_recursive_absolute(def.path_join(s))
		_status("已补齐缺失的文件夹")
		_missing_dirs.clear()
		_create_default_dialog.hide()
		return
	_create_game_skeleton(def)
	_path_edit.text = def
	_on_path_changed()
	_save_settings()
	_status("已创建并设为默认目录：%s" % def)
	_create_default_dialog.hide()


func _on_create_default_custom() -> void:
	_create_default_dialog.hide()
	_on_browse_pressed()


## 「默认路径」按钮：回到设置里保存的那个目录
func _on_use_default_dir() -> void:
	_check_subdirs_hint()
	var def := _default_game_dir()
	_path_edit.text = def
	_on_path_changed()
	if not DirAccess.dir_exists_absolute(def):
		_status("默认目录还不存在，开始下载时会自动创建：%s" % def)

## 启动时发现默认目录不在 → 问是否创建（确认 / 取消 / 自定义路径）
func _build_default_dir_dialog() -> void:
	_create_default_dialog = PopupPanel.new()
	_create_default_dialog.theme = theme
	add_child(_create_default_dialog)

	var m := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	_create_default_dialog.add_child(m)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	m.add_child(box)

	_create_default_text = Label.new()
	_create_default_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_create_default_text.custom_minimum_size = Vector2(480, 0)
	box.add_child(_create_default_text)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(bar)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(func() -> void:
		_create_default_dialog.hide()
		_status("已跳过默认目录检查")
	)
	bar.add_child(cancel)

	var custom := Button.new()
	custom.text = "自定义路径"
	custom.pressed.connect(_on_create_default_custom)
	bar.add_child(custom)

	var ok := Button.new()
	ok.text = "确认创建"
	ok.pressed.connect(_on_create_default_confirmed)
	bar.add_child(ok)


## 设置弹窗正文
func _set_default_dialog_text(text: String) -> void:
	if _create_default_text != null:
		_create_default_text.text = text

func _ask_on_start_enabled() -> bool:
	return _ask_on_start_check == null or _ask_on_start_check.button_pressed

## 支持器 / Fabric API / 附加内容 各自独立的进度条
func _build_task_bars() -> void:
	var host: Node = get_node_or_null("Margin/Root/Body/RightPanel/RightMargin/RightScroll/RightBox")
	if host == null or _bar_loader != null:
		return
	var specs := [
		["支持器进度", "_bar_loader"],
		["Fabric API 进度", "_bar_fabric"],
		["附加内容进度", "_bar_extras"],
	]
	_extras_box = VBoxContainer.new()
	_extras_box.add_theme_constant_override("separation", 4)
	host.add_child(_extras_box)

	for spec in specs:
		var cap := Label.new()
		cap.text = String(spec[0])
		cap.add_theme_font_size_override("font_size", 12)
		cap.add_theme_color_override("font_color", Color("8b93a1"))
		host.add_child(cap)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 10)
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		host.add_child(bar)
		match String(spec[1]):
			"_bar_loader": _bar_loader = bar
			"_bar_fabric": _bar_fabric = bar
			"_bar_extras": _bar_extras = bar


func _set_task_progress(which: String, ratio: float) -> void:
	if _wizard != null:
		_wizard.call("wiz_progress", which, ratio, "%d%%" % int(ratio * 100.0))
	match which:
		"loader":
			if _bar_loader != null:
				_bar_loader.value = clampf(ratio * 100.0, 0.0, 100.0)
		"fabric":
			if _bar_fabric != null:
				_bar_fabric.value = clampf(ratio * 100.0, 0.0, 100.0)
		"extras":
			if _bar_extras != null:
				_bar_extras.value = clampf(ratio * 100.0, 0.0, 100.0)

## 路径等于默认目录时，在下面给一行绿字
func _update_default_hint() -> void:
	if _default_hint == null:
		_default_hint = Label.new()
		_default_hint.add_theme_font_size_override("font_size", 12)
		_default_hint.add_theme_color_override("font_color", Color("6fcf97"))
		_default_hint.visible = false
		var host: Node = get_node_or_null("Margin/Root/Body/RightPanel/RightMargin/RightScroll/RightBox")
		if host != null:
			host.add_child(_default_hint)
	var cur := _game_dir().replace("\\", "/").trim_suffix("/")
	var def := _default_game_dir().replace("\\", "/").trim_suffix("/")
	if not cur.is_empty() and not def.is_empty() and cur == def:
		_default_hint.text = "✓ 正在使用默认目录"
		_default_hint.visible = true
	else:
		_default_hint.visible = false

## 给每个附加内容建一条独立进度条（mod / 光影 / 资源包各一条）
func _prepare_extra_bars(extras: Array) -> void:
	_extra_bars.clear()
	if _extras_box == null:
		return
	for c in _extras_box.get_children():
		c.queue_free()
	for item in extras:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var hit: Dictionary = (item as Dictionary).get("hit", {})
		var kind := String((item as Dictionary).get("kind", ""))
		var title := String(hit.get("title", "?"))
		var cap := Label.new()
		cap.text = "%s：%s" % [_kind_cn(kind), title]
		cap.add_theme_font_size_override("font_size", 11)
		cap.add_theme_color_override("font_color", Color("8b93a1"))
		_extras_box.add_child(cap)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		_extras_box.add_child(bar)
		_extra_bars.append(bar)


func _kind_cn(kind: String) -> String:
	match kind:
		"mod": return "Mod"
		"shader": return "光影"
		"resourcepack": return "资源包"
		"datapack": return "数据包"
		_: return kind

## 建标准目录结构：versions / libraries / assets / mods / runtime / resourcepacks / saves / shaderpacks
func _create_game_skeleton(root: String) -> void:
	var subs := ["versions", "libraries", "assets", "mods", "runtime",
		"resourcepacks", "shaderpacks", "saves", "config", "logs"]
	for s in subs:
		DirAccess.make_dir_recursive_absolute(root.path_join(s))

## 使用说明书（路径须知 / 注意事项 / 常见问题）
func _open_help() -> void:
	GLog.info("打开使用说明书")
	if _help_dialog == null:
		_help_dialog = PopupPanel.new()
		_help_dialog.theme = theme
		add_child(_help_dialog)

		var m := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 18)
		_help_dialog.add_child(m)

		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(720, 0)
		box.add_theme_constant_override("separation", 10)
		m.add_child(box)

		var title := Label.new()
		title.text = "使用说明书"
		title.add_theme_font_size_override("font_size", 18)
		box.add_child(title)

		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(700, 460)
		scroll.horizontal_scroll_mode = 0
		box.add_child(scroll)

		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size = Vector2(680, 0)
		text.add_theme_font_size_override("normal_font_size", 13)
		text.text = _help_text()
		scroll.add_child(text)

		var bar := HBoxContainer.new()
		bar.alignment = BoxContainer.ALIGNMENT_END
		box.add_child(bar)
		var close := Button.new()
		close.text = "关闭"
		close.pressed.connect(func() -> void: _help_dialog.hide())
		bar.add_child(close)

	UiFx.install(_help_dialog)
	_help_dialog.popup_centered()
	var panel := _help_dialog.get_child(0) as Control
	if panel != null:
		UiFx.page_in(panel)


func _help_text() -> String:
	return "[b]一、各类文件装在哪[/b]\n" + \
		"· 原版游戏：<游戏目录>/versions、libraries、assets\n" + \
		"· Mod：<游戏目录>/mods（只放 .jar，不要解压）\n" + \
		"· 资源包：<游戏目录>/resourcepacks\n" + \
		"· 光影：<游戏目录>/shaderpacks（需要 Iris 或 OptiFine）\n" + \
		"· 数据包：<游戏目录>/saves/<存档名>/datapacks（只对那个存档生效）\n" + \
		"· 整合包：<游戏目录>/versions/<整合包版本>\n" + \
		"· Java：你指定的位置，或 <游戏目录>/runtime\n\n" + \
		"[b]二、注意事项[/b]\n" + \
		"1. Mod 必须与游戏版本、加载器类型同时匹配（Fabric 的不能放 Forge）。\n" + \
		"2. 同一个 Mod 不要放多个版本。\n" + \
		"3. 光影只放文件不装 Iris / OptiFine 不会生效。\n" + \
		"4. 数据包装进单个存档，不是全局生效。\n" + \
		"5. 安装大型整合包前先备份存档。\n" + \
		"6. 下载中的 .part 文件是临时文件，中断不会损坏正式文件。\n\n" + \
		"[b]三、常见问题[/b]\n" + \
		"[color=#9aa1ad]Q：版本列表加载失败？[/color]\n" + \
		"A：软件会在官方源与镜像之间自动切换；仍失败请检查网络或更换下载源。\n" + \
		"[color=#9aa1ad]Q：Java 检测不到？[/color]\n" + \
		"A：会扫描游戏目录、JAVA_HOME、PATH 和各盘常见位置；仍找不到可在右侧点「安装 Java」。\n" + \
		"[color=#9aa1ad]Q：Mod 装了不生效？[/color]\n" + \
		"A：检查版本与加载器是否匹配，确认 Fabric 用户已安装 Fabric API。\n" + \
		"[color=#9aa1ad]Q：整合包装完启动不了？[/color]\n" + \
		"A：Forge / NeoForge 整合包需要在「原版游戏」页按包内版本号手动安装加载器。\n" + \
		"[color=#9aa1ad]Q：下载很慢？[/color]\n" + \
		"A：在设置里更换下载源，或调整并发数（8~16 通常够用）。\n"

## 当前路径下缺不�少标准子文件夹 → 状态栏提示（含 saves）
func _check_subdirs_hint() -> void:
	var dir := _game_dir()
	if dir.is_empty():
		return
	var missing: Array[String] = []
	for s in ["versions", "libraries", "assets", "mods", "runtime",
			"resourcepacks", "shaderpacks", "saves"]:
		if not DirAccess.dir_exists_absolute(dir.path_join(s)):
			missing.append(s)
	if missing.is_empty():
		return
	_status("这个目录下还缺：%s（开始下载会自动补）" % ", ".join(missing))
	GLog.warn("目录缺子文件夹：%s" % ", ".join(missing))
