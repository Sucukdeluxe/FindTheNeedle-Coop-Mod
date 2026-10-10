extends Node

# Loose item replication.
#
# Every prop in the yard gets an id. The peer that made it owns it and is the
# only one that sends its movement; everyone else keeps a frozen copy that
# follows along. Picking up an item somebody else owns takes it over, so the
# item keeps moving for everybody while you carry it.
#
# The host is the reference: a joining client throws its own props away and
# rebuilds the list the host sends.

const MOVE_TICK := 0.1
const STATE_TICK := 1.0
const CENSUS_TICK := 6.0
const MOVE_EPS := 0.005
const BASIS_EPS := 0.01
const MOVE_BUDGET := 60
const STATE_BUDGET := 20
const RESET_BATCH := 30
const SMOOTH := 16.0
# tool items and the avatar tool that draws them, see _hide_held_tools
const TOOL_ITEMS := {"spade": 1, "pitchfork": 2, "broom": 3, "sand_shovel": 4,
	"metal_detector": 5, "yard_vac": 6}
const HELD_TICK := 0.2
# pushed with both hands, the owner's farmer draws them, see _hand_barrows
const PUSHED_ITEMS := {"wheelbarrow": true}

var mp: Node
var world: Node
var props: Node

var _by_id := {}     # mp id -> Carryable
var _owner := {}     # mp id -> peer id
var _sent := {}      # mp id -> last transform we broadcast
var _hash := {}      # mp id -> hash of the last state we broadcast
var _goal := {}      # mp id -> transform a remote copy is easing towards
var _want := {}      # mp id -> peer we expect it from
var _manager_script: Script
var _cleanup_state := {"auto_clean": false, "prop_decay": false, "auto_clean_seconds": 60.0}
var _published_cleanup := {}
var _original_tools := {}
var _epoch := {}
var _deleted := {}
var _claim_pending := {}
var _reset_seen := {}
var _move_cursor := 0
var _state_cursor := 0
var _settling := {}
var _move_order := {}
var _move_sequence := 0
var _next := 0
var _ready_map := false
var _busy := false   # we are the ones touching the prop list, do not echo it
var _move_t := 0.0
var _state_t := 0.0
var _census_t := 0.0
var _held_t := 0.0
var _hidden := {}   # mp id -> the layer a hidden copy had, while it is hidden
var _held := {}     # mp id -> true while its owner says they're carrying it
var _pushed := {}   # mp id -> avatar placing that copy in its hands
var _boarded := {}  # mp id -> where one of ours got on a belt, guest only
var _belt_t := 0.0
var _log := OS.get_environment("MP_DEBUG_PROPS") != ""  # dev tracing


func start(mp_node: Node, world_node: Node) -> void:
	mp = mp_node
	world = world_node
	props = world.get("props")
	if props == null or not is_instance_valid(props):
		return
	_manager_script = props.get_script()
	_replace_script(props, load(mp.base_dir + "/mp_prop_manager.gd"))
	props.set("mp_props", self)
	props.item_added.connect(_on_added)
	props.item_removed.connect(_on_removed)
	var carry: Variant = _carry_tool()
	if carry != null:
		carry.carry_changed.connect(_on_carry_changed)
	session_started()


# The host can also open a session from inside a world, after this node is up.
func session_started() -> void:
	if mp.is_host and not _ready_map:
		_adopt_all()
		_ready_map = true


func shutdown() -> void:
	for item in _original_tools:
		if is_instance_valid(item):
			_replace_script(item, _original_tools[item])
	_original_tools.clear()
	if props == null or not is_instance_valid(props):
		return
	if _manager_script != null:
		_replace_script(props, _manager_script)
	if props.item_added.is_connected(_on_added):
		props.item_added.disconnect(_on_added)
	if props.item_removed.is_connected(_on_removed):
		props.item_removed.disconnect(_on_removed)
	var carry: Variant = _carry_tool()
	if carry != null and carry.carry_changed.is_connected(_on_carry_changed):
		carry.carry_changed.disconnect(_on_carry_changed)
	for id in _by_id:
		var it: Variant = _by_id[id]
		if it != null and is_instance_valid(it):
			_release(it)
			if _hidden.has(id):
				it.collision_layer = int(_hidden[id])
				it.visible = true
	for id in _pushed:
		if is_instance_valid(_pushed[id]):
			_pushed[id].push_item(null)
	_pushed.clear()
	_boarded.clear()
	_held.clear()
	_hidden.clear()
	_by_id.clear()
	_owner.clear()
	_goal.clear()
	_settling.clear()
	_move_order.clear()


