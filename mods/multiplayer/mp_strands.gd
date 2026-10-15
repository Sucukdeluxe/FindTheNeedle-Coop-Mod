extends Node

# Loose straw.
#
# Every player's dig throws hundreds of straws around, and until now each
# player only saw their own: the floor was covered on one screen and clean on
# the other. The peer that made a straw sends where it is; everyone else keeps
# a copy of it.
#
# The copies are the game's own "visual only" straws: no collision, no physics
# body, drawn by the same multimesh as the real ones. They cannot be picked up
# or swept, so nobody can turn one straw into two loads of hay. Straws that
# have come to rest stop costing anything, since their pose never changes
# again, and nothing is sent about straws too far from anyone else to see.

const SCAN_TICK := 0.1
const MOVE_TICK := 0.1
const CENSUS_TICK := 5.0
const RANGE := 26.0        # what a remote player could see, Cfg.STRAND_DESPAWN_DIST
const MOVE_EPS := 0.004
const ADD_BUDGET := 80
const MOVE_BUDGET := 120
const MINE_CAP := 400      # never track more of our own than this
const MAX_RAW := 4 << 20

var mp: Node
var world: Node
var live: Node
var _live_script: Script

var _mine := {}      # sid -> body we own
var _ghost := {}     # sid -> our copy of somebody else's straw
var _sent := {}      # sid -> last transform broadcast
var _owner := {}     # sid -> peer, for ghosts
var _goal := {}      # sid -> where a copy is heading, eased so it does not jump
var _next := 0
var _pose_sequence := 0
var _received_pose := {}
var _watched := {}   # instance id -> true, bodies whose tree_exiting we listen to
var _scan_t := 0.0
var _move_t := 0.0
var _census_t := 0.0


func start(mp_node: Node, world_node: Node) -> void:
	mp = mp_node
	world = world_node
	live = world.get("live")
	if is_instance_valid(live):
		_live_script = live.get_script()
		_replace_live_script(load(mp.base_dir + "/mp_live_strand_manager.gd"))
		live.set("mp_strands", self)


func shutdown() -> void:
	if is_instance_valid(live) and _live_script != null:
		_replace_live_script(_live_script)
		_live_script = null
	for sid in _ghost:
		var b: Variant = _ghost[sid]
		if b != null and is_instance_valid(b) and live != null:
			_revive(b)
			live.consume(b)
	_ghost.clear()
	for pid in _hands:
		for b in _hands[pid]:
			if b != null and is_instance_valid(b) and live != null:
				_revive(b)
				live.consume(b)
	_hands.clear()
	_mine.clear()
	_sent.clear()
	_owner.clear()
	_received_pose.clear()


func _me() -> int:
	return multiplayer.get_unique_id()


# The game keeps its straw bodies in a pool: a straw that is used up (a bucket
# scoops it, the vac takes it, it rides off on a belt) leaves the tree and the
# same body comes back later as some other straw. We held on to it and kept
# moving it, read its position out of the tree, and in the end handed it back
# to the pool again while something else was using it: a belt, a hand, a
# machine. That is the crash guests got while the host was building. So let go
# of a body the moment it leaves, whoever took it.
func _watch(b: Node) -> void:
	var id := b.get_instance_id()
	if _watched.has(id):
		return
	_watched[id] = true
	b.tree_exiting.connect(_on_body_left.bind(b))


func _on_body_left(b: Node) -> void:
	if not is_instance_valid(b):
		return
	var gid := int(b.get_meta("mp_gid", 0))
	if gid != 0 and _ghost.get(gid) == b:
		_ghost.erase(gid)
		_goal.erase(gid)
		_owner.erase(gid)
		_received_pose.erase(gid)
	var sid := int(b.get_meta("mp_sid", 0))
	if sid != 0 and _mine.get(sid) == b:
		_mine.erase(sid)
		_sent.erase(sid)
		if mp != null and mp.active() and multiplayer.multiplayer_peer != null:
			mp._rx_straw_del.rpc(PackedInt64Array([sid]), mp._outgoing_world_seed())
	for pid in _hands:
		(_hands[pid] as Array).erase(b)
	# the pool does not clear what we put on it, and the next straw made from
	# this body is nobody's copy
	for key in ["mp_ghost", "mp_gid", "mp_sid"]:
		if b.has_meta(key):
			b.remove_meta(key)


