extends RefCounted

static func representatives(items: Array) -> Array[Carryable]:
	var cells := {}
	var selected: Array[Carryable] = []
	for item in items:
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var at: Vector3 = item.global_position
		var cell := Vector2i(floori(at.x / BeltWatch.CELL), floori(at.z / BeltWatch.CELL))
		if not cells.has(cell):
			cells[cell] = true
			selected.append(item)
	return selected

static func should_group(items: Array) -> bool:
	if items.size() < 256:
		return false
	var cells := {}
	var count := 0
	for i in range(64):
		var item = items[i * items.size() / 64]
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var at: Vector3 = item.global_position
		cells[Vector2i(floori(at.x / BeltWatch.CELL), floori(at.z / BeltWatch.CELL))] = true
		count += 1
	return count > 0 and cells.size() * 4 <= count * 3
