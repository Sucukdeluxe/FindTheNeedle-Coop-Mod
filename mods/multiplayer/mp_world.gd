# Per-world sync for the multiplayer mod. Created by MPMod once the yard is
# built, freed when the scene changes. All network traffic goes through MPMod's
# RPCs; this node only reads and applies game state.
extends Node

var mp: Node
var world: Node
var field: Node
var builds: Node
var _build_script: Script
var _mission_script: Script
var _mission_reported_index := 0
var player: Node

const POSE_HZ := 20.0
const HAY_TICK := 0.12
const HAY_FULL_SCAN := 3.0
const HAY_EPS := 0.002
const HAY_BATCH := 6000
const BUILD_TICK := 0.4
const RECONCILE_TICK := 3.0
const STATE_TICK := 0.25
# The host sends a checksum per 16x16-vertex block of the pile this often. A
# guest compares it with its own pile and asks for the blocks that drifted.
const HAY_SUM_TICK := 4.0
const HAY_BLOCK := 16
# metres of height summed over a block before it counts as drifted: well above
# the HAY_EPS rounding every vertex is allowed, well below any real dig
const HAY_SUM_TOL := 0.5

# Machines that dig, scan, route, lift or turn hay into something, and the
# cabinets and radars. They run on the host only: their motion, settings, belt
# contents and the items they make are sent out, so running them twice would
# count the same hay twice. Conveyors, decks, walls and lamps stay live
# everywhere.
const CLIENT_FROZEN := ["piston_rakes", "robotic_arms", "hay_drones", "scanners",
	"compressors", "pulpers", "papers", "briquette_presses", "wrappers", "silos",
	"pelletizers", "tube_launchers", "dump_hatches", "needle_radars",
	"generators", "boreholes", "splitters", "joiners", "hay_lifts", "hay_stairs",
	"cabinets"]

const BUILD_ARRAYS := ["conveyors", "corners", "water_mains", "water_splitters",
	"robotic_arms", "platforms", "stairs", "railings", "walls", "roofs", "scanners",
	"compressors", "pulpers", "papers", "briquette_presses", "wrappers", "silos",
	"pelletizers", "generators", "boreholes", "tube_launchers", "dump_hatches",
	"hay_stairs", "hay_lifts", "splitters", "joiners", "cabinets", "needle_radars",
	"paint_boards", "work_lamps", "hay_drones", "piston_rakes", "power_poles"]
const BUILD_SHAPE_KEYS := ["span", "rise", "kind", "sections", "rows", "side", "port_r", "line", "buried"]

# Settings the game keeps in a save's meta and reads back when it loads one,
# as { the name on Cfg: the name in the meta }. The guest builds its yard out
# of our payload with the game's own loader, so anything missing here reaches
# it as a default: shed_long_bays decides how long the warehouse is and where
# the sell stand goes, and leaving it out put the two players' stands eleven
# metres apart. Sent only when the game has it, so older builds are untouched.
const CFG_META := {"shed_long_bays": "shed_bays", "shed_grid": "shed_grid"}

const ADD_F := ["money", "debt", "hay_total", "hay_dug", "hay_returned", "hay_sold",
	"money_earned", "stacks_ordered", "needles_found", "pile_needles_found"]
const ADD_A := ["needles_by_type", "needle_stock"]
const OR_A := ["needle_taken", "discovered"]
const HOST_ABS := ["run_secs", "lot_tier", "hay_initial", "money_peak", "pile_cleared",
	"first_needle_secs", "first_clear_secs", "best_sale", "best_sale_strands"]
const HOST_MAX := ["mission_index", "contract_index"]

var avatars := {}
var _avatar_script: Script
var _me: Node  # our own body, seen when looking down
var props_sync: Node  # loose item replication
var belts_sync: Node  # what is riding on the belts
var machines_sync: Node  # how the machines move and what they are set to
var strands_sync: Node  # loose straw on the ground
var contracts_sync: Node  # the delivery truck and its contract
var _tech_script: Script
var tools_sync: Node
var economy: Node
var boards_sync: Node  # what is drawn on the paint boards
var _pose_t := 0.0

var _hay_base := PackedFloat32Array()
var _hay_cand := {}
var _hay_t := 0.0
var _hay_scan_t := 0.0

var _bkeys := {}  # key -> building dict
var _builds_dirty := false
var _build_t := 0.0
var _applying_builds := false
var _reconcile_t := 0.0
var _build_revision := 0
var _last_build_change := 0
var _mismatch_count := 0
var _repair_requested_at := -10000

var _st_base := {}
var _st_pending: Array = []  # [seq, delta]
var _seq := 0
var _peer_ack := {}
var _state_t := 0.0
var _tech_mute := false
var _needles := {}  # needle index -> "free" | "held" | "away"
var _holder := {}  # host: needle index -> peer holding it
var _last_at := {}  # peer -> where its last pose put it (outlives the avatar)
var _hay_sum_t := 0.0
var _tech_queue := {}  # tech id -> rank changed this frame, sent at the end of it
var _tech_paid := {}   # tech id -> true if that change was bought, not granted
var tech_refunds := 0  # host: ranks bought twice and paid back (for the log and the test)
var _needle_t := 0.0
var _frozen := false  # stop sending (pile swap in progress, waiting for a reload)
var _pile_seed := 0


func _ready() -> void:
	_tech_script = Tech.get_script()
	_replace_tech_script(load(mp.base_dir + "/mp_tech.gd"))
	Tech.set("mp_world", self)
	field = world.get("field")
	builds = world.get("builds")
	if is_instance_valid(builds):
		_build_script = builds.get_script()
		_replace_build_script(load(mp.base_dir + "/mp_builds.gd"))
		builds.set("mp_world", self)
	player = world.get("player")
	var missions: Variant = world.get("missions")
	if is_instance_valid(missions):
		_mission_script = missions.get_script()
		_replace_mission_script(load(mp.base_dir + "/mp_missions.gd"))
		missions.set("mp_world", self)
	_mission_reported_index = GameState.mission_index
	_avatar_script = load(mp.base_dir + "/mp_avatar.gd")
	_me = _avatar_script.new()
	_me.setup_local(player, mp)
	world.add_child(_me)
	props_sync = (load(mp.base_dir + "/mp_props.gd") as Script).new()
	props_sync.name = "MPProps"
	add_child(props_sync)
	props_sync.start(mp, world)
	belts_sync = (load(mp.base_dir + "/mp_belts.gd") as Script).new()
	belts_sync.name = "MPBelts"
	add_child(belts_sync)
	belts_sync.start(mp, world)
	machines_sync = (load(mp.base_dir + "/mp_machines.gd") as Script).new()
	machines_sync.name = "MPMachines"
	add_child(machines_sync)
	machines_sync.start(mp, world)
	strands_sync = (load(mp.base_dir + "/mp_strands.gd") as Script).new()
	strands_sync.name = "MPStrands"
	add_child(strands_sync)
	strands_sync.start(mp, world)
	contracts_sync = (load(mp.base_dir + "/mp_contracts.gd") as Script).new()
	contracts_sync.name = "MPContracts"
	add_child(contracts_sync)
	contracts_sync.start(mp, world)
	boards_sync = (load(mp.base_dir + "/mp_boards.gd") as Script).new()
	boards_sync.name = "MPBoards"
	add_child(boards_sync)
	boards_sync.start(mp, world)
	tools_sync = load(mp.base_dir + "/mp_tools.gd").new()
	add_child(tools_sync)
	tools_sync.start(mp, world)
	economy = load(mp.base_dir + "/mp_economy.gd").new()
	add_child(economy)
	economy.start(mp, self)
	if field != null:
		field.cells_redrawn.connect(_on_cells_redrawn)
	if builds != null:
		builds.changed.connect(_on_builds_changed)
	Tech.tech_changed.connect(_on_tech_changed)
	GameState.pile_replaced.connect(_on_pile_replaced)
	GameState.needle_found.connect(_on_needle_found)
	GameState.needle_discovered.connect(_on_needle_discovered)
	GameState.purchased.connect(_on_purchased)
	rebaseline()
	if mp.active():
		apply_session_rules()


