extends RefCounted

const GAP := 0.10
const WINDOW := 0.65

static func snap(builds: Node, at: Vector3, anchor := Vector3.INF) -> Vector3:
	if not is_instance_valid(builds) or not at.is_finite():
		return at
	var result := at
	var distance := INF
	for run in builds.conveyors:
		if not is_instance_valid(run) or not run.is_inside_tree() or run.is_queued_for_deletion():
			continue
		if absf(run.a.y - run.b.y) > 0.02 or absf(at.y - run.a.y) > 0.8:
			continue
		var start: Vector3 = run.a
		var delta: Vector3 = run.b - start
		var length := delta.length()
		if length < Cfg.BELT_MIN_LENGTH:
			continue
		var direction := delta / length
		var side := Vector3(direction.z, 0.0, -direction.x)
		var spacing := Cfg.BELT_WIDTH + GAP
		var side_distance := (at - start).dot(side)
		var sign := 1.0 if side_distance >= 0.0 else -1.0
		if anchor.is_finite():
			var anchor_side := (anchor - start).dot(side)
			if absf(absf(anchor_side) - spacing) > 0.03 or absf(anchor.y - start.y) > 0.03:
				continue
			sign = 1.0 if anchor_side >= 0.0 else -1.0
		if absf(side_distance - sign * spacing) > WINDOW and absf(side_distance) > Cfg.BELT_WIDTH * 0.5:
			continue
		var along := (at - start).dot(direction)
		if along < -0.5 or along > length + 0.5:
			continue
		along = clampf(snappedf(along, 0.25), 0.0, length)
		if along < 0.3:
			along = 0.0
		elif length - along < 0.3:
			along = length
		var candidate := start + direction * along + side * sign * spacing
		var score := candidate.distance_squared_to(at)
		if score < distance:
			distance = score
			result = candidate
	return result
