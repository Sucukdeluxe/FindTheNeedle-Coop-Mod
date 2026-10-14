extends RefCounted

const SIZES := ["standard", "big", "huge", "mountain"]
const VERSION := 1

static func empty(seed: int = 0) -> Dictionary:
	return {"version": VERSION, "cycles": 0, "seed": seed, "indices": [], "found": [], "last_transaction": ""}

static func normalize(value: Variant, seed: int) -> Dictionary:
	if not value is Dictionary or int(value.get("version", 0)) != VERSION:
		return empty(seed)
	var data := empty(seed)
	data.cycles = maxi(0, int(value.get("cycles", 0)))
	data.seed = int(value.get("seed", seed))
	data.last_transaction = str(value.get("last_transaction", "")).substr(0, 128)
	for key in ["indices", "found"]:
		if value.get(key) is Array:
			for number in value[key]:
				if number is int and number >= 0 and not data[key].has(number):
					data[key].append(number)
	return data

static func found_count(data: Dictionary, discoveries: PackedByteArray, types: PackedInt32Array, seed: int) -> int:
	var found := 0
	for type in types:
		if int(data.get("cycles", 0)) == 0:
			if type >= 0 and type < discoveries.size() and discoveries[type] != 0:
				found += 1
		elif int(data.get("seed", -1)) == seed and data.get("found", []).has(type):
			found += 1
	return found

static func record(data: Dictionary, index: int, type: int, seed: int) -> void:
	if int(data.get("cycles", 0)) <= 0 or int(data.get("seed", -1)) != seed:
		return
	if not data.get("indices", []).has(index):
		return
	if not data.found.has(type):
		data.found.append(type)

static func next_state(previous: Dictionary, seed: int, count: int, transaction: String) -> Dictionary:
	var data := empty(seed)
	data.cycles = int(previous.get("cycles", 0)) + 1
	data.indices = range(count)
	data.last_transaction = transaction
	return data

static func allowed(remaining: float, found: int, count: int) -> bool:
	return is_finite(remaining) and remaining >= 0.0 and remaining < 0.5 and count == 6 and found == count

static func credit(strands: float, worth: float, price: float, debt: float, share: float) -> Dictionary:
	if not is_finite(strands) or not is_finite(worth) or not is_finite(price) or strands < 0.0 or worth < 0.0 or price < 0.0:
		return {}
	var gross := worth * price
	var payment := minf(maxf(0.0, debt), gross * clampf(share, 0.0, 1.0))
	return {"gross": gross, "paid": gross - payment, "debt": maxf(0.0, debt - payment)}