func shutdown() -> void:
	if is_instance_valid(economy):
		economy.shutdown()
	if _tech_script != null:
		_replace_tech_script(_tech_script)
	if is_instance_valid(tools_sync):
		tools_sync.shutdown()
	if _mission_script != null and is_instance_valid(world.get("missions")):
		_replace_mission_script(_mission_script)
	if is_instance_valid(builds) and _build_script != null:
		_replace_build_script(_build_script)
	if Tech.tech_changed.is_connected(_on_tech_changed):
		Tech.tech_changed.disconnect(_on_tech_changed)
	if GameState.pile_replaced.is_connected(_on_pile_replaced):
		GameState.pile_replaced.disconnect(_on_pile_replaced)
	if GameState.needle_found.is_connected(_on_needle_found):
		GameState.needle_found.disconnect(_on_needle_found)
	if GameState.needle_discovered.is_connected(_on_needle_discovered):
		GameState.needle_discovered.disconnect(_on_needle_discovered)
	if GameState.purchased.is_connected(_on_purchased):
		GameState.purchased.disconnect(_on_purchased)
	if props_sync != null and is_instance_valid(props_sync):
		props_sync.shutdown()
	if belts_sync != null and is_instance_valid(belts_sync):
		belts_sync.shutdown()
	if machines_sync != null and is_instance_valid(machines_sync):
		machines_sync.shutdown()
	if strands_sync != null and is_instance_valid(strands_sync):
		strands_sync.shutdown()
	if contracts_sync != null and is_instance_valid(contracts_sync):
		contracts_sync.shutdown()
	if boards_sync != null and is_instance_valid(boards_sync):
		boards_sync.shutdown()
	clear_avatars()
	if is_instance_valid(_me):
		_me.queue_free()


# Take the current world as the agreed starting point (nothing to send yet).
func rebaseline() -> void:
	if field != null:
		_hay_base = field.heights.duplicate()
	_hay_cand.clear()
	_bkeys = _scan_builds()
	_builds_dirty = false
	_st_base = _capture_state()
	_st_pending.clear()
	_pile_seed = GameState.run_seed
	_needles.clear()
	_holder.clear()
	for idx in _needle_bodies():
		_needles[idx] = "free"
	_frozen = false


# Put the local player where a new game starts (the save carries the host's
# spot). Each client gets a small sideways offset so nobody spawns inside
# someone else.
func place_at_spawn() -> void:
	if player == null or not is_instance_valid(player):
		return
	var consts: Dictionary = world.get_script().get_script_constant_map()
	var sp: Vector3 = consts.get("SPAWN_POS", Vector3(13.2, 0.4, 5.6))
	var slot: int = mp.players.keys().find(multiplayer.get_unique_id())
	sp += Vector3(0.0, 0.0, 0.9 * float(maxi(slot, 1)))
	var at: Vector3 = world._seat(sp) if world.has_method("_seat") else sp
	player.global_position = at
	player.look_at_from_position(at, Vector3(0, 3.0, 0), Vector3.UP)
	player.rotation = Vector3(0, player.rotation.y, 0)
	if player.has_method("set_look"):
		player.set_look(player.rotation.y, 0.0)
	player.velocity = Vector3.ZERO


func apply_session_rules() -> void:
	mp._mp_guard_online_services()
	mp.hold_profile()
	if props_sync != null and is_instance_valid(props_sync):
		props_sync.session_started()
	if not mp.is_host:
		SaveManager.block_save = true
		if "autosave_enabled" in world:
			world.autosave_enabled = false
		# needles that surface as the pile is dug are announced by the host;
		# letting both sides pop them out gives two bodies for one needle
		var live: Node = _live()
		if live != null and "expose_uncovered" in live:
			live.expose_uncovered = false
		_freeze_client_machines()


func _is_client() -> bool:
	return mp.active() and not mp.is_host


func _process(delta: float) -> void:
	if not mp.active() or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_pose_t += delta
	if _pose_t >= 1.0 / POSE_HZ:
		_pose_t = 0.0
		_send_pose()
	if _frozen:
		return
	if not _tech_queue.is_empty():
		_flush_tech()
	_hay_t += delta
	_hay_scan_t += delta
	if _hay_t >= HAY_TICK:
		_hay_t = 0.0
		var full := _hay_scan_t >= HAY_FULL_SCAN
		if full:
			_hay_scan_t = 0.0
		_hay_tick(full)
	_reconcile_t += delta
	if _reconcile_t >= RECONCILE_TICK:
		_reconcile_t = 0.0
		if mp.is_host and not _applying_builds and not _builds_dirty:
			var digest := _build_digest()
			for peer_id in mp.players:
				if peer_id != 1 and mp.players[peer_id].get("state") == "world":
					mp._rx_build_digest.rpc_id(peer_id, digest)
	_build_t += delta
	if _build_t >= BUILD_TICK:
		_build_t = 0.0
		_build_tick()
	_needle_t += delta
	if _needle_t >= 0.2:
		_needle_t = 0.0
		_needle_tick()
	_state_t += delta
	if _state_t >= STATE_TICK:
		_state_t = 0.0
		_mission_tick()
		_state_tick()
	if mp.is_host:
		_hay_sum_t += delta
		if _hay_sum_t >= HAY_SUM_TICK:
			_hay_sum_t = 0.0
			_send_hay_sums()


# ---------------------------------------------------------------- avatars

func _send_pose() -> void:
	if player == null or not is_instance_valid(player):
		return
	var pitch := 0.0
	var p: Variant = player.get("_pitch")
	if p != null:
		pitch = float(p)
	var crouch := 0.0
	if player.has_method("crouch_amount"):
		crouch = float(player.crouch_amount())
	var moving: float = (player.velocity * Vector3(1, 0, 1)).length() if "velocity" in player else 0.0
	mp._rx_pose.rpc(player.global_position, player.rotation.y, pitch,
		int(player.get("current_tool")), crouch, moving, _hands(), _tool_fill())


# What is in our bare hands, in one number: how many straws in the low four
# bits, and the type of needle plus one above that (0 for none). The full game
# has 24 needle types, so the needle part is read back without a 4-bit mask.
func _hands() -> int:
	var hand: Variant = player.get("hand")
	if hand == null or not is_instance_valid(hand):
		return 0
	var straws: int = clampi(int(hand.count()), 0, 15)
	var needle := 0
	if hand.has_method("held_needle_index"):
		var idx: int = int(hand.held_needle_index())
		if idx >= 0:
			needle = int(GameState.type_of(idx)) + 1
	return straws | (needle << 4)


