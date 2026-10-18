extends Node

const State = preload("res://mods/multiplayer/mp_prestige_state.gd")
const Inventory = preload("res://mods/multiplayer/mp_prestige_inventory.gd")
const Store = preload("res://mods/multiplayer/mp_prestige_store.gd")
const Pile = preload("res://mods/multiplayer/mp_prestige_pile.gd")
signal changed
signal finished(ok: bool, message: String)
var mp: Node
var world_sync: Node
var _offer := {}
var _token := ""
var _reports := {}
var _expected := []
var _old_paused := false
var _owns_freeze := false
var _old_frozen := false
var _old_transition := false
var _shutdown_requested := false
var _network_at_start := false
var _source_slot := -1
var _deadline := 0
var _committing := false
var _remote_token := ""
var _saved_process := {}
var _cancel_reason := ""
var _remaining_stamp := -10000
var _remaining_cache := 0.0
var _collection_note: Label
var _collection_clock := 0.0

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_collection_note()

func _setup_collection_note() -> void:
	var panel: Node = world_sync.world.get("needle_panel")
	if not is_instance_valid(panel):
		return
	var sub: Label = panel.get("_sub")
	if not is_instance_valid(sub):
		return
	_collection_note = Label.new()
	_collection_note.name = "PrestigeProgress"
	_collection_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_collection_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_collection_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiFont.style(_collection_note, 14, Color(0.13, 0.12, 0.11), 0, false)
	var column := sub.get_parent()
	column.add_child(_collection_note)
	column.move_child(_collection_note, sub.get_index() + 1)
	_refresh_collection_note()

func _refresh_collection_note() -> void:
	if not is_instance_valid(_collection_note):
		return
	_collection_note.visible = int(GameState.mp_prestige.get("cycles", 0)) > 0
	if _collection_note.visible:
		_collection_note.text = State.current_progress(GameState, NeedleTypes.pool(Cfg.DEMO_LAST_LOT), TranslationServer.get_locale())

func _text(de: String, en: String) -> String:
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase(de, en)

func busy() -> bool:
	return _token != "" or _remote_token != "" or _committing

func _ready_for_transition() -> bool:
	if not world_sync.economy.pending.is_empty() or not world_sync.economy._queue.is_empty():
		return false
	if not world_sync.needles_sync._pending.is_empty() or not world_sync.vacuum_transfer._pending().is_empty():
		return false
	if not world_sync.scanner_sync._pending.is_empty() or not world_sync.scanner_sync._claims.is_empty():
		return false
	var sweep: Variant = world_sync.get("sweep_sync")
	return not is_instance_valid(sweep) or not sweep.busy()

func status() -> Dictionary:
	var host: bool = not mp.active() or mp.is_host
	var data := State.normalize(GameState.mp_prestige, GameState.run_seed)
	var types := NeedleTypes.pool(Cfg.DEMO_LAST_LOT)
	var count := State.found_count(data, GameState.discovered, types, GameState.run_seed)
	if Time.get_ticks_msec() - _remaining_stamp >= 1000 and not _committing:
		_remaining_stamp = Time.get_ticks_msec()
		world_sync.field.settle_join()
		_remaining_cache = maxf(0.0, world_sync.field.measure_strands())
	var remaining := _remaining_cache
	var reason := ""
	if _committing:
		reason = _text("Neuer Heuhaufen wird erzeugt. Bitte warten.", "Generating the new hay pile. Please wait.")
	elif busy():
		reason = _text("Kartenwechsel wird vorbereitet.", "Preparing map change.")
	elif not host:
		reason = _text("Nur der Host kann Prestige starten.", "Only the host can start prestige.")
	elif not State.allowed(remaining, count, types.size()):
		reason = _text("Der Heuhaufen muss leer sein und alle sechs Nadelarten müssen in diesem Durchlauf im Nadelschrank abgelegt sein.", "Empty the hay pile and deposit all six needle types in the cabinet during this run first.")
	elif not _ready_for_transition():
		reason = _text("Eine Übertragung läuft noch. Bitte kurz warten.", "A transfer is still pending. Please wait.")
	return {"allowed": reason == "", "reason": reason, "remaining": remaining, "found": count, "total": 6, "busy": busy(), "host": host, "cycles": data.cycles}

