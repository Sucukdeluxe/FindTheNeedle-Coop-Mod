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


func take(item: Carryable) -> bool:
	if _needs_claim(item):
		return mp_belts.mp.world_sync.props_sync.request_claim(int(item.get_meta("mp_id")), "carry")
	return super.take(item)

func stack_on(item: Carryable) -> bool:
	if _needs_claim(item):
		return mp_belts.mp.world_sync.props_sync.request_claim(int(item.get_meta("mp_id")), "stack")
	return super.stack_on(item)

func _needs_claim(item: Carryable) -> bool:
	if not is_instance_valid(mp_belts) or not mp_belts.mp.active() or not is_instance_valid(item):
		return false
	if not item.has_meta("mp_id"):
		return false
	return not mp_belts.mp.world_sync.props_sync._mine(int(item.get_meta("mp_id")))
