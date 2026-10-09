extends "res://scripts/player/player.gd"

func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)

func eye_position() -> Vector3:
	return camera.global_position

func look_direction() -> Vector3:
	return -camera.global_basis.z

func is_mouse_captured() -> bool:
	return true

func menu_is_up() -> bool:
	return false
