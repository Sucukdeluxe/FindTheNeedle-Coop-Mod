extends RefCounted

static func core_radius(count: int, half_width: float = 0.49) -> float:
	return half_width / sin(PI / float(count))

static func polygon(count: int, half_width: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for side in count:
		var angle := TAU * (float(side) + 0.5) / float(count)
		points.append(Vector3(sin(angle), 0.0, cos(angle)) * core_radius(count, half_width))
	return points

static func build(receiver: Node3D) -> Array:
	var count: int = receiver.port_count
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(frame, polygon(count, 0.49), -0.018, -0.18)
	var steel := ConveyorKit.frame_material()
	frame.set_material(steel)
	frame.generate_tangents()
	var body := MeshInstance3D.new()
	body.name = "Frame"
	body.mesh = frame.commit()
	receiver.add_child(body)
	var deck := ArrayMesh.new()
	var deck_running := {}
	var edge_points := polygon(count, 0.421)
	for side in count:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var direction: Vector3 = receiver.port_local(side).normalized()
		var across := Vector3(direction.z, 0.0, -direction.x)
		var left := edge_points[(side + count - 1) % count]
		var right := edge_points[side]
		for point in [Vector3.ZERO, right, left]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(point.dot(across), point.dot(direction)))
			surface.add_vertex(point + Vector3.UP * 0.002)
		var material := ConveyorKit.belt_material_fast() if receiver.port_is_output(side) else ConveyorKit.belt_material_fast_reversed()
		surface.set_material(material)
		surface.generate_tangents()
		surface.commit(deck)
		deck_running[side] = material
	var infill := MeshInstance3D.new()
	infill.name = "CentralDeck"
	infill.mesh = deck
	infill.set_meta("receiver_running", deck_running)
	receiver.add_child(infill)
	var hardware := SurfaceTool.new()
	hardware.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shared_corner := core_radius(count) * 0.96
	for side in count:
		var end: Vector3 = receiver.port_local(side)
		var direction := end.normalized()
		var across := Vector3(direction.z, 0.0, -direction.x)
		var start := direction * (core_radius(count, 0.421) * cos(PI / count) - 0.012)
		var length := start.distance_to(end)
		var branch := MeshInstance3D.new()
		branch.name = "Branch%d" % side
		branch.mesh = ConveyorKit.segment_mesh()
		branch.transform = Transform3D(Basis(across, Vector3.UP, direction).scaled_local(Vector3(1.0, 1.0, length)), (start + end) * 0.5)
		var running := {}
		for surface in branch.mesh.get_surface_count():
			var material := branch.mesh.surface_get_material(surface)
			if material == ConveyorKit.belt_material():
				material = ConveyorKit.belt_material_fast() if receiver.port_is_output(side) else ConveyorKit.belt_material_fast_reversed()
				running[surface] = material
			elif material == ConveyorKit.drum_material():
				material = ConveyorKit.drum_material_fast() if receiver.port_is_output(side) else ConveyorKit.drum_material_fast_reversed()
				running[surface] = material
			branch.set_surface_override_material(surface, material)
		branch.set_meta("receiver_running", running)
		body.add_child(branch)
		for hand in [-1, 1]:
			var rail := MeshInstance3D.new()
			rail.name = "Rail%d_%d" % [side, hand]
			rail.mesh = ConveyorKit.rail_mesh(hand)
			rail.transform = branch.transform
			body.add_child(rail)
		var nose := MeshInstance3D.new()
		nose.name = "DriveDrum%d" % side
		nose.mesh = ConveyorKit.nose_mesh(receiver.port_is_output(side))
		nose.transform = Transform3D(Basis(across, Vector3.UP, direction), end)
		var drum_running := {}
		for surface in nose.mesh.get_surface_count():
			var material := nose.mesh.surface_get_material(surface)
			if material == ConveyorKit.belt_material():
				material = ConveyorKit.belt_material_fast() if receiver.port_is_output(side) else ConveyorKit.belt_material_fast_reversed()
				drum_running[surface] = material
			elif material == ConveyorKit.drum_material():
				material = ConveyorKit.drum_material_fast() if receiver.port_is_output(side) else ConveyorKit.drum_material_fast_reversed()
				drum_running[surface] = material
			nose.set_surface_override_material(surface, material)
		nose.set_meta("receiver_running", drum_running)
		body.add_child(nose)
		var arrow := MeshInstance3D.new()
		arrow.name = "IntakeArrow%d" % side
		arrow.mesh = ConveyorKit.flow_arrow_mesh()
		arrow.material_override = ConveyorKit.flow_material()
		var travel := direction if receiver.port_is_output(side) else -direction
		var arrow_basis := Basis(Vector3(travel.z, 0.0, -travel.x), Vector3.UP, travel)
		var inner := core_radius(count, 0.421) * cos(PI / count)
		arrow.transform = Transform3D(arrow_basis.scaled_local(Vector3.ONE * 0.42), direction * inner * 0.66 + Vector3.UP * 0.006)
		body.add_child(arrow)
		var plate_at := end * 0.85 + across * 0.62 + Vector3.UP * 0.13
		var plate_basis := Basis(across, Vector3.UP, direction)
		_box(hardware, Transform3D(plate_basis, plate_at), Vector3(0.27, 0.025, 0.30))
		var corner_angle := TAU * (float(side) + 0.5) / float(count)
		_cylinder(hardware, Vector3(sin(corner_angle), -0.009, cos(corner_angle)) * Vector3(shared_corner, 1.0, shared_corner), Vector3.UP, 0.014, 0.018, 6)
		var label := Label3D.new()
		label.name = "PortLabel%d" % side
		label.text = "%d\n%s" % [side + 1, "OUT" if receiver.port_is_output(side) else "IN"]
		label.font_size = 40
		label.pixel_size = 0.0029
		label.outline_size = 7
		label.outline_modulate = Color(0.02, 0.025, 0.025)
		label.transform = Transform3D(Basis(across, -direction, Vector3.UP), plate_at + Vector3.UP * 0.015)
		label.modulate = Color(1.0, 0.79, 0.32) if receiver.port_is_output(side) else Color(0.9, 0.95, 0.94)
		body.add_child(label)
	hardware.set_material(steel)
	hardware.generate_tangents()
	var details := MeshInstance3D.new()
	details.name = "PortPlatesAndBolts"
	details.mesh = hardware.commit()
	body.add_child(details)
	if bool(receiver.get("covered")):
		set_covered(receiver, true)
	return [body, infill]

