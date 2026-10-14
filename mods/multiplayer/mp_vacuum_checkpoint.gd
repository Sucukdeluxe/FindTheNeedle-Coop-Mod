extends Node

const VERSION := 1
const MAX_FILL := 1000000
const MAX_AMOUNT := 50000
var mp: Node
var _pending := {}
var _load_id := 0
var _failure := ""
var _diagnostic_sent := false

func start(session: Node) -> void:
	mp = session
	if not SaveManager.loaded.is_connected(_on_loaded):
		SaveManager.loaded.connect(_on_loaded)

func _exit_tree() -> void:
	if SaveManager.loaded.is_connected(_on_loaded):
		SaveManager.loaded.disconnect(_on_loaded)

func _authoritative() -> bool:
	return is_instance_valid(mp) and (not mp.active() or mp.is_host)

func capture() -> Dictionary:
	if not _authoritative():
		return {}
	var sync: Variant = mp.get("world_sync")
	if not is_instance_valid(sync):
		return {}
	var transfer: Variant = sync.get("vacuum_transfer")
	var player: Variant = sync.get("player")
	if not is_instance_valid(transfer) or not is_instance_valid(player) or not bool(transfer.get("_valid")):
		return {}
	var vacuum: Variant = player.get("yard_vac")
	if not is_instance_valid(vacuum) or not vacuum.has_method("fill"):
		return {}
	return snapshot(transfer.serialize_host(), transfer.serialize_local(), int(vacuum.fill()), GameState.run_seed)

func _on_loaded() -> void:
	_load_id += 1
	_pending.clear()
	_failure = ""
	_diagnostic_sent = false
	if not _authoritative() or _network_save_directory(SaveManager.save_dir()):
		return
	var loaded: Variant = GameState.get("mp_vacuum_checkpoint")
	if loaded == null or loaded == {}:
		return
	var checkpoint := normalize(loaded, GameState.mp_vacuum_transfers, GameState.run_seed)
	if checkpoint.is_empty():
		_pending = {"invalid": true, "read_id": GameState.get("_mp_vacuum_read_id"), "load_id": _load_id}
		_reject(_text("Die gespeicherte Saugerladung konnte nicht geprüft werden. Der Spielstand bleibt bis zur Klärung vor Überschreiben geschützt.", "The saved vacuum inventory could not be validated. Saving is blocked to preserve the recovery data."))
		return
	_pending = {"checkpoint": checkpoint, "directory": SaveManager.save_dir(), "slot": SaveManager.current_slot,
		"read_id": GameState.get("_mp_vacuum_read_id"), "load_id": _load_id}

func _network_save_directory(directory: String) -> bool:
	var script: Script = mp.get_script() if is_instance_valid(mp) else null
	var network_directory: Variant = script.get_script_constant_map().get("SESSION_DIR") if is_instance_valid(script) else null
	if not network_directory is String:
		return true
	return directory.rstrip("/\\") == network_directory.rstrip("/\\")

func has_pending() -> bool:
	_forget_obsolete()
	return not _pending.is_empty()

func failure_reason() -> String:
	return _failure

func _forget_obsolete() -> void:
	if not _pending.is_empty() and GameState.get("_mp_vacuum_read_id") != _pending.read_id:
		_pending.clear()
		_failure = ""
		_diagnostic_sent = false

func _reject(reason: String) -> Dictionary:
	_failure = reason
	if not _diagnostic_sent:
		_diagnostic_sent = true
		push_warning("[MP] " + reason)
	return {}

func prepare_restore() -> Dictionary:
	_forget_obsolete()
	if _pending.is_empty():
		return {}
	if bool(_pending.get("invalid", false)):
		return {}
	if not _authoritative() or _network_save_directory(SaveManager.save_dir()):
		return _reject(_text("Die Saugerladung kann nur im zugehörigen lokalen Spielstand wiederhergestellt werden.", "The vacuum inventory can only be restored in its local save."))
	if SaveManager.save_dir() != _pending.directory or SaveManager.current_slot != int(_pending.slot):
		return _reject(_text("Der ausgewählte Spielstand hat sich während der Wiederherstellung der Saugerladung geändert.", "The selected save changed while restoring the vacuum inventory."))
	var checkpoint := normalize(_pending.checkpoint, GameState.mp_vacuum_transfers, GameState.run_seed)
	if checkpoint.is_empty():
		return _reject(_text("Saugerladung und Weltzustand passen nicht zum geladenen Spielstand.", "The vacuum inventory does not match the loaded world state."))
	var current: Variant = mp.get("vacuum_transfer_local")
	var merged: Dictionary = checkpoint.local.duplicate(true) if current == null or current == {} else merge_local(current, checkpoint.local, checkpoint.realm)
	if merged.is_empty():
		return _reject(_text("Eine offene Saugerübertragung eines anderen Spielstands verhindert die Wiederherstellung. Die gespeicherten Daten wurden nicht verändert.", "A pending vacuum transfer from another save prevents restoration. The saved data has not been changed."))
	return {"local": merged, "fill": int(checkpoint.fill), "realm": checkpoint.realm, "seed": int(checkpoint.seed), "load_id": int(_pending.load_id)}

