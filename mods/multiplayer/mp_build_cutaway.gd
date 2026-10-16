extends Node

const STAND_CUT_HEIGHT := 2.25
const ROOF_PARTS := ["Sheets", "HatchEnds", "Rafters", "Purlins"]

var active := false
var _world: Node
var _camera: Camera3D
var _roof_layer := 0
var _inside_layer := 0
var _geometry := {}
var _cameras := {}
var _interiors := {}

func begin(world: Node, camera: Camera3D) -> bool:
	finish()
	if not is_instance_valid(world) or not is_instance_valid(camera):
		return false
	_world = world
	_camera = camera
	var used := 0
	var nodes: Array[Node] = [world]
	var scan: Array[Node] = []
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		scan.append(node)
		if node is VisualInstance3D:
			used |= node.layers
		nodes.append_array(node.get_children())
	var free_layers: Array[int] = []
	for index in range(19, -1, -1):
		var bit := 1 << index
		if not used & bit:
			free_layers.append(bit)
		if free_layers.size() == 2:
			break
	if free_layers.size() < 2:
		return false
	_roof_layer = free_layers[0]
	_inside_layer = free_layers[1]
	active = true
	for node in scan:
		_consider(node)
	_track_camera(camera)
	get_tree().node_added.connect(_node_added)
	set_process(true)
	return true

func finish() -> void:
	active = false
	set_process(false)
	if is_inside_tree() and get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
	for node in _interiors.values():
		if is_instance_valid(node):
			node.hide()
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	for node in _geometry:
		if is_instance_valid(node):
			node.layers = _geometry[node]
	for camera in _cameras:
		if is_instance_valid(camera):
			camera.cull_mask = _cameras[camera]
	_interiors.clear()
	_geometry.clear()
	_cameras.clear()
	_world = null
	_camera = null

func _exit_tree() -> void:
	finish()

func _process(_delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(_world) or not is_instance_valid(_camera):
		finish()
		return
	for node in _geometry.keys():
		if is_instance_valid(node):
			node.layers = _roof_layer
		else:
			_geometry.erase(node)
	for original in _interiors.keys():
		var inside: MeshInstance3D = _interiors[original]
		if not is_instance_valid(original) or not is_instance_valid(inside):
			if is_instance_valid(inside):
				inside.queue_free()
			_interiors.erase(original)
		else:
			inside.visible = original.visible
			inside.transform = original.transform
			inside.material_override = original.material_override
			inside.material_overlay = original.material_overlay

func _node_added(node: Node) -> void:
	if active and (node is GeometryInstance3D or node is Camera3D):
		_consider.call_deferred(node)

func _consider(node: Node) -> void:
	if not active or not is_instance_valid(node) or not is_instance_valid(_world) or not _world.is_ancestor_of(node):
		return
	if node is Camera3D:
		_track_camera(node)
		return
	if not node is GeometryInstance3D or _geometry.has(node):
		return
	var parent := node.get_parent()
	if _script_class(parent, "Warehouse") and node is MeshInstance3D:
		var box: AABB = node.transform * node.get_aabb()
		if node.name in ["ShellP", "ShellN", "Ribs", "Purlins", "Verges"] or box.position.y >= 7.5:
			_hide_roof(node)
	elif _script_class(parent, "Roof") and node.name in ROOF_PARTS:
		if not bool(parent.get("placement_preview")) and not bool(parent.get("deck_style")):
			_hide_roof(node)
	elif node is MeshInstance3D and node.name == "HaySellingStand_Static_00":
		var stand := _ancestor(node, "HaySellingStand")
		if stand != null:
			_add_interior(node, stand)

func _track_camera(camera: Camera3D) -> void:
	if _cameras.has(camera):
		return
	_cameras[camera] = camera.cull_mask
	if camera == _camera:
		camera.cull_mask = (camera.cull_mask | _inside_layer) & ~_roof_layer
	else:
		camera.cull_mask = (camera.cull_mask | _roof_layer) & ~_inside_layer

func _hide_roof(node: GeometryInstance3D) -> void:
	_geometry[node] = node.layers
	node.layers = _roof_layer

func _add_interior(original: MeshInstance3D, stand: Node3D) -> void:
	if original.mesh == null:
		return
	var mesh := ArrayMesh.new()
	var local := stand.global_transform.affine_inverse() * original.global_transform
	for surface in original.mesh.get_surface_count():
		if original.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := original.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize(vertices.size())
			for i in vertices.size():
				indices[i] = i
		var keep := PackedInt32Array()
		for i in range(0, indices.size() - 2, 3):
			var below := false
			for j in 3:
				if (local * vertices[indices[i + j]]).y < STAND_CUT_HEIGHT:
					below = true
			if below:
				keep.append(indices[i])
				keep.append(indices[i + 1])
				keep.append(indices[i + 2])
		if keep.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = keep
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, original.get_active_material(surface))
	var inside := MeshInstance3D.new()
	inside.name = "MPBuildStandInterior"
	inside.mesh = mesh
	inside.layers = _inside_layer
	inside.transform = original.transform
	inside.visible = original.visible
	inside.material_override = original.material_override
	inside.material_overlay = original.material_overlay
	inside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	original.get_parent().add_child(inside)
	_interiors[original] = inside
	_hide_roof(original)

static func intersect_ray(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, overhead: bool = false) -> Dictionary:
	if not overhead:
		return space.intersect_ray(query)
	var filtered := PhysicsRayQueryParameters3D.create(query.from, query.to, query.collision_mask, query.exclude)
	filtered.collide_with_areas = query.collide_with_areas
	filtered.collide_with_bodies = query.collide_with_bodies
	filtered.hit_back_faces = query.hit_back_faces
	filtered.hit_from_inside = query.hit_from_inside
	for i in 64:
		var hit := space.intersect_ray(filtered)
		if hit.is_empty() or not roof_collider(hit.get("collider") as Node):
			return hit
		var excluded := filtered.exclude
		excluded.append(hit.rid)
		filtered.exclude = excluded
	return {}

static func roof_collider(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if str(node.get_meta("scenery", "")) == "roof":
		return true
	if _script_class(node, "Roof"):
		return not bool(node.get("placement_preview")) and not bool(node.get("deck_style"))
	return node.name in ["Col_Roof", "Col_RoofSign"] and _ancestor(node, "HaySellingStand") != null

static func _ancestor(node: Node, name: String) -> Node:
	var current := node.get_parent()
	while current != null:
		if _script_class(current, name):
			return current
		current = current.get_parent()
	return null

static func _script_class(node: Node, name: String) -> bool:
	if not is_instance_valid(node):
		return false
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == name:
			return true
		script = script.get_base_script()
	return false
