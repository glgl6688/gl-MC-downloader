extends Control
## Mod / 整合包 / 资源包 / 光影包 / 数据包 浏览下载页。
## 导航栏始终可见，本页只铺满导航下方的区域。
## 数据源：Modrinth 公开 API（允许第三方客户端，带 UA，低频调用）。

signal close_requested

const KIND_LABELS := {
	"mod": "Mod", "modpack": "整合包", "resourcepack": "资源包",
	"shader": "光影包", "datapack": "数据包",
}
const SOURCES := ["自动", "Modrinth"]
const LOADERS := ["全部", "fabric", "forge", "neoforge", "quilt"]
const SORT_LABELS := ["下载量", "相关度", "最近更新", "最新发布"]
const SORT_INDEX := ["downloads", "relevance", "updated", "newest"]

const CATEGORIES := {
	"mod": [
		["全部", ""], ["优化", "optimization"], ["科技", "technology"], ["魔法", "magic"],
		["世界生成", "worldgen"], ["冒险", "adventure"], ["装备", "equipment"], ["食物", "food"],
		["装饰", "decoration"], ["存储", "storage"], ["运输", "transportation"],
		["库", "library"], ["多人", "multiplayer"], ["实用", "utility"], ["怪物", "mobs"],
		["游戏机制", "game-mechanics"], ["经济", "economy"], ["管理", "management"],
		["小游戏", "minigame"], ["社交", "social"], ["诅咒", "cursed"],
	],
	"modpack": [
		["全部", ""], ["战斗", "combat"], ["空岛", "skyblock"], ["冒险", "adventure"],
		["科技", "technology"], ["魔法", "magic"], ["任务", "quests"], ["轻量", "lightweight"],
		["原味", "kitchen-sink"], ["多人", "multiplayer"], ["优化", "optimization"],
		["探索", "exploration"], ["科幻", "sci-fi"], ["硬核", "hardcore"],
		["挑战", "challenging"],
	],
	"resourcepack": [
		["全部", ""], ["写实", "realistic"], ["卡通", "cartoon"], ["中世纪", "medieval"],
		["现代", "modern"], ["简约", "simplistic"], ["主题", "themed"], ["字体", "fonts"],
		["界面", "gui"], ["音效", "audio"], ["模组支持", "modded"], ["微调", "tweaks"],
		["方块", "blocks"], ["生物", "entities"], ["物品", "items"], ["环境", "environment"],
		["核心光影", "core-shaders"],
	],
	"shader": [
		["全部", ""], ["写实", "realistic"], ["半写实", "semi-realistic"], ["卡通", "cartoon"],
		["奇幻", "fantasy"], ["原版风", "vanilla-like"], ["低配", "low"], ["中配", "medium"],
		["高配", "high"], ["极致", "potato"],
	],
	"datapack": [
		["全部", ""], ["冒险", "adventure"], ["实用", "utility"], ["世界生成", "worldgen"],
		["魔法", "magic"], ["科技", "technology"], ["怪物", "mobs"], ["小游戏", "minigame"],
		["库", "library"], ["装饰", "decoration"], ["游戏机制", "game-mechanics"],
	],
}

var kind := "mod"
var game_dir := ""

var _title: Label
var _search_edit: LineEdit
var _source_option: OptionButton
var _loader_option: OptionButton
var _category_option: OptionButton
var _version_edit: LineEdit
var _sort_option: OptionButton
var _refresh_btn: Button
var _list: ItemList
var _count: Label
var _icon: TextureRect
var _name: Label
var _meta: Label
var _desc: Label
var _version_option: OptionButton
var _path_edit: LineEdit
var _progress: ProgressBar
var _status: Label
var _spinner: Control
var _dir_dialog: FileDialog
var _deps_check: CheckBox
var _dl_button: Button
var _save_option: OptionButton
var _save_btn: Button
var _path_hint: Label
var _more_btn: Button
var _icon_busy := false
var _loaded_total := 0
var _last_query := ""
var _last_loader := ""
var _last_sort := "downloads"
var _last_category := ""
var _last_ver := ""

