extends "res://scripts/hay/live_strand_manager.gd"

const Cargo = preload("res://mods/multiplayer/mp_lift_cargo.gd")

var mp_strands: Node


func _hold_transport() -> Array:
	if not is_instance_valid(mp_strands) or not is_instance_valid(mp_strands.mp) or not mp_strands.mp.active():
		return []
	return Cargo.hold_bodies(mp_strands.mp.world_sync)


func _reclaim_pass() -> void:
	if not _automatic_cleanup_enabled():
		return
	var saved := _hold_transport()
	super._reclaim_pass()
	Cargo.release_bodies(saved)


func _drain(budget: int, here: Vector3, keep: float) -> int:
	if not _automatic_cleanup_enabled():
		return 0
	var saved := _hold_transport()
	var retired := super._drain(budget, here, keep)
	Cargo.release_bodies(saved)
	return retired


func _take_body() -> RigidBody3D:
	if not _automatic_cleanup_enabled():
		if _pool.is_empty():
			_grow_pool(_active.size() + 64)
			var needed := _active.size() + _pool.size()
			if needed > _capacity:
				_capacity = needed
				_mm.instance_count = _capacity
				_mm.visible_instance_count = 0
				_shown = 0
		return _pool.pop_back()
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
	if not _automatic_cleanup_enabled():
		if super._is_lost(body):
			var position := body.global_position
			position.y = maxf(FLOOR_Y, field.height_at(position.x, position.z) if field != null else FLOOR_Y) + Cfg.STRAND_LEN_MAX * 0.5
			body.global_position = position
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.sleeping = true
		return false
	return super._is_lost(body)

func _automatic_cleanup_enabled() -> bool:
	if is_instance_valid(mp_strands) and is_instance_valid(mp_strands.mp) and mp_strands.mp.active():
		var sync: Node = mp_strands.mp.world_sync
		if is_instance_valid(sync) and is_instance_valid(sync.props_sync):
			return bool(sync.props_sync.cleanup_policy().get("auto_clean", Cfg.auto_clean))
	return Cfg.auto_clean

func fold_away(body: RigidBody3D) -> bool:
	if not _automatic_cleanup_enabled():
		return false
	return super.fold_away(body)
