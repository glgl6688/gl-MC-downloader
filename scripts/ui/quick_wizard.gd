extends Control
## 快速安装向导：目录 → 游戏版本 → Mod 支持器 → 附加内容 → 确认安装。
## 数据来自 Modrinth 公开 API；版本清单由主页面传入，不重复请求。

signal close_requested
signal install_requested(cfg: Dictionary)

const LOADERS := ["不装", "fabric", "quilt", "forge", "neoforge"]
const KINDS := [
	["mod", "Mod"], ["shader", "光影"], ["resourcepack", "资源包"],
]
const SORTS := ["下载量", "最近更新", "最新发布"]
const SORT_KEYS := ["downloads", "updated", "newest"]
const KIND_CN := {"mod": "Mod", "shader": "光影", "resourcepack": "资源包", "datapack": "数据包"}
const MOD_CATS := [
	["全部类型", ""], ["优化", "optimization"], ["科技", "technology"], ["魔法", "magic"],
	["世界生成", "worldgen"], ["冒险", "adventure"], ["装备", "equipment"], ["食物", "food"],
	["装饰", "decoration"], ["存储", "storage"], ["运输", "transportation"],
	["库", "library"], ["多人", "multiplayer"], ["实用", "utility"], ["怪物", "mobs"],
	["游戏机制", "game-mechanics"], ["经济", "economy"], ["管理", "management"],
	["小游戏", "minigame"], ["社交", "social"], ["诅咒", "cursed"],
]

var step := 0
var game_dir := ""

var _release_ids: Array[String] = []
var _other_ids: Array[String] = []
var _all_versions: Array = []
var _ver_filter: OptionButton
const VER_FILTERS := ["全部版本", "正式版", "快照", "愚人节", "远古版本"]

var _step_label: Label
var _content: VBoxContainer
var _next_btn: Button

# 各步状态（离开那一步后控件会释放，所以必须存下来）
var _chosen_mc := ""
var _chosen_name := ""
var _chosen_loader := "不装"
var _chosen_loader_ver := ""
var _versions: Array = []
var _loader_versions: Array = []
var _picked_versions := {}
var _chosen_items := {}
var _snapshot: Array = []      # 离开组件页时的已选快照

# 控件
var _path_edit: LineEdit
var _dir_dialog: FileDialog
var _ver_option: OptionButton
var _name_edit: LineEdit
var _loader_option: OptionButton
var _loader_ver_option: OptionButton
var _pick_search: LineEdit
var _pick_sort: OptionButton
var _mod_cat: OptionButton
var _wiz_bar: ProgressBar
var _wiz_status: Label
var _pick_lists := {}
var _java_check: CheckBox

# 弹窗
var _pick_dialog: PopupPanel
var _ver_dialog: PopupPanel
var _ver_dropdown: OptionButton
var _ver_list: Array = []
var _ver_target := {}
var _install_box: VBoxContainer
var _install_bars: Array = []
var _prog_extras: Array = []
var _prog_has_java := false

var _step_token := 0
var _busy := false


func _process(_delta: float) -> void:
	if step == 5 and not _install_bars.is_empty():
		_sync_from_page()


func _ready() -> void:
	theme = UiTheme.build()
	_build()
	_fit()
	if get_parent() != null:
		get_parent().resized.connect(_fit)
	_goto(0)


func _fit() -> void:
	if get_parent() == null:
		return
	var top := 74.0
	var host: Node = get_parent().get_node_or_null("Margin/Root/Body")
	if host is Control:
		top = (host as Control).get_global_rect().position.y - 6.0
	position = Vector2(0, top)
	size = Vector2(get_parent().size.x, maxf(get_parent().size.y - top, 200.0))


func setup(p_game_dir: String, p_versions: Array) -> void:
	game_dir = p_game_dir
	_release_ids.clear()
	_other_ids.clear()
	_all_versions = p_versions.duplicate()
	for v in p_versions:
		var mv: McVersion = v as McVersion
		if mv == null:
			continue
		if mv.is_release():
			_release_ids.append(mv.id)
		else:
			_other_ids.append(mv.id)
	_goto(0)


