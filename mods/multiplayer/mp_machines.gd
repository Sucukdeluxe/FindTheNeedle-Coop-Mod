extends Node

const ArmState = preload("res://mods/multiplayer/mp_arm_state.gd")
const ArmVisual = preload("res://mods/multiplayer/mp_arm_visual.gd")

var _arm_visual := ArmVisual.new()

const DroneState = preload("res://mods/multiplayer/mp_drone_state.gd")
const MachinePacket = preload("res://mods/multiplayer/mp_machine_packet.gd")
const DiagnosticState = preload("res://mods/multiplayer/mp_diagnostic_state.gd")

# Machines.
#
# A machine runs on the host only, so the same hay cannot become two bales.
# That used to leave it standing still on everyone else's screen. The host now
# sends three things for each one:
#
#   * where its moving parts are, whatever drives them (the piston rake scrubs
#     an AnimationPlayer, the robotic arm drives its joints from code)
#   * which of its parts are visible and which particles are running, so smoke,
#     flames and lamps show up
#   * the handful of numbers that other systems read: fuel and output for the
#     generator, and every setting a panel can change
#
# Only what changed is sent, and only for machines somebody is standing near.

const TICK := 0.1
const FIELD_TICK := 0.5
const EDIT_TICK := 0.2    # how often a guest looks for a setting it changed
const FULL_TICK := 2.0    # how often every part goes out again, packets get lost
const RANGE := 32.0        # metres from a player before a machine is worth sending
const MOVE_EPS := 0.0015
const ANG_EPS := 0.004
# a machine model carries a lot of nodes and the smoke and firebox sit well
# down the list, so do not cut the walk short
const MAX_PARTS := 120
const SMOOTH := 22.0
const MAX_RAW := 4 << 20

# What each kind of machine keeps that is worth copying: the numbers other
# parts of the game read (power, stock) and everything a settings panel can
# change. Read from the machine, written back through its setter when it has
# one.
const FIELDS := {
	"generators": ["fuel", "switched_off", "made_kw"],
	"silos": ["switched_off", "discharge_rate", "resume_rate", "stored", "queued"],
	"splitters": ["forced_side", "priority_side", "next_side", "filters", "entry", "manual", "closed_lane", "fed", "stem_wait", "mp_t_revision"],
	"joiners": ["out_lane", "manual", "next_side", "mp_t_revision"],
	"tube_launchers": ["switched_off", "aim", "power", "stored"],
	"piston_rakes": ["switched_off", "throw_distance"],
	"hay_drones": ["switched_off", "mode", "takes", "mp_zone", "mp_drop", "mp_drone_status"],
	"pelletizers": ["switched_off", "throw_distance", "head_yaw", "stored"],
	"robotic_arms": ["switched_off", "accept_mask", "tier_index", "paid_cost", "legacy_refit", "pick_order", "mp_links", "mp_arm_status"],
	"scanners": ["switched_off", "tier_index", "stored"],
	"compressors": ["switched_off", "stored"],
	"pulpers": ["switched_off", "stored", "mp_taps"],
	"papers": ["switched_off", "queued"],
	"briquette_presses": ["switched_off", "stored_strands", "stored_bricks"],
	"wrappers": ["switched_off", "queued"],
	"boreholes": ["switched_off"],
	"dump_hatches": ["stored"],
	"needle_radars": ["cooldown"],
	"work_lamps": ["brightness", "_off"],
}

# Machines that keep running on clients but whose settings still have to match.
const SETTINGS_ONLY := ["work_lamps"]

# The areas a machine watches for something to eat. Named rather than walked,
# because a machine's other areas are the scanner's beam and the stairs' climb
# zone, which have nothing to do with taking hay in.
const MOUTHS := ["_intake", "_hopper", "_mouth", "_mouth_area", "_wad_mouth",
	"_brick_mouth", "_catch", "_payout_area", "_skirt_area"]
const MOUTH_TICK := 0.25

# What a panel lets a player change, as opposed to what a machine works out for
# itself. Only these travel back from a guest: fuel, stock, output and the rest
# are the host's to count, and taking a guest's word for them would let the
# same hay pay twice.
const SETTINGS := {
	"generators": ["switched_off"],
	"silos": ["switched_off", "discharge_rate", "resume_rate"],
	"joiners": ["out_lane", "manual"],
	"splitters": ["forced_side", "priority_side", "filters", "entry", "manual", "closed_lane"],
	"tube_launchers": ["switched_off", "aim", "power"],
	"piston_rakes": ["switched_off", "throw_distance"],
	"hay_drones": ["switched_off", "mode", "takes", "mp_zone", "mp_drop"],
	"pelletizers": ["switched_off", "throw_distance", "head_yaw"],
	"robotic_arms": ["switched_off", "accept_mask", "pick_order", "mp_links"],
	"scanners": ["switched_off", "tier_index"],
	"compressors": ["switched_off"],
	"pulpers": ["switched_off"],
	"papers": ["switched_off"],
	"briquette_presses": ["switched_off"],
	"wrappers": ["switched_off"],
	"boreholes": ["switched_off"],
	"work_lamps": ["brightness", "_off"],
}

const FIELD_GROUPS := [["entry", "out_lane", "closed_lane", "forced_side", "priority_side", "next_side", "manual", "stem_wait", "mp_t_revision"],
	["discharge_rate", "resume_rate"]]

var mp: Node
var world: Node
var builds: Node

var _part_shapes := {}
var _parts := {}    # key -> Array[Node3D] in walk order
var _ids := {}      # key -> PackedInt32Array, each part named by its path
var _slot := {}     # key -> {part id: index into _parts}
var _sent := {}     # key -> {part id: last transform broadcast}
var _full := false  # this tick, send every part again
var _refresh_t := 0.0
var _log := OS.get_environment("MP_DEBUG_PROPS") != ""
var _fx := {}       # key -> per part: its light and its shader values
var _fx_sent := {}  # key -> {"part:slot": last value sent}
var _flags := {}    # key -> PackedByteArray last broadcast
var _vals := {}     # key -> Dictionary of fields last broadcast
var _goal := {}     # key -> {part index: Transform3D}
var _nodes := {}    # key -> machine node
var _group := {}    # key -> which build array it came from
var _scan_t := 0.0
var _t := 0.0
var _field_t := 0.0
var _edit_t := 0.0
var _mouth_t := 0.0
var _pending_settings := {}
var _queued_settings := {}
var _applying_fields := false
var _processor_hooks := {}
var _junction_hooks := {}
var _processors_enabled := false
var _theirs := {}   # guest: key -> the settings as the host last stated them
var _alias := {}    # a key from the host -> our key for the same machine
var _rescan_at := -100000  # msec, last rescan forced by a key we did not know
# a key naming a machine we do not have (yet): skip it until then instead of
# walking every machine again for every packet that mentions it
const UNKNOWN_KEY_WAIT := 1000
const KEY_SLACK := 0.25   # metres: the same machine, placed on both sides
const BIG_PACKET := 1000  # compressed bytes; past this a packet goes reliable


func start(mp_node: Node, world_node: Node) -> void:
	mp = mp_node
	world = world_node
	builds = world.get("builds")
	_processors_enabled = true
	set_process(true)
	get_tree().node_added.connect(_processor_added)
	builds.changed.connect(_protect_processors)
	_rescan()


