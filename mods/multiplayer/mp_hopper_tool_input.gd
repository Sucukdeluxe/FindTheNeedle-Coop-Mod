extends Node

const Store = preload("res://mods/multiplayer/mp_hopper_state.gd")
const MAX_RAW := 400
const MAX_PROPS := 64
var hoppers: Node
var world_sync: Node
var mp: Node
var _local := {}
var _raw_used := {}
var _raw_next := 0
var _operation_next := 0
var _operation_stream := Crypto.new().generate_random_bytes(12).hex_encode()
var _operations := {}
var _leases := {}
var _token := 0
var _acks := {}
var _ack_wait := 0.0
var _release_wait := false
var _resolve_wait := 0.0

func start(service: Node) -> void:
	hoppers = service
	world_sync = service.world_sync
	mp = service.mp
	world_sync.economy.completed.connect(_completed)

func shutdown() -> void:
	session_ended()
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.economy) and world_sync.economy.completed.is_connected(_completed):
		world_sync.economy.completed.disconnect(_completed)
func _process(delta: float) -> void:
	if not is_instance_valid(world_sync) or not is_instance_valid(world_sync.economy):
		return
	var economy: Node = world_sync.economy
	if not _local.is_empty() and not _local.get("committed", false) and not _local.quarantined:
		if str(_local.epoch) != economy.epoch or not economy.pending.has(int(_local.get("seq", 0))):
			_quarantine()
	if _release_wait and not Input.is_action_pressed("secondary"):
		_unlock()
	_resolve_wait -= delta
	if not _local.is_empty() and _local.quarantined and mp.active() and economy.epoch != "" and not world_sync._frozen and _resolve_wait <= 0.0:
		_resolve_wait = 1.0
		var sequence := int(_local.get("resolve_seq", 0))
		if sequence == 0 or not economy.pending.has(sequence):
			_local.resolve_seq = economy.request("hopper_tool_resolve", {"operation": _local.operation, "epoch": _local.epoch})
	_ack_wait -= delta
	if _ack_wait <= 0.0 and not world_sync._frozen:
		_ack_wait = 1.0
		for operation in _acks.keys():
			var ack: Dictionary = _acks[operation]
			if int(ack.seq) == 0 or not economy.pending.has(int(ack.seq)):
				ack.seq = economy.request("hopper_tool_ack", {"token": int(ack.token), "operation": operation})
	if not is_instance_valid(mp) or not mp.is_host:
		return
	for id in _leases.keys():
		if not mp.players.has(int(_leases[id].peer)):
			_release_lease(id)
func _input(event: InputEvent) -> void:
	if not is_instance_valid(world_sync) or not is_instance_valid(world_sync.player):
		return
	if not _local.is_empty() and not bool(_local.get("quarantined", false)):
		if _release_wait and event.is_action_released("secondary"):
			_unlock()
		if event is InputEventMouseButton or event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("secondary") and request_secondary():
		get_viewport().set_input_as_handled()