# ---------------------------------------------------------------- 骨架

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.078431, 0.086275, 0.101961, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)

	var t := Label.new()
	t.text = "快速安装"
	t.add_theme_font_size_override("font_size", 20)
	head.add_child(t)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 13)
	_step_label.add_theme_color_override("font_color", Color("98a0ae"))
	_step_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_step_label)

	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	root.add_child(_content)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	root.add_child(bar)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.tooltip_text = "回到第一步"
	cancel.pressed.connect(func() -> void: _goto(0))
	bar.add_child(cancel)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(fill)

	_next_btn = Button.new()
	_next_btn.text = "开始"
	_next_btn.custom_minimum_size = Vector2(120, 0)
	_next_btn.pressed.connect(_on_next)
	bar.add_child(_next_btn)

	_dir_dialog = FileDialog.new()
	_dir_dialog.title = "选择安装目录"
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.use_native_dialog = true
	_dir_dialog.dir_selected.connect(func(p: String) -> void: _path_edit.text = p.replace("\\", "/"))
	add_child(_dir_dialog)


func _clear() -> void:
	_pick_lists.clear()
	for c in _content.get_children():
		c.queue_free()


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("98a0ae"))
	l.add_theme_font_size_override("font_size", 13)
	return l


func _warn(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("e0a33a"))
	return l


func _goto(n: int) -> void:
	step = n
	_step_token += 1
	_clear()
	var titles := ["第 1 步 · 选目录", "第 2 步 · 游戏版本", "第 3 步 · Mod 支持器",
		"第 4 步 · 附加内容", "第 5 步 · 确认安装", "安装中"]
	_step_label.text = titles[clampi(n, 0, 5)]
	_next_btn.disabled = false
	_next_btn.text = "开始" if n == 0 else ("安装" if n == 4 else "下一步")
	match n:
		0: _build_step0()
		1: _build_step1()
		2: _build_step2()
		3: _build_step3()
		4: _build_step4()
		5: _build_step5()


# ---------------------------------------------------------------- 第 1 步

func _build_step0() -> void:
	_content.add_child(_caption("装到哪个目录（会在里面建 versions / libraries / mods …）"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	_path_edit = LineEdit.new()
	_path_edit.text = game_dir
	_path_edit.placeholder_text = "例如 D:/MC"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_path_edit)

	var browse := Button.new()
	browse.text = "浏览…"
	browse.pressed.connect(func() -> void:
		if not _path_edit.text.strip_edges().is_empty():
			_dir_dialog.current_dir = _path_edit.text.strip_edges()
		_dir_dialog.popup_centered()
	)
	row.add_child(browse)

	var tip := Label.new()
	tip.text = "接着依次选：游戏版本 → Mod 支持器 → 附加内容（mod/光影/资源包/数据包）→ 确认安装。\n哪一步点「取消」都会回到这里。"
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color("8b93a1"))
	_content.add_child(tip)


# ---------------------------------------------------------------- 第 2 步

