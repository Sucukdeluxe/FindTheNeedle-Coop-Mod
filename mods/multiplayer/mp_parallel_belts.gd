extends RefCounted

const GAP := 0.10
const WINDOW := 0.65
static var _owner: WeakRef
static var _paths: Array[PackedVector3Array] = []

static func invalidate() -> void:
	_paths.clear()

static func _key(at: Vector3) -> Vector3i:
	return Vector3i(roundi(at.x * 1000.0), roundi(at.y * 1000.0), roundi(at.z * 1000.0))

static func _chains(builds: Node) -> Array[PackedVector3Array]:
	if _owner == null or _owner.get_ref() != builds:
		_owner = weakref(builds)
		_paths.clear()
		if not builds.changed.is_connected(invalidate):
			builds.changed.connect(invalidate)
	if not _paths.is_empty():
		return _paths
	var edges := []
	var joints := {}
	for run in builds.conveyors:
		if not is_instance_valid(run) or not run.is_inside_tree() or run.is_queued_for_deletion():
			continue
		if Vector2(run.b.x - run.a.x, run.b.z - run.a.z).length() < 0.01:
			continue
		var index := edges.size()
		edges.append([run.a, run.b])
		for point: Vector3 in [run.a, run.b]:
			var key := _key(point)
			if not joints.has(key):
				joints[key] = []
			joints[key].append(index)
	var used := {}
	for index in edges.size():
		if used.has(index):
			continue
		used[index] = true
		var chain := PackedVector3Array(edges[index])
		for reverse in [false, true]:
			if reverse:
				chain.reverse()
			while chain.size() <= 512:
				var links: Array = joints.get(_key(chain[-1]), [])
				if links.size() != 2:
					break
				var next := -1
				for link: int in links:
					if not used.has(link):
						next = link
				if next < 0:
					break
				used[next] = true
				var edge: Array = edges[next]
				chain.append(edge[1] if _key(edge[0]) == _key(chain[-1]) else edge[0])
		var tidy := PackedVector3Array([chain[0]])
		for i in range(1, chain.size() - 1):
			if (chain[i] - tidy[-1]).normalized().dot((chain[i + 1] - chain[i]).normalized()) < 0.99999:
				tidy.append(chain[i])
		tidy.append(chain[-1])
		_paths.append(tidy)
	return _paths

static func _side(direction: Vector3) -> Vector3:
	return Vector3(direction.z, 0.0, -direction.x).normalized()

static func offset_path(chain: PackedVector3Array, distance: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if chain.size() < 2:
		return out
	out.append(chain[0] + _side(chain[1] - chain[0]) * distance)
	for i in range(1, chain.size() - 1):
		var before := _side(chain[i] - chain[i - 1])
		var after := _side(chain[i + 1] - chain[i])
		var sum := before + after
		var denominator := sum.dot(after)
		if denominator < 0.1:
			return PackedVector3Array()
		out.append(chain[i] + sum * (distance / denominator))
	out.append(chain[-1] + _side(chain[-1] - chain[-2]) * distance)
	return out

static func _nearest(path: PackedVector3Array, point: Vector3, quantize: bool) -> Dictionary:
	var best := {}
	var score := INF
	for i in path.size() - 1:
		var delta := path[i + 1] - path[i]
		var flat := Vector2(delta.x, delta.z)
		var length := flat.length()
		if length < 0.001:
			continue
		var along := clampf(Vector2(point.x - path[i].x, point.z - path[i].z).dot(flat / length), 0.0, length)
		if quantize:
			along = clampf(snappedf(along, 0.25), 0.0, length)
			if along < 0.3:
				along = 0.0
			elif length - along < 0.3:
				along = length
		var at := path[i] + delta * (along / length)
		var current := Vector2(at.x - point.x, at.z - point.z).length_squared()
		if current < score:
			score = current
			best = {"point": at, "segment": i, "fraction": along / length, "distance": sqrt(score), "direction": delta.normalized()}
	return best

static func alignment(builds: Node, at: Vector3, anchor := Vector3.INF) -> Dictionary:
	if not is_instance_valid(builds) or not at.is_finite():
		return {}
	var best := {}
	var score := INF
	for chain in _chains(builds):
		for sign in [-1.0, 1.0]:
			var path := offset_path(chain, (Cfg.BELT_WIDTH + GAP) * sign)
			if path.size() < 2:
				continue
			var start := _nearest(path, anchor, false) if anchor.is_finite() else {}
			if anchor.is_finite() and (start.is_empty() or start.point.distance_to(anchor) > 0.04):
				continue
			var end := _nearest(path, at, true)
			if end.is_empty() or float(end.distance) > WINDOW or (not anchor.is_finite() and absf(end.point.y - at.y) > 0.8):
				continue
			if float(end.distance) < score:
				score = end.distance
				best = end.duplicate()
				best.path = path
				best.start = start
	return best

static func snap(builds: Node, at: Vector3, anchor := Vector3.INF) -> Vector3:
	return alignment(builds, at, anchor).get("point", at)

static func route(builds: Node, from: Vector3, to: Vector3) -> PackedVector3Array:
	var match := alignment(builds, to, from)
	if match.is_empty() or match.point.distance_to(to) > 0.04:
		return PackedVector3Array()
	var path: PackedVector3Array = match.path
	var start: Dictionary = match.start
	var reverse: bool = float(start.segment) + float(start.fraction) > float(match.segment) + float(match.fraction)
	var first: Dictionary = match if reverse else start
	var last: Dictionary = start if reverse else match
	var out := PackedVector3Array([first.point])
	for i in range(int(first.segment) + 1, int(last.segment) + 1):
		if out[-1].distance_to(path[i]) > 0.01:
			out.append(path[i])
	if out[-1].distance_to(last.point) > 0.01:
		out.append(last.point)
	if reverse:
		out.reverse()
	return out
