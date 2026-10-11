extends RefCounted

static func valid(entries: Array) -> bool:
	for entry in entries:
		if not (entry is Dictionary):
			return false
		for key in ["a", "b"]:
			var endpoint: Variant = entry.get(key)
			if not (endpoint is Vector3) or not endpoint.is_finite():
				return false
		var rows: Variant = entry.get("records")
		if not (rows is Array):
			return false
		for row in rows:
			if not (row is Dictionary):
				return false
			var kind: Variant = row.get("kind")
			if not (kind is int) or kind < 0 or kind >= BeltRun.ITEM_IDS.size():
				return false
			var strands: Variant = row.get("strands")
			if not (strands is int) or strands < 0:
				return false
			var needle: Variant = row.get("needle", -1)
			if not (needle is int) or needle < -1:
				return false
			for key in ["reach", "side", "lift", "s", "speed"]:
				var value: Variant = row.get(key, 0.0)
				if not (value is float or value is int) or not is_finite(float(value)):
					return false
			if not (row.get("state", {}) is Dictionary):
				return false
	return true
