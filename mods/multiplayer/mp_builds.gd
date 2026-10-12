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


func reshape_hay_lift(lift: HayLift, carries_down: bool, turn: int) -> Dictionary:
	if not is_instance_valid(mp_world) or not mp_world.mp.active():
		return super.reshape_hay_lift(lift, carries_down, turn)
	var out := {"lift": lift, "error": ""}
	var economy: Variant = mp_world.economy
	if is_instance_valid(economy) and economy.executing and mp_world.mp.is_host:
		return super.reshape_hay_lift(lift, carries_down, turn)
	if not is_instance_valid(lift) or not lift.is_inside_tree() or lift.is_queued_for_deletion():
		out["error"] = mp_world.mp.t("building_missing")
		return out
	if turn < 0 or turn > 3:
		out["error"] = mp_world.mp.t("building_invalid")
		return out
	var actor: Variant = mp_world.player
	if not is_instance_valid(economy) or not is_instance_valid(actor) or not is_instance_valid(actor.camera):
		out["error"] = mp_world.mp.t("economy_wait")
		return out
	if economy.request("lift_reshape", {"target": lift.to_dict(), "down": carries_down, "turn": turn,
			"body": actor.global_transform, "camera": actor.camera.global_transform}) == 0:
		out["error"] = mp_world.mp.t("economy_wait")
	return out


func restring_for_reach() -> void:
	if is_instance_valid(mp_world) and mp_world._is_client():
		return
	super.restring_for_reach()
