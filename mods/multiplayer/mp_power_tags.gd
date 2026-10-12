extends "res://scripts/build/power_tags.gd"

var mp_power: Node

func _power_remote() -> bool:
	return is_instance_valid(mp_power) and mp_power.mp.active() and not mp_power.applying

func rename(tag: int, text: String) -> void:
	if _power_remote():
		mp_power.request_tag("rename", tag, text)
	else:
		super.rename(tag, text)

func set_priority(tag: int, level: int) -> void:
	if _power_remote():
		mp_power.request_tag("priority", tag, level)
	else:
		super.set_priority(tag, level)

func set_tag(machine: Node, tag: int) -> void:
	if _power_remote():
		mp_power.request_tag("member", tag, null, machine)
	else:
		super.set_tag(machine, tag)

func switch(tag: int, off: bool) -> int:
	if not _power_remote():
		return super.switch(tag, off)
	mp_power.request_tag("switch", tag, off)
	return 0

func switch_all(off: bool) -> int:
	if not _power_remote():
		return super.switch_all(off)
	mp_power.request_tag("switch_all", -1, off)
	return 0
