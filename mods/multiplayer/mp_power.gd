extends Node

const BuildSnapshot = preload("res://mods/multiplayer/mp_build_snapshot.gd")
const FrameSlots = preload("res://mods/multiplayer/mp_frame_slots.gd")


signal completed(seq: int, result: Dictionary)
const TICK := 1.0
const FULL_TICK := 5.0
const MAX_NODES := 16384
const MAX_BYTES := 8 << 20
var mp: Node
var world_sync: Node
var builds: Node
var applying := false
var device_panel: Control
var _originals := {}
var _requests := {}
var _ids := {}
var _nodes := {}
var _next_id := 0
var _revision := 0
var _changed_at := {}
var _flat := {}
var _packet := {}
var _pending := {}
var _client_nodes := {}
var _client_ids := {}
var _clock := 0.0
var _full_clock := 0.0
var _slot := FrameSlots.new()
var _builds_flushed := false
var _sent_revision := 0
var _client_epoch := ""
var _applied_revision := 0

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	builds = sync.builds
	sync.economy.completed.connect(_completed)
	_hook_controls()
	device_panel = preload("res://mods/multiplayer/mp_device_panel.gd").new()
	add_child(device_panel)
	device_panel.start(self)

func _hook_controls() -> void:
	_hook(builds.get("tags"), "mp_power_tags.gd")
	_hook(builds.get("grid"), "mp_power_grid.gd")
	var panel: Variant = world_sync.player.get("pole_panel")
	_hook(panel, "mp_pole_panel.gd")
	if is_instance_valid(panel) and not completed.is_connected(panel._power_completed):
		completed.connect(panel._power_completed)
	var wire: Variant = world_sync.player.get("wire_mode")
	_hook(wire, "mp_wire_mode.gd")
	if is_instance_valid(wire) and wire.has_method("_power_completed") and not completed.is_connected(wire._power_completed):
		completed.connect(wire._power_completed)

func _hook(object: Object, file: String) -> void:
	if not is_instance_valid(object) or _originals.has(object):
		return
	_originals[object] = object.get_script()
	_replace(object, load(mp.base_dir + "/" + file))
	object.set("mp_power", self)

func _replace(object: Object, script: Script) -> void:
	var values := {}
	for property in object.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = object.get(property.name)
	object.set_script(script)
	for key in values:
		if key in object:
			object.set(key, values[key])

func shutdown() -> void:
	if is_instance_valid(device_panel):
		device_panel.shutdown()
		device_panel.queue_free()
	if is_instance_valid(world_sync.economy) and world_sync.economy.completed.is_connected(_completed):
		world_sync.economy.completed.disconnect(_completed)
	for object in _originals:
		if is_instance_valid(object):
			if object.has_method("_power_completed") and completed.is_connected(object._power_completed):
				completed.disconnect(object._power_completed)
			if is_instance_valid(builds) and object == builds.grid:
				_restore_grid(object, _originals[object])
			else:
				_replace(object, _originals[object])
	_originals.clear()
	_requests.clear()
	_client_nodes.clear()
	_client_ids.clear()

func _restore_grid(current: Object, original: Script) -> void:
	var restored: RefCounted = original.new(builds)
	for property in current.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name in restored:
			restored.set(property.name, current.get(property.name))
	builds.grid = restored

func _ready_for_state() -> bool:
	return is_instance_valid(builds) and not world_sync._frozen and not world_sync._applying_builds and world_sync.economy.epoch != "" and builds._grid_settle == 0

func _process(delta: float) -> void:
	if mp == null or not mp.active():
		return
	_clock += delta
	_full_clock += delta
	if _clock < TICK or not _ready_for_state() or not _slot.take():
		return
	if mp.is_host and not _builds_flushed:
		world_sync._flush_builds()
		_builds_flushed = true
		return
	_builds_flushed = false
	_clock = 0.0
	_hook_controls()
	if mp.is_host:
		publish(0, _full_clock >= FULL_TICK, false)
	else:
		_apply_pending()
	if _full_clock >= FULL_TICK:
		_full_clock = 0.0

