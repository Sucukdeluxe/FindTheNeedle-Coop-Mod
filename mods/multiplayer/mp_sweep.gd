extends Node

signal finished(token: String, result: Dictionary)

const MAX_STRANDS := 65536
var mp: Node
var world_sync: Node
var executing := false
var _job := {}
var _last_requests := {}
var _receipts := {}
var _command_highwater := {}
var _command_tokens := {}
var _client_scope := ""
var _reminder := 0.0
var _elapsed := 0.0
var _warned := false

static func find_service(node: Node) -> Node:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var session := node.get_tree().root.get_node_or_null("MPMod")
	if not is_instance_valid(session):
		return null
	var sync: Variant = session.get("world_sync")
	return sync.get("sweep_sync") if is_instance_valid(sync) else null

static func native_allowed(node: Node) -> bool:
	var session := node.get_tree().root.get_node_or_null("MPMod") if node.is_inside_tree() else null
	if not is_instance_valid(session) or not session.active():
		return true
	var service := find_service(node)
	return is_instance_valid(service) and service.executing and session.is_host

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync

func session_ended() -> void:
	executing = false
	if not _job.is_empty():
		_job.failed = bool(_job.failed) or not _job.waiting.is_empty()
		_job.waiting.clear()
		_complete(str(_job.token))
	_last_requests.clear()
	_reminder = 0.0
	_elapsed = 0.0
	_warned = false

func shutdown() -> void:
	executing = false
	_job.clear()
	_last_requests.clear()
	_receipts.clear()
	_command_highwater.clear()
	_command_tokens.clear()
	_client_scope = ""

func busy() -> bool:
	return not _job.is_empty()

func request_args() -> Dictionary:
	return {"pile_seed": GameState.run_seed, "epoch": world_sync.economy.epoch, "request": int(mp.economy_sequence) + 1}

func request_token(args: Dictionary) -> String:
	var peer := 1 if not mp.active() or mp.is_host else multiplayer.get_unique_id()
	return str(args.epoch) + ":" + str(args.pile_seed) + ":" + str(peer) + ":" + str(args.request)

func _scope(epoch: String, seed: int) -> bool:
	return is_instance_valid(world_sync) and is_instance_valid(world_sync.economy) and epoch == world_sync.economy.epoch and seed == GameState.run_seed

func _failure() -> Dictionary:
	return {"ok": false, "message": _tr("Aufräumen derzeit nicht möglich. Bitte den laufenden Wechsel oder Vorgang abwarten.", "Cleanup is currently unavailable. Wait for the current transition or operation to finish.")}

func execute(peer: int, args: Dictionary) -> Dictionary:
	if not is_instance_valid(mp) or (mp.active() and not mp.is_host):
		return _failure()
	if not (args.get("pile_seed") is int) or not (args.get("epoch") is String) or not (args.get("request") is int):
		return _failure()
	if not _scope(args.epoch, args.pile_seed) or world_sync._frozen or int(args.request) <= 0:
		return _failure()
	if mp.active() and (not mp.players.has(peer) or (peer != 1 and mp.players[peer].get("state") != "world")):
		return _failure()
	var previous: Dictionary = _last_requests.get(peer, {})
	if not previous.is_empty() and int(args.request) <= int(previous.request):
		return previous.response.duplicate(true) if int(args.request) == int(previous.request) else _failure()
	if busy():
		return _failure()
	var props: Variant = world_sync.world.get("props")
	var live: Variant = world_sync.world.get("live")
	if not is_instance_valid(props) or not is_instance_valid(live):
		return _failure()
	var token: String = args.epoch + ":" + str(args.pile_seed) + ":" + str(peer) + ":" + str(args.request)
	_job = {"token": token, "peer": peer, "request": args.request, "epoch": args.epoch, "seed": args.pile_seed, "waiting": {}, "things": 0, "straws": 0, "failed": false}
	if mp.active():
		for id in mp.players:
			if int(id) != 1 and mp.players[id].get("state") == "world":
				_job.waiting[int(id)] = true
	var response := {"ok": true, "pending": true, "token": token}
	_last_requests[peer] = {"request": args.request, "response": response.duplicate(true)}
	executing = true
	_job.things = props.sweep_floor()
	_job.straws = live.sweep_floor()
	executing = false
	_publish()
	for id in _job.waiting:
		mp._rx_sweep_command.rpc_id(int(id), args.epoch, args.pile_seed, token)
	_reminder = 0.0
	_elapsed = 0.0
	_warned = false
	if _job.waiting.is_empty():
		_complete.call_deferred(token)
	return response

