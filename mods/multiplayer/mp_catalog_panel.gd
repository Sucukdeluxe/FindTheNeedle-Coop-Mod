extends "res://scripts/ui/catalog_panel.gd"

const HopperIcon = preload("res://mods/multiplayer/mp_hopper_icon.gd")

func _build_icon(id: String) -> TextureRect:
	var icon := super._build_icon(id)
	if id == "mp_hopper":
		icon.texture = HopperIcon.texture()
		icon.visible = icon.texture != null
	return icon
