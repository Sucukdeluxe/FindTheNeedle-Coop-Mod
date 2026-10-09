extends Node

const TOOL_IDS := ["spade", "pitchfork", "broom", "sand_shovel", "metal_detector", "yard_vac", "lighter"]
var mp: Node
var player: Node
var shared := {}
var announced := {}
var original: Script
var elapsed := 0.0

func start(session: Node, world: Node) -> void:
	mp = session
	player = world.player
	original = player.get_script()
	_replace(load(mp.base_dir + "/mp_player.gd"))
	player.mp_tools = self

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
	if is_instance_valid(player) and original != null:
		_replace(original)

func _process(delta: float) -> void:
	if mp == null or not mp.active() or multiplayer.multiplayer_peer == null:
		return
	elapsed += delta
	if elapsed < 0.2:
		return
	elapsed = 0.0
	var added: Array = []
	for id in TOOL_IDS:
		if GameState.has_tool(id) and not announced.has(id):
			announced[id] = true
			added.append(id)
	if not added.is_empty():
		if mp.is_host:
			on_request(1, added)
		else:
			mp._rx_tools_request.rpc_id(1, added)
	for id in shared:
		if not GameState.has_tool(id):
			GameState.grant_tool(id)

func on_request(sender: int, ids: Array) -> void:
	if not mp.is_host or not mp.players.has(sender):
		return
	for id in ids:
		if id in TOOL_IDS:
			shared[id] = true
	on_shared(shared.keys())
	mp._rx_tools_shared.rpc(shared.keys())

func on_shared(ids: Array) -> void:
	for id in ids:
		if id not in TOOL_IDS:
			continue
		shared[id] = true
		announced[id] = true
		if not GameState.has_tool(id):
			GameState.grant_tool(id)

func send_all(pid: int) -> void:
	for id in TOOL_IDS:
		if GameState.has_tool(id):
			shared[id] = true
	mp._rx_tools_shared.rpc_id(pid, shared.keys())
