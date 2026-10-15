extends "res://scripts/ui/catalog_panel.gd"

const RouterCatalog = preload("res://mods/multiplayer/mp_router_catalog.gd")
const HopperIcon = preload("res://mods/multiplayer/mp_hopper_icon.gd")

func _build_icon(id: String) -> TextureRect:
	var icon := super._build_icon(id)
	if id == "mp_hopper":
		icon.texture = HopperIcon.texture()
		icon.visible = icon.texture != null
	if id in RouterCatalog.ids():
		icon.texture = preload("res://mods/multiplayer/mp_receiver_icon.gd").texture(RouterCatalog.count_for(id), RouterCatalog.is_distributor(id))
		icon.visible = icon.texture != null
	return icon