var _hits: Array = []
var _versions: Array = []
var _selected: Dictionary = {}
var _busy := false
var _token := 0
var _debounce := 0.0
var _icon_cache := {}


func _ready() -> void:
	theme = UiTheme.build()
	_build()
	_fit()
	if get_parent() != null:
		get_parent().resized.connect(_fit)
	_refresh_filters()
	_run_search()


func _fit() -> void:
	if get_parent() == null:
		return
	var top := 74.0
	var host: Node = get_parent().get_node_or_null("Margin/Root/Body")
	if host is Control:
		top = (host as Control).get_global_rect().position.y - 6.0
	position = Vector2(0, top)
	size = Vector2(get_parent().size.x, maxf(get_parent().size.y - top, 200.0))


func setup(p_kind: String, p_game_dir: String) -> void:
	var changed := p_kind != kind
	kind = p_kind
	game_dir = p_game_dir
	# 切换页面：停掉上一个页面还在跑的搜索/图标加载，别把结果带到新页面
	_token += 1
	_busy = false
	_icon_busy = false
	_spinner.visible = false
	_hits.clear()
	_list.clear()
	_title.text = "%s 下载" % String(KIND_LABELS.get(kind, "Mod"))
	_path_edit.text = _default_target()
	_refresh_filters()
	if _dl_button != null:
		_dl_button.text = "安装整合包" if kind == "modpack" else "下载"
	if _deps_check != null:
		_deps_check.visible = kind == "mod"
	if _save_btn != null:
		_save_btn.visible = kind == "datapack"
	if _save_option != null:
		_save_option.visible = kind == "datapack"
	if kind == "datapack" and _save_option != null:
		_refresh_saves()
	if _path_hint != null:
		_check_default_hint()
	if changed or _hits.is_empty():
		_run_search()
	_fit()


func _default_target() -> String:
	if game_dir.is_empty():
		return ""
	match kind:
		"resourcepack":
			return game_dir.path_join("resourcepacks")
		"shader":
			return game_dir.path_join("shaderpacks")
		"datapack":
			return game_dir.path_join("saves").path_join("datapacks")
		"modpack":
			return game_dir.path_join("versions")
		_:
			return game_dir.path_join("mods")