func shutdown() -> void:
	_arm_visual.clear()
	_processors_enabled = false
	set_process(false)
	if is_instance_valid(builds) and builds.changed.is_connected(_protect_processors):
		builds.changed.disconnect(_protect_processors)
	if is_inside_tree() and get_tree().node_added.is_connected(_processor_added):
		get_tree().node_added.disconnect(_processor_added)
	for saved in _processor_hooks.values():
		var node: Variant = saved["node"].get_ref()
		if is_instance_valid(node) and node.get_script() == saved["replacement"]:
			_replace_processor_script(node, saved["original"])
			if node is HayLift or node is HayStairs:
				node._follow_tech()
			_refresh_processor_belt(node)
	_processor_hooks.clear()
	for saved in _junction_hooks.values():
		var helper: Variant = saved.helper.get_ref()
		if is_instance_valid(helper) and helper.get_script() == saved.replacement:
			_replace_junction_script(helper, saved.original)
	_junction_hooks.clear()
	_pending_settings.clear()
	_queued_settings.clear()
	_parts.clear()
	_part_shapes.clear()
	_fx.clear()
	_ids.clear()
	_slot.clear()
	_sent.clear()
	_flags.clear()
	_vals.clear()
	_goal.clear()
	_nodes.clear()
	# walk the models again: the game adds and drops nodes as it runs
	_parts.clear()
	_fx.clear()
	_ids.clear()
	_slot.clear()
	_group.clear()


# ------------------------------------------------------------------ the parts

# Every machine worth sending, under a key both sides work out the same way:
# the array it lives in and where it stands.
func _rescan() -> void:
	if not _processors_enabled or not is_instance_valid(mp) or not is_instance_valid(builds):
		return
	var ws: Node = mp.world_sync
	if not is_instance_valid(ws) or ws.get("world") != world:
		return
	for id in _processor_hooks.keys():
		if not is_instance_valid(_processor_hooks[id]["node"].get_ref()):
			_processor_hooks.erase(id)
	for id in _junction_hooks.keys():
		if not is_instance_valid(_junction_hooks[id].helper.get_ref()):
			_junction_hooks.erase(id)
	for key in _pending_settings.keys():
		if Time.get_ticks_msec() - int(_pending_settings[key].time) > 10000:
			_pending_settings.erase(key)
	var groups: Array = ws.get_script().get_script_constant_map().get("CLIENT_FROZEN", [])
	_nodes.clear()
	# walk the models again: the game adds and drops nodes as it runs
	_fx.clear()
	_group.clear()
	for group in groups + SETTINGS_ONLY:
		var arr: Variant = builds.get(group)
		if not (arr is Array):
			continue
		for n in arr:
			if is_instance_valid(n) and n is Node3D and n.is_inside_tree() and not n.is_queued_for_deletion():
				_protect_processor(n)
				var key := _key(String(group), n)
				_nodes[key] = n
				_group[key] = String(group)
	for key in _parts.keys():
		var node: Variant = _nodes.get(key)
		var current: Array = []
		if is_instance_valid(node):
			_walk(node, current)
		var same: bool = is_instance_valid(node) and _parts[key] == current \
			and _part_shapes.get(key, []) == DiagnosticState.machine_shape(node, current)
		if not same:
			_parts.erase(key)
			_ids.erase(key)
			_slot.erase(key)
			_part_shapes.erase(key)
	# forget machines that are gone (this used to run over _parts after it was
	# cleared, so it never did anything and every demolished machine's state
	# stayed behind for good)
	for d in [_sent, _flags, _vals, _goal, _fx_sent, _theirs]:
		for key in (d as Dictionary).keys():
			if not _nodes.has(key):
				(d as Dictionary).erase(key)
	for key in _alias.keys():
		if not _nodes.has(_alias[key]):
			_alias.erase(key)

	_arm_visual.prune(_nodes)


# Our key for a machine the host named. Both sides place a machine from the
# same save data, but its position can come out a hair different, and the key
# is built from it; so an exact miss falls back to the nearest machine of the
# same kind. A key that matches nothing waits a second before the next rescan.
func _local_key(key: String) -> String:
	if _nodes.has(key):
		return key
	var known: String = _alias.get(key, "")
	if known != "" and _nodes.has(known):
		return known
	var now := Time.get_ticks_msec()
	if now - _rescan_at >= UNKNOWN_KEY_WAIT:
		_rescan_at = now
		_rescan()
		if _nodes.has(key):
			return key
	return ""


func _key(group: String, n: Node3D) -> String:
	var p := n.global_position
	return "%s|%.4f,%.4f,%.4f|%.5f" % [group, p.x, p.y, p.z, wrapf(n.rotation.y, -PI, PI)]


# The model's own nodes, in tree order. Both sides build the machine from the
# same code, so the same walk gives the same list and an index is enough.
func _parts_of(key: String) -> Array:
	if _parts.has(key):
		return _parts[key]
	var out: Array = []
	var ids := PackedInt32Array()
	var slot := {}
	var n: Variant = _nodes.get(key)
	if n != null and is_instance_valid(n):
		# from the machine itself, not from its model: the fire, the lamps and
		# the smoke column are made in code and hang off the machine, so a walk
		# that started at the model never saw them
		var base: Node = n as Node
		_walk(base, out)
		# A part is named by where it hangs, not by its place in the list: the
		# game adds and removes nodes of its own (alert markers, dust, range
		# rings), and a machine with one more of those would otherwise hand
		# every pose to the wrong part and come out crooked.
		for i in out.size():
			# 31 bits: these ids travel in a signed 32-bit array, and a hash that
			# spills over the sign bit would arrive as a different number and
			# match nothing. It cost half the parts of every machine.
			var id := int(_part_path(base, out[i]).hash()) & 0x7fffffff
			ids.append(id)
			slot[id] = i
	_parts[key] = out
	_part_shapes[key] = DiagnosticState.machine_shape(n, out) if is_instance_valid(n) else []
	_ids[key] = ids
	_slot[key] = slot
	return out


func _ids_of(key: String) -> PackedInt32Array:
	_parts_of(key)
	return _ids.get(key, PackedInt32Array())


func _slot_of(key: String) -> Dictionary:
	_parts_of(key)
	return _slot.get(key, {})


func _walk(n: Node, out: Array) -> void:
	for child in n.get_children():
		if out.size() >= MAX_PARTS:
			return
		if child is Node3D and not child.is_queued_for_deletion() and not _is_transport_part(child):
			out.append(child)
			_walk(child, out)


# ------------------------------------------------------------------ ticks

