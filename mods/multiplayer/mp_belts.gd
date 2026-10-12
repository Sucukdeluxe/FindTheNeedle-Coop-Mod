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
const Snapshot = preload("res://mods/multiplayer/mp_belt_snapshot.gd")
const LiftCargo = preload("res://mods/multiplayer/mp_lift_cargo.gd")

var mp: Node
var world: Node
var _t := 0.0
var _since := 0.0
var _last_hash := 0
var _carry: Node
var _carry_script: Script
var _pick_pending := false
var _pick_stack := false
var _cleanup_scripts := {}
var _mirror_holds := {}
var _pending_snapshot: Variant = null
var _stopped := false
var _lift_cargo := LiftCargo.new()


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
	_release_mirror_holds()
	_lift_cargo.clear()
	_pending_snapshot = null
	_stopped = true
	set_process(false)


func _process(delta: float) -> void:
	_flush_pending_belts()
	_lift_cargo.step(delta)
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
	var raw := var_to_bytes({"paths": entries, "lifts": LiftCargo.capture(mp.world_sync)})
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
	if _stopped or not is_instance_valid(mp) or not mp.active() or mp.is_host:
		return
	if raw_size <= 0 or raw_size > MAX_RAW:
		return
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return
	var payload: Variant = bytes_to_var(raw)
	var entries: Variant = payload.get("paths") if payload is Dictionary else payload
	var lifts: Variant = payload.get("lifts", []) if payload is Dictionary else []
	if not (entries is Array) or not Snapshot.valid(entries) or not LiftCargo.valid(lifts):
		return
	_pending_snapshot = {"paths": entries, "lifts": lifts}
	_flush_pending_belts()


func _flush_pending_belts() -> void:
	if _pending_snapshot == null or _stopped:
		return
	if not is_instance_valid(mp) or not mp.active() or mp.is_host:
		_pending_snapshot = null
		return
	var sync: Node = mp.world_sync
	if not is_instance_valid(sync) or sync.world != world:
		_pending_snapshot = null
		return
	if mp.phase != mp.Phase.IN_WORLD or sync._frozen or sync._applying_builds or sync._builds_dirty:
		return
	var payload: Dictionary = _pending_snapshot
	_pending_snapshot = null
	_apply_belts(payload.paths)
	_lift_cargo.apply(sync, payload.lifts)


func _apply_belts(entries: Array) -> void:
	mp.trace.note("belts begin: %d paths" % entries.size())
	for id in _mirror_holds.keys():
		if not is_instance_valid(_mirror_holds[id]["path"].get_ref()):
			_mirror_holds.erase(id)
	for item in BeltPath._live:
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		item.run.clear()
		_hold_mirrored_path(item)
	var got: Dictionary = BeltPath.belts_from_array(entries, null)
	mp.trace.note("belts end: %d restored, %d unmatched" % [int(got.get("boarded", 0)), int(got.get("lost", 0))])
	if is_instance_valid(mp.world_sync) and is_instance_valid(mp.world_sync.diagnostics):
		mp.world_sync.diagnostics.check_belts(entries)
	if OS.get_environment("MP_DEBUG_PROPS") != "":
		var rows := 0
		for entry in entries:
			rows += entry["records"].size()
		print("[MPBELTS] %d paths, %d rows -> %s" % [entries.size(), rows, got])


func _hold_mirrored_path(item: Node) -> void:
	if item._records_held:
		return
	var saved := {"path": weakref(item), "eats": item._eats, "hold_for": item.run.hold_for}
	item.hold_records(Callable())
	saved["applied_hold"] = item.run.hold_for
	_mirror_holds[item.get_instance_id()] = saved


func _release_mirror_holds() -> void:
	for saved in _mirror_holds.values():
		var item: Variant = saved["path"].get_ref()
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		if not item._records_held or item._eats.is_valid() or item.run.hold_for != saved["applied_hold"]:
			continue
		item._records_held = false
		item._eats = saved["eats"]
		item.run.hold_for = saved["hold_for"]
		item._sync_run_links()
	_mirror_holds.clear()


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
		patch.source_code = "extends %s\nfunc _shed_over_cap() -> void:\n\tvar session = get_node_or_null(\"/root/MPMod\")\n\tif is_instance_valid(session) and session.active():\n\t\tif not session.is_host or not Cfg.auto_clean:\n\t\t\treturn\n\tsuper._shed_over_cap()\nfunc _spill_records() -> void:\n\tvar session = get_node_or_null(\"/root/MPMod\")\n\tif is_instance_valid(session) and session.active() and not session.is_host:\n\t\trun.clear()\n\t\treturn\n\tsuper._spill_records()\nfunc _keeps_at_seam(r: Rider) -> bool:\n\tvar session = get_node_or_null(\"/root/MPMod\")\n\tif is_instance_valid(session) and session.active() and is_instance_valid(downstream) and downstream.is_inside_tree() and not downstream.is_queued_for_deletion():\n\t\tvar body = r.body\n\t\tif is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and is_same(body.get_meta(LiveStrandManager.META_RIDER, null), self):\n\t\t\treturn true\n\treturn super._keeps_at_seam(r)\n" % JSON.stringify(original.resource_path)
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
