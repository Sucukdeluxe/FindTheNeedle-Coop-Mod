extends "res://scripts/build/hay_pelletizer.gd"

var mp_transport: Node

func set_throw_distance(metres: float) -> void:
	super.set_throw_distance(metres)
	_mp_setting("throw_distance", throw_distance)

func set_head_yaw(degrees: float) -> void:
	super.set_head_yaw(degrees)
	_mp_setting("head_yaw", head_yaw)

func set_switched_off(off: bool) -> void:
	super.set_switched_off(off)
	_mp_setting("switched_off", switched_off)

func _mp_setting(field: String, value: Variant) -> void:
	if is_instance_valid(mp_transport):
		mp_transport.queue_setting(self, field, value)