func _process(delta: float) -> void:
	if not _processors_enabled:
		return
	_ease(delta)
	if mp == null or not mp.active() or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not mp.is_host:
		# a guest works the panels on its own copy, which the machine itself
		# ignores, so watch for what the player changed and hand it to the host
		_scan_t += delta
		if _scan_t >= 2.0:
			_scan_t = 0.0
			_rescan()
		_edit_t += delta
		if _edit_t >= EDIT_TICK:
			_edit_t = 0.0
			_send_edits()
		return
	if mp.players.size() < 2:
		return
	_scan_t += delta
	if _scan_t >= 2.0:
		_scan_t = 0.0
		_rescan()
	_t += delta
	if _t >= TICK:
		_t = 0.0
		_refresh_t += TICK
		_full = _refresh_t >= FULL_TICK
		if _full:
			_refresh_t = 0.0
			_vals.clear()
		_send_poses()
	_field_t += delta
	if _field_t >= FIELD_TICK:
		_field_t = 0.0
		_send_fields()
	_mouth_t += delta
	if _mouth_t >= MOUTH_TICK:
		_mouth_t = 0.0
		_feed_mouths()


func _watchers() -> Array:
	var out: Array = []
	var ws: Node = mp.world_sync
	if ws == null or not is_instance_valid(ws):
		return out
	for id in ws.avatars:
		var a: Variant = ws.avatars[id]
		if a != null and is_instance_valid(a) and (a as Node3D).is_inside_tree():
			out.append((a as Node3D).global_position)
	return out


func _near(at: Vector3, watchers: Array) -> bool:
	for w in watchers:
		if at.distance_squared_to(w) < RANGE * RANGE:
			return true
	return false


func _send_poses() -> void:
	var watchers := _watchers()
	if watchers.is_empty():
		return
	var batch := {}
	for key in _nodes:
		if SETTINGS_ONLY.has(_group.get(key, "")):
			continue
		var n: Variant = _nodes[key]
		if n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			continue
		if not _near((n as Node3D).global_position, watchers):
			continue
		var parts := _parts_of(key)
		if parts.is_empty():
			continue
		# Every part now and then, not only the ones that just moved: poses go
		# out on an unreliable channel, and a part that moves once and stops
		# would stay wrong on the other screen for good if that packet was
		# lost. It also puts right anything that started out differently.
		var last: Dictionary = _sent.get(key, {})
		if _full:
			last = {}
		var part_ids := _ids_of(key)
		var flags := PackedByteArray()
		flags.resize(parts.size())
		var moved := PackedInt32Array()
		var rows := PackedFloat32Array()
		for i in parts.size():
			var part: Variant = parts[i]
			if not _live_part(key, part):
				continue
			var node := part as Node3D
			flags[i] = _flags_of(node)
			var xf: Transform3D = node.transform
			var was: Variant = last.get(part_ids[i])
			if was != null and _same(was, xf):
				continue
			last[part_ids[i]] = xf
			moved.append(part_ids[i])
			# the whole basis, not a rotation and a scale: some parts are
			# skewed and rebuilding them from a quaternion left them crooked
			rows.append_array(PackedFloat32Array([
				xf.origin.x, xf.origin.y, xf.origin.z,
				xf.basis.x.x, xf.basis.x.y, xf.basis.x.z,
				xf.basis.y.x, xf.basis.y.y, xf.basis.y.z,
				xf.basis.z.x, xf.basis.z.y, xf.basis.z.z]))
		_sent[key] = last
		var entry := {}
		if n is RoboticArm:
			var visual := _arm_visual.capture(key, n, _full)
			if not visual.is_empty():
				entry["a"] = visual
		if moved.size() > 0:
			entry["i"] = moved
			entry["t"] = rows
		if _full or _flags.get(key, PackedByteArray()) != flags:
			_flags[key] = flags
			var fl := PackedInt32Array()
			for i in parts.size():
				fl.append(part_ids[i])
				fl.append(flags[i])
			entry["f"] = fl
		var fx_ids := PackedInt32Array()
		var fx_vals := PackedFloat32Array()
		_read_fx(key, fx_ids, fx_vals)
		if fx_vals.size() > 0:
			entry["xi"] = fx_ids
			entry["xv"] = fx_vals
		if not entry.is_empty():
			batch[key] = entry
	if batch.is_empty():
		return
	if _log and _full:
		for key in batch:
			var e: Dictionary = batch[key]
			print("[MPMACH] send %s moved=%d flags=%d fx=%d" % [key,
				(e.get("i", PackedInt32Array()) as PackedInt32Array).size(),
				(e.get("f", PackedInt32Array()) as PackedInt32Array).size() / 2,
				(e.get("xv", PackedFloat32Array()) as PackedFloat32Array).size()])
	if mp.over_steam:
		_send_small(batch)
		return
	var raw := var_to_bytes(batch)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	# One machine's full pose is already bigger than a packet. Sent unreliably,
	# losing any fragment lost the whole batch, so big batches and the
	# periodic full refresh go on the reliable channel instead.
	if _full or packed.size() > BIG_PACKET or _has_arm_geometry(batch):
		mp._rx_machines_big.rpc(packed, raw.size())
	else:
		mp._rx_machines.rpc(packed, raw.size())


# Over Steam, in small pieces. Every guest crash over Steam came right after a
# big machine update arrived (up to 9 KB in one message), and over a direct
# connection it has never happened, so over Steam no message gets that big:
# each machine's parts, flags and effects are split into pieces a guest can
# apply one by one, and packed into messages of about a kilobyte.
const PIECE_PARTS := 10
const PIECE_PAIRS := 40
const SMALL_PACKET := 900

func _send_small(batch: Dictionary) -> void:
	var pieces: Array = []  # [key, sub entry]
	for key in batch:
		var e: Dictionary = batch[key]
		if e.has("a"):
			for visual in ArmVisual.pieces(e.a):
				pieces.append([key, {"a": visual}])
		if e.has("f"):
			var f: PackedInt32Array = e["f"]
			for a in range(0, f.size(), PIECE_PAIRS * 2):
				pieces.append([key, {"f": f.slice(a, a + PIECE_PAIRS * 2)}])
		if e.has("xi") and e.has("xv"):
			var xi: PackedInt32Array = e["xi"]
			var xv: PackedFloat32Array = e["xv"]
			for a in range(0, xv.size(), PIECE_PAIRS):
				pieces.append([key, {"xi": xi.slice(a * 2, (a + PIECE_PAIRS) * 2),
					"xv": xv.slice(a, a + PIECE_PAIRS)}])
		if e.has("i") and e.has("t"):
			var ids: PackedInt32Array = e["i"]
			var rows: PackedFloat32Array = e["t"]
			for a in range(0, ids.size(), PIECE_PARTS):
				pieces.append([key, {"i": ids.slice(a, a + PIECE_PARTS),
					"t": rows.slice(a * 12, (a + PIECE_PARTS) * 12)}])
	var out := {}
	for p in pieces:
		var key: String = p[0]
		if out.has(key):
			_send_one(out)
			out = {}
		out[key] = p[1]
		if var_to_bytes(out).size() > SMALL_PACKET * 3:
			# ~3:1 compression on these; keep what is sent near a kilobyte
			_send_one(out)
			out = {}
	if not out.is_empty():
		_send_one(out)


func _send_one(batch: Dictionary) -> void:
	var raw := var_to_bytes(batch)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	# the periodic full refresh has to arrive; the moves in between may drop
	if _full or _has_arm_geometry(batch):
		mp._rx_machines_big.rpc(packed, raw.size())
	else:
		mp._rx_machines.rpc(packed, raw.size())


func _has_arm_geometry(batch: Dictionary) -> bool:
	for entry in batch.values():
		if entry.has("a") and entry.a.has("d"):
			return true
	return false


