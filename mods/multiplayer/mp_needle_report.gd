extends RefCounted

static func counts(taken: Variant, kinds: Variant, type_count: int) -> Dictionary:
	if not (taken is PackedByteArray or taken is Array) or not (kinds is PackedByteArray or kinds is Array):
		return {}
	if taken.size() != kinds.size() or taken.size() > 100000 or type_count < 1 or type_count > 256:
		return {}
	var by_type := PackedInt32Array()
	by_type.resize(type_count)
	var total := 0
	for index in taken.size():
		if not taken[index] is int or int(taken[index]) not in [0, 1] or not kinds[index] is int:
			return {}
		var kind := int(kinds[index])
		if kind < 0 or kind >= type_count:
			return {}
		if taken[index] == 0:
			total += 1
			by_type[kind] += 1
	var remaining_types := 0
	for amount in by_type:
		if amount > 0:
			remaining_types += 1
	return {"total": total, "types": remaining_types, "by_type": by_type}

static func line(data: Dictionary, locale: String) -> String:
	var german := locale.begins_with("de")
	if data.is_empty():
		return "Bestand wird synchronisiert." if german else "Synchronizing remaining needles."
	var total := int(data.total)
	var kinds := int(data.types)
	if german:
		return "Noch im Haufen: %s %s · %s %s" % [number(total, "."), "Nadel" if total == 1 else "Nadeln", number(kinds, "."), "Art" if kinds == 1 else "Arten"]
	return "Still in the pile: %s %s · %s %s" % [number(total, ","), "needle" if total == 1 else "needles", number(kinds, ","), "type" if kinds == 1 else "types"]

static func number(value: int, separator: String) -> String:
	var digits := str(maxi(value, 0))
	var out := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			out += separator
		out += digits[index]
	return out
