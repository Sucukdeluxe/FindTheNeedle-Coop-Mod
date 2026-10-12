extends RefCounted

const SMOOTH := 22.0

var _draws := {}


static func valid(groups: Variant) -> bool:
	if not (groups is Array):
		return false
	var keys := {}
	var sequences := {}
	for group in groups:
		if not (group is Dictionary) or not (group.get("key") is String) or keys.has(group.key):
			return false
		keys[group.key] = true
		if not (group.get("rows") is Array):
			return false
		for row in group.rows:
			if not (row is Array) or row.size() != 4:
				return false
			if not (row[0] is int) or row[0] < 0 or sequences.has(row[0]):
				return false
			sequences[row[0]] = true
			if not (row[1] is int) or row[1] < 0 or row[1] >= BeltRun.ITEM_IDS.size():
				return false
			if not (row[2] is int) or row[2] < 0:
				return false
			if not (row[3] is Transform3D) or not row[3].is_finite():
				return false
	return true


static func capture(sync: Node) -> Array:
	var out := []
	for lift in carriers(sync):
		if not is_instance_valid(lift) or not lift.is_inside_tree() or lift.is_queued_for_deletion() or lift.placement_preview:
			continue
		var rows := []
		for carried in lift._carried:
			var rec: Variant = carried.get("rec")
			if not (rec is Dictionary) or rec.is_empty():
				continue
			var draw: Variant = carried.get("draw")
			if is_instance_valid(draw):
				rows.append([draw.get_instance_id(), int(rec["kind"]), int(rec["strands"]), carried["xform"]])
		if not rows.is_empty():
			out.append({"key": sync._bkey(lift.to_dict()), "rows": rows})
	return out


func apply(sync: Node, groups: Array) -> void:
	if not ready(sync, groups):
		return
	var lifts := {}
	for lift in carriers(sync):
		if is_instance_valid(lift) and lift.is_inside_tree() and not lift.is_queued_for_deletion() and not lift.placement_preview:
			discard_local_records(lift)
			lifts[sync._bkey(lift.to_dict())] = lift
	var seen := {}
	for group in groups:
		var lift: Variant = lifts.get(group.key)
		if not is_instance_valid(lift):
			continue
		for row in group.rows:
			var seq: int = row[0]
			seen[seq] = true
			var saved: Dictionary = _draws.get(seq, {})
			if not saved.is_empty():
				if not is_instance_valid(saved.draw) or saved.draw.get_parent() != lift or saved.kind != row[1] or saved.strands != row[2]:
					_erase(seq)
					saved = {}
			if saved.is_empty():
				var draw: Node3D = BeltRunBatch.stand_in(row[1], row[2])
				if draw == null:
					continue
				draw.set_meta("mp_lift_cargo", true)
				lift.add_child(draw)
				draw.global_transform = row[3]
				saved = {"draw": draw, "kind": row[1], "strands": row[2], "goal": row[3]}
				_draws[seq] = saved
			saved.goal = row[3]
	for seq in _draws.keys():
		if not seen.has(seq):
			_erase(seq)


func step(delta: float) -> void:
	var weight := minf(1.0, maxf(0.0, delta) * SMOOTH)
	for seq in _draws.keys():
		var saved: Dictionary = _draws[seq]
		var draw: Variant = saved.draw
		if not is_instance_valid(draw) or not draw.is_inside_tree() or draw.is_queued_for_deletion():
			_erase(seq)
			continue
		draw.global_transform = draw.global_transform.interpolate_with(saved.goal, weight)


func clear() -> void:
	for seq in _draws.keys():
		_erase(seq)


func _erase(seq: int) -> void:
	var saved: Dictionary = _draws.get(seq, {})
	if not saved.is_empty() and is_instance_valid(saved.draw):
		saved.draw.hide()
		saved.draw.queue_free()
	_draws.erase(seq)


static func carriers(sync: Node) -> Array:
	var out := []
	for collection in ["hay_lifts", "hay_stairs"]:
		var nodes: Variant = sync.builds.get(collection)
		if nodes is Array:
			out.append_array(nodes)
	return out


static func discard_local_records(carrier: Node) -> void:
	for index in range(carrier._carried.size() - 1, -1, -1):
		var row: Dictionary = carrier._carried[index]
		if not row.has("rec"):
			continue
		var draw: Variant = row.get("draw")
		if is_instance_valid(draw):
			draw.hide()
		carrier._free_draw(row)
		carrier._carried.remove_at(index)


func ready(sync: Node, groups: Array) -> bool:
	var counts := {}
	for carrier in carriers(sync):
		if not is_instance_valid(carrier) or not carrier.is_inside_tree() or carrier.is_queued_for_deletion() or carrier.placement_preview:
			continue
		var key: String = sync._bkey(carrier.to_dict())
		counts[key] = int(counts.get(key, 0)) + 1
	for group in groups:
		if int(counts.get(group.key, 0)) != 1:
			return false
	return true