# ---------------------------------------------------------------- 界面

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.078431, 0.086275, 0.101961, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	root.add_child(row1)

	_title = Label.new()
	_title.text = "Mod 下载"
	_title.add_theme_font_size_override("font_size", 18)
	_title.custom_minimum_size = Vector2(140, 0)
	row1.add_child(_title)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "搜索名称（输入即搜）"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.tooltip_text = "输入关键词，停一下自动搜索"
	_search_edit.text_changed.connect(func(_t: String) -> void:
		_debounce = 0.35
	)
	_search_edit.text_submitted.connect(func(_t: String) -> void: _run_search())
	row1.add_child(_search_edit)

	_refresh_btn = Button.new()
	_refresh_btn.text = "刷新"
	_refresh_btn.tooltip_text = "按当前筛选重新搜索"
	_refresh_btn.pressed.connect(func() -> void: _run_search())
	row1.add_child(_refresh_btn)

	_more_btn = Button.new()
	_more_btn.text = "加载更多"
	_more_btn.tooltip_text = "再往下多拉 100 条（避免一次刷太多请求）"
	_more_btn.visible = false
	_more_btn.pressed.connect(_load_more)
	row1.add_child(_more_btn)

	var probe_btn := Button.new()
	probe_btn.text = "测速"
	probe_btn.tooltip_text = "测 Modrinth 接口响应"
	probe_btn.pressed.connect(_on_probe)
	row1.add_child(probe_btn)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	root.add_child(row2)

	_source_option = OptionButton.new()
	for i in SOURCES.size():
		_source_option.add_item(SOURCES[i], i)
	_source_option.tooltip_text = "下载源"
	_source_option.custom_minimum_size = Vector2(110, 0)
	_source_option.item_selected.connect(func(_i: int) -> void: _run_search())
	row2.add_child(_source_option)

	_loader_option = OptionButton.new()
	for i in LOADERS.size():
		_loader_option.add_item(LOADERS[i], i)
	_loader_option.tooltip_text = "按加载器筛选"
	_loader_option.custom_minimum_size = Vector2(105, 0)
	_loader_option.item_selected.connect(func(_i: int) -> void: _run_search())
	row2.add_child(_loader_option)

	_category_option = OptionButton.new()
	_category_option.tooltip_text = "按类型筛选"
	_category_option.custom_minimum_size = Vector2(120, 0)
	_category_option.item_selected.connect(func(_i: int) -> void: _run_search())
	row2.add_child(_category_option)

	_version_edit = LineEdit.new()
	_version_edit.placeholder_text = "游戏版本，如 1.21.1"
	_version_edit.custom_minimum_size = Vector2(170, 0)
	_version_edit.tooltip_text = "手输游戏版本，填了只显示支持它的；留空不限"
	_version_edit.text_submitted.connect(func(_t: String) -> void: _run_search())
	row2.add_child(_version_edit)

	_sort_option = OptionButton.new()
	for i in SORT_LABELS.size():
		_sort_option.add_item(SORT_LABELS[i], i)
	_sort_option.select(0)
	_sort_option.tooltip_text = "排序"
	_sort_option.custom_minimum_size = Vector2(105, 0)
	_sort_option.item_selected.connect(func(_i: int) -> void: _run_search())
	row2.add_child(_sort_option)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(spacer)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)

	var left := PanelContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.7
	body.add_child(left)

	var lm := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		lm.add_theme_constant_override("margin_" + side, 8)
	left.add_child(lm)

	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 6)
	lm.add_child(lbox)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(26, 26)
	_list.add_theme_font_size_override("font_size", 15)
	_list.item_selected.connect(_on_item_selected)
	lbox.add_child(_list)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 12)
	_count.add_theme_color_override("font_color", Color("98a0ae"))
	_count.text = "共 0 个"
	lbox.add_child(_count)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(370, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	var rm := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		rm.add_theme_constant_override("margin_" + side, 12)
	right.add_child(rm)

	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 8)
	rm.add_child(rbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	rbox.add_child(head)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(56, 56)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_icon)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)

	_name = Label.new()
	_name.text = "未选择"
	_name.add_theme_font_size_override("font_size", 17)
	names.add_child(_name)

	_meta = Label.new()
	_meta.add_theme_font_size_override("font_size", 12)
	_meta.add_theme_color_override("font_color", Color("98a0ae"))
	names.add_child(_meta)

	_desc = Label.new()
	_desc.custom_minimum_size = Vector2(0, 40)
	_desc.clip_text = true
	_desc.add_theme_font_size_override("font_size", 12)
	_desc.add_theme_color_override("font_color", Color("98a0ae"))
	rbox.add_child(_desc)

	rbox.add_child(HSeparator.new())

	var vcap := Label.new()
	vcap.text = "适配版本（游戏版本 ｜ 加载器）"
	vcap.add_theme_font_size_override("font_size", 12)
	vcap.add_theme_color_override("font_color", Color("98a0ae"))
	rbox.add_child(vcap)

	_version_option = OptionButton.new()
	_version_option.tooltip_text = "选要下载的版本"
	rbox.add_child(_version_option)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	rbox.add_child(save_row)

	_save_btn = Button.new()
	_save_btn.text = "选择存档"
	_save_btn.tooltip_text = "数据包装进具体存档，先选存档"
	_save_btn.visible = false
	_save_btn.pressed.connect(_refresh_saves)
	save_row.add_child(_save_btn)

	_save_option = OptionButton.new()
	_save_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_option.visible = false
	_save_option.tooltip_text = "默认目录里检测到的存档"
	_save_option.item_selected.connect(_on_save_selected)
	save_row.add_child(_save_option)

	var pcap := Label.new()
	pcap.text = "下载到"
	pcap.add_theme_font_size_override("font_size", 12)
	pcap.add_theme_color_override("font_color", Color("98a0ae"))
	rbox.add_child(pcap)

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	rbox.add_child(prow)

	_path_edit = LineEdit.new()
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.placeholder_text = "下载目录"
	prow.add_child(_path_edit)

	var browse := Button.new()
	browse.text = "浏览…"
	browse.tooltip_text = "选下载目录"
	browse.pressed.connect(_on_browse)
	prow.add_child(browse)

	_path_hint = Label.new()
	_path_hint.add_theme_font_size_override("font_size", 12)
	_path_hint.add_theme_color_override("font_color", Color("6fcf97"))
	_path_hint.visible = false
	rbox.add_child(_path_hint)

	_deps_check = CheckBox.new()
	_deps_check.text = "连同必需依赖一起下载"
	_deps_check.button_pressed = true
	_deps_check.tooltip_text = "递归解析必需依赖，一起下载"
	rbox.add_child(_deps_check)

	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	rbox.add_child(drow)

	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(16, 16)
	_spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spinner.visible = false
	_spinner.set_script(load("res://scripts/ui/spinner.gd"))
	drow.add_child(_spinner)

	_dl_button = Button.new()
	_dl_button.text = "下载"
	_dl_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dl_button.tooltip_text = "下载到上面选的目录"
	_dl_button.pressed.connect(_on_download)
	drow.add_child(_dl_button)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 12)
	_progress.max_value = 100.0
	_progress.value = 0.0
	_progress.show_percentage = false
	rbox.add_child(_progress)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rbox.add_child(fill)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color("98a0ae"))
	rbox.add_child(_status)

	_dir_dialog = FileDialog.new()
	_dir_dialog.title = "选择下载目录"
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.use_native_dialog = true
	_dir_dialog.dir_selected.connect(func(p: String) -> void: _path_edit.text = p.replace("\\", "/"))
	add_child(_dir_dialog)


