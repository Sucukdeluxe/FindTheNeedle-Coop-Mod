extends ConveyorJoiner

const Model = preload("res://mods/multiplayer/mp_receiver_model.gd")
var port_count := 4
var covered := false
var output_port := 0
var _transfer_surfaces: Array = []

func _ready() -> void:
	super._ready()
	set_physics_process(not placement_preview)

func radius() -> float:
	return preload("res://mods/multiplayer/mp_router_catalog.gd").radius(port_count)

func port_local(side: int) -> Vector3:
	var angle := TAU * float(side) / float(port_count)
	return Vector3(sin(angle), 0.0, cos(angle)) * radius()

func port_is_output(side: int) -> bool:
	return side == output_port

func inlet_sides() -> Array:
	var result := []
	for side in port_count:
		if side != output_port:
			result.append(side)
	return result

func port(side: int) -> Vector3:
	return global_transform * port_local(side)

func port_out() -> Vector3:
	return port(output_port)

func ports() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for side in port_count:
		result.append(port(side))
	return result

func forward() -> Vector3:
	return global_basis * port_local(output_port).normalized()

func _exit_local() -> Vector3:
	return port_local(output_port).normalized()

func _arm_name(side: int) -> String:
	return "Port%d" % side

func _mouths() -> Array:
	var result := []
	for side in port_count:
		result.append(port_local(side))
	return result

func _lanes() -> Array:
	var result := []
	for side in port_count:
		var mouth := port_local(side)
		result.append({"mouth": mouth, "travel": mouth.normalized() * (1.0 if side == output_port else -1.0)})
	return result

func build_cost() -> float:
	return preload("res://mods/multiplayer/mp_router_catalog.gd").build_cost(port_count)

func to_dict() -> Dictionary:
	return {"type": "mp_receiver%d" % port_count, "position": global_position,
		"yaw": global_rotation.y, "receiver_output": output_port, "next_side": next_side, "covered": covered}

func _make_sweep() -> Area3D:
	return WyeSweep.make_area(radius())

func empty() -> bool:
	for path in paths():
		if path.run.count() > 0 or not path._riders.is_empty():
			return false
	return true

func paths() -> Array[BeltPath]:
	var out: Array[BeltPath] = []
	for side in inlet_sides():
		var branch := _arms.get(side) as BeltPath
		if is_instance_valid(branch):
			out.append(branch)
	if is_instance_valid(_out):
		out.append(_out)
	return out

func _build_paths() -> void:
	_out = BeltPath.new()
	_out.name = "Out"
	_out.records_props = true
	_out.record_boost = arm_boost
	add_child(_out)
	_out.build_path(PackedVector3Array([global_position, port_out()]), Cfg.BELT_JOINT_OVERLAP)
	_hide_sections(_out)
	_out.gathers_straw = true
	for side in inlet_sides():
		var branch := BeltPath.new()
		branch.name = "Arm%s" % _arm_name(side)
		branch.records_props = true
		branch.record_boost = arm_boost
		add_child(branch)
		branch.build_path(_arm_points(side), Cfg.BELT_JOINT_OVERLAP)
		_hide_sections(branch)
		branch.gathers_straw = true
		branch.bundles_straw = true
		branch.bundles_upstream = true
		branch.downstream = _out
		branch.set_catch_dead_zone(Cfg.JOINER_ARM_DEAD_ZONE)
		branch.set_hold_back(Cfg.JOINER_ARM_DEAD_ZONE)
		branch.handed_on.connect(_on_arm_gave.bind(side))
		branch.handed_on_record.connect(_on_arm_gave_record.bind(side))
		_arms[side] = branch
	var all := paths()
	if _out != null:
		_out.shared_at_end = false
	for path in all:
		path.share_deck(all)
	var inner := Model.core_radius(port_count, 0.421) * cos(PI / float(port_count))
	for path in all:
		var outward := -1.0 if path != _out else 1.0
		for span in path._spans:
			var deck: StaticBody3D = span.body
			if not is_instance_valid(deck):
				continue
			for child in deck.get_children():
				var collision := child as CollisionShape3D
				if collision == null or not collision.shape is BoxShape3D:
					continue
				var box := collision.shape.duplicate() as BoxShape3D
				var radial := deck.global_basis.z * outward
				var centre := (deck.to_global(collision.position) - global_position).dot(radial)
				var old_length := box.size.z
				var outer := centre + old_length * 0.5
				if outer <= inner:
					collision.free()
					continue
				if centre - old_length * 0.5 >= inner:
					continue
				box.size.z = outer - inner
				collision.shape = box
				collision.position.z += outward * (old_length - box.size.z) * 0.5
	_serve()