func request_secondary() -> bool:
	var player: Node = world_sync.player
	if not hoppers._usable() or world_sync._frozen or player.menu_is_up() or not player.is_mouse_captured() or player.scripted:
		return false
	var camera_mode: Variant = player.get("mp_build_camera")
	if is_instance_valid(camera_mode) and camera_mode.active:
		return false
	for mode in [player.arm_links, player.drone_zone, player.wire_mode]:
		if is_instance_valid(mode) and mode.is_active():
			return false
	var id: int = hoppers.target_id()
	if id == 0:
		return false
	if player.current_tool == Player.Tool.YARD_VAC and not player.carry.is_carrying():
		return hoppers.request_dump(player.yard_vac)
	if not _local.is_empty():
		return true
	var selection := _selection(player)
	if selection.is_empty():
		return false
	var row: Dictionary = hoppers._row(id)
	if row.is_empty() or row.stored >= Store.capacity(row):
		world_sync.toast(_tr("Trichter voll", "Hopper full"))
		return true
	var source: Node = selection.source
	var raw := PackedInt64Array()
	var props: Array = []
	var local_raw := {}
	var local_props := {}
	for body in selection.bodies:
		if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion():
			continue
		if body is HayWad:
			if props.size() >= MAX_PROPS or String(body.item_id) not in ["hay_wad", "hay_tuft"]:
				continue
			var pid: int = int(body.get_meta("mp_id", 0)) if mp.active() else -int(body.get_instance_id())
			if pid == 0 or (mp.active() and not world_sync.props_sync._mine(pid)):
				continue
			props.append([pid, int(body.hay_strands()), int(body.needle_index), int(world_sync.props_sync._epoch.get(pid, 0))])
			local_props[pid] = weakref(body)
		elif raw.size() < MAX_RAW and body.get_parent() == world_sync.world.live and not body.has_meta("needle_index") and not bool(body.get_meta("mp_ghost", false)):
			var sid := 0
			if mp.active():
				sid = world_sync.strands_sync.register_loaded(body)
			else:
				sid = int(body.get_meta("mp_hopper_source", 0))
				if sid <= 0:
					_raw_next += 1
					sid = _raw_next
					body.set_meta("mp_hopper_source", sid)
			if sid <= 0:
				continue
			raw.append(sid)
			local_raw[sid] = weakref(body)
	if raw.is_empty() and props.is_empty():
		world_sync.toast(_tr("Kein loses Heu geladen", "No raw hay loaded"))
		return true
	_operation_next += 1
	var operation := _operation_stream + ":" + str(_operation_next)
	_local = {"operation": operation, "epoch": world_sync.economy.epoch, "identity": _identity(1 if mp.is_host or not mp.active() else multiplayer.get_unique_id()), "authority": mp.is_host or not mp.active(), "quarantined": false, "committed": false, "resolve_seq": 0, "source": weakref(source), "kind": selection.kind, "raw": local_raw, "props": local_props, "modes": [], "frozen": []}
	for node in [source, player.carry] if source is SandShovel else [source]:
		_local.modes.append([weakref(node), node.process_mode])
		node.process_mode = Node.PROCESS_MODE_DISABLED
	for sid in local_raw:
		var reference: WeakRef = local_raw[sid]
		var body: RigidBody3D = reference.get_ref()
		_local.frozen.append([reference, body.freeze, sid])
		body.freeze = true
	for reference in local_props.values():
		var body: RigidBody3D = reference.get_ref()
		_local.frozen.append([reference, body.freeze, 0])
		body.freeze = true
	if mp.active() and not raw.is_empty():
		world_sync.strands_sync._census()
	var seq: int = world_sync.economy.request("hopper_tool_deposit", {"operation": operation, "id": id, "raw": raw, "props": props, "tool": selection.tool, "body": player.global_transform, "camera": player.camera.global_transform})
	if seq == 0:
		_unlock()
	else:
		_local.seq = seq
	return true

func _selection(player: Node) -> Dictionary:
	if player.carry.is_carrying():
		var held: Node = player.carry.held()
		if held is SandShovel:
			return {"source": held, "kind": "blade", "tool": "sand_shovel", "bodies": held._riding.values()}
		if held is HayWad:
			return {"source": player.carry, "kind": "carry", "tool": "hand", "bodies": player.carry._pile.duplicate()}
		return {}
	if player.current_tool == Player.Tool.HAND:
		return {"source": player.hand, "kind": "hand", "tool": "hand", "bodies": player.hand.held_bodies()}
	if player.current_tool == Player.Tool.SHOVEL:
		return {"source": player.shovel, "kind": "blade", "tool": "spade", "bodies": player.shovel._riding.values()}
	if player.current_tool == Player.Tool.PITCHFORK:
		return {"source": player.pitchfork, "kind": "blade", "tool": "pitchfork", "bodies": player.pitchfork._riding.values()}
	return {}