func _refresh_filters() -> void:
	_loader_option.disabled = kind == "resourcepack" or kind == "shader" or kind == "datapack"
	_category_option.clear()
	var cats: Array = CATEGORIES.get(kind, [["全部", ""]])
	for i in cats.size():
		var c: Array = cats[i]
		_category_option.add_item(String(c[0]), i)
	_category_option.select(0)


func _on_browse() -> void:
	var start := _path_edit.text.strip_edges()
	if not start.is_empty() and DirAccess.dir_exists_absolute(start):
		_dir_dialog.current_dir = start
	_dir_dialog.popup_centered()


# ---------------------------------------------------------------- 搜索

func _say(text: String) -> void:
	if _status != null:
		_status.text = text


func _process(delta: float) -> void:
	if _debounce > 0.0:
		_debounce -= delta
		if _debounce <= 0.0:
			_run_search()


func _run_search() -> void:
	if _busy:
		return
	_token += 1
	var token := _token
	_busy = true
	_spinner.visible = true
	_list.clear()
	_hits.clear()
	_count.text = "搜索中…"
	_say("正在搜索…")

	var raw_loader: String = LOADERS[clampi(_loader_option.selected, 0, LOADERS.size() - 1)]
	var loader := "" if raw_loader == "全部" else raw_loader
	var cats: Array = CATEGORIES.get(kind, [["全部", ""]])
	var cat_index: int = clampi(_category_option.selected, 0, maxi(cats.size() - 1, 0))
	var cat_pair: Array = cats[cat_index]
	var category := String(cat_pair[1])
	var sort_key: String = SORT_INDEX[clampi(_sort_option.selected, 0, SORT_INDEX.size() - 1)]
	var ver := _version_edit.text.strip_edges()

	var query := _search_edit.text.strip_edges()
	var only_title := Modrinth.search_mode == 0
	if Modrinth.search_mode == 2 and not query.is_empty():
		_say("正在翻译关键词…")
		query = await Modrinth.translate_to_english(self, query)

	_last_query = query
	_last_loader = loader
	_last_sort = sort_key
	_last_category = category
	_last_ver = ver
	var page_res := await Modrinth.search(self, query, kind, loader, sort_key, 100, 0, category, ver)
	var collected: Array = []
	var ok := bool(page_res.get("ok", false))
	var err_text := String(page_res.get("error", "未知错误"))
	var total := 0
	if ok:
		collected = page_res.get("hits", [])
		total = int(page_res.get("total", collected.size()))
		_loaded_total = collected.size()

	_spinner.visible = false
	_busy = false
	if token != _token:
		return
	if not ok:
		_count.text = "搜索失败"
		_say("搜索失败：%s" % err_text)
		return

	_hits = collected
	if only_title and not query.is_empty():
		var filtered: Array = []
		var needle := query.to_lower()
		for h in _hits:
			if typeof(h) == TYPE_DICTIONARY and String((h as Dictionary).get("title", "")).to_lower().contains(needle):
				filtered.append(h)
		_hits = filtered

	_hits = []
	_append_hits(collected)
	_count.text = "共 %d 个（已显示 %d 个）" % [maxi(total, _hits.size()), _hits.size()]
	_more_btn.visible = _hits.size() < total
	_say("")
	_load_icons(token)
	_load_all_icons(token)


