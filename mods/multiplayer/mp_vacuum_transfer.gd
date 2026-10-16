extends Node

const VERSION := 1
const MAX_AMOUNT := 50000
const MAX_STREAMS := 128
const MAX_RECEIPTS := 64
var mp: Node
var world_sync: Node
var _host := {}
var _local := {}
var _realm := ""
var _vacuum: Node
var _resolve_wait := 0.0
var _valid := false
var _mode := ""
var _waiting := false
var _refresh_wait := 0.0
var _startup_checkpoint := {}
var _startup_checkpoint_applied := false
var _restore_blocked := false
var _journal: RefCounted
var _journal_loaded := false
var _writing_fill := false
var _observed_fill := -1

func start(session: Node, sync: Node, saved_checkpoint: Dictionary = {}) -> bool:
	mp = session
	world_sync = sync
	_startup_checkpoint = {}
	_restore_blocked = false
	_startup_checkpoint_applied = saved_checkpoint.is_empty()
	if not saved_checkpoint.is_empty():
		if not (saved_checkpoint.get("local") is Dictionary) or not valid_local(saved_checkpoint.local) or not (saved_checkpoint.get("fill") is int):
			_restore_blocked = true
			_valid = false
			set_process(false)
			return false
		_startup_checkpoint = saved_checkpoint.duplicate(true)
		_local = saved_checkpoint.local.duplicate(true)
	if not world_sync.economy.completed.is_connected(apply_result):
		world_sync.economy.completed.connect(apply_result)
	set_process(true)
	session_started()
	if not _startup_checkpoint_applied:
		_restore_blocked = true
		_valid = false
		set_process(false)
	return _startup_checkpoint_applied

func restore_saved_checkpoint(local: Dictionary, fill: int) -> bool:
	if not _usable() or _mode not in ["host", "offline"] or not is_instance_valid(_vacuum) or not valid_local(local):
		return false
	var checked: Dictionary = preload("res://mods/multiplayer/mp_vacuum_checkpoint.gd").snapshot(_host, local, fill, GameState.run_seed)
	if checked.is_empty() or (fill > 0 and not GameState.has_tool("yard_vac")):
		return false
	_local = local.duplicate(true)
	_save_local()
	_write_fill(_vacuum, fill)
	var pending := _pending()
	_lock(_vacuum, not pending.is_empty())
	if not pending.is_empty():
		if not bool(pending.sent):
			_abort_unsent()
		elif pending.has("receipt"):
			_finish(pending.receipt)
		else:
			_resolve_wait = 3.0
	return true

func _role() -> String:
	if not is_instance_valid(mp):
		return ""
	if not mp.active():
		return "offline"
	return "host" if mp.is_host else "guest"

func _load_local() -> bool:
	if _mode == "guest" and not _journal_loaded:
		_journal = preload("res://mods/multiplayer/mp_vacuum_journal.gd").new()
		var saved_state: Dictionary = _journal.read(str(mp.tool_profile))
		_journal_loaded = true
		if _journal.error != "":
			return _journal_failure()
		if not saved_state.is_empty():
			if not valid_local(saved_state.local):
				return _journal_failure()
			if _local.is_empty() and mp.vacuum_transfer_local.is_empty():
				_local = saved_state.local.duplicate(true)
	if not _local.is_empty():
		return valid_local(_local)
	var saved: Variant = mp.get("vacuum_transfer_local")
	if saved is Dictionary and valid_local(saved):
		_local = saved.duplicate(true)
	elif saved == null or saved == {}:
		var profile := str(mp.get("tool_profile"))
		if profile.length() != 32 or not profile.is_valid_hex_number():
			profile = Crypto.new().generate_random_bytes(16).hex_encode()
		_local = {"version": VERSION, "stream": profile, "next_id": 1, "escrows": {}}
		_save_local()
	else:
		push_warning("[MP] Local vacuum escrow is invalid; saved data preserved")
		return false
	return true

