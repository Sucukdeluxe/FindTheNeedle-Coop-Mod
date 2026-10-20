extends RefCounted

const REFERENCE_SIZE := 24.0

var _groups := {}
var _size := REFERENCE_SIZE

func track(node: Node) -> void:
	if not node is GeometryInstance3D or node.name != "FarLod" or _groups.has(node):
		return
	var boundary: float = node.visibility_range_begin
	if boundary <= 0.0 or node.get_parent() == null:
		return
	var parts: Array = []
	var pending: Array[Node] = [node.get_parent()]
	while not pending.is_empty():
		var part: Node = pending.pop_back()
		pending.append_array(part.get_children())
		if part != node and part is GeometryInstance3D and part.visibility_range_begin == 0.0 				and is_equal_approx(part.visibility_range_end, boundary):
			parts.append([part, part.visibility_range_end, part.visibility_range_end_margin])
	if parts.is_empty():
		return
	_groups[node] = {"begin": boundary, "margin": node.visibility_range_begin_margin, "parts": parts}
	_apply(node, _groups[node])

func update(size: float) -> void:
	if not is_finite(size) or size <= 0.0 or is_equal_approx(size, _size):
		return
	_size = size
	for node in _groups:
		_apply(node, _groups[node])

func _apply(node: Variant, group: Dictionary) -> void:
	var scale := minf(1.0, REFERENCE_SIZE / _size)
	if is_instance_valid(node):
		node.visibility_range_begin = float(group.begin) * scale
		node.visibility_range_begin_margin = float(group.margin) * scale
	for part in group.parts:
		if is_instance_valid(part[0]):
			part[0].visibility_range_end = float(part[1]) * scale
			part[0].visibility_range_end_margin = float(part[2]) * scale

func finish() -> void:
	_size = REFERENCE_SIZE
	for node in _groups:
		_apply(node, _groups[node])
	_groups.clear()