func on_pose(id: int, pos: Vector3, yaw: float, pitch: float, tool: int, crouch: float, moving: float, hands: int = 0, tool_fill: float = 0.0) -> void:
	_last_at[id] = pos
	var a: Node = avatars.get(id)
	if a == null or not is_instance_valid(a):
		a = _avatar_script.new()
		a.setup(mp.player_name(id), mp.player_color(id))
		world.add_child(a)
		a.global_position = pos
		avatars[id] = a
	a.set_target(pos, yaw, pitch, tool, crouch, moving)
	a.set_tool_load(tool_fill)
	if a.has_method("set_hands"):
		a.set_hands(hands & 15, (hands >> 4) - 1)
	if strands_sync != null and is_instance_valid(strands_sync):
		# one straw is a straw; from two up the farmer holds a small ball of hay
		var straws: int = hands & 15
		strands_sync.set_hand(id, 0 if straws >= 2 else straws)


func remove_avatar(id: int) -> void:
	if strands_sync != null and is_instance_valid(strands_sync):
		strands_sync.drop_hand(id)
	var a: Node = avatars.get(id)
	if a != null and is_instance_valid(a):
		a.queue_free()
	avatars.erase(id)


func clear_avatars() -> void:
	for id in avatars.keys():
		remove_avatar(id)


func forget_peer(id: int) -> void:
	if is_instance_valid(economy):
		economy.peer_gone(id)
	if mp.is_host:
		_drop_needles_of(id)
	_last_at.erase(id)
	if props_sync != null and is_instance_valid(props_sync):
		props_sync.peer_gone(id)
	if strands_sync != null and is_instance_valid(strands_sync):
		strands_sync.peer_gone(id)
	_peer_ack.erase(id)


func avatar_positions() -> Dictionary:
	var out := {}
	for id in avatars:
		if is_instance_valid(avatars[id]):
			out[id] = avatars[id].global_position
	return out


# ---------------------------------------------------------------- hay

func _on_cells_redrawn(cells: PackedInt32Array) -> void:
	var nc: int = field.get("_nc")
	var nv: int = field.get("_nv")
	for gc in cells:
		var v := (gc / nc) * nv + (gc % nc)
		_hay_cand[v] = true
		_hay_cand[v + 1] = true
		_hay_cand[v + nv] = true
		_hay_cand[v + nv + 1] = true


func _hay_tick(full: bool) -> void:
	if field == null:
		return
	var h: PackedFloat32Array = field.heights
	if h.size() != _hay_base.size():
		_hay_base = h.duplicate()
		_hay_cand.clear()
		return
	var idx := PackedInt32Array()
	var vals := PackedFloat32Array()
	if full:
		for i in h.size():
			if absf(h[i] - _hay_base[i]) > HAY_EPS:
				idx.append(i)
				vals.append(h[i])
				_hay_base[i] = h[i]
	else:
		var n := h.size()
		for i in _hay_cand:
			if i < n and absf(h[i] - _hay_base[i]) > HAY_EPS:
				idx.append(i)
				vals.append(h[i])
				_hay_base[i] = h[i]
	_hay_cand.clear()
	var at := 0
	while at < idx.size():
		var end := mini(at + HAY_BATCH, idx.size())
		# The host owns the pile. A guest hands its digs to the host, which
		# settles them into its pile and sends the result to everybody; two
		# players' digs and slides used to overwrite each other for good.
		if mp.is_host:
			mp._rx_hay.rpc(idx.slice(at, end), vals.slice(at, end))
		else:
			mp._rx_hay.rpc_id(1, idx.slice(at, end), vals.slice(at, end))
		at = end


func on_hay(sender: int, idx: PackedInt32Array, vals: PackedFloat32Array) -> void:
	if field == null or _frozen:
		return
	field.settle_join()
	var h: PackedFloat32Array = field.heights
	var n := h.size()
	if _hay_base.size() != n:
		_hay_base = h.duplicate()
	var nv: int = field.get("_nv")
	# Host, digs from a guest: take them in as our own change, so our pile
	# settles around them and our next tick sends the result to everyone (the
	# guest included). Everyone else: the host's word is final, write it down
	# without settling it again.
	var from_guest: bool = mp.is_host and sender != 1 and sender != 0
	var touched := PackedInt32Array()
	for k in mini(idx.size(), vals.size()):
		var i := idx[k]
		if i < 0 or i >= n:
			continue
		h[i] = vals[k]
		if not from_guest:
			_hay_base[i] = vals[k]
		touched.append(i)
	field.heights = h
	for i in touched:
		if from_guest:
			field._touch_vertex(i % nv, i / nv)
		else:
			field._dirty_vertex_cells(i % nv, i / nv)


func _hay_blocks_per_side() -> int:
	var nv: int = field.get("_nv")
	return int(ceil(float(nv) / HAY_BLOCK))


func _hay_block_sums() -> PackedFloat32Array:
	var nv: int = field.get("_nv")
	var per := _hay_blocks_per_side()
	var sums := PackedFloat32Array()
	sums.resize(per * per)
	var h: PackedFloat32Array = field.heights
	for j in nv:
		var row := (j / HAY_BLOCK) * per
		var base := j * nv
		for i in nv:
			sums[row + i / HAY_BLOCK] += h[base + i]
	return sums


func _send_hay_sums() -> void:
	if field == null:
		return
	var sums := _hay_block_sums()
	for pid in mp.players.keys():
		if pid != 1 and str(mp.players[pid].get("state", "")) == "world":
			mp._rx_hay_sums.rpc_id(pid, sums)


# Guest: the host's checksums. Anything we dug since our last tick goes out
# first, on the same channel, so the host has it before it answers; then ask
# for every block that does not add up.
func on_hay_sums(sums: PackedFloat32Array) -> void:
	if field == null or _frozen or mp.is_host:
		return
	_hay_tick(false)
	var mine := _hay_block_sums()
	if mine.size() != sums.size():
		return
	var want := PackedInt32Array()
	for b in sums.size():
		if absf(mine[b] - sums[b]) > HAY_SUM_TOL:
			want.append(b)
	if not want.is_empty():
		mp._rx_hay_want.rpc_id(1, want)


# Host: send a guest the blocks it asked for, as they are here.
func on_hay_want(pid: int, blocks: PackedInt32Array) -> void:
	if field == null:
		return
	var nv: int = field.get("_nv")
	var per := _hay_blocks_per_side()
	var h: PackedFloat32Array = field.heights
	var idx := PackedInt32Array()
	var vals := PackedFloat32Array()
	for b in blocks:
		if b < 0 or b >= per * per:
			continue
		var j0 := (b / per) * HAY_BLOCK
		var i0 := (b % per) * HAY_BLOCK
		for j in range(j0, mini(j0 + HAY_BLOCK, nv)):
			for i in range(i0, mini(i0 + HAY_BLOCK, nv)):
				idx.append(j * nv + i)
				vals.append(h[j * nv + i])
	var at := 0
	while at < idx.size():
		var end := mini(at + HAY_BATCH, idx.size())
		mp._rx_hay.rpc_id(pid, idx.slice(at, end), vals.slice(at, end))
		at = end


# ---------------------------------------------------------------- buildings