# bit 0: the part is drawn. bit 1: its particles are running.
func _flags_of(n: Node3D) -> int:
	var f := 1 if n.visible else 0
	if n is GPUParticles3D:
		f |= 2 if (n as GPUParticles3D).emitting else 0
	elif n is CPUParticles3D:
		f |= 2 if (n as CPUParticles3D).emitting else 0
	return f


func _same(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_squared_to(b.origin) > MOVE_EPS * MOVE_EPS:
		return false
	return a.basis.x.distance_squared_to(b.basis.x) < ANG_EPS * ANG_EPS \
		and a.basis.y.distance_squared_to(b.basis.y) < ANG_EPS * ANG_EPS \
		and a.basis.z.distance_squared_to(b.basis.z) < ANG_EPS * ANG_EPS


func _send_fields() -> void:
	var batch := {}
	for key in _nodes:
		var n: Variant = _nodes[key]
		if n == null or not is_instance_valid(n):
			continue
		var names: Array = FIELDS.get(_group.get(key, ""), [])
		if names.is_empty():
			continue
		var was: Dictionary = _vals.get(key, {})
		var now := {}
		var diff := {}
		for f in names:
			var v: Variant = _read_field(n, f)
			if v == null:
				continue
			now[f] = _copy_value(v)
			if not was.has(f) or was[f] != v:
				diff[f] = _copy_value(v)
		_vals[key] = now
		if not diff.is_empty():
			_complete_fields(n, diff, names)
			batch[key] = diff
	if batch.is_empty():
		return
	mp._rx_machine_fields.rpc(batch)


# ------------------------------------------------------------------ from the net

func on_poses(packed: PackedByteArray, raw_size: int) -> void:
	if raw_size <= 0 or raw_size > MAX_RAW:
		_observe_packet(true)
		return
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		_observe_packet(true)
		return
	var batch: Variant = bytes_to_var(raw)
	if not MachinePacket.valid(batch):
		_observe_packet(true)
		return
	_observe_packet(false)
	for host_key in batch:
		var key := _local_key(String(host_key))
		if key == "":
			if _log:
				print("[MPMACH] got %s but no machine of mine matches" % host_key)
			continue
		var parts := _parts_of(key)
		if parts.is_empty():
			if _log:
				print("[MPMACH] got %s but walked no parts" % key)
			continue
		var slot := _slot_of(key)
		var entry: Dictionary = batch[host_key]
		if entry.has("a") and _nodes.get(key) is RoboticArm:
			_arm_visual.apply(key, _nodes[key], entry.a)
		if entry.has("f"):
			var flags: PackedInt32Array = entry["f"]
			var k := 0
			var hit := 0
			var lost := 0
			while k + 1 < flags.size():
				var at: int = int(slot.get(flags[k], -1))
				if at >= 0 and at < parts.size():
					var part: Variant = parts[at]
					if _live_part(key, part):
						_set_flags(part as Node3D, flags[k + 1])
						hit += 1
				else:
					lost += 1
				k += 2
			if _log and lost > 0:
				print("[MPMACH] %s flags: %d placed, %d with no part here (I walked %d)" % [
					key, hit, lost, parts.size()])
		if entry.has("xi") and entry.has("xv"):
			on_fx(key, entry["xi"], entry["xv"])
		if not entry.has("t") or not entry.has("i"):
			continue
		var moved: PackedInt32Array = entry["i"]
		var rows: PackedFloat32Array = entry["t"]
		var want: Dictionary = _goal.get(key, {})
		for j in moved.size():
			var r := j * 12
			if r + 11 >= rows.size():
				break
			if not slot.has(moved[j]):
				continue
			var to := Transform3D(Basis(
					Vector3(rows[r + 3], rows[r + 4], rows[r + 5]),
					Vector3(rows[r + 6], rows[r + 7], rows[r + 8]),
					Vector3(rows[r + 9], rows[r + 10], rows[r + 11])),
				Vector3(rows[r], rows[r + 1], rows[r + 2]))
			# walk from where the part is now to where it has got to, over the
			# gap between packets. Chasing the newest pose with a fixed pull
			# made every arm and grabber move in steps.
			var at: int = int(slot[moved[j]])
			if at < 0 or at >= parts.size() or not _live_part(key, parts[at]):
				continue
			var from: Transform3D = (parts[at] as Node3D).transform
			want[moved[j]] = [from, to, 0.0, weakref(parts[at])]
		_goal[key] = want


func _set_flags(n: Node3D, f: int) -> void:
	var on := (f & 1) != 0
	if n.visible != on:
		n.visible = on
	var running := (f & 2) != 0
	if n is GPUParticles3D and (n as GPUParticles3D).emitting != running:
		(n as GPUParticles3D).emitting = running
	elif n is CPUParticles3D and (n as CPUParticles3D).emitting != running:
		(n as CPUParticles3D).emitting = running


func on_fields(batch: Dictionary) -> void:
	if not mp.is_host:
		_send_edits()
	var diagnostic_errors := 0
	var junctions: Array = []
	for host_key in batch:
		var key := _local_key(String(host_key))
		var n: Variant = _nodes.get(key)
		if n == null or not is_instance_valid(n):
			diagnostic_errors += 1
			continue
		if not (batch[host_key] is Dictionary):
			continue
		var junction_before := _junction_state(n)
		var diff: Dictionary = batch[host_key]
		# remember what the host says, so a guest can tell a setting the player
		# just changed from one the host handed down
		var known: Dictionary = _theirs.get(key, {})
		var checked := {}
		var held := _held_fields(key, diff)
		for f in _ordered_fields(diff):
			if f in held:
				continue
			if not FIELDS.get(_group.get(key, ""), []).has(f):
				continue
			if f == "mp_arm_status" and not ArmState.valid(diff[f]):
				diagnostic_errors += 1
				continue
			if n is HayDrone and not DroneState.valid(str(f), diff[f]):
				diagnostic_errors += 1
				continue
			var pending_key := key + "|" + str(f)
			var pending: Dictionary = _pending_settings.get(pending_key, {})
			if not pending.is_empty():
				if pending.value != diff[f] and Time.get_ticks_msec() - int(pending.time) < 2000:
					continue
				_pending_settings.erase(pending_key)
			_apply_field(n as Node, String(f), diff[f])
			known[String(f)] = _copy_value(diff[f])
			checked[String(f)] = diff[f]
		_theirs[key] = known
		if _junction_state(n) != junction_before:
			junctions.append(n)
		for f in checked:
			var matches: bool = _tap_state_matches(n, checked[f]) if f == "mp_taps" else _read_field(n, f) == checked[f]
			if not matches:
				diagnostic_errors += 1
	_rewire_junctions(junctions)
	if is_instance_valid(mp.world_sync) and "diagnostics" in mp.world_sync and is_instance_valid(mp.world_sync.diagnostics):
		mp.world_sync.diagnostics.observe("machines", diagnostic_errors > 0, diagnostic_errors)


# Guest: anything in SETTINGS that no longer matches what the host last told us
# is something the player just did on a panel. Send it and remember it as the
# new agreed value, so a switch does not go out again every tick while we wait
# for the host to echo it back.
func _send_edits() -> void:
	var batch := {}
	for key in _queued_settings:
		var queued: Dictionary = _queued_settings[key]
		var n: Variant = queued.node.get_ref()
		if not is_instance_valid(n) or _nodes.get(key) != n:
			continue
		var known: Dictionary = _theirs.get(key, {})
		for field in queued.fields:
			known[field] = _copy_value(queued.fields[field])
		_theirs[key] = known
		batch[key] = queued.fields.duplicate(true)
	_queued_settings.clear()
	for key in _nodes:
		var names: Array = SETTINGS.get(_group.get(key, ""), [])
		if names.is_empty():
			continue
		var n: Variant = _nodes[key]
		if n == null or not is_instance_valid(n):
			continue
		# nothing from the host yet: we have no idea what it thinks, so a
		# difference here would be our own ignorance, not the player's doing
		var known: Dictionary = _theirs.get(key, {})
		if known.is_empty():
			continue
		var diff := {}
		for f in names:
			if not known.has(f):
				continue
			var v: Variant = _read_field(n, f)
			if v == null or v == known[f]:
				continue
			diff[f] = _copy_value(v)
		if not diff.is_empty():
			_complete_fields(n, diff, names)
			for f in diff:
				_pending_settings[key + "|" + str(f)] = {"value": _copy_value(diff[f]), "time": Time.get_ticks_msec()}
				known[f] = _copy_value(diff[f])
			if batch.has(key):
				batch[key].merge(diff, true)
			else:
				batch[key] = diff
	if batch.is_empty():
		return
	mp._rx_machine_edit.rpc_id(1, batch)
	if _log:
		print("[MPMACH] guest sent %d machine edits" % batch.size())


func queue_setting(node: Node, field: String, value: Variant) -> void:
	if _applying_fields or not is_instance_valid(mp) or not mp.active() or mp.is_host:
		return
	if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion():
		return
	if field not in ["throw_distance", "head_yaw", "switched_off"] or not node is HayPelletizer:
		return
	if field == "switched_off":
		if not value is bool:
			return
	elif not (value is int or value is float) or not is_finite(float(value)):
		return
	var key := _key("pelletizers", node)
	if _nodes.get(key) != node:
		_rescan()
	if _nodes.get(key) != node:
		return
	if not _queued_settings.has(key):
		_queued_settings[key] = {"node": weakref(node), "fields": {}}
	_queued_settings[key].fields[field] = _copy_value(value)
	_pending_settings[key + "|" + field] = {"value": _copy_value(value), "time": Time.get_ticks_msec()}


# Host: hand the machines whatever a guest has put in their mouths. A copy
# somebody else owns is frozen, and a machine skips a frozen body that is not
# riding a belt, so a guest could load a generator all day and nothing burned.
# Taking the item over here lets the machine's own code do the rest.
func _feed_mouths() -> void:
	var props: Node = mp.world_sync.props_sync if mp.world_sync != null else null
	if props == null or not is_instance_valid(props):
		return
	# loose straw thrown in by a guest, not only their items
	var straws: Node = mp.world_sync.strands_sync
	var watchers := _watchers()
	if watchers.is_empty():
		return
	var feeders: Array = _nodes.values()
	var stand: Node = builds.get("stand") as Node if is_instance_valid(builds) else null
	if is_instance_valid(stand):
		feeders.append(stand)
	for n in feeders:
		if n == null or not is_instance_valid(n) or not (n as Node3D).is_inside_tree():
			continue
		if not _near((n as Node3D).global_position, watchers):
			continue
		for mouth in MOUTHS:
			var a: Variant = (n as Node).get(mouth)
			if not (a is Area3D) or not (a as Area3D).is_inside_tree():
				continue
			for body in (a as Area3D).get_overlapping_bodies():
				if not props.host_take(body) and straws != null and is_instance_valid(straws):
					straws.host_take(body)

	for id in props._by_id.keys():
		var container: Variant = props._by_id.get(id)
		if not props._mine(id) or not is_instance_valid(container) or not container.is_inside_tree():
			continue
		if not container.has_method("takes_loose") or not container.takes_loose():
			continue
		var interior: Variant = container.get("_interior")
		if not (interior is Area3D) or not interior.is_inside_tree():
			continue
		for body in interior.get_overlapping_bodies():
			if not props.host_take(body) and is_instance_valid(straws):
				straws.host_take(body)


# Host: a guest worked a panel. The machine is ours to run, so apply it here and
# the next field tick hands it to everyone, the guest who asked included.
func on_edit(from: int, batch: Dictionary) -> void:
	if not mp.is_host or not mp.players.has(from):
		return
	for guest_key in batch:
		var key := _local_key(String(guest_key))
		var n: Variant = _nodes.get(key)
		if n == null or not is_instance_valid(n):
			continue
		var names: Array = SETTINGS.get(_group.get(key, ""), [])
		if not (batch[guest_key] is Dictionary):
			continue
		var diff: Dictionary = batch[guest_key]
		if not _t_edit_matches(n, diff):
			_vals.erase(key)
			continue
		var was: Dictionary = _vals.get(key, {})
		for f in _ordered_fields(diff):
			if (n is ConveyorTSplitter or n is ConveyorTJoiner) and f in ["entry", "out_lane", "manual", "closed_lane"]:
				continue
			# only ever the settings: a guest does not get to set our stock
			if names.has(String(f)):
				_apply_field(n as Node, String(f), diff[f])
			# forget what we last sent for it either way, so the next field
			# tick states our value again: that is what puts a guest back in
			# line when we would not take the change
			was.erase(String(f))
		_vals[key] = was


func _t_edit_matches(node: Node, fields: Dictionary) -> bool:
	var required: Array = []
	if node is ConveyorTSplitter:
		required = ["entry", "manual", "closed_lane"]
	elif node is ConveyorTJoiner:
		required = ["out_lane", "manual"]
	for field in required:
		if not fields.has(field) or fields[field] != node.get(field):
			return false
	return true


func _junction_state(node: Node) -> PackedInt32Array:
	if node is ConveyorTSplitter:
		return PackedInt32Array([node.entry, int(node.manual), node.closed_lane])
	if node is ConveyorTJoiner:
		return PackedInt32Array([node.out_lane, int(node.manual)])
	return PackedInt32Array()


func _rewire_junctions(nodes: Array) -> void:
	if nodes.is_empty() or not is_instance_valid(builds):
		return
	for node in nodes:
		if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():
			builds.refit_runs_at(node.ports())
			YardPorts.touch()
			BuildManager.jx_note(node)
	builds.rebuild_junctions()
	builds.changed.emit()
	_rescan()


func _complete_fields(n: Node, diff: Dictionary, allowed: Array) -> void:
	for group in FIELD_GROUPS:
		var changed := false
		for field in group:
			if diff.has(field) and field not in ["next_side", "stem_wait"]:
				changed = true
		if not changed:
			continue
		for field in group:
			if field in allowed:
				var value: Variant = _read_field(n, field)
				if value != null:
					diff[field] = _copy_value(value)


func _held_fields(key: String, diff: Dictionary) -> Array:
	var held: Array = []
	for field in diff:
		var pending: Dictionary = _pending_settings.get(key + "|" + str(field), {})
		if not pending.is_empty() and pending.value != diff[field] and Time.get_ticks_msec() - int(pending.time) < 2000:
			held.append(field)
	for group in FIELD_GROUPS:
		var blocked := false
		for field in group:
			if field in held:
				blocked = true
		if blocked:
			for field in group:
				if field not in held:
					held.append(field)
	return held


func _ordered_fields(diff: Dictionary) -> Array:
	var fields: Array = diff.keys()
	for field in ["out_lane", "entry"]:
		if fields.has(field):
			fields.erase(field)
			fields.push_front(field)
	for field in ["forced_side", "priority_side", "next_side", "stem_wait", "resume_rate"]:
		if fields.has(field):
			fields.erase(field)
			fields.append(field)
	return fields


func _tap_state(n: Node) -> Array:
	var out: Array = []
	for tap in n.taps:
		if is_instance_valid(tap) and not tap.is_queued_for_deletion() and not n.is_pending_tap(tap):
			out.append([tap.position, -tap.basis.z])
	return out


func _tap_state_matches(n: Node, value: Variant) -> bool:
	if not (value is Array):
		return false
	var current := _tap_state(n)
	if current.size() != value.size():
		return false
	for i in current.size():
		if not (value[i] is Array) or value[i].size() != 2:
			return false
		for side in 2:
			if not (value[i][side] is Vector3) or not value[i][side].is_finite():
				return false
			if current[i][side].distance_to(value[i][side]) >= 0.00001:
				return false
	return true


func _same_tap(tap: Node3D, data: Array) -> bool:
	return tap.position.distance_to(data[0]) < 0.00001 and (-tap.basis.z).distance_to(data[1]) < 0.00001


func _apply_taps(n: Node, value: Variant) -> void:
	if not (value is Array) or value.size() > 4096:
		return
	for data in value:
		if not (data is Array) or data.size() != 2:
			return
		if not (data[0] is Vector3) or not (data[1] is Vector3) or not data[0].is_finite() or not data[1].is_finite():
			return
		if absf(data[1].length_squared() - 1.0) > 0.001 or absf(data[1].dot(Vector3.BACK)) > 0.999:
			return
	if _tap_state(n) == value:
		return
	var used: Array = []
	var changed := false
	for data in value:
		var found: Node3D = null
		for tap in n.taps:
			if is_instance_valid(tap) and not tap.is_queued_for_deletion() and tap not in used and _same_tap(tap, data):
				found = tap
				break
		if found == null:
			found = n.add_tap(data[0], data[1], false)
			changed = true
		elif n.is_pending_tap(found):
			n.commit_tap(found)
			changed = true
		used.append(found)
	for tap in n.taps.duplicate():
		if not is_instance_valid(tap):
			n.taps.erase(tap)
			changed = true
		elif tap not in used:
			if n.is_pending_tap(tap):
				used.append(tap)
			else:
				n.remove_tap(tap)
				changed = true
	if n.taps != used:
		n.taps.assign(used)
		changed = true
	if changed:
		builds.rebuild_water_joints()
		builds.changed.emit()


func _copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	if typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) < TYPE_MAX:
		return value.duplicate()
	return value