func execute(peer: int, action: String, args: Dictionary) -> Dictionary:
	if not hoppers._usable() or hoppers._mode not in ["host", "offline"] or world_sync._frozen or not world_sync.economy.executing:
		return _failure(_tr("Aktion nicht verfügbar", "Action unavailable"))
	if action == "hopper_tool_ack":
		return _ack(peer, args)
	if action == "hopper_tool_resolve":
		return _resolve(peer, args)
	var operation: Variant = args.get("operation")
	if not _valid_operation(operation):
		return _failure(_tr("Ungültige Übertragung", "Invalid transfer"))
	var key := _identity(peer) + ":" + str(operation)
	if _operations.has(key):
		return _receipt_for(key)
	var id: Variant = args.get("id")
	var raw: Variant = args.get("raw")
	var props: Variant = args.get("props")
	if not (id is int) or not (raw is PackedInt64Array) or raw.size() > MAX_RAW or not (props is Array) or props.size() > MAX_PROPS:
		return _failure(_tr("Ungültige Heuladung", "Invalid hay load"))
	var tool: Variant = args.get("tool")
	if tool not in ["hand", "spade", "pitchfork", "sand_shovel"] or (tool != "hand" and mp.active() and not world_sync.tools_sync.has_tool(peer, tool)):
		return _failure(_tr("Werkzeug nicht verfügbar", "Tool unavailable"))
	var row: Dictionary = hoppers._row(id)
	if row.is_empty() or not hoppers._near(peer, args, row.position, 7.0):
		return _failure(_tr("Trichter außer Reichweite", "Hopper out of reach"))
	var camera: Transform3D = args.camera
	if hoppers._target_from_ray({"origin": camera.origin, "direction": -camera.basis.z.normalized(), "length": 6.0}) != id:
		return _failure(_tr("Trichter nicht im Blick", "Hopper is not under the cursor"))
	var unique := {}
	for sid in raw:
		if sid <= 0 or unique.has(sid) or _raw_was_used(peer, sid):
			return _failure(_tr("Heuladung bereits übertragen", "Hay load already transferred"))
		var straw := _raw_body(peer, sid)
		if not is_instance_valid(straw) or straw.has_meta("needle_index") or straw.global_position.distance_to(args.body.origin) > 6.0:
			return _failure(_tr("Halm nicht verfügbar", "Straw unavailable"))
		unique[sid] = true
	var sync: Node = world_sync.props_sync
	unique.clear()
	for entry in props:
		if not (entry is Array) or entry.size() != 4 or not (entry[0] is int) or not (entry[1] is int) or not (entry[2] is int) or not (entry[3] is int):
			return _failure(_tr("Ungültige Heuladung", "Invalid hay load"))
		var item: Variant = _source_prop(int(entry[0]))
		if unique.has(entry[0]) or _leases.has(entry[0]) or not is_instance_valid(item) or not item is HayWad or String(item.item_id) not in ["hay_wad", "hay_tuft"]:
			return _failure(_tr("Heuladung hat sich geändert", "Hay load has changed"))
		if (mp.active() and (int(sync._owner.get(entry[0], 1)) != peer or int(sync._epoch.get(entry[0], 0)) != entry[3])) or int(item.hay_strands()) != entry[1] or int(item.needle_index) != entry[2] or entry[1] <= 0:
			return _failure(_tr("Heuladung hat sich geändert", "Hay load has changed"))
		if item.global_position.distance_to(args.body.origin) > 6.0 or BeltPath.is_rider(item):
			return _failure(_tr("Heuladung außer Reichweite", "Hay load out of reach"))
		unique[entry[0]] = true
	var room: int = Store.capacity(row) - int(row.stored)
	var accepted := PackedInt64Array()
	var changes: Array = []
	var moved := 0
	_token += 1
	for entry in props:
		if room <= 0:
			break
		var item: Node = _source_prop(int(entry[0]))
		var amount := mini(room, int(entry[1]))
		if amount == entry[1] and entry[2] >= 0 and row.needles.has(entry[2]):
			continue
		var remaining: int = int(entry[1]) - amount
		if remaining == 0:
			if entry[2] >= 0:
				row.needles.append(entry[2])
			_remove_prop(item, peer)
		else:
			if peer != 1:
				sync._owner[entry[0]] = 1
				sync._held[entry[0]] = true
				item.set_meta(PropManager.META_CLAIM, get_instance_id())
				_leases[entry[0]] = {"peer": peer, "identity": _identity(peer), "operation": operation, "token": _token, "remaining": remaining}
			item.set_strands(remaining)
			item.needle_index = entry[2]
			sync._hash.erase(entry[0])
			sync._sent.erase(entry[0])
		changes.append([entry[0], amount, remaining, entry[2], true])
		moved += amount
		room -= amount
	for sid in raw:
		if room <= 0:
			break
		var straw := _raw_body(peer, sid)
		if peer != 1 and mp.active():
			if not world_sync.strands_sync.host_take(straw):
				continue
		elif not _local.is_empty():
			_detach(_local.source.get_ref(), straw)
			straw.remove_meta("mp_hopper_source")
		if not world_sync.world.live.consume(straw):
			continue
		_remember_raw(peer, sid)
		accepted.append(sid)
		room -= 1
		moved += 1
	if moved <= 0:
		return _failure(_tr("Trichter voll", "Hopper full"))
	Store.transfer(row, moved)
	var receipt := {"ok": true, "moved": moved, "raw": accepted, "props": changes, "token": _token, "operation": operation}
	_operations[key] = receipt.duplicate(true)
	hoppers._changed()
	return receipt

