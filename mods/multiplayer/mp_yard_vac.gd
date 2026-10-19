extends "res://scripts/tools/yard_vac.gd"

const MP_DUMP_BUDGET := 2000
const MP_DUMP_INTERVAL := 0.1
var mp_dump_all := false
var mp_tools: Node
var _mp_dump_wait := 0.0
var _mp_flights := {}
var _mp_belt_flight: WeakRef
var _mp_belt_launched := 0
var _mp_router_pour_wait := 0.0

func mp_cancel_dump() -> void:
	if not mp_dump_all:
		return
	mp_dump_all = false
	_mp_dump_wait = 0.0
	set_pouring(false)

func _physics_process(delta: float) -> void:
	if bool(get_meta("mp_vacuum_escrow", false)):
		set_sucking(false)
		set_pouring(false)
		_carry_needles()
		return
	if mp_dump_all:
		if not _active or not is_instance_valid(player) or player.menu_is_up() or not player.is_mouse_captured() or not is_loaded():
			mp_cancel_dump()
		else:
			set_sucking(false)
			set_pouring(true)
	super._physics_process(delta)

func _pour(delta: float) -> void:
	if mp_dump_all:
		_mp_dump_wait = maxf(0.0, _mp_dump_wait - delta)
		if _mp_dump_wait > 0.0:
			return
		_mp_dump_wait = MP_DUMP_INTERVAL
		_pour_owed = float(mini(_fill, MP_DUMP_BUDGET))
		_spit_t = 0.0
		super._pour(0.0)
		return
	super._pour(delta)

func _pour_straw(delta: float) -> void:
	if not mp_dump_all:
		if _mp_pour_router(delta):
			return
		_mp_router_pour_wait = 0.0
		super._pour_straw(delta)
		return
	if is_instance_valid(mp_tools) and is_instance_valid(mp_tools.mp.world_sync.vacuum_transfer):
		if mp_tools.mp.world_sync.vacuum_transfer.try_belt(self):
			return
	if not is_instance_valid(live) or not is_instance_valid(live.props):
		return
	var mouth := mouth_position()
	var launch := _pour_launch(mouth)
	var belt := BeltPath.Pour.NO_BELT
	if not is_instance_valid(_into):
		belt = BeltPath.pour_verdict(mouth, launch, _tuft_reach())
		if belt == BeltPath.Pour.NO_ROOM or (belt == BeltPath.Pour.ROOM and _mp_waiting_for_belt()):
			_say_no_room()
			return
	var want := mini(mini(_fill, int(_pour_owed)), MP_DUMP_BUDGET)
	while want > 0:
		var count := mini(want, Cfg.TUFT_MAX)
		var pose := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), mouth)
		var tuft := live.props.spawn("hay_tuft", pose, {"strands": count}) as HayTuft
		if not is_instance_valid(tuft):
			break
		if tuft.strands != count:
			live.props.remove(tuft)
			break
		tuft.linear_velocity = launch
		tuft.sleeping = false
		_fill -= count
		_pour_owed -= count
		want -= count
		if is_instance_valid(_into):
			_mp_track_flight(tuft, _into)
		if belt == BeltPath.Pour.ROOM:
			_mp_belt_flight = weakref(tuft)
			_mp_belt_launched = Time.get_ticks_msec()
			break
	_draw_fill()

func _mp_router_target() -> Node3D:
	if not is_instance_valid(player) or not is_instance_valid(player.camera) or not is_inside_tree():
		return null
	var camera: Camera3D = player.camera
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * Cfg.VAC_POUR_REACH, Cfg.L_BUILD | Cfg.L_WORLD | Cfg.L_PILE)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var node := hit.get("collider") as Node
	while is_instance_valid(node):
		if node is ConveyorSplitter or node is ConveyorJoiner:
			if not node.placement_preview and "port_count" in node and int(node.get("port_count")) in [4, 6, 8]:
				return node as Node3D
			return null
		node = node.get_parent()
	return null

