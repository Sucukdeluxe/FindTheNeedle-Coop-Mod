extends RoboticArm

var mp_transport: Node
var _mp_searching := false
var _mp_snapshot_depth := 0

func mp_snapshot_begin() -> void:
	_mp_snapshot_depth += 1

func mp_snapshot_end() -> void:
	_mp_snapshot_depth = maxi(0, _mp_snapshot_depth - 1)

func _credit_the_undrawn() -> void:
	if _mp_snapshot_depth == 0:
		super._credit_the_undrawn()

func _mp_props() -> Node:
	if not is_instance_valid(mp_transport) or not is_instance_valid(mp_transport.mp):
		return null
	if not mp_transport.mp.active() or not mp_transport.mp.is_host:
		return null
	var sync: Variant = mp_transport.mp.world_sync
	return sync.props_sync if is_instance_valid(sync) else null

func _mp_candidate(item: Variant, sync: Node, allow_belt: bool = false) -> bool:
	if not is_instance_valid(item) or not is_instance_valid(sync) or not item is Carryable:
		return false
	if not item.is_inside_tree() or item.is_queued_for_deletion() or item.is_held():
		return false
	if item.has_meta(HayLift.META_CARRIED) or item.has_meta(HayStairs.META_CARRIED):
		return false
	if not allow_belt and BeltPath.is_rider(item):
		return false
	var id := int(item.get_meta("mp_id", 0))
	var owner := int(sync._owner.get(id, 0))
	return id > 0 and sync._by_id.get(id) == item and owner > 1 and sync.mp.players.has(owner) \
		and int(item.get_meta(PropManager.META_CLAIM, 0)) == sync.get_instance_id() \
		and not bool(sync._held.get(id, false)) and not sync._pushed.has(id) \
		and not sync._claim_pending.has(id) and not sync._goal.has(id)

func _find_prop_pickup(shoulder_world: Vector3, biggest: bool = false) -> Carryable:
	var sync := _mp_props()
	if sync == null or props == null:
		return super._find_prop_pickup(shoulder_world, biggest)
	var released: Array = []
	var reach_squared := work_reach() * work_reach()
	for item in props.items:
		if is_instance_valid(item) and shoulder_world.distance_squared_to(item.global_position) <= reach_squared and _mp_candidate(item, sync):
			released.append([item, item.get_meta(PropManager.META_CLAIM)])
			item.remove_meta(PropManager.META_CLAIM)
	var picked := super._find_prop_pickup(shoulder_world, biggest)
	for entry in released:
		if is_instance_valid(entry[0]):
			entry[0].set_meta(PropManager.META_CLAIM, entry[1])
	if picked == null or sync._mine(int(picked.get_meta("mp_id", 0))):
		return picked
	return picked if _mp_candidate(picked, sync) and sync.host_take(picked) else null

func _claimed_by_other(item: Carryable) -> bool:
	if not super._claimed_by_other(item):
		return false
	return not (_mp_searching and _mp_candidate(item, _mp_props(), true))

func _find_belt_pickup() -> Dictionary:
	_mp_searching = true
	var picked := super._find_belt_pickup()
	_mp_searching = false
	return picked

func _belt_load_under_claw(run: BeltPath) -> Carryable:
	_mp_searching = true
	var picked := super._belt_load_under_claw(run)
	_mp_searching = false
	var sync := _mp_props()
	if picked == null or sync == null or sync._mine(int(picked.get_meta("mp_id", 0))):
		return picked
	return picked if _mp_candidate(picked, sync, true) and sync.host_take(picked) else null