## 图标：缓存 + 并发，先拉前 40 个
func _load_icons(token: int) -> void:
	var limit := mini(_hits.size(), mini(_list.item_count, 20))
	for i in limit:
		if token != _token:
			return
		var hit: Dictionary = _hits[i]
		var url := String(hit.get("icon_url", ""))
		if url.is_empty():
			continue
		if _icon_cache.has(url):
			_list.set_item_icon(i, _icon_cache[url])
			continue
		_fetch_into_list(i, url, token)


func _fetch_into_list(index: int, url: String, token: int) -> void:
	await get_tree().create_timer(0.02 * float(index % 8)).timeout
	if token != _token:
		return
	var tex := await _fetch_icon(url)
	if tex == null or token != _token:
		return
	if index < _list.item_count:
		_list.set_item_icon(index, tex)


func _fetch_icon(url: String) -> Texture2D:
	if _icon_cache.has(url):
		return _icon_cache[url]
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var err := http.request(url, PackedStringArray(["User-Agent: gl-downloader/0.3"]))
	if err != OK:
		http.queue_free()
		return null
	var res: Array = await http.request_completed
	http.queue_free()
	if res.size() < 4:
		return null
	if int(res[1]) != 200:
		return null
	var body: PackedByteArray = res[3]
	if body.size() < 12:
		return null

	# 先看文件头再解码，免得拿非图片数据硬解、刷一堆 png 报错
	var img := Image.new()
	var e := ERR_FILE_UNRECOGNIZED
	if body[0] == 0x89 and body[1] == 0x50 and body[2] == 0x4E and body[3] == 0x47:
		e = img.load_png_from_buffer(body)
	elif body[0] == 0xFF and body[1] == 0xD8:
		e = img.load_jpg_from_buffer(body)
	elif body[0] == 0x52 and body[1] == 0x49 and body[8] == 0x57 and body[9] == 0x45:
		e = img.load_webp_from_buffer(body)
	if e != OK:
		return null
	if img.get_width() > 96 or img.get_height() > 96:
		img.resize(64, 64, Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)
	# 缓存上限，长列表/多次搜索不会把内存吃满
	if _icon_cache.size() >= 80:
		_icon_cache.clear()
	_icon_cache[url] = tex
	return tex


