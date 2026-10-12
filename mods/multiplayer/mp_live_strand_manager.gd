extends "res://scripts/hay/live_strand_manager.gd"

const Cargo = preload("res://mods/multiplayer/mp_lift_cargo.gd")

var mp_strands: Node


func _hold_transport() -> Array:
	if not is_instance_valid(mp_strands) or not is_instance_valid(mp_strands.mp) or not mp_strands.mp.active():
		return []
	return Cargo.hold_bodies(mp_strands.mp.world_sync)


func _reclaim_pass() -> void:
	var saved := _hold_transport()
	super._reclaim_pass()
	Cargo.release_bodies(saved)


func _drain(budget: int, here: Vector3, keep: float) -> int:
	var saved := _hold_transport()
	var retired := super._drain(budget, here, keep)
	Cargo.release_bodies(saved)
	return retired


func _take_body() -> RigidBody3D:
	var saved := _hold_transport()
	var body := super._take_body()
	Cargo.release_bodies(saved)
	return body
