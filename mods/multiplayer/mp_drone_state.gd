extends RefCounted

static func valid(field: String, value: Variant) -> bool:
	if field == "switched_off":
		return value is bool
	if field == "mode":
		return value is int and value >= HayDrone.Mode.DIG and value <= HayDrone.Mode.COLLECT
	if field == "takes":
		return value is int and value >= 0 and (value & ~(HayDrone.collect_all() | HayDrone.NOTHING)) == 0
	if field != "mp_zone" and field != "mp_drop":
		return false
	if not (value is Array) or value.size() != 2 or not (value[0] is Vector3):
		return false
	if value[0] != Vector3.INF and not value[0].is_finite():
		return false
	if field == "mp_zone":
		return (value[1] is int or value[1] is float) and is_finite(float(value[1])) and value[1] > 0.0
	return value[1] is int and value[1] >= HayDrone.Drop.NONE and value[1] <= HayDrone.Drop.FLOOR and ((value[0] == Vector3.INF) == (value[1] == HayDrone.Drop.NONE))

static func apply_snapshot(node: Node, field: String, value: Variant) -> void:
	if not valid(field, value):
		return
	if field == "switched_off":
		node.set_switched_off(value)
		return
	if field == "mp_zone":
		node.zone_at = value[0]
		node.zone_r = float(value[1])
	elif field == "mp_drop":
		node.drop_at = value[0]
		node.drop_kind = int(value[1])
		node.set("_drop_run", null)
	else:
		node.set(field, value)
	node.set("_route_dirty", true)
	node.set("_job_key", "")