func _read_field(n: Node, field: String) -> Variant:
	match field:
		"mp_arm_status": return n.mp_status_snapshot() if n.has_method("mp_status_snapshot") else ArmState.capture(n)
		"mp_drone_status": return DroneState.status(n)
		"mp_t_revision":
			return int(n.get_meta("mp_t_revision", 0)) if n is ConveyorTSplitter or n is ConveyorTJoiner else null
		"mp_links": return n.links_to_save()
		"mp_taps": return _tap_state(n)
		"mp_zone": return [n.zone_at, n.zone_r]
		"mp_drop": return [n.drop_at, n.drop_kind]
		"_off": return n.get("_off")
	return n.get(field)


func _apply_field(n: Node, f: String, v: Variant) -> void:
	var was_applying := _applying_fields
	_applying_fields = true
	_apply_field_value(n, f, v)
	_applying_fields = was_applying


func _apply_field_value(n: Node, f: String, v: Variant) -> void:
	if f == "mp_arm_status":
		if not mp.is_host and n.has_method("mp_apply_status"):
			n.mp_apply_status(v)
		return
	if f == "banked" and n is HaystackScanner:
		return
	if f == "mp_t_revision":
		if not mp.is_host and v is int and v >= 0 and (n is ConveyorTSplitter or n is ConveyorTJoiner):
			n.set_meta("mp_t_revision", maxi(v, int(n.get_meta("mp_t_revision", 0))))
		return
	if f == "mp_taps":
		if not mp.is_host:
			_apply_taps(n, v)
		return
	if f in ["discharge_rate", "resume_rate", "throw_distance", "head_yaw", "out_lane", "entry"]:
		if not (v is int or v is float) or not is_finite(float(v)):
			return
	if f in ["out_lane", "entry"]:
		var setter := "set_out" if f == "out_lane" else "set_entry"
		if v != int(v) or int(v) < 0 or int(v) > 2 or not n.has_method(setter):
			return
		n.call(setter, int(v))
		return
	if f == "discharge_rate" and n.has_method("set_rate"):
		var resume: Variant = n.get("resume_rate")
		n.set_rate(float(v))
		if not mp.is_host:
			n.set(f, float(v))
			n.set("resume_rate", resume)
		return
	if f == "resume_rate" and n.has_method("rate_min") and n.has_method("rate_max"):
		n.set(f, clampf(float(v), n.rate_min(), n.rate_max()) if mp.is_host else float(v))
		return
	if n is HayDrone:
		if not DroneState.valid(f, v):
			return
		if not mp.is_host:
			DroneState.apply_snapshot(n, f, v)
			return
	if f == "mp_links" and n.has_method("load_links"):
		n.load_links(v)
		return
	if f == "mp_zone" and v is Array and v.size() == 2:
		if not (v[0] is Vector3) or not v[0].is_finite() or float(v[1]) <= 0:
			n.clear_zone()
		else:
			n.set_zone(v[0], float(v[1]))
		return
	if f == "mp_drop" and v is Array and v.size() == 2:
		if not (v[0] is Vector3) or not v[0].is_finite():
			n.clear_drop()
		else:
			n.set_drop(v[0], int(v[1]))
		return
	if f == "tier_index" and n.has_method("set_tier"):
		n.set_tier(int(v))
		return
	if f == "filters" and n.has_method("set_filter") and (v is Array or v is PackedInt32Array):
		for side in mini(v.size(), 3):
			n.set_filter(side, int(v[side]))
		return
	if f == "closed_lane" and n.has_method("set_closed"):
		n.set_closed(int(v))
		return
	var setter := "set_switched_off" if f == "_off" else "set_" + f
	if n.has_method(setter):
		n.call(setter, v)
	else:
		n.set(f, v)


