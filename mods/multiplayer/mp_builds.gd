extends "res://scripts/build/build_manager.gd"

func _mp_sale_stations() -> Node:
	var session := get_node_or_null("/root/MPMod")
	if not is_instance_valid(session) or not is_instance_valid(session.world_sync):
		return null
	var hoppers: Node = session.world_sync.get("hoppers_sync")
	return hoppers.get("sale_stations") if is_instance_valid(hoppers) else null

func snap_stand_port(point: Vector3) -> Vector3:
	var hopper := _mp_hoppers()
	if is_instance_valid(hopper):
		var port: Dictionary = hopper.input_at(point, Cfg.STAND_SNAP_RADIUS)
		if not port.is_empty():return port.point
	var service := _mp_sale_stations()
	if is_instance_valid(service):
		var station: Node3D = service.port_at(point, Cfg.STAND_SNAP_RADIUS)
		if is_instance_valid(station):
			return station.belt_entry_point()
	return super.snap_stand_port(point)

func port_bearing_at(point: Vector3) -> Vector3:
	var hopper := _mp_hoppers()
	if is_instance_valid(hopper):
		var port: Dictionary = hopper.input_at(point)
		if not port.is_empty():return port.bearing
	var service := _mp_sale_stations()
	if is_instance_valid(service):
		var station: Node3D = service.port_at(point)
		if is_instance_valid(station):
			return station.intake_forward()
	return super.port_bearing_at(point)

func intake_at(point: Vector3) -> bool:
	var hopper := _mp_hoppers()
	if is_instance_valid(hopper) and not hopper.input_at(point).is_empty():return true
	var service := _mp_sale_stations()
	return (is_instance_valid(service) and is_instance_valid(service.port_at(point))) or super.intake_at(point)

func _mp_hoppers() -> Node:
	var session := get_node_or_null("/root/MPMod")
	return session.world_sync.hoppers_sync if is_instance_valid(session) and is_instance_valid(session.world_sync) else null

const WallPalette = preload("res://mods/multiplayer/mp_wall_palette.gd")
const RouterCatalog = preload("res://mods/multiplayer/mp_router_catalog.gd")
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

func add_multi_splitter(at: Vector3, yaw: float, count: int, input: int = -1) -> ConveyorSplitter:
	var splitter := preload("res://mods/multiplayer/mp_multi_splitter.gd").new()
	splitter.name = _free_name("MultiSplitter", splitters.size())
	splitter.port_count = count
	splitter.input_port = count / 2 if input < 0 else input
	splitter.next_side = 0 if splitter.input_port != 0 else 1
	splitter.setup(at, yaw)
	splitters.append(splitter)
	add_child(splitter)
	rebuild_junctions()
	_refresh_wye_supports_at(splitter.ports())
	refit_runs_at(splitter.ports())
	changed.emit()
	return splitter

func receiver_splice_fits(belt: Conveyor, at: Vector3, yaw: float, count: int) -> bool:
	if count not in RouterCatalog.COUNTS or not conveyors.has(belt) or not is_instance_valid(belt) or belt.is_queued_for_deletion():
		return false
	var direction := Basis(Vector3.UP, yaw).z
	var radius := RouterCatalog.radius(count)
	var incoming := at - direction * radius
	var outgoing := at + direction * radius
	var taken: Array[Conveyor] = _splice_taken(belt, incoming, outgoing)
	if taken.is_empty():
		return false
	var points: Array[Vector3] = [taken[0].a, incoming, at, outgoing, taken[-1].b]
	var plans: Array[Dictionary] = []
	for i in range(points.size() - 1):
		if points[i].distance_to(points[i + 1]) < 0.01:
			return false
		var run := BeltRun.new()
		run.set_line(PackedVector3Array([points[i], points[i + 1]]))
		run.catching = true
		plans.append({"a": points[i], "b": points[i + 1], "run": run})
	for k in range(taken.size() - 1, -1, -1):
		var source := taken[k]
		for i in range(source.run.first(), source.run.first() + source.run.count()):
			var record: Dictionary = source.run.record(i)
			var position: Vector3 = source._point_at(clampf(float(record.s), 0.0, source.path_length()))
			var nearest := plans.duplicate()
			nearest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _receiver_plan_point(a, position).distance_squared_to(position) < _receiver_plan_point(b, position).distance_squared_to(position))
			var accepted := false
			for plan in nearest:
				var run: BeltRun = plan.run
				var want: float = plan.a.distance_to(_receiver_plan_point(plan, position))
				var spot := want
				if run.count() > 0:
					var rear := run.first() + run.count() - 1
					if want <= run.s_of(rear):
						var reach := float(record.reach)
						var spacing := maxf(run.spacing, maxf(reach * 2.0, reach + run.reach_of(rear)))
						spot = minf(want, run.s_of(rear) - spacing - 0.0001)
						if spot < 0.0 or want - spot > BeltPath.SPLICE_GIVE:
							continue
				if run.board_record(record, spot, float(record.speed), false):
					accepted = true
					break
			if not accepted:
				return false
	var slots: Array[Dictionary] = []
	for plan in plans:
		var run: BeltRun = plan.run
		for i in range(run.first(), run.first() + run.count()):
			slots.append({"position": _receiver_plan_at(plan, run.s_of(i), run.side_of(i)), "reach": run.reach_of(i)})
	var across := Vector3(direction.z, 0.0, -direction.x)
	for source in taken:
		for rider in source._riders:
			if not is_instance_valid(rider.body):
				continue
			var point: Vector3 = source._point_at(rider.s)
			var nearest := plans.duplicate()
			nearest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _receiver_plan_point(a, point).distance_squared_to(point) < _receiver_plan_point(b, point).distance_squared_to(point))
			var plan: Dictionary = nearest[0]
			var position := _receiver_plan_at(plan, plan.a.distance_to(_receiver_plan_point(plan, point)), rider.side)
			for slot in slots:
				var offset: Vector3 = position - slot.position
				var reach := float(rider.reach) + float(slot.reach)
				if absf(offset.dot(direction)) <= maxf(reach, Cfg.STRAND_THICK * 2.0) and absf(offset.dot(across)) <= maxf(reach, Cfg.STRAND_THICK * 6.0):
					return false
			slots.append({"position": position, "reach": rider.reach})
	return true