func on_command(epoch: String, seed: int, token: String) -> void:
	if not is_instance_valid(mp) or not mp.active() or mp.is_host or not _scope(epoch, seed) or token.length() > 160:
		return
	var prefix := epoch + ":" + str(seed) + ":"
	if not token.begins_with(prefix):
		return
	var identity := token.trim_prefix(prefix).split(":")
	if identity.size() != 2 or not identity[0].is_valid_int() or not identity[1].is_valid_int():
		return
	var actor := int(identity[0])
	var request := int(identity[1])
	if request <= 0:
		return
	if _client_scope != prefix:
		_receipts.clear()
		_command_highwater.clear()
		_command_tokens.clear()
		_client_scope = prefix
	if _receipts.has(token):
		var cached: Dictionary = _receipts[token]
		mp._rx_sweep_report.rpc_id(1, epoch, seed, token, cached.rows, cached.ok)
		return
	if not mp.players.has(actor):
		mp._rx_sweep_report.rpc_id(1, epoch, seed, token, [], false)
		return
	if request <= int(_command_highwater.get(actor, 0)):
		mp._rx_sweep_report.rpc_id(1, epoch, seed, token, [], false)
		return
	if _command_tokens.has(actor):
		_receipts.erase(_command_tokens[actor])
	_command_highwater[actor] = request
	_command_tokens[actor] = token
	var rows: Array = []
	var ok: bool = not world_sync._frozen
	var live: Variant = world_sync.world.get("live")
	ok = ok and is_instance_valid(live) and live.has_method("mp_sweep_collect")
	if ok:
		executing = true
		rows = live.mp_sweep_collect()
		executing = false
	_receipts[token] = {"rows": rows, "ok": ok}
	mp._rx_sweep_report.rpc_id(1, epoch, seed, token, rows, ok)

func on_report(peer: int, epoch: String, seed: int, token: String, rows: Array, ok: bool) -> void:
	if not is_instance_valid(mp) or not mp.active() or not mp.is_host or not _scope(epoch, seed) or _job.is_empty():
		return
	if _job.token != token or not _job.waiting.has(peer) or rows.size() > MAX_STRANDS:
		return
	for row in rows:
		if not (row is Array) or row.size() != 2 or not (row[0] is Vector3) or not row[0].is_finite() or not (row[1] is bool):
			return
	if not ok and not rows.is_empty():
		return
	_job.waiting.erase(peer)
	if ok:
		executing = true
		_credit_rows(rows)
		executing = false
		_job.straws += rows.size()
	else:
		_job.failed = true
	_publish()
	if _job.waiting.is_empty():
		_complete(token)

func _credit_rows(rows: Array) -> void:
	var live: Node = world_sync.world.get("live")
	var sample := RigidBody3D.new()
	sample.freeze = true
	sample.collision_layer = 0
	sample.collision_mask = 0
	live.add_child(sample)
	var returned := 0
	for row in rows:
		sample.global_position = row[0]
		if not row[1] or not live._absorb_into_pile(sample):
			returned += 1
	sample.free()
	if returned > 0:
		GameState.return_hay(float(returned))

func _publish() -> void:
	if mp.active() and mp.is_host and not world_sync._frozen:
		world_sync._hay_tick(true)
		world_sync._state_tick()
		world_sync.economy.publish()

func peer_gone(peer: int) -> void:
	var token: String = _command_tokens.get(peer, "")
	if token == "" or bool(_receipts.get(token, {}).get("finished", false)):
		_receipts.erase(token)
		_command_tokens.erase(peer)
		_command_highwater.erase(peer)
	_last_requests.erase(peer)
	if _job.is_empty() or not _job.waiting.has(peer):
		return
	_job.waiting.erase(peer)
	_job.failed = true
	if _job.waiting.is_empty():
		_complete(str(_job.token))

func _complete(token: String) -> void:
	if _job.is_empty() or _job.token != token or not _job.waiting.is_empty():
		return
	var result := {"ok": true, "pending": false, "token": token, "things": int(_job.things), "straws": int(_job.straws), "incomplete": bool(_job.failed)}
	if _last_requests.has(_job.peer):
		_last_requests[_job.peer].response = result.duplicate(true)
	var epoch: String = _job.epoch
	var seed: int = _job.seed
	_job = {}
	if is_instance_valid(mp) and mp.is_inside_tree() and mp.active() and mp.is_host:
		mp._rx_sweep_finished.rpc(epoch, seed, token, result)
	finished.emit(token, result)

func on_finished(epoch: String, seed: int, token: String, result: Dictionary) -> void:
	if not is_instance_valid(mp) or mp.is_host or not _scope(epoch, seed) or token.length() > 160:
		return
	if not (result.get("things") is int) or not (result.get("straws") is int) or not (result.get("incomplete") is bool):
		return
	if int(result.things) < 0 or int(result.straws) < 0:
		return
	if not bool(result.get("pending", false)) and not bool(result.incomplete) and _receipts.has(token):
		_receipts[token] = {"rows": [], "ok": true, "finished": true}
		for actor in _command_tokens.keys():
			if _command_tokens[actor] == token and not mp.players.has(actor):
				peer_gone(int(actor))
	finished.emit(token, result)

func _process(delta: float) -> void:
	if not busy() or not mp.active() or not mp.is_host:
		return
	_elapsed += delta
	if _elapsed >= 30.0 and not _warned:
		_warned = true
		var result := {"ok": true, "pending": true, "token": str(_job.token), "things": int(_job.things), "straws": int(_job.straws), "incomplete": false}
		mp._rx_sweep_finished.rpc(_job.epoch, _job.seed, _job.token, result)
		finished.emit(str(_job.token), result)
	_reminder += delta
	if _reminder < 3.0:
		return
	_reminder = 0.0
	if not _scope(_job.epoch, _job.seed) or world_sync._frozen:
		return
	for id in _job.waiting:
		mp._rx_sweep_command.rpc_id(int(id), _job.epoch, _job.seed, _job.token)

func _tr(de: String, en: String) -> String:
	return de if TranslationServer.get_locale().begins_with("de") else en