func _raw_body(peer: int, id: int) -> RigidBody3D:
	if not mp.active():
		var reference: Variant = _local.get("raw", {}).get(id)
		var body: Variant = reference.get_ref() if reference != null else null
		return body if is_instance_valid(body) and body.is_inside_tree() and world_sync.world.live._active.has(body) else null
	var strands: Node = world_sync.strands_sync
	var body: Variant = strands._mine.get(id) if peer == 1 else strands._ghost.get(id)
	if peer != 1 and int(strands._owner.get(id, 0)) != peer:
		return null
	return body if is_instance_valid(body) and body.is_inside_tree() and world_sync.world.live._active.has(body) else null

func _identity(peer: int) -> String:
	return "host" if peer == 1 or not mp.active() else mp.tool_identity(peer)

static func _valid_operation(operation: Variant) -> bool:
	return operation is String and operation.length() >= 26 and operation.length() <= 64 and operation.split(":").size() == 2 and operation.get_slice(":", 0).length() == 24 and operation.get_slice(":", 0).is_valid_hex_number() and operation.get_slice(":", 1).is_valid_int() and int(operation.get_slice(":", 1)) > 0

func _receipt_for(key: String) -> Dictionary:
	var receipt: Dictionary = _operations[key].duplicate(true)
	for entry in receipt.get("props", []):
		if entry[2] > 0:
			entry[4] = _leases.has(entry[0]) and _leases[entry[0]].operation == receipt.operation
	return receipt

func _resolve(peer: int, args: Dictionary) -> Dictionary:
	var operation: Variant = args.get("operation")
	if not _valid_operation(operation):
		return _failure(_tr("Ungültige Übertragung", "Invalid transfer"))
	var key := _identity(peer) + ":" + str(operation)
	if _operations.has(key):
		return {"ok": true, "hopper_resolution": _receipt_for(key)}
	for queued in world_sync.economy._queue:
		if int(queued.peer) == peer and str(queued.args.get("operation", "")) == str(operation):
			return {"ok": true, "hopper_pending": true}
	_operations[key] = {"ok": false, "operation": operation, "reason": _tr("Übertragung verworfen", "Transfer cancelled")}
	return {"ok": true, "hopper_resolution": _operations[key].duplicate(true)}

func _raw_was_used(peer: int, id: int) -> bool:
	for span in _raw_used.get(peer, []):
		if id >= int(span[0]) and id <= int(span[1]):
			return true
	return false

func _remember_raw(peer: int, id: int) -> void:
	var spans: Array = _raw_used.get(peer, [])
	var low := id
	var high := id
	var merged: Array = []
	for span in spans:
		if int(span[1]) + 1 < low or int(span[0]) - 1 > high:
			merged.append(span)
		else:
			low = mini(low, int(span[0]))
			high = maxi(high, int(span[1]))
	merged.append([low, high])
	_raw_used[peer] = merged

func _source_prop(id: int) -> Node:
	if not mp.active():
		var reference: Variant = _local.get("props", {}).get(id)
		return reference.get_ref() if reference != null else null
	return world_sync.props_sync._by_id.get(id)

func _remove_prop(item: Node, peer: int) -> void:
	if peer == 1:
		world_sync.world.props.remove(item)
		return
	var sync: Node = world_sync.props_sync
	var id := int(item.get_meta("mp_id"))
	var epoch := int(sync._epoch.get(id, 0)) + 1
	var was_busy: bool = sync._busy
	sync._busy = true
	world_sync.world.props.remove(item)
	sync._busy = was_busy
	for other in mp.players:
		if int(other) != 1 and int(other) != peer:
			mp._rx_prop_owner.rpc_id(int(other), id, 1, epoch, false, mp._outgoing_world_seed())
			mp._rx_prop_del.rpc_id(int(other), PackedInt64Array([id]), mp._outgoing_world_seed())

func _ack(peer: int, args: Dictionary) -> Dictionary:
	var token: Variant = args.get("token")
	var operation: Variant = args.get("operation")
	if not (token is int) or token <= 0 or not _valid_operation(operation):
		return _failure(_tr("Ungültige Bestätigung", "Invalid acknowledgement"))
	var identity := _identity(peer)
	var key := identity + ":" + str(operation)
	if not _operations.has(key) or int(_operations[key].get("token", 0)) != token:
		return _failure(_tr("Übertragung nicht gefunden", "Transfer not found"))
	var sync: Node = world_sync.props_sync
	for id in _leases.keys():
		var lease: Dictionary = _leases[id]
		if lease.identity != identity or lease.operation != operation or lease.token != token:
			continue
		var item: Variant = sync._by_id.get(id)
		if is_instance_valid(item):
			item.remove_meta(PropManager.META_CLAIM)
			sync._assign_owner(id, peer, true)
		_leases.erase(id)
	return {"ok": true}