func session_started() -> void:
	if _restore_blocked:
		return
	var mode := _role()
	if mode == "":
		if _mode != "":
			session_ended()
		_load_local()
		return
	if _mode != "" and _mode != mode:
		session_ended()
	_mode = mode
	_valid = false
	_waiting = false
	_refresh_wait = 0.0
	if not _load_local():
		return
	var saved: Variant = GameState.get("mp_vacuum_transfers")
	if saved == null or saved == {}:
		if mode == "guest":
			_waiting = true
			return
		saved = {"version": VERSION, "realm": Crypto.new().generate_random_bytes(16).hex_encode(), "streams": {}}
	if not valid_host(saved):
		push_warning("[MP] Vacuum transfer history is invalid; saved data preserved")
		return
	var previous := _realm
	_host = saved.duplicate(true)
	_realm = str(_host.realm)
	_valid = true
	for key in _host.streams:
		if str(key).ends_with(":" + str(_local.stream)):
			_local.next_id = maxi(int(_local.next_id), int(_host.streams[key].high) + 1)
	_save_local()
	_save_host()
	if previous != _realm:
		if is_instance_valid(_vacuum):
			_lock(_vacuum, false)
		_vacuum = null
	if is_instance_valid(world_sync.player):
		if not _startup_checkpoint.is_empty():
			_vacuum = world_sync.player.get("yard_vac")
			if str(_startup_checkpoint.get("realm", "")) == _realm and int(_startup_checkpoint.get("seed", -1)) == GameState.run_seed and restore_saved_checkpoint(_startup_checkpoint.local, int(_startup_checkpoint.fill)):
				_startup_checkpoint.clear()
				_startup_checkpoint_applied = true
			else:
				if is_instance_valid(_vacuum):
					_lock(_vacuum, true)
				_valid = false
		else:
			bind_vacuum(world_sync.player.get("yard_vac"))

func session_ended() -> void:
	if _restore_blocked:
		return
	_abort_unsent()
	var pending := _pending()
	if _valid and _mode in ["host", "offline"] and not pending.is_empty():
		var payload: Dictionary = pending.payload
		var key := "host:" + str(payload.stream)
		var stream: Dictionary = _host.get("streams", {}).get(key, {"high": 0, "receipts": {}})
		var receipt: Dictionary = stream.receipts.get(int(payload.counter), {})
		if receipt.is_empty() and int(payload.counter) > int(stream.high):
			receipt = payload.duplicate()
			receipt["moved"] = 0
			_host.streams[key] = stream
			_remember(stream, receipt)
		if not receipt.is_empty():
			_finish(receipt)
	_save_local()
	if is_instance_valid(_vacuum):
		_lock(_vacuum, false)
	_vacuum = null
	_realm = ""
	_mode = ""
	_valid = false
	_waiting = false
	_resolve_wait = 0.0

func _usable() -> bool:
	return not _restore_blocked and _valid and _realm != "" and _mode != "" and _role() == _mode

func shutdown() -> void:
	session_ended()
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.economy) and world_sync.economy.completed.is_connected(apply_result):
		world_sync.economy.completed.disconnect(apply_result)
	set_process(false)

func _process(delta: float) -> void:
	_refresh_wait += delta
	if _role() != _mode or (_waiting and _refresh_wait >= 0.5):
		session_started()
	if not _usable():
		return
	if not is_instance_valid(_vacuum) and is_instance_valid(world_sync.player):
		bind_vacuum(world_sync.player.get("yard_vac"))
	var pending := _pending()
	if pending.is_empty():
		return
	if pending.has("receipt"):
		_finish(pending.receipt)
		return
	_resolve_wait += delta
	if _resolve_wait >= 3.0:
		_resolve_wait = 0.0
		resolve()

func prepare(vacuum: Node, requested: int) -> Dictionary:
	if not _usable() or not _pending().is_empty() or not is_instance_valid(vacuum) or requested <= 0:
		return {}
	if not vacuum.has_method("fill") or not (vacuum.get("_fill") is int):
		return {}
	var amount := mini(mini(requested, MAX_AMOUNT), maxi(0, int(vacuum.call("fill"))))
	if amount <= 0 or int(_local.get("next_id", 0)) <= 0 or int(_local.next_id) >= 2147483647 or _local.escrows.size() >= 16:
		return {}
	var counter: int = _local.next_id
	_local.next_id += 1
	var payload := {"realm": _realm, "stream": _local.stream, "counter": counter, "amount": amount}
	var after := int(vacuum.call("fill")) - amount
	_local.escrows[_realm] = {"payload": payload.duplicate(), "after": after, "sequences": [], "sent": false}
	_vacuum = vacuum
	_lock(vacuum, true)
	if not _save_local(after):
		_local.escrows.erase(_realm)
		return {}
	_write_fill(vacuum, after)
	return payload