func _build_step1() -> void:
	_content.add_child(_caption("要装哪个游戏版本（可搜索 / 可筛选）"))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	_content.add_child(frow)

	_ver_filter = OptionButton.new()
	for i in VER_FILTERS.size():
		_ver_filter.add_item(VER_FILTERS[i], i)
	_ver_filter.custom_minimum_size = Vector2(120, 0)
	_ver_filter.item_selected.connect(func(_i: int) -> void: _fill_versions(""))
	frow.add_child(_ver_filter)

	var search := LineEdit.new()
	search.placeholder_text = "输入版本号过滤，如 1.21 / 1.20.1"
	search.text_changed.connect(func(t: String) -> void: _fill_versions(t))
	_content.add_child(search)

	_ver_option = OptionButton.new()
	_ver_option.custom_minimum_size = Vector2(0, 34)
	_content.add_child(_ver_option)

	_content.add_child(_caption("给它取个名字（留空 = 用官方版本号）"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "例如 我的生存"
	_content.add_child(_name_edit)

	_fill_versions("")


func _fill_versions(filter: String) -> void:
	if _ver_option == null:
		return
	var needle := filter.strip_edges().to_lower()
	var mode: int = _ver_filter.selected if _ver_filter != null else 0
	_ver_option.clear()
	_versions.clear()
	for v in _all_versions:
		var mv: McVersion = v as McVersion
		if mv == null:
			continue
		# 分类筛选（和原版下载页一致）
		var tname := String(mv.type)
		match mode:
			1:
				if tname != "release":
					continue
			2:
				if tname != "snapshot":
					continue
			3:
				if not mv.is_april_fools():
					continue
			4:
				if not tname.begins_with("old"):
					continue
		if not needle.is_empty() and not mv.id.to_lower().contains(needle):
			continue
		_versions.append(mv.id)
	if _versions.is_empty():
		_ver_option.add_item("没有匹配的版本", 0)
		return
	for i in _versions.size():
		_ver_option.add_item(String(_versions[i]), i)
	_ver_option.select(0)

func _build_step2() -> void:
	_content.add_child(_caption("要装哪个 Mod 支持器（不装可以只装原版）"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	_loader_option = OptionButton.new()
	for i in LOADERS.size():
		_loader_option.add_item(LOADERS[i].capitalize() if LOADERS[i] != "不装" else "不装", i)
	_loader_option.select(maxi(["不装", "fabric", "quilt", "forge", "neoforge"].find(_chosen_loader), 0))
	_loader_option.item_selected.connect(_on_loader_picked)
	row.add_child(_loader_option)

	_loader_ver_option = OptionButton.new()
	_loader_ver_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loader_ver_option.add_item("自动：适配本版本的最新", 0)
	_loader_ver_option.item_selected.connect(func(i: int) -> void:
		if i <= 0:
			_chosen_loader_ver = ""
		elif i - 1 < _loader_versions.size():
			_chosen_loader_ver = String(_loader_versions[i - 1])
	)
	row.add_child(_loader_ver_option)
	var lrefresh := Button.new()
	lrefresh.text = "刷新"
	lrefresh.tooltip_text = "重新拉这个支持器的版本列表"
	lrefresh.pressed.connect(func() -> void:
		if _loader_option != null:
			_on_loader_picked(_loader_option.selected)
	)
	row.add_child(lrefresh)

	var tip := Label.new()
	tip.text = "下拉第一项是「自动」，会挑适配 %s 的最新版本；后面是具体版本。\nForge / NeoForge 需要 Java 才能跑官方安装器。" % _chosen_mc
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color("8b93a1"))
	_content.add_child(tip)

	if _chosen_loader != "不装":
		_on_loader_picked(_loader_option.selected)


func _on_loader_picked(index: int) -> void:
	_step_token += 1
	if _next_btn != null:
		_next_btn.disabled = true
		_next_btn.text = "正在加载版本…"
	var token := _step_token
	if not is_instance_valid(_loader_ver_option):
		return
	_loader_ver_option.clear()
	_loader_versions.clear()
	_loader_ver_option.add_item("自动：适配本版本的最新", 0)
	var kind: String = LOADERS[index]
	_chosen_loader = kind
	_chosen_loader_ver = ""
	if kind == "不装" or _chosen_mc.is_empty():
		return

	var list: Array = []
	match kind:
		"fabric":
			list = await McLoaders.fabric_loader_versions(self)
		"quilt":
			list = await McLoaders.quilt_loader_versions(self)
		"forge":
			var promos: Dictionary = await McLoaders.forge_promotions(self)
			for v in McLoaders.forge_versions_for(promos, _chosen_mc):
				list.append({"version": String(v)})
		"neoforge":
			for v in await McLoaders.neoforge_versions_multi(self, _chosen_mc):
				list.append({"version": String(v)})

	if token != _step_token or not is_instance_valid(_loader_ver_option):
		return
	for item in list:
		_loader_versions.append(String((item as Dictionary).get("version", "")))
	for i in _loader_versions.size():
		if not is_instance_valid(_loader_ver_option):
			return
		_loader_ver_option.add_item(String(_loader_versions[i]), i + 1)
	if _loader_versions.is_empty() and is_instance_valid(_loader_ver_option):
		_loader_ver_option.add_item("没拉到版本列表", 1)
	if _next_btn != null:
		_next_btn.disabled = false
		_next_btn.text = "下一步"


# ---------------------------------------------------------------- 第 4 步

func _build_step3() -> void:
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	_content.add_child(srow)

	_pick_search = LineEdit.new()
	_pick_search.placeholder_text = "搜索要装的 Mod / 光影 / 资源包 / 数据包"
	_pick_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick_search.text_submitted.connect(func(_t: String) -> void: _reload_picks())
	srow.add_child(_pick_search)

	_pick_sort = OptionButton.new()
	for i in SORTS.size():
		_pick_sort.add_item(SORTS[i], i)
	_pick_sort.custom_minimum_size = Vector2(110, 0)
	_pick_sort.item_selected.connect(func(_i: int) -> void: _reload_picks())
	srow.add_child(_pick_sort)

	var reload := Button.new()
	reload.text = "刷新列表"
	reload.pressed.connect(_reload_picks)
	srow.add_child(reload)

	var clear := Button.new()
	clear.text = "清空选择"
	clear.pressed.connect(func() -> void:
		for k in _pick_lists.keys():
			var l: ItemList = _pick_lists[k]
			if is_instance_valid(l):
				l.deselect_all()
	)
	srow.add_child(clear)

	_content.add_child(_caption("双击项目 → 选版本（自动 = 按 %s 取最新适配）；可以多选" % _chosen_mc))

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)

	for spec in KINDS:
		var kind: String = String(spec[0])
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(box)
		var cap := Label.new()
		cap.text = String(spec[1])
		cap.add_theme_font_size_override("font_size", 13)
		cap.add_theme_color_override("font_color", Color("98a0ae"))
		box.add_child(cap)
		var list := ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.select_mode = ItemList.SELECT_TOGGLE
		list.allow_reselect = true
		list.add_theme_font_size_override("font_size", 13)
		list.item_activated.connect(func(idx: int) -> void: _on_pick_selected(kind, list, idx))
		box.add_child(list)
		_pick_lists[kind] = list
		_pick_attr(kind)


func _reload_picks() -> void:
	for k in _pick_lists.keys():
		var l: ItemList = _pick_lists[k]
		if is_instance_valid(l):
			l.clear()
			_pick_attr(k)


func _pick_attr(kind: String) -> void:
	var token := _step_token
	var sort_key: String = SORT_KEYS[clampi(_pick_sort.selected, 0, SORT_KEYS.size() - 1)] if _pick_sort != null else "downloads"
	var q := _pick_search.text.strip_edges() if _pick_search != null else ""
	var ver_filter := _chosen_mc
	if kind == "shader" or kind == "resourcepack":
		ver_filter = ""
	var cat := ""
	if kind == "mod" and _mod_cat != null:
		cat = String(MOD_CATS[clampi(_mod_cat.selected, 0, MOD_CATS.size() - 1)][1])
	var res: Dictionary = await Modrinth.search(self, q, kind, "", sort_key, 20, 0, cat, "")
	if token != _step_token:
		return
	var list: ItemList = _pick_lists.get(kind, null)
	if list == null or not is_instance_valid(list):
		return
	if not bool(res.get("ok", false)):
		return
	for h in (res.get("hits", []) as Array):
		if typeof(h) != TYPE_DICTIONARY or not is_instance_valid(list):
			continue
		var hit: Dictionary = h
		var item := list.add_item(String(hit.get("title", "?")))
		list.set_item_metadata(item, hit)


# ---------------------------------------------------------------- 选版本弹窗

func _on_pick_selected(kind: String, list: ItemList, idx: int) -> void:
	if not is_instance_valid(list) or idx < 0 or idx >= list.item_count:
		return
	var meta: Variant = list.get_item_metadata(idx)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	_ver_target = {"kind": kind, "hit": meta, "list": list, "idx": idx}

	if _pick_dialog == null:
		_pick_dialog = PopupPanel.new()
		_pick_dialog.theme = theme
		add_child(_pick_dialog)
		var m := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 16)
		_pick_dialog.add_child(m)
		var vb := VBoxContainer.new()
		vb.custom_minimum_size = Vector2(420, 0)
		vb.add_theme_constant_override("separation", 10)
		m.add_child(vb)
		var cap := Label.new()
		cap.name = "Cap"
		vb.add_child(cap)
		var bar := HBoxContainer.new()
		bar.alignment = BoxContainer.ALIGNMENT_END
		bar.add_theme_constant_override("separation", 10)
		vb.add_child(bar)
		var auto_btn := Button.new()
		auto_btn.text = "自动选择"
		auto_btn.pressed.connect(_choose_auto)
		bar.add_child(auto_btn)
		var man_btn := Button.new()
		man_btn.text = "手动选择"
		man_btn.pressed.connect(_choose_manual)
		bar.add_child(man_btn)

	var cap_node: Label = _pick_dialog.get_child(0).get_child(0).get_node("Cap")
	cap_node.text = "「%s」装哪个版本？\n自动 = 按 %s 取最新适配版本" % [String((meta as Dictionary).get("title", "?")), _chosen_mc]
	_pick_dialog.popup_centered()


func _choose_auto() -> void:
	if _pick_dialog != null and is_instance_valid(_pick_dialog):
		_pick_dialog.hide()
	var kind := String(_ver_target.get("kind", ""))
	var hit: Dictionary = _ver_target.get("hit", {})
	var list: ItemList = _ver_target.get("list", null)
	var idx := int(_ver_target.get("idx", -1))
	var pid := String(hit.get("project_id", ""))
	if pid.is_empty():
		return
	var vers := await Modrinth.versions(self, pid, _chosen_mc, "")
	if vers.is_empty():
		if is_instance_valid(list) and idx >= 0 and idx < list.item_count:
			list.set_item_text(idx, "%s  ✘ 没有适配 %s 的版本" % [String(hit.get("title", "?")), _chosen_mc])
		_say("「%s」没有适配 %s 的版本" % [String(hit.get("title", "?")), _chosen_mc])
		return
	_picked_versions["%s|%s" % [kind, pid]] = vers[0]
	_chosen_items["%s|%s" % [kind, pid]] = {"kind": kind, "hit": hit, "version": vers[0]}
	if is_instance_valid(list) and idx >= 0 and idx < list.item_count:
		list.set_item_text(idx, "%s  ✔ %s" % [String(hit.get("title", "?")), String((vers[0] as Dictionary).get("version_number", ""))])


func _choose_manual() -> void:
	if _pick_dialog != null and is_instance_valid(_pick_dialog):
		_pick_dialog.hide()

	if _ver_dialog == null:
		_ver_dialog = PopupPanel.new()
		_ver_dialog.theme = theme
		add_child(_ver_dialog)
		var m := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 16)
		_ver_dialog.add_child(m)
		var vb := VBoxContainer.new()
		vb.custom_minimum_size = Vector2(440, 0)
		vb.add_theme_constant_override("separation", 8)
		m.add_child(vb)
		var cap := Label.new()
		cap.text = "选一个具体版本"
		vb.add_child(cap)
		_ver_dropdown = OptionButton.new()
		_ver_dropdown.custom_minimum_size = Vector2(420, 0)
		vb.add_child(_ver_dropdown)
		var bar := HBoxContainer.new()
		bar.alignment = BoxContainer.ALIGNMENT_END
		vb.add_child(bar)
		var ok := Button.new()
		ok.text = "用这个版本"
		ok.pressed.connect(_apply_manual_version)
		bar.add_child(ok)

	var kind := String(_ver_target.get("kind", ""))
	var hit: Dictionary = _ver_target.get("hit", {})
	var pid := String(hit.get("project_id", ""))
	_ver_dropdown.clear()
	_ver_dropdown.add_item("加载中…", 0)
	_ver_dialog.popup_centered()

	var vers := await Modrinth.versions(self, pid, _chosen_mc, "")
	if not is_instance_valid(_ver_dropdown):
		return
	_ver_list = vers
	_ver_dropdown.clear()
	if vers.is_empty():
		_ver_dropdown.add_item("没有适配 %s 的版本" % _chosen_mc, 0)
		return
	for i in mini(vers.size(), 80):
		var v: Dictionary = vers[i]
		_ver_dropdown.add_item("%s ｜ %s" % [String(v.get("version_number", "")), ", ".join(v.get("game_versions", []))], i)