func full_rate() -> bool:
	if _offer != null or (_sweep != null and _sweep.has_overlapping_bodies()):
		return true
	if old_machines:
		for path in paths():
			if path.is_busy():
				return true
		return false
	var quick := BeltPath.rate_direct
	for side in inlet_sides():
		var branch := _arms.get(side) as BeltPath
		if branch != null and not (quick and branch._calm) and branch.is_busy():
			return true
	return _out != null and not (quick and _out._calm) and _out.is_busy()

func factory_tick(_delta: float) -> void:
	if _jam_step():
		return
	_serve()
	_refresh_held()
	if _sweep != null and _sweep.has_overlapping_bodies():
		WyeSweep.run(_sweep, self, _sweep_lanes(), Cfg.BELT_SPEED, _exit_local())

func _any_awake() -> bool:
	for side in inlet_sides():
		var branch = _arms.get(side)
		if branch != null and is_instance_valid(branch) and not (branch as BeltPath)._asleep:
			return true
	return _out != null and is_instance_valid(_out) and not _out._asleep

func _serve() -> void:
	if _jam.suspended():
		return
	var sides := inlet_sides()
	if sides.is_empty():
		return
	if _crossing():
		for s in sides:
			var held := _arms.get(s) as BeltPath
			if held != null:
				held.set_outlet_held(true)
		return
	var side := next_side if next_side in sides else int(sides[0])
	var due_next := -1 if _due(side) else _first_due_after(side)
	if due_next >= 0:
		side = due_next
	elif _turn_to_nearer() and not _due(side):
		var nearer := _nearest_after(side)
		if _to_door(nearer) < _to_door(side):
			side = nearer
	var n := sides.size()
	var at := sides.find(_serving)
	if at < 0:
		_serving = side
		at = maxi(0, sides.find(_serving))
	var deepest := _committed_by(_serving)
	var deep_side := _serving
	for k in range(1, n):
		var s: int = sides[(at + k) % n]
		var by := _committed_by(s)
		if by > deepest:
			deepest = by
			deep_side = s
	if deepest > 0.0:
		side = deep_side
	side = _doorway(side)
	_serving = side
	for s in sides:
		var branch := _arms.get(s) as BeltPath
		if branch != null:
			branch.set_outlet_held(s != side)
	_park_behind_front(side)

func _doorway(side: int) -> int:
	if _out == null or not is_instance_valid(_out):
		return side
	if old_join_mouth:
		_out.set_gate_pass(null)
		return side
	var sides := inlet_sides()
	var n := sides.size()
	var at := maxi(0, sides.find(side))
	var count := 0
	var first := -1
	var side_in := false
	for k in range(n):
		var s: int = sides[(at + k) % n]
		if _in_mouth(s):
			count += 1
			if first < 0:
				first = s
			if s == side:
				side_in = true
	if count == 1 or (count > 1 and not side_in):
		side = first
	var branch := _arms.get(side) as BeltPath
	if _out.set_gate_pass(branch if count > 1 else null) and branch != null:
		branch.wake()
	return side

func _jam_paths() -> Array:
	var out: Array = []
	for side in inlet_sides():
		var branch := _arms.get(side) as BeltPath
		if branch != null:
			out.append(branch)
	if _out != null and is_instance_valid(_out) and not _out._outlet_held:
		out.append(_out)
	return out

