extends "res://scripts/ui/catalog_panel.gd"

const HopperIcon = preload("res://mods/multiplayer/mp_hopper_icon.gd")

func _build_icon(id: String) -> TextureRect:
	var icon := super._build_icon(id)
	if id == "mp_hopper":
		icon.texture = HopperIcon.texture()
		icon.visible = icon.texture != null
	if id in ["mp_receiver4", "mp_receiver8"]:
		icon.texture = preload("res://mods/multiplayer/mp_receiver_icon.gd").texture(4 if id == "mp_receiver4" else 8)
		icon.visible = icon.texture != null
	return icon
