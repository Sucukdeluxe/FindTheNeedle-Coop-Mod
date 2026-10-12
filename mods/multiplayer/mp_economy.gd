extends Node

signal completed(seq: int, result: Dictionary)
const CACHE_LIMIT := 256
const MAX_PENDING := 32
const BUILD_PREPARE_TIMEOUT_MSEC := 30000
var mp: Node
var world_sync: Node
var epoch := ""
var executing := false
var pending := {}
var _next := 0
var _queue: Array = []
var _queued := {}
var _last := {}
var _results := {}
var _actors := {}
var _preparing := {}
var _originals := {}
var _retry := 0.0

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	if mp.is_host:
		epoch = str(Time.get_ticks_usec()) + ":" + str(randi())
	_hook(sync.player.build, "mp_build_tool.gd")
	_hook(sync.world.shop_menu, "mp_shop.gd")
	GameState.gifts_changed.connect(_gifts_changed)
	GameState.purchased.connect(_purchase_changed)

func _hook(node: Node, file: String) -> void:
	if not is_instance_valid(node):
		return
	_originals[node] = node.get_script()
	_replace(node, load(mp.base_dir + "/" + file))
	node.set("mp_economy", self)

func _replace(node: Node, script: Script) -> void:
	var values := {}
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = node.get(property.name)
	node.set_script(script)
	for key in values:
		if key in node:
			node.set(key, values[key])

func shutdown() -> void:
	if GameState.gifts_changed.is_connected(_gifts_changed):
		GameState.gifts_changed.disconnect(_gifts_changed)
	if GameState.purchased.is_connected(_purchase_changed):
		GameState.purchased.disconnect(_purchase_changed)
	for node in _originals:
		if is_instance_valid(node):
			_replace(node, _originals[node])
	_originals.clear()
	for actor in _actors.values():
		if is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()
	_preparing.clear()
	_queue.clear()
	_queued.clear()
	pending.clear()

func peer_gone(pid: int) -> void:
	_discard_actor(pid)
	_results.erase(pid)
	_last.erase(pid)
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i].peer == pid:
			_queued.erase(str(pid) + ":" + str(_queue[i].seq))
			_queue.remove_at(i)

func request(action: String, args: Dictionary) -> int:
	if epoch == "" or pending.size() >= MAX_PENDING or world_sync._frozen:
		mp.ui.notify(mp.t("economy_wait"))
		return 0
	if not mp.is_host:
		world_sync._state_tick()
	_next = maxi(_next, mp.economy_sequence) + 1
	mp.economy_sequence = _next
	pending[_next] = {"action": action, "args": args.duplicate(true)}
	if mp.is_host:
		on_request(1, epoch, _next, action, args)
	else:
		mp._rx_economy_request.rpc_id(1, epoch, _next, action, args)
	return _next

func on_request(peer: int, token: String, seq: int, action: String, args: Dictionary) -> void:
	if not mp.is_host or token != epoch or seq <= 0 or not mp.players.has(peer):
		return
	if peer != 1 and mp.players[peer].get("state") != "world":
		return
	var cache: Dictionary = _results.get(peer, {})
	if cache.has(seq):
		_reply(peer, seq, cache[seq])
		return
	var key := str(peer) + ":" + str(seq)
	if seq <= int(_last.get(peer, 0)):
		_reply(peer, seq, _failure("economy_expired"))
		return
	if _queued.has(key):
		return
	if _queue.size() >= MAX_PENDING * 8 or var_to_bytes(args).size() > 65536:
		return
	_queued[key] = true
	_queue.append({"peer": peer, "seq": seq, "action": action, "args": args.duplicate(true)})

func _physics_process(_delta: float) -> void:
	if mp == null or not mp.active() or not mp.is_host or _queue.is_empty():
		return
	var entry: Dictionary = _queue[0]
	var peer := int(entry.peer)
	var seq := int(entry.seq)
	var preparation := 1
	if mp.players.has(peer) and seq > int(_last.get(peer, 0)) and not world_sync._frozen \
			and entry.action in ["place", "demolish", "demolish_tile", "reverse"]:
		preparation = _prepare_build_tool(peer, entry.args)
		if preparation == 0:
			return
	_queue.pop_front()
	_queued.erase(str(peer) + ":" + str(seq))
	if not mp.players.has(peer):
		return
	if seq <= int(_last.get(peer, 0)):
		_reply(peer, seq, _failure("economy_expired"))
		return
	var before := float(GameState.money)
	executing = true
	var result := _failure("economy_wait")
	if not world_sync._frozen:
		result = _failure("purchase_declined") if preparation < 0 else _execute(peer, entry.action, entry.args)
	executing = false
	result["money_change"] = float(GameState.money) - before
	result["action"] = entry.action
	result["id"] = str(entry.args.get("id", ""))
	_last[peer] = maxi(int(_last.get(peer, 0)), seq)
	if not _results.has(peer):
		_results[peer] = {}
	_results[peer][seq] = result.duplicate(true)
	while _results[peer].size() > CACHE_LIMIT:
		_results[peer].erase(_results[peer].keys()[0])
	world_sync._flush_builds()
	world_sync._state_tick()
	publish()
	_reply(peer, seq, result)