func _new_sid() -> int:
	_next += 1
	return _me() * 1000000 + _next


# ------------------------------------------------------------------ ticks

func _process(delta: float) -> void:
	if live == null or not is_instance_valid(live):
		return
	# keeps following the fist even if the link hiccups
	_park_hands()
	_ease(delta)
	_watch_hand()
	if mp == null or not mp.active() or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_scan_t += delta
	if _scan_t >= SCAN_TICK:
		_scan_t = 0.0
		_scan()
	_move_t += delta
	if _move_t >= MOVE_TICK:
		_move_t = 0.0
		_send_moves()
	_census_t += delta
	if _census_t >= CENSUS_TICK:
		_census_t = 0.0
		_census()


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


# Pick up straws that are ours and close enough to somebody else to matter,
# and let go of the ones that are gone or out of everyone's sight.
func _scan() -> void:
	var watchers := _watchers()
	var active: Variant = live.get("_active")
	if not (active is Array):
		return
	var adds: Array = []
	var seen := {}
	if not watchers.is_empty():
		for b in active:
			if b == null or not is_instance_valid(b):
				continue
			if b.has_meta("mp_ghost") or b.has_meta("needle_index"):
				continue
			# straw in a hand, a bucket or on a tool travels with whatever
			# holds it, so it is not ours to scatter on the floor
			if bool(b.get_meta("protected", false)):
				var held_sid := int(b.get_meta("mp_sid", 0))
				if held_sid != 0 and _mine.get(held_sid) == b:
					seen[held_sid] = true
				continue
			var body := b as Node3D
			if not body.is_inside_tree() or not _near(body.global_position, watchers):
				continue
			var sid := int(b.get_meta("mp_sid", 0))
			if sid != 0 and _mine.get(sid) == b:
				seen[sid] = true
				continue
			if _mine.size() >= MINE_CAP or adds.size() >= ADD_BUDGET:
				continue
			sid = _new_sid()
			b.set_meta("mp_sid", sid)
			_mine[sid] = b
			_watch(b)
			seen[sid] = true
			_sent[sid] = body.global_transform
			adds.append([sid, body.global_transform,
				b.get_meta("tint", Color(1, 1, 1))])
	var drop := PackedInt64Array()
	for sid in _mine.keys():
		if seen.has(sid):
			continue
		var b: Variant = _mine[sid]
		if is_instance_valid(b) and b.is_inside_tree() and bool(b.get_meta("protected", false)):
			continue
		_mine.erase(sid)
		_sent.erase(sid)
		if b != null and is_instance_valid(b):
			b.remove_meta("mp_sid")
		drop.append(sid)
	if not adds.is_empty():
		mp._rx_straw_add.rpc(adds, mp._outgoing_world_seed())
	if drop.size() > 0:
		mp._rx_straw_del.rpc(drop, mp._outgoing_world_seed())


func register_loaded(body: RigidBody3D) -> int:
	if not is_instance_valid(body) or not body.is_inside_tree() or body.get_parent() != live or not live._active.has(body) or body.has_meta("needle_index") or body.has_meta("mp_ghost"):
		return 0
	var sid := int(body.get_meta("mp_sid", 0))
	if sid > 0 and _mine.get(sid) == body and int(sid / 1000000) == _me():
		return sid
	if _mine.get(sid) == body:
		_mine.erase(sid)
		_sent.erase(sid)
	if _mine.size() >= MINE_CAP:
		return 0
	sid = _new_sid()
	body.set_meta("mp_sid", sid)
	_mine[sid] = body
	_watch(body)
	_sent[sid] = body.global_transform
	mp._rx_straw_add.rpc([[sid, body.global_transform, body.get_meta("tint", Color(1, 1, 1))]], mp._outgoing_world_seed())
	return sid