func submit(vacuum: Node, action: String, args: Dictionary, amount: int) -> int:
	if not _usable() or not is_instance_valid(world_sync) or world_sync._frozen or (mp.active() and world_sync.economy.epoch == ""):
		return 0
	var payload := prepare(vacuum, amount)
	if payload.is_empty():
		return 0
	var request := args.duplicate(true)
	request["vacuum_escrow"] = payload
	var reserved := _pending()
	reserved.sent = true
	if not _save_local():
		_lock(vacuum, true)
		return 0
	var seq: int = world_sync.economy.request(action, request)
	if seq == 0:
		reserved.sent = false
		_abort_unsent()
		return 0
	var pending := _pending()
	pending.sent = true
	pending.sequences.append(seq)
	_save_local()
	_resolve_wait = 0.0
	return seq

func bind_vacuum(vacuum: Node) -> void:
	if not _usable() or not is_instance_valid(vacuum) or _vacuum == vacuum:
		return
	_vacuum = vacuum
	var pending := _pending()
	if _mode == "guest" and _journal != null:
		var saved_fill: Variant = _journal.state.get("fills", {}).get(_realm)
		if saved_fill is Dictionary and saved_fill.get("seed") == GameState.run_seed and saved_fill.get("fill") is int and saved_fill.fill >= 0 and saved_fill.fill <= 1000000:
			_write_fill(vacuum, int(saved_fill.fill))
	if pending.is_empty():
		_save_local()
		return
	_lock(vacuum, true)
	_write_fill(vacuum, int(pending.after))
	if not bool(pending.sent):
		_abort_unsent()
	elif pending.has("receipt"):
		_finish(pending.receipt)

func locked() -> bool:
	return _usable() and not _pending().is_empty()

func resolve() -> int:
	var pending := _pending()
	if not _usable() or pending.is_empty() or not pending.sent or pending.has("receipt") or (mp.active() and world_sync.economy.epoch == ""):
		return 0
	var seq: int = world_sync.economy.request("vacuum_resolve", {"vacuum_escrow": pending.payload.duplicate()})
	if seq > 0:
		pending.sequences.append(seq)
		while pending.sequences.size() > 64:
			pending.sequences.pop_front()
		_save_local()
	return seq

func execute(peer: int, action: String, args: Dictionary) -> Dictionary:
	if not _usable() or _mode not in ["host", "offline"] or (_mode == "offline" and peer != 1) or not world_sync.economy.executing:
		return _failure(_tr("Übertragung nicht verfügbar", "Transfer unavailable"))
	var payload: Variant = args.get("vacuum_escrow")
	if not valid_payload(payload) or payload.realm != _realm:
		return _failure(_tr("Ungültige Übertragung", "Invalid transfer"))
	var key: String = str(mp.tool_identity(peer)) + ":" + str(payload.stream)
	var streams: Dictionary = _host.streams
	if not streams.has(key):
		if streams.size() >= MAX_STREAMS:
			var rejected: Dictionary = payload.duplicate()
			rejected["moved"] = 0
			return _result(rejected)
		streams[key] = {"high": 0, "receipts": {}}
	var stream: Dictionary = streams[key]
	var counter := int(payload.counter)
	var receipts: Dictionary = stream.receipts
	if action == "vacuum_ack":
		var old: Variant = receipts.get(counter)
		if old is Dictionary and old.amount == payload.amount and old.moved == args.get("moved"):
			receipts.erase(counter)
			_save_host()
		return {"ok": true}
	if receipts.has(counter):
		return _result(receipts[counter])
	if counter <= int(stream.high):
		return _failure(_tr("Übertragung wurde bereits bestätigt", "Transfer already acknowledged"))
	if receipts.size() >= MAX_RECEIPTS:
		return _failure(_tr("Zu viele offene Übertragungen", "Too many unresolved transfers"))
	var receipt: Dictionary = payload.duplicate()
	receipt["moved"] = 0
	if action != "vacuum_resolve":
		if world_sync._frozen or not (GameState.has_tool("yard_vac") if _mode == "offline" else world_sync.tools_sync.has_tool(peer, "yard_vac")) or int(payload.amount) > mini(MAX_AMOUNT, int(Tech.vac_capacity())):
			return _remember(stream, receipt)
		if peer == 1 and not _matches_local(payload):
			return _remember(stream, receipt)
		if action == "vacuum_belt":
			receipt.moved = _deliver_belt(peer, args, int(payload.amount))
		elif action == "hopper_deposit":
			var hoppers: Node = world_sync.get("hoppers_sync")
			if is_instance_valid(hoppers) and hoppers.has_method("accept_reserved"):
				receipt.moved = hoppers.accept_reserved(peer, args, int(payload.amount))
	return _remember(stream, receipt)

