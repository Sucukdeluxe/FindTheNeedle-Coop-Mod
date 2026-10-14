extends "res://scripts/ui/tech_panel.gd"


func _row(id: String) -> PanelContainer:
	var row := super._row(id)
	var parts: Dictionary = _parts.get(id, {})
	var meta: Variant = parts.get("meta")
	if is_instance_valid(meta) and meta is Label and meta.get_parent() == null:
		meta.hide()
		row.add_child(meta)
	return row
