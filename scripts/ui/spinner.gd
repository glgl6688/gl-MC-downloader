class_name Spinner
extends Control
## 一个很小的旋转加载圈，纯 _draw 画的，不依赖图片资源。
## 用 visible 控制显隐；隐藏时会自动停止 redraw，几乎不占性能。

@export var color: Color = Color("4a9eff")
@export var thickness: float = 2.0
## 每秒转多少弧度
@export var speed: float = 6.0

var _angle := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(16, 16)
	set_process(false)
	visibility_changed.connect(_sync_process)
	_sync_process()


func _sync_process() -> void:
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	_angle = fmod(_angle + delta * speed, TAU)
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - thickness
	if radius <= 0.0:
		return
	var center := size * 0.5
	# 底圈
	draw_arc(center, radius, 0.0, TAU, 32, Color(color.r, color.g, color.b, 0.18), thickness, true)
	# 旋转的一段弧
	draw_arc(center, radius, _angle, _angle + TAU * 0.35, 24, color, thickness, true)
