extends "res://scripts/ui/hotkey_bar.gd"

const RouterCatalog = preload("res://mods/multiplayer/mp_router_catalog.gd")
const HopperIcon = preload("res://mods/multiplayer/mp_hopper_icon.gd")

func _icon_for_slot(index: int) -> Texture2D:
	if index >= Player.TOOL_SLOTS.size() and GameState.hotbar_slot(index - Player.TOOL_SLOTS.size()) == "mp_hopper":
		return HopperIcon.texture()
	if index >= Player.TOOL_SLOTS.size():
		var id := GameState.hotbar_slot(index - Player.TOOL_SLOTS.size())
		if id in RouterCatalog.ids():
			return preload("res://mods/multiplayer/mp_receiver_icon.gd").texture(RouterCatalog.count_for(id), RouterCatalog.is_distributor(id))
	return super._icon_for_slot(index)