func _apply_manual_version() -> void:
	var kind := String(_ver_target.get("kind", ""))
	var hit: Dictionary = _ver_target.get("hit", {})
	var list: ItemList = _ver_target.get("list", null)
	var idx := int(_ver_target.get("idx", -1))
	var sel := _ver_dropdown.selected
	if sel >= 0 and sel < _ver_list.size():
		var pid := String(hit.get("project_id", ""))
		var v: Dictionary = _ver_list[sel]
		_picked_versions["%s|%s" % [kind, pid]] = v
		_chosen_items["%s|%s" % [kind, pid]] = {"kind": kind, "hit": hit, "version": v}
		if is_instance_valid(list) and idx >= 0 and idx < list.item_count:
			list.set_item_text(idx, "%s  ✔ %s" % [String(hit.get("title", "?")), String(v.get("version_number", ""))])
	if _ver_dialog != null and is_instance_valid(_ver_dialog):
		_ver_dialog.hide()


func _build_step4() -> void:
	var lines: Array[String] = []
	lines.append("安装目录：%s" % (game_dir if not game_dir.is_empty() else "（未填）"))
	lines.append("游戏版本：%s" % (_chosen_mc if not _chosen_mc.is_empty() else "（未选）"))
	lines.append("版本名字：%s" % (_chosen_name if not _chosen_name.is_empty() else "（用 %s）" % _chosen_mc))
	if _chosen_loader == "不装":
		lines.append("Mod 支持器：不装")
	else:
		var lv := _chosen_loader_ver
		if lv.is_empty() and not _loader_versions.is_empty():
			lv = String(_loader_versions[0])
		lines.append("Mod 支持器：%s ｜ %s" % [_chosen_loader.capitalize(), lv if not lv.is_empty() else "自动"])

	for item in _snapshot:
		var k := String((item as Dictionary).get("kind", ""))
		var m: Dictionary = (item as Dictionary).get("hit", {})
		var vd: Dictionary = (item as Dictionary).get("version", {})
		var vname := String(vd.get("version_number", "自动最新"))
		lines.append("  %s：%s ｜ %s" % [String(KIND_CN.get(k, k)), String(m.get("title", "?")), vname])
	if _snapshot.is_empty():
		lines.append("附加内容：不装")

	var lab := Label.new()
	lab.text = "\n".join(lines)
	lab.add_theme_font_size_override("font_size", 14)
	_content.add_child(lab)

	_java_check = CheckBox.new()
	_java_check.text = "自动检测 Java，没有合适版本就自动装到 <安装目录>/runtime"
	_java_check.button_pressed = true
	_java_check.tooltip_text = "不勾就只检测、不下载 Java"
	_content.add_child(_java_check)