func _mp_pour_router(delta: float) -> bool:
	if not is_instance_valid(_mp_router_target()):
		return false
	_pour_owed = minf(_pour_owed + Cfg.VAC_POUR_RATE * delta, float(_fill))
	_mp_router_pour_wait = maxf(0.0, _mp_router_pour_wait - delta)
	if _mp_router_pour_wait > 0.0 or not is_instance_valid(live) or not is_instance_valid(live.props):
		return true
	var count := mini(mini(_fill, int(_pour_owed)), Cfg.TUFT_MAX)
	if count <= 0:
		return true
	var mouth := mouth_position()
	var pose := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), mouth)
	var tuft := live.props.spawn("hay_tuft", pose, {"strands": count}) as HayTuft
	if not is_instance_valid(tuft):
		return true
	if tuft.strands != count:
		live.props.remove(tuft)
		return true
	tuft.linear_velocity = _pour_launch(mouth)
	tuft.sleeping = false
	_fill -= count
	_pour_owed -= count
	_mp_router_pour_wait = MP_DUMP_INTERVAL
	_draw_fill()
	return true

func _mp_waiting_for_belt() -> bool:
	if _mp_belt_flight == null:
		return false
	var body: Variant = _mp_belt_flight.get_ref()
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and not BeltPath.is_rider(body) and Time.get_ticks_msec() - _mp_belt_launched < 1000

func _unload(into: Node3D, delta: float) -> void:
	if mp_dump_all:
		if not is_instance_valid(into) or _room_in(into) <= 0:
			_say_no_room()
			return
		_pour_owed = minf(_pour_owed, float(_room_in(into)))
		_pour_straw(delta)
		return
	super._unload(into, delta)

func _pour_launch(from: Vector3) -> Vector3:
	if mp_dump_all and is_instance_valid(_into):
		return _arc_to(from, _into_point(_into))
	return super._pour_launch(from)

func _take_falling(body: RigidBody3D) -> void:
	if mp_dump_all and is_instance_valid(_into):
		_mp_track_flight(body, _into)
		return
	super._take_falling(body)

func _mp_track_flight(body: RigidBody3D, target: Node3D) -> void:
	var id := body.get_instance_id()
	if _mp_flights.has(id):
		return
	var gone := _mp_forget_flight.bind(id)
	_mp_flights[id] = {"body": weakref(body), "target": weakref(target), "gone": gone, "launched": Time.get_ticks_msec()}
	body.tree_exiting.connect(gone, CONNECT_ONE_SHOT)

func _takes_poured(t) -> bool:
	if not super._takes_poured(t):
		return false
	if is_instance_valid(mp_tools) and not mp_tools.owns_poured_heap(t):
		return false
	return true

func _room_in(into: Node3D) -> int:
	var room := super._room_in(into)
	for id in _mp_flights.keys():
		var flight: Dictionary = _mp_flights[id]
		var body: Variant = flight.body.get_ref()
		if not is_instance_valid(body) or Time.get_ticks_msec() - int(flight.launched) > 3000:
			_mp_forget_flight(id)
			continue
		if flight.target.get_ref() == into and is_instance_valid(body) and body.is_inside_tree():
			room -= body.strands if body is HayTuft else 1
	return maxi(room, 0)

func _mp_forget_flight(id: int) -> void:
	var flight: Dictionary = _mp_flights.get(id, {})
	_mp_flights.erase(id)
	if flight.is_empty():
		return
	var body: Variant = flight.body.get_ref()
	if is_instance_valid(body) and body.tree_exiting.is_connected(flight.gone):
		body.tree_exiting.disconnect(flight.gone)

func mp_release_flights() -> void:
	_mp_belt_flight = null
	for id in _mp_flights.keys():
		_mp_forget_flight(id)

func _take_needle(body: RigidBody3D) -> void:
	var service: Node = mp_tools.mp.world_sync.needles_sync if is_instance_valid(mp_tools) and is_instance_valid(mp_tools.mp.world_sync) else null
	if service != null and service.active() and not service.take(body, "vacuum"):
		return
	super._take_needle(body)

func mp_accept_needle(body: RigidBody3D) -> bool:
	if not _active or not is_instance_valid(body):
		return false
	super._take_needle(body)
	return _inbound.has(body.get_instance_id()) or _needles.has(body)

func _let_needle_out(body: RigidBody3D, at: Vector3, velocity: Vector3) -> void:
	super._let_needle_out(body, at, velocity)
	if is_instance_valid(mp_tools) and is_instance_valid(mp_tools.mp.world_sync.needles_sync):
		mp_tools.mp.world_sync.needles_sync.released(body)

func _draw_fill() -> void:
	super._draw_fill()
	if is_instance_valid(mp_tools) and is_instance_valid(mp_tools.mp.world_sync):
		var transfer: Node = mp_tools.mp.world_sync.get("vacuum_transfer")
		if is_instance_valid(transfer):
			transfer.capture_fill(self)