func _process(delta: float) -> void:
	if mp == null or not mp.active() or mp.is_host or pending.is_empty():
		return
	_retry += delta
	if _retry < 2.0:
		return
	_retry = 0.0
	for seq in pending:
		var entry: Dictionary = pending[seq]
		mp._rx_economy_request.rpc_id(1, epoch, int(seq), entry.action, entry.args)

func _reply(peer: int, seq: int, result: Dictionary) -> void:
	if peer == 1:
		on_result(epoch, seq, result)
	else:
		mp._rx_economy_result.rpc_id(peer, epoch, seq, result)

func on_result(token: String, seq: int, result: Dictionary) -> void:
	if token != epoch or not pending.has(seq):
		return
	pending.erase(seq)
	world_sync.tools_sync.accept_result(seq, result)
	var tool: Node = world_sync.player.build
	if is_instance_valid(tool) and tool.has_method("accept_result"):
		tool.accept_result(seq, result)
	if result.get("ok", false):
		var id := str(result.get("id", ""))
		var action := str(result.get("action", ""))
		var missions: Variant = world_sync.world.get("missions")
		if is_instance_valid(missions) and missions.has_method("accept_action"):
			missions.accept_action(action)
		if action == "fetch" and is_instance_valid(world_sync.world.shop_menu):
			world_sync.world.shop_menu.accept_fetch(id, int(result.get("moved", 0)))
		if result.get("action") == "tool_pickup" and GameState.has_tool(id):
			world_sync.player.equip_tool_id(id)
		if result.get("action") == "buy" and GameState.has_tool(id):
			var shop: Node = world_sync.world.shop_menu
			if is_instance_valid(shop) and shop._can_hand_over():
				world_sync.player.equip_tool_id(id)
	else:
		mp.ui.notify(str(result.get("message", mp.t("purchase_declined"))))
	if is_instance_valid(world_sync.world.shop_menu):
		world_sync.world.shop_menu._refresh()
	completed.emit(seq, result)

func _gifts_changed() -> void:
	if mp.is_host and not executing:
		publish()

func _purchase_changed(_kind: String, _id: String) -> void:
	_gifts_changed()

func publish(pid: int = 0) -> void:
	if not mp.is_host:
		return
	var state := {"gifts": GameState.gifts.duplicate(true),
		"gifts_given": GameState.gifts_given.duplicate(true),
		"purchase_log": GameState.purchase_log.duplicate(true)}
	if pid != 0:
		mp._rx_economy_state.rpc_id(pid, epoch, state)
	else:
		for peer in mp.players:
			if peer != 1 and mp.players[peer].get("state") == "world":
				mp._rx_economy_state.rpc_id(peer, epoch, state)

func on_state(token: String, state: Dictionary) -> void:
	if mp.is_host:
		return
	if epoch != token:
		epoch = token
		pending.clear()
		world_sync.tools_sync.reset_actions()
		if is_instance_valid(world_sync.player.build):
			world_sync.player.build.request_id = 0
	var previous: Dictionary = GameState.gifts.duplicate(true)
	for key in ["gifts", "gifts_given", "purchase_log"]:
		if state.has(key) and typeof(state[key]) == typeof(GameState.get(key)):
			GameState.set(key, state[key].duplicate(true))
	if previous != GameState.gifts:
		GameState.gifts_changed.emit()

func _failure(key: String) -> Dictionary:
	return {"ok": false, "message": mp.t(key)}

func _valid_transform(value: Variant) -> bool:
	if not (value is Transform3D):
		return false
	return value.origin.is_finite() and value.origin.length() < 10000.0 \
		and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite() \
		and absf(value.basis.determinant()) > 0.01