# ---------------------------------------------------------------- 流程

func _on_next() -> void:
	match step:
		0:
			var dir := _path_edit.text.strip_edges().replace("\\", "/")
			if dir.is_empty() or dir.length() < 4 or dir.ends_with(":"):
				_content.add_child(_warn("路径不对，填个像 D:/MC 的目录"))
				return
			game_dir = dir
			_goto(1)
		1:
			if _ver_option == null or _ver_option.item_count == 0 or _versions.is_empty():
				_content.add_child(_warn("先选一个游戏版本"))
				return
			_chosen_mc = _current_ver()
			if _chosen_mc.is_empty():
				_content.add_child(_warn("先选一个游戏版本"))
				return
			_chosen_name = _name_edit.text.strip_edges() if _name_edit != null else ""
			_goto(2)
		2:
			_chosen_loader = LOADERS[_loader_option.selected]
			if _chosen_loader_ver.is_empty() and not _loader_versions.is_empty():
				_chosen_loader_ver = String(_loader_versions[0])
			if _chosen_loader != "不装" and _loader_versions.is_empty():
				_content.add_child(_warn("支持器版本还没加载好，等下拉里出现版本再下一步"))
				return
			_goto(3)
		3:
			_snapshot_picks()
			_goto(4)
		4:
			_do_install()