func _remember(stream: Dictionary, receipt: Dictionary) -> Dictionary:
	stream.high = maxi(int(stream.high), int(receipt.counter))
	stream.receipts[int(receipt.counter)] = receipt.duplicate()
	var counters: Array = stream.receipts.keys()
	counters.sort()
	while counters.size() > 8:
		stream.receipts.erase(counters.pop_front())
	_save_host()
	return _result(receipt)

func apply_result(seq: int, result: Dictionary) -> void:
	var pending := _pending()
	if pending.is_empty() or not seq in pending.sequences:
		return
	var receipt: Variant = result.get("vacuum_receipt")
	if not valid_receipt(receipt) or receipt.realm != _realm or receipt.stream != pending.payload.stream 			or receipt.counter != pending.payload.counter or receipt.amount != pending.payload.amount:
		_resolve_wait = 3.0
		return
	pending["receipt"] = receipt.duplicate()
	_save_local()
	_finish(receipt)

func _finish(receipt: Dictionary) -> void:
	var pending := _pending()
	if pending.is_empty() or not is_instance_valid(_vacuum):
		return
	var restored := int(pending.after) + int(receipt.amount) - int(receipt.moved)
	var payload: Dictionary = pending.payload.duplicate()
	_local.escrows.erase(_realm)
	if not _save_local(restored):
		_local.escrows[_realm] = pending
		_lock(_vacuum, true)
		return
	_write_fill(_vacuum, restored)
	_lock(_vacuum, false)
	if is_instance_valid(world_sync) and mp.active() and world_sync.economy.epoch != "":
		world_sync.economy.request("vacuum_ack", {"vacuum_escrow": payload, "moved": int(receipt.moved)})

func _abort_unsent() -> void:
	var pending := _pending()
	if pending.is_empty() or pending.sent:
		return
	var restored := int(pending.after) + int(pending.payload.amount)
	_local.escrows.erase(_realm)
	if not _save_local(restored):
		_local.escrows[_realm] = pending
		return
	if is_instance_valid(_vacuum):
		_write_fill(_vacuum, restored)
		_lock(_vacuum, false)


func _matches_local(payload: Dictionary) -> bool:
	var pending := _pending()
	return not pending.is_empty() and pending.payload == payload

func _pending() -> Dictionary:
	return _local.get("escrows", {}).get(_realm, {})

func _lock(vacuum: Node, on: bool) -> void:
	vacuum.set_meta("mp_vacuum_escrow", on)
	if on:
		if vacuum.has_method("set_sucking"):
			vacuum.call("set_sucking", false)
		if vacuum.has_method("set_pouring"):
			vacuum.call("set_pouring", false)

func _write_fill(vacuum: Node, amount: int) -> void:
	_writing_fill = true
	vacuum.set("_fill", amount)
	if vacuum.has_method("_draw_fill"):
		vacuum.call("_draw_fill")
	_writing_fill = false

