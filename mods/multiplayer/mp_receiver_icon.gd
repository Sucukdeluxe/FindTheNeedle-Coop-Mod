extends RefCounted

static func texture(count: int, distributor: bool = false) -> Texture2D:
	return preload("res://mods/multiplayer/mp_icons.gd").building(("mp_splitter%d" if distributor else "mp_receiver%d") % count)