static func set_held(body: MeshInstance3D, held: bool, infill: MeshInstance3D = null) -> void:
	var parts := body.get_children()
	if is_instance_valid(infill):
		parts.append(infill)
	for child in parts:
		if not (child is MeshInstance3D) or not child.has_meta("receiver_running"):
			continue
		var running: Dictionary = child.get_meta("receiver_running")
		for surface in running:
			var material: Material = running[surface]
			if held:
				material = ConveyorKit.belt_material_held() if material in [ConveyorKit.belt_material_fast(), ConveyorKit.belt_material_fast_reversed()] else ConveyorKit.roller_material()
			child.set_surface_override_material(surface, material)

static func _vertex(st: SurfaceTool, point: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	if absf(normal.y) > 0.5:
		st.set_uv(Vector2(point.x, point.z))
	elif absf(normal.x) > 0.5:
		st.set_uv(Vector2(point.z, point.y))
	else:
		st.set_uv(Vector2(point.x, point.y))
	st.add_vertex(point)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, c, b, a, d, c]:
		_vertex(st, point, normal)

static func _face(st: SurfaceTool, points: PackedVector3Array, y: float) -> void:
	for i in points.size():
		for point in [Vector3(0, y, 0), points[(i + 1) % points.size()] + Vector3.UP * y, points[i] + Vector3.UP * y]:
			_vertex(st, point, Vector3.UP)

static func _prism(st: SurfaceTool, points: PackedVector3Array, top: float, bottom: float) -> void:
	_face(st, points, top)
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		_quad(st, a + Vector3.UP * bottom, b + Vector3.UP * bottom, b + Vector3.UP * top, a + Vector3.UP * top)

static func _box(st: SurfaceTool, transform: Transform3D, size: Vector3) -> void:
	var x := size.x * 0.5
	var y := size.y * 0.5
	var z := size.z * 0.5
	var p := []
	for value in [Vector3(-x,-y,-z),Vector3(x,-y,-z),Vector3(x,y,-z),Vector3(-x,y,-z),Vector3(-x,-y,z),Vector3(x,-y,z),Vector3(x,y,z),Vector3(-x,y,z)]:
		p.append(transform * value)
	for face in [[4,5,6,7],[1,0,3,2],[0,4,7,3],[5,1,2,6],[7,6,2,3],[0,1,5,4]]:
		_quad(st,p[face[0]],p[face[1]],p[face[2]],p[face[3]])

