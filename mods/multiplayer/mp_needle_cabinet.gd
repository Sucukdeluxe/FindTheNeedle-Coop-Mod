extends "res://scripts/build/needle_cabinet.gd"

var mp_needles: Node

func factory_tick(delta: float) -> void:
	if is_instance_valid(mp_needles) and mp_needles.mp.active() and not mp_needles.mp.is_host:
		return
	super.factory_tick(delta)
