extends ConveyorSplitter

const Model = preload("res://mods/multiplayer/mp_receiver_model.gd")
const Catalog = preload("res://mods/multiplayer/mp_router_catalog.gd")
var port_count := 4
var covered := false
var input_port := 2

func radius() -> float:
	return Catalog.radius(port_count)

func port_local(side: int) -> Vector3:
	var angle := TAU * float(side) / port_count
	return Vector3(sin(angle), 0.0, cos(angle)) * radius()

func port(side: int) -> Vector3:
	return global_transform * port_local(side)

func port_in() -> Vector3:
	return port(input_port)

func port_is_output(side: int) -> bool:
	return side != input_port

func output_sides() -> Array:
	var result := []
	for side in port_count:
		if port_is_output(side):result.append(side)
	return result

func ports() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for side in port_count:result.append(port(side))
	return result

func forward() -> Vector3:
	return -(global_basis * port_local(input_port).normalized())

func arm_travel(side: int) -> Vector3:
	return global_basis * port_local(side).normalized()

func _mouths() -> Array:
	var result := []
	for side in port_count:result.append(port_local(side))
	return result

func _lanes() -> Array:
	var result := []
	for side in port_count:
		var mouth := port_local(side)
		result.append({"mouth": mouth, "travel": mouth.normalized() * (1.0 if port_is_output(side) else -1.0)})
	return result

func footprint() -> Array[Vector4]:
	return [Vector4(global_position.x, global_position.y, global_position.z, radius() + 0.12)]

func _build_model() -> void:
	var meshes := Model.build(self)
	_body = meshes[0]
	_infill = meshes[1]

func _make_infill_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.L_BUILD
	body.collision_mask = 0
	var points := PackedVector3Array()
	for point in Model.polygon(port_count, 0.421):
		points.append(point + Vector3.DOWN * 0.04)
		points.append(point)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body

func _make_sweep() -> Area3D:
	return WyeSweep.make_area(radius())

func _route_points(side: int) -> PackedVector3Array:
	return PackedVector3Array([port_in(), global_position, port(side)])

func _build_routes() -> void:
	for side in output_sides():
		var path := BeltPath.new()
		path.name = "Route%d" % side
		path.records_props = true
		path.record_boost = route_boost
		add_child(path)
		path.build_path(_route_points(side), Cfg.BELT_JOINT_OVERLAP)
		path.set_belt_drawn(false)
		path.gathers_straw = true
		path.bundles_upstream = true
		path.shared_at_end = false
		path.caught.connect(_on_caught.bind(side))
		path.caught_record.connect(_on_caught_record.bind(side))
		_routes[side] = path
	for path in routes():
		path.share_deck(routes())
	_apply_catching()

func routes() -> Array[BeltPath]:
	var result: Array[BeltPath] = []
	for side in output_sides():
		var path := route(side)
		if is_instance_valid(path):result.append(path)
	return result

func _open_side() -> int:
	var sides := output_sides()
	var start := maxi(0, sides.find(next_side))
	for offset in sides.size():
		var side: int = sides[(start + offset) % sides.size()]
		var path := route(side)
		if not is_instance_valid(path):continue
		var target := path.downstream if is_instance_valid(path.downstream) else path.end_deck
		var connected := is_instance_valid(target) and target.accepts_handover(0.25)
		if connected and not path._occupied(0.0, 0.0, 0.25):return side
	return -1

func _apply_catching() -> void:
	var open := _open_side()
	for side in output_sides():
		var path := route(side)
		if not is_instance_valid(path):continue
		path.set_catching(side == open)
		path.set_outlet_held(not is_instance_valid(path.downstream) and not is_instance_valid(path.end_deck))
	_sync_feeder(open)

func _sync_feeder(open: int = -2) -> void:
	if not is_instance_valid(_feeder):return
	if open == -2:open = _open_side()
	_feeder.downstream = route(open if open >= 0 else output_sides()[0])
	_feeder.set_outlet_held(open < 0)

func _on_caught(_body: RigidBody3D, side: int) -> void:
	_advance(side)

func _on_caught_record(_seq: int, _kind: int, _strands: int, side: int) -> void:
	_advance(side)

func _advance(side: int) -> void:
	var sides := output_sides()
	next_side = sides[(maxi(0, sides.find(side)) + 1) % sides.size()]
	_apply_catching()

func factory_tick(_delta: float) -> void:
	_apply_catching()
	_refresh_held()

func is_waiting() -> bool:
	return false

func _show_held() -> void:
	if is_instance_valid(_body):Model.set_held(_body, _drawn_held, _infill)

func has_panel() -> bool:
	return false

func straight_side() -> int:
	return (input_port + port_count / 2) % port_count

func empty() -> bool:
	for path in routes():
		if path.run.count() > 0 or not path._riders.is_empty():return false
	return true

func set_preview_valid(valid: bool) -> void:
	if not placement_preview:return
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("IntakeArrow"):
			mesh.hide()
			continue
		mesh.material_overlay = ConveyorKit.ghost_material(valid)

func build_cost() -> float:
	return Catalog.build_cost(port_count)

func to_dict() -> Dictionary:
	return {"type": Catalog.id(port_count, true), "position": global_position, "yaw": global_rotation.y, "splitter_input": input_port, "next_side": next_side, "covered": covered}

func set_covered(on: bool) -> void:
	covered = on
	if is_instance_valid(_body):
		Model.set_covered(self, on)
