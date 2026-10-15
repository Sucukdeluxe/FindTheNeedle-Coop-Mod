extends RoboticArm

const ArmState = preload("res://mods/multiplayer/mp_arm_state.gd")
const ArmRoutes = preload("res://mods/multiplayer/mp_arm_routes.gd")

var _mp_status := {}

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

func _mp_remote() -> bool:
	return is_instance_valid(mp_transport) and is_instance_valid(mp_transport.mp) and mp_transport.mp.active() and not mp_transport.mp.is_host

func mp_status_snapshot() -> Dictionary:
	return _mp_status.duplicate(true) if _mp_remote() else ArmState.capture(self)

func mp_apply_status(value: Variant) -> void:
	if not _mp_remote() or not ArmState.valid(value):
		return
	_mp_status = value.duplicate(true)
	power = float(value.power)
	line_power = float(value.line_power)
	power_blocked = value.blocked
	power_line = value.line

func set_power(value: float) -> void:
	if not _mp_remote() or _mp_status.is_empty():
		super.set_power(value)

func set_power_blocked(value: bool) -> void:
	if not _mp_remote() or _mp_status.is_empty():
		super.set_power_blocked(value)

func set_power_line(value: int) -> void:
	if not _mp_remote() or _mp_status.is_empty():
		super.set_power_line(value)

func alert_reason() -> String:
	return str(_mp_status.get("alert", "")) if _mp_remote() else super.alert_reason()

func alert_icon() -> String:
	return str(_mp_status.get("icon", "")) if _mp_remote() else super.alert_icon()

func waiting_reason() -> String:
	return str(_mp_status.get("waiting", _mp_pending_text())) if _mp_remote() else super.waiting_reason()

func is_clear() -> bool:
	return bool(_mp_status.get("clear", false)) if _mp_remote() else super.is_clear()

func plate_status(sign_up: bool) -> Array:
	if not _mp_remote():
		return super.plate_status(sign_up)
	return _mp_status.get("plate_sign" if sign_up else "plate", [PLATE_WAITING, _mp_pending_text()]).duplicate()

func hay_per_minute() -> int:
	return int(_mp_status.get("rate", 0)) if _mp_remote() else super.hay_per_minute()

func belts_in_reach() -> int:
	return int(_mp_status.get("belts", 0)) if _mp_remote() else super.belts_in_reach() + ArmRoutes.drops(builds, _shoulder_world(), work_reach()).size()

func _mp_pending_text() -> String:
	return "Roboterstatus wird synchronisiert." if TranslationServer.get_locale().begins_with("de") else "Synchronizing robot arm status."

var _mp_hopper_id := 0

func _mp_hoppers() -> Node:
	if is_instance_valid(mp_transport) and is_instance_valid(mp_transport.mp.world_sync):
		return mp_transport.mp.world_sync.hoppers_sync
	return null

func _choose_drop(count: int, prop: Carryable = null, only: BeltPath = null, require_room: bool = true, skip: BeltPath = null, ahead: float = 0.0, empty_only: bool = false) -> Dictionary:
	var service := _mp_hoppers()
	if not is_instance_valid(service) or count <= 0 or (prop != null and not prop is HayWad):
		_mp_hopper_id = 0
		return _mp_choose_drop(count, prop, only, require_room, skip, ahead, empty_only)
	var row: Dictionary = service.arm_hopper(self, true)
	if row.is_empty():
		var belt := _mp_choose_drop(count, prop, only, require_room, skip, ahead, empty_only)
		if not belt.is_empty():
			_mp_hopper_id = 0
			return belt
		row = service.arm_hopper(self)
	if row.is_empty() or not link_in_reach(service.arm_point(row, self)) or (require_room and not service.arm_room(row.id, count)):
		return {}
	_mp_hopper_id = row.id
	return {"point": service.arm_point(row, self), "forward": Vector3.ZERO, "conveyor": null}

func _mp_choose_drop(count: int, prop: Carryable, only: BeltPath, require_room: bool, skip: BeltPath, ahead: float, empty_only: bool) -> Dictionary:
	var native := super._choose_drop(count, prop, only, require_room, skip, ahead, empty_only)
	if not native.is_empty():
		return native
	for candidate in ArmRoutes.drops(builds, _shoulder_world(), work_reach(), only):
		var path: BeltPath = candidate.conveyor
		if path == skip or not _may_put_on(path) or (empty_only and not _carries_nothing(path)):
			continue
		var release := _release_on_run(path, _put_aim(path, candidate.point), count, prop, require_room, ahead)
		if release.is_empty():
			continue
		candidate.point = release.point
		_drop_fault = FAULT_NONE
		return candidate
	return {}

