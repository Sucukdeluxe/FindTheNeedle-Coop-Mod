extends "res://scripts/items/tool_prop.gd"

var mp_props: Node

func claim(player: Player) -> bool:
	if not is_instance_valid(mp_props) or not mp_props.mp.active() or not has_meta("mp_id"):
		return super.claim(player)
	var tools: Node = mp_props.mp.world_sync.tools_sync
	if is_instance_valid(tools):
		tools.request_pickup(self)
	return false
