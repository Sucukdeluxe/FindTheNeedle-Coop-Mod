extends "res://scripts/player/player.gd"

var mp_tools: Node

func _drop_tool_object(id: String) -> bool:
	if is_instance_valid(mp_tools) and mp_tools.mp.active() and mp_tools.shared.has(id):
		_set_tool(Tool.HAND, true)
		return true
	return super._drop_tool_object(id)

func _throw_tool_object(id: String) -> bool:
	if is_instance_valid(mp_tools) and mp_tools.mp.active() and mp_tools.shared.has(id):
		_set_tool(Tool.HAND, true)
		return true
	return super._throw_tool_object(id)