func _send_moves() -> void:
	if _mine.is_empty():
		return
	var ids := PackedInt64Array()
	var rows := PackedFloat32Array()
	for sid in _mine:
		var b: Variant = _mine[sid]
		if b == null or not is_instance_valid(b) or not (b as Node3D).is_inside_tree():
			continue
		var xf: Transform3D = (b as Node3D).global_transform
		var was: Variant = _sent.get(sid)
		if was != null and (was as Transform3D).origin.distance_squared_to(xf.origin) < MOVE_EPS * MOVE_EPS:
			continue
		_sent[sid] = xf
		ids.append(sid)
		var q := xf.basis.get_rotation_quaternion()
		rows.append_array(PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z,
			q.x, q.y, q.z, q.w]))
		if ids.size() >= MOVE_BUDGET:
			break
	if ids.size() > 0:
		_pose_sequence += 1
		mp._rx_straw_move.rpc(ids, rows, _pose_sequence, mp._outgoing_world_seed())


func _census() -> void:
	var ids := PackedInt64Array()
	var rows := PackedFloat32Array()
	for sid in _mine:
		var b: Variant = _mine[sid]
		if not is_instance_valid(b) or not b.is_inside_tree():
			continue
		var xf: Transform3D = b.global_transform
		var q := xf.basis.get_rotation_quaternion()
		ids.append(sid)
		rows.append_array(PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z,
			q.x, q.y, q.z, q.w]))
	_pose_sequence += 1
	mp._rx_straw_census.rpc(ids, rows, _pose_sequence, mp._outgoing_world_seed())


# ------------------------------------------------------------------ from the net

func on_add(sender: int, adds: Array) -> void:
	if sender <= 0 or live == null or not is_instance_valid(live) or adds.size() > ADD_BUDGET:
		return
	var owned_count: int = _owner.values().count(sender)
	for row in adds:
		if not (row is Array) or (row as Array).size() != 3:
			continue
		if not (row[0] is int) or not (row[1] is Transform3D) or not (row[2] is Color):
			continue
		var sid: int = row[0]
		if sid <= 0 or owned_count >= MINE_CAP or _ghost.has(sid) or _mine.has(sid):
			continue
		var xf: Transform3D = row[1]
		var tint: Color = row[2]
		if not xf.origin.is_finite() or not xf.basis.is_finite() or xf.basis.determinant() <= 0.0001:
			continue
		if not is_finite(tint.r) or not is_finite(tint.g) or not is_finite(tint.b) or not is_finite(tint.a):
			continue
		var b: Variant = live.spawn(xf.origin, xf.basis, Vector3.ZERO, row[2], true)
		if b == null:
			continue
		b.set_meta("mp_ghost", true)
		b.set_meta("mp_gid", sid)
		_solid(b)
		_place(b, xf)
		_ghost[sid] = b
		_owner[sid] = sender
		owned_count += 1
		_watch(b)


func on_move(sender: int, ids: PackedInt64Array, rows: PackedFloat32Array, sequence: int) -> void:
	if sender <= 0 or sequence <= 0 or ids.size() > MOVE_BUDGET or rows.size() != ids.size() * 7:
		return
	_apply_moves(sender, ids, rows, sequence)


func _apply_moves(sender: int, ids: PackedInt64Array, rows: PackedFloat32Array, sequence: int) -> void:
	for i in ids.size():
		if int(_owner.get(ids[i], 0)) != sender or sequence <= int(_received_pose.get(ids[i], 0)):
			continue
		var b: Variant = _ghost.get(ids[i])
		if b == null or not is_instance_valid(b) or not (b as Node3D).is_inside_tree():
			continue
		var k := i * 7
		var at := Vector3(rows[k], rows[k + 1], rows[k + 2])
		var rotation := Quaternion(rows[k + 3], rows[k + 4], rows[k + 5], rows[k + 6])
		if not at.is_finite() or not rotation.is_finite() or absf(rotation.length_squared() - 1.0) > 0.01:
			continue
		var to := Transform3D(Basis(rotation.normalized()), at)
		_received_pose[ids[i]] = sequence
		_goal[ids[i]] = [(b as Node3D).global_transform, to, 0.0]


func on_del(sender: int, ids: PackedInt64Array) -> void:
	if sender <= 0 or ids.size() > MINE_CAP:
		return
	for sid in ids:
		if int(_owner.get(sid, 0)) == sender:
			_drop_ghost(sid)

