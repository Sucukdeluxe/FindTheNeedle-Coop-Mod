extends "res://scripts/tools/yard_vac.gd"

const MP_DUMP_BUDGET := 64
const MP_DUMP_INTERVAL := 0.1
var mp_dump_all := false
var mp_tools: Node
var _mp_dump_wait := 0.0
var _mp_flights := {}

func mp_cancel_dump() -> void:
	if not mp_dump_all:
		return
	mp_dump_all = false
	_mp_dump_wait = 0.0
	set_pouring(false)

func _physics_process(delta: float) -> void:
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
	if mp_dump_all:
		var mouth := mouth_position()
		if BeltPath.pour_verdict(mouth, _pour_launch(mouth), _tuft_reach()) == BeltPath.Pour.NO_ROOM:
			_say_no_room()
			return
	super._pour_straw(delta)

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
		var id := body.get_instance_id()
		var gone := _mp_forget_flight.bind(id)
		_mp_flights[id] = {"body": weakref(body), "target": weakref(_into), "gone": gone}
		body.tree_exiting.connect(gone, CONNECT_ONE_SHOT)
		return
	super._take_falling(body)

func _takes_poured(t) -> bool:
	if not super._takes_poured(t):
		return false
	if is_instance_valid(mp_tools) and not mp_tools.owns_poured_heap(t):
		return false
	return true

func _room_in(into: Node3D) -> int:
	var room := super._room_in(into)
	for flight in _mp_flights.values():
		var body: Variant = flight.body.get_ref()
		if flight.target.get_ref() == into and is_instance_valid(body) and body.is_inside_tree():
			room -= 1
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
	for id in _mp_flights.keys():
		_mp_forget_flight(id)
