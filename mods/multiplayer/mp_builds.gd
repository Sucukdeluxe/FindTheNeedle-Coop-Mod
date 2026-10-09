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


func upgrade_arm(arm: RoboticArm) -> bool:
	if not is_instance_valid(mp_world) or not is_instance_valid(mp_world.economy) or not mp_world.mp.active() or mp_world.economy.executing:
		return super.upgrade_arm(arm)
	var actor: Player = mp_world.player
	return mp_world.economy.request("arm_upgrade", {"target": arm.to_dict(),
		"tier": arm.tier_index, "max_price": arm_upgrade_price(arm),
		"body": actor.global_transform, "camera": actor.camera.global_transform}) != 0


func demolish_blocked_reason(building: Node3D) -> String:
	if is_instance_valid(mp_world) and mp_world._is_client() and mp_world._applying_builds:
		return ""
	return super.demolish_blocked_reason(building)
