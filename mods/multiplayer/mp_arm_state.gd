extends RefCounted

const TEXT_FIELDS := ["alert", "icon", "waiting"]
const NUMBER_FIELDS := ["power", "line_power"]

static func capture(arm: Node) -> Dictionary:
	var scoped := arm.has_method("mp_status_begin") and arm.has_method("mp_status_end")
	if scoped:
		arm.mp_status_begin()
	var result := {
		"alert": arm.alert_reason(), "icon": arm.alert_icon(),
		"waiting": arm.waiting_reason(), "clear": arm.is_clear(),
		"plate": arm.plate_status(false), "plate_sign": arm.plate_status(true),
		"rate": arm.hay_per_minute(), "belts": arm.belts_in_reach(),
		"power": arm.power, "line_power": arm.line_power,
		"blocked": arm.power_blocked, "line": arm.power_line,
	}
	if scoped:
		arm.mp_status_end()
	return result

static func valid(value: Variant) -> bool:
	if not (value is Dictionary) or value.size() != 12:
		return false
	for field in TEXT_FIELDS:
		if not (value.get(field) is String) or value[field].length() > 4096:
			return false
	for field in NUMBER_FIELDS:
		if not (value.get(field) is float or value.get(field) is int) or not is_finite(float(value[field])) or value[field] < 0.0 or value[field] > 1.0:
			return false
	for field in ["clear", "blocked"]:
		if not (value.get(field) is bool):
			return false
	for field in ["rate", "belts", "line"]:
		if not (value.get(field) is int) or value[field] < 0:
			return false
	if value.line > MachinePower.LINE_NO_GENERATOR:
		return false
	for field in ["plate", "plate_sign"]:
		var plate: Variant = value.get(field)
		if not (plate is Array) or plate.size() != 2 or not (plate[0] is int) or plate[0] < RoboticArm.PLATE_WORKING or plate[0] > RoboticArm.PLATE_STOPPED or not (plate[1] is String) or plate[1].length() > 4096:
			return false
	return var_to_bytes(value).size() <= 16384
