extends Node

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
	"silos": ["switched_off", "stored", "queued"],
	"splitters": ["forced_side", "priority_side", "next_side", "filters", "entry", "manual", "closed_lane", "fed"],
	"joiners": ["next_side"],
	"tube_launchers": ["switched_off", "aim", "power", "stored"],
	"piston_rakes": ["switched_off", "throw_distance"],
	"pelletizers": ["switched_off", "throw_distance", "stored"],
	"robotic_arms": ["switched_off", "accept_mask", "tier_index"],
	"scanners": ["switched_off", "tier_index", "banked", "stored"],
	"compressors": ["switched_off", "stored"],
	"pulpers": ["switched_off", "stored"],
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
	"_brick_mouth", "_catch"]
const MOUTH_TICK := 0.25

# What a panel lets a player change, as opposed to what a machine works out for
# itself. Only these travel back from a guest: fuel, stock, output and the rest
# are the host's to count, and taking a guest's word for them would let the
# same hay pay twice.
const SETTINGS := {
	"generators": ["switched_off"],
	"silos": ["switched_off"],
	"splitters": ["forced_side", "priority_side", "filters", "entry", "manual", "closed_lane"],
	"tube_launchers": ["switched_off", "aim", "power"],
	"piston_rakes": ["switched_off", "throw_distance"],
	"pelletizers": ["switched_off", "throw_distance"],
	"robotic_arms": ["switched_off", "accept_mask", "tier_index"],
	"scanners": ["switched_off", "tier_index"],
	"compressors": ["switched_off"],
	"pulpers": ["switched_off"],
	"papers": ["switched_off"],
	"briquette_presses": ["switched_off"],
	"wrappers": ["switched_off"],
	"boreholes": ["switched_off"],
	"work_lamps": ["brightness", "_off"],
}

var mp: Node
var world: Node
var builds: Node

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
	_rescan()


func shutdown() -> void:
	_parts.clear()
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
	if builds == null or not is_instance_valid(builds):
		return
	var ws: Node = mp.world_sync
	var groups: Array = ws.get_script().get_script_constant_map().get("CLIENT_FROZEN", [])
	_nodes.clear()
	# walk the models again: the game adds and drops nodes as it runs
	_parts.clear()
	_fx.clear()
	_ids.clear()
	_slot.clear()
	_group.clear()
	for group in groups + SETTINGS_ONLY:
		var arr: Variant = builds.get(group)
		if not (arr is Array):
			continue
		for n in arr:
			if n is Node3D and is_instance_valid(n):
				var key := _key(String(group), n)
				_nodes[key] = n
				_group[key] = String(group)
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
	var bar := key.find("|")
	if bar < 0:
		return ""
	var group := key.substr(0, bar)
	var xyz := key.substr(bar + 1).split(",")
	if xyz.size() != 3:
		return ""
	var at := Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
	var best := ""
	var best_d := KEY_SLACK * KEY_SLACK
	for k in _nodes:
		if _group.get(k, "") != group:
			continue
		var n: Variant = _nodes[k]
		if n == null or not is_instance_valid(n):
			continue
		var d := (n as Node3D).global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = k
	if best != "":
		_alias[key] = best
	return best


func _key(group: String, n: Node3D) -> String:
	var p := n.global_position
	return "%s|%.2f,%.2f,%.2f" % [group, p.x, p.y, p.z]


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
		if child is Node3D:
			out.append(child)
			_walk(child, out)


# ------------------------------------------------------------------ ticks

func _process(delta: float) -> void:
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
			if part == null or not is_instance_valid(part):
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
	if _full or packed.size() > BIG_PACKET:
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
	if _full:
		mp._rx_machines_big.rpc(packed, raw.size())
	else:
		mp._rx_machines.rpc(packed, raw.size())


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
			var v: Variant = (n as Node).get(f)
			if v == null:
				continue
			now[f] = _copy_value(v)
			if not was.has(f) or was[f] != v:
				diff[f] = _copy_value(v)
		_vals[key] = now
		if not diff.is_empty():
			batch[key] = diff
	if batch.is_empty():
		return
	mp._rx_machine_fields.rpc(batch)


