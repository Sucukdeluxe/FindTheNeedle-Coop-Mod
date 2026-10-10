extends Node

# Belt contents.
#
# The host decides what is riding on the belts. A few times a second it sends
# the whole ride list, compressed; clients drop what they have and board the
# list they were given. Their own belts keep turning in between, so the items
# move smoothly and the snapshot only corrects the small drift.
#
# Machines that eat from a belt are switched off on clients, or both sides
# would turn the same hay into two bales.

const TICK := 0.25
const FULL_TICK := 2.0  # the list goes out at least this often, changed or not
const MAX_RAW := 8 << 20

var mp: Node
var world: Node
var _t := 0.0
var _since := 0.0
var _last_hash := 0
var _carry: Node
var _carry_script: Script
var _pick_pending := false
var _pick_stack := false
var _outlet_repair_pending := false
var _outlet_repair_at := -100000
var _cleanup_scripts := {}


func start(mp_node: Node, world_node: Node) -> void:
	mp = mp_node
	world = world_node
	get_tree().node_added.connect(_protect_belt_cleanup)
	for path in BeltPath._live:
		_protect_belt_cleanup(path)
	var player: Variant = world.get("player")
	if is_instance_valid(player):
		_carry = player.get("carry")
	if is_instance_valid(_carry):
		_carry_script = _carry.get_script()
		_replace_carry_script(load(mp.base_dir + "/mp_carry.gd"))
		_carry.set("mp_belts", self)
	_repair_sell_outlet_later()


# Hand the belt ends back, in case the world outlives the session.
func shutdown() -> void:
	if get_tree().node_added.is_connected(_protect_belt_cleanup):
		get_tree().node_added.disconnect(_protect_belt_cleanup)
	for path in BeltPath._live:
		if not is_instance_valid(path):
			continue
		for original in _cleanup_scripts:
			if path.get_script() == _cleanup_scripts[original]:
				_replace_belt_script(path, original)
				break
	_cleanup_scripts.clear()
	if is_instance_valid(_carry) and _carry_script != null:
		_replace_carry_script(_carry_script)
	for item in BeltPath._live:
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		if not item._records_held:
			continue
		item._records_held = false
		item._eats = Callable()
		item.run.hold_for = Callable()
		item._sync_run_links()


func _process(delta: float) -> void:
	if mp == null or not mp.is_host or not mp.active():
		return
	if multiplayer.multiplayer_peer == null:
		return
	if mp.players.size() < 2:
		return
	_t += delta
	_since += delta
	if _t < TICK:
		return
	_t = 0.0
	send_all()


# Everyone, or one guest that just came in. Unchanged lists are skipped: an
# idle yard used to send the whole ride list four times a second.
func send_all(pid: int = 0) -> void:
	var entries: Array = []
	for path in BeltPath._live:
		if not is_instance_valid(path) or not path.is_inside_tree() or path.run.count() == 0:
			continue
		var ends: PackedVector3Array = path.save_ends()
		if ends.size() < 2:
			continue
		var rows: Array = []
		for i in range(path.run.first(), path.run.first() + path.run.count()):
			var row: Dictionary = path.run.record(i)
			var state: Dictionary = row.get("state") if row.get("state") is Dictionary else {}
			row["state"] = state.duplicate(true)
			row["state"]["_mp_belt_seq"] = int(row["seq"])
			rows.append(row)
		entries.append({"a": ends[0], "b": ends[1], "records": rows})
	var raw := var_to_bytes(entries)
	if pid == 0:
		var h := hash(raw)
		if h == _last_hash and _since < FULL_TICK:
			return
		_last_hash = h
		_since = 0.0
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if pid > 0:
		mp._rx_belts.rpc_id(pid, packed, raw.size())
	else:
		mp._rx_belts.rpc(packed, raw.size())


func on_belts(packed: PackedByteArray, raw_size: int) -> void:
	if raw_size <= 0 or raw_size > MAX_RAW:
		return
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	var entries: Variant = bytes_to_var(raw)
	if not (entries is Array):
		return
	mp.trace.note("belts begin: %d paths" % (entries as Array).size())
	for item in BeltPath._live:
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		item.run.clear()
		# A belt that reaches its end turns the ride into a real item. The host
		# does that and sends us the item, so hold our own end shut: the same
		# switch a machine sitting at the end of a belt uses.
		if not item._records_held:
			item.hold_records(Callable())
	# no PropManager: a ride we cannot place is dropped instead of becoming a
	# loose item that only this player would have
	var got: Dictionary = BeltPath.belts_from_array(entries, null)
	_repair_sell_outlet_later()
	mp.trace.note("belts end")
	if is_instance_valid(mp.world_sync) and "diagnostics" in mp.world_sync and is_instance_valid(mp.world_sync.diagnostics):
		mp.world_sync.diagnostics.check_belts(entries)
	if OS.get_environment("MP_DEBUG_PROPS") != "":
		var rows := 0
		for e in entries:
			rows += (e.get("records", []) as Array).size()
		print("[MPBELTS] %d paths, %d rows -> %s" % [entries.size(), rows, got])