func _release_on_run(path: BeltPath, point: Vector3, count: int, prop: Carryable, require_room: bool, ahead: float = 0.0) -> Dictionary:
	var release := super._release_on_run(path, point, count, prop, require_room, ahead)
	if not release.is_empty() and not ArmRoutes.valid_drop(path, release.point):
		return {}
	return release

func set_link(path: BeltPath, at: Vector3, role: int) -> int:
	if ArmRoutes.owner_of(path) == null:
		return super.set_link(path, at, role)
	if role not in [LINK_TAKE, LINK_PUT]:
		return link_role(path)
	if role == LINK_PUT:
		path = ArmRoutes.drop_path(path, at)
	if not ArmRoutes.usable(path):
		return LINK_NONE
	at = ArmRoutes.point(path, at, role == LINK_PUT)
	for index in _links.size():
		var link: Dictionary = _links[index]
		if _link_run(link) != path:
			continue
		if int(link.role) == role:
			_links.remove_at(index)
			_links_changed()
			return LINK_NONE
		if not link_in_reach(at):
			return int(link.role)
		link.role = role
		link.at = at
		link.erase("stuck")
		_links_changed()
		return role
	if not link_in_reach(at):
		return LINK_NONE
	_links.append({"role": role, "at": at, "run": path})
	_links_changed()
	return role

func _link_run(link: Dictionary) -> BeltPath:
	var path := super._link_run(link)
	if int(link.get("role", LINK_NONE)) == LINK_PUT and ArmRoutes.owner_of(path) != null:
		path = ArmRoutes.drop_path(path, link.at)
		link.run = path
	return path

func _belt_at(at: Vector3) -> BeltPath:
	var found := super._belt_at(at)
	var distance := found._point_at(found.s_at(at)).distance_to(at) if found != null else LINK_SNAP
	for candidate in ArmRoutes.all(builds):
		var path: BeltPath = candidate
		var d := path._point_at(path.s_at(at)).distance_to(at)
		if d < distance:
			distance = d
			found = path
	return found

func _links_changed() -> void:
	super._links_changed()
	if is_instance_valid(mp_transport):
		mp_transport.queue_setting(self, "mp_links", links_to_save())

func _drop_run_clear() -> bool:
	if _mp_hopper_id > 0 and _drop_run == null:
		var service := _mp_hoppers()
		return is_instance_valid(service) and service.arm_room(_mp_hopper_id, _payload_count)
	return super._drop_run_clear()

func _release_carried_prop(ignore_until: float) -> void:
	if _payload_prop is HayTuft and ArmRoutes.owner_of(_drop_run) != null:
		var item := _payload_prop
		if item.has_meta(PropManager.META_CLAIM) and int(item.get_meta(PropManager.META_CLAIM)) == get_instance_id():
			item.remove_meta(PropManager.META_CLAIM)
		item.set_meta(LiveStrandManager.META_ARM_IGNORE_UNTIL, ignore_until)
		if _drop_run.board_made_body(item, _drop_target, Tech.belt_speed()):
			_payload_prop = null
			return
	super._release_carried_prop(ignore_until)

func _release_payload() -> void:
	if _mp_hopper_id <= 0 or _drop_run != null:
		super._release_payload()
		return
	var service := _mp_hoppers()
	var needle := int(_payload_prop.needle_index) if is_instance_valid(_payload_prop) else -1
	if not is_instance_valid(service) or not service.receive_arm(_mp_hopper_id, _payload_count, needle):
		return
	if is_instance_valid(_payload_prop):
		props.remove(_payload_prop)
	for entry in _payload:
		var body: Variant = entry.get("body")
		if is_instance_valid(body):
			live.consume(body)
	_clear_payload_visual()
	_payload_pose_valid = false
	last_record_seq = -1
	last_cycle_needle = false
	last_cycle_from_field = _pickup_from_field
	completed_cycles += 1
	_note_load(_payload_count)
	_payload.clear()
	_payload_prop = null
	_payload_needle = null
	_payload_count = 0
	_decoy_count = 0
	_mp_hopper_id = 0
