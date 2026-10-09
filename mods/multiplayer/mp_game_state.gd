extends "res://autoload/game_state.gd"

var mp_personal_tools: Dictionary = {}

func to_dict() -> Dictionary:
	var data := super.to_dict()
	if not mp_personal_tools.is_empty():
		mp_personal_tools.players["host"] = owned_tools.keys()
		data["mp_personal_tools"] = mp_personal_tools.duplicate(true)
	return data

func from_dict(data: Dictionary) -> void:
	super.from_dict(data)
	var saved: Variant = data.get("mp_personal_tools", {})
	mp_personal_tools = {}
	if not (saved is Dictionary) or not (saved.get("players") is Dictionary) or not (saved.get("initial") is Array):
		return
	var inventories := {}
	for key in saved.players:
		if key is String and saved.players[key] is Array:
			inventories[key] = saved.players[key].duplicate()
	mp_personal_tools = {"version": 1, "initial": saved.initial.duplicate(), "players": inventories}

func reset(seed_value: int, total_strands: float) -> void:
	super.reset(seed_value, total_strands)
	mp_personal_tools = {}
