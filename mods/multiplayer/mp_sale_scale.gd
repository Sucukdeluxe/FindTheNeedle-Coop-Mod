extends "res://mods/multiplayer/mp_selling_stand.gd"

const OFFSET := Vector3(1.66, 0.0, 3.05)
const BASE_BOUNDS := AABB(Vector3(1.05, -0.02, 2.10), Vector3(1.22, 1.75, 1.55))

func _build_model() -> void:
	var packed: PackedScene = load(MODEL)
	if packed == null:
		return
	var source := packed.instantiate()
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	for node in source.find_children("*", "Node3D", true, false):
		if String(node.name).begins_with("Scale_") or String(node.name).begins_with("Col_Scale"):
			var part := node.duplicate() as Node3D
			part.position -= OFFSET
			_model.add_child(part)
		elif node is MeshInstance3D and String(node.name).begins_with("HaySellingStand_Static"):
			var mesh := _base_mesh(node.mesh)
			if mesh.get_surface_count() > 0:
				var part := MeshInstance3D.new()
				part.name = "ScaleBase"
				part.mesh = mesh
				part.position = -OFFSET
				_model.add_child(part)
	source.free()
	_bind_scale()

static func _base_mesh(source: Mesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var indices := PackedInt32Array()
		for i in range(0, source_indices.size(), 3):
			if BASE_BOUNDS.has_point(vertices[source_indices[i]]) and BASE_BOUNDS.has_point(vertices[source_indices[i + 1]]) and BASE_BOUNDS.has_point(vertices[source_indices[i + 2]]):
				indices.append_array(source_indices.slice(i, i + 3))
		if indices.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	return result

func _build_belt() -> void:
	_belt_tail = Vector3(-0.8, 0.66, 0.0)
	_belt_head = Vector3(0.0, 0.66, 0.0)
	_scale_plate = Vector3(0.0, 0.61, 0.0)
	_belt = BeltPath.new()
	_belt.name = "ScaleIntake"
	_belt.stand_belt = true
	_belt.gathers_straw = true
	_belt.lay_deck = false
	add_child(_belt)
	_belt.build_path(PackedVector3Array([to_global(_belt_tail), to_global(_belt_head)]))
	_belt.records_props = true
	_belt.hold_records(_eats_kind)
	_belt_mid = to_global((_belt_tail + _belt_head) * 0.5)

func intake_forward() -> Vector3:
	return global_basis.x.normalized()

func _build_payout_area() -> void:
	_payout_area = Area3D.new()
	_payout_area.name = "ScalePayoutVolume"
	_payout_area.collision_layer = 0
	_payout_area.collision_mask = Cfg.L_STRAND | Cfg.L_PROP
	_payout_area.monitorable = false
	var box := BoxShape3D.new()
	box.size = Vector3(1.15, 1.25, 1.12)
	var shape := CollisionShape3D.new()
	shape.shape = box
	_payout_area.add_child(shape)
	add_child(_payout_area)
	_payout_area.position = Vector3(0.0, 1.15, 0.0)
	_popup_at = to_global(Vector3(0.0, 2.1, 0.0))
	_resolve_coin_spout()
	_build_skirt()

func _resolve_coin_spout() -> void:
	_coins_at = to_global(Vector3(0.0, 1.75, -0.3))
	_coins_face = global_basis.z

func _build_hand_back() -> void:
	pass

func _build_ledger_note() -> void:
	pass

func _build_price_board() -> void:
	pass

func _build_till() -> void:
	pass

func _collect_body(body: Node3D, skirt: bool) -> void:
	if body is ToolProp or body is SandShovel or body is HayContainer:
		return
	super._collect_body(body, skirt)
