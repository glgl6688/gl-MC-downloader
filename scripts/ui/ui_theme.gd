class_name UiTheme
extends RefCounted
## 代码生成的主题（深色 + 蓝色强调色）。
## 用代码建主题的好处是不用维护 .tres、改颜色只改常量；字体用系统字体，
## 这样中文不会变成方块，也不用内嵌字体文件。

const BG := Color("1a1c20")
const PANEL := Color("23262d")
const PANEL_HI := Color("2b2f38")
const BORDER := Color("343943")
const TEXT := Color("e8eaee")
const TEXT_DIM := Color("98a0ae")
const ACCENT := Color("4a9eff")
const ACCENT_DARK := Color("2f7de1")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = system_font()
	t.default_font_size = 15

	# ---- Label
	t.set_color("font_color", "Label", TEXT)

	# ---- Button
	t.set_stylebox("normal", "Button", box(PANEL_HI, 6, BORDER))
	t.set_stylebox("hover", "Button", box(Color("353b46"), 6, Color("404754")))
	t.set_stylebox("pressed", "Button", box(Color("3e4552"), 6, ACCENT_DARK))
	t.set_stylebox("disabled", "Button", box(Color("25282e"), 6, Color("2d313a")))
	t.set_stylebox("focus", "Button", focus_box())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("666e7c"))
	t.set_font_size("font_size", "Button", 15)

	# ---- LineEdit
	t.set_stylebox("normal", "LineEdit", box(PANEL, 6, BORDER))
	t.set_stylebox("focus", "LineEdit", box(PANEL, 6, ACCENT))
	t.set_stylebox("read_only", "LineEdit", box(Color("1d2026"), 6, BORDER))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("font_uneditable_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))

	# ---- ItemList
	t.set_stylebox("panel", "ItemList", box(PANEL, 8, BORDER))
	t.set_stylebox("selected", "ItemList", box(ACCENT_DARK, 5))
	t.set_stylebox("selected_focus", "ItemList", box(ACCENT, 5))
	t.set_stylebox("cursor", "ItemList", box(Color(1, 1, 1, 0.06), 5))
	t.set_stylebox("cursor_unfocused", "ItemList", box(Color(1, 1, 1, 0.03), 5))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", Color(1, 1, 1, 0.06))
	t.set_constant("v_separation", "ItemList", 7)
	t.set_constant("h_separation", "ItemList", 8)
	t.set_font_size("font_size", "ItemList", 14)

	# ---- OptionButton / 弹出菜单
	t.set_stylebox("panel", "PopupMenu", box(Color("2a2e36"), 6, BORDER))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT_DARK, 5))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_separator_color", "PopupMenu", TEXT_DIM)
	t.set_constant("v_separation", "PopupMenu", 8)

	# ---- PanelContainer
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, BORDER))

	# ---- 弹出面板（下载设置）
	t.set_stylebox("panel", "PopupPanel", box(PANEL, 10, BORDER))

	# ---- ProgressBar
	t.set_stylebox("background", "ProgressBar", flat(Color("2f333c"), 6))
	t.set_stylebox("fill", "ProgressBar", flat(ACCENT, 6))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", 13)

	# ---- 分隔线
	t.set_stylebox("separator", "HSeparator", line(BORDER))
	t.set_constant("separation", "HSeparator", 10)

	# ---- 滚动条
	t.set_stylebox("scroll", "VScrollBar", flat(Color(1, 1, 1, 0.03), 4))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(1, 1, 1, 0.12), 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(1, 1, 1, 0.20), 4))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(ACCENT, 4))

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_disabled_color", "CheckBox", Color("666e7c"))
	t.set_font_size("font_size", "CheckBox", 14)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_font_size("font_size", "CheckButton", 14)

	# ---- SpinBox（内部是 LineEdit + 上下箭头）
	t.set_stylebox("normal", "SpinBox", box(PANEL, 6, BORDER))
	t.set_color("font_color", "SpinBox", TEXT)
	return t


## 系统字体：用系统默认无衬线字体，中文靠系统回退，所以不用内嵌字体文件
static func system_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"sans-serif",
		"PingFang SC", "Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC",
	])
	f.allow_system_fallback = true
	return f


static func box(bg: Color, radius: int = 6, border := Color(0, 0, 0, 0), pad := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.anti_aliasing = true
	if pad:
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
	return sb


static func flat(bg: Color, radius: int = 5) -> StyleBoxFlat:
	return box(bg, radius, Color(0, 0, 0, 0), false)


static func focus_box() -> StyleBoxFlat:
	var sb := box(Color(0, 0, 0, 0), 6, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55), false)
	return sb


static func line(color: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = color
	sb.thickness = 1
	sb.vertical = false
	return sb
