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

func empty() -> bool:
	for path in paths():
		if path.run.count() > 0 or not path._riders.is_empty():
			return false
	return true

func _build_paths() -> void:
	super._build_paths()
	var inner := Model.core_radius(port_count, 0.421) * cos(PI / float(port_count))
	for path in paths():
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
