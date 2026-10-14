extends "res://scripts/player/player.gd"

var mp_tools: Node
var mp_build_camera: Node
var _mp_air_jump := preload("res://mods/multiplayer/mp_double_jump.gd").new()

func _drop_tool_object(id: String) -> bool:
	if is_instance_valid(mp_tools) and mp_tools.mp.active():
		mp_tools.request_drop(id, false)
		return false
	return super._drop_tool_object(id)

func _throw_tool_object(id: String) -> bool:
	if is_instance_valid(mp_tools) and mp_tools.mp.active():
		mp_tools.request_drop(id, true)
		return false
	return super._throw_tool_object(id)
func _physics_process(delta: float) -> void:
	var allowed := Tech.rank_of("double_jump") > 0 and not noclip and not scripted and not _flung and not _climbing and _ladder_grace <= 0.0 and _crouch < 0.5 and _accepts_move() and not menu_is_up() and not _ladder_close()
	if jetpack != null and Tech.rank_of("jetpack") > 0:
		allowed = false
	if _mp_air_jump.step(is_on_floor(), Input.is_action_pressed("jump"), allowed):
		velocity.y = Tech.jump_velocity(JUMP_VELOCITY, GRAVITY) * stamina.jump_scale()
		_jumps += 1
	super._physics_process(delta)

func eye_position() -> Vector3:
	if is_instance_valid(mp_build_camera) and mp_build_camera.active:
		return mp_build_camera.ray_origin()
	return super.eye_position()

func look_direction() -> Vector3:
	if is_instance_valid(mp_build_camera) and mp_build_camera.active:
		return mp_build_camera.ray_direction()
	return super.look_direction()

func capture_mouse(on: bool) -> void:
	super.capture_mouse(on)
	if is_instance_valid(mp_build_camera) and mp_build_camera.active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