func _on_builds_changed() -> void:
	if not _applying_builds:
		_builds_dirty = true
		_build_revision += 1
		_last_build_change = Time.get_ticks_msec()
		_mismatch_count = 0
	# a machine placed here would run on its own until the next build tick
	if _is_client():
		_freeze_client_machines.call_deferred()


func _bkey(d: Dictionary) -> String:
	var parts := [str(d.get("type", ""))]
	for k in ["position", "a", "b"]:
		if d.has(k):
			parts.append(_qv(d[k]))
	if d.has("yaw"):
		parts.append("%.5f" % wrapf(float(d["yaw"]), -PI, PI))
	for k in BUILD_SHAPE_KEYS:
		if d.has(k):
			parts.append("%s=%s" % [k, str(d[k])])
	return "|".join(parts)


func _qv(v: Variant) -> String:
	if v is Vector3:
		return "%.4f,%.4f,%.4f" % [v.x, v.y, v.z]
	return str(v)


func _scan_builds() -> Dictionary:
	var out := {}
	if builds == null:
		return out
	for d in builds.to_array():
		if d is Dictionary:
			out[_bkey(d)] = d
	return out


func _build_tick() -> void:
	if _applying_builds or not _builds_dirty:
		return
	_flush_builds()


func _flush_builds() -> void:
	_builds_dirty = false
	var cur := _scan_builds()
	var adds: Array = []
	var removes: Array = []
	for k in cur:
		if not _bkeys.has(k):
			adds.append(cur[k])
	for k in _bkeys:
		if not cur.has(k):
			removes.append(_bkeys[k])
	_bkeys = cur
	if (not adds.is_empty() or not removes.is_empty()) and mp.is_host:
		mp._rx_builds.rpc(adds, removes)
	if _is_client():
		_freeze_client_machines()


func on_builds(adds: Array, removes: Array) -> void:
	if builds == null or _frozen:
		return
	while _applying_builds:
		await get_tree().process_frame
	# anything we built locally goes out first so the rescan below can't swallow it
	if _builds_dirty:
		_flush_builds()
	_applying_builds = true
	adds = adds.duplicate()
	removes = removes.duplicate()
	if builds.has_method("_clear_mirrored_records"):
		builds._clear_mirrored_records()
	_apply_reversals(adds, removes)
	mp.trace.note("builds begin: %s added, %s removed" % [_types_of(adds), _types_of(removes)])
	for d in removes:
		if d is Dictionary:
			var n := _find_building(d)
			if n != null:
				_demolish(n)
	if not adds.is_empty():
		await _add_buildings(adds)
	builds.rebuild_junctions()
	builds.rebuild_water_joints()
	builds.fit_posts_to_decks()
	builds.share_joints()
	builds.changed.emit()
	_bkeys = _scan_builds()
	_builds_dirty = false
	_applying_builds = false
	mp.trace.note("builds end")
	if _is_client():
		_freeze_client_machines()


func _replace_build_script(script: Script) -> void:
	var values := {}
	for property in builds.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = builds.get(property.name)
	builds.set_script(script)
	for key in values:
		if key in builds:
			builds.set(key, values[key])


func _replace_mission_script(script: Script) -> void:
	var missions: Node = world.get("missions")
	var values := {}
	for property in missions.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = missions.get(property.name)
	missions.set_script(script)
	for key in values:
		if key in missions:
			missions.set(key, values[key])


func _mission_tick() -> void:
	var reached := mini(GameState.mission_index, MissionBook.count())
	if reached <= _mission_reported_index:
		return
	if _is_client():
		var completed := PackedStringArray()
		for index in range(_mission_reported_index, reached):
			completed.append(MissionBook.id_at(index))
		mp._rx_mission_done.rpc_id(1, completed)
	_mission_reported_index = reached


func on_mission_done(sender: int, completed: PackedStringArray) -> void:
	if not mp.is_host or not mp.players.has(sender):
		return
	var missions: Variant = world.get("missions")
	if not is_instance_valid(missions) or not ("remote_completed" in missions):
		return
	for id in completed:
		var index := MissionBook.index_of(id)
		if index >= GameState.mission_index and index < MissionBook.count():
			missions.remote_completed[id] = true


func _apply_reversals(adds: Array, removes: Array) -> void:
	for before in removes.duplicate():
		if not (before is Dictionary) or before.get("type") != "conveyor":
			continue
		for after in adds.duplicate():
			if not (after is Dictionary) or after.get("type") != "conveyor":
				continue
			if before.get("a") != after.get("b") or before.get("b") != after.get("a"):
				continue
			var node := _find_building(before)
			if node == null:
				break
			node.reverse()
			node.line_id = int(after.get("line", 0))
			if after.has("paid"):
				node.paid_cost = float(after["paid"])
			adds.erase(after)
			removes.erase(before)
			break


func _build_digest() -> int:
	var rows := PackedStringArray()
	if not is_instance_valid(builds):
		return 0
	for data in builds.to_array():
		rows.append(_bkey(data))
	for path in builds.conveyors + builds.corners:
		if not is_instance_valid(path) or not path.is_inside_tree():
			continue
		var points := PackedStringArray()
		for point in path._line:
			points.append(_qv(point))
		rows.append("path:" + ";".join(points))
	rows.sort()
	return hash(rows)


func on_build_digest(digest: int) -> void:
	if not _is_client() or _frozen or _applying_builds or _builds_dirty:
		return
	if digest == _build_digest():
		_mismatch_count = 0
		return
	_mismatch_count += 1
	var now := Time.get_ticks_msec()
	if _mismatch_count < 2 or now - _last_build_change < 2000 or now - _repair_requested_at < 5000:
		return
	_repair_requested_at = now
	mp._rx_build_repair_request.rpc_id(1, _build_revision)


func on_build_repair(host_builds: Array, revision: int) -> void:
	if not _is_client() or _frozen or _applying_builds or _builds_dirty or revision != _build_revision:
		return
	var want := {}
	for data in host_builds:
		if data is Dictionary:
			want[_bkey(data)] = data
	var have := _scan_builds()
	var adds: Array = []
	var removes: Array = []
	for key in want:
		if not have.has(key):
			adds.append(want[key])
	for key in have:
		if not want.has(key):
			removes.append(have[key])
	await on_builds(adds, removes)
	_mismatch_count = 0


func _types_of(dicts: Array) -> String:
	var out := PackedStringArray()
	for d in dicts:
		if d is Dictionary:
			out.append(str(d.get("type", "?")))
	return "[" + ",".join(out) + "]"


func _find_building(d: Dictionary) -> Node3D:
	var want := str(d.get("type", ""))
	var key := _bkey(d)
	for n in builds.every_placed():
		if not is_instance_valid(n) or n.is_queued_for_deletion() or not n.has_method("to_dict"):
			continue
		var nd: Dictionary = n.to_dict()
		if str(nd.get("type", "")) != want:
			continue
		if _bkey(nd) == key:
			return n
	return null


# Taking down the other player's demolition. Pulling down a free building (a
# pole, a rake or a cabinet a mission gave you) hands the gift back, and the
# game did that here as well as on their side, so every demolish made one more
# free building and a friend ended up with twenty poles. Whoever took it down
# gets it back; here it just goes.
func _demolish(n: Node3D) -> void:
	var gifts: Dictionary = GameState.gifts.duplicate()
	builds._demolish_one(n)
	if GameState.gifts != gifts:
		GameState.gifts = gifts
		GameState.gifts_changed.emit()