func _live(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node3D and node.is_inside_tree() and not node.is_queued_for_deletion()

func _switchable(node: Node) -> bool:
	return PowerTags.taggable(node) or (node.has_method("mp_belt_switchable") and node.has_method("is_switched_off") and node.has_method("set_switched_off") and bool(node.mp_belt_switchable()))

func _switch_targets(node: Node3D) -> Array:
	if node.has_method("mp_belt_switch_targets"):
		return node.mp_belt_switch_targets()
	return [node]

func _candidates() -> Array:
	var out: Array = []
	for node in builds.all_buildings():
		if _live(node) and (node is PowerPole or _switchable(node)):
			out.append(node)
	return out

func _capture() -> void:
	var live_ids := {}
	var rows: Array = []
	var tags: Variant = builds.get("tags")
	var candidates := _candidates()
	if candidates.size() > MAX_NODES:
		_packet = {}
		return
	_nodes.clear()
	for node in candidates:
		var instance: int = node.get_instance_id()
		if not _ids.has(instance):
			_next_id += 1
			_ids[instance] = _next_id
		var id: int = _ids[instance]
		live_ids[instance] = id
		_nodes[id] = node
	_ids = live_ids
	for node in candidates:
		var id: int = _ids[node.get_instance_id()]
		var pole := node is PowerPole
		var taggable := _switchable(node)
		var row := {"id": id, "key": world_sync._bkey(BuildSnapshot.row(node)), "pole": pole,
			"taggable": taggable, "tag": tags.tag_of(node) if taggable and is_instance_valid(tags) else -1,
			"off": bool(node.is_switched_off()) if taggable else false, "links": [], "cuts": []}
		if pole:
			for target in node.links_to:
				if _live(target) and _ids.has(target.get_instance_id()):
					row.links.append(_ids[target.get_instance_id()])
			for target in node.cuts_to:
				if _live(target) and _ids.has(target.get_instance_id()):
					row.cuts.append(_ids[target.get_instance_id()])
			row.links.sort()
			row.cuts.sort()
		rows.append(row)
	var names: Array = Array(tags.names) if is_instance_valid(tags) else ["", "", "", "", "", "", "", ""]
	var priority: Array = Array(tags.priorities) if is_instance_valid(tags) else [1, 1, 1, 1, 1, 1, 1, 1]
	var state := {"rows": rows, "names": names, "priority": priority}
	var flat := _flatten(state)
	if flat != _flat or _revision == 0:
		_revision += 1
		for key in flat:
			if not _flat.has(key) or flat[key] != _flat[key]:
				_changed_at[key] = _revision
		for key in _flat:
			if not flat.has(key):
				_changed_at[key] = _revision
		_flat = flat
	state["revision"] = _revision
	_packet = state

func _edge_key(a: int, b: int) -> String:
	return "edge:%d:%d" % [mini(a, b), maxi(a, b)]

func _flatten(state: Dictionary) -> Dictionary:
	var flat := {}
	var groups: Array = [[], [], [], [], [], [], [], []]
	for row in state.rows:
		var id: int = row.id
		flat["node:%d" % id] = row.key
		flat["member:%d" % id] = row.tag
		flat["off:%d" % id] = row.off
		if row.tag >= 0:
			groups[row.tag].append(id)
		for target in row.links:
			var key := _edge_key(id, target)
			flat[key] = int(flat.get(key, 0)) | (1 if id < target else 2)
		for target in row.cuts:
			var key := _edge_key(id, target)
			flat[key] = int(flat.get(key, 0)) | (4 if id < target else 8)
	for tag in 8:
		groups[tag].sort()
		flat["group:%d" % tag] = groups[tag]
		flat["name:%d" % tag] = state.names[tag]
		flat["priority:%d" % tag] = state.priority[tag]
	return flat

func publish(pid: int = 0, force: bool = false, flush: bool = true) -> void:
	if not mp.is_host or not _ready_for_state():
		return
	if flush:
		world_sync._flush_builds()
	_capture()
	if _packet.is_empty() or not _valid_state(_packet):
		_observe(true)
		return
	_observe(false)
	if pid == 0 and not force and _sent_revision == _revision:
		return
	if var_to_bytes(_packet).size() > MAX_BYTES:
		return
	if pid != 0:
		mp._rx_power_state.rpc_id(pid, world_sync.economy.epoch, _packet, mp._outgoing_world_seed())
	else:
		for peer in mp.players:
			if peer != 1 and mp.players[peer].get("state") == "world":
				mp._rx_power_state.rpc_id(peer, world_sync.economy.epoch, _packet, mp._outgoing_world_seed())
		_sent_revision = _revision

func invalidate_builds() -> void:
	if mp.is_host:
		return
	_pending.clear()
	_client_nodes.clear()
	_client_ids.clear()
	_applied_revision = 0

func on_state(epoch: String, state: Dictionary) -> void:
	if mp.is_host or epoch != world_sync.economy.epoch:
		return
	if not _valid_state(state):
		_observe(true)
		return
	if _client_epoch != epoch:
		_client_epoch = epoch
		_revision = 0
		_applied_revision = 0
		_client_nodes.clear()
		_client_ids.clear()
		_requests.clear()
	if state.revision < _revision:
		return
	_revision = state.revision
	_pending = state.duplicate(true)
	_apply_pending()

func _valid_state(state: Dictionary) -> bool:
	if not (state.get("revision") is int) or state.revision <= 0 or not (state.get("rows") is Array) or state.rows.size() > MAX_NODES:
		return false
	if not (state.get("names") is Array) or state.names.size() != 8 or not (state.get("priority") is Array) or state.priority.size() != 8:
		return false
	if var_to_bytes(state).size() > MAX_BYTES:
		return false
	for tag in 8:
		if not (state.names[tag] is String) or state.names[tag].length() > 16 or not (state.priority[tag] is int) or state.priority[tag] < 0 or state.priority[tag] > 2:
			return false
	var ids := {}
	var keys := {}
	for row in state.rows:
		if not (row is Dictionary) or not (row.get("id") is int) or row.id <= 0 or ids.has(row.id):
			return false
		if not (row.get("key") is String) or row.key.length() > 2048 or row.key == "" or keys.has(row.key):
			return false
		if not (row.get("pole") is bool) or not (row.get("taggable") is bool) or not (row.get("off") is bool):
			return false
		if not (row.get("tag") is int) or row.tag < -1 or row.tag > 7 or (not row.taggable and row.tag != -1):
			return false
		if not row.pole and not row.taggable:
			return false
		if not (row.get("links") is Array) or not (row.get("cuts") is Array):
			return false
		if row.links.size() > state.rows.size() or row.cuts.size() > state.rows.size() or (not row.pole and (not row.links.is_empty() or not row.cuts.is_empty())):
			return false
		ids[row.id] = row
		keys[row.key] = true
	for row in state.rows:
		for list in [row.links, row.cuts]:
			var seen := {}
			for id in list:
				if not (id is int) or id == row.id or not ids.has(id) or not ids[id].pole or seen.has(id):
					return false
				seen[id] = true
	return true

func _observe(bad: bool) -> void:
	if is_instance_valid(world_sync.diagnostics):
		world_sync.diagnostics.observe("power", bad, 1 if bad else 0)

func _apply_pending() -> void:
	if mp.is_host or _pending.is_empty() or not _ready_for_state() or _client_epoch != world_sync.economy.epoch:
		return
	var local := {}
	var candidates := _candidates()
	for node in candidates:
		var key: String = world_sync._bkey(BuildSnapshot.row(node))
		if local.has(key):
			_observe(true)
			return
		local[key] = node
	if local.size() != _pending.rows.size():
		_observe(true)
		return
	var resolved := {}
	for row in _pending.rows:
		var node: Variant = local.get(row.key)
		if not _live(node) or (node is PowerPole) != row.pole or _switchable(node) != row.taggable:
			_observe(true)
			return
		if _client_nodes.has(row.id) and _client_nodes[row.id].get_ref() != node:
			_observe(true)
			return
		resolved[row.id] = node
	var tags: Variant = builds.get("tags")
	if not is_instance_valid(tags):
		return
	var switches_changed: bool = _applied_revision != _pending.revision
	var wires_changed := false
	var expected_members := {}
	var expected_machines := {}
	for row in _pending.rows:
		if row.tag >= 0:
			var node: Node3D = resolved[row.id]
			expected_members[node.get_instance_id()] = row.tag
			expected_machines[node.get_instance_id()] = node
	var tags_changed: bool = tags._of != expected_members or tags._machine != expected_machines or Array(tags.names) != _pending.names or Array(tags.priorities) != _pending.priority or not tags._pending.is_empty()
	applying = true
	_client_nodes.clear()
	_client_ids.clear()
	for row in _pending.rows:
		var node: Node3D = resolved[row.id]
		_client_nodes[row.id] = weakref(node)
		_client_ids[node.get_instance_id()] = row.id
		if not row.pole:
			continue
		var links: Array[PowerPole] = []
		var cuts: Array[PowerPole] = []
		for id in row.links:
			links.append(resolved[id] as PowerPole)
		for id in row.cuts:
			cuts.append(resolved[id] as PowerPole)
		var pole := node as PowerPole
		var links_at: Array[Vector3] = []
		var cuts_at: Array[Vector3] = []
		for target in links:
			links_at.append(target.global_position)
		for target in cuts:
			cuts_at.append(target.global_position)
		if pole.links_to != links or pole.cuts_to != cuts or pole.links_at != links_at or pole.cuts_at != cuts_at:
			pole.link(links)
			pole.cuts_to.clear()
			pole.cuts_at.clear()
			for target in cuts:
				pole.remember_cut(target)
			wires_changed = true
	if tags_changed:
		tags.names = PackedStringArray(_pending.names)
		tags.priorities = PackedInt32Array(_pending.priority)
		tags._pending.clear()
		tags._of = expected_members
		tags._machine = expected_machines
		tags.changed.emit()
	if switches_changed:
		world_sync.machines_sync._send_edits()
		var switches := {}
		for row in _pending.rows:
			if row.taggable:
				switches[resolved[row.id]] = row.off
		world_sync.machines_sync.apply_power_switches(switches)
	if wires_changed:
		builds._rewire_now()
	elif (tags_changed or switches_changed) and builds.grid != null:
		builds.grid.tick()
	applying = false
	_applied_revision = _pending.revision
	_observe(false)

func _reference(node: Node) -> int:
	if not _live(node):
		return 0
	if mp.is_host:
		return int(_ids.get(node.get_instance_id(), 0))
	var id: int = _client_ids.get(node.get_instance_id(), 0)
	return id if _client_nodes.has(id) and _client_nodes[id].get_ref() == node else 0

func _request(args: Dictionary) -> int:
	if not _ready_for_state() or (not mp.is_host and (_pending.is_empty() or _applied_revision != _revision or _applied_revision == 0 or _client_epoch != world_sync.economy.epoch)):
		mp.ui.notify(mp.t("economy_wait"))
		return 0
	args["revision"] = _revision
	var seq: int = world_sync.economy.request("power", args)
	if seq != 0:
		_requests[seq] = args.duplicate(true)
	return seq

func switch_pending(node: Node3D) -> bool:
	if not mp.active():
		return false
	var id := _reference(node)
	for request in _requests.values():
		if request.get("kind") in ["line", "pole", "machine"] and request.get("node") == id:
			return true
	return false

func request_wire(from: PowerPole, to: PowerPole, joined: bool) -> int:
	if mp.is_host:
		_capture()
	var a := _reference(from)
	var b := _reference(to)
	if a == 0 or b == 0 or a == b:
		mp.ui.notify(mp.t("building_missing"))
		return 0
	return _request({"kind": "wire", "a": a, "b": b, "value": joined})

func ready_for_switch(node: Node3D) -> bool:
	if not _live(node) or not _switchable(node) or world_sync._frozen or world_sync._applying_builds:
		return false
	if not mp.active():
		return true
	if not _ready_for_state():
		return false
	return mp.is_host or (_applied_revision > 0 and _applied_revision == _revision and _client_epoch == world_sync.economy.epoch and _reference(node) > 0)

func request_machine(node: Node3D, off: bool) -> int:
	if not _live(node) or not _switchable(node):
		return 0
	if not mp.active():
		if world_sync._frozen or world_sync._applying_builds:
			return 0
		node.set_switched_off(off)
		if builds.grid != null:
			builds.grid.tick()
		return 0
	if mp.is_host:
		_capture()
	var id := _reference(node)
	if id == 0:
		mp.ui.notify(mp.t("building_missing"))
		return 0
	var ids: Array = []
	for target in _switch_targets(node):
		var target_id := _reference(target)
		if target_id == 0:
			mp.ui.notify(mp.t("economy_wait"))
			return 0
		ids.append(target_id)
	ids.sort()
	return _request({"kind": "machine", "node": id, "targets": ids, "value": off})

func request_switch(node: Node3D, off: bool, whole_line: bool) -> int:
	if mp.is_host:
		_capture()
	var id := _reference(node)
	if id == 0 or builds.grid == null:
		mp.ui.notify(mp.t("building_missing"))
		return 0
	var targets: Array = builds.grid.switches_of(node) if whole_line else builds.grid.pole_switches(node)
	var ids: Array = []
	for target in targets:
		var target_id := _reference(target)
		if target_id == 0:
			mp.ui.notify(mp.t("economy_wait"))
			return 0
		ids.append(target_id)
	ids.sort()
	return _request({"kind": "line" if whole_line else "pole", "node": id, "targets": ids, "value": off})

func request_tag(kind: String, tag: int, value: Variant, machine: Node = null) -> int:
	if mp.is_host:
		_capture()
	var args := {"kind": kind, "tag": tag, "value": value}
	if kind == "member":
		var id := _reference(machine)
		if id == 0:
			mp.ui.notify(mp.t("building_missing"))
			return 0
		args["node"] = id
	return _request(args)

func _completed(seq: int, result: Dictionary) -> void:
	if not _requests.has(seq):
		return
	_requests.erase(seq)
	completed.emit(seq, result)

func _unchanged(key: String, revision: int) -> bool:
	return int(_changed_at.get(key, 0)) <= revision

func _failed() -> Dictionary:
	return {"ok": false, "message": mp.t("power_changed")}

func execute(args: Dictionary) -> Dictionary:
	if not mp.is_host or not _ready_for_state() or not (args.get("revision") is int) or not (args.get("kind") is String):
		return _failed()
	_capture()
	var revision: int = args.revision
	if revision <= 0 or revision > _revision or _packet.is_empty() or not _valid_state(_packet):
		return _failed()
	applying = true
	var result: Dictionary
	if args.kind == "wire":
		result = _wire(args, revision)
	elif args.kind in ["line", "pole", "machine"]:
		result = _switch(args, revision)
	else:
		result = _tag(args, revision)
	applying = false
	world_sync.machines_sync._send_fields()
	publish(0, true)
	return result

func _wire(args: Dictionary, revision: int) -> Dictionary:
	if not (args.get("a") is int) or not (args.get("b") is int) or not (args.get("value") is bool):
		return _failed()
	var a: Variant = _nodes.get(args.a)
	var b: Variant = _nodes.get(args.b)
	if not _live(a) or not _live(b) or not (a is PowerPole) or not (b is PowerPole) or a == b or builds.grid == null:
		return _failed()
	var joined: bool = a.strung_to(b) or b.strung_to(a)
	if joined != args.value:
		if not _unchanged(_edge_key(args.a, args.b), revision) or not _unchanged("node:%d" % args.a, revision) or not _unchanged("node:%d" % args.b, revision):
			return _failed()
		var count: int = builds.join_poles(a, b) if args.value else builds.cut_poles(a, b)
		if count < 0:
			return _failed()
	var still_connected: bool = builds.grid.network_of(a) == builds.grid.network_of(b)
	return {"ok": true, "joined": args.value, "lines": builds.grid.network_count(), "still_connected": still_connected}

func _switch(args: Dictionary, revision: int) -> Dictionary:
	if not (args.get("node") is int) or not (args.get("value") is bool) or not (args.get("targets") is Array) or args.targets.size() > MAX_NODES:
		return _failed()
	var source: Variant = _nodes.get(args.node)
	if not _live(source) or builds.grid == null or not _unchanged("node:%d" % args.node, revision):
		return _failed()
	if (args.kind == "machine" and not _switchable(source)) or (args.kind != "machine" and not source is PowerPole):
		return _failed()
	var targets: Array = _switch_targets(source) if args.kind == "machine" else (builds.grid.switches_of(source) if args.kind == "line" else builds.grid.pole_switches(source))
	if args.kind == "machine" and not targets.has(source):
		return _failed()
	var ids: Array = []
	for target in targets:
		var id := _reference(target)
		if id == 0 or not _unchanged("node:%d" % id, revision) or (bool(target.is_switched_off()) != args.value and not _unchanged("off:%d" % id, revision)):
			return _failed()
		ids.append(id)
	ids.sort()
	if ids != args.targets:
		return _failed()
	var count: int = 0
	if args.kind == "machine":
		for target in targets:
			if bool(target.is_switched_off()) != args.value:
				count += 1
		if count > 0:
			source.set_switched_off(args.value)
			builds.grid.tick()
	else:
		count = builds.grid.switch_line(source, args.value) if args.kind == "line" else builds.grid.switch_pole(source, args.value)
	return {"ok": true, "switched": count, "off": args.value}

func _tag(args: Dictionary, revision: int) -> Dictionary:
	var tags: Variant = builds.get("tags")
	if not is_instance_valid(tags) or not tags.enabled() or not (args.get("tag") is int):
		return _failed()
	var tag: int = args.tag
	var kind: String = args.kind
	if kind not in ["member", "switch_all"] and (tag < 0 or tag >= 8):
		return _failed()
	match kind:
		"rename":
			if not (args.get("value") is String) or args.value.length() > 4096:
				return _failed()
			var clean: String = args.value.strip_edges().left(16)
			if clean != tags.names[tag] and not _unchanged("name:%d" % tag, revision):
				return _failed()
			tags.rename(tag, clean)
		"priority":
			if not (args.get("value") is int):
				return _failed()
			var level: int = clampi(args.value, 0, 2)
			if level != tags.priorities[tag] and not _unchanged("priority:%d" % tag, revision):
				return _failed()
			tags.set_priority(tag, level)
		"member":
			if not (args.get("node") is int):
				return _failed()
			var node: Variant = _nodes.get(args.node)
			if not _live(node) or not PowerTags.taggable(node):
				return _failed()
			if tag < 0 or tag >= 8:
				tag = -1
			if tag != tags.tag_of(node) and (not _unchanged("member:%d" % args.node, revision) or not _unchanged("node:%d" % args.node, revision)):
				return _failed()
			tags.set_tag(node, tag)
		"switch", "switch_all":
			if not (args.get("value") is bool):
				return _failed()
			var targets: Array = []
			for group in 8:
				if kind == "switch" and group != tag:
					continue
				if not _unchanged("group:%d" % group, revision):
					return _failed()
				targets.append_array(tags.members(group))
			for node in targets:
				var id := _reference(node)
				if id == 0 or (bool(node.is_switched_off()) != args.value and not _unchanged("off:%d" % id, revision)):
					return _failed()
			if kind == "switch":
				tags.switch(tag, args.value)
			else:
				tags.switch_all(args.value)
		_:
			return _failed()
	return {"ok": true}
