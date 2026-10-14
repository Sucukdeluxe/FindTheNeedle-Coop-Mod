extends RefCounted

static func row(node: Node) -> Dictionary:
	if node.has_method("mp_snapshot_begin"):
		node.mp_snapshot_begin()
	var data: Dictionary = node.to_dict()
	if node.has_method("mp_snapshot_end"):
		node.mp_snapshot_end()
	return data

static func buildings(builds: Node) -> Array:
	var guarded: Array[Node] = []
	for arm in builds.robotic_arms:
		if is_instance_valid(arm) and arm.has_method("mp_snapshot_begin"):
			arm.mp_snapshot_begin()
			guarded.append(arm)
	var data: Array = builds.to_array()
	for arm in guarded:
		if is_instance_valid(arm):
			arm.mp_snapshot_end()
	return data
