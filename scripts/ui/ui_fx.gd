class_name UiFx
extends RefCounted
## 轻量动画工具：全部用 Tween 实现，不依赖任何资源文件。
## 每个函数都做了空节点 / 不在场景树 的保护，可以放心在界面回调里调用。

## 淡入（页面、面板首次出现）
static func fade_in(node: CanvasItem, duration := 0.35) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, duration)


## 内容切换时的快速淡入（换版本、换状态文案）
static func fade_swap(node: CanvasItem, duration := 0.2) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var alpha := node.modulate.a
	node.modulate.a = 0.15 if alpha > 0.5 else alpha
	var t := node.create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, duration)


## 点击回弹：短暂提亮再回来
static func tap(node: CanvasItem) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var alpha := node.modulate.a
	var t := node.create_tween()
	t.tween_property(node, "modulate", Color(1.5, 1.5, 1.5, alpha), 0.05)
	t.tween_property(node, "modulate", Color(1, 1, 1, alpha), 0.32)


## 完成 / 成功时的发光提示
static func glow(node: CanvasItem, color: Color, duration := 0.9) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var alpha := node.modulate.a
	var t := node.create_tween()
	t.tween_property(node, "modulate", Color(color.r, color.g, color.b, alpha), duration * 0.48)
	t.tween_property(node, "modulate", Color(1, 1, 1, alpha), duration * 0.7)

# ---------------------------------------------------------------- 全局按钮特效

## 给一棵子树里所有按钮装上：按下缩放回弹 + 点击涟漪 + 悬停高亮
static func install(root: Node, depth := 0) -> void:
	if root == null or depth > 24:
		return
	for child in root.get_children():
		if child is BaseButton:
			_bind(child as BaseButton)
		install(child, depth + 1)


static func _bind(b: BaseButton) -> void:
	if b == null or not is_instance_valid(b) or b.has_meta("gf_bound"):
		return
	b.set_meta("gf_bound", true)
	b.button_down.connect(func() -> void: _press_fx(b))
	b.mouse_entered.connect(func() -> void: _hover(b, true))
	b.mouse_exited.connect(func() -> void: _hover(b, false))


static func _hover(b: BaseButton, on: bool) -> void:
	if not is_instance_valid(b):
		return
	var t := b.create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "modulate", Color(1.15, 1.15, 1.15, 1.0) if on else Color(1, 1, 1, 1), 0.14)


static func _press_fx(b: BaseButton) -> void:
	if not is_instance_valid(b) or not (b is Control):
		return
	var c := b as Control
	if c.size.x <= 0.0:
		return
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2(0.95, 0.95), 0.07)
	t.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ripple(c)


## 以按钮中心为原点扩散一圈彩色涟漪
static func _ripple(c: Control) -> void:
	var parent := c.get_parent()
	if parent == null:
		return
	var dot := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.68, 1.0, 0.5)
	sb.corner_radius_top_left = 24
	sb.corner_radius_top_right = 24
	sb.corner_radius_bottom_left = 24
	sb.corner_radius_bottom_right = 24
	dot.add_theme_stylebox_override("panel", sb)
	dot.size = Vector2(24, 24)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.pivot_offset = Vector2(12, 12)
	parent.add_child(dot)
	dot.global_position = c.get_global_rect().get_center() - Vector2(12, 12)
	var t := dot.create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(dot, "scale", Vector2(5.5, 5.5), 0.42)
	t.tween_property(dot, "modulate:a", 0.0, 0.42)
	t.chain().tween_callback(dot.queue_free)

# ---------------------------------------------------------------- 启动 / 切页

## 启动特效：整体淡入 + 轻微放大（不动 position，锚点布局不受影响）
static func launch_intro(node: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.modulate.a = 0.0
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.985, 0.985)
	var t := node.create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.55)
	t.tween_property(node, "scale", Vector2.ONE, 0.55)


## 页面切入：淡入 + 轻微放大（锚点布局下安全）
static func page_in(node: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.modulate.a = 0.0
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.97, 0.97)
	var t := node.create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.26)
	t.tween_property(node, "scale", Vector2.ONE, 0.26)


## 页面切出：淡出 + 轻微缩小，结束后隐藏并复位
static func page_out(node: Control, on_done := Callable()) -> void:
	if node == null or not is_instance_valid(node):
		if on_done.is_valid():
			on_done.call()
		return
	node.pivot_offset = node.size * 0.5
	var t := node.create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(node, "modulate:a", 0.0, 0.18)
	t.tween_property(node, "scale", Vector2(0.97, 0.97), 0.18)
	t.finished.connect(_after_out.bind(node, on_done))


static func _after_out(node: Control, on_done: Callable) -> void:
	if is_instance_valid(node):
		node.hide()
		node.modulate.a = 1.0
		node.scale = Vector2.ONE
	if on_done.is_valid():
		on_done.call()
