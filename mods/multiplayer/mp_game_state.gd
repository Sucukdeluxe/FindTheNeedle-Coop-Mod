extends "res://autoload/game_state.gd"

var mp_personal_tools: Dictionary = {}
var mp_prestige: Dictionary = {}
var mp_income_rate := -1.0
var mp_needle_committed: Dictionary = {}
var mp_hoppers: Dictionary = {}
var mp_vacuum_transfers: Dictionary = {}

func income_per_minute() -> float:
	var mp := get_node_or_null("/root/MPMod")
	if mp_income_rate >= 0.0 and is_instance_valid(mp) and mp.active() and not mp.is_host:
		return mp_income_rate
	return super.income_per_minute()

func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["mp_prestige"] = mp_prestige.duplicate(true)
	data["mp_needle_committed"] = mp_needle_committed.duplicate()
	data["mp_hoppers"] = mp_hoppers.duplicate(true)
	data["mp_vacuum_transfers"] = mp_vacuum_transfers.duplicate(true)
	if not mp_personal_tools.is_empty():
		mp_personal_tools.players["host"] = owned_tools.keys()
		data["mp_personal_tools"] = mp_personal_tools.duplicate(true)
	return data

func from_dict(data: Dictionary) -> void:
	mp_income_rate = -1.0
	super.from_dict(data)
	mp_prestige = preload("res://mods/multiplayer/mp_prestige_state.gd").normalize(data.get("mp_prestige", {}), run_seed)
	mp_needle_committed = {}
	var spent: Variant = data.get("mp_needle_committed", {})
	if spent is Dictionary:
		for key in spent:
			if key is int and key >= 0 and key < needle_positions.size() and spent[key] in ["stored", "used"]:
				mp_needle_committed[key] = spent[key]
	var hoppers: Variant = data.get("mp_hoppers", {})
	mp_hoppers = hoppers.duplicate(true) if hoppers is Dictionary else {}
	var transfers: Variant = data.get("mp_vacuum_transfers", {})
	mp_vacuum_transfers = transfers.duplicate(true) if transfers is Dictionary else {}
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
	mp_income_rate = -1.0
	super.reset(seed_value, total_strands)
	mp_needle_committed.clear()
	mp_prestige.clear()
	mp_hoppers.clear()
	mp_vacuum_transfers.clear()
	mp_personal_tools = {}

func _mp_needle_service() -> Node:
	var session := get_node_or_null("/root/MPMod")
	if not is_instance_valid(session) or not session.active() or not is_instance_valid(session.world_sync):
		return null
	return session.world_sync.get("needles_sync")

func deposit_needle(index: int, at: Vector3) -> void:
	var service := _mp_needle_service()
	if service != null:
		if not service.can_deposit(index):
			return
		mp_needle_committed[index] = "stored"
	super.deposit_needle(index, at)
	preload("res://mods/multiplayer/mp_prestige_state.gd").record(mp_prestige, index, type_of(index), run_seed)

func withdraw_needle(type: int, at: Vector3 = Vector3.ZERO) -> int:
	var service := _mp_needle_service()
	if service != null and not service.mp.is_host:
		return -1
	return super.withdraw_needle(type, at)

func lose_needle(index: int, type: int, paid: float, cause: NeedleLoss) -> void:
	var service := _mp_needle_service()
	if service != null:
		if not service.can_deposit(index):
			return
		mp_needle_committed[index] = "used"
	super.lose_needle(index, type, paid, cause)
