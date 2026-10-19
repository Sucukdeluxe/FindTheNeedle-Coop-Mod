extends "res://scripts/build/power_grid.gd"

var mp_power: Node

func _init(manager: BuildManager = null) -> void:
	super(manager)

func _power_remote() -> bool:
	return is_instance_valid(mp_power) and mp_power.mp.active() and not mp_power.applying

func switch_line(node: Node3D, off: bool) -> int:
	if not _power_remote():
		return super.switch_line(node, off)
	mp_power.request_switch(node, off, true)
	return 0

func switch_pole(pole: PowerPole, off: bool) -> int:
	if not _power_remote():
		return super.switch_pole(pole, off)
	mp_power.request_switch(pole, off, false)
	return 0
