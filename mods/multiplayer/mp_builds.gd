extends "res://scripts/build/build_manager.gd"

const BuildSnapshot = preload("res://mods/multiplayer/mp_build_snapshot.gd")
const ScannerDemolition = preload("res://mods/multiplayer/mp_scanner_demolition.gd")


var mp_world: Node
var _mp_repairing_water := false
var _mp_scanner_removing: Node3D


func _clear_mirrored_records() -> void:
	if not is_instance_valid(mp_world) or not mp_world._is_client():
		return
	for path in BeltPath._live:
		if is_instance_valid(path) and path.is_inside_tree():
			path.run.clear()


func reverse_conveyor(conveyor: Conveyor) -> bool:
	_clear_mirrored_records()
	return super.reverse_conveyor(conveyor)


func _demolish_one(building: Node3D) -> float:
	_clear_mirrored_records()
	if not is_instance_valid(building) or building.is_queued_for_deletion() or not building is HaystackScanner or not scanners.has(building):
		return super._demolish_one(building)
	var snapshot := ScannerDemolition.capture(building, mp_world, scanners)
	var previous := _mp_scanner_removing
	_mp_scanner_removing = building
	var refund := super._demolish_one(building)
	_mp_scanner_removing = previous
	if building.is_queued_for_deletion():
		ScannerDemolition.release(snapshot, mp_world)
	return refund


func _held_needles_of(building: Node3D) -> PackedInt32Array:
	if is_instance_valid(building) and building == _mp_scanner_removing:
		return PackedInt32Array()
	return super._held_needles_of(building)


func clear() -> void:
	_clear_mirrored_records()
	super.clear()


func upgrade_arm(arm: RoboticArm) -> bool:
	if not is_instance_valid(mp_world) or not is_instance_valid(mp_world.economy) or not mp_world.mp.active() or mp_world.economy.executing:
		return super.upgrade_arm(arm)
	var actor: Player = mp_world.player
	return mp_world.economy.request("arm_upgrade", {"target": BuildSnapshot.row(arm),
		"tier": arm.tier_index, "max_price": arm_upgrade_price(arm),
		"body": actor.global_transform, "camera": actor.camera.global_transform}) != 0


func demolish_blocked_reason(building: Node3D) -> String:
	if is_instance_valid(building) and building is HaystackScanner:
		return ""
	if is_instance_valid(mp_world) and mp_world._is_client() and mp_world._applying_builds:
		return ""
	return super.demolish_blocked_reason(building)


func reshape_hay_lift(lift: HayLift, carries_down: bool, turn: int) -> Dictionary:
	if not is_instance_valid(mp_world) or not mp_world.mp.active():
		return super.reshape_hay_lift(lift, carries_down, turn)
	var out := {"lift": lift, "error": ""}
	var economy: Variant = mp_world.economy
	if is_instance_valid(economy) and economy.executing and mp_world.mp.is_host:
		return super.reshape_hay_lift(lift, carries_down, turn)
	if not is_instance_valid(lift) or not lift.is_inside_tree() or lift.is_queued_for_deletion():
		out["error"] = mp_world.mp.t("building_missing")
		return out
	if turn < 0 or turn > 3:
		out["error"] = mp_world.mp.t("building_invalid")
		return out
	var actor: Variant = mp_world.player
	if not is_instance_valid(economy) or not is_instance_valid(actor) or not is_instance_valid(actor.camera):
		out["error"] = mp_world.mp.t("economy_wait")
		return out
	if economy.request("lift_reshape", {"target": lift.to_dict(), "down": carries_down, "turn": turn,
			"body": actor.global_transform, "camera": actor.camera.global_transform}) == 0:
		out["error"] = mp_world.mp.t("economy_wait")
	return out


func restring_for_reach() -> void:
	if is_instance_valid(mp_world) and mp_world._is_client():
		return
	super.restring_for_reach()


