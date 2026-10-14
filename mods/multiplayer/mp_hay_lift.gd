extends HayLift

var mp_transport: Node

func _take(body: RigidBody3D, at: Dictionary) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion():
		return
	if body is HayTuft:
		BeltPath.release(body)
		LiveStrandManager.unpin(body)
		_take_body_as_record(body, at, BeltRun.Kind.TUFT)
		return
	super._take(body, at)

func _carry(delta: float) -> void:
	for index in range(_carried.size() - 1, -1, -1):
		var row: Dictionary = _carried[index]
		var body: Variant = row.get("body")
		if not is_instance_valid(body) or not body is HayTuft or not body.is_inside_tree() \
				or not body.has_meta(META_CARRIED) or not is_same(body.get_meta(META_CARRIED), self) or not body.freeze:
			continue
		_carried.remove_at(index)
		_unfit(row)
		_take(body, {"s": row.s, "sink": row.sink})
	super._carry(delta)

func _follow_tech() -> void:
	super._follow_tech()
	if Tech.has_method("hay_lift_speed_scale"):
		_speed *= float(Tech.call("hay_lift_speed_scale"))
	var direction := -1.0 if down else 1.0
	if _anim != null:
		_anim.speed_scale = direction * _speed / Cfg.HAY_LIFT_SPEED
	if _belt_mat != null:
		_belt_mat.set_shader_parameter("speed", direction * _speed)
