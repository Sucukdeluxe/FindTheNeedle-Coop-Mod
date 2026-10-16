extends Control

signal port_selected(side: int)
var target: Node3D
var _buttons: Array[Button] = []
var _points := PackedVector2Array()
var _dark := false

func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in int(target.port_count):
		var button := PlateKit.button(str(side + 1), "", func():port_selected.emit(side))
		button.name = "Port%d" % (side + 1)
		button.text = str(side + 1)
		button.custom_minimum_size = Vector2(42, 42)
		button.add_theme_font_size_override("font_size", 16)
		add_child(button)
		_buttons.append(button)
	resized.connect(_layout)
	_layout()

func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	if _dark != ArmPanel.dark:
		_dark = ArmPanel.dark
		_layout()
	for side in _buttons.size():
		_buttons[side].disabled = not target.empty()
	queue_redraw()

func _layout() -> void:
	_points.clear()
	var center := size * 0.5
	var radius := maxf(50.0, minf(size.x, size.y) * 0.5 - 28.0)
	for side in _buttons.size():
		var angle := TAU * float(side) / float(_buttons.size()) + target.global_rotation.y
		var point := center + Vector2(sin(angle), cos(angle)) * radius
		_points.append(point)
		_buttons[side].position = point - Vector2(21, 21)
		_buttons[side].size = Vector2(42, 42)
		var output: bool = target.port_is_output(side)
		var ink: Color = ArmPanel.COL_TAKE_INK if output else ArmPanel.COL_PUT_INK
		_buttons[side].add_theme_color_override("font_color", ink)
		_buttons[side].tooltip_text = preload("res://mods/multiplayer/mp_i18n.gd").phrase("Ausgang", "Output") if output else preload("res://mods/multiplayer/mp_i18n.gd").phrase("Eingang", "Input")
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(target):return
	var center := size * 0.5
	draw_circle(center, 33.0, Color(0.12, 0.15, 0.17))
	draw_arc(center, 33.0, 0.0, TAU, 48, Color(0.5, 0.55, 0.58), 1.0, true)
	for side in _points.size():
		var direction := (_points[side] - center).normalized()
		var output: bool = target.port_is_output(side)
		var ink: Color = ArmPanel.COL_TAKE_INK if output else ArmPanel.COL_PUT_INK
		var a := center + direction * 38.0
		var b := _points[side] - direction * 28.0
		draw_line(a, b, ink, 3.0, true)
		var travel := direction if output else -direction
		var across := Vector2(-travel.y, travel.x)
		var point := a.lerp(b, 0.6 if output else 0.4)
		draw_polyline(PackedVector2Array([point - travel * 9.0 + across * 6.0, point, point - travel * 9.0 - across * 6.0]), ink, 3.0, true)
