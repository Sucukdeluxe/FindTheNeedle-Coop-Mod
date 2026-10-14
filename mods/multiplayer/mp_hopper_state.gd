extends RefCounted

const VERSION := 1
const CAPACITY := 50000
const LIMIT := 32
const COST := 2500.0

static func empty() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "rows": []}

static func valid(data: Variant) -> bool:
	if not (data is Dictionary) or not (data.get("version") is int) or data.get("version") != VERSION:
		return false
	if not (data.get("next_id") is int) or data.next_id < 1 or data.next_id > 2147483647:
		return false
	if not (data.get("rows") is Array) or data.rows.size() > LIMIT:
		return false
	var used := {}
	for row in data.rows:
		if not (row is Dictionary) or row.size() != 5:
			return false
		var id: Variant = row.get("id")
		var at: Variant = row.get("position")
		var yaw: Variant = row.get("yaw")
		var amount: Variant = row.get("stored")
		var paused: Variant = row.get("paused")
		if not (id is int) or id < 1 or id >= data.next_id or used.has(id):
			return false
		if not (at is Vector3) or not at.is_finite() or at.length() > 10000.0:
			return false
		if not (yaw is float or yaw is int) or not is_finite(float(yaw)) or absf(float(yaw)) > TAU:
			return false
		if not (amount is int) or amount < 0 or amount > CAPACITY or not (paused is bool):
			return false
		used[id] = true
	return true

static func transfer(row: Dictionary, available: int) -> int:
	if available <= 0:
		return 0
	var moved := mini(available, maxi(0, CAPACITY - int(row.get("stored", CAPACITY))))
	row["stored"] = int(row.get("stored", 0)) + moved
	return moved

static func output(row: Dictionary, portion: int, insert: Callable) -> int:
	if bool(row.get("paused", false)) or portion <= 0 or not insert.is_valid():
		return 0
	var count := mini(int(row.get("stored", 0)), mini(portion, 1000))
	if count <= 0 or not bool(insert.call(count)):
		return 0
	row["stored"] = int(row.stored) - count
	return count
