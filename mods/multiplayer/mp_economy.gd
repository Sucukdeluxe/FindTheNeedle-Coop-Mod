extends Node

const BuildSnapshot = preload("res://mods/multiplayer/mp_build_snapshot.gd")


signal completed(seq: int, result: Dictionary)
const CACHE_LIMIT := 256
const MAX_PENDING := 32
const BuildCamera = preload("res://mods/multiplayer/mp_build_camera.gd")
const LOCAL_ACTIONS := ["hopper_place", "hopper_remove", "hopper_deposit", "hopper_tool_deposit", "hopper_tool_ack", "hopper_tool_resolve", "hopper_configure", "hopper_link", "receiver_place", "receiver_configure", "sale_place", "sale_move", "supply_move", "sale_remove", "sale_configure", "vacuum_belt", "vacuum_resolve", "vacuum_ack", "sweep_floor", "order_pile"]
const BUILD_PREPARE_TIMEOUT_MSEC := 30000
var mp: Node
var world_sync: Node
var epoch := ""
var executing := false
var pending := {}
var _next := 0
var _t_revision := 0
var _queue: Array = []
var _queued := {}
var _last := {}
var _results := {}
var _actors := {}
var _preparing := {}
var _originals := {}
var _retry := 0.0
var _purchase_spots: Array = []

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	session_started()
	_hook(sync.player.build, "mp_hopper_build_tool.gd")
	sync.player.build.set_process_input(true)
	_hook(sync.player.arm_links, "mp_arm_link_mode.gd")
	_hook(sync.world.shop_menu, "mp_shop.gd")
	_hook(sync.world.t_panel, "mp_t_panel.gd")
	_hook(sync.world.load_panel, "mp_load_panel.gd")
	_hook(sync.world.get("delivery_board"), "mp_delivery_board.gd")
	get_tree().node_added.connect(_options_added)
	for control in get_tree().root.find_children("*", "Control", true, false):
		_options_added(control)
	GameState.gifts_changed.connect(_gifts_changed)
	GameState.purchased.connect(_purchase_changed)

func session_started() -> void:
	if mp.is_host and epoch == "":
		epoch = str(Time.get_ticks_usec()) + ":" + str(randi())

func session_ended() -> void:
	for peer in _actors.keys():
		_discard_actor(peer)
	_queue.clear()
	_queued.clear()
	_results.clear()
	_last.clear()
	pending.clear()
	_preparing.clear()
	_purchase_spots.clear()
	_retry = 0.0
	epoch = ""
	if is_instance_valid(world_sync.tools_sync):
		world_sync.tools_sync.reset_actions()
	if is_instance_valid(world_sync.player.build) and world_sync.player.build.has_method("reset_mp_request"):
		world_sync.player.build.reset_mp_request()

func _hook(node: Node, file: String) -> void:
	if not is_instance_valid(node):
		return
	_originals[node] = node.get_script()
	_replace(node, load(mp.base_dir + "/" + file))
	node.set("mp_economy", self)