static func _cylinder(st: SurfaceTool, center: Vector3, axis: Vector3, radius: float, length: float, sides: int) -> void:
	var across := axis.cross(Vector3.FORWARD).normalized()
	var up := axis.cross(across).normalized()
	for i in sides:
		var a := (across * cos(TAU * i / sides) + up * sin(TAU * i / sides)) * radius
		var b := (across * cos(TAU * (i + 1) / sides) + up * sin(TAU * (i + 1) / sides)) * radius
		_quad(st,center+a-axis*length*0.5,center+b-axis*length*0.5,center+b+axis*length*0.5,center+a+axis*length*0.5)
		for point in [center+axis*length*0.5,center+b+axis*length*0.5,center+a+axis*length*0.5]:
			_vertex(st,point,axis)

static var _cover_section: Mesh
static var _cover_lids: Dictionary = {}
static var _cover_branches: Dictionary = {}

static func _section_shell() -> Mesh:
	if _cover_section != null:
		return _cover_section
	var source: Mesh = EnclosedConveyorKit.new().mesh("Section")
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := SafeEngine.surface_arrays(source, surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(vertices.size()))
		var shell := PackedInt32Array()
		for index in range(0, indices.size(), 3):
			var a: int = indices[index]
			var b: int = indices[index + 1]
			var c: int = indices[index + 2]
			if maxf(vertices[a].y, maxf(vertices[b].y, vertices[c].y)) > 0.1:
				shell.append_array(PackedInt32Array([a, b, c]))
		if shell.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = shell
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	_cover_section = result
	return _cover_section

static func _cover_lid(count: int) -> Mesh:
	if _cover_lids.has(count):
		return _cover_lids[count]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_prism(surface, polygon(count, 0.482), 0.666, 0.638)
	var bolts := polygon(count, 0.44)
	for point in bolts:
		_cylinder(surface, point + Vector3.UP * 0.675, Vector3.UP, 0.017, 0.018, 6)
	surface.set_material(ConveyorKit.frame_material())
	surface.generate_tangents()
	_cover_lids[count] = surface.commit()
	return _cover_lids[count]

static func _branch_shell(router: Node3D) -> Mesh:
	var count: int = router.port_count
	if _cover_branches.has(count):
		return _cover_branches[count]
	var section := _section_shell()
	var result := ArrayMesh.new()
	var inner := core_radius(count, 0.482) * cos(PI / float(count)) - 0.05
	for index in section.get_surface_count():
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side in count:
			var end: Vector3 = router.port_local(side)
			var direction := end.normalized()
			var start := direction * inner
			var transform := Transform3D(Basis(Vector3(direction.z, 0.0, -direction.x), Vector3.UP, direction).scaled_local(Vector3(1.0, 1.0, start.distance_to(end))), (start + end) * 0.5)
			surface.append_from(section, index, transform)
		surface.set_material(section.surface_get_material(index))
		surface.commit(result)
	_cover_branches[count] = result
	return result

static func set_covered(router: Node3D, on: bool) -> void:
	var cover: Node3D = router.get_node_or_null("RouterCover")
	if on and cover == null:
		cover = Node3D.new()
		cover.name = "RouterCover"
		router.add_child(cover)
		var count: int = router.port_count
		var lid := MeshInstance3D.new()
		lid.name = "HubLid"
		lid.mesh = _cover_lid(count)
		cover.add_child(lid)
		var branch_mesh := MeshInstance3D.new()
		branch_mesh.name = "BranchCovers"
		branch_mesh.mesh = _branch_shell(router)
		cover.add_child(branch_mesh)
	if cover != null:
		cover.visible = on
	for label in router.find_children("PortLabel*", "Label3D", true, false):
		if not label.has_meta("uncovered_position"):
			label.set_meta("uncovered_position", label.position)
		var at: Vector3 = label.get_meta("uncovered_position")
		label.position = at + Vector3.UP * 0.56 if on else at
