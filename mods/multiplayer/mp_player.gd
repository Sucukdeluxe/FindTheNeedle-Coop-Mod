extends "res://scripts/player/player.gd"

var mp_tools: Node

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