func _completed(seq: int, result: Dictionary) -> void:
	for operation in _acks.keys():
		var ack: Dictionary = _acks[operation]
		if int(ack.seq) == seq:
			if result.get("ok", false):
				_acks.erase(operation)
			else:
				ack.seq = 0
	if _local.is_empty() or _local.get("committed", false):
		return
	if int(_local.get("resolve_seq", 0)) == seq and _local.quarantined:
		_local.resolve_seq = 0
		if not (result.get("hopper_resolution") is Dictionary):
			return
		result = result.hopper_resolution
		if str(result.get("operation", "")) != str(_local.operation):
			return
	elif int(_local.get("seq", 0)) != seq:
		return
	_local.committed = true
	if result.get("ok", false):
		var source: Variant = _local.source.get_ref()
		for sid in result.get("raw", PackedInt64Array()):
			var reference: Variant = _local.raw.get(sid)
			var body: Variant = reference.get_ref() if reference != null else null
			if is_instance_valid(body) and _raw_matches(body, sid):
				_detach(source, body)
				if body.is_inside_tree():
					body.remove_meta("mp_hopper_source")
					world_sync.world.live.consume(body)
		for entry in result.get("props", []):
			var reference: Variant = _local.props.get(entry[0])
			var body: Variant = reference.get_ref() if reference != null else null
			if not is_instance_valid(body):
				continue
			if int(entry[2]) == 0 or (entry.size() > 4 and not entry[4]):
				_detach(source, body)
				if body.is_inside_tree() and not body.is_queued_for_deletion():
					var canonical_only: bool = int(entry[2]) > 0
					var was_busy: bool = world_sync.props_sync._busy
					if canonical_only:
						world_sync.props_sync._busy = true
					world_sync.world.props.remove(body)
					world_sync.props_sync._busy = was_busy
			else:
				body.set_strands(int(entry[2]))
				body.needle_index = int(entry[3])
		_refresh_source(source)
		_acks[str(_local.operation)] = {"token": int(result.get("token", 0)), "seq": 0}
		world_sync.toast(_tr("%s Halme in den Trichter gefüllt", "%s strands transferred to hopper") % hoppers._number(int(result.get("moved", 0))))
	if _local.quarantined:
		_restore_quarantine()
		_unlock()
	elif Input.is_action_pressed("secondary"):
		_release_wait = true
	else:
		_unlock()
func session_ended() -> void:
	if not _local.is_empty() and not _local.get("committed", false):
		if _local.get("authority", false):
			var key: String = str(_local.identity) + ":" + str(_local.operation)
			if not _operations.has(key):
				_operations[key] = {"ok": false, "operation": _local.operation, "reason": _tr("Übertragung verworfen", "Transfer cancelled")}
			_completed(int(_local.get("seq", 0)), _receipt_for(key))
		else:
			_quarantine()
	elif not _local.is_empty():
		_unlock()
	if not _local.is_empty() and _local.get("committed", false):
		_unlock()
	for id in _leases.keys():
		_release_lease(id)
	_acks.clear()

func _release_lease(id: int) -> void:
	var item: Variant = world_sync.props_sync._by_id.get(id)
	if is_instance_valid(item):
		world_sync.props_sync._held.erase(id)
		item.remove_meta(PropManager.META_CLAIM)
		if mp.active() and mp.is_host:
			world_sync.props_sync._assign_owner(id, 1, false)
		else:
			world_sync.props_sync._release(item)
	_leases.erase(id)

func _raw_matches(body: Node, id: int) -> bool:
	return int(body.get_meta("mp_sid", 0)) == id or int(body.get_meta("mp_hopper_source", 0)) == id

func retire_claimed(body: Node) -> void:
	if not is_instance_valid(body) or not is_instance_valid(world_sync.player):
		return
	var player: Node = world_sync.player
	if is_instance_valid(player.hand):
		for entry in player.hand._held.duplicate():
			if entry.body == body:
				player.hand._held.erase(entry)
	var sources: Array = [player.shovel, player.pitchfork]
	if is_instance_valid(player.carry) and player.carry.held() is SandShovel:
		sources.append(player.carry.held())
	for source in sources:
		if not is_instance_valid(source):
			continue
		var id := body.get_instance_id()
		if source._riding.get(id) != body:
			continue
		for property in ["_riding", "_ride_local", "_ride_from", "_let_go", "_landed"]:
			if property in source:
				source.get(property).erase(id)
