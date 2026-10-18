extends RefCounted

const BuildCamera = preload("res://mods/multiplayer/mp_build_camera.gd")

static func capture(camera: Node) -> Vector4:
	if not is_instance_valid(camera) or not camera.active:
		return Vector4.ZERO
	var view: Dictionary = camera.request_view(camera.get_viewport().get_visible_rect().size * 0.5)
	if view.is_empty():
		return Vector4.ZERO
	return Vector4(view.focus.x, view.focus.z, view.size, view.aspect)

static func region(view: Vector4, body: Vector3) -> AABB:
	if not view.is_finite() or not body.is_finite() or view.z < BuildCamera.MIN_SIZE or view.z > BuildCamera.MAX_SIZE or view.w < 0.2 or view.w > 6.0:
		return AABB()
	var center := Vector3(view.x, body.y, view.y)
	if not BuildCamera.point_allowed(center, body):
		return AABB()
	var half := Vector2(view.z * view.w, view.z) * 0.5
	var bounds := Rect2(Vector2(view.x, view.y) - half, half * 2.0).intersection(BuildCamera._map_bounds)
	if not bounds.has_area():
		return AABB()
	return AABB(Vector3(bounds.position.x, body.y - BuildCamera.BELOW_PLAYER, bounds.position.y), Vector3(bounds.size.x, BuildCamera.BELOW_PLAYER + BuildCamera.MAX_HEIGHT, bounds.size.y))

static func near(at: Vector3, watchers: Array, radius: float) -> bool:
	if not at.is_finite():
		return false
	for watcher in watchers:
		if watcher is Vector3 and at.distance_squared_to(watcher) < radius * radius:
			return true
		if watcher is AABB and watcher.grow(radius).has_point(at):
			return true
	return false