# Add buildings through the game's own loader without wiping the yard:
# from_array() starts with clear(), so the existing buildings are parked
# outside the manager's lists while it runs, then merged back. clear() also
# empties the demo's withheld buildings (they would drop out of the host's
# save) and frees the enclosed-conveyor shells, so those are parked too.
const BUILD_EXTRAS := ["demo_withheld"]


func _add_buildings(dicts: Array) -> void:
	var known := _scan_builds()
	var normal: Array = []
	var other: Array = []
	for d in dicts:
		if not (d is Dictionary) or known.has(_bkey(d)):
			continue
		known[_bkey(d)] = d
		if d.get("type", "") == "conveyor" and d.get("a") is Vector3 and d.get("b") is Vector3:
			normal.append(d)
		else:
			other.append(d)
	if not other.is_empty():
		await _restore_buildings(other)
	for d in normal:
		var belt: Node = builds.add_conveyor(d["a"], d["b"], int(d.get("line", 0)))
		if belt != null and d.has("paid"):
			belt.paid_cost = float(d["paid"])
	if not normal.is_empty():
		builds.rebuild_junctions()
		builds.share_joints()
		builds.changed.emit()


func _restore_buildings(dicts: Array) -> void:
	var parked := {}
	for a in BUILD_ARRAYS + BUILD_EXTRAS:
		var arr: Variant = builds.get(a)
		if arr is Array:
			parked[a] = arr.duplicate()
			arr.clear()
	var shells: Variant = builds.get("_enclosed_visuals")
	var shells_sig: Variant = builds.get("_enclosed_built")
	var on_show: Variant = builds.get("_enclosed_on_show")
	var on_show_kept: Dictionary = (on_show as Dictionary).duplicate() if on_show is Dictionary else {}
	if shells != null:
		# clear() frees whatever this points at; keep the node alive
		builds.set("_enclosed_visuals", null)
	var slice: int = builds.restore_slice_usec
	builds.restore_slice_usec = 0
	await builds.from_array(dicts)
	builds.restore_slice_usec = slice
	for a in parked:
		var arr: Array = builds.get(a)
		var fresh := arr.duplicate()
		arr.clear()
		arr.append_array(parked[a])
		arr.append_array(fresh)
	if shells != null and is_instance_valid(shells):
		var made: Variant = builds.get("_enclosed_visuals")
		if made != null and is_instance_valid(made) and made != shells:
			builds.remove_child(made)
			made.queue_free()
		builds.set("_enclosed_visuals", shells)
		if shells_sig != null:
			builds.set("_enclosed_built", shells_sig)
	if on_show is Dictionary:
		var now_show: Dictionary = builds.get("_enclosed_on_show")
		for k in on_show_kept:
			if not now_show.has(k):
				now_show[k] = on_show_kept[k]
	if builds.has_method("_rebuild_enclosed_visuals"):
		builds._rebuild_enclosed_visuals()
	builds.rebuild_junctions()
	builds.rebuild_water_joints()
	builds.fit_posts_to_decks()
	builds.share_joints()
	builds.changed.emit()


# Stopping a machine takes more than process_mode: the factory runs its
# machines from one static list (FactoryClock._tick_machines) and skips only
# the ones whose physics processing is off, so a "disabled" machine kept
# eating hay and spawning items while standing perfectly still. Clear both
# flags and the machine is really out of the loop; the host sends us how it
# moves instead.
func _freeze_client_machines() -> void:
	if builds == null:
		return
	for a in CLIENT_FROZEN:
		var arr: Variant = builds.get(a)
		if not (arr is Array):
			continue
		for n in arr:
			if not is_instance_valid(n) or n.has_meta("mp_stopped"):
				continue
			n.set_meta("mp_stopped", true)
			n.set_process(false)
			n.set_physics_process(false)
			# Not process_mode: a disabled node takes its collision body out of
			# the world (CollisionObject3D.disable_mode) and its particles stop
			# emitting, so the machine turned into a hole you walk through with
			# no smoke and no fire.
			if n.process_mode == Node.PROCESS_MODE_DISABLED:
				n.process_mode = Node.PROCESS_MODE_INHERIT
			_still_animations(n)


# Their clips would otherwise hold whatever frame they stopped on, or keep
# looping, and fight the poses coming from the host.
func _still_animations(n: Node) -> void:
	for child in n.get_children():
		if child is AnimationPlayer:
			(child as AnimationPlayer).pause()
			child.process_mode = Node.PROCESS_MODE_DISABLED
		_still_animations(child)


# ---------------------------------------------------------------- shared game state

func _capture_state() -> Dictionary:
	var s := {}
	for f in ADD_F:
		s[f] = GameState.get(f)
	for a in ADD_A + OR_A:
		var v: Variant = GameState.get(a)
		s[a] = v.duplicate() if v != null else null
	return s


func _state_tick() -> void:
	if mp.is_host:
		var snap := _capture_state()
		for f in HOST_ABS + HOST_MAX:
			snap[f] = GameState.get(f)
		for pid in mp.players.keys():
			if pid != 1 and str(mp.players[pid].get("state", "")) == "world":
				mp._rx_state_snap.rpc_id(pid, int(_peer_ack.get(pid, 0)), snap)
		return
	var cur := _capture_state()
	var delta := {}
	for f in ADD_F:
		var d: float = float(cur[f]) - float(_st_base[f])
		if absf(d) > 1e-6:
			delta[f] = d
	for a in ADD_A:
		var c: Variant = cur[a]
		var b: Variant = _st_base[a]
		if c == null or b == null or c.size() != b.size():
			continue
		var diff := PackedInt32Array()
		diff.resize(c.size())
		var any := false
		for i in c.size():
			diff[i] = c[i] - b[i]
			any = any or diff[i] != 0
		if any:
			delta[a] = diff
	for a in OR_A:
		var c: Variant = cur[a]
		var b: Variant = _st_base[a]
		if c == null or b == null or c.size() != b.size():
			continue
		var bits := PackedInt32Array()
		for i in c.size():
			if c[i] != 0 and b[i] == 0:
				bits.append(i)
		if not bits.is_empty():
			delta[a] = bits
	_st_base = cur
	if delta.is_empty():
		return
	_seq += 1
	_st_pending.append([_seq, delta])
	mp._rx_state_delta.rpc_id(1, _seq, delta)


func on_state_delta(pid: int, seq: int, delta: Dictionary) -> void:
	if seq <= int(_peer_ack.get(pid, 0)):
		return
	var before := _capture_state()
	for f in ADD_F:
		if delta.has(f):
			_set_typed(f, float(GameState.get(f)) + float(delta[f]))
	for a in ADD_A:
		if delta.has(a):
			var arr: Variant = GameState.get(a)
			var d: PackedInt32Array = delta[a]
			if arr != null and arr.size() == d.size():
				for i in d.size():
					arr[i] = maxi(0, arr[i] + d[i])
				GameState.set(a, arr)
	for a in OR_A:
		if delta.has(a):
			var arr: Variant = GameState.get(a)
			if arr != null:
				for i in delta[a]:
					if i >= 0 and i < arr.size():
						arr[i] = 1
				GameState.set(a, arr)
	_peer_ack[pid] = seq
	_emit_state_signals(before)