func _current_ver() -> String:
	if _ver_option != null and _ver_option.selected >= 0 and _ver_option.selected < _versions.size():
		return String(_versions[_ver_option.selected])
	return _chosen_mc


func _do_install() -> void:
	if _chosen_mc.is_empty():
		return
	_busy = false
	var cfg := {
		"dir": game_dir,
		"version": _chosen_mc,
		"name": _chosen_name,
		"loader": _chosen_loader,
		"loader_ver": _chosen_loader_ver,
		"java_auto": _java_check == null or _java_check.button_pressed,
		"extras": _snapshot.duplicate(),
	}
	install_requested.emit(cfg)


func _snapshot_picks() -> void:
	_snapshot.clear()
	for key in _chosen_items.keys():
		var item: Dictionary = _chosen_items[key]
		_snapshot.append(item)


func set_progress(text: String, ratio: float) -> void:
	if _wiz_status != null and is_instance_valid(_wiz_status):
		_wiz_status.text = text
	if _wiz_bar != null and is_instance_valid(_wiz_bar):
		_wiz_bar.value = clampf(ratio * 100.0, 0.0, 100.0)

## 安装阶段：给每个附加内容建一条进度条（向导保持可见）
func show_install_progress(extras: Array) -> void:
	_install_bars.clear()
	if _install_box != null and is_instance_valid(_install_box):
		_install_box.queue_free()
	_install_box = VBoxContainer.new()
	_install_box.add_theme_constant_override("separation", 4)
	var host: Node = _content.get_parent()
	if host != null:
		host.add_child(_install_box)
	for item in extras:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var hit: Dictionary = (item as Dictionary).get("hit", {})
		var kind := String((item as Dictionary).get("kind", ""))
		var cap := Label.new()
		cap.text = "%s：%s" % [String(KIND_CN.get(kind, kind)), String(hit.get("title", "?"))]
		cap.add_theme_font_size_override("font_size", 11)
		cap.add_theme_color_override("font_color", Color("8b93a1"))
		_install_box.add_child(cap)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.max_value = 100.0
		bar.value = 0.0
		bar.show_percentage = false
		_install_box.add_child(bar)
		_install_bars.append(bar)


