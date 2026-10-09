extends "res://autoload/tech.gd"

var mp_world: Node
var pending := {}

func buy(id: String) -> bool:
	if not is_instance_valid(mp_world) or not mp_world.mp.active() or mp_world.mp.is_host:
		return super.buy(id)
	if pending.has(id):
		return false
	if not can_buy(id).get("ok", false):
		return false
	pending[id] = true
	mp_world.mp._rx_tech_purchase.rpc_id(1, id, int(ranks.get(id, 0)))
	return true
