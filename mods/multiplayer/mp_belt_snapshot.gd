extends RefCounted

static func valid(entries: Array) -> bool:
	var sequences := {}
	for entry in entries:
		if not (entry is Dictionary):
			return false
		for key in ["a", "b"]:
			var endpoint: Variant = entry.get(key)
			if not (endpoint is Vector3) or not endpoint.is_finite():
				return false
		var line: Variant = entry.get("line")
		if not (entry.get("owner") is String) or not (line is PackedVector3Array) or line.size() < 2:
			return false
		for point in line:
			if not point.is_finite():
				return false
		var rows: Variant = entry.get("records")
		if not (rows is Array):
			return false
		var previous := INF
		for row in rows:
			if not (row is Dictionary):
				return false
			var kind: Variant = row.get("kind")
			if not (kind is int) or kind < 0 or kind >= BeltRun.ITEM_IDS.size():
				return false
			var strands: Variant = row.get("strands")
			if not (strands is int) or strands < 0 or strands > 2147483647:
				return false
			var needle: Variant = row.get("needle")
			if not (needle is int) or needle < -1 or needle > 2147483647:
				return false
			for key in ["reach", "gap", "side", "lift", "s", "speed"]:
				var value: Variant = row.get(key)
				if not (value is float or value is int) or not is_finite(float(value)):
					return false
			var seq: Variant = row.get("seq")
			if not (seq is int) or seq < 0 or seq > 2147483647 or sequences.has(seq):
				return false
			sequences[seq] = true
			if float(row.get("s", 0.0)) > previous + 0.0000001:
				return false
			previous = float(row.get("s", 0.0))
			if row.get("reach", -1.0) < 0.0 or row.get("gap", -1.0) < 0.0:
				return false
			if not (row.get("state") is Dictionary):
				return false
	return true
