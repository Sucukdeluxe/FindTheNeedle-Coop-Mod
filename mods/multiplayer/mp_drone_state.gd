extends RefCounted

const STATUS_FIELDS := {
	"_phase": TYPE_INT, "trips": TYPE_INT, "strands_put": TYPE_INT,
	"_load_too_long": TYPE_BOOL, "_route_dirty": TYPE_BOOL,
	"_route_why": TYPE_STRING, "_route_leg": TYPE_INT, "_route_block": TYPE_VECTOR3,
	"_route_block_name": TYPE_STRING, "_stall": TYPE_STRING, "_empty_why": TYPE_INT,
	"_crowd_sign": TYPE_BOOL, "_wait_traffic": TYPE_BOOL, "_wait": TYPE_STRING,
}

static func status(node: Node) -> Dictionary:
	var state := {"drop_full": node._drop_full()}
	for field in STATUS_FIELDS:
		state[field] = node.get(field)
	return state

static func valid_status(value: Variant) -> bool:
	if not (value is Dictionary) or value.size() != STATUS_FIELDS.size() + 1 or not (value.get("drop_full") is bool):
		return false
	for field in STATUS_FIELDS:
		if not value.has(field) or typeof(value[field]) != STATUS_FIELDS[field]:
			return false
		if value[field] is String and value[field].length() > 2048:
			return false
	return value._phase >= HayDrone.Phase.IDLE and value._phase <= HayDrone.Phase.LAND \
		and value.trips >= 0 and value.strands_put >= 0 \
		and value._empty_why >= HayDrone.Empty.DONE and value._empty_why <= HayDrone.Empty.BLOCKED \
		and value._route_leg >= -1 and value._route_leg <= 3 \
		and (value._route_block == Vector3.INF or value._route_block.is_finite())

static func valid(field: String, value: Variant) -> bool:
	if field == "mp_drone_status":
		return valid_status(value)
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
	if field == "mp_drone_status":
		for key in STATUS_FIELDS:
			node.set(key, value[key])
		node.set("_mp_drop_full", value.drop_full)
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