func on_state_snap(ack: int, snap: Dictionary) -> void:
	if mp.is_host:
		return
	while not _st_pending.is_empty() and int(_st_pending[0][0]) <= ack:
		_st_pending.pop_front()
	var pend := {}
	for entry in _st_pending:
		var d: Dictionary = entry[1]
		for f in d:
			if f in ADD_F:
				pend[f] = float(pend.get(f, 0.0)) + float(d[f])
			elif f in ADD_A:
				if not pend.has(f):
					pend[f] = d[f].duplicate()
				elif pend[f].size() == d[f].size():
					for i in d[f].size():
						pend[f][i] += d[f][i]
			elif f in OR_A:
				if not pend.has(f):
					pend[f] = PackedInt32Array()
				pend[f].append_array(d[f])
	var before := _capture_state()
	var cur := before
	for f in ADD_F:
		if not snap.has(f):
			continue
		var unsent: float = float(cur[f]) - float(_st_base[f])
		var nb: float = float(snap[f]) + float(pend.get(f, 0.0))
		_st_base[f] = nb
		_set_typed(f, nb + unsent)
	for a in ADD_A:
		if not snap.has(a) or snap[a] == null:
			continue
		var s: PackedInt32Array = snap[a]
		var c: Variant = cur[a]
		var b: Variant = _st_base[a]
		if c == null or b == null or c.size() != s.size() or b.size() != s.size():
			GameState.set(a, s.duplicate())
			_st_base[a] = s.duplicate()
			continue
		var p: Variant = pend.get(a)
		var nb := s.duplicate()
		var nv := s.duplicate()
		for i in s.size():
			var pi: int = p[i] if p != null and p.size() == s.size() else 0
			nb[i] = s[i] + pi
			nv[i] = nb[i] + (c[i] - b[i])
		_st_base[a] = nb
		GameState.set(a, nv)
	for a in OR_A:
		if not snap.has(a) or snap[a] == null:
			continue
		var s: PackedByteArray = snap[a]
		var c: Variant = cur[a]
		if c == null or c.size() != s.size():
			GameState.set(a, s.duplicate())
			_st_base[a] = s.duplicate()
			continue
		var nb := s.duplicate()
		for i in pend.get(a, PackedInt32Array()):
			if i >= 0 and i < nb.size():
				nb[i] = 1
		var nv := nb.duplicate()
		for i in s.size():
			if c[i] != 0:
				nv[i] = 1
		_st_base[a] = nb
		GameState.set(a, nv)
	for f in HOST_ABS:
		if snap.has(f) and snap[f] != null:
			GameState.set(f, snap[f])
	if snap.has("mission_index"):
		_mission_reported_index = maxi(_mission_reported_index, int(snap["mission_index"]))
	for f in HOST_MAX:
		if snap.has(f):
			GameState.set(f, maxi(int(GameState.get(f)), int(snap[f])))
	_emit_state_signals(before)


func _set_typed(f: String, v: float) -> void:
	var cur: Variant = GameState.get(f)
	if typeof(cur) == TYPE_INT:
		GameState.set(f, int(round(v)))
	else:
		GameState.set(f, v)


func _emit_state_signals(before: Dictionary) -> void:
	if not is_equal_approx(float(before["money"]), float(GameState.money)):
		GameState.money_changed.emit(GameState.money)
	if not is_equal_approx(float(before["debt"]), float(GameState.debt)):
		GameState.debt_changed.emit(GameState.debt)
	if not is_equal_approx(float(before["hay_total"]), float(GameState.hay_total)) \
	or not is_equal_approx(float(before["hay_dug"]), float(GameState.hay_dug)):
		GameState.set("_hay_dirty", true)
		GameState.hay_changed.emit(GameState.hay_total, GameState.hay_dug)
	if not is_equal_approx(float(before["hay_sold"]), float(GameState.hay_sold)):
		GameState.hay_sold_changed.emit(GameState.hay_sold)
	var bs: Variant = before["needle_stock"]
	var ns: PackedInt32Array = GameState.needle_stock
	if bs != null and bs.size() == ns.size():
		for t in ns.size():
			if bs[t] != ns[t]:
				GameState.needle_stock_changed.emit(t, ns[t])
	var bd: Variant = before["discovered"]
	var nd: PackedByteArray = GameState.discovered
	if bd != null and bd.size() == nd.size():
		var at: Vector3 = player.global_position if player != null and is_instance_valid(player) else Vector3.ZERO
		for t in nd.size():
			if bd[t] == 0 and nd[t] != 0:
				GameState.needle_discovered.emit(t, at)


# ---------------------------------------------------------------- tech tree

# Tech.buy() changes the rank first and records the purchase right after, and
# a grant (bundled cards, rewards) never records one. So collect this frame's
# changes and send them at the end of it, marked bought or granted.
func _on_tech_changed(id: String, rank: int) -> void:
	if _tech_mute or not mp.active() or _frozen:
		return
	_tech_queue[id] = rank


func _on_purchased(kind: String, id: String) -> void:
	if kind == "card":
		_tech_paid[id] = true


func _flush_tech() -> void:
	for id in _tech_queue:
		mp._rx_tech.rpc(String(id), int(_tech_queue[id]), bool(_tech_paid.get(id, false)))
	_tech_queue.clear()
	_tech_paid.clear()


func on_tech(sender: int, id: String, rank: int, paid: bool = false) -> void:
	var have := int(Tech.ranks.get(id, 0))
	if rank > 0 and rank <= have:
		# Two players bought the same rank at once and both paid for it. The
		# host puts the second payment back into the shared money.
		if mp.is_host and paid and sender != 1:
			var cost := float(TechTree.cost_at(id, rank - 1))
			if cost > 0.0:
				tech_refunds += 1
				GameState.money += cost
				GameState.money_changed.emit(GameState.money)
				print("[MPMod] %s rank %d was bought twice, refunded %.0f" % [id, rank, cost])
		return
	_tech_mute = true
	if rank <= 0:
		Tech.ranks.erase(id)
	else:
		Tech.ranks[id] = rank
	Tech.tech_changed.emit(id, rank)
	_tech_mute = false


# ---------------------------------------------------------------- full sync / pile swaps