func _actor(peer: int, args: Dictionary) -> Player:
	if not _valid_transform(args.get("body")) or not _valid_transform(args.get("camera")):
		return null
	var body: Transform3D = args.body
	var camera: Transform3D = args.camera
	if body.origin.distance_to(camera.origin) > 5.0:
		return null
	var actor: Player = _actors.get(peer)
	if not is_instance_valid(actor):
		actor = load(mp.base_dir + "/mp_build_actor.gd").new()
		actor.name = "MPBuildActor" + str(peer)
		actor.defer_tools = true
		actor.camera = Camera3D.new()
		actor.add_child(actor.camera)
		actor.warehouse = world_sync.world.warehouse
		world_sync.world.add_child(actor)
		actor.hide()
		_actors[peer] = actor
	actor.global_transform = body.orthonormalized()
	actor.camera.global_transform = camera.orthonormalized()
	return actor

func _discard_actor(peer: int) -> void:
	var actor: Variant = _actors.get(peer)
	if is_instance_valid(actor):
		actor.queue_free()
	_actors.erase(peer)
	_preparing.erase(peer)

func _prepare_build_tool(peer: int, args: Dictionary) -> int:
	var actor := _actor(peer, args)
	if not is_instance_valid(actor):
		return -1
	if not _preparing.has(peer):
		_preparing[peer] = Time.get_ticks_msec()
	var tool := _build_tool(actor)
	if not is_instance_valid(tool) or tool.is_queued_for_deletion() or not tool.is_inside_tree() \
			or not ("previews_ready" in tool):
		_discard_actor(peer)
		return -1
	if bool(tool.previews_ready):
		_preparing.erase(peer)
		return 1
	if Time.get_ticks_msec() - int(_preparing[peer]) >= BUILD_PREPARE_TIMEOUT_MSEC:
		push_warning("[MP] Build preview preparation timed out")
		_discard_actor(peer)
		return -1
	return 0

func _execute(peer: int, action: String, args: Dictionary) -> Dictionary:
	if args.has("inputs") and not (args.inputs is Dictionary):
		return _failure("purchase_declined")
	if args.has("target") and not (args.target is Dictionary):
		return _failure("purchase_declined")
	if args.has("max_price") and typeof(args.max_price) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("purchase_declined")
	if args.has("tier") and not (args.tier is int):
		return _failure("purchase_declined")
	if args.has("item") and not (args.item is int):
		return _failure("purchase_declined")
	if action == "demolish_tile" and not (args.get("tile") is Rect2):
		return _failure("purchase_declined")
	var actor := _actor(peer, args)
	if actor == null:
		return _failure("purchase_declined")
	match action:
		"buy":
			return _buy(peer, actor, args)
		"tool_drop":
			return _drop_tool(peer, actor, args)
		"tool_pickup":
			return _pickup_tool(peer, actor, args)
		"sell":
			return _sell(actor, args)
		"fetch":
			return _fetch(actor, args)
		"arm_upgrade":
			return _upgrade_arm(args)
		"place":
			return _build(actor, action, args)
		"demolish", "demolish_tile", "reverse":
			return _edit(actor, action, args)
	return _failure("purchase_declined")

