extends Node

const MAX_ROWS := 4096
const MAX_BYTES := 512 * 1024
const MAX_DISTANCE := 12.0
var mp: Node
var world_sync: Node
var _running := false
var _clock := 0.0
var _full_clock := 0.0
var _dirty := true
var _sequence := 0
var _received := 0
var _next_request := 0
var _pending := {}
var _done := {}
var _results := {}
var _last_request := {}
var _claims := {}
var _snapshot := {}
var _epoch := ""

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	_running = true

func _ready_for_state() -> bool:
	return _running and is_instance_valid(mp) and mp.active() and is_instance_valid(world_sync) and not world_sync._frozen and is_instance_valid(world_sync.player) and is_instance_valid(world_sync.builds) and is_instance_valid(world_sync.machines_sync) and is_instance_valid(world_sync.economy) and world_sync.economy.epoch != ""

func changed() -> void:
	_dirty = true

func _key(node: Node3D) -> String:
	return world_sync.machines_sync._key("scanners", node)

func _scanner(key: String) -> Node:
	for node in world_sync.builds.scanners:
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() and not node.placement_preview and _key(node) == key:
			return node
	return null

func _capture() -> Dictionary:
	var data := {}
	for node in world_sync.builds.scanners:
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion() and not node.placement_preview:
			data[_key(node)] = node.banked.duplicate()
	return data

func _process(delta: float) -> void:
	if not _ready_for_state():
		return
	_clock += delta
	_full_clock += delta
	if _clock < 0.2:
		return
	_clock = 0.0
	if mp.is_host:
		publish(0, _dirty or _full_clock >= 2.0)
	else:
		_apply_snapshot()
		if not _pending.is_empty() and _full_clock >= 1.0:
			_send_request()
	if _full_clock >= 2.0:
		_full_clock = 0.0

func publish(peer: int = 0, force: bool = false) -> void:
	if not _ready_for_state() or not mp.is_host:
		return
	var state := _capture()
	if not force and peer == 0 and state == _snapshot:
		return
	if state.size() > MAX_ROWS or var_to_bytes(state).size() > MAX_BYTES:
		return
	_snapshot = state
	_dirty = false
	_sequence += 1
	if peer != 0:
		mp._rx_scanner_state.rpc_id(peer, world_sync.economy.epoch, _sequence, state)
	else:
		for id in mp.players:
			if id != 1 and mp.players[id].get("state") == "world":
				mp._rx_scanner_state.rpc_id(id, world_sync.economy.epoch, _sequence, state)
	_refresh_drawer()

func on_state(epoch: String, sequence: int, state: Dictionary) -> void:
	if not _ready_for_state() or mp.is_host or epoch != world_sync.economy.epoch or sequence <= 0:
		return
	if epoch == _epoch and sequence <= _received:
		return
	if state.size() > MAX_ROWS or var_to_bytes(state).size() > MAX_BYTES:
		return
	for key in state:
		if not (key is String) or key.length() > 256 or not (state[key] is PackedInt32Array) or state[key].size() > MAX_ROWS:
			return
		var seen := {}
		for index in state[key]:
			if index < 0 or index >= GameState.needle_positions.size() or seen.has(index):
				return
			seen[index] = true
	_epoch = epoch
	_received = sequence
	_snapshot = state.duplicate(true)
	_apply_snapshot()

func _apply_snapshot() -> void:
	if _epoch != world_sync.economy.epoch:
		return
	var updated := false
	for key in _snapshot:
		var node := _scanner(key)
		if node == null or node.banked == _snapshot[key]:
			continue
		node.banked = _snapshot[key].duplicate()
		node._refresh_screen()
		node._apply_lamps()
		if node.banked.is_empty():
			node._hush_alarm()
		updated = true
	if updated:
		_refresh_drawer()

func _refresh_drawer() -> void:
	var drawer: Variant = world_sync.player.get("needle_drawer") if is_instance_valid(world_sync.player) else null
	if is_instance_valid(drawer) and drawer.is_open():
		drawer._fill()

func request(node: Node3D, mode: String, index: int) -> void:
	if not _ready_for_state() or mp.is_host or not _pending.is_empty():
		return
	var hand: Variant = world_sync.player.get("hand")
	if mode == "take" and (not is_instance_valid(hand) or hand.is_holding() or not node.banked.has(index)):
		return
	_next_request += 1
	_pending = {"sequence": _next_request, "key": _key(node), "mode": mode, "index": index}
	_send_request()

func _send_request() -> void:
	mp._rx_scanner_request.rpc_id(1, world_sync.economy.epoch, _pending.sequence, _pending.key, _pending.mode, _pending.index)

