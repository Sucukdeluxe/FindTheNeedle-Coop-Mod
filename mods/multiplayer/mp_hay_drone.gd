extends HayDrone

var mp_transport: Node
var _mp_searching := false
var _mp_drop_full := false

func _mp_props() -> Node:
	if not is_instance_valid(mp_transport) or not is_instance_valid(mp_transport.mp):
		return null
	if not mp_transport.mp.active() or not mp_transport.mp.is_host:
		return null
	var world_sync: Variant = mp_transport.mp.world_sync
	return world_sync.props_sync if is_instance_valid(world_sync) else null

func _mp_candidate(item: Node, sync: Node) -> bool:
	if not is_instance_valid(item) or not is_instance_valid(sync) or not item.is_inside_tree() or item.is_queued_for_deletion():
		return false
	if not (item is Carryable) or item.is_held() or BeltPath.is_rider(item):
		return false
	var id := int(item.get_meta("mp_id", 0))
	var owner := int(sync._owner.get(id, 0))
	return id > 0 and sync._by_id.get(id) == item and owner > 1 and sync.mp.players.has(owner) \
		and int(item.get_meta(PropManager.META_CLAIM, 0)) == sync.get_instance_id() \
		and not bool(sync._held.get(id, false)) and not sync._pushed.has(id) \
		and not sync._claim_pending.has(id) and not sync._goal.has(id)

func _is_prize(item: Node) -> bool:
	if super._is_prize(item):
		return true
	if not _mp_searching:
		return false
	var sync := _mp_props()
	if not _mp_candidate(item, sync):
		return false
	var claim: Variant = item.get_meta(PropManager.META_CLAIM)
	item.remove_meta(PropManager.META_CLAIM)
	var eligible := super._is_prize(item)
	item.set_meta(PropManager.META_CLAIM, claim)
	return eligible

func _find_collect() -> Dictionary:
	_mp_searching = true
	var pick := super._find_collect()
	_mp_searching = false
	if pick.is_empty():
		return pick
	var sync := _mp_props()
	var item: Variant = pick.get("item")
	if not is_instance_valid(sync) or not is_instance_valid(item):
		return pick
	var id := int(item.get_meta("mp_id", 0))
	if sync._mine(id):
		return pick
	if not _mp_candidate(item, sync) or not sync.host_take(item):
		return {}
	return pick if sync._mine(id) and super._is_prize(item) else {}

func _drop_full() -> bool:
	if is_instance_valid(mp_transport) and is_instance_valid(mp_transport.mp) and mp_transport.mp.active() and not mp_transport.mp.is_host:
		return _mp_drop_full
	return super._drop_full()