func try_belt(vacuum: Node) -> bool:
	if not _usable() or not is_instance_valid(world_sync) or not is_instance_valid(world_sync.player) or not is_instance_valid(vacuum):
		return false
	var player: Node = world_sync.player
	if not player.is_mouse_captured() or player.menu_is_up():
		return false
	var camera: Camera3D = player.camera
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 6.0, Cfg.L_BUILD | Cfg.L_WORLD)
	var hit: Dictionary = world_sync.world.get_world_3d().direct_space_state.intersect_ray(query)
	var at: Variant = hit.get("position")
	if not (at is Vector3):
		return false
	var owner: Node = hit.get("collider") as Node
	while is_instance_valid(owner) and not (owner is Conveyor):
		owner = owner.get_parent()
	if not is_instance_valid(owner):
		return false
	var owned_ends: PackedVector3Array = owner.save_ends()
	if owned_ends.size() < 2:
		return false
	var target := _belt_near(at, owned_ends[0], owned_ends[1])
	if target.is_empty():
		return false
	if locked():
		return true
	var portion := 100
	if Tech.has_method("belt_portion"):
		portion = clampi(int(Tech.call("belt_portion")), 100, 1000)
	var ends: PackedVector3Array = target.path.save_ends()
	var args := {"a": ends[0], "b": ends[1], "at": target.at, "body": player.global_transform, "camera": camera.global_transform}
	submit(vacuum, "vacuum_belt", args, portion)
	return true

func _deliver_belt(peer: int, args: Dictionary, amount: int) -> int:
	for key in ["a", "b", "at"]:
		var point: Variant = args.get(key)
		if not (point is Vector3) or not point.is_finite() or point.length() > 10000.0:
			return 0
	if not _near(peer, args, args.at):
		return 0
	var target := _belt_near(args.at, args.a, args.b)
	if target.is_empty():
		return 0
	var portion := 100
	if Tech.has_method("belt_portion"):
		portion = clampi(int(Tech.call("belt_portion")), 100, 1000)
	var count := mini(amount, portion)
	var kind := BeltRun.Kind.WAD if count > 100 else BeltRun.Kind.TUFT
	var seq: int = target.path.push_record(kind, count, -1, {"strands": count}, target.at, -1.0, 0.15)
	return count if seq >= 0 else 0

func _belt_near(point: Vector3, a := Vector3.INF, b := Vector3.INF) -> Dictionary:
	var best := {}
	var distance := 0.7
	for path in BeltPath._live:
		if not is_instance_valid(path) or not (path is Conveyor) or not path.is_inside_tree() or path.is_queued_for_deletion():
			continue
		var ends: PackedVector3Array = path.save_ends()
		if ends.size() < 2 or (a.is_finite() and (ends[0].distance_to(a) > 0.02 or ends[1].distance_to(b) > 0.02)):
			continue
		var line: PackedVector3Array = path.centre_line()
		for i in range(line.size() - 1):
			var delta := line[i + 1] - line[i]
			if delta.length_squared() < 0.0001:
				continue
			var ratio := clampf((point - line[i]).dot(delta) / delta.length_squared(), 0.0, 1.0)
			var at := line[i] + delta * ratio
			var gap := point.distance_to(at)
			if gap < distance:
				distance = gap
				best = {"path": path, "at": at}
	return best

func _near(peer: int, args: Dictionary, at: Vector3) -> bool:
	var body: Variant = args.get("body")
	var camera: Variant = args.get("camera")
	if not (body is Transform3D) or not (camera is Transform3D) or not body.origin.is_finite() or not camera.origin.is_finite():
		return false
	if not camera.basis.is_finite() or absf(camera.basis.determinant()) < 0.01 or camera.origin.distance_to(body.origin) > 5.0 or camera.origin.distance_to(at) > 7.0:
		return false
	var known: Variant = world_sync.player.global_position if peer == 1 else world_sync.avatar_positions().get(peer)
	return known is Vector3 and known.distance_to(body.origin) <= 4.0

func serialize_host() -> Dictionary:
	return _host.duplicate(true)

func serialize_local() -> Dictionary:
	return _local.duplicate(true)

func restore_host(data: Dictionary) -> bool:
	if not valid_host(data):
		return false
	_host = data.duplicate(true)
	_realm = _host.realm
	return true

func restore_local(data: Dictionary) -> bool:
	if not valid_local(data):
		return false
	_local = data.duplicate(true)
	return true

func _save_host() -> void:
	if _valid and is_instance_valid(mp) and _mode in ["host", "offline"]:
		GameState.set("mp_vacuum_transfers", serialize_host())

func _journal_failure() -> bool:
	_restore_blocked = true
	if is_instance_valid(world_sync.player):
		_vacuum = world_sync.player.get("yard_vac")
		if is_instance_valid(_vacuum):
			_lock(_vacuum, true)
	var reason := _tr("Saugersicherung nicht les- oder schreibbar. Daten bleiben erhalten; Sauger gesperrt.", "Vacuum recovery data cannot be read or written. Data preserved; vacuum locked.")
	push_warning("[MP] " + reason)
	if is_instance_valid(world_sync):
		world_sync.toast(reason)
	return false

