extends RefCounted

const EDGE_EPSILON := 0.04
const HEIGHT_SNAP := 0.5

static func wall_point(builds: Node, raw: Vector3, free: Vector3, native: Vector3, anchor: Vector3, grid: bool) -> Vector3:
	if not is_instance_valid(builds) or not raw.is_finite():
		return native
	var post: Variant = builds.nearest_wall_post(raw)
	if post is Vector3 and Vector2(post.x - raw.x, post.z - raw.z).length() <= Cfg.WALL_SNAP_RADIUS:
		return native
	var best := INF
	var result := native
	var edges := _platform_edges(builds)
	for edge in edges:
		if absf(raw.y - edge.a.y) > HEIGHT_SNAP:
			continue
		var point := Geometry3D.get_closest_point_to_segment(raw, edge.a, edge.b)
		point.y = edge.a.y
		var distance := Vector2(point.x - raw.x, point.z - raw.z).length()
		if distance > Cfg.WALL_SNAP_RADIUS or not _edge_exposed(builds, point, edge.outward):
			continue
		var along: Vector3 = (edge.b - edge.a).normalized()
		if grid:
			var origin: Vector3 = edge.a
			if anchor.is_finite():
				if absf(anchor.y - point.y) > EDGE_EPSILON or absf((anchor - point).cross(along).y) > EDGE_EPSILON:
					continue
				origin = anchor
			point = origin + along * snappedf((point - origin).dot(along), Cfg.WALL_PANEL)
			point = Geometry3D.get_closest_point_to_segment(point, edge.a, edge.b)
		if not _edge_exposed(builds, point, edge.outward):
			continue
		var score := distance + Vector2(point.x - raw.x, point.z - raw.z).length() * 0.05
		if score < best:
			best = score
			result = point
	if best < INF:
		return result
	for edge in edges:
		if absf(native.y - edge.a.y) <= EDGE_EPSILON and Geometry3D.get_closest_point_to_segment(native, edge.a, edge.b).distance_to(native) <= EDGE_EPSILON and not _edge_exposed(builds, native, edge.outward):
			return free
	return native

static func roof_point(builds: Node, eye: Vector3, look: Vector3, reach: float, native: Vector3) -> Vector3:
	if not is_instance_valid(builds) or not eye.is_finite() or not look.is_finite() or not is_finite(reach) or look.length_squared() < 0.5:
		return native
	var direction := look.normalized()
	var limit := maxf(0.0, reach) + Cfg.ROOF_AIM_OVERREACH
	var best := INF
	var result := native
	for wall in builds.walls:
		if not is_instance_valid(wall) or wall.length < 0.001:
			continue
		var a: Vector3 = wall.a + Vector3.UP * Cfg.WALL_HEIGHT
		var b: Vector3 = wall.b + Vector3.UP * Cfg.WALL_HEIGHT
		var closest := Geometry3D.get_closest_points_between_segments(eye, eye + direction * limit, a, b)
		var along := (b - a).normalized()
		var point := a + along * clampf(snappedf((closest[1] - a).dot(along), Cfg.ROOF_BAY), 0.0, wall.length)
		var score := _ray_score(eye, direction, limit, point)
		if score < best:
			best = score
			result = point
	for roof in builds.roofs:
		if not is_instance_valid(roof):
			continue
		for point in roof.joint_points():
			var score := _ray_score(eye, direction, limit, point)
			if score < best:
				best = score
				result = point
	return result

static func roof_heading(builds: Node, point: Vector3, look: Vector3) -> Vector3:
	if not is_instance_valid(builds) or not point.is_finite():
		return Vector3.INF
	var flat := Vector3(look.x, 0.0, look.z)
	flat = flat.normalized() if flat.length_squared() > 0.000001 else Vector3.BACK
	var best := INF
	var result := Vector3.INF
	for roof in builds.roofs:
		if not is_instance_valid(roof) or roof.length < 0.001:
			continue
		for joint in roof.joint_points():
			if joint.distance_to(point) <= EDGE_EPSILON:
				return _heading_for(roof.a, roof.b, point, flat)
	for wall in builds.walls:
		if not is_instance_valid(wall) or wall.length < 0.001:
			continue
		var a: Vector3 = wall.a + Vector3.UP * Cfg.WALL_HEIGHT
		var b: Vector3 = wall.b + Vector3.UP * Cfg.WALL_HEIGHT
		var nearest := Geometry3D.get_closest_point_to_segment(point, a, b)
		if nearest.distance_to(point) > EDGE_EPSILON:
			continue
		var along := (b - a).normalized()
		var score := 1.0 - absf(along.dot(flat)) - minf(wall.length, 100.0) * 0.0001
		if score < best:
			best = score
			result = _heading_for(a, b, point, flat)
	return result

static func roof_side(builds: Node, from: Vector3, to: Vector3, native: int) -> int:
	var along := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if not is_instance_valid(builds) or along.length_squared() < 0.000001:
		return native
	along = along.normalized()
	var right := Vector3(along.z, 0.0, -along.x)
	var centre := (from + to) * 0.5
	var positive := _floor_under(builds, centre + right * Cfg.ROOF_DEPTH * 0.5, from.y - Cfg.WALL_HEIGHT)
	var negative := _floor_under(builds, centre - right * Cfg.ROOF_DEPTH * 0.5, from.y - Cfg.WALL_HEIGHT)
	return (1 if positive else -1) if positive != negative else native

static func _platform_edges(builds: Node) -> Array:
	var edges := []
	for deck in builds.platforms:
		if not is_instance_valid(deck):
			continue
		var rect: Rect2 = deck.footprint()
		var y: float = deck.top_y()
		var a := Vector3(rect.position.x, y, rect.position.y)
		var b := Vector3(rect.end.x, y, rect.position.y)
		var c := Vector3(rect.end.x, y, rect.end.y)
		var d := Vector3(rect.position.x, y, rect.end.y)
		edges.append_array([{"a": a, "b": b, "outward": Vector3.FORWARD}, {"a": b, "b": c, "outward": Vector3.RIGHT}, {"a": d, "b": c, "outward": Vector3.BACK}, {"a": a, "b": d, "outward": Vector3.LEFT}])
	return edges

static func _edge_exposed(builds: Node, point: Vector3, outward: Vector3) -> bool:
	return not _floor_under(builds, point + outward * EDGE_EPSILON, point.y)

static func _floor_under(builds: Node, point: Vector3, height: float) -> bool:
	for deck in builds.platforms:
		if is_instance_valid(deck) and absf(deck.top_y() - height) <= EDGE_EPSILON and deck.footprint().has_point(Vector2(point.x, point.z)):
			return true
	return false

static func _ray_score(eye: Vector3, direction: Vector3, limit: float, point: Vector3) -> float:
	var offset := point - eye
	var along := offset.dot(direction)
	if along < 0.4 or along > limit:
		return INF
	var distance := (offset - direction * along).length()
	return distance + along * 0.005 if distance <= Cfg.ROOF_AIM_RADIUS else INF

static func _heading_for(a: Vector3, b: Vector3, point: Vector3, look: Vector3) -> Vector3:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var length := a.distance_to(b)
	var at := (point - a).dot(along)
	var forward := at + Cfg.ROOF_BAY <= length + EDGE_EPSILON
	var backward := at - Cfg.ROOF_BAY >= -EDGE_EPSILON
	if forward != backward:
		return along if forward else -along
	return along if along.dot(look) >= 0.0 else -along