func _buy(peer: int, actor: Player, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not ItemDb.has_item(id) or not ItemDb.is_unlocked(id) or ItemDb.price(id) <= 0.0:
		return _failure("purchase_declined")
	if not world_sync.world.shop.is_near(actor.global_position):
		return _failure("economy_shop_distance")
	var price := float(ItemDb.price(id))
	var limit := float(args.get("max_price", -1.0))
	if not is_finite(limit) or price > limit + 0.001:
		return _failure("economy_price_changed")
	if id in GameState.TOOL_IDS and world_sync.tools_sync.has_tool(peer, id):
		return {"ok": true, "already_owned": true}
	if not GameState.spend_money(price):
		return _failure("economy_funds")
	if id in GameState.TOOL_IDS:
		if not world_sync.tools_sync.grant(peer, id):
			GameState.add_money(price)
			return _failure("purchase_declined")
	else:
		var item: Variant = world_sync.props_sync.props.spawn_at_feet(id, actor)
		if not is_instance_valid(item):
			GameState.add_money(price)
			return _failure("purchase_declined")
		Tech.note_bought(id)
	GameState.note_purchase("tool", id, 0, price)
	return {"ok": true}

func _sell(actor: Player, args: Dictionary) -> Dictionary:
	if not world_sync.world.shop.is_near(actor.global_position):
		return _failure("economy_shop_distance")
	var id := str(args.get("id", ""))
	var item_id := int(args.get("item", 0))
	var props: Node = world_sync.props_sync
	var item: Variant = props._by_id.get(item_id)
	if not is_instance_valid(item) or item.item_id != id or props._held.has(item_id) or item.is_held():
		return _failure("purchase_declined")
	if not YardSale.buys(item) or ItemDb.price(id) <= 0.0:
		return _failure("purchase_declined")
	BeltPath.release(item)
	props.props.remove(item)
	GameState.add_money(ItemDb.price(id))
	return {"ok": true}

func _fetch(actor: Player, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not ItemDb.has_item(id):
		return _failure("purchase_declined")
	if not world_sync.world.shop.is_near(actor.global_position):
		return _failure("economy_shop_distance")
	var props: Node = world_sync.props_sync
	var moved := 0
	for item_id in props._by_id.keys():
		var item: Variant = props._by_id.get(item_id)
		if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion():
			continue
		if item.item_id != id or props._held.has(item_id) or item.is_held():
			continue
		if item.has_meta(PropManager.META_CLAIM) and int(item.get_meta(PropManager.META_CLAIM)) != props.get_instance_id():
			continue
		props.host_take(item)
		BeltPath.release(item)
		props.props.place_at_feet(item, actor, moved)
		moved += 1
	if moved == 0:
		return _failure("tool_unavailable")
	GameState.used_fetch = true
	return {"ok": true, "moved": moved}

func _upgrade_arm(args: Dictionary) -> Dictionary:
	var target: Node = world_sync._find_building(args.get("target", {}))
	if not is_instance_valid(target) or not (target is RoboticArm):
		return _failure("purchase_declined")
	var expected := int(args.get("tier", -1))
	if target.tier_index > expected and expected >= 0:
		return {"ok": true, "already_owned": true}
	var limit := float(args.get("max_price", -1.0))
	if not is_finite(limit) or target.tier_index != expected or world_sync.builds.arm_upgrade_price(target) > limit + 0.001:
		return _failure("economy_price_changed")
	var blocked: String = world_sync.builds.arm_upgrade_block(target)
	if blocked != "":
		return {"ok": false, "message": blocked}
	return {"ok": world_sync.builds.upgrade_arm(target)}

func _build(actor: Player, action: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("build_id", ""))
	if not BuildCatalog.has_id(id):
		return _failure("purchase_declined")
	if action == "place" and (not BuildCatalog.is_unlocked(id) or BuildCatalog.is_withheld(id)):
		return _failure("purchase_declined")
	var tool := _build_tool(actor)
	actor.build_id = id
	tool.set_mode(BuildCatalog.mode_of(id))
	tool._follow_tech()
	var inputs: Dictionary = args.get("inputs", {})
	for key in tool.INPUT_FIELDS:
		if not inputs.has(key) or typeof(inputs[key]) != typeof(tool.get(key)):
			continue
		var value: Variant = inputs[key]
		if value is PackedVector3Array and value.size() > 256:
			return _failure("purchase_declined")
		if value is Vector3 and not value.is_finite() and key not in ["_finished_at", "_tee_stop_at"]:
			return _failure("purchase_declined")
		if value is Vector2 and (not value.is_finite() or value.length() > 10000.0):
			return _failure("purchase_declined")
		if value is float and not is_finite(value) and (key not in ["_work_height", "_work_base"] or not is_nan(value)):
			return _failure("purchase_declined")
		if value is PackedVector3Array:
			for point in value:
				if not point.is_finite() or point.length() > 10000.0:
					return _failure("purchase_declined")
		tool.set(key, value)
	tool._reach = clampf(tool._reach, Cfg.BUILD_REACH_MIN, Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus())
	if tool._state not in [BuildTool.State.AIMING, BuildTool.State.RUNNING]:
		return _failure("purchase_declined")
	tool._placed_tick = -1
	tool._active = true
	actor.show()
	tool._sync_ghosts()
	world_sync.builds.ghost_reading = true
	tool._update_ghost(0.0)
	world_sync.builds.ghost_reading = false
	tool._eval_pick = tool._pick
	var status: Dictionary = tool.status()
	var limit := float(args.get("max_price", -1.0))
	if not is_finite(limit) or limit < 0.0 or float(status.get("cost", 0.0)) > limit + 0.001:
		actor.hide()
		return _failure("economy_price_changed")
	tool.price_limit = limit
	if not status.get("ok", false) and not status.get("done", false):
		actor.hide()
		return {"ok": false, "message": str(status.get("reason", mp.t("purchase_declined")))}
	var before: Dictionary = world_sync._scan_builds()
	var old_inputs: Dictionary = tool.capture_inputs()
	var counters := {}
	for key in tool.COUNTER_FIELDS:
		counters[key] = int(tool.get(key))
	tool.execute_native(action, null, args)
	actor.hide()
	var after: Dictionary = world_sync._scan_builds()
	var new_inputs: Dictionary = tool.capture_inputs()
	var changed := before != after or var_to_bytes(old_inputs) != var_to_bytes(new_inputs)
	for key in counters:
		counters[key] = maxi(0, int(tool.get(key)) - int(counters[key]))
	var result := {"ok": changed, "inputs": new_inputs, "counters": counters, "build_id": id,
		"placed": action == "place" and before != after,
		"message": "" if changed else mp.t("purchase_declined")}
	return result

func _build_tool(actor: Player) -> Node:
	var tool: Node = actor.build
	if not is_instance_valid(tool):
		tool = load(mp.base_dir + "/mp_build_tool.gd").new()
		tool.player = actor
		tool.builds = world_sync.builds
		actor.build = tool
		actor.add_child(tool)
		tool.set_process(false)
		tool.set_physics_process(false)
		tool.set_process_unhandled_input(false)
	return tool

func _edit(actor: Player, action: String, args: Dictionary) -> Dictionary:
	var target: Node3D = world_sync._find_building(args.get("target", {}))
	if not is_instance_valid(target):
		return _failure("building_missing")
	var blocked := ""
	match action:
		"demolish":
			blocked = world_sync.builds.demolish_blocked_reason(target)
		"demolish_tile":
			if not (target is Platform):
				return _failure("building_invalid")
			var tile: Rect2 = args.tile
			if not tile.position.is_finite() or not tile.size.is_finite() or tile.size.x <= 0.0 or tile.size.y <= 0.0:
				return _failure("building_invalid")
			var center := tile.get_center()
			var canonical := BuildManager.deck_tile_at(target, Vector3(center.x, target.top_y(), center.y))
			if not tile.is_equal_approx(canonical):
				return _failure("building_invalid")
			blocked = world_sync.builds.tile_blocked_reason(target, tile)
		"reverse":
			if not (target is Conveyor):
				return _failure("building_invalid")
			blocked = world_sync.builds.reverse_blocked_reason(target)
	if blocked != "":
		return {"ok": false, "message": blocked}
	var tool := _build_tool(actor)
	var counters := {}
	for key in tool.COUNTER_FIELDS:
		counters[key] = int(tool.get(key))
	var before: Dictionary = world_sync._scan_builds()
	tool.execute_native(action, target, args)
	var changed: bool = before != world_sync._scan_builds()
	for key in counters:
		counters[key] = maxi(0, int(tool.get(key)) - int(counters[key]))
	var result := {"ok": changed, "counters": counters,
		"message": "" if changed else mp.t("building_invalid")}
	if action == "reverse" and is_instance_valid(tool.last_reversed):
		result["reversed_target"] = tool.last_reversed.to_dict()
	return result


func _drop_tool(peer: int, actor: Player, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	if not world_sync.tools_sync.has_tool(peer, id) or not ToolProp.has_spec(id):
		return _failure("tool_unavailable")
	var spawned: bool = actor._throw_tool_object(id) if bool(args.get("throwing", false)) else actor._drop_tool_object(id)
	if not spawned:
		return _failure("purchase_declined")
	world_sync.tools_sync.take(peer, id)
	return {"ok": true}


func _pickup_tool(peer: int, actor: Player, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	var item_id := int(args.get("item", 0))
	var props: Node = world_sync.props_sync
	var item: Variant = props._by_id.get(item_id)
	if not is_instance_valid(item) or not (item is ToolProp or item is SandShovel) or item.item_id != id or props._held.has(item_id) or item.is_held():
		return _failure("tool_unavailable")
	var reach: float = Tech.carry_reach() + item.ride_box().size.length() * 0.5 + 1.0
	if item.global_position.distance_to(actor.eye_position()) > reach:
		return _failure("tool_unavailable")
	if not world_sync.tools_sync.grant(peer, id):
		return _failure("tool_capacity")
	BeltPath.release(item)
	props.props.remove(item)
	return {"ok": true}
