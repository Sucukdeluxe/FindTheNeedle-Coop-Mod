extends "res://scripts/ui/hotkey_bar.gd"

const HopperIcon = preload("res://mods/multiplayer/mp_hopper_icon.gd")

func _icon_for_slot(index: int) -> Texture2D:
	if index >= Player.TOOL_SLOTS.size() and GameState.hotbar_slot(index - Player.TOOL_SLOTS.size()) == "mp_hopper":
		return HopperIcon.texture()
	return super._icon_for_slot(index)
