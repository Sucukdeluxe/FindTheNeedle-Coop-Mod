extends "res://scripts/items/tool_prop.gd"

var mp_props: Node

func claim(player: Player) -> bool:
	if not is_instance_valid(mp_props) or not mp_props.mp.active() or not has_meta("mp_id"):
		return super.claim(player)
	var id := int(get_meta("mp_id"))
	if not mp_props._mine(id):
		mp_props.request_claim(id, "tool")
		return false
	var accepted := super.claim(player)
	if accepted and mp_props.props.items.has(self):
		mp_props.props.remove(self)
	return false
