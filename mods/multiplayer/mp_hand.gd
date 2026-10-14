extends "res://scripts/player/hand.gd"

var mp_needles: Node

func _mp_active() -> bool:
	return is_instance_valid(mp_needles) and mp_needles.active()

func _grab(body: RigidBody3D, sound: bool = true) -> void:
	if _mp_active() and body.has_meta("needle_index") and not mp_needles.take(body, "hand"):
		return
	super._grab(body, sound)

func withdraw_from(cabinet: NeedleCabinet, type: int) -> bool:
	if not _mp_active():
		return super.withdraw_from(cabinet, type)
	if is_holding() or cabinet == null:
		return false
	return mp_needles.withdraw(cabinet, type)

func deposit_into(cabinet: NeedleCabinet) -> bool:
	if not _mp_active():
		return super.deposit_into(cabinet)
	var index := held_needle_index()
	if index < 0 or cabinet == null:
		return false
	return mp_needles.deposit(index, cabinet)

func take_needle(index: int, at: Vector3) -> bool:
	if live == null or is_holding():
		return false
	if _mp_active() and not mp_needles.applying and not mp_needles.owns(index):
		return false
	for body in live.needles:
		if is_instance_valid(body) and int(body.get_meta("needle_index", -1)) == index:
			_grab(body)
			return held_needle_index() == index
	if not super.take_needle(index, at):
		return false
	return held_needle_index() == index

func drop_held() -> void:
	var bodies := held_bodies()
	super.drop_held()
	if _mp_active():
		for body in bodies:
			mp_needles.released(body)

func throw_held() -> void:
	var bodies := held_bodies()
	super.throw_held()
	if _mp_active():
		for body in bodies:
			mp_needles.released(body)