# Parts ease towards the last pose we heard about, so ten packets a second
# still read as movement rather than stepping.
func _ease(delta: float) -> void:
	_arm_visual.step(delta)
	if _goal.is_empty():
		return
	var step_t := delta / TICK
	for key in _goal:
		var parts := _parts_of(key)
		var slot := _slot_of(key)
		var want: Dictionary = _goal[key]
		var done: Array = []
		for part_id in want:
			var idx: int = int(slot.get(part_id, -1))
			if idx < 0 or idx >= parts.size():
				done.append(part_id)
				continue
			var part: Variant = parts[idx]
			if not _live_part(key, part):
				done.append(part_id)
				continue
			var walk: Array = want[part_id]
			if walk.size() != 4 or not is_same(walk[3].get_ref(), part):
				done.append(part_id)
				continue
			var from: Transform3D = walk[0]
			var to: Transform3D = walk[1]
			var t: float = minf(1.0, float(walk[2]) + step_t)
			walk[2] = t
			# axis by axis: interpolate_with would pull a skewed part through a
			# rotation it never had
			(part as Node3D).transform = Transform3D(Basis(
					from.basis.x.lerp(to.basis.x, t),
					from.basis.y.lerp(to.basis.y, t),
					from.basis.z.lerp(to.basis.z, t)),
				from.origin.lerp(to.origin, t))
			if t >= 1.0:
				done.append(part_id)
		for gone in done:
			want.erase(gone)