func preview(size_id: String) -> Dictionary:
	var out := status()
	out["ok"] = false
	if not out.allowed or not size_id in State.SIZES:
		return out
	world_sync.field.settle_join()
	if not State.allowed(world_sync.field.measure_strands(), out.found, 6):
		out.reason = _text("Im Haufen liegt noch Heu.", "The pile still contains hay.")
		return out
	var inventory := Inventory.new().capture(world_sync)
	var credit := State.credit(inventory.hay, inventory.worth, Tech.hay_price(), GameState.debt, Cfg.CONSIGNMENT_PAYBACK_SHARE)
	if credit.is_empty():
		return out
	_offer = {"token": Crypto.new().generate_random_bytes(16).hex_encode(), "seed": GameState.run_seed, "size": size_id, "expires": Time.get_ticks_msec() + 60000, "payout": inventory.building_value + credit.paid}
	out.merge({"ok": true, "token": _offer.token, "payout": _offer.payout, "building_value": inventory.building_value, "goods_value": credit.paid, "buildings": inventory.buildings, "hay": inventory.hay, "size": size_id}, true)
	return out

func confirm(token: String) -> bool:
	if busy() or _offer.is_empty() or token != _offer.token or Time.get_ticks_msec() > int(_offer.expires) or int(_offer.seed) != GameState.run_seed:
		return false
	if not status().allowed:
		return false
	_shutdown_requested = false
	_network_at_start = mp.active()
	_source_slot = SaveManager.current_slot
	_token = token
	_cancel_reason = ""
	_deadline = Time.get_ticks_msec() + 15000
	_reports.clear()
	_expected.clear()
	if mp.active():
		for peer in mp.players:
			if peer != 1:
				if str(mp.players[peer].get("state", "")) != "world":
					_abort(_text("Ein Spieler lädt noch die Welt.", "A player is still loading the world."))
					return false
				_expected.append(peer)
				mp._rx_prestige_prepare.rpc_id(peer, _token, GameState.run_seed)
	_freeze()
	_reports[1] = local_report()
	changed.emit()
	_finish_prepare.call_deferred()
	return true

