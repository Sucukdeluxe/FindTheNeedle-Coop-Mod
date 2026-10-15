extends ConveyorJoiner

const Shapes = preload("res://mods/multiplayer/mp_hopper_model.gd")
var port_count := 4
var output_port := 0

func radius() -> float:
	return 1.25 if port_count == 4 else 2.05

func port_local(side: int) -> Vector3:
	var angle := TAU * float(side) / float(port_count)
	return Vector3(sin(angle), 0.0, cos(angle)) * radius()

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
	return 2000.0 if port_count == 4 else 5000.0

func to_dict() -> Dictionary:
	return {"type": "mp_receiver%d" % port_count, "position": global_position,
		"yaw": global_rotation.y, "receiver_output": output_port, "next_side": next_side}

func empty() -> bool:
	for path in paths():
		if path.run.count() > 0 or not path._riders.is_empty():
			return false
	return true

func _build_model() -> void:
	Shapes._make_materials()
	var mesh := ArrayMesh.new()
	for material in 3:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		if material == 0:
			Shapes._box(surface, Vector3(0, -0.11, 0), Vector3(radius() * 1.24, 0.22, radius() * 1.24))
			for side in port_count:
				var direction := port_local(side).normalized()
				Shapes._beam(surface, Vector3(0,-0.08,0), direction * radius() + Vector3(0,-0.08,0), 0.16, Cfg.BELT_WIDTH)
		elif material == 1:
			for side in port_count:
				var end := port_local(side)
				var along := end.normalized()
				var across := Vector3(along.z, 0, -along.x)
				Shapes._cylinder(surface, end * 0.85 + Vector3(0,-0.22,0), across, 0.10, Cfg.BELT_WIDTH + 0.10)
				for sign in [-1.0, 1.0]:
					var offset: Vector3 = across * sign * Cfg.BELT_WIDTH * 0.51 + Vector3.UP * 0.10
					Shapes._beam(surface, end * 0.6 + offset, end + offset, 0.04, 0.20)
		else:
			Shapes._box(surface, Vector3(0,-0.30,0), Vector3(radius(), 0.12, radius()))
		surface.set_material(Shapes._materials[material])
		surface.commit(mesh)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = mesh
	add_child(_body)
	_infill = _make_infill()
	add_child(_infill)
	for side in port_count:
		var label := Label3D.new()
		label.text = str(side + 1) + "\n" + ("OUT" if side == output_port else "IN")
		label.font_size = 30
		label.pixel_size = 0.005
		label.position = port_local(side) * 0.76 + Vector3.UP * 0.05
		label.rotation = Vector3(-PI * 0.5, 0, -TAU * side / port_count)
		label.modulate = Color(1.0, 0.77, 0.28) if side == output_port else Color(0.9,0.95,0.95)
		add_child(label)

func _serve() -> void:
	for path in _arms.values():
		if is_instance_valid(path):
			path.set_outlet_held(true)

func factory_tick(_delta: float) -> void:
	if not is_instance_valid(_out):
		return
	_serve()
	var sides := inlet_sides()
	var start := maxi(0, sides.find(next_side))
	for offset in sides.size():
		var side: int = sides[(start + offset) % sides.size()]
		var path: BeltPath = _arms.get(side)
		if not is_instance_valid(path):
			continue
		for rider in path._riders:
			if not is_instance_valid(rider.body) or float(rider.s) < path.path_length() - 0.35 - float(rider.reach):
				continue
			if _out._occupied(0.0, 0.0, maxf(0.25, float(rider.reach))):
				continue
			rider.side = 0.0
			rider.slide = 0.0
			if path.pass_rider_to(rider.body, _out, 0.0):
				next_side = sides[(start + offset + 1) % sides.size()]
				_refresh_held()
				return
		if path.run.count() == 0:
			continue
		var index := path.run.first()
		var record: Dictionary = path.run.record(index)
		if float(record.s) < path.path_length() - 0.35 - float(record.reach):
			continue
		if _out._occupied(0.0, 0.0, float(record.reach)) or not _out.run.board_record(record, 0.0, float(record.speed), false):
			continue
		path.take_record_at(index)
		_out.wake()
		BeltPath._put_load(_out.get_instance_id(), _out._ride_load())
		next_side = sides[(start + offset + 1) % sides.size()]
		break
	_refresh_held()
	if _sweep != null and _sweep.has_overlapping_bodies():
		WyeSweep.run(_sweep, self, _sweep_lanes(), Cfg.BELT_SPEED, _exit_local())