# A client just arrived: forget what we think it knows, so the next ticks
# send every pose, flag and setting again.
func send_all(_pid: int) -> void:
	_rescan()
	_sent.clear()
	_flags.clear()
	_vals.clear()


# ------------------------------------------------------------------ glow

# Smoke columns, fire glow and dials are driven by a shader value or a light's
# strength, not by a node moving, so a frozen machine looks cold without them.
# Work out once per part what it has, then send only what changed.
func _fx_of(key: String) -> Array:
	if _fx.has(key):
		return _fx[key]
	var out: Array = []
	for part in _parts_of(key):
		# the game frees some parts of its own (markers, rings) while it runs
		if part == null or not is_instance_valid(part):
			out.append(null)
			continue
		var node := part as Node3D
		var entry: Dictionary = {}
		if node is Light3D:
			entry["light"] = node
		var mat: Variant = _shader_of(node)
		if mat != null:
			var names := PackedStringArray()
			for u in (mat as ShaderMaterial).shader.get_shader_uniform_list():
				if int(u.get("type", -1)) == TYPE_FLOAT:
					names.append(String(u.get("name", "")))
			if names.size() > 0:
				entry["mat"] = mat
				entry["names"] = names
		out.append(entry if not entry.is_empty() else null)
	_fx[key] = out
	return out


func _shader_of(n: Node3D) -> Variant:
	if not (n is GeometryInstance3D):
		return null
	var g := n as GeometryInstance3D
	if g.material_override is ShaderMaterial:
		# the build hologram, while a machine is being put up: it belongs to
		# BuildFx, which hands the real material back when it is done
		if _is_build_glow(g.material_override):
			return null
		return g.material_override
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.get_surface_override_material_count() > 0 \
		and mi.get_surface_override_material(0) is ShaderMaterial:
			return mi.get_surface_override_material(0)
		if mi.mesh != null and mi.mesh.get_surface_count() > 0 \
		and mi.mesh.surface_get_material(0) is ShaderMaterial:
			return mi.mesh.surface_get_material(0)
	return null


# While a machine is being put up, BuildFx swaps every mesh's material for its
# green hologram and puts the real one back when it is done, but only on a
# mesh still wearing that hologram. We used to copy it as the part's "own"
# material, so the game never gave the real one back and the machine stayed a
# half-built hologram for good.
func _is_build_glow(mat: Variant) -> bool:
	return mat is ShaderMaterial and BuildFx._shader != null \
		and (mat as ShaderMaterial).shader == BuildFx._shader


# -1 as the slot means the light's strength, 0 and up are shader values
func _read_fx(key: String, ids: PackedInt32Array, vals: PackedFloat32Array) -> void:
	var fx := _fx_of(key)
	var part_ids := _ids_of(key)
	var was: Dictionary = _fx_sent.get(key, {})
	if _full:
		was = {}
	for i in fx.size():
		var entry: Variant = fx[i]
		if entry == null:
			continue
		var d: Dictionary = entry
		if d.has("light"):
			var light: Variant = d["light"]
			if is_instance_valid(light):
				_note_fx(part_ids[i], -1, (light as Light3D).light_energy, was, ids, vals)
		if not d.has("mat"):
			continue
		var mat: Variant = d["mat"]
		if not is_instance_valid(mat):
			continue
		var names: PackedStringArray = d["names"]
		for j in names.size():
			var v: Variant = (mat as ShaderMaterial).get_shader_parameter(names[j])
			if v == null:
				continue
			_note_fx(part_ids[i], j, float(v), was, ids, vals)
	_fx_sent[key] = was


func _note_fx(part_id: int, slot: int, v: float, was: Dictionary,
		ids: PackedInt32Array, vals: PackedFloat32Array) -> void:
	var at := "%d:%d" % [part_id, slot]
	if was.has(at) and absf(float(was[at]) - v) < 0.004:
		return
	was[at] = v
	ids.append(part_id)
	ids.append(slot)
	vals.append(v)


func on_fx(key: String, ids: PackedInt32Array, vals: PackedFloat32Array) -> void:
	if ids.size() != vals.size() * 2:
		return
	var parts := _parts_of(key)
	var fx := _fx_of(key)
	var slot := _slot_of(key)
	var k := 0
	while k + 1 < ids.size() and k / 2 < vals.size():
		var at: int = int(slot.get(ids[k], -1))
		var which: int = ids[k + 1]
		var v: float = vals[k / 2]
		k += 2
		if not is_finite(v) or at < 0 or at >= fx.size() or fx[at] == null or at >= parts.size() or not _live_part(key, parts[at]):
			continue
		var d: Dictionary = fx[at]
		if which < 0:
			if d.has("light") and is_instance_valid(d["light"]):
				(d["light"] as Light3D).light_energy = v
			continue
		if not d.has("mat") or not is_instance_valid(d["mat"]):
			continue
		var names: PackedStringArray = d["names"]
		if which < names.size():
			var material := _own_material(key, at, d)
			if material != null:
				material.set_shader_parameter(names[which], v)


# A machine's shader material is often the mesh's own, shared by every copy of
# that machine, so one machine's smoke or glow set here showed on all of them.
# Give the part its own copy the first time we write to it.
func _own_material(key: String, at: int, d: Dictionary) -> ShaderMaterial:
	var mat: ShaderMaterial = d["mat"]
	var parts := _parts_of(key)
	if at < 0 or at >= parts.size() or parts[at] == null or not is_instance_valid(parts[at]) \
	or not (parts[at] is GeometryInstance3D):
		return null
	if _shader_of(parts[at]) != mat or _is_build_glow(mat):
		return null
	if mat.has_meta("mp_own"):
		return mat
	var own := mat.duplicate() as ShaderMaterial
	own.set_meta("mp_own", true)
	var g := parts[at] as GeometryInstance3D
	if g.material_override == mat:
		g.material_override = own
	elif g is MeshInstance3D:
		(g as MeshInstance3D).set_surface_override_material(0, own)
	else:
		return mat
	d["mat"] = own
	return own


