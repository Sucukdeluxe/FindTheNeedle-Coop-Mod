extends RefCounted

static func texture() -> Texture2D:
	return preload("res://mods/multiplayer/mp_icons.gd").building("mp_hopper")