func on_census(sender: int, ids: PackedInt64Array, rows: PackedFloat32Array, sequence: int) -> void:
	if sender <= 0 or sequence <= 0 or ids.size() > MINE_CAP or rows.size() != ids.size() * 7:
		return
	_apply_moves(sender, ids, rows, sequence)
	var theirs := {}
	for sid in ids:
		theirs[sid] = true
	var gone: Array = []
	for sid in _ghost:
		if int(_owner.get(sid, 0)) == sender and not theirs.has(sid):
			gone.append(sid)
	for sid in gone:
		_drop_ghost(sid)


func _drop_ghost(sid: int) -> void:
	var b: Variant = _ghost.get(sid)
	_ghost.erase(sid)
	_goal.erase(sid)
	_owner.erase(sid)
	_received_pose.erase(sid)
	if b != null and is_instance_valid(b) and live != null:
		_revive(b)
		live.consume(b)


# A "visual only" straw is taken out of the physics world entirely. These
# bodies come from a pool the game reuses for real straws, so put it back
# before handing it over or the next straw drawn from the pool falls through
# the floor. Same steps the robotic arm uses for its sample bodies.
func _revive(b: Node) -> void:
	var body := b as Node3D
	if body == null or not body.is_inside_tree():
		return
	var space: RID = body.get_world_3d().space
	PhysicsServer3D.body_set_space(b.get_rid(), space)
	PhysicsServer3D.body_set_state(b.get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	body.force_update_transform()


func peer_gone(pid: int) -> void:
	var gone: Array = []
	for sid in _owner:
		if int(_owner[sid]) == pid:
			gone.append(sid)
	for sid in gone:
		_drop_ghost(sid)


# ------------------------------------------------------------------ in the hand

# Straw a remote player is holding. Their own game parks the real bodies in
# front of their camera; here we put copies in their farmer's hand so the
# others can see them carry it.

const HAND_FAN := 0.05
# the hand node hangs down the arm: a short step along -Z is the fist itself
const HAND_REACH := 0.13
const HAND_DROP := -0.03

var _hands := {}     # peer -> Array of straw bodies we keep for them


func set_hand(pid: int, count: int) -> void:
	if live == null or not is_instance_valid(live):
		return
	var held: Array = _hands.get(pid, [])
	count = clampi(count, 0, 12)
	while held.size() > count:
		var b: Variant = held.pop_back()
		if b != null and is_instance_valid(b):
			_revive(b)
			live.consume(b)
	while held.size() < count:
		var b: Variant = live.spawn(Vector3.ZERO, Basis(), Vector3.ZERO,
			Color(0.86, 0.74, 0.4), true)
		if b == null:
			break
		b.set_meta("mp_ghost", true)
		held.append(b)
		_watch(b)
	if held.is_empty():
		_hands.erase(pid)
	else:
		_hands[pid] = held


# fanned out in front of the fist, the way the game holds them
func _park_hands() -> void:
	if _hands.is_empty():
		return
	var ws: Node = mp.world_sync
	if ws == null or not is_instance_valid(ws):
		return
	for pid in _hands.keys():
		var av: Variant = ws.avatars.get(pid)
		if av == null or not is_instance_valid(av) or not av.has_method("hand_xform"):
			set_hand(int(pid), 0)
			continue
		var base: Transform3D = av.hand_xform()
		var held: Array = _hands[pid]
		for i in held.size():
			var b: Variant = held[i]
			if b == null or not is_instance_valid(b) or not (b as Node3D).is_inside_tree():
				continue
			var side := (float(i) - float(held.size() - 1) * 0.5) * HAND_FAN
			var xf := base * Transform3D(Basis(Vector3.UP, side * 1.6),
				Vector3(side, HAND_DROP, -HAND_REACH))
			(b as Node3D).global_transform = xf


func drop_hand(pid: int) -> void:
	set_hand(pid, 0)


# ------------------------------------------------------------------ picking up

# A copy starts life outside the physics world, which is cheap but means the
# aim ray goes straight through it: you could see your friend's straw and not
# pick it up. Put it back in as a still, solid body. It collides with nothing
# itself, so it neither falls nor pushes anyone; the owner says where it is.
func _solid(b: Node) -> void:
	_revive(b)
	b.collision_layer = Cfg.L_STRAND
	b.collision_mask = 0
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	b.continuous_cd = false


func _place(b: Node, xf: Transform3D) -> void:
	PhysicsServer3D.body_set_state(b.get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	(b as Node3D).global_transform = xf


# Picking somebody else's straw out of the yard takes it over: they drop
# theirs, we keep ours, and the straw stays one straw.
func _watch_hand() -> void:
	if _ghost.is_empty():
		return
	var pl: Variant = world.get("player")
	if pl == null or not is_instance_valid(pl):
		return
	var hand: Variant = pl.get("hand")
	if hand == null or not is_instance_valid(hand) or not hand.has_method("held_bodies"):
		return
	for b in hand.held_bodies():
		if b == null or not is_instance_valid(b) or not b.has_meta("mp_ghost"):
			continue
		var sid := int(b.get_meta("mp_gid", 0))
		if sid == 0 or not _ghost.has(sid):
			continue
		_ghost.erase(sid)
		_goal.erase(sid)
		_owner.erase(sid)
		_received_pose.erase(sid)
		b.remove_meta("mp_ghost")
		b.remove_meta("mp_gid")
		# a real straw again: it can fall, be carried and be put in a bucket
		b.collision_mask = LiveStrandManager.STRAND_MASK
		b.continuous_cd = true
		mp._rx_straw_claim.rpc(sid, mp._outgoing_world_seed())


# Host only. A guest's straw landed in one of our machines' mouths. Our copy is
# frozen and a machine will not eat a frozen straw, so make it a real straw of
# ours, the way picking one up does, and the guest drops theirs. The machine
# takes it on its own tick and it burns once, here.
func host_take(b: Variant) -> bool:
	if not mp.is_host or b == null or not is_instance_valid(b):
		return false
	var sid := int((b as Node).get_meta("mp_gid", 0))
	if sid == 0 or _ghost.get(sid) != b:
		return false
	_ghost.erase(sid)
	_goal.erase(sid)
	_owner.erase(sid)
	_received_pose.erase(sid)
	b.remove_meta("mp_ghost")
	b.remove_meta("mp_gid")
	# a copy is made as a protected, visual only straw; this one is loose hay
	b.set_meta(LiveStrandManager.META_PROTECTED, false)
	b.collision_mask = LiveStrandManager.STRAND_MASK
	b.continuous_cd = true
	b.freeze = false
	b.sleeping = false
	mp._rx_straw_claim.rpc(sid, mp._outgoing_world_seed())
	return true


func on_claim(sender: int, sid: int) -> void:
	if sender == _me():
		return
	var mine: Variant = _mine.get(sid)
	if mine != null:
		var hopper_service: Variant = mp.world_sync.get("hoppers_sync") if is_instance_valid(mp.world_sync) else null
		var input_service: Variant = hopper_service.get("tool_input") if is_instance_valid(hopper_service) else null
		if is_instance_valid(input_service):
			input_service.retire_claimed(mine)
		_mine.erase(sid)
		_sent.erase(sid)
		if is_instance_valid(mine) and live != null:
			if mine.has_meta("mp_sid"):
				mine.remove_meta("mp_sid")
			live.consume(mine)
		return
	_drop_ghost(sid)


# A thrown straw moves fast and we only hear about it ten times a second, so
# slide the copy towards where it was last seen instead of teleporting it.
func _ease(delta: float) -> void:
	if _goal.is_empty():
		return
	var step_t := delta / MOVE_TICK
	var done: Array = []
	for sid in _goal:
		var b: Variant = _ghost.get(sid)
		if b == null or not is_instance_valid(b) or not (b as Node3D).is_inside_tree():
			done.append(sid)
			continue
		var walk: Array = _goal[sid]
		var from: Transform3D = walk[0]
		var to: Transform3D = walk[1]
		var t: float = minf(1.0, float(walk[2]) + step_t)
		walk[2] = t
		_place(b, Transform3D(
			Basis(from.basis.get_rotation_quaternion().slerp(
				to.basis.get_rotation_quaternion(), t)),
			from.origin.lerp(to.origin, t)))
		if t >= 1.0:
			done.append(sid)
	for sid in done:
		_goal.erase(sid)


func _replace_live_script(script: Script) -> void:
	var values := {}
	for property in live.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = live.get(property.name)
	live.set_script(script)
	for key in values:
		if key in live:
			live.set(key, values[key])
