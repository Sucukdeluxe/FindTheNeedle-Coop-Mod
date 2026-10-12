extends RefCounted

const LINE_EPSILON_SQUARED := 0.000001


static func owner_key(sync: Node, path: Node) -> String:
	var node: Node = path
	while is_instance_valid(node) and node != sync.world:
		if node.has_method("to_dict"):
			var data: Variant = node.to_dict()
			if data is Dictionary and not data.is_empty():
				return sync._bkey(data)
		node = node.get_parent()
	return ""


static func same_line(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i].distance_squared_to(b[i]) > LINE_EPSILON_SQUARED:
			return false
	return true


static func resolve(sync: Node, entries: Array, paths: Array) -> Dictionary:
	var by_owner := {}
	for path in paths:
		if not is_instance_valid(path) or not path.is_inside_tree() or path.is_queued_for_deletion() or path._line.size() < 2:
			continue
		var key := owner_key(sync, path)
		if not by_owner.has(key):
			by_owner[key] = []
		by_owner[key].append(path)
	var claimed := {}
	var assignments := []
	for entry in entries:
		var found: Node = null
		for path in by_owner.get(entry.owner, []):
			if same_line(path._line, entry.line):
				if found != null:
					return {"ready": false}
				found = path
		if found == null or claimed.has(found.get_instance_id()) or not found.records_props or not found.run.has_method("_insert_row") or not found.run.has_method("_ev_board"):
			return {"ready": false}
		claimed[found.get_instance_id()] = true
		assignments.append([found, entry.records])
	return {"ready": true, "assignments": assignments}


static func restore(path: Node, rows: Array) -> void:
	for row in rows:
		var index: int = path.run.first() + path.run.count()
		path.run._insert_row(index, row.s, row.reach, row.gap, row.side, row.lift, row.speed, row.kind, row.strands, row.needle, row.seq, row.state)
		path.run._ev_board(index)
	path.run.stepped_tick = Engine.get_physics_frames()
	path.run.clock_live = true
	path.run.wake()
	path.wake()
	path._max_at_take = maxi(path._max_at_take, path.belt_load())
	path._put_load(path.get_instance_id(), path._ride_load())
