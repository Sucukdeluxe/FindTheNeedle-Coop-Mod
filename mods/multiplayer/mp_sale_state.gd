extends RefCounted

const LIMIT := 5
const COST := 500.0
const UPGRADE_COSTS := [1000.0, 2500.0, 5000.0, 10000.0]

static func fresh(at: Vector3, yaw: float) -> Dictionary:
	return {"version": 1, "next_id": 2, "rows": [{"id": 1, "position": at, "yaw": yaw, "revision": 0}]}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("rows") is Array or not value.get("next_id") is int:
		return false
	if value.rows.is_empty() or value.rows.size() > LIMIT or value.next_id < 2:
		return false
	var seen := {}
	for row in value.rows:
		if not row is Dictionary or not row.get("id") is int or row.id < 1 or row.id >= value.next_id or seen.has(row.id):
			return false
		if not row.get("position") is Vector3 or not row.position.is_finite() or row.position.length() > 10000.0:
			return false
		if not (row.get("yaw") is float or row.get("yaw") is int) or not is_finite(float(row.yaw)) or absf(float(row.yaw)) > TAU:
			return false
		if not row.get("revision") is int or row.revision < 0:
			return false
		seen[row.id] = true
	return seen.has(1)
