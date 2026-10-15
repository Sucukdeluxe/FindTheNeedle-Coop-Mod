extends ConveyorJoiner

const Model = preload("res://mods/multiplayer/mp_receiver_model.gd")
var port_count := 4
var output_port := 0

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
		"yaw": global_rotation.y, "receiver_output": output_port, "next_side": next_side}

func empty() -> bool:
	for path in paths():
		if path.run.count() > 0 or not path._riders.is_empty():
			return false
	return true

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

func set_preview_valid(valid: bool) -> void:
	if not placement_preview:
		return
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("IntakeArrow"):
			mesh.hide()
			continue
		mesh.material_overlay = ConveyorKit.ghost_material(valid)
