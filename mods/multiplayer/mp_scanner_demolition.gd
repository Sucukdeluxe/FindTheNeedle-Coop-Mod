extends RefCounted

static func capture(scanner: Node3D, sync: Node, scanners: Array) -> Dictionary:
	if is_instance_valid(sync) and sync._is_client():
		return {}
	var elsewhere := {}
	for other in scanners:
		if is_instance_valid(other) and other != scanner and not other.is_queued_for_deletion():
			for index in other.held_needles():
				elsewhere[index] = true
	var indices := PackedInt32Array()
	for index in scanner.held_needles():
		if index >= 0 and index < GameState.needle_positions.size() and index < GameState.needle_type.size() and not indices.has(index) and not elsewhere.has(index):
			indices.append(index)
	return {"indices": indices, "live": scanner.live, "at": scanner.global_position + Vector3(0.0, 0.35, 0.0)}

static func release(snapshot: Dictionary, sync: Node) -> void:
	if snapshot.is_empty() or not is_instance_valid(snapshot.get("live")):
		return
	var online: bool = is_instance_valid(sync) and is_instance_valid(sync.mp) and sync.mp.active()
	if online and not sync.mp.is_host:
		return
	var live: Node = snapshot.live
	var occupied := {}
	for body in live.needles:
		if is_instance_valid(body) and not body.is_queued_for_deletion():
			occupied[int(body.get_meta("needle_index", -1))] = true
	var ordinal := 0
	for index in snapshot.indices:
		if GameState.mp_needle_committed.has(index) or occupied.has(index):
			continue
		if online and sync._holder_of(index) != 0:
			continue
		var at: Vector3 = snapshot.at + Vector3(float(ordinal % 5 - 2) * 0.12, 0.04 * float(ordinal / 25), float(ordinal / 5 % 5 - 2) * 0.12)
		ordinal += 1
		if online:
			sync._apply_needle("spawn", index, at, 0)
			sync._needle_out("spawn", index, at, 0)
		else:
			live.reveal_needle(index, at)
		occupied[index] = true
	if online and is_instance_valid(sync.scanner_sync):
		sync.scanner_sync.changed()