func _repair_sell_outlet_later() -> void:
	if _outlet_repair_pending or Time.get_ticks_msec() < _outlet_repair_at:
		return
	_outlet_repair_pending = true
	_outlet_repair_at = Time.get_ticks_msec() + 500
	call_deferred("_repair_sell_outlet")


func _repair_sell_outlet() -> void:
	_outlet_repair_pending = false
	if not is_instance_valid(world):
		return
	var manager: Variant = world.get("builds")
	if is_instance_valid(manager):
		if manager.has_method("rebuild_junctions"):
			manager.rebuild_junctions()
		if manager.has_method("rebuild_water_joints"):
			manager.rebuild_water_joints()
		if manager.has_method("fit_posts_to_decks"):
			manager.fit_posts_to_decks()
		if manager.has_method("share_joints"):
			manager.share_joints()
	var stand: Variant = world.get("stand")
	if not is_instance_valid(stand) or not stand.has_method("mouth_centre"):
		return
	var mouth: Vector3 = stand.mouth_centre()
	var repaired := 0
	for path in BeltPath._live:
		if not is_instance_valid(path) or not path.is_inside_tree():
			continue
		var ends: PackedVector3Array = path.save_ends()
		if ends.size() < 2:
			continue
		var near := minf(ends[0].distance_squared_to(mouth), ends[1].distance_squared_to(mouth))
		if near > 4.0:
			continue
		if not bool(path.get("stand_belt")):
			path.set("stand_belt", true)
			repaired += 1
		if path.has_method("set_end_closed") and bool(path.get("end_closed")):
			path.set_end_closed(false)
		if path.has_method("_sync_end_shut"):
			path._sync_end_shut()
	if repaired > 0 and is_instance_valid(mp) and is_instance_valid(mp.trace):
		mp.trace.note("sell outlet repaired: %d path(s)" % repaired)


func _replace_carry_script(script: Script) -> void:
	var values := {}
	for property in _carry.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = _carry.get(property.name)
	_carry.set_script(script)
	for key in values:
		if key in _carry:
			_carry.set(key, values[key])


func request_pick(record: Dictionary, onto_stack: bool) -> bool:
	if _pick_pending:
		return true
	var state: Variant = record.get("state")
	if not (state is Dictionary) or not state.has("_mp_belt_seq"):
		return false
	_pick_pending = true
	_pick_stack = onto_stack
	mp._rx_belt_pick.rpc_id(1, int(state["_mp_belt_seq"]))
	return true


func on_pick(sender: int, seq: int) -> void:
	for path in BeltPath._live.duplicate():
		if not is_instance_valid(path) or not path.is_inside_tree():
			continue
		for i in range(path.run.first(), path.run.first() + path.run.count()):
			if path.run.seq_of(i) != seq:
				continue
			var item: Variant = path.materialize_record(i)
			if not is_instance_valid(item):
				mp._rx_belt_pick_result.rpc_id(sender, sender, 0)
				return
			var id := int(item.get_meta("mp_id", 0))
			if id == 0:
				mp._rx_belt_pick_result.rpc_id(sender, sender, 0)
				return
			mp.world_sync.props_sync._assign_owner(id, sender, true)
			mp._rx_belt_pick_result.rpc(sender, id)
			send_all()
			return
	mp._rx_belt_pick_result.rpc_id(sender, sender, 0)


func on_pick_result(owner: int, id: int) -> void:
	var sync: Node = mp.world_sync.props_sync
	if owner != multiplayer.get_unique_id():
		return
	_pick_pending = false
	var item: Variant = sync._by_id.get(id)
	if not is_instance_valid(item) or not is_instance_valid(_carry):
		return
	if _pick_stack and _carry.can_stack(item):
		_carry.stack_on(item)
	elif not _carry.is_carrying():
		_carry.take(item)


func _protect_belt_cleanup(node: Node) -> void:
	if not (node is BeltPath):
		return
	var original: Script = node.get_script()
	if original == null or not original.resource_path.begins_with("res://scripts/"):
		return
	if not _cleanup_scripts.has(original):
		var patch := GDScript.new()
		patch.source_code = "extends %s\nfunc _shed_over_cap() -> void:\n\tvar session = get_node_or_null(\"/root/MPMod\")\n\tif is_instance_valid(session) and session.active():\n\t\tif not session.is_host or not Cfg.auto_clean:\n\t\t\treturn\n\tsuper._shed_over_cap()\n" % JSON.stringify(original.resource_path)
		if patch.reload() != OK:
			return
		_cleanup_scripts[original] = patch
	_replace_belt_script(node, _cleanup_scripts[original])


func _replace_belt_script(node: Node, script: Script) -> void:
	var values := {}
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = node.get(property.name)
	node.set_script(script)
	for key in values:
		node.set(key, values[key])
