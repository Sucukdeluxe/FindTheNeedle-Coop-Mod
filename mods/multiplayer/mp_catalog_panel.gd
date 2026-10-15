extends "res://scripts/ui/catalog_panel.gd"

const RouterCatalog = preload("res://mods/multiplayer/mp_router_catalog.gd")
const WallPalette = preload("res://mods/multiplayer/mp_wall_palette.gd")
const HopperIcon = preload("res://mods/multiplayer/mp_hopper_icon.gd")

func _build_icon(id: String) -> TextureRect:
	var icon := super._build_icon(WallPalette.base_id(id))
	if id == "mp_hopper":
		icon.texture = HopperIcon.texture()
		icon.visible = icon.texture != null
	if id in ["mp_sale_scale", "mp_sale_move"]:
		icon.texture = preload("res://mods/multiplayer/mp_sale_icon.gd").texture()
		icon.visible = icon.texture != null
	if id in RouterCatalog.ids():
		icon.texture = preload("res://mods/multiplayer/mp_receiver_icon.gd").texture(RouterCatalog.count_for(id), RouterCatalog.is_distributor(id))
		icon.visible = icon.texture != null
	if WallPalette.index(id) > 0:
		icon.modulate = WallPalette.color(WallPalette.index(id))
	return icon