# The host's world in the same shape SaveManager writes to disk, so a client
# can drop it into a scratch slot and load it with the game's own loader.
func build_payload(pid: int) -> Dictionary:
	if pid != 1:
		props_sync.retire_equipped_tools(pid)
	var xf: Transform3D = player.global_transform
	xf.origin += xf.basis.x * 1.2 + Vector3.UP * 0.2
	var props_arr: Array = []
	var props: Variant = world.get("props")
	if props != null and props.has_method("to_array"):
		props_arr = props.to_array()
	var belts: Dictionary = {}
	if world.has_method("_belts_to_dict"):
		belts = world._belts_to_dict()
	var out := {
		"version": SaveManager.FORMAT_VERSION,
		"pile_shape_version": SaveManager.current_pile_shape_version,
		"state": GameState.to_dict(),
		"heights": field.heights,
		"player": xf,
		"buildings": builds.to_array(),
		"props": props_arr,
		"belts": belts,
		"tech": Tech.to_dict(),
		"cell": Cfg.CELL,
		"extent": Cfg.FIELD_EXTENT,
		"meta": {
			"name": "Multijugador",
			"locked": false,
			"map": SaveManager.current_map,
			"pile_size": SaveManager.current_pile_size,
			"saved_at": int(Time.get_unix_time_from_system()),
			"hay_dug": GameState.hay_dug,
			"hay_initial": GameState.hay_initial,
			"hay_total": GameState.hay_total,
			"needles_found": GameState.needles_found,
			"money": GameState.money,
			"money_earned": GameState.money_earned,
		},
	}
	out.state["owned_tools"] = tools_sync.inventory_for(pid).keys()
	out.state.erase("mp_personal_tools")
	# the pile's starting shape: without it the guest re-shapes the dome from
	# the seed, which is slow and not what the host's pile was dug from
	var dome: Variant = field.get("dome")
	if dome is PackedFloat32Array and (dome as PackedFloat32Array).size() == field.heights.size():
		out["dome"] = dome
		out["dome_seed"] = int(field.get("dome_seed"))
	var meta: Dictionary = out["meta"]
	for key in CFG_META:
		# null when this build of the game does not have the setting
		var v: Variant = Cfg.get(key)
		if v != null:
			meta[CFG_META[key]] = v
	return out


func send_full_sync(pid: int) -> void:
	if is_instance_valid(economy):
		economy.publish(pid)
	if is_instance_valid(tools_sync):
		tools_sync.send_all(pid)
	# loose needles the late joiner missed: [index, position, who holds it]
	var needles: Array = []
	var bodies := _needle_bodies()
	for idx in bodies:
		needles.append([idx, bodies[idx].global_position, _holder_of(idx)])
	for idx in _holder:
		if not bodies.has(idx):
			needles.append([idx, Vector3.ZERO, int(_holder[idx])])
	mp._rx_full_sync.rpc_id(pid, field.heights, builds.to_array(), Tech.to_dict(), needles)
	if props_sync != null and is_instance_valid(props_sync):
		props_sync.send_all(pid)
	if belts_sync != null and is_instance_valid(belts_sync):
		belts_sync.send_all(pid)
	if boards_sync != null and is_instance_valid(boards_sync):
		boards_sync.send_all(pid)
	if machines_sync != null and is_instance_valid(machines_sync):
		machines_sync.send_all(pid)


func on_full_sync(heights: PackedFloat32Array, host_builds: Array, tech: Dictionary, needles: Array = []) -> void:
	# what we spent or earned since the last state tick goes out now: the
	# rebaseline at the end of this used to drop it on the floor
	if _is_client():
		_state_tick()
	for n in needles:
		var holder := int(n[2])
		on_needle("claim" if holder != 0 else "spawn", int(n[0]), n[1], holder)
	if field != null and heights.size() == field.heights.size():
		var idx := PackedInt32Array()
		var vals := PackedFloat32Array()
		var h: PackedFloat32Array = field.heights
		for i in heights.size():
			if absf(heights[i] - h[i]) > HAY_EPS:
				idx.append(i)
				vals.append(heights[i])
		if not idx.is_empty():
			on_hay(1, idx, vals)
		_hay_base = field.heights.duplicate()
	if builds != null:
		var want := {}
		for d in host_builds:
			if d is Dictionary:
				want[_bkey(d)] = d
		var have := _scan_builds()
		var adds: Array = []
		var removes: Array = []
		for k in want:
			if not have.has(k):
				adds.append(want[k])
		for k in have:
			if not want.has(k):
				removes.append(have[k])
		if not adds.is_empty() or not removes.is_empty():
			_builds_dirty = false
			await on_builds(adds, removes)
		_bkeys = _scan_builds()
	_tech_mute = true
	Tech.from_dict(tech)
	_tech_mute = false
	_st_base = _capture_state()


func _on_pile_replaced() -> void:
	if not mp.active():
		_pile_seed = GameState.run_seed
		return
	if mp.is_host:
		_frozen = true
		mp.ui.notify(mp.t("new_pile_host"))
		await get_tree().create_timer(1.5).timeout
		if not is_inside_tree():
			return
		rebaseline()
		mp.resync_all()
	else:
		# We just paid for the load. Get that out before freezing stops the
		# state tick, or the host undoes its own charge expecting ours and the
		# pile ends up free for everyone. Say how we paid, so the host can put
		# it back if it cannot take a new load after all.
		var on_credit: bool = float(GameState.debt) > float(_st_base.get("debt", 0.0)) + 0.5
		_state_tick()
		_frozen = true
		# the host owns the pile; ask it to swap its pile, it will send us the result
		mp.ui.notify(mp.t("new_pile_client"))
		mp._rx_new_pile_request.rpc_id(1, on_credit)


func host_new_pile_for_client(pid: int, on_credit: bool = false) -> void:
	# The client already paid on its side (that arrives as a state delta),
	# so undo the host-side charge of the delivery.
	var money: float = GameState.money
	var debt: float = GameState.debt
	var stacks: int = GameState.stacks_ordered
	var seed_before := GameState.run_seed
	if world.has_method("_deliver_new_pile"):
		world._deliver_new_pile(false)
	GameState.money = money
	GameState.debt = debt
	GameState.stacks_ordered = stacks
	GameState.money_changed.emit(money)
	GameState.debt_changed.emit(debt)
	if GameState.run_seed == seed_before:
		# The host could not take a new load right now (the landing spot is
		# blocked, or no load may be ordered). The guest's payment already came
		# in with its state delta: give it back, then put the guest back.
		if GameState.stacks_ordered > 0:
			GameState.stacks_ordered -= 1
			if on_credit:
				GameState.debt = maxf(0.0, GameState.debt - GameState.credit_stack_fee())
				GameState.debt_changed.emit(GameState.debt)
			else:
				GameState.money += GameState.next_stack_fee()
				GameState.money_changed.emit(GameState.money)
		mp.send_world(pid)


# ---------------------------------------------------------------- loose needles
# Uncovered needles are physics bodies in LiveStrandManager.needles, tagged
# with meta "needle_index". Everyone sees a needle once someone uncovers it;
# picking it up claims it (it vanishes for the others) so it can only be
# handed in once. States per index: "free" (lying here), "held" (in our hand),
# "away" (someone else is holding it).

func _live() -> Node:
	return world.get("live")


func _needle_bodies() -> Dictionary:
	var out := {}
	var live := _live()
	if live == null:
		return out
	for b in live.get("needles"):
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			var idx := int(b.get_meta("needle_index", -1))
			if idx >= 0:
				out[idx] = b
	return out


func _held_needle() -> int:
	var hand: Variant = player.get("hand") if player != null and is_instance_valid(player) else null
	if hand != null and is_instance_valid(hand) and hand.has_method("held_needle_index"):
		return int(hand.held_needle_index())
	return -1


