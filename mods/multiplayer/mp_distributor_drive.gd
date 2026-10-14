extends RefCounted

static func scale() -> float:
	if not Tech.has_method("distributor_speed_scale"):
		return 1.0
	var value := float(Tech.call("distributor_speed_scale"))
	return clampf(value, 1.0, 2.5) if is_finite(value) else 1.0

static func apply(path: Node) -> bool:
	if not is_instance_valid(path) or path.is_queued_for_deletion() or not path.is_inside_tree():
		return false
	var machine: Node = path.get_parent()
	if not (machine is ConveyorSplitter or machine is ConveyorJoiner) or machine.placement_preview:
		return false
	var speed := float(Tech.belt_speed()) * scale()
	if not is_finite(speed) or speed <= 0.0:
		return false
	path.set_drive_speed(speed)
	return true