func _pretty(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (float(n) / 1000000.0)
	if n >= 1000:
		return "%.1fk" % (float(n) / 1000.0)
	return str(n)


# ---------------------------------------------------------------- 详情

func _on_item_selected(index: int) -> void:
	var meta: Variant = _list.get_item_metadata(index)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	_selected = meta
	_name.text = String(_selected.get("title", "?"))
	_meta.text = "%s ｜ %s 下载 ｜ %s 关注" % [
		String(_selected.get("author", "")),
		_pretty(int(_selected.get("downloads", 0))),
		_pretty(int(_selected.get("follows", 0))),
	]
	_desc.text = String(_selected.get("description", ""))
	_desc.tooltip_text = _desc.text

	var icon_url := String(_selected.get("icon_url", ""))
	_icon.texture = null
	if not icon_url.is_empty():
		_icon.texture = await _fetch_icon(icon_url)

	_refresh_versions()


func _refresh_versions() -> void:
	if _selected.is_empty():
		return
	_version_option.clear()
	_versions.clear()
	var pid := String(_selected.get("project_id", _selected.get("slug", "")))
	if pid.is_empty():
		return
	_say("正在拉版本列表…")
	_spinner.visible = true
	var raw_loader: String = LOADERS[clampi(_loader_option.selected, 0, LOADERS.size() - 1)]
	var loader := "" if raw_loader == "全部" else raw_loader
	var ver := _version_edit.text.strip_edges()
	var list := await Modrinth.versions(self, pid, ver, loader)
	_spinner.visible = false

	# 服务器筛选不一定生效，本地再按游戏版本过滤一遍
	if not ver.is_empty():
		var keep: Array = []
		for v in list:
			if typeof(v) != TYPE_DICTIONARY:
				continue
			var gvs: Array = (v as Dictionary).get("game_versions", [])
			if gvs.has(ver):
				keep.append(v)
		list = keep

	list.sort_custom(func(a: Variant, b: Variant) -> bool:
		return String((a as Dictionary).get("date_published", "")) > String((b as Dictionary).get("date_published", ""))
	)
	if list.is_empty():
		_say("没拉到版本列表，试试清空版本或加载器筛选")
		return
	_versions = list
	for i in _versions.size():
		var v: Dictionary = _versions[i]
		var gv: Array = v.get("game_versions", [])
		var ld: Array = v.get("loaders", [])
		var gv_text := ", ".join(gv) if gv.size() <= 3 else "%s 等 %d 个" % [", ".join(gv.slice(0, 3)), gv.size()]
		_version_option.add_item("%s ｜ %s ｜ %s" % [
			String(v.get("version_number", "")), gv_text, ", ".join(ld),
		], i)
	_say("共 %d 个版本" % _versions.size())


# ---------------------------------------------------------------- 下载

func _on_download() -> void:
	var idx := _version_option.selected
	if idx < 0 or idx >= _versions.size():
		_say("先挑个版本")
		return
	var dir := _path_edit.text.strip_edges().replace("\\", "/").trim_suffix("/")
	if dir.is_empty():
		_say("先选个下载目录吧")
		return
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		if not DirAccess.dir_exists_absolute(dir):
			_say("这个目录建不出来")
			return

	var version: Dictionary = _versions[idx]
	var raw_loader: String = LOADERS[clampi(_loader_option.selected, 0, LOADERS.size() - 1)]
	var loader := "" if raw_loader == "全部" else raw_loader
	var ver := _version_edit.text.strip_edges()

	if kind == "modpack":
		await _install_modpack(version, dir)
		return

	_spinner.visible = true
	_set_locked(true)
	_progress.value = 0.0
	_status.text = "正在下载…"
	var progress := func(text: String, ratio: float) -> void:
		_status.text = "%s  %d%%" % [text, int(ratio * 100.0)]
		if _progress != null:
			_progress.value = ratio * 100.0
		GLog.info("[%s] 下载 %s %d%%" % [String(KIND_LABELS.get(kind, kind)), text, int(ratio * 100.0)])

	var res := await Modrinth.download_version_file(self, version, dir, progress)
	if not bool(res.get("ok", false)):
		_spinner.visible = false
		_set_locked(false)
		_status.text = "下载失败：%s" % String(res.get("error", "未知错误"))
		return
	_status.text = "已下载到：%s" % String(res.get("path", ""))
	_progress.value = 100.0
	await get_tree().create_timer(1.2).timeout
	_progress.value = 0.0

	# 必需依赖
	if _deps_check != null and _deps_check.button_pressed:
		_status.text = "正在解析依赖…"
		var deps := await Modrinth.resolve_dependencies(self, version, ver, loader)
		if not deps.is_empty():
			var dep_res := await Modrinth.download_versions(self, deps, dir, progress)
			if bool(dep_res.get("ok", false)):
				_status.text = "已下载主体 + %d 个依赖" % (deps as Array).size()
			else:
				_status.text = "主体已下载，有 %d 个依赖失败" % (dep_res.get("failed", []) as Array).size()
	_spinner.visible = false
	_set_locked(false)


## 整合包安装：下 .mrpack → 解 overrides → 按 index 拉文件 → 装加载器
func _install_modpack(version: Dictionary, dir: String) -> void:
	var slug := String(_selected.get("slug", "pack"))
	_spinner.visible = true
	_set_locked(true)
	_progress.value = 0.0
	_status.text = "正在下载整合包文件…"
	var progress := func(text: String, ratio: float) -> void:
		_status.text = "%s  %d%%" % [text, int(ratio * 100.0)]
		if _progress != null:
			_progress.value = ratio * 100.0

	var dl := await Modrinth.download_version_file(self, version, dir, progress)
	if not bool(dl.get("ok", false)):
		_spinner.visible = false
		_set_locked(false)
		_status.text = "整合包下载失败：%s" % String(dl.get("error", "未知错误"))
		return

	var target := dir.path_join(slug)
	_status.text = "正在解包并下载里面的文件…"
	var res := await ModpackInstaller.install(self, String(dl.get("path", "")), target, progress)
	if not bool(res.get("ok", false)):
		_spinner.visible = false
		_set_locked(false)
		_status.text = "安装失败：%s" % String(res.get("error", "未知错误"))
		return

	var loader := String(res.get("loader", ""))
	var lv := String(res.get("loader_version", ""))
	var mc := String(res.get("minecraft", ""))
	_spinner.visible = false
	_set_locked(false)
	if loader.is_empty() or lv.is_empty():
		_status.text = "整合包已展开到 %s（index 里没写加载器版本）" % target
		return
	if game_dir.is_empty():
		_status.text = "整合包已展开到 %s；加载器 %s %s 要先选游戏目录才能装" % [target, loader, lv]
		return
	if loader != "fabric" and loader != "quilt":
		_status.text = "整合包已展开到 %s\n加载器 %s %s 请到「原版游戏」页选 %s 再装" % [target, loader, lv, mc]
		return

	_status.text = "正在安装加载器 %s %s…" % [loader, lv]
	_spinner.visible = true
	var src := DownloadSource.create(DownloadSource.ID_AUTO)
	var lres := await McLoaders.install_fabric_like(self, src, mc, lv, game_dir, loader, progress)
	_spinner.visible = false
	if bool(lres.get("ok", false)):
		_status.text = "整合包装好了：%s\n目录：%s\n加载器：%s %s" % [String(_selected.get("title", "")), target, loader, lv]
	else:
		_status.text = "整合包已展开到 %s，加载器安装失败：%s" % [target, String(lres.get("error", ""))]


## 下载时把本页控件锁住（没有暂停/取消，所以全锁）
func _set_locked(locked: bool) -> void:
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	for n in [_search_edit, _source_option, _loader_option, _category_option, _version_edit, _sort_option, _refresh_btn, _version_option, _path_edit, _dl_button, _deps_check]:
		if n == null:
			continue
		if n is BaseButton:
			(n as BaseButton).disabled = locked
		elif n is LineEdit:
			(n as LineEdit).editable = not locked


func _on_probe() -> void:
	_count.text = "测速中…"
	_say("正在测速…")
	var r := await Modrinth.probe(self)
	var src_name := "自定义镜像" if Modrinth.is_custom() else "Modrinth"
	var text := ("%s 响应 %.0f ms" % [src_name, float(r.get("seconds", 0.0)) * 1000.0]) if bool(r.get("ok", false)) else ("%s 连不上：%s" % [src_name, String(r.get("error", "未知错误"))])
	_count.text = text
	_say(text)

## 把一批 hits 追加到列表（先在第一批就显示，不用等全拉完）
func _append_hits(rows: Array) -> void:
	for h in rows:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		var hit: Dictionary = h
		var idx := _list.add_item("%s    ·    %s 下载    ·    %s" % [
			String(hit.get("title", "?")),
			_pretty(int(hit.get("downloads", 0))),
			String(hit.get("author", "")),
		])
		_list.set_item_metadata(idx, hit)
		_hits.append(hit)


## 再拉 100 条
func _load_more() -> void:
	if _busy:
		return
	_busy = true
	_more_btn.disabled = true
	_say("正在加载更多…")
	var res := await Modrinth.search(self, _last_query, kind, _last_loader, _last_sort, 100, _loaded_total, _last_category, _last_ver)
	_busy = false
	_more_btn.disabled = false
	if not bool(res.get("ok", false)):
		_say("加载失败：%s" % String(res.get("error", "未知错误")))
		return
	var got: Array = res.get("hits", [])
	_append_hits(got)
	_loaded_total += got.size()
	_count.text = "共 %d 个（已显示 %d 个）" % [maxi(int(res.get("total", _loaded_total)), _loaded_total), _loaded_total]
	_more_btn.visible = _loaded_total < int(res.get("total", _loaded_total))
	_say("")
	_load_icons(_token)


## 后台把所有条目的图标都补上（限速，避免一次性打几百个请求）
func _load_all_icons(token: int) -> void:
	if _icon_busy:
		return
	_icon_busy = true
	for i in mini(_hits.size(), 60):
		if token != _token:
			break
		var hit: Dictionary = _hits[i]
		var url := String(hit.get("icon_url", ""))
		if url.is_empty():
			continue
		if i < _list.item_count and _list.get_item_icon(i) != null:
			continue
		var tex: Texture2D = _icon_cache.get(url, null)
		if tex == null:
			tex = await _fetch_icon(url)
			await get_tree().create_timer(0.03).timeout
		if tex != null and i < _list.item_count and token == _token:
			_list.set_item_icon(i, tex)
	_icon_busy = false

## 扫默认目录里的存档（含 level.dat 的文件夹）
func _refresh_saves() -> void:
	_save_option.clear()
	var saves_dir := game_dir.path_join("saves")
	var d := DirAccess.open(saves_dir)
	if d == null:
		_path_hint.visible = true
		_path_hint.text = "默认目录里还没有存档：%s" % saves_dir
		return
	d.list_dir_begin()
	var n := d.get_next()
	var count := 0
	while n != "":
		if d.current_is_dir() and FileAccess.file_exists(saves_dir.path_join(n).path_join("level.dat")):
			_save_option.add_item(n, count)
			_save_option.set_item_metadata(count, n)
			count += 1
		n = d.get_next()
	d.list_dir_end()
	if count == 0:
		_path_hint.visible = true
		_path_hint.text = "默认目录里没检测到存档"
		return
	_save_option.select(0)
	_on_save_selected(0)


func _on_save_selected(index: int) -> void:
	var name := String(_save_option.get_item_metadata(index))
	if name.is_empty():
		return
	_path_edit.text = game_dir.path_join("saves").path_join(name).path_join("datapacks")
	_check_default_hint()


## 选了默认路径就给一行绿字提示
func _check_default_hint() -> void:
	if _path_hint == null:
		return
	var cur := _path_edit.text.strip_edges().replace("\\", "/").trim_suffix("/")
	var def := _default_target().replace("\\", "/").trim_suffix("/")
	if not cur.is_empty() and not def.is_empty() and cur == def:
		_path_hint.visible = true
		_path_hint.text = "✓ 正在使用默认路径"
	else:
		_path_hint.visible = false