func _needle_tick() -> void:
	var cur := _needle_bodies()
	var held := _held_needle()
	for idx in cur:
		var st: String = _needles.get(idx, "")
		if st == "away":
			continue
		if st == "":
			# a new needle here: the host's own pile uncovered it, or one of our
			# tools lifted it out (the shovel does); either way everyone sees it
			_needles[idx] = "free"
			st = "free"
			if mp.is_host:
				_needle_out("spawn", idx, cur[idx].global_position, 0)
			else:
				mp._rx_needle_req.rpc_id(1, "spawn", idx, cur[idx].global_position)
		if idx == held and st == "free":
			_needles[idx] = "held"
			_needle_claim(idx)
		elif idx != held and st == "held":
			_needles[idx] = "free"
			if mp.is_host:
				_holder.erase(idx)
				_needle_out("spawn", idx, cur[idx].global_position, 0)
			else:
				mp._rx_needle_req.rpc_id(1, "drop", idx, cur[idx].global_position)
	for idx in _needles.keys():
		if _needles[idx] == "away" or cur.has(idx):
			continue
		var was: String = _needles[idx]
		_needles.erase(idx)
		if mp.is_host:
			# the host's copy is the one that counts
			_holder.erase(idx)
			_needle_out("gone", idx, Vector3.ZERO, 0)
		elif was == "held":
			# ours, and we used it up (handed it in)
			mp._rx_needle_req.rpc_id(1, "gone", idx, Vector3.ZERO)
		else:
			# a loose needle vanished here only (our physics lost it): that is
			# no reason to take it off everybody, ask the host where it is
			mp._rx_needle_req.rpc_id(1, "want", idx, Vector3.ZERO)


func _holder_of(idx: int) -> int:
	if _holder.has(idx):
		return int(_holder[idx])
	return 1 if mp.is_host and idx == _held_needle() else 0


func _needle_out(kind: String, idx: int, pos: Vector3, holder: int) -> void:
	mp._rx_needle.rpc(kind, idx, pos, holder)


# We picked a needle up. The host decides: first come, first served.
func _needle_claim(idx: int) -> void:
	if not mp.is_host:
		mp._rx_needle_req.rpc_id(1, "claim", idx, Vector3.ZERO)
		return
	var h := int(_holder.get(idx, 0))
	if h != 0 and h != 1:
		# a guest's claim got here first: it is theirs
		_apply_needle("claim", idx, Vector3.ZERO, h)
		return
	_holder[idx] = 1
	_needle_out("claim", idx, Vector3.ZERO, 1)


# Host: what a guest says happened to a needle.
func on_needle_req(sender: int, kind: String, idx: int, pos: Vector3) -> void:
	if _frozen or idx < 0:
		return
	var h := _holder_of(idx)
	match kind:
		"claim":
			if h != 0 and h != sender:
				# somebody else has it: tell the guest who, so it lets go
				mp._rx_needle.rpc_id(sender, "claim", idx, Vector3.ZERO, h)
				return
			_holder[idx] = sender
			_apply_needle("claim", idx, Vector3.ZERO, sender)
			_needle_out("claim", idx, Vector3.ZERO, sender)
		"drop":
			if h != sender:
				return
			_holder.erase(idx)
			_apply_needle("spawn", idx, pos, 0)
			_needle_out("spawn", idx, pos, 0)
		"gone":
			if h != sender and h != 0:
				return
			_holder.erase(idx)
			_apply_needle("gone", idx, Vector3.ZERO, 0)
			_needle_out("gone", idx, Vector3.ZERO, 0)
		"spawn":
			if h != 0 or _needle_bodies().has(idx):
				return
			_apply_needle("spawn", idx, pos, 0)
			_needle_out("spawn", idx, pos, 0)
		"want":
			var body: Variant = _needle_bodies().get(idx)
			if h != 0:
				mp._rx_needle.rpc_id(sender, "claim", idx, Vector3.ZERO, h)
			elif body != null:
				mp._rx_needle.rpc_id(sender, "spawn", idx, (body as Node3D).global_position, 0)
			else:
				mp._rx_needle.rpc_id(sender, "gone", idx, Vector3.ZERO, 0)


func on_needle(kind: String, idx: int, pos: Vector3, holder: int = 0) -> void:
	if _frozen:
		return
	_apply_needle(kind, idx, pos, holder)


func _apply_needle(kind: String, idx: int, pos: Vector3, holder: int) -> void:
	var live := _live()
	if live == null:
		return
	var me := multiplayer.get_unique_id()
	var body: RigidBody3D = _needle_bodies().get(idx)
	match kind:
		"spawn":
			if idx == _held_needle():
				return  # our claim is on its way; the host will settle it
			if body != null:
				body.global_position = pos
				body.linear_velocity = Vector3.ZERO
			else:
				live.reveal_needle(idx, pos)
			_needles[idx] = "free"
		"claim":
			if holder == me:
				_needles[idx] = "held"
				return
			# someone else holds it. If we grabbed it too, we were second: it
			# leaves our hand as well, so it can only be handed in once
			if body != null:
				live.consume_needle(body)
			_needles[idx] = "away"
		"gone":
			if body != null:
				live.consume_needle(body)
			_needles.erase(idx)


# A guest left while holding a needle: put it down where they were standing, so
# it is not lost to everybody.
func _drop_needles_of(pid: int) -> void:
	for idx in _holder.keys():
		if int(_holder[idx]) != pid:
			continue
		_holder.erase(idx)
		# the avatar is already gone by now, so use the last pose we had
		var at: Vector3 = GameState.needle_positions[idx] if idx < GameState.needle_positions.size() else Vector3.ZERO
		if _last_at.has(pid):
			at = (_last_at[pid] as Vector3) + Vector3.UP * 0.4
		_apply_needle("spawn", idx, at, 0)
		_needle_out("spawn", idx, at, 0)


# ---------------------------------------------------------------- events / toasts

func _on_needle_found(_index: int, _pos: Vector3) -> void:
	if mp.active() and not _frozen:
		mp._rx_event.rpc("needle", {})


func _on_needle_discovered(type: int, _pos: Vector3) -> void:
	pass


func on_event(id: int, kind: String, _data: Dictionary) -> void:
	match kind:
		"needle":
			toast(mp.t("needle_found") % mp.player_name(id))


func toast(text: String, seconds: float = 3.5) -> void:
	var hud: Variant = world.get("hud")
	if hud != null and is_instance_valid(hud) and hud.has_method("show_toast"):
		hud.show_toast(text, seconds)
	else:
		mp.ui.notify(text)


func _replace_tech_script(script: Script) -> void:
	var values := {}
	for property in Tech.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = Tech.get(property.name)
	Tech.set_script(script)
	for key in values:
		if key in Tech:
			Tech.set(key, values[key])

func on_tech_purchase(sender: int, id: String, expected_rank: int) -> void:
	if not mp.is_host or not mp.players.has(sender):
		return
	var current := int(Tech.ranks.get(id, 0))
	var accepted := false
	if current == expected_rank:
		accepted = Tech.buy(id)
	elif current > expected_rank:
		accepted = true
	mp._rx_tech_purchase_result.rpc_id(sender, id, accepted)
	_state_tick()

func on_tech_purchase_result(id: String, accepted: bool) -> void:
	if "pending" in Tech:
		Tech.get("pending").erase(id)
	if not accepted:
		mp.ui.notify(mp.t("purchase_declined"))


func _tool_fill() -> float:
	var tool: Node
	match int(player.current_tool):
		1, 4: tool = player.shovel
		2: tool = player.pitchfork
	if is_instance_valid(tool) and tool.has_method("fill_fraction"):
		return clampf(float(tool.fill_fraction()), 0.0, 1.0)
	return 0.0