func finish_restore(prepared: Dictionary, restored: bool) -> bool:
	if not restored or _pending.is_empty() or int(prepared.get("load_id", -1)) != int(_pending.load_id):
		return false
	_pending.clear()
	_failure = ""
	return true

static func _text(de: String, en: String) -> String:
	return de if TranslationServer.get_locale().begins_with("de") else en

static func snapshot(host: Dictionary, local: Dictionary, fill: int, seed: int) -> Dictionary:
	if not _valid_local(local):
		return {}
	var realm: Variant = host.get("realm")
	if not _hex(realm):
		return {}
	var scoped := local.duplicate(true)
	scoped.escrows = {}
	if local.escrows.has(realm):
		scoped.escrows[realm] = local.escrows[realm].duplicate(true)
	return normalize({"version": VERSION, "realm": realm, "seed": seed, "fill": fill, "local": scoped}, host, seed)

static func normalize(value: Variant, host: Dictionary, seed: int) -> Dictionary:
	if not value is Dictionary or value.size() != 5 or host.get("version") != 1:
		return {}
	if not value.get("version") is int or value.version != VERSION or not value.get("seed") is int or value.seed != seed:
		return {}
	if not _hex(value.get("realm")) or value.realm != host.get("realm"):
		return {}
	if not value.get("fill") is int or value.fill < 0 or value.fill > MAX_FILL or not _valid_local(value.get("local")):
		return {}
	var local: Dictionary = value.local
	if local.escrows.size() > 1 or not local.escrows.is_empty() and not local.escrows.has(value.realm):
		return {}
	if local.escrows.has(value.realm):
		var escrow: Dictionary = local.escrows[value.realm]
		if value.fill != int(escrow.after):
			return {}
	return value.duplicate(true)

static func merge_local(current: Dictionary, saved: Dictionary, realm: String) -> Dictionary:
	if not _valid_local(current) or not _valid_local(saved) or not _hex(realm):
		return {}
	if saved.escrows.size() > 1 or not saved.escrows.is_empty() and not saved.escrows.has(realm):
		return {}
	var remaining: Dictionary = current.escrows.duplicate(true)
	remaining.erase(realm)
	if current.stream != saved.stream and not remaining.is_empty():
		return {}
	var merged := saved.duplicate(true)
	if current.stream == saved.stream:
		merged.next_id = maxi(int(current.next_id), int(saved.next_id))
		for other in remaining:
			merged.escrows[other] = remaining[other]
	return merged if _valid_local(merged) else {}

static func _hex(value: Variant) -> bool:
	return value is String and value.length() == 32 and value.is_valid_hex_number()

static func _valid_payload(value: Variant) -> bool:
	return value is Dictionary and value.size() == 4 and _hex(value.get("realm")) and _hex(value.get("stream")) \
		and value.get("counter") is int and value.counter > 0 and value.counter < 2147483647 \
		and value.get("amount") is int and value.amount > 0 and value.amount <= MAX_AMOUNT

static func _valid_local(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not _hex(value.get("stream")):
		return false
	if not value.get("next_id") is int or value.next_id < 1 or value.next_id > 2147483647:
		return false
	if not value.get("escrows") is Dictionary or value.escrows.size() > 16:
		return false
	for realm in value.escrows:
		var escrow: Variant = value.escrows[realm]
		if not escrow is Dictionary or not _valid_payload(escrow.get("payload")):
			return false
		if escrow.payload.realm != realm or escrow.payload.stream != value.stream or escrow.payload.counter >= value.next_id:
			return false
		if not escrow.get("after") is int or escrow.after < 0 or escrow.after > MAX_FILL or not escrow.get("sent") is bool:
			return false
		if not escrow.get("sequences") is Array or escrow.sequences.size() > 64:
			return false
		for seq in escrow.sequences:
			if not seq is int or seq <= 0:
				return false
		if escrow.has("receipt"):
			var receipt: Variant = escrow.receipt
			if not receipt is Dictionary or not receipt.get("moved") is int or receipt.moved < 0 or receipt.moved > escrow.payload.amount:
				return false
			var payload: Dictionary = receipt.duplicate()
			payload.erase("moved")
			if payload != escrow.payload:
				return false
	return true