func _break_jam(stuck: BeltPath) -> void:
	var side := -1
	for s in inlet_sides():
		if _arms.get(s) == stuck:
			side = s
	if side < 0:
		stuck.wake()
		return
	_serving = side
	for s in inlet_sides():
		var branch := _arms.get(s) as BeltPath
		if branch != null:
			branch.set_outlet_held(s != side)
			branch.hold_before(-1.0)
			branch.wake()
	if _out != null and is_instance_valid(_out):
		_out.set_gate_pass(stuck)
		_out.wake()

func _on_arm_gave(body: RigidBody3D, side: int) -> void:
	next_side = _next_after(side)
	_offer = body
	_flight = Engine.get_physics_frames()
	_hold_arm(side)

func _on_arm_gave_record(_seq: int, _kind: int, _strands: int, side: int) -> void:
	next_side = _next_after(side)
	_offer = null
	_flight = Engine.get_physics_frames()
	_jam.release()
	if old_merge:
		_hold_arm(side)
	else:
		_serve()

func _park_behind_front(served: int) -> void:
	for s in inlet_sides():
		var branch := _arms.get(s) as BeltPath
		if branch == null:
			continue
		var on: bool = BeltPath.old_wye or not _turn_to_nearer() or s != served or _first_due_after(s) >= 0
		if branch.run.wye != on:
			branch.run.wye = on
			branch.wake()

func _next_after(side: int) -> int:
	var sides := inlet_sides()
	return int(sides[(maxi(0, sides.find(side)) + 1) % sides.size()])

func _first_due_after(side: int) -> int:
	var sides := inlet_sides()
	var n := sides.size()
	var at := maxi(0, sides.find(side))
	for k in range(1, n):
		var s: int = sides[(at + k) % n]
		if _due(s):
			return s
	return -1

func _nearest_after(side: int) -> int:
	var sides := inlet_sides()
	var n := sides.size()
	var at := maxi(0, sides.find(side))
	var best: int = sides[(at + 1) % n]
	var best_d := _to_door(best)
	for k in range(2, n):
		var s: int = sides[(at + k) % n]
		var d := _to_door(s)
		if d < best_d:
			best = s
			best_d = d
	return best

func _build_model() -> void:
	var meshes := Model.build(self)
	_body = meshes[0]
	_infill = meshes[1]

func _show_held() -> void:
	if is_instance_valid(_body):
		Model.set_held(_body, _drawn_held, _infill)

func footprint() -> Array[Vector4]:
	return [Vector4(global_position.x, global_position.y, global_position.z, radius() + 0.12)]

func _make_infill_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0
	var outline := Model.polygon(port_count, 0.421)
	var hub := PackedVector3Array()
	for point in outline:
		hub.append(point.normalized() * 0.3)
	_add_transfer_surface(body, hub, output_port)
	for side in port_count:
		var previous := posmod(side - 1, port_count)
		_add_transfer_surface(body, PackedVector3Array([outline[previous], outline[side], hub[side], hub[previous]]), side)
	return body

func _add_transfer_surface(parent: Node3D, outline: PackedVector3Array, side: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.L_BUILD
	body.collision_mask = 0
	var points := PackedVector3Array()
	for point in outline:
		points.append(point)
		points.append(point + Vector3.DOWN * 0.04)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	_transfer_surfaces.append({"body": body, "side": side})
	_refresh_transfer_surfaces()

func _physics_process(_delta: float) -> void:
	_refresh_transfer_surfaces()

func _refresh_transfer_surfaces() -> void:
	for surface in _transfer_surfaces:
		var side: int = surface.side
		var path := _out if side == output_port else arm(side)
		if not is_instance_valid(path):
			continue
		var direction := global_basis * port_local(side).normalized() * (1.0 if side == output_port else -1.0)
		var velocity := Vector3.ZERO if path._deck_shows_held else direction * path.drive_speed
		if not surface.body.constant_linear_velocity.is_equal_approx(velocity):
			surface.body.constant_linear_velocity = velocity

func set_preview_valid(valid: bool) -> void:
	if not placement_preview:
		return
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("IntakeArrow"):
			mesh.hide()
			continue
		mesh.material_overlay = ConveyorKit.ghost_material(valid)

func set_covered(on: bool) -> void:
	covered = on
	if is_instance_valid(_body):
		Model.set_covered(self, on)
