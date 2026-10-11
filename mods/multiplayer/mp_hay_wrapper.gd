extends "res://scripts/build/hay_wrapper.gd"

var mp_transport: Node

func _mp_active() -> bool:
	return is_instance_valid(mp_transport) and is_instance_valid(mp_transport.mp) and mp_transport.mp.active()

func _parks(kind: int, strands: int) -> bool:
	return super._parks(kind, strands) or (_mp_active() and kind == BeltRun.Kind.TUFT)

func _release_product() -> void:
	if _mp_active() and not is_instance_valid(props):
		return
	super._release_product()
