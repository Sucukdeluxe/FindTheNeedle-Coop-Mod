extends "res://scripts/build/yard_wall.gd"

var mp_wall_color := 0

func set_wall_color(index: int) -> void:
	mp_wall_color = clampi(index, 0, 4)
	_apply_color()

func _build_model() -> void:
	super._build_model()
	_apply_color()

func _apply_color() -> void:
	if not is_instance_valid(_panels) or _panels.multimesh == null:
		return
	var mesh := _panels.multimesh.mesh
	if mesh == null:
		return
	var base: Mesh = mesh.get_meta("mp_wall_base") if mesh.has_meta("mp_wall_base") else mesh
	if mp_wall_color == 0:
		_panels.multimesh.mesh = base
		return
	if mesh.has_meta("mp_wall_color") and int(mesh.get_meta("mp_wall_color")) == mp_wall_color:
		return
	var colored := base.duplicate() as ArrayMesh
	if colored == null:
		return
	var tint: Color = preload("res://mods/multiplayer/mp_wall_palette.gd").color(mp_wall_color)
	for surface in colored.get_surface_count():
		var original := base.surface_get_material(surface)
		if not (original is ShaderMaterial):
			continue
		var material := original.duplicate() as ShaderMaterial
		material.set_shader_parameter("tint", tint)
		colored.surface_set_material(surface, material)
	colored.set_meta("mp_wall_base", base)
	colored.set_meta("mp_wall_color", mp_wall_color)
	_panels.multimesh.mesh = colored

func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["mp_wall_color"] = mp_wall_color
	return data
