extends "res://scripts/player/carry_tool.gd"

var mp_belts: Node


func _pick_record(onto_stack: bool = false) -> bool:
	if not is_instance_valid(mp_belts) or mp_belts.mp.is_host or not mp_belts.mp.active():
		return super._pick_record(onto_stack)
	var target := _record_under_crosshair()
	if target.is_empty():
		return false
	var record: Dictionary = target.get("record", {})
	if _record_refused(int(record.get("kind", -1))):
		return false
	return mp_belts.request_pick(record, onto_stack)