func on_request(peer: int, epoch: String, sequence: int, key: String, mode: String, index: int) -> void:
	if not _ready_for_state() or not mp.is_host or epoch != world_sync.economy.epoch or sequence <= 0 or key.length() > 256 or not mp.players.has(peer) or mp.players[peer].get("state") != "world":
		return
	var token := "%d:%d" % [peer, sequence]
	if _results.has(token):
		_reply(peer, sequence, _results[token])
		return
	if sequence <= int(_last_request.get(peer, 0)):
		return
	_last_request[peer] = sequence
	var result := {"ok": false, "index": index, "mode": mode, "key": key, "at": Vector3.ZERO}
	var node := _scanner(key)
	var at: Variant = world_sync._last_at.get(peer)
	var near: bool = node != null and at is Vector3 and at.distance_to(node.bin_position()) <= MAX_DISTANCE
	for claim in _claims.values():
		if claim.peer == peer:
			near = false
	if near and mode == "take" and index >= 0 and index < GameState.needle_positions.size() and node.banked.has(index) and world_sync._holder_of(index) == 0:
		if node.take_banked(index):
			world_sync._holder[index] = peer
			world_sync._apply_needle("claim", index, Vector3.ZERO, peer)
			world_sync._needle_out("claim", index, Vector3.ZERO, peer)
			result.ok = true
			result.at = node.bin_position()
			_claims[token] = {"peer": peer, "index": index, "scanner": weakref(node), "at": result.at}
	elif near and mode == "collect" and not node.banked.is_empty() and not node._busy:
		node.dispense()
		result.ok = true
	_results[token] = result
	if _results.size() > 512:
		for old in _results.keys():
			if not _claims.has(old):
				_results.erase(old)
				if _results.size() <= 256:
					break
	publish(0, true)
	_reply(peer, sequence, result)

func _reply(peer: int, sequence: int, result: Dictionary) -> void:
	mp._rx_scanner_result.rpc_id(peer, world_sync.economy.epoch, sequence, result)

func on_result(epoch: String, sequence: int, result: Dictionary) -> void:
	if not _ready_for_state() or mp.is_host or epoch != world_sync.economy.epoch:
		return
	if _done.has(sequence):
		mp._rx_scanner_ack.rpc_id(1, epoch, sequence, _done[sequence])
		return
	if _pending.is_empty() or sequence != _pending.sequence or result.get("key") != _pending.key or result.get("mode") != _pending.mode or result.get("index") != _pending.index:
		return
	var success := false
	if result.get("ok", false) and _pending.mode == "take" and result.get("at") is Vector3 and result.at.is_finite():
		var hand: Variant = world_sync.player.get("hand")
		if is_instance_valid(hand) and not hand.is_holding():
			success = hand.take_needle(_pending.index, result.at)
		if success:
			world_sync._needles[_pending.index] = "held"
			var drawer: Variant = world_sync.player.get("needle_drawer")
			if is_instance_valid(drawer) and drawer.is_open():
				drawer.set_open(false)
	elif result.get("ok", false) and _pending.mode == "collect":
		success = true
	_done[sequence] = success
	if _done.size() > 256:
		_done.erase(_done.keys()[0])
	_pending.clear()
	mp._rx_scanner_ack.rpc_id(1, epoch, sequence, success)

func on_ack(peer: int, epoch: String, sequence: int, success: bool) -> void:
	if not _ready_for_state() or not mp.is_host or epoch != world_sync.economy.epoch:
		return
	var token := "%d:%d" % [peer, sequence]
	if not _claims.has(token):
		return
	if success:
		_claims.erase(token)
	else:
		_return_claim(token)

func _return_claim(token: String) -> void:
	var claim: Dictionary = _claims[token]
	_claims.erase(token)
	if world_sync._holder_of(claim.index) != claim.peer:
		return
	world_sync._holder.erase(claim.index)
	world_sync._apply_needle("gone", claim.index, Vector3.ZERO, 0)
	world_sync._needle_out("gone", claim.index, Vector3.ZERO, 0)
	var node: Variant = claim.scanner.get_ref()
	if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():
		node.rebank(claim.index)
	else:
		world_sync._apply_needle("spawn", claim.index, claim.at, 0)
		world_sync._needle_out("spawn", claim.index, claim.at, 0)
	changed()

func peer_gone(peer: int) -> void:
	for token in _claims.keys():
		if _claims[token].peer == peer:
			_return_claim(token)
	_last_request.erase(peer)
	for token in _results.keys():
		if token.begins_with(str(peer) + ":"):
			_results.erase(token)

func reserved(node: Node) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for claim in _claims.values():
		if claim.scanner.get_ref() == node:
			indices.append(claim.index)
	return indices

func shutdown() -> void:
	if _running and is_instance_valid(mp) and mp.is_host:
		for token in _claims.keys():
			_return_claim(token)
	_running = false
	set_process(false)
	_pending.clear()
	_done.clear()
	_results.clear()
	_claims.clear()
	_snapshot.clear()
