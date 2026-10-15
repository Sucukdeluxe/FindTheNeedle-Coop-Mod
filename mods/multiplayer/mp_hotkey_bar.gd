extends "res://scripts/ui/hotkey_bar.gd"

const HopperIcon = preload("res://mods/multiplayer/mp_hopper_icon.gd")

func _icon_for_slot(index: int) -> Texture2D:
	if index >= Player.TOOL_SLOTS.size() and GameState.hotbar_slot(index - Player.TOOL_SLOTS.size()) == "mp_hopper":
		return HopperIcon.texture()
	if index >= Player.TOOL_SLOTS.size():
		var id := GameState.hotbar_slot(index - Player.TOOL_SLOTS.size())
		if id in ["mp_receiver4", "mp_receiver8"]:
			return preload("res://mods/multiplayer/mp_receiver_icon.gd").texture(4 if id == "mp_receiver4" else 8)
	return super._icon_for_slot(index)
