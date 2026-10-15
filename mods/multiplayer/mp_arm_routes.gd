extends RefCounted

static func usable(path: Variant) -> bool:
	return is_instance_valid(path) and path is BeltPath and path.is_inside_tree() \
		and not path.is_queued_for_deletion() and path.path_length() > 0.01

static func owner_of(path: BeltPath) -> Node:
	if not usable(path):
		return null
	var parent := path.get_parent()
	return parent if parent is ConveyorJoiner or parent is ConveyorSplitter else null

static func paths(machine: Node, dropping := false) -> Array:
	var result := []
	if not is_instance_valid(machine) or machine.is_queued_for_deletion() or machine.placement_preview:
		return result
	if machine is ConveyorJoiner:
		result = machine._arms.values() if dropping else machine.paths()
	elif machine is ConveyorSplitter:
		result = machine.routes()
		if dropping:
			var open := int(machine._open_side())
			var chosen: Variant = machine.route(open)
			if usable(chosen):
				result = [chosen]
	return result.filter(func(path: Variant) -> bool: return usable(path))

static func all(builds: Node, dropping := false) -> Array:
	var result := []
	if is_instance_valid(builds):
		for machine in builds.joiners + builds.splitters:
			result.append_array(paths(machine, dropping))
	return result

static func point(path: BeltPath, near: Vector3, dropping := false) -> Vector3:
	var along := path.s_at(near)
	var owner := owner_of(path)
	if dropping and owner is ConveyorSplitter:
		along = minf(along, path.s_at(owner.global_position))
	return path._point_at(along)

static func closest(machine: Node, near: Vector3, dropping := false) -> BeltPath:
	var found: BeltPath
	var distance := INF
	for path in paths(machine, dropping):
		var d := point(path, near, dropping).distance_squared_to(near)
		if d < distance:
			distance = d
			found = path
	return found

static func from_hit(collider: Node, near: Vector3) -> BeltPath:
	var current := collider
	for depth in 8:
		if not is_instance_valid(current):
			break
		if current is ConveyorJoiner or current is ConveyorSplitter:
			return closest(current, near)
		current = current.get_parent()
	return null

static func drop_path(path: BeltPath, at: Vector3) -> BeltPath:
	var owner := owner_of(path)
	return closest(owner, at, true) if owner != null else path

static func valid_drop(path: BeltPath, at: Vector3) -> bool:
	var owner := owner_of(path)
	if owner is ConveyorJoiner:
		return path in owner._arms.values()
	if owner is ConveyorSplitter:
		return path.s_at(at) <= path.s_at(owner.global_position) + 0.02
	return owner == null

static func drops(builds: Node, from: Vector3, reach: float, only: BeltPath = null) -> Array:
	var result := []
	var candidates := [only] if only != null else all(builds, true)
	for candidate in candidates:
		var path: BeltPath = candidate
		if owner_of(path) == null or not usable(path):
			continue
		var deck := point(path, from, true)
		if not valid_drop(path, deck):
			continue
		var at := deck + path._basis_at(path.s_at(deck)).y * 0.26
		var distance := from.distance_squared_to(at)
		if distance < reach * reach:
			result.append({"conveyor": path, "point": at,
				"forward": -path._basis_at(path.s_at(deck)).z, "distance2": distance})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance2 < b.distance2)
	return result
