extends "res://scripts/build/build_manager.gd"

var mp_world: Node


func _clear_mirrored_records() -> void:
	if not is_instance_valid(mp_world) or not mp_world._is_client():
		return
	for path in BeltPath._live:
		if is_instance_valid(path) and path.is_inside_tree():
			path.run.clear()


func reverse_conveyor(conveyor: Conveyor) -> bool:
	_clear_mirrored_records()
	return super.reverse_conveyor(conveyor)


func _demolish_one(building: Node3D) -> float:
	_clear_mirrored_records()
	return super._demolish_one(building)


func clear() -> void:
	_clear_mirrored_records()
	super.clear()