# ------------------------------------------------------------------ from the net

func on_poses(packed: PackedByteArray, raw_size: int) -> void:
	if raw_size <= 0 or raw_size > MAX_RAW:
		return
	var batch: Variant = bytes_to_var(packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD))
	if not (batch is Dictionary):
		return
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
		if entry.has("f"):
			var flags: PackedInt32Array = entry["f"]
			var k := 0
			var hit := 0
			var lost := 0
			while k + 1 < flags.size():
				var at: int = int(slot.get(flags[k], -1))
				if at >= 0 and at < parts.size():
					var part: Variant = parts[at]
					if part != null and is_instance_valid(part):
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
			var from: Transform3D = to
			if at < parts.size() and parts[at] != null and is_instance_valid(parts[at]):
				from = (parts[at] as Node3D).transform
			want[moved[j]] = [from, to, 0.0]
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
	for host_key in batch:
		var key := _local_key(String(host_key))
		var n: Variant = _nodes.get(key)
		if n == null or not is_instance_valid(n):
			continue
		var diff: Dictionary = batch[host_key]
		# remember what the host says, so a guest can tell a setting the player
		# just changed from one the host handed down
		var known: Dictionary = _theirs.get(key, {})
		for f in diff:
			_apply_field(n as Node, String(f), diff[f])
			known[String(f)] = _copy_value(diff[f])
		_theirs[key] = known


# Guest: anything in SETTINGS that no longer matches what the host last told us
# is something the player just did on a panel. Send it and remember it as the
# new agreed value, so a switch does not go out again every tick while we wait
# for the host to echo it back.
func _send_edits() -> void:
	if _theirs.is_empty():
		return
	var batch := {}
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
			var v: Variant = (n as Node).get("switched_off" if f == "_off" else f)
			if v == null or v == known[f]:
				continue
			diff[f] = v
			known[f] = _copy_value(v)
		if not diff.is_empty():
			batch[key] = diff
	if batch.is_empty():
		return
	mp._rx_machine_edit.rpc_id(1, batch)
	if _log:
		print("[MPMACH] guest sent %d machine edits" % batch.size())


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
	for key in _nodes:
		var n: Variant = _nodes[key]
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
		var diff: Dictionary = batch[guest_key]
		var was: Dictionary = _vals.get(key, {})
		for f in diff:
			# only ever the settings: a guest does not get to set our stock
			if names.has(String(f)):
				_apply_field(n as Node, String(f), diff[f])
			# forget what we last sent for it either way, so the next field
			# tick states our value again: that is what puts a guest back in
			# line when we would not take the change
			was.erase(String(f))
		_vals[key] = was


func _copy_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary or value is PackedInt32Array:
		return value.duplicate(true) if value is Array or value is Dictionary else value.duplicate()
	return value


func _apply_field(n: Node, f: String, v: Variant) -> void:
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
			if part == null or not is_instance_valid(part):
				done.append(part_id)
				continue
			var walk: Array = want[part_id]
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
	var fx := _fx_of(key)
	var slot := _slot_of(key)
	var k := 0
	while k + 1 < ids.size() and k / 2 < vals.size():
		var at: int = int(slot.get(ids[k], -1))
		var which: int = ids[k + 1]
		var v: float = vals[k / 2]
		k += 2
		if at < 0 or at >= fx.size() or fx[at] == null:
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
			_own_material(key, at, d).set_shader_parameter(names[which], v)


# A machine's shader material is often the mesh's own, shared by every copy of
# that machine, so one machine's smoke or glow set here showed on all of them.
# Give the part its own copy the first time we write to it.
func _own_material(key: String, at: int, d: Dictionary) -> ShaderMaterial:
	var mat: ShaderMaterial = d["mat"]
	if mat.has_meta("mp_own") or _is_build_glow(mat):
		return mat
	var parts := _parts_of(key)
	if at < 0 or at >= parts.size() or parts[at] == null or not is_instance_valid(parts[at]) \
	or not (parts[at] is GeometryInstance3D):
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