func set_item_progress(index: int, ratio: float) -> void:
	if index >= 0 and index < _install_bars.size():
		var b: ProgressBar = _install_bars[index]
		if is_instance_valid(b):
			b.value = clampf(ratio * 100.0, 0.0, 100.0)

## 底部状态栏提示
func _say(text: String) -> void:
	if _wiz_status != null and is_instance_valid(_wiz_status):
		_wiz_status.text = text

# ---------------------------------------------------------------- 第 6 屏：安装进度

## 主页面在开始安装前调用：告诉向导这次要装哪些东西
func prepare_install(has_java: bool, extras: Array) -> void:
	_prog_has_java = has_java
	_prog_extras = extras.duplicate()
	_install_bars.clear()
	_goto(5)


func _build_step5() -> void:
	_content.add_child(_caption("正在安装，下面是每一项的独立进度"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)

	var pause_btn := Button.new()
	pause_btn.set_meta("always_enabled", true)
	pause_btn.text = "暂停"
	pause_btn.tooltip_text = "暂停下载，已完成的文件不会丢"
	pause_btn.pressed.connect(func() -> void:
		var page := get_parent()
		if page != null and page.has_method("_on_pause_pressed"):
			page.call("_on_pause_pressed")
	)
	row.add_child(pause_btn)

	var cancel_btn := Button.new()
	cancel_btn.set_meta("always_enabled", true)
	cancel_btn.text = "取消"
	cancel_btn.tooltip_text = "取消这次快速安装"
	cancel_btn.pressed.connect(func() -> void:
		var page := get_parent()
		if page != null and page.has_method("_on_cancel_pressed"):
			page.call("_on_cancel_pressed")
	)
	row.add_child(cancel_btn)

	_add_prog_row("原版游戏", "game")
	_add_prog_row("Mod 支持器", "loader")
	if _prog_has_java:
		_add_prog_row("Java 运行时", "java")
	for i in _prog_extras.size():
		var item: Dictionary = _prog_extras[i]
		var hit: Dictionary = item.get("hit", {})
		var kind := String(item.get("kind", ""))
		_add_prog_row("%s：%s" % [String(KIND_CN.get(kind, kind)), String(hit.get("title", "?"))], "extra:%d" % i)


func _add_prog_row(text: String, key: String) -> void:
	var cap := Label.new()
	cap.text = text
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color("98a0ae"))
	_content.add_child(cap)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	_content.add_child(bar)
	_install_bars.append({"key": key, "bar": bar, "label": cap, "title": text})