func request_t_configuration(t: Node3D, manual: bool, roles: Array[int] = []) -> int:
	if not is_instance_valid(mp_world) or not mp_world.mp.active() or not is_instance_valid(t) \
			or not t.is_inside_tree() or t.is_queued_for_deletion() \
			or not (t is ConveyorTSplitter or t is ConveyorTJoiner):
		return 0
	var economy: Variant = mp_world.economy
	var actor: Variant = mp_world.player
	if not is_instance_valid(economy) or not is_instance_valid(actor) or not is_instance_valid(actor.camera):
		return 0
	return economy.request("t_configure", {"target": t.to_dict(), "manual": manual, "roles": roles,
		"body": actor.global_transform, "camera": actor.camera.global_transform})


func set_t_by_hand(t: Node3D, roles: Array[int]) -> Dictionary:
	if not is_instance_valid(mp_world) or not mp_world.mp.active() \
			or (is_instance_valid(mp_world.economy) and mp_world.economy.executing and mp_world.mp.is_host):
		return super.set_t_by_hand(t, roles)
	var error: String = "" if request_t_configuration(t, true, roles) != 0 else mp_world.mp.t("economy_wait")
	return {"t": t, "error": error}


func set_t_by_belts(t: Node3D) -> Node3D:
	if not is_instance_valid(mp_world) or not mp_world.mp.active() \
			or (is_instance_valid(mp_world.economy) and mp_world.economy.executing and mp_world.mp.is_host):
		return super.set_t_by_belts(t)
	request_t_configuration(t, false)
	return t


func _swap_t(old: Node3D, made: Node3D) -> void:
	var revision := int(old.get_meta("mp_t_revision", 0))
	if revision > int(made.get_meta("mp_t_revision", 0)):
		made.set_meta("mp_t_revision", revision)
	super._swap_t(old, made)


func rebuild_water_joints() -> void:
	var repaired := false
	if not _mp_repairing_water and not ghost_reading and is_instance_valid(mp_world) \
			and mp_world.mp.active() and mp_world.mp.is_host:
		_mp_repairing_water = true
		for pulper in pulpers:
			if not is_instance_valid(pulper) or not pulper.is_inside_tree() or pulper.is_queued_for_deletion() or pulper.placement_preview:
				continue
			for tap in pulper.taps:
				if is_instance_valid(tap) and pulper.is_pending_tap(tap) and _mp_pipe_ends_at(tap.global_position):
					pulper.commit_tap(tap)
					repaired = true
			var before: int = pulper.taps.size()
			pulper.adopt_loose_ends()
			repaired = repaired or pulper.taps.size() != before
		_mp_repairing_water = false
	super.rebuild_water_joints()
	if repaired:
		if water != null:
			water.rebuild()
		changed.emit()

func _mp_pipe_ends_at(point: Vector3) -> bool:
	for main in water_mains:
		if not is_instance_valid(main) or not main.is_inside_tree() or main.is_queued_for_deletion():
			continue
		for endpoint in main.endpoints():
			if endpoint.distance_to(point) <= Cfg.PIPE_JOIN_TOLERANCE:
				return true
	return false

func add_receiver(at: Vector3, yaw: float, count: int, output: int = 0) -> ConveyorJoiner:
	var receiver := preload("res://mods/multiplayer/mp_receiver.gd").new()
	receiver.name = _free_name("Receiver", joiners.size())
	receiver.port_count = count
	receiver.output_port = output
	receiver.next_side = 1 if output == 0 else 0
	receiver.setup(at, yaw)
	joiners.append(receiver)
	add_child(receiver)
	rebuild_junctions()
	_refresh_wye_supports_at(receiver.ports())
	refit_runs_at(receiver.ports())
	changed.emit()
	return receiver

func from_array(data: Array) -> void:
	var native_rows := []
	var receiver_rows := []
	for row in data:
		if row is Dictionary and row.get("type") in ["mp_receiver4", "mp_receiver8"]:
			receiver_rows.append(row)
		else:
			native_rows.append(row)
	await super.from_array(native_rows)
	for row in receiver_rows:
		var count := 4 if row.type == "mp_receiver4" else 8
		if not (row.get("position") is Vector3) or not row.position.is_finite():
			continue
		var receiver := add_receiver(row.position, float(row.get("yaw", 0.0)), count, clampi(int(row.get("receiver_output", 0)), 0, count - 1))
		var side := int(row.get("next_side", 0))
		receiver.next_side = side if side in receiver.inlet_sides() else receiver.inlet_sides()[0]