func _carry_tool() -> Variant:
	var pl: Variant = world.get("player")
	if pl == null or not is_instance_valid(pl):
		return null
	var c: Variant = pl.get("carry")
	if c == null or not is_instance_valid(c) or not c.has_signal("carry_changed"):
		return null
	return c


func _me() -> int:
	return multiplayer.get_unique_id()


func _new_id() -> int:
	_next += 1
	return _me() * 1000000 + _next


# ------------------------------------------------------------------ bookkeeping

func _adopt_all() -> void:
	for item in props.items:
		if is_instance_valid(item) and not item.has_meta("mp_id"):
			_adopt(item, _new_id(), _me())


func _adopt(item: Node, id: int, owner: int) -> void:
	# Ids are peer * 1e6 + a counter that starts over with every world load.
	# After a resync the host still lists items we made before it, so carry on
	# counting from the highest of ours, or a new item takes an old one's id
	# and the others just move the old one to where the new one is.
	if id / 1000000 == _me():
		_next = maxi(_next, id % 1000000)
	if mp != null and mp.active() and item.has_method("claim") and String(item.item_id) in TOOL_ITEMS:
		if not _original_tools.has(item):
			_original_tools[item] = item.get_script()
			_replace_script(item, load(mp.base_dir + "/mp_tool_prop.gd"))
			item.set("mp_props", self)
	item.set_meta("mp_id", id)
	_by_id[id] = item
	_owner[id] = owner
	_want.erase(id)
	_deleted.erase(id)
	if owner == _me():
		_release(item)
	else:
		_puppet(item)


func _forget(id: int, deleted: bool = true) -> void:
	_original_tools.erase(_by_id.get(id))
	_hidden.erase(id)
	_held.erase(id)
	_by_id.erase(id)
	_owner.erase(id)
	_sent.erase(id)
	_hash.erase(id)
	_goal.erase(id)
	_claim_pending.erase(id)
	_settling.erase(id)
	_move_order.erase(id)
	if deleted:
		_deleted[id] = Time.get_ticks_msec()


# A copy owned by somebody else: no physics of its own, and off limits to the
# yard cleaner and to the machines that go looking for loose hay.
func _puppet(item: Node) -> void:
	item.set_meta("mp_copy", true)
	item.set_meta(PropManager.META_CLAIM, get_instance_id())
	item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	item.freeze = true
	item.set_physics_process(false)
	# a new hay tuft starts with no collision layer and gets it back in its own
	# physics tick once no straw is inside it; that tick is off on a copy, so the
	# copy stayed out of everyone's aim and only its maker could pick it up
	if item is HayTuft and float(item.get("_emerging")) > 0.0:
		item.set("_emerging", 0.0)
		item.collision_layer = int(item.get("_emerge_layer"))
		item.collision_mask = int(item.get("_emerge_mask"))


