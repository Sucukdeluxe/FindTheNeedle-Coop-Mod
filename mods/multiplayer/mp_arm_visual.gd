extends RefCounted

const MAX_INSTANCES := 64
const VALUES_PER_INSTANCE := 16
const CHUNK_INSTANCES := 8

var _sent := {}
var _received := {}
var _generation := 0
var _sequence := 0

static func _pose_values(pose: Transform3D) -> PackedFloat32Array:
	return PackedFloat32Array([pose.origin.x, pose.origin.y, pose.origin.z,
		pose.basis.x.x, pose.basis.x.y, pose.basis.x.z,
		pose.basis.y.x, pose.basis.y.y, pose.basis.y.z,
		pose.basis.z.x, pose.basis.z.y, pose.basis.z.z])

static func _pose(values: PackedFloat32Array, offset: int = 0) -> Transform3D:
	return Transform3D(Basis(Vector3(values[offset + 3], values[offset + 4], values[offset + 5]),
		Vector3(values[offset + 6], values[offset + 7], values[offset + 8]),
		Vector3(values[offset + 9], values[offset + 10], values[offset + 11])),
		Vector3(values[offset], values[offset + 1], values[offset + 2]))

func capture(key: String, arm: RoboticArm, full: bool) -> Dictionary:
	var draw: Variant = arm.get("_payload_visual")
	var count := 0
	var identity := 0
	var pose := Transform3D.IDENTITY
	if is_instance_valid(draw) and draw is MultiMeshInstance3D and draw.is_inside_tree() \
			and not draw.is_queued_for_deletion() and draw.visible and draw.multimesh != null:
		count = draw.multimesh.instance_count
		if count > 0 and count <= MAX_INSTANCES:
			identity = draw.get_instance_id()
			pose = draw.global_transform
		else:
			count = 0
	var previous: Dictionary = _sent.get(key, {})
	var changed: bool = previous.get("identity", -1) != identity or previous.get("count", -1) != count
	if changed:
		_generation += 1
		previous = {"identity": identity, "count": count, "generation": _generation}
		_sent[key] = previous
	if count == 0 and not changed and not full:
		return {}
	_sequence += 1
	var out := {"g": previous.generation, "q": _sequence, "n": count, "p": _pose_values(pose)}
	if changed or full:
		var data := PackedFloat32Array()
		for i in count:
			data.append_array(_pose_values(draw.multimesh.get_instance_transform(i)))
			var tint: Color = draw.multimesh.get_instance_color(i)
			data.append_array(PackedFloat32Array([tint.r, tint.g, tint.b, tint.a]))
		out["o"] = 0
		out["d"] = data
	return out

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("g") is int or not value.get("q") is int \
			or not value.get("n") is int or not value.get("p") is PackedFloat32Array:
		return false
	if value.g <= 0 or value.q <= 0 or value.n < 0 or value.n > MAX_INSTANCES or value.p.size() != 12:
		return false
	for number in value.p:
		if not is_finite(number) or absf(number) > 1000000.0:
			return false
	if value.has("d") != value.has("o"):
		return false
	if value.has("d"):
		if not value.d is PackedFloat32Array or not value.o is int or value.o < 0 \
				or value.d.size() % VALUES_PER_INSTANCE != 0 or value.o + value.d.size() / VALUES_PER_INSTANCE > value.n:
			return false
		if value.n > 0 and value.d.is_empty():
			return false
		for number in value.d:
			if not is_finite(number) or absf(number) > 1000000.0:
				return false
	return true

static func pieces(state: Dictionary) -> Array:
	if not state.has("d") or state.d.is_empty():
		return [state]
	var result: Array = []
	var count: int = state.d.size() / VALUES_PER_INSTANCE
	for offset in range(0, count, CHUNK_INSTANCES):
		var part := state.duplicate()
		part.o = state.o + offset
		part.d = state.d.slice(offset * VALUES_PER_INSTANCE, mini(count, offset + CHUNK_INSTANCES) * VALUES_PER_INSTANCE)
		result.append(part)
	return result

func apply(key: String, arm: RoboticArm, state: Dictionary) -> void:
	if not valid(state):
		return
	var current: Dictionary = _received.get(key, {})
	if not current.is_empty() and current.owner.get_ref() != arm:
		_discard(current)
		current = {}
	if not current.is_empty() and state.g < current.generation:
		return
	if current.is_empty() or state.g > current.generation:
		_discard(current)
		current = {"owner": weakref(arm), "generation": state.g, "count": state.n,
			"sequence": 0, "seen": {}, "data": PackedFloat32Array(), "draw": null,
			"from": _pose(state.p), "to": _pose(state.p), "elapsed": 1.0}
		current.data.resize(state.n * VALUES_PER_INSTANCE)
		_received[key] = current
	if state.n != current.count:
		return
	if state.q > current.sequence:
		current.sequence = state.q
		current.from = current.draw.global_transform if is_instance_valid(current.draw) else _pose(state.p)
		current.to = _pose(state.p)
		current.elapsed = 0.0
	if state.n == 0 or not state.has("d"):
		return
	for i in state.d.size():
		current.data[state.o * VALUES_PER_INSTANCE + i] = state.d[i]
	for i in range(state.o, state.o + state.d.size() / VALUES_PER_INSTANCE):
		current.seen[i] = true
	if current.seen.size() != current.count or is_instance_valid(current.draw):
		return
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.mesh = StrandFactory.strand_mesh()
	mesh.instance_count = current.count
	for i in current.count:
		var offset: int = i * VALUES_PER_INSTANCE
		mesh.set_instance_transform(i, _pose(current.data, offset))
		mesh.set_instance_color(i, Color(current.data[offset + 12], current.data[offset + 13], current.data[offset + 14], current.data[offset + 15]))
	var draw := MultiMeshInstance3D.new()
	draw.name = "MPCarriedHay"
	draw.set_meta("mp_arm_visual", true)
	draw.multimesh = mesh
	draw.custom_aabb = RoboticArm.CLAW_STRAW_BOUNDS
	draw.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	draw.top_level = true
	arm.add_child(draw)
	draw.global_transform = current.to
	current.draw = draw

func step(delta: float) -> void:
	for current in _received.values():
		if not is_instance_valid(current.draw):
			continue
		current.elapsed = minf(1.0, current.elapsed + delta / 0.1)
		current.draw.global_transform = current.from.interpolate_with(current.to, current.elapsed)

func prune(nodes: Dictionary) -> void:
	for key in _sent.keys():
		if not nodes.has(key):
			_sent.erase(key)
	for key in _received.keys():
		if not nodes.has(key) or _received[key].owner.get_ref() != nodes[key]:
			_discard(_received[key])
			_received.erase(key)

func clear() -> void:
	for current in _received.values():
		_discard(current)
	_received.clear()
	_sent.clear()

func _discard(current: Dictionary) -> void:
	var draw: Variant = current.get("draw")
	if is_instance_valid(draw):
		draw.hide()
		draw.queue_free()
	current["draw"] = null