# Where a part hangs, as a name both sides work out the same way. Nodes the
# game builds in code get a generated name (@GPUParticles3D@27) that counts up
# differently on each machine, so those are placed by what they are and where
# they sit among their siblings instead.
func _part_path(base: Node, n: Node) -> String:
	var bits := PackedStringArray()
	var cur: Node = n
	while cur != null and cur != base:
		bits.append(_part_name(cur))
		cur = cur.get_parent()
	bits.reverse()
	return "/".join(bits)


func _part_name(n: Node) -> String:
	var nm := String(n.name)
	if not nm.begins_with("@"):
		return nm
	var parent := n.get_parent()
	if parent == null:
		return n.get_class()
	var seen := 0
	for child in parent.get_children():
		if child == n:
			break
		if child.get_class() == n.get_class():
			seen += 1
	return "%s#%d" % [n.get_class(), seen]


func _protect_processors() -> void:
	for group in ["compressors", "wrappers", "hay_drones", "robotic_arms", "hay_lifts", "hay_stairs", "scanners", "pelletizers", "joiners", "splitters"]:
		var nodes: Variant = builds.get(group)
		if nodes is Array:
			for node in nodes:
				_protect_processor(node)


func _processor_added(node: Node) -> void:
	if node is HayCompressor or node is HayWrapper or node is HayDrone or node is RoboticArm or node is HayLift or node is HayStairs or node is HaystackScanner or node is HayPelletizer or node is ConveyorJoiner or node is ConveyorSplitter:
		_protect_processor_deferred.call_deferred(weakref(node))


func _protect_processor_deferred(reference: WeakRef) -> void:
	var node: Variant = reference.get_ref()
	if is_instance_valid(node):
		_protect_processor(node)


func _protect_processor(node: Node) -> void:
	if not _processors_enabled or not is_instance_valid(node) or not node.is_inside_tree() or not node.is_node_ready() or node.is_queued_for_deletion():
		return
	_protect_junction(node)
	if not (node is HayCompressor or node is HayWrapper or node is HayDrone or node is RoboticArm or node is HayLift or node is HayStairs or node is HaystackScanner or node is HayPelletizer or node is ConveyorTSplitter):
		return
	if node.placement_preview:
		return
	var original: Script = node.get_script()
	var saved: Dictionary = _processor_hooks.get(node.get_instance_id(), {})
	if not saved.is_empty() and original == saved["replacement"]:
		_refresh_processor_belt(node)
		return
	if original == null:
		return
	var replacement: Script
	if original.resource_path == "res://scripts/build/conveyor_t_splitter.gd":
		replacement = load(mp.base_dir + "/mp_distributor_t_splitter.gd")
	elif original.resource_path == "res://scripts/build/hay_compressor.gd":
		replacement = load(mp.base_dir + "/mp_hay_compressor.gd")
	elif original.resource_path == "res://scripts/build/hay_wrapper.gd":
		replacement = load(mp.base_dir + "/mp_hay_wrapper.gd")
	elif original.resource_path == "res://scripts/build/hay_drone.gd":
		replacement = load(mp.base_dir + "/mp_hay_drone.gd")
	elif original.resource_path == "res://scripts/build/hay_pelletizer.gd":
		replacement = load(mp.base_dir + "/mp_hay_pelletizer.gd")
	elif original.resource_path == "res://scripts/build/hay_stairs.gd":
		replacement = load(mp.base_dir + "/mp_hay_stairs.gd")
	elif original.resource_path == "res://scripts/build/hay_lift.gd":
		replacement = load(mp.base_dir + "/mp_hay_lift.gd")
	elif original.resource_path == "res://scripts/build/robotic_arm.gd":
		replacement = load(mp.base_dir + "/mp_robotic_arm.gd")
	elif original.resource_path == "res://scripts/build/haystack_scanner.gd":
		replacement = load(mp.base_dir + "/mp_haystack_scanner.gd")
	else:
		return
	_replace_processor_script(node, replacement)
	if "mp_transport" in node:
		node.set("mp_transport", self)
	if node is HayLift or node is HayStairs:
		node._follow_tech()
	_processor_hooks[node.get_instance_id()] = {"node": weakref(node), "original": original, "replacement": replacement}
	_refresh_processor_belt(node)


func _protect_junction(node: Node) -> void:
	if not mp.is_host or not (node is ConveyorJoiner or node is ConveyorSplitter) or node.placement_preview or not "_jam" in node:
		return
	var helper: Variant = node.get("_jam")
	if not is_instance_valid(helper):
		return
	var original: Script = helper.get_script()
	if original == null or original.resource_path != "res://scripts/build/junction_jam.gd":
		return
	var replacement: Script = load(mp.base_dir + "/mp_junction_jam.gd")
	if replacement == null:
		return
	_replace_junction_script(helper, replacement)
	_junction_hooks[helper.get_instance_id()] = {"helper": weakref(helper), "original": original, "replacement": replacement}


func _replace_junction_script(helper: Object, script: Script) -> void:
	var values := {}
	for property in helper.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = helper.get(property.name)
	helper.set_script(script)
	for key in values:
		if key in helper:
			helper.set(key, values[key])


func _replace_processor_script(node: Node, script: Script) -> void:
	var values := {}
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = node.get(property.name)
	node.set_script(script)
	for key in values:
		if key in node:
			node.set(key, values[key])


func _refresh_processor_belt(node: Node) -> void:
	if node is HayDrone or node is RoboticArm or node is HayLift or node is HayStairs or node is HaystackScanner or node is HayPelletizer or node is ConveyorTSplitter:
		return
	var belt: Variant = node.get("_belt")
	if not is_instance_valid(belt) or not belt.is_inside_tree():
		return
	var parks := Callable(node, "_parks")
	if belt.get("_eats") != parks or not bool(belt.get("_records_held")) \
			or belt.run.hold_for != Callable(belt, "_eats_kind"):
		belt.hold_records(parks)
	if node is HayCompressor:
		belt._sync_run_links()
		var holds := Callable(node, "_held_in_mouth")
		if belt.get("_hold_for") != holds:
			belt.set_hold_filter(holds)


func _live_part(key: String, part: Variant) -> bool:
	var machine: Variant = _nodes.get(key)
	return is_instance_valid(machine) and machine is Node3D \
		and machine.is_inside_tree() and not machine.is_queued_for_deletion() \
		and is_instance_valid(part) and part is Node3D \
		and part.is_inside_tree() and not part.is_queued_for_deletion() \
		and machine.is_ancestor_of(part) and not _is_transport_part(part)


func _is_transport_part(part: Node) -> bool:
	var current := part
	while is_instance_valid(current):
		if current is BeltPath or current.name == "Marker_BeltIn" or current.name == "Marker_BeltOut" or current.has_meta("mp_lift_cargo") or current.has_meta("mp_arm_visual"):
			return true
		var parent := current.get_parent()
		if parent is RoboticArm and current == parent.get("_payload_visual"):
			return true
		if parent is HayPulper and current in parent.taps:
			return true
		if parent is HayLift or parent is HayStairs:
			for carried in parent._carried:
				if carried.get("draw") == current:
					return true
		current = parent
	return false


func _observe_packet(rejected: bool) -> void:
	if is_instance_valid(mp.world_sync) and is_instance_valid(mp.world_sync.diagnostics):
		mp.world_sync.diagnostics.observe("machines", rejected, 1 if rejected else 0, 1)
