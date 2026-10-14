extends RefCounted

static func generate(size_id: String, seed: int) -> Dictionary:
	if not size_id in ["standard", "big", "huge", "mountain"]:
		return {}
	var previous: String = Cfg.pile_size_id
	Cfg.apply_pile_size(size_id)
	var field = preload("res://mods/multiplayer/mp_prestige_field.gd").new()
	field._nv = Cfg.field_verts()
	field._nc = Cfg.field_cells()
	field._cpe = Cfg.chunks_per_edge()
	field._rng.seed = seed
	field.heights.resize(field._nv * field._nv)
	field._built_h.resize(field.heights.size())
	field._built_h.fill(-999.0)
	field._cell_render_h.resize(field._nc * field._nc)
	field._cell_render_h.fill(-999.0)
	field._slice_start = Time.get_ticks_usec()
	field._relax.active_mark.resize(field.heights.size())
	field._relax.rng.seed = seed
	field._repose_step = tan(Cfg.ANGLE_OF_REPOSE) * Cfg.CELL
	field._dome_prep_step = tan(deg_to_rad(Cfg.PILE_PREP_ANGLE_DEG)) * Cfg.CELL
	field._relax_rules()
	await field._shape_dome(seed)
	await field._prepare_dome()
	var total: float = field.measure_strands()
	var points := PackedVector3Array()
	var types := PackedByteArray()
	var valid: bool = is_finite(total) and total > 0.0 and field.settling_count() == 0
	for type in NeedleTypes.pool(Cfg.DEMO_LAST_LOT):
		var at := Vector3.INF
		for attempt in 800:
			at = field._needle_site(NeedleTypes.site_band(type) if attempt < 400 else HayField.SITE_ANY)
			if at.is_finite():
				break
		if not at.is_finite():
			valid = false
		points.append(at)
		types.append(type)
	var out: Dictionary = {"heights": field.heights.duplicate(), "total": total, "extent": Cfg.FIELD_EXTENT, "needles": points, "types": types} if valid and points.size() == 6 else {}
	field.free()
	Cfg.apply_pile_size(previous)
	return out

static func safe_spot(pile: Dictionary, ordinal: int = 0) -> Vector3:
	var extent: float = pile.extent
	var side := int(round(extent * 2.0 / Cfg.CELL)) + 1
	var heights: PackedFloat32Array = pile.heights
	var slots := PackedVector3Array()
	for edge in 4:
		for step in range(2, maxi(3, int(extent * 2.0) - 2)):
			var offset := -extent + float(step)
			var at := Vector3(extent - 1.5, 0.0, offset)
			if edge == 1:
				at = Vector3(-extent + 1.5, 0.0, offset)
			elif edge == 2:
				at = Vector3(offset, 0.0, extent - 1.5)
			elif edge == 3:
				at = Vector3(offset, 0.0, -extent + 1.5)
			var clear := true
			for x in [-0.5, 0.0, 0.5]:
				for z in [-0.5, 0.0, 0.5]:
					var ix := clampi(int(round((at.x + x + extent) / Cfg.CELL)), 0, side - 1)
					var iz := clampi(int(round((at.z + z + extent) / Cfg.CELL)), 0, side - 1)
					if heights[iz * side + ix] > 0.03:
						clear = false
			if clear:
				slots.append(at + Vector3.UP * 0.8)
	if slots.is_empty():
		return Vector3.INF
	var at := slots[posmod(ordinal, slots.size())]
	at.y += float(ordinal / slots.size()) * 0.8
	return at