static func _receiver_plan_point(plan: Dictionary, point: Vector3) -> Vector3:
	var axis: Vector3 = plan.b - plan.a
	return plan.a + axis * clampf((point - plan.a).dot(axis) / axis.length_squared(), 0.0, 1.0)

static func _receiver_plan_at(plan: Dictionary, s: float, side: float) -> Vector3:
	return plan.a + (plan.b - plan.a).normalized() * s + BeltPath.run_basis(plan.a, plan.b).x * side

func splice_receiver(belt: Conveyor, at: Vector3, yaw: float, count: int, distributor: bool = false) -> Node3D:
	if not receiver_splice_fits(belt, at, yaw, count):
		return null
	var direction := Basis(Vector3.UP, yaw).z
	var radius := RouterCatalog.radius(count)
	var build := func() -> Node3D: return add_multi_splitter(at, yaw, count) if distributor else add_receiver(at, yaw, count)
	return splice_built(belt, at - direction * radius, at + direction * radius, build, _receiver_through)

static func _receiver_through(receiver: Node3D) -> Array[BeltPath]:
	var paths: Array[BeltPath] = []
	if is_instance_valid(receiver) and receiver is ConveyorSplitter:
		paths.append(receiver.route(receiver.straight_side()))
	elif is_instance_valid(receiver):
		paths.append(receiver.arm(receiver.port_count / 2))
		paths.append(receiver.out_path())
	return paths

func from_array(data: Array) -> void:
	var native_rows := []
	var receiver_rows := []
	for row in data:
		if row is Dictionary and row.get("type") in RouterCatalog.ids():
			receiver_rows.append(row)
		else:
			native_rows.append(row)
	await super.from_array(native_rows)
	for row in native_rows:
		if not (row is Dictionary) or row.get("type") != "wall":
			continue
		var color: Variant = row.get("mp_wall_color", 0)
		color = clampi(color, 0, 4) if color is int else 0
		for wall in walls:
			if wall.a == row.get("a") and wall.b == row.get("b"):
				WallPalette.apply(wall, color)
				break
	for row in receiver_rows:
		var count := RouterCatalog.count_for(row.type)
		var distributor := RouterCatalog.is_distributor(row.type)
		if not (row.get("position") is Vector3) or not row.position.is_finite():
			continue
		var receiver: Node3D
		if distributor:
			receiver = add_multi_splitter(row.position, float(row.get("yaw", 0.0)), count, clampi(int(row.get("splitter_input", count / 2)), 0, count - 1))
		else:
			receiver = add_receiver(row.position, float(row.get("yaw", 0.0)), count, clampi(int(row.get("receiver_output", 0)), 0, count - 1))
		var side := int(row.get("next_side", 0))
		var sides: Array = receiver.output_sides() if distributor else receiver.inlet_sides()
		receiver.next_side = side if side in sides else sides[0]

func add_wall(from: Vector3, to: Vector3, kind: YardWall.Bay) -> YardWall:
	var wall := super.add_wall(from, to, kind)
	var color: int = int(get_meta("mp_wall_color")) if has_meta("mp_wall_color") else 0
	return WallPalette.apply(wall, color)

func id_of(building: Node3D) -> String:
	var id := super.id_of(building)
	if building is YardWall and "mp_wall_color" in building:
		var color: int = building.get("mp_wall_color")
		if color > 0 and color < WallPalette.KEYS.size() and id in WallPalette.BASE_IDS:
			return "mp_%s_%s" % [id, WallPalette.KEYS[color]]
	return id