func _freeze() -> void:
	if _owns_freeze:
		return
	_owns_freeze = true
	_old_frozen = world_sync._frozen
	_old_transition = mp._prestige_transition
	_old_paused = get_tree().paused
	world_sync._frozen = true
	mp._prestige_transition = true
	world_sync.build_camera.leave()
	for node in [world_sync.world, world_sync.player]:
		_saved_process[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = true

func _thaw() -> void:
	if not _owns_freeze:
		return
	_owns_freeze = false
	for node in _saved_process:
		if is_instance_valid(node):
			node.process_mode = _saved_process[node]
	_saved_process.clear()
	if is_inside_tree():
		get_tree().paused = _old_paused
	if is_instance_valid(world_sync):
		world_sync._frozen = _old_frozen
	if is_instance_valid(mp):
		mp._prestige_transition = _old_transition

func local_report() -> Dictionary:
	if not _ready_for_transition():
		return {"ok": false}
	var vacuum: Node = world_sync.player.yard_vac
	var fill := int(vacuum.fill()) if is_instance_valid(vacuum) else 0
	var raw := 0
	for body in world_sync.world.live._active:
		if is_instance_valid(body) and not bool(body.get_meta(LiveStrandManager.META_LOCAL_VISUAL, false)) and not body.has_meta("mp_ghost"):
			raw += 1
	var props := []
	var sync: Node = world_sync.props_sync
	var mine := multiplayer.get_unique_id() if mp.active() else 1
	for id in sync._by_id:
		if int(sync._owner.get(id, 0)) != mine:
			continue
		var body: Node = sync._by_id[id]
		if not is_instance_valid(body):
			continue
		var part := Inventory.new()
		part.body(body)
		props.append({"id": id, "hay": part.hay, "worth": part.worth, "needles": part.needles.keys()})
	return {"ok": true, "vacuum": fill, "raw": raw, "props": props, "needles": world_sync._local_carried_needles().keys()}

func on_prepare(token: String, seed: int) -> void:
	if not mp.active() or mp.is_host or seed != GameState.run_seed or busy() or token.length() != 32 or not token.is_valid_hex_number():
		return
	world_sync._state_tick()
	_remote_token = token
	_freeze()
	mp._rx_prestige_ready.rpc_id(1, token, seed, local_report())

func on_ready(peer: int, token: String, seed: int, report: Dictionary) -> void:
	if not mp.is_host or token != _token or seed != GameState.run_seed or not _expected.has(peer) or _reports.has(peer):
		return
	if not bool(report.get("ok", false)) or not report.get("vacuum") is int or not report.get("raw") is int or not report.get("props") is Array or not report.get("needles", []) is Array:
		_abort(_text("Ein Spieler hat noch ausstehende Aktionen.", "A player still has pending actions."))
		return
	if var_to_bytes(report).size() > 1048576 or report.vacuum < 0 or report.vacuum > 1000000 or report.raw < 0 or report.raw > 1000000 or report.props.size() > 20000:
		_abort(_text("Ungültiger Spielerbestand.", "Invalid player inventory."))
		return
	for index in report.get("needles", []):
		if not index is int or index < 0 or index >= GameState.needle_type.size():
			_abort(_text("Ungültiger Nadelbestand.", "Invalid needle inventory."))
			return
	_reports[peer] = report.duplicate(true)
	_finish_prepare.call_deferred()

func on_cancel(token: String, seed: int) -> void:
	if token != _remote_token or seed != GameState.run_seed:
		return
	_remote_token = ""
	_thaw()

func _process(_delta: float) -> void:
	_collection_clock += _delta
	if _collection_clock >= 0.25:
		_collection_clock = 0.0
		_refresh_collection_note()
	if _token != "" and not _committing and Time.get_ticks_msec() > _deadline:
		_abort(_text("Zeitüberschreitung beim Spielerabgleich. Nichts wurde verkauft.", "Player synchronization timed out. Nothing was sold."))

func _abort(message: String) -> void:
	if mp.active() and mp.is_host:
		for peer in _expected:
			if mp.players.has(peer):
				mp._rx_prestige_cancel.rpc_id(peer, _token, GameState.run_seed)
	_token = ""
	_reports.clear()
	_expected.clear()
	_committing = false
	_shutdown_requested = false
	_cancel_reason = ""
	_thaw()
	changed.emit()
	finished.emit(false, message)

func _finish_prepare() -> void:
	if _token == "" or _committing:
		return
	for peer in _expected:
		if not _reports.has(peer):
			return
	if not bool(_reports.get(1, {}).get("ok", false)):
		_abort(_text("Eine Aktion läuft noch. Bitte erneut versuchen.", "An action is still pending. Please try again."))
		return
	_committing = true
	world_sync.field.settle_join()
	var data := State.normalize(GameState.mp_prestige, GameState.run_seed)
	var found := State.found_count(data, GameState.discovered, NeedleTypes.pool(Cfg.DEMO_LAST_LOT), GameState.run_seed)
	if not State.allowed(world_sync.field.measure_strands(), found, 6):
		_abort(_text("Die Voraussetzungen haben sich geändert.", "The requirements have changed."))
		return
	var inventory := Inventory.new().capture(world_sync)
	for owner in _reports:
		var report: Dictionary = _reports[owner]
		inventory.hay += float(report.vacuum)
		inventory.worth += float(report.vacuum)
		for index in report.get("needles", []):
			if index is int and index >= 0 and index < GameState.needle_type.size() and not inventory.needles.has(index):
				if world_sync._holder_of(index) != owner:
					_abort(_text("Der Nadelbesitz hat sich geändert.", "Needle ownership has changed."))
					return
				inventory.needles.append(index)
	for peer in _expected:
		inventory.hay += float(_reports[peer].raw)
		inventory.worth += float(_reports[peer].raw)
		for part in _reports[peer].props:
			if not part is Dictionary or not part.get("id") is int or not world_sync.props_sync._by_id.has(part.id) or int(world_sync.props_sync._owner.get(part.id, 0)) != peer:
				_abort(_text("Der Gegenstandsbesitz hat sich geändert.", "Item ownership has changed."))
				return
			var body: Node = world_sync.props_sync._by_id[part.id]
			var old := Inventory.new()
			old.body(body)
			var amount := float(part.get("hay", -1))
			var value := float(part.get("worth", -1))
			if not is_finite(amount) or not is_finite(value) or amount < 0 or value < 0 or amount > 100000000 or value > 1000000000:
				_abort(_text("Ungültige Warenmenge.", "Invalid goods amount."))
				return
			inventory.hay += amount - old.hay
			inventory.worth += value - old.worth
			for index in part.get("needles", []):
				if index is int and index >= 0 and index < GameState.needle_type.size() and not inventory.needles.has(index):
					inventory.needles.append(index)
	var credit := State.credit(inventory.hay, inventory.worth, Tech.hay_price(), GameState.debt, Cfg.CONSIGNMENT_PAYBACK_SHARE)
	if credit.is_empty() or inventory.building_value + credit.paid + 0.005 < float(_offer.payout):
		_abort(_text("Die Verkaufssumme hat sich geändert. Bitte eine neue Vorschau öffnen.", "The sale value has changed. Please open a new preview."))
		return
	var before: Dictionary = world_sync.build_payload(1)
	before.player = world_sync.player.global_transform
	before.state = GameState.to_dict()
	before.meta.name = SaveManager.current_name
	before.meta.locked = SaveManager.current_locked
	for item in world_sync.world.props.items:
		if item is SandShovel and item.carrier != null:
			before.props.append({"id": item.item_id, "state": item.to_state(), "xform": item.global_transform})
	var seed := int(randi())
	while seed == GameState.run_seed:
		seed = int(randi())
	var pile: Dictionary = await Pile.generate(_offer.size, seed)
	if _shutdown_requested or not is_instance_valid(world_sync) or world_sync.world != get_tree().current_scene or SaveManager.current_slot != _source_slot or mp.active() != _network_at_start:
		_abort(_text("Der Kartenwechsel wurde abgebrochen. Nichts wurde verkauft.", "The map change was cancelled. Nothing was sold."))
		return
	if _cancel_reason != "":
		_abort(_cancel_reason)
		return
	if pile.is_empty() or not Pile.safe_spot(pile).is_finite():
		_abort(_text("Der neue Heuhaufen konnte nicht erzeugt werden. Der Spielstand bleibt erhalten.", "The new hay pile could not be generated. The save is unchanged."))
		return
	var after: Dictionary = before.duplicate(true)
	after.heights = pile.heights
	after.dome = pile.heights.duplicate()
	after.dome_seed = seed
	after.extent = pile.extent
	after.meta.pile_size = _offer.size
	after.meta.saved_at = int(Time.get_unix_time_from_system())
	after.buildings = []
	after.belts = {}
	after.props = _retained_props(before.props, pile)
	var state: Dictionary = after.state
	state.run_seed = seed
	state.hay_initial = pile.total
	state.hay_total = pile.total
	state.hay_returned = 0.0
	state.pile_cleared = false
	state.pile_needles_found = 0
	state.needle_positions = pile.needles
	state.needle_type = pile.types
	state.needle_taken = PackedByteArray()
	state.needle_taken.resize(pile.types.size())
	state.needle_out = PackedInt32Array()
	state.needle_loose = PackedInt32Array()
	state.needle_loose_at = PackedVector3Array()
	state.money = float(state.money) + inventory.building_value + credit.paid
	state.debt = credit.debt
	state.hay_sold = float(state.hay_sold) + inventory.hay
	state.money_earned = float(state.money_earned) + credit.gross
	state.money_peak = maxf(float(state.get("money_peak", 0)), state.money)
	state.mp_hoppers = preload("res://mods/multiplayer/mp_hopper_state.gd").empty()
	state.mp_sale_stations = {}
	state.mp_needle_committed = {}
	state.mp_vacuum_transfers = {}
	state.erase("mp_vacuum_checkpoint")
	state.mp_prestige = State.next_state(data, seed, pile.types.size(), _token)
	for index in inventory.needles:
		if index >= 0 and index < GameState.needle_type.size() and not GameState.mp_needle_committed.has(index):
			var type := GameState.type_of(index)
			if type >= 0 and type < state.needle_stock.size():
				state.needle_stock[type] += 1
	for key in ["money", "hay_initial", "hay_total", "hay_dug", "money_earned", "needles_found"]:
		after.meta[key] = state[key]
	after.player = Transform3D(Basis.IDENTITY, Pile.safe_spot(pile))
	var saved := Store.commit(SaveManager, before, after, _token)
	if not saved.ok:
		if bool(saved.get("restored", false)) or bool(saved.get("unchanged", false)):
			_abort(_text("Speichern fehlgeschlagen. Der bisherige Spielstand bleibt erhalten.", "Saving failed. The previous save is preserved."))
		else:
			SaveManager.block_save = true
			_abort(_text("Speicherfehler. Automatisches Speichern wurde gesperrt; Sicherung prüfen: ", "Save error. Autosave was blocked; check the backup: ") + str(saved.get("backup", "prestige-backups")))
		return
	finished.emit(true, _text("Prestige abgeschlossen. Die neue Karte wird geladen.", "Prestige complete. Loading the new map."))
	mp._prestige_host_reload = true
	mp._prestige_transition = true
	for peer in _expected:
		if mp.players.has(peer):
			mp.players[peer]["state"] = "loading"
	SaveManager.begin_load(SaveManager.current_slot)
	get_tree().paused = false
	Loading.show_screen("FIND THE NEEDLE", _text("NEUE KARTE", "NEW MAP"))
	Loading.enter_scene(mp.GAME_SCENE)

func _retained_props(props: Array, pile: Dictionary) -> Array:
	var out := []
	for row in props:
		if not row is Dictionary or ItemDb.price(str(row.get("id", ""))) <= 0:
			continue
		var kept: Dictionary = row.duplicate(true)
		kept.state = kept.get("state", {}).duplicate(true)
		for key in ["stored", "fill", "strands"]:
			if kept.state.has(key):
				kept.state[key] = 0
		kept.state.erase("needle")
		kept.xform = Transform3D(Basis.IDENTITY, Pile.safe_spot(pile, out.size() + 2))
		out.append(kept)
	return out

func shutdown() -> void:
	if is_instance_valid(_collection_note):
		_collection_note.queue_free()
	_collection_note = null
	_shutdown_requested = true
	if _committing:
		_cancel_reason = _text("Sitzung beendet. Der Kartenwechsel wird abgebrochen.", "Session ended. Cancelling the map change.")
		return
	if _token != "":
		_abort(_text("Kartenwechsel abgebrochen.", "Map change cancelled."))
	elif _remote_token != "":
		_remote_token = ""
		_thaw()
	_offer.clear()
	_reports.clear()
	_expected.clear()
	_shutdown_requested = false

func accept_draining(peer: int) -> bool:
	return _token != "" and not _committing and _expected.has(peer) and not _reports.has(peer)

func peer_gone(peer: int) -> void:
	if _expected.has(peer) and _token != "":
		var message := _text("Ein Spieler hat die Sitzung verlassen. Nichts wurde verkauft.", "A player left the session. Nothing was sold.")
		if _committing:
			_cancel_reason = message
		else:
			_abort(message)