func capture_fill(vacuum: Node) -> void:
	if _writing_fill or _mode != "guest" or not _usable() or vacuum != _vacuum or not _pending().is_empty():
		return
	if int(vacuum.call("fill")) == _observed_fill:
		return
	if not _save_local():
		_lock(vacuum, true)
		_restore_blocked = true
		push_warning("[MP] Vacuum recovery journal could not be saved; vacuum paused")

func _save_local(fill_override: int = -1) -> bool:
	if not valid_local(_local) or not is_instance_valid(mp):
		return false
	if _mode == "guest" and _journal != null and _realm != "" and (fill_override >= 0 or is_instance_valid(_vacuum)):
		var fill := fill_override if fill_override >= 0 else int(_vacuum.call("fill"))
		if not _journal.write(str(mp.tool_profile), _local, _realm, GameState.run_seed, fill):
			return _journal_failure()
		_observed_fill = fill
	mp.set("vacuum_transfer_local", serialize_local())
	return true


static func valid_payload(value: Variant) -> bool:
	if not (value is Dictionary) or value.size() != 4:
		return false
	for key in ["realm", "stream"]:
		if not (value.get(key) is String) or value[key].length() != 32 or not value[key].is_valid_hex_number():
			return false
	return value.get("counter") is int and value.counter > 0 and value.counter < 2147483647 		and value.get("amount") is int and value.amount > 0 and value.amount <= MAX_AMOUNT

static func valid_receipt(value: Variant) -> bool:
	if not (value is Dictionary) or not (value.get("moved") is int) or value.moved < 0:
		return false
	var payload: Dictionary = value.duplicate()
	payload.erase("moved")
	return valid_payload(payload) and value.moved <= value.amount

static func valid_host(value: Variant) -> bool:
	if not (value is Dictionary) or (not (value.get("version") is int) or value.get("version") != VERSION) or not (value.get("streams") is Dictionary) or value.streams.size() > MAX_STREAMS:
		return false
	if not (value.get("realm") is String) or value.realm.length() != 32 or not value.realm.is_valid_hex_number():
		return false
	for key in value.streams:
		var stream: Variant = value.streams[key]
		if not (key is String) or key.length() > 300 or not (stream is Dictionary) or not (stream.get("high") is int) or stream.high < 0:
			return false
		if not (stream.get("receipts") is Dictionary) or stream.receipts.size() > MAX_RECEIPTS:
			return false
		for counter in stream.receipts:
			if not (counter is int) or counter > stream.high or not valid_receipt(stream.receipts[counter]):
				return false
			if stream.receipts[counter].realm != value.realm or stream.receipts[counter].counter != counter:
				return false
	return true

static func valid_local(value: Variant) -> bool:
	if not (value is Dictionary) or value.get("version") != VERSION or not (value.get("stream") is String):
		return false
	if value.stream.length() != 32 or not value.stream.is_valid_hex_number() or not (value.get("next_id") is int) or value.next_id < 1:
		return false
	if not (value.get("escrows") is Dictionary) or value.escrows.size() > 16:
		return false
	for realm in value.escrows:
		var pending: Variant = value.escrows[realm]
		if not (pending is Dictionary) or not valid_payload(pending.get("payload")) or pending.payload.realm != realm:
			return false
		if pending.payload.stream != value.stream or pending.payload.counter >= value.next_id or not (pending.get("after") is int) or pending.after < 0 or pending.after > 2147483647:
			return false
		if not (pending.get("sequences") is Array) or pending.sequences.size() > 64 or not (pending.get("sent") is bool):
			return false
		for seq in pending.sequences:
			if not (seq is int) or seq <= 0:
				return false
		if pending.has("receipt"):
			if not valid_receipt(pending.receipt):
				return false
			var payload: Dictionary = pending.receipt.duplicate()
			payload.erase("moved")
			if payload != pending.payload:
				return false
	return true

static func _result(receipt: Dictionary) -> Dictionary:
	return {"ok": true, "moved": receipt.moved, "vacuum_receipt": receipt.duplicate()}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _tr(de: String, en: String) -> String:
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase(de, en)
