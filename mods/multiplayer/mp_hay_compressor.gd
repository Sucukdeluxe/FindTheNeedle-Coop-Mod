extends "res://scripts/build/hay_compressor.gd"

var mp_transport: Node

func _mp_active() -> bool:
	return is_instance_valid(mp_transport) and is_instance_valid(mp_transport.mp) and mp_transport.mp.active()

func _eats(kind: int, strands: int) -> bool:
	return super._eats(kind, strands) or (_mp_active() and kind == BeltRun.Kind.TUFT)

func _parks(kind: int, strands: int) -> bool:
	return super._parks(kind, strands) or (_mp_active() and kind == BeltRun.Kind.TUFT)

func _held_in_mouth(body: Object) -> bool:
	if _mp_active() and is_instance_valid(body):
		if body is HayWad or (body is RigidBody3D and body.get_parent() is LiveStrandManager):
			return true
	return super._held_in_mouth(body)

func _release_bale() -> void:
	if _mp_active() and not is_instance_valid(props):
		return
	super._release_bale()
