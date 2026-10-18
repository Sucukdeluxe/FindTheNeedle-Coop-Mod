extends "res://autoload/game_state.gd"

var mp_balance: Dictionary = {}
var mp_personal_tools: Dictionary = {}
var mp_prestige: Dictionary = {}
var mp_income_rate := -1.0
var mp_needle_committed: Dictionary = {}
var mp_hoppers: Dictionary = {}
var mp_sale_stations: Dictionary = {}
var mp_supply_station: Dictionary = {}
var mp_vacuum_transfers: Dictionary = {}
var mp_vacuum_checkpoint: Variant = {}
var _mp_vacuum_read_id := 0

func income_per_minute() -> float:
	var mp := get_node_or_null("/root/MPMod")
	if mp_income_rate >= 0.0 and is_instance_valid(mp) and mp.active() and not mp.is_host:
		return mp_income_rate
	return super.income_per_minute()

func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["mp_balance"] = mp_balance.duplicate(true)
	data["mp_prestige"] = mp_prestige.duplicate(true)
	data["mp_needle_committed"] = mp_needle_committed.duplicate()
	data["mp_hoppers"] = mp_hoppers.duplicate(true)
	data["mp_sale_stations"] = mp_sale_stations.duplicate(true)
	data["mp_supply_station"] = mp_supply_station.duplicate(true)
	data["mp_vacuum_transfers"] = mp_vacuum_transfers.duplicate(true)
	var session := get_node_or_null("/root/MPMod")
	var checkpoint: Variant = session.get("vacuum_checkpoint") if is_instance_valid(session) else null
	if is_instance_valid(checkpoint):
		var current: Dictionary = checkpoint.capture()
		if not current.is_empty():
			data["mp_vacuum_checkpoint"] = current
	if not data.has("mp_vacuum_checkpoint") and mp_vacuum_checkpoint != {} and (not is_instance_valid(session) or not session.active() or session.is_host):
		data["mp_vacuum_checkpoint"] = mp_vacuum_checkpoint.duplicate(true) if mp_vacuum_checkpoint is Dictionary or mp_vacuum_checkpoint is Array else mp_vacuum_checkpoint
	if not mp_personal_tools.is_empty():
		mp_personal_tools.players["host"] = owned_tools.keys()
		data["mp_personal_tools"] = mp_personal_tools.duplicate(true)
	return data

func from_dict(data: Dictionary) -> void:
	var balance: Variant = data.get("mp_balance", {})
	mp_balance = balance.duplicate(true) if balance is Dictionary else {"invalid": true}
	_mp_vacuum_read_id += 1
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
	var stations: Variant = data.get("mp_sale_stations", {})
	mp_sale_stations = stations.duplicate(true) if stations is Dictionary else {"invalid": true}
	var supply: Variant = data.get("mp_supply_station", {})
	mp_supply_station = supply.duplicate(true) if supply is Dictionary else {"invalid": true}
	var transfers: Variant = data.get("mp_vacuum_transfers", {})
	mp_vacuum_transfers = transfers.duplicate(true) if transfers is Dictionary else {}
	var checkpoint: Variant = data.get("mp_vacuum_checkpoint", {})
	mp_vacuum_checkpoint = checkpoint.duplicate(true) if checkpoint is Dictionary or checkpoint is Array else checkpoint
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
	_mp_vacuum_read_id += 1
	mp_income_rate = -1.0
	mp_balance = preload("res://mods/multiplayer/mp_balance.gd").fresh_state()
	super.reset(seed_value, total_strands)
	mp_needle_committed.clear()
	mp_prestige.clear()
	mp_hoppers.clear()
	mp_sale_stations.clear()
	mp_supply_station.clear()
	mp_vacuum_transfers.clear()
	mp_vacuum_checkpoint = {}
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