# Moving a frozen body by its transform alone leaves its collision shape
# behind, so a copy could be seen but not picked up or bumped into. Tell the
# physics server as well, the way the game does in Carryable.warp().
func _place(item: Node, xform: Transform3D) -> void:
	PhysicsServer3D.body_set_state(item.get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	item.global_transform = xform


func _release(item: Node) -> void:
	if not item.has_meta("mp_copy"):
		return
	item.remove_meta("mp_copy")
	if item.has_meta(PropManager.META_CLAIM) \
	and int(item.get_meta(PropManager.META_CLAIM)) == get_instance_id():
		item.remove_meta(PropManager.META_CLAIM)
	item.set_physics_process(true)
	# an item in a hand is carried as a kinematic body: forcing it static here
	# undid what the game had just set and left it sweeping through things
	if item.is_held():
		item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	else:
		item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		item.freeze = false


func _mine(id: int) -> bool:
	return int(_owner.get(id, 0)) == _me()


# Host only. A guest's item is sitting in a machine's mouth. The machines run
# here, and they will not touch a frozen copy that belongs to somebody else, so
# take it over first: once it is ours and unfrozen the machine swallows it on
# its own tick, and the delete goes out like any other. This is how hay a guest
# loads finally counts, and it still only counts once, here.
func host_take(item: Variant) -> bool:
	if not mp.is_host or item == null or not is_instance_valid(item) or not item.is_inside_tree():
		return false
	var n := item as Node
	if n == null or not n.has_meta("mp_id"):
		return false
	var id := int(n.get_meta("mp_id"))
	# theirs to carry for as long as they are carrying it
	if _mine(id) or bool(_held.get(id, false)):
		return false
	_assign_owner(id, _me(), false)
	return true


# ------------------------------------------------------------------ local events

func _on_added(item: Node) -> void:
	if _busy or not _ready_map or item.has_meta("mp_id"):
		return
	var id := _new_id()
	_adopt(item, id, _me())
	_sent[id] = item.global_transform
	var st := _state_of(item)
	_hash[id] = st.hash()
	if _log:
		print("[MPPROPS] made %s id=%d at %v" % [item.item_id, id, item.global_position])
	mp._rx_prop_add.rpc(id, String(item.item_id), item.global_transform, st)


func _on_removed(item: Node) -> void:
	if not item.has_meta("mp_id"):
		return
	var id := int(item.get_meta("mp_id"))
	var mine := _mine(id)
	_forget(id, mine or mp.is_host)
	if _busy:
		return
	if _log:
		print("[MPPROPS] lost %s id=%d mine=%s" % [item.item_id, id, mine])
	if mine and _boarded.has(id):
		# our belt took it, but the host's belts are the real ones: hand it over
		# there, or the host's next belt snapshot wipes it and the hay is gone
		mp._rx_prop_board.rpc_id(1, id, _boarded[id])
		_boarded.erase(id)
	elif mine:
		mp._rx_prop_del.rpc(PackedInt64Array([id]))
	elif mp.is_host:
		# the host's world is the one that counts: something here used up a
		# guest's item (the delivery truck loads whatever lands in its bed), so
		# it is gone for everybody. Asking for it back put it in the truck again
		# and the same bale was counted over and over.
		mp._rx_prop_owner.rpc(id, 1, int(_epoch.get(id, 0)) + 1, false)
		mp._rx_prop_del.rpc(PackedInt64Array([id]))
	else:
		# a local machine ate a copy: ask for it back
		_want[id] = 0


# Taking an item somebody else owns makes it ours, so we are the one moving it.
func _on_carry_changed(item: Variant) -> void:
	# picked up or let go: tell the others now, not in a second
	_state_t = STATE_TICK
	if item == null or not is_instance_valid(item) or not item.has_meta("mp_id"):
		for stale_id in _held.keys():
			if not _mine(stale_id):
				continue
			var stale_item: Variant = _by_id.get(stale_id)
			if stale_item == null or not is_instance_valid(stale_item) or not stale_item.is_held():
				_held.erase(stale_id)
		return
	var id := int(item.get_meta("mp_id"))
	if _mine(id):
		return
	request_claim(id, "carry")


# Guest only. A belt says what it caught just before it takes the item out of
# the prop list, so note ours on the way past and _on_removed knows why it went.
func _watch_belts() -> void:
	for belt in BeltPath._live:
		if is_instance_valid(belt) and not belt.caught.is_connected(_on_belt_caught):
			belt.caught.connect(_on_belt_caught)


func _on_belt_caught(rb: Node) -> void:
	if rb == null or not is_instance_valid(rb) or not rb.has_meta("mp_id"):
		return
	var id := int(rb.get_meta("mp_id"))
	if _mine(id):
		_boarded[id] = (rb as Node3D).global_transform
		_hand_rider.call_deferred(rb)


# Guest only. Most items leave the prop list when a belt takes them, and
# _on_removed hands them to the host. A hay tuft stays an item riding the belt,
# so it never left: it rode our belt only, which just mirrors the host's, and
# at a splitter it went off the path and back to the start over and over. Hand
# it over now, where it got on, and drop it from our belt: the host's belt
# carries it from there like the host's own.
func _hand_rider(rb: Node) -> void:
	if rb == null or not is_instance_valid(rb) or not rb.is_inside_tree():
		return
	var id := int(rb.get_meta("mp_id", 0))
	if not _mine(id) or not BeltPath.is_rider(rb as RigidBody3D):
		return
	var xf: Transform3D = _boarded.get(id, (rb as Node3D).global_transform)
	_boarded.erase(id)
	BeltPath.release(rb as RigidBody3D)
	_owner[id] = 1
	_goal.erase(id)
	_hash.erase(id)
	_puppet(rb)
	_place(rb, xf)
	mp._rx_prop_board.rpc_id(1, id, xf)


# Host only. The guest's belt took one of the guest's items at xf. Take our copy
# over, put it there and let it go: our belt catches it on its next tick and it
# reaches everyone in the belt snapshot, the way the host's own hay does.
func on_board(sender: int, id: int, xf: Transform3D) -> void:
	var it: Variant = _by_id.get(id)
	if it == null or not is_instance_valid(it) or int(_owner.get(id, 0)) != sender:
		return
	# it just left their hands, whatever the last state said
	_held.erase(id)
	if not host_take(it):
		return
	_place(it, xf)
	(it as RigidBody3D).linear_velocity = Vector3.ZERO
	(it as RigidBody3D).sleeping = false


# Hay the other player dropped: the little piles a spade leaves (HayTuft) and
# wads. Our copy of one is frozen and claimed, and the spade passes over a
# frozen or claimed wad, so only the player who made a pile could scoop it up
# again. When we dig with a spade and such a copy lies in reach in front of us,
# take it over first, the way picking up an item does: then it is ours, loose,
# and the spade takes it like any other. Picking one up by hand already claims
# it.
const CLAIM_REACH := 2.4   # the spade's gather reach

func _claim_in_reach() -> void:
	var pl: Variant = world.get("player")
	if pl == null or not is_instance_valid(pl):
		return
	var tool := int(pl.get("current_tool"))
	if tool != Player.Tool.SHOVEL or not Input.is_action_pressed("primary"):
		return
	var eye: Vector3 = pl.eye_position()
	var look: Vector3 = pl.look_direction()
	for id in _by_id.keys():
		if _mine(id) or bool(_held.get(id, false)):
			continue
		var it: Variant = _by_id[id]
		if it == null or not is_instance_valid(it) or not (it is HayWad) or not (it as Node3D).is_inside_tree():
			continue
		# riding somebody's belt is not lying on the floor: taking it froze it
		# on the host's belt
		if BeltPath.is_rider(it as RigidBody3D):
			continue
		var to: Vector3 = (it as Node3D).global_position - eye
		if to.length() > CLAIM_REACH or to.normalized().dot(look) < 0.6:
			continue
		request_claim(id, "release")


func _state_of(item: Node) -> Dictionary:
	var st: Dictionary = item.to_state()
	if item.holds_needle():
		st["needle"] = item.needle_index
	# the game's from_state only reads its own keys, so older versions skip this
	if item.is_held():
		st["held"] = true
	return st


# ------------------------------------------------------------------ ticks

func _process(delta: float) -> void:
	_smooth(delta)
	_held_t += delta
	if _held_t >= HELD_TICK:
		_held_t = 0.0
		_hide_held_tools()
		_hand_barrows()
	if mp == null or not mp.active() or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not _ready_map:
		return
	if not mp.is_host:
		_belt_t += delta
		if _belt_t >= 0.5:
			_belt_t = 0.0
			_watch_belts()
	_move_t += delta
	if _move_t >= MOVE_TICK:
		_move_t = 0.0
		_move_tick()
		_claim_in_reach()
	_state_t += delta
	if _state_t >= STATE_TICK:
		_state_t = 0.0
		_state_tick()
		_publish_cleanup()
		_feed_containers()
	_census_t += delta
	if _census_t >= CENSUS_TICK:
		_census_t = 0.0
		_census_tick()


# A tool somebody else is carrying floats in front of their first-person view,
# but their farmer already draws it in its hand, so hide that copy while it's
# up there. Tools lying around, and every other item, stay visible.
func _hide_held_tools() -> void:
	var ws: Variant = mp.world_sync if mp != null else null
	var avatars: Dictionary = ws.avatars if ws != null and is_instance_valid(ws) else {}
	for id in _by_id:
		var it: Variant = _by_id[id]
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			continue
		var tool: int = TOOL_ITEMS.get(String(it.item_id), 0)
		if tool == 0:
			continue
		var hide := false
		if not _mine(id):
			var av: Variant = avatars.get(int(_owner.get(id, 0)))
			if av != null and is_instance_valid(av) and int(av.get("_tool")) == tool:
				var off: Vector3 = it.global_position - av.global_position
				hide = off.y > 0.5 and Vector2(off.x, off.z).length() < 2.0
		if hide and not _hidden.has(id):
			# out of sight and out of everyone's aim: an invisible tool that is
			# still solid catches the ray meant for whatever is behind it, and
			# then nobody can pick anything up
			_hidden[id] = it.collision_layer
			it.collision_layer = 0
			it.visible = false
		elif not hide and _hidden.has(id):
			it.collision_layer = int(_hidden[id])
			_hidden.erase(id)
			it.visible = true


# A wheelbarrow somebody is pushing is drawn by their farmer, between its
# hands, instead of where their first-person view has it. When they let go it
# eases back to where the owner says it is.
func _hand_barrows() -> void:
	var ws: Variant = mp.world_sync if mp != null else null
	var avatars: Dictionary = ws.avatars if ws != null and is_instance_valid(ws) else {}
	var want := {}  # mp id -> avatar
	for pid in avatars:
		var av: Variant = avatars[pid]
		if av == null or not is_instance_valid(av) or not av.has_method("push_item"):
			continue
		for it in held_by(int(pid)):
			if PUSHED_ITEMS.has(String(it.item_id)):
				want[int(it.get_meta("mp_id"))] = av
	for id in _pushed.keys():
		var av: Variant = _pushed[id]
		if is_instance_valid(av) and want.get(id) == av:
			continue
		_pushed.erase(id)
		# unless it's taking another one below
		if is_instance_valid(av) and not want.values().has(av):
			av.push_item(null)
	for id in want:
		if _pushed.has(id):
			continue
		var it: Node = _by_id[id]
		# keep where it really is, for when they let go
		if not _goal.has(id):
			_goal[id] = it.global_transform
		_pushed[id] = want[id]
		want[id].push_item(it)


# Items a peer owns and says they're carrying (see _state_of).
func held_by(pid: int) -> Array:
	var out: Array = []
	for id in _held:
		var it: Variant = _by_id.get(id)
		if int(_owner.get(id, 0)) == pid and it != null and is_instance_valid(it):
			out.append(it)
	return out


# Remote copies ease towards the last position we heard about instead of
# jumping ten times a second.
func _smooth(delta: float) -> void:
	if _goal.is_empty():
		return
	var f := minf(1.0, delta * SMOOTH)
	var done: Array = []
	for id in _goal:
		var it: Variant = _by_id.get(id)
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			done.append(id)
			continue
		if _pushed.has(id):
			# a farmer is holding it, the goal waits for them to let go
			continue
		var want: Transform3D = _goal[id]
		var step: Transform3D = it.global_transform.interpolate_with(want, f)
		_place(it, step)
		if step.origin.distance_to(want.origin) < 0.002:
			_place(it, want)
			done.append(id)
	for id in done:
		_goal.erase(id)


func _move_tick() -> void:
	var ids := PackedInt64Array()
	var xfs: Array = []
	var epochs := PackedInt64Array()
	var resting := PackedInt64Array()
	var rest_xfs: Array = []
	var rest_epochs := PackedInt64Array()
	var keys := _by_id.keys()
	var start := _move_cursor
	for offset in keys.size():
		var index := (start + offset) % keys.size()
		var id: int = keys[index]
		_move_cursor = (index + 1) % keys.size()
		var it: Variant = _by_id[id]
		if it == null or not is_instance_valid(it) or not _mine(id) or not it.is_inside_tree():
			continue
		var xf: Transform3D = it.global_transform
		var last: Variant = _sent.get(id)
		if last != null and _same(last, xf):
			if _settling.has(id):
				_settling.erase(id)
				_sent[id] = xf
				resting.append(id)
				rest_xfs.append(xf)
				rest_epochs.append(int(_epoch.get(id, 0)))
		else:
			_sent[id] = xf
			_settling[id] = true
			ids.append(id)
			xfs.append(xf)
			epochs.append(int(_epoch.get(id, 0)))
		if ids.size() + resting.size() >= MOVE_BUDGET:
			break
	if not ids.is_empty():
		_move_sequence += 1
		mp._rx_prop_move.rpc(ids, xfs, _move_sequence, epochs)
	if not resting.is_empty():
		_move_sequence += 1
		mp._rx_prop_rest.rpc(resting, rest_xfs, _move_sequence, rest_epochs)
	if not _want.is_empty():
		var asking := PackedInt64Array()
		for id in _want:
			asking.append(id)
		_want.clear()
		mp._rx_prop_want.rpc(asking)


func _same(a: Transform3D, b: Transform3D) -> bool:
	if a.origin.distance_squared_to(b.origin) > MOVE_EPS * MOVE_EPS:
		return false
	return a.basis.x.distance_squared_to(b.basis.x) < BASIS_EPS * BASIS_EPS \
		and a.basis.y.distance_squared_to(b.basis.y) < BASIS_EPS * BASIS_EPS


func _state_tick() -> void:
	var ids := PackedInt64Array()
	var states: Array = []
	var keys := _by_id.keys()
	var start := _state_cursor
	for offset in keys.size():
		var index := (start + offset) % keys.size()
		var id: int = keys[index]
		_state_cursor = (index + 1) % keys.size()
		var it: Variant = _by_id[id]
		if it == null or not is_instance_valid(it):
			continue
		var st := _state_of(it)
		var h := st.hash()
		if mp.is_host and not _mine(id) and _hash.has(id) and it.has_method("put_in") and it.has_method("take_out") and int(_hash.get(id, 0)) != h:
			_assign_owner(id, 1, false)
		if not _mine(id):
			continue
		if int(_hash.get(id, 0)) == h:
			continue
		_hash[id] = h
		ids.append(id)
		states.append(st)
		if ids.size() >= STATE_BUDGET:
			break
	if ids.size() > 0:
		mp._rx_prop_state.rpc(ids, states)


func _census_tick() -> void:
	for id in _deleted.keys():
		if Time.get_ticks_msec() - int(_deleted[id]) > 120000:
			_deleted.erase(id)
	_sent.clear()
	for id in _hash.keys():
		if _mine(id):
			_hash.erase(id)
	var ids := PackedInt64Array()
	for id in _by_id:
		if _mine(id) and is_instance_valid(_by_id[id]):
			ids.append(id)
	mp._rx_prop_census.rpc(ids)


# ------------------------------------------------------------------ from the net

func on_add(sender: int, id: int, item_id: String, xf: Transform3D, state: Dictionary) -> void:
	if mp != null and mp.is_host and sender != 1 and mp.players.get(sender, {}).get("state", "world") != "world":
		return
	if _deleted.has(id):
		return
	var have: Variant = _by_id.get(id)
	if have != null and is_instance_valid(have):
		if not _mine(id) and int(_owner.get(id, 0)) == sender:
			_goal[id] = xf
		return
	if not ItemDb.has_item(item_id):
		return
	_busy = true
	var it: Variant = props.spawn(item_id, xf, state)
	_busy = false
	if it != null:
		_adopt(it, id, int(_owner.get(id, sender)))
		_note_held(id, state)
		if not _mine(id):
			_hash[id] = _state_of(it).hash()


func on_del(sender: int, ids: PackedInt64Array) -> void:
	for id in ids:
		if _mine(id) or int(_owner.get(id, 0)) != sender:
			continue
		var it: Variant = _by_id.get(id)
		_forget(id)
		if it != null and is_instance_valid(it):
			_busy = true
			props.remove(it)
			_busy = false


func on_move(sender: int, ids: PackedInt64Array, xfs: Array, sequence: int = 0, epochs: PackedInt64Array = PackedInt64Array()) -> void:
	for i in mini(ids.size(), xfs.size()):
		var id: int = ids[i]
		if _mine(id):
			continue
		var it: Variant = _by_id.get(id)
		if it == null or not is_instance_valid(it):
			if not _deleted.has(id):
				_want[id] = sender
			continue
		if int(_owner.get(id, 0)) != sender:
			continue
		if not epochs.is_empty() and (i >= epochs.size() or int(epochs[i]) != int(_epoch.get(id, 0))):
			continue
		if sequence > 0 and sequence <= int(_move_order.get(id, 0)):
			continue
		if it.is_held():
			continue
		if sequence > 0:
			_move_order[id] = sequence
		_goal[id] = xfs[i]


func on_state(sender: int, ids: PackedInt64Array, states: Array) -> void:
	for i in mini(ids.size(), states.size()):
		var id: int = ids[i]
		if _mine(id):
			continue
		var it: Variant = _by_id.get(id)
		if it == null or not is_instance_valid(it):
			_want[id] = sender
			continue
		if int(_owner.get(id, 0)) != sender:
			continue
		var st: Dictionary = states[i]
		it.from_state(st)
		it.needle_index = int(st.get("needle", -1))
		_note_held(id, st)
		_hash[id] = _state_of(it).hash()


# older versions never send "held", so their items just look loose
func _note_held(id: int, st: Dictionary) -> void:
	if st.get("held", false):
		_held[id] = true
	else:
		_held.erase(id)


func request_claim(id: int, action: String = "release") -> bool:
	if _claim_pending.has(id):
		return true
	if not _by_id.has(id):
		return false
	_claim_pending[id] = action
	if mp.is_host:
		on_claim_request(_me(), id, int(_epoch.get(id, 0)), action != "release")
	else:
		mp._rx_prop_claim.rpc_id(1, id, int(_epoch.get(id, 0)), action != "release")
	return true


func on_claim_request(sender: int, id: int, expected: int, holding: bool) -> void:
	if not mp.is_host or not mp.players.has(sender):
		return
	var item: Variant = _by_id.get(id)
	if not is_instance_valid(item):
		_reply_owner(sender, id, 0, int(_epoch.get(id, 0)), false)
		return
	var owner := int(_owner.get(id, 1))
	var held: bool = bool(_held.get(id, false)) or item.is_held()
	if owner != sender and (expected != int(_epoch.get(id, 0)) or held):
		_reply_owner(sender, id, owner, int(_epoch.get(id, 0)), held)
		_claim_pending.erase(id)
		return
	_assign_owner(id, sender, holding)


func _reply_owner(peer: int, id: int, owner: int, epoch: int, holding: bool) -> void:
	if peer == _me():
		on_owner(id, owner, epoch, holding)
	else:
		mp._rx_prop_owner.rpc_id(peer, id, owner, epoch, holding)


func _assign_owner(id: int, owner: int, holding: bool) -> void:
	var epoch := int(_epoch.get(id, 0)) + 1
	on_owner(id, owner, epoch, holding)
	mp._rx_prop_owner.rpc(id, owner, epoch, holding)


func on_claim(sender: int, id: int) -> void:
	on_owner(id, sender, int(_epoch.get(id, 0)) + 1, false)


func on_owner(id: int, owner: int, epoch: int, holding: bool) -> void:
	if epoch < int(_epoch.get(id, 0)):
		return
	var ownership_changed := epoch != int(_epoch.get(id, 0)) or owner != int(_owner.get(id, 0))
	var action := str(_claim_pending.get(id, ""))
	_claim_pending.erase(id)
	_epoch[id] = epoch
	if owner == 0:
		return
	var it: Variant = _by_id.get(id)
	_owner[id] = owner
	_held.erase(id)
	if holding:
		_held[id] = true
	_hash.erase(id)
	_sent.erase(id)
	_settling.erase(id)
	if ownership_changed:
		_move_order.erase(id)
	_goal.erase(id)
	if not is_instance_valid(it):
		_want[id] = owner
		return
	if owner == _me():
		_release(it)
		if action == "tool" and it.has_method("claim"):
			it.claim(world.player)
			return
		var carry: Variant = _carry_tool()
		if carry != null and action in ["carry", "stack"]:
			if action == "stack" and carry.can_stack(it):
				carry.stack_on(it)
			elif not carry.is_carrying():
				carry.take(it)
	else:
		if it.is_held():
			var carry: Variant = _carry_tool()
			if carry != null:
				carry.drop_all()
		if it is RigidBody3D:
			BeltPath.release(it)
		_puppet(it)
		if not holding:
			_hash[id] = _state_of(it).hash()


func on_want(sender: int, ids: PackedInt64Array) -> void:
	for id in ids:
		if not _mine(id):
			continue
		var it: Variant = _by_id.get(id)
		if it == null or not is_instance_valid(it):
			continue
		mp._rx_prop_add.rpc_id(sender, id, String(it.item_id),
			it.global_transform, _state_of(it))


func on_census(sender: int, ids: PackedInt64Array) -> void:
	var missing := PackedInt64Array()
	for id in ids:
		var it2: Variant = _by_id.get(id)
		if (it2 == null or not is_instance_valid(it2)) and not _deleted.has(id):
			missing.append(id)
	if missing.size() > 0:
		mp._rx_prop_want.rpc_id(sender, missing)


# ------------------------------------------------------------------ joining

# Host side: hand a client the whole yard, in batches so no single packet gets
# out of hand. Sent right after the client reports it is in the world.
func send_all(pid: int) -> void:
	_publish_cleanup(pid)
	var ids := PackedInt64Array()
	var owners := PackedInt32Array()
	var entries: Array = []
	var first := true
	for id in _by_id:
		var it: Variant = _by_id[id]
		if it == null or not is_instance_valid(it) or not it.is_inside_tree():
			continue
		ids.append(id)
		owners.append(int(_owner.get(id, 1)))
		var st := _state_of(it)
		# someone else carrying it right now
		if _held.has(id):
			st["held"] = true
		entries.append({
			"id": String(it.item_id),
			"epoch": int(_epoch.get(id, 0)),
			"xform": it.global_transform,
			"state": st,
		})
		if entries.size() >= RESET_BATCH:
			mp._rx_prop_reset.rpc_id(pid, first, ids, owners, entries)
			first = false
			ids = PackedInt64Array()
			owners = PackedInt32Array()
			entries = []
	mp._rx_prop_reset.rpc_id(pid, first, ids, owners, entries)
	mp._rx_prop_reset_end.rpc_id(pid)


func on_reset(first: bool, ids: PackedInt64Array, owners: PackedInt32Array, entries: Array) -> void:
	if first:
		_reset_seen.clear()
		if not _ready_map:
			_busy = true
			props.clear()
			_busy = false
			_by_id.clear()
			_owner.clear()
			_epoch.clear()
			_deleted.clear()
			_sent.clear()
			_settling.clear()
			_move_order.clear()
			_hash.clear()
			_goal.clear()
			_want.clear()
			_held.clear()
			_hidden.clear()
	for i in mini(ids.size(), mini(owners.size(), entries.size())):
		var id: int = ids[i]
		_reset_seen[id] = true
		var e: Dictionary = entries[i]
		var epoch := int(e.get("epoch", 0))
		if epoch < int(_epoch.get(id, 0)):
			continue
		var existing: Variant = _by_id.get(id)
		if is_instance_valid(existing):
			if _mine(id) or _claim_pending.has(id):
				continue
			on_owner(id, owners[i], epoch, bool(e.get("state", {}).get("held", false)))
			if not _mine(id):
				existing.from_state(e.get("state", {}))
				_goal[id] = e.get("xform", existing.global_transform)
			continue
		var item_id: String = e.get("id", "")
		if not ItemDb.has_item(item_id) or _deleted.has(id):
			continue
		_busy = true
		var it: Variant = props.spawn(item_id, e.get("xform", Transform3D.IDENTITY), e.get("state", {}))
		_busy = false
		if it != null:
			_epoch[id] = epoch
			_adopt(it, id, owners[i])
			_note_held(id, e.get("state", {}))


func on_reset_end() -> void:
	for id in _by_id.keys():
		if _reset_seen.has(id) or int(_owner.get(id, 0)) != 1 or _mine(id) or _claim_pending.has(id):
			continue
		var item: Variant = _by_id[id]
		_forget(id)
		if is_instance_valid(item):
			_busy = true
			props.remove(item)
			_busy = false
	_ready_map = true


# A peer left: the host keeps their things and takes over sending them.
func peer_gone(pid: int) -> void:
	retire_equipped_tools(pid)
	for id in _owner.keys():
		if int(_owner[id]) != pid:
			continue
		_epoch[id] = int(_epoch.get(id, 0)) + 1
		_move_order.erase(id)
		_settling.erase(id)
		_hash.erase(id)
		_owner[id] = 1
		_held.erase(id)
		var it: Variant = _by_id.get(id)
		if it == null or not is_instance_valid(it):
			continue
		if _me() == 1:
			_release(it)
			_sent.erase(id)


func _replace_script(item: Node, script: Script) -> void:
	var values := {}
	for property in item.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = item.get(property.name)
	item.set_script(script)
	for key in values:
		if key in item:
			item.set(key, values[key])


func _feed_containers() -> void:
	for id in _by_id.keys():
		var container: Variant = _by_id.get(id)
		if not _mine(id) or not is_instance_valid(container) or not container.is_inside_tree():
			continue
		if not container.has_method("takes_loose") or not container.takes_loose():
			continue
		var interior: Variant = container.get("_interior")
		if not (interior is Area3D) or not interior.is_inside_tree():
			continue
		for body in interior.get_overlapping_bodies():
			if not (body is HayWad) or not body.has_meta("mp_id"):
				continue
			var other := int(body.get_meta("mp_id"))
			if not _mine(other) and not _held.has(other):
				request_claim(other)


func cleanup_policy() -> Dictionary:
	if not mp.is_host:
		return _cleanup_state
	return {"auto_clean": Cfg.auto_clean, "prop_decay": Cfg.prop_decay,
		"auto_clean_seconds": Cfg.auto_clean_seconds}

func _publish_cleanup(pid: int = 0) -> void:
	if not mp.is_host:
		return
	var policy := cleanup_policy()
	if pid != 0:
		mp._rx_prop_cleanup.rpc_id(pid, policy)
	elif policy != _published_cleanup:
		_published_cleanup = policy.duplicate()
		mp._rx_prop_cleanup.rpc(policy)

func on_cleanup(policy: Dictionary) -> void:
	if mp.is_host or not (policy.get("auto_clean") is bool) or not (policy.get("prop_decay") is bool):
		return
	var seconds: Variant = policy.get("auto_clean_seconds")
	if typeof(seconds) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(seconds)) or float(seconds) <= 0.0:
		return
	_cleanup_state = {"auto_clean": policy.auto_clean, "prop_decay": policy.prop_decay,
		"auto_clean_seconds": float(seconds)}


func is_personal_tool_body(item: Node) -> bool:
	if mp == null or not mp.is_host or not (item is SandShovel) or not item.has_meta("mp_id"):
		return false
	var id := int(item.get_meta("mp_id"))
	if not item.is_held() and not bool(_held.get(id, false)):
		return false
	var sync: Node = mp.world_sync.tools_sync if is_instance_valid(mp.world_sync) else null
	return is_instance_valid(sync) and sync.has_tool(int(_owner.get(id, 1)), "sand_shovel")


func retire_equipped_tools(pid: int) -> void:
	if mp == null or not mp.is_host:
		return
	for id in _by_id.keys():
		var item: Variant = _by_id[id]
		if int(_owner.get(id, 0)) == pid and is_instance_valid(item) and is_personal_tool_body(item):
			props.remove(item)
