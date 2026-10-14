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


func sweep_floor() -> int:
	if not preload("res://mods/multiplayer/mp_sweep.gd").native_allowed(self):
		return 0
	return _mp_sweep(false).size()

func mp_sweep_collect() -> Array:
	var service := preload("res://mods/multiplayer/mp_sweep.gd").find_service(self)
	if not is_instance_valid(service) or not service.executing or not service.mp.active() or service.mp.is_host:
		return []
	return _mp_sweep(true)

func _mp_sweep(consume_only: bool) -> Array:
	var rows: Array = []
	for body in _active.duplicate():
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		if body.has_meta("mp_ghost") or body.has_meta(META_LOCAL_VISUAL) or body.has_meta("needle_index"):
			continue
		if _is_held(body) or body.has_meta(META_GLIDE) or body.has_meta(META_RIDER) or Cargo.is_transported(body):
			continue
		if rows.size() >= preload("res://mods/multiplayer/mp_sweep.gd").MAX_STRANDS:
			break
		var position: Vector3 = body.global_position
		var settled := float(body.get_meta(META_REST, 0.0)) >= Cfg.STRAND_RECLAIM_REST
		if consume_only:
			if not consume(body):
				continue
		else:
			_retire(body, settled)
		rows.append([position, settled])
	return rows

func _is_lost(body: RigidBody3D) -> bool:
	if _is_held(body):
		return false
	return super._is_lost(body)
