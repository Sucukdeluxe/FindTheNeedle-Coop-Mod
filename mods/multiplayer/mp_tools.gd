extends Node

const TOOL_IDS := ["spade", "pitchfork", "broom", "sand_shovel", "metal_detector", "yard_vac", "lighter"]
var mp: Node
var player: Node
var original: Script
var epoch := ""
var _observed := {}
var diagnostic_inventory := {}
var _applying := false
var _pending := {}
var _actions := {}
var _last := {}
var _revisions := {}
var _received := -1
var _retry := 0.0

func start(session: Node, world: Node) -> void:
	mp = session
	player = world.player
	original = player.get_script()
	_replace(load(mp.base_dir + "/mp_player.gd"))
	player.mp_tools = self
	_observed = _local()
	diagnostic_inventory = _observed.duplicate()
	if mp.is_host:
		epoch = str(Time.get_ticks_usec()) + ":" + str(randi())
		_store()
	GameState.tools_changed.connect(_changed)

func _replace(script: Script) -> void:
	var values := {}
	for property in player.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = player.get(property.name)
	player.set_script(script)
	for key in values:
		if key in player:
			player.set(key, values[key])

func shutdown() -> void:
	if GameState.tools_changed.is_connected(_changed):
		GameState.tools_changed.disconnect(_changed)
	if is_instance_valid(player) and original != null:
		_replace(original)

func _local() -> Dictionary:
	var out := {}
	for id in TOOL_IDS:
		if GameState.has_tool(id):
			out[id] = true
	return out

func _store() -> Dictionary:
	if GameState.mp_personal_tools.is_empty():
		GameState.mp_personal_tools = {"version": 1, "initial": _local().keys(), "players": {"host": _local().keys()}}
	return GameState.mp_personal_tools

func inventory_for(pid: int) -> Dictionary:
	var store := _store()
	var key: String = mp.tool_identity(pid)
	var inventories: Dictionary = store.players
	if not inventories.has(key):
		inventories[key] = store.get("initial", []).duplicate()
	var out := {}
	for id in inventories[key]:
		if id in TOOL_IDS:
			out[id] = true
	return out

func _write(pid: int, inventory: Dictionary) -> void:
	_store().players[mp.tool_identity(pid)] = inventory.keys()
	_revisions[pid] = int(_revisions.get(pid, 0)) + 1
	send_all(pid)

func has_tool(pid: int, id: String) -> bool:
	return inventory_for(pid).has(id)

func grant(pid: int, id: String) -> bool:
	var inventory := inventory_for(pid)
	if id not in TOOL_IDS or inventory.has(id) or inventory.size() >= GameState.CARRIED_TOOL_MAX:
		return false
	if Cfg.DEMO and id in GameState.DEMO_WITHHELD_TOOLS:
		return false
	inventory[id] = true
	_write(pid, inventory)
	return true

func take(pid: int, id: String) -> bool:
	var inventory := inventory_for(pid)
	if not inventory.erase(id):
		return false
	_write(pid, inventory)
	return true

func _changed() -> void:
	if _applying or mp == null or not mp.active():
		return
	var current := _local()
	if current == _observed:
		return
	var added: Array = []
	var removed: Array = []
	for id in current:
		if not _observed.has(id):
			added.append(id)
	for id in _observed:
		if not current.has(id):
			removed.append(id)
	_observed = current
	diagnostic_inventory = current.duplicate()
	if mp.is_host:
		_store().players["host"] = current.keys()
		_revisions[1] = int(_revisions.get(1, 0)) + 1
	else:
		mp.tools_sequence += 1
		_pending[mp.tools_sequence] = {"added": added, "removed": removed}
		_send_pending()

func _send_pending() -> void:
	if epoch == "":
		return
	for seq in _pending:
		var change: Dictionary = _pending[seq]
		mp._rx_tools_request.rpc_id(1, epoch, int(seq), change.added, change.removed)

func _process(delta: float) -> void:
	if mp == null or not mp.active() or mp.is_host or _pending.is_empty():
		return
	_retry += delta
	if _retry >= 1.0:
		_retry = 0.0
		_send_pending()

func on_request(sender: int, token: String, seq: int, added: Array, removed: Array) -> void:
	if not mp.is_host or token != epoch or not mp.players.has(sender) or seq <= 0 or added.size() > TOOL_IDS.size() or removed.size() > TOOL_IDS.size():
		return
	if seq <= int(_last.get(sender, 0)):
		send_all(sender)
		return
	var inventory := inventory_for(sender)
	for id in removed:
		if id in TOOL_IDS:
			inventory.erase(id)
	for id in added:
		if id in TOOL_IDS and inventory.size() < GameState.CARRIED_TOOL_MAX and not (Cfg.DEMO and id in GameState.DEMO_WITHHELD_TOOLS):
			inventory[id] = true
	_last[sender] = seq
	_write(sender, inventory)

func send_all(pid: int) -> void:
	if not mp.is_host:
		return
	var inventory := inventory_for(pid)
	var revision := int(_revisions.get(pid, 0))
	var ack := int(_last.get(pid, 0))
	if pid == 1:
		on_inventory(epoch, revision, ack, inventory.keys())
	else:
		mp._rx_tools_inventory.rpc_id(pid, epoch, revision, ack, inventory.keys())

func on_inventory(token: String, revision: int, ack: int, ids: Array) -> void:
	if token == epoch and revision < _received:
		return
	if token != epoch:
		_received = -1
	epoch = token
	_received = revision
	for seq in _pending.keys():
		if int(seq) <= ack:
			_pending.erase(seq)
	var inventory := {}
	for id in ids:
		if id in TOOL_IDS:
			inventory[id] = true
	for change in _pending.values():
		for id in change.removed:
			inventory.erase(id)
		for id in change.added:
			inventory[id] = true
	_apply(inventory)
	if not mp.is_host:
		_send_pending()

func _apply(inventory: Dictionary) -> void:
	diagnostic_inventory = inventory.duplicate()
	_applying = true
	for id in TOOL_IDS:
		if not inventory.has(id):
			GameState.take_tool(id)
	for id in inventory:
		if not GameState.has_tool(id):
			GameState.grant_tool(id)
	if is_instance_valid(player):
		var active: String = player.tool_unlock(player.current_tool)
		if active != "" and not GameState.has_tool(active):
			if active == "lighter" and is_instance_valid(player.lighter):
				player.lighter.let_go()
			player._set_tool(Player.Tool.HAND, true)
	_observed = _local()
	_applying = false

func request_drop(id: String, throwing: bool) -> void:
	_request("tool_drop", {"id": id, "throwing": throwing}, "drop:" + id)

func request_pickup(item: Node) -> void:
	_request("tool_pickup", {"id": String(item.item_id), "item": int(item.get_meta("mp_id", 0))}, "pick:" + str(item.get_meta("mp_id", 0)))

func _request(action: String, args: Dictionary, key: String) -> void:
	if _actions.values().has(key):
		return
	var economy: Node = mp.world_sync.economy
	if not is_instance_valid(economy):
		return
	args["body"] = player.global_transform
	args["camera"] = player.camera.global_transform
	var seq: int = economy.request(action, args)
	if seq > 0:
		_actions[seq] = key

func accept_result(seq: int, _result: Dictionary) -> void:
	_actions.erase(seq)
