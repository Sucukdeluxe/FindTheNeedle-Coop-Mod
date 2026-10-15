extends RefCounted

const VERSION := 2
const CAPACITY := 100000
const LIMIT := 32
const COST := 2500.0
const UPGRADE_COSTS := [1000, 1500, 2000, 2500, 3000, 4000, 5000, 6500, 8000]

static func empty() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "rows": []}

static func capacity(row: Dictionary) -> int:
	return 10000 * (1 + int(row.get("level", 4)))

static func create(id: int, at: Vector3, yaw: float) -> Dictionary:
	return {"id": id, "position": at, "yaw": yaw, "stored": 0, "paused": false, "level": 0, "portion": 1000, "revision": 0, "needles": [], "arms": []}

static func migrate(data: Dictionary) -> Dictionary:
	if not valid(data):
		return {}
	var out := data.duplicate(true)
	if int(out.version) == 1:
		out.version = VERSION
		for row in out.rows:
			row.level = 4
			row.portion = 1000
			row.revision = 0
			row.needles = []
			row.arms = []
	return out

static func valid(data: Variant) -> bool:
	if not (data is Dictionary) or not (data.get("version") is int) or int(data.version) not in [1, VERSION]:
		return false
	if not (data.get("next_id") is int) or data.next_id < 1 or data.next_id > 2147483647:
		return false
	if not (data.get("rows") is Array) or data.rows.size() > LIMIT:
		return false
	var used := {}
	for row in data.rows:
		if not (row is Dictionary) or row.size() != (5 if data.version == 1 else 10):
			return false
		var id: Variant = row.get("id")
		var at: Variant = row.get("position")
		var yaw: Variant = row.get("yaw")
		var amount: Variant = row.get("stored")
		if not (id is int) or id < 1 or id >= data.next_id or used.has(id):
			return false
		if not (at is Vector3) or not at.is_finite() or at.length() > 10000.0:
			return false
		if not (yaw is float or yaw is int) or not is_finite(float(yaw)) or absf(float(yaw)) > TAU:
			return false
		if data.version == VERSION:
			if not (row.get("level") is int) or row.level < 0 or row.level > 9:
				return false
			if not (row.get("portion") is int) or row.portion < 100 or row.portion > 1000 or row.portion % 100 != 0:
				return false
			if not (row.get("revision") is int) or row.revision < 0:
				return false
			if not (row.get("needles") is Array) or row.needles.size() > 4096 or (amount is int and row.needles.size() > amount) or not (row.get("arms") is Array) or row.arms.size() > 128:
				return false
			var needles := {}
			for needle in row.needles:
				if not (needle is int) or needle < 0 or needles.has(needle):
					return false
				needles[needle] = true
			for arm in row.arms:
				if not (arm is Vector3) or not arm.is_finite() or arm.length() > 10000.0:
					return false
		if not (amount is int) or amount < 0 or amount > capacity(row) or not (row.get("paused") is bool):
			return false
		used[id] = true
	return true

static func transfer(row: Dictionary, available: int) -> int:
	if available <= 0:
		return 0
	var moved := mini(available, maxi(0, capacity(row) - int(row.get("stored", capacity(row)))))
	row["stored"] = int(row.get("stored", 0)) + moved
	return moved

static func output(row: Dictionary, portion: int, insert: Callable) -> int:
	if bool(row.get("paused", false)) or portion <= 0 or not insert.is_valid():
		return 0
	var count := mini(int(row.get("stored", 0)), mini(portion, int(row.get("portion", 1000))))
	if row.get("needles", []).size() > 1:
		count = mini(count, int(row.stored) - row.needles.size() + 1)
	if count <= 0 or not bool(insert.call(count)):
		return 0
	row["stored"] = int(row.stored) - count
	return count
