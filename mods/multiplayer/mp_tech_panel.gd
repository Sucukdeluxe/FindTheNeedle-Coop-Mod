extends "res://scripts/ui/tech_panel.gd"

const ModIcons = preload("res://mods/multiplayer/mp_icons.gd")

func _icon(id: String, side: float) -> TextureRect:
	var icon := super._icon(id, side)
	var texture := ModIcons.upgrade(id)
	if texture != null:
		icon.texture = texture
		icon.visible = true
	return icon


func _row(id: String) -> PanelContainer:
	var row := super._row(id)
	var parts: Dictionary = _parts.get(id, {})
	var texture := ModIcons.upgrade(id)
	if texture != null and is_instance_valid(parts.get("icon")):
		parts.icon.texture = texture
		parts.icon.visible = true
	var meta: Variant = parts.get("meta")
	if is_instance_valid(meta) and meta is Label and meta.get_parent() == null:
		meta.hide()
		row.add_child(meta)
	return row

func _paint_inspector() -> void:
	super._paint_inspector()
	if not is_instance_valid(_ins_icon) or _selected.is_empty():
		return
	var texture := ModIcons.upgrade(_selected)
	if texture != null:
		_ins_icon.texture = texture
		_ins_icon.visible = true