func _restore_modes() -> void:
	for saved in _local.get("modes", []):
		var node: Variant = saved[0].get_ref()
		if is_instance_valid(node):
			node.process_mode = int(saved[1])
	_local.modes = []

func _quarantine() -> void:
	if _local.is_empty() or _local.get("quarantined", false):
		return
	var source: Variant = _local.source.get_ref()
	for sid in _local.raw:
		var body: Variant = _local.raw[sid].get_ref()
		if not is_instance_valid(body) or not _raw_matches(body, int(sid)):
			continue
		_detach(source, body)
		if body.is_inside_tree() and not body.is_queued_for_deletion():
			world_sync.world.live.set_protected(body, true)
			body.freeze = true
	for reference in _local.props.values():
		var body: Variant = reference.get_ref()
		if not is_instance_valid(body):
			continue
		_detach(source, body)
		if body.is_inside_tree() and not body.is_queued_for_deletion():
			body.release(Vector3.ZERO)
			body.set_meta(PropManager.META_CLAIM, get_instance_id())
			body.freeze = true
	_refresh_source(source)
	_restore_modes()
	_local.quarantined = true
	_release_wait = false
	_resolve_wait = 0.0
func _restore_quarantine() -> void:
	for sid in _local.raw:
		var body: Variant = _local.raw[sid].get_ref()
		if is_instance_valid(body) and body.is_inside_tree() and _raw_matches(body, int(sid)):
			body.freeze = false
			world_sync.world.live.set_protected(body, false)
			LiveStrandManager.release_hold(body)
	for reference in _local.props.values():
		var body: Variant = reference.get_ref()
		if is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion():
			if int(body.get_meta(PropManager.META_CLAIM, 0)) == get_instance_id():
				body.remove_meta(PropManager.META_CLAIM)
			body.release(Vector3.ZERO)
	_local.frozen = []

func _detach(source: Variant, body: Node) -> void:
	if not is_instance_valid(source):
		return
	var id := body.get_instance_id()
	if _local.kind == "hand":
		for entry in source._held.duplicate():
			if entry.body == body:
				source._held.erase(entry)
	elif _local.kind == "blade":
		for property in ["_riding", "_ride_local", "_ride_from", "_let_go", "_landed"]:
			if property in source:
				source.get(property).erase(id)
	elif _local.kind == "carry":
		source._pile.erase(body)
		source._held = source._pile.back() if not source._pile.is_empty() else null
		source._restack()

func _refresh_source(source: Variant) -> void:
	if not is_instance_valid(source):
		return
	if _local.kind == "hand":
		for entry in source._held.duplicate():
			if not is_instance_valid(entry.body) or not entry.body.is_inside_tree():
				source._held.erase(entry)
	elif _local.kind == "carry":
		for body in source._pile.duplicate():
			if not is_instance_valid(body) or not body.is_inside_tree():
				source._pile.erase(body)
		source._held = source._pile.back() if not source._pile.is_empty() else null
		source._prune()
		source.carry_changed.emit(source.held())
	else:
		for id in source._riding.keys():
			var body: Variant = source._riding[id]
			if not is_instance_valid(body) or not body.is_inside_tree():
				for property in ["_riding", "_ride_local", "_ride_from", "_let_go", "_landed"]:
					if property in source:
						source.get(property).erase(id)
		if "_carried" in source:
			var amount := 0
			for body in source._riding.values():
				amount += int(body.hay_strands()) if body is HayWad else 1
			source._carried = amount
			source._prev_carried = amount
func _unlock() -> void:
	_release_wait = false
	for saved in _local.get("frozen", []):
		var body: Variant = saved[0].get_ref()
		if is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion():
			if saved.size() > 2 and int(saved[2]) != 0 and not _raw_matches(body, int(saved[2])):
				continue
			body.freeze = bool(saved[1])
	for saved in _local.get("modes", []):
		var node: Variant = saved[0].get_ref()
		if is_instance_valid(node):
			node.process_mode = int(saved[1])
	_local.clear()

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _tr(de: String, en: String) -> String:
	return de if TranslationServer.get_locale().begins_with("de") else en