func _options_added(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var script: Script = node.get_script()
	if script != null and script.resource_path == "res://scripts/ui/options_panel.gd":
		_hook_options.call_deferred(node)

func _hook_options(node: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(world_sync) or is_queued_for_deletion():
		return
	var script: Script = node.get_script()
	if _originals.has(node) or script == null or script.resource_path != "res://scripts/ui/options_panel.gd":
		return
	_hook(node, "mp_options_panel.gd")

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
	if is_inside_tree() and get_tree().node_added.is_connected(_options_added):
		get_tree().node_added.disconnect(_options_added)
	if GameState.gifts_changed.is_connected(_gifts_changed):
		GameState.gifts_changed.disconnect(_gifts_changed)
	if GameState.purchased.is_connected(_purchase_changed):
		GameState.purchased.disconnect(_purchase_changed)
	for node in _originals:
		if is_instance_valid(node):
			if node.has_method("reset_mp_request"):
				node.reset_mp_request()
			_replace(node, _originals[node])
	_originals.clear()
	for actor in _actors.values():
		if is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()
	_preparing.clear()
	_purchase_spots.clear()
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
	if not mp.active():
		if action not in LOCAL_ACTIONS or pending.size() >= MAX_PENDING or world_sync._frozen:
			return 0
		_next = maxi(_next, mp.economy_sequence) + 1
		mp.economy_sequence = _next
		pending[_next] = {"action": action, "args": args.duplicate(true)}
		_execute_local.call_deferred(_next, action, args.duplicate(true))
		return _next
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
		(mp._rx_vacuum_request if action.begins_with("vacuum_") else mp._rx_economy_request).rpc_id(1, epoch, _next, action, args, mp._outgoing_world_seed())
	return _next

func _execute_local(seq: int, action: String, args: Dictionary) -> void:
	if not pending.has(seq):
		return
	var before := float(GameState.money)
	var result := _failure("economy_expired")
	if not mp.active() and not world_sync._frozen and action in LOCAL_ACTIONS:
		executing = true
		result = _execute(1, action, args)
		executing = false
	result["money_change"] = float(GameState.money) - before
	result["action"] = action
	result["id"] = str(args.get("id", ""))
	on_result(epoch, seq, result)

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
	var index := -1
	var preparation := 1
	var seen := {}
	for i in _queue.size():
		var waiting: Dictionary = _queue[i]
		var pid := int(waiting.peer)
		if seen.has(pid):
			continue
		seen[pid] = true
		var ready := 1
		if mp.players.has(pid) and int(waiting.seq) > int(_last.get(pid, 0)) and not world_sync._frozen and waiting.action == "place":
			ready = _prepare_build_tool(pid, waiting.args)
		if ready != 0:
			index = i
			preparation = ready
			break
	if index < 0:
		return
	var entry: Dictionary = _queue[index]
	var peer := int(entry.peer)
	var seq := int(entry.seq)
	_queue.remove_at(index)
	_queued.erase(str(peer) + ":" + str(seq))
	if not mp.players.has(peer):
		return
	if seq <= int(_last.get(peer, 0)):
		_reply(peer, seq, _failure("economy_expired"))
		return
	var before := float(GameState.money)
	executing = true
	var result := _failure("economy_wait")
	if not world_sync._frozen or entry.action == "build_cancel":
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
	if not entry.action.begins_with("needle_") and not entry.action.begins_with("vacuum_") and entry.action not in ["hopper_deposit", "hopper_tool_deposit", "hopper_tool_ack", "hopper_tool_resolve", "sweep_floor", "order_pile"]:
		world_sync._flush_builds()
	if entry.action == "t_configure" and result.get("ok", false):
		world_sync.machines_sync._send_fields()
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
		(mp._rx_vacuum_request if str(entry.action).begins_with("vacuum_") else mp._rx_economy_request).rpc_id(1, epoch, int(seq), entry.action, entry.args, mp._outgoing_world_seed())

func _reply(peer: int, seq: int, result: Dictionary) -> void:
	if peer == 1:
		on_result(epoch, seq, result)
	else:
		(mp._rx_vacuum_result if str(result.get("action", "")).begins_with("vacuum_") else mp._rx_economy_result).rpc_id(peer, epoch, seq, result, mp._outgoing_world_seed())

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
	var panel: Variant = world_sync.world.get("t_panel")
	if is_instance_valid(panel) and panel.has_method("accept_result"):
		panel.accept_result(seq, result)
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
		mp._rx_economy_state.rpc_id(pid, epoch, state, mp._outgoing_world_seed())
	else:
		for peer in mp.players:
			if peer != 1 and mp.players[peer].get("state") == "world":
				mp._rx_economy_state.rpc_id(peer, epoch, state, mp._outgoing_world_seed())

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

func _actor(peer: int, args: Dictionary, allow_view: bool = false) -> Player:
	if not _valid_transform(args.get("body")) or not _valid_transform(args.get("camera")):
		return null
	var body: Transform3D = args.body
	var camera: Transform3D = args.camera
	var ray := {}
	if args.has("build_view"):
		if not allow_view:
			return null
		var known: Variant = world_sync.player.global_position if peer == 1 else world_sync._last_at.get(peer)
		if not (known is Vector3) or not known.is_finite() or known.distance_to(body.origin) > 4.0:
			return null
		ray = BuildCamera.validate_view(args.build_view, known)
		if ray.is_empty():
			return null
		ray["anchor"] = known
		camera = ray.transform
	elif body.origin.distance_to(camera.origin) > 5.0:
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
	if ray.is_empty():
		if actor.has_meta("mp_build_view"):
			actor.remove_meta("mp_build_view")
	else:
		actor.set_meta("mp_build_view", ray)
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
	var actor := _actor(peer, args, true)
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
	if action == "order_pile":
		return world_sync.order_pile(peer, args)
	if action == "sweep_floor":
		return world_sync.sweep_sync.execute(peer, args)
	if action == "supply_move":
		return world_sync.hoppers_sync.supply_station.execute(peer, action, args)
	if action.begins_with("sale_"):
		return world_sync.hoppers_sync.sale_stations.execute(peer, action, args)
	if action.begins_with("receiver_"):
		return world_sync.hoppers_sync.receivers.execute(peer, action, args)
	if action.begins_with("hopper_"):
		return world_sync.hoppers_sync.execute(peer, action, args)
	if action in ["vacuum_belt", "vacuum_resolve", "vacuum_ack"]:
		return world_sync.vacuum_transfer.execute(peer, action, args)
	if action.begins_with("needle_"):
		return world_sync.needles_sync.execute(peer, action, args)
	if action == "power":
		return world_sync.power_sync.execute(args)
	if action == "build_cancel":
		_cancel_build(peer)
		return {"ok": true}
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
	var actor := _actor(peer, args, action in ["place", "demolish", "demolish_tile", "reverse", "rotate_existing"])
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
		"lift_reshape":
			return _reshape_lift(args)
		"t_configure":
			return _configure_t(args)
		"place":
			return _build(actor, action, args)
		"rotate_existing":
			return _rotate_existing(actor, args)
		"demolish", "demolish_tile", "reverse":
			return _edit(actor, action, args)
	return _failure("purchase_declined")

func _cancel_build(peer: int) -> void:
	var actor: Variant = _actors.get(peer)
	if not is_instance_valid(actor) or actor.is_queued_for_deletion():
		return
	var tool: Variant = actor.get("build")
	if is_instance_valid(tool) and not tool.is_queued_for_deletion():
		tool.cancel()
	actor.hide()

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
		var item: Variant = _spawn_purchase(id, actor)
		if not is_instance_valid(item):
			GameState.add_money(price)
			return _failure("purchase_declined")
		Tech.note_bought(id)
	GameState.note_purchase("tool", id, 0, price)
	return {"ok": true}

func _spawn_purchase(id: String, actor: Player) -> Carryable:
	var props: Node = world_sync.props_sync.props
	var blocked := props.is_blocking_signals()
	props.set_block_signals(true)
	var item: Carryable = props.spawn_at_feet(id, actor)
	if not is_instance_valid(item):
		props.set_block_signals(blocked)
		return null
	if not _place_purchase(item, actor):
		props.remove(item)
		props.set_block_signals(blocked)
		return null
	props.set_block_signals(blocked)
	if not blocked:
		props.emit_signal("item_added", item)
		props.emit_signal("changed")
	return item

func _purchase_shapes(item: Carryable) -> Array:
	var shapes: Array = []
	for owner in item.get_shape_owners():
		if item.is_shape_owner_disabled(owner):
			continue
		for index in item.shape_owner_get_shape_count(owner):
			var shape: Shape3D = item.shape_owner_get_shape(owner, index)
			if shape == null:
				continue
			shapes.append({"shape": shape, "transform": item.shape_owner_get_transform(owner)})
	return shapes

func _place_purchase(item: Carryable, actor: Player) -> bool:
	var shapes := _purchase_shapes(item)
	if shapes.is_empty():
		return false
	var bounds: AABB
	for index in shapes.size():
		var local_bounds: AABB = shapes[index].transform * shapes[index].shape.get_debug_mesh().get_aabb()
		bounds = local_bounds if index == 0 else bounds.merge(local_bounds)
	bounds = bounds.grow(0.025)
	var frame := Engine.get_physics_frames()
	for index in range(_purchase_spots.size() - 1, -1, -1):
		var previous: Variant = _purchase_spots[index]
		var previous_item: Variant = previous.item.get_ref()
		if not is_instance_valid(previous_item) or previous_item.is_queued_for_deletion() or frame > int(previous.frame) + 2:
			_purchase_spots.remove_at(index)
	var desired := item.global_transform
	var space := actor.get_world_3d().direct_space_state
	var exclude: Array[RID] = [actor.get_rid(), item.get_rid()]
	var mask: int = Cfg.L_WORLD | Cfg.L_BUILD | Cfg.L_PROP | Cfg.L_PILE
	var step := clampf(maxf(bounds.size.x, bounds.size.z) + 0.1, 0.5, 1.0)
	var offsets: Array[Vector3] = [Vector3.ZERO]
	for ring in 3:
		var radius := step * float(ring + 1)
		for index in 8:
			var angle := float(index) * TAU / 8.0
			offsets.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	for offset in offsets:
		var candidate := desired
		candidate.origin += offset
		var chest := actor.global_position + Vector3.UP * 0.9
		var ray := PhysicsRayQueryParameters3D.create(chest, candidate.origin + Vector3.UP * 0.15, Cfg.L_WORLD | Cfg.L_BUILD, exclude)
		if not space.intersect_ray(ray).is_empty():
			continue
		var candidate_bounds: AABB = candidate * bounds
		var occupied := false
		for previous in _purchase_spots:
			var previous_item: Variant = previous.item.get_ref()
			if not is_instance_valid(previous_item):
				continue
			var previous_bounds: AABB = previous_item.global_transform * previous.bounds
			if candidate_bounds.intersects(previous_bounds):
				occupied = true
				break
		if occupied:
			continue
		for entry in shapes:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = entry.shape
			query.transform = candidate * entry.transform
			query.collision_mask = mask
			query.exclude = exclude
			query.margin = 0.025
			if not space.intersect_shape(query, 1).is_empty():
				occupied = true
				break
		if occupied:
			continue
		item.global_transform = candidate
		_purchase_spots.append({"item": weakref(item), "bounds": bounds, "frame": frame})
		return true
	return false

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

func _rotate_existing(actor: Player, args: Dictionary) -> Dictionary:
	if not (args.get("target") is Dictionary) or typeof(args.get("yaw")) not in [TYPE_INT, TYPE_FLOAT] or typeof(args.get("previous_yaw")) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("purchase_declined")
	var target: Node3D = world_sync._find_building(args.target)
	if not is_instance_valid(target) or target is Conveyor or not is_finite(float(args.yaw)) or absf(float(args.yaw)) > PI + 0.001:
		return _failure("building_invalid")
	if absf(wrapf(target.global_rotation.y - float(args.previous_yaw), -PI, PI)) > 0.02:
		return _failure("economy_expired")
	if target.has_method("empty") and not target.empty():
		return _failure("building_invalid")
	for field in ["stored_strands", "stored_bricks", "stored_hay", "stored_pellets"]:
		if field in target and int(target.get(field)) > 0:
			return _failure("building_invalid")
	var before: Dictionary = world_sync._scan_builds()
	var yaw := wrapf(float(args.yaw), -PI, PI)
	target.rotation.y = yaw
	target.global_rotation.y = yaw
	world_sync.builds.rebuild_junctions()
	world_sync.builds.rebuild_water_joints()
	target.rotation.y = yaw
	target.global_rotation.y = yaw
	world_sync.builds.changed.emit()
	var changed: bool = before != world_sync._scan_builds()
	return {"ok": changed, "message": "" if changed else mp.t("building_invalid"), "yaw": target.global_rotation.y}

func _build(actor: Player, action: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("build_id", ""))
	if not BuildCatalog.has_id(id):
		return _failure("purchase_declined")
	if action == "place" and (not BuildCatalog.is_unlocked(id) or BuildCatalog.is_withheld(id)):
		return _failure("purchase_declined")
	var tool := _build_tool(actor)
	actor.build_id = id
	var inputs: Dictionary = args.get("inputs", {})
	if not tool.rotation_inputs_allowed(inputs):
		return _failure("purchase_declined")
	if actor.has_meta("mp_build_view") and not BuildCamera.inputs_allowed(inputs, actor.get_meta("mp_build_view").anchor):
		return _failure("purchase_declined")
	tool.prepare_mode(BuildCatalog.mode_of(id), inputs)
	tool._follow_tech()
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
		tool.set_process_input(false)
		tool.set_process_unhandled_input(false)
	return tool

func _edit(actor: Player, action: String, args: Dictionary) -> Dictionary:
	var target: Node3D = world_sync._find_building(args.get("target", {}))
	if not is_instance_valid(target):
		return _failure("building_missing")
	if actor.has_meta("mp_build_view"):
		var ray: Dictionary = actor.get_meta("mp_build_view")
		var point := target.global_position
		if action == "demolish_tile":
			if not (target is Platform):
				return _failure("building_invalid")
			var center: Vector2 = args.tile.get_center()
			point = Vector3(center.x, target.top_y(), center.y)
		if not BuildCamera.point_allowed(point, ray.anchor):
			return _failure("building_invalid")
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
		result["reversed_target"] = BuildSnapshot.row(tool.last_reversed)
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

func _reshape_lift(args: Dictionary) -> Dictionary:
	if not mp.is_host or not executing:
		return _failure("purchase_declined")
	if not (args.get("target") is Dictionary) or not (args.get("down") is bool) \
			or not (args.get("turn") is int):
		return _failure("building_invalid")
	var turn := int(args.turn)
	if turn < 0 or turn > 3:
		return _failure("building_invalid")
	var lift: Node3D = world_sync._find_building(args.target)
	if not is_instance_valid(lift) or not (lift is HayLift) or not lift.is_inside_tree() or lift.is_queued_for_deletion():
		return _failure("building_missing")
	var result: Dictionary = world_sync.builds.reshape_hay_lift(lift, args.down, turn)
	var error := str(result.get("error", ""))
	if error != "":
		return {"ok": false, "message": error}
	if not is_instance_valid(result.get("lift")):
		return _failure("building_missing")
	return {"ok": true}

func _configure_t(args: Dictionary) -> Dictionary:
	if not mp.is_host or not executing or not (args.get("target") is Dictionary) or not (args.get("manual") is bool):
		return _failure("building_invalid")
	var target: Node3D = world_sync._find_building(args.target)
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
		return _failure("building_missing")
	if not (target is ConveyorTSplitter or target is ConveyorTJoiner):
		return _failure("building_invalid")
	var now: Node3D
	if args.manual:
		if not (args.get("roles") is Array) or args.roles.size() != 3:
			return _failure("building_invalid")
		var roles: Array[int] = []
		for role in args.roles:
			if not (role is int) or role < ConveyorTSplitter.ROLE_IN or role > ConveyorTSplitter.ROLE_CLOSED:
				return _failure("building_invalid")
			roles.append(role)
		if ConveyorTSplitter.shape_of(roles) == "":
			return _failure("building_invalid")
		var result: Dictionary = world_sync.builds.set_t_by_hand(target, roles)
		if str(result.get("error", "")) != "":
			return {"ok": false, "message": str(result.error)}
		now = result.get("t")
	else:
		now = world_sync.builds.set_t_by_belts(target)
	if not is_instance_valid(now) or not now.is_inside_tree() or now.is_queued_for_deletion():
		return _failure("building_missing")
	_t_revision = maxi(maxi(_t_revision + 1, int(now.get_meta("mp_t_revision", 0)) + 1), Time.get_ticks_usec())
	now.set_meta("mp_t_revision", _t_revision)
	world_sync.machines_sync.send_all(0)
	return {"ok": true, "target": BuildSnapshot.row(now), "t_revision": _t_revision}