## 主页面推进某一条：section = game / loader / java / extra:i
func wiz_progress(section: String, ratio: float, size_text := "") -> void:
	for row in _install_bars:
		if String((row as Dictionary).get("key", "")) == section:
			var b: ProgressBar = (row as Dictionary).get("bar", null)
			if b != null and is_instance_valid(b):
				b.value = clampf(ratio * 100.0, 0.0, 100.0)
			var lab: Label = (row as Dictionary).get("label", null)
			if lab != null and is_instance_valid(lab) and not size_text.is_empty():
				lab.text = "%s ｜ %s" % [String((row as Dictionary).get("title", section)), size_text]
			return

## 装完后把所有进度条清零、标签恢复原样
func reset_progress() -> void:
	for row in _install_bars:
		var b: ProgressBar = (row as Dictionary).get("bar", null)
		if b != null and is_instance_valid(b):
			b.value = 0.0
		var lab: Label = (row as Dictionary).get("label", null)
		if lab != null and is_instance_valid(lab):
			lab.text = String((row as Dictionary).get("title", ""))
	_say("")
	if _wiz_bar != null and is_instance_valid(_wiz_bar):
		_wiz_bar.value = 0.0

## 安装页：直接读主页面的真实进度来同步（不依赖事件推送，绝不会不动）
func _sync_from_page() -> void:
	var page := get_parent()
	if page == null:
		return
	for row in _install_bars:
		var key := String((row as Dictionary).get("key", ""))
		var b: ProgressBar = (row as Dictionary).get("bar", null)
		if b == null or not is_instance_valid(b):
			continue
		var v := 0.0
		match key:
			"game":
				var pb = page.get("_progress_bar")
				if pb is ProgressBar:
					v = (pb as ProgressBar).value
			"loader":
				var lb = page.get("_bar_loader")
				if lb is ProgressBar:
					v = (lb as ProgressBar).value
			"fabric":
				var fb = page.get("_bar_fabric")
				if fb is ProgressBar:
					v = (fb as ProgressBar).value
			_:
				if key.begins_with("extra:"):
					var idx := int(key.substr(6))
					var bars: Array = page.get("_extra_bars")
					if idx >= 0 and idx < bars.size() and bars[idx] is ProgressBar:
						v = (bars[idx] as ProgressBar).value
		if v > b.value:
			b.value = v
