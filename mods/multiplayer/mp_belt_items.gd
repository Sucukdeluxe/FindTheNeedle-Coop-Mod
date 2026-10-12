extends RefCounted

static var _busy := {}


static func materialize(path: BeltPath, index: int) -> Carryable:
	if index < path.run.first() or index >= path.run.first() + path.run.count():
		return null
	var props := path._props()
	if not is_instance_valid(props):
		return null
	var record: Dictionary = path.run.record(index)
	var seq := int(record["seq"])
	var key := "%d:%d" % [path.get_instance_id(), seq]
	if _busy.has(key):
		return null
	_busy[key] = true
	var item := path._spawn_record(record, clampf(float(record["s"]), 0.0, path.path_length()))
	_busy.erase(key)
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		return null
	for current in range(path.run.first(), path.run.first() + path.run.count()):
		if path.run.seq_of(current) == seq:
			path.run.remove_at(current)
			BeltPath._put_load(path.get_instance_id(), path._ride_load())
			return item
	props.remove(item)
	return null


static func transfer(path: BeltPath, seq: int, other: BeltPath) -> bool:
	if not is_instance_valid(other) or other == path or not other.records_props:
		return false
	var key := "%d:%d" % [path.get_instance_id(), seq]
	var target_key := "%d:%d" % [other.get_instance_id(), seq]
	if _busy.has(key) or _busy.has(target_key):
		return false
	for index in range(other.run.first(), other.run.first() + other.run.count()):
		if other.run.seq_of(index) == seq:
			return false
	var record: Dictionary = {}
	for index in range(path.run.first(), path.run.first() + path.run.count()):
		if path.run.seq_of(index) == seq:
			record = path.run.record(index)
			break
	if record.is_empty():
		return false
	_busy[key] = true
	_busy[target_key] = true
	var accepted: bool = other.run.board_record(record, float(record["s"]), float(record["speed"]), false)
	if not accepted:
		_busy.erase(key)
		_busy.erase(target_key)
		return false
	var consumed := false
	for index in range(path.run.first(), path.run.first() + path.run.count()):
		if path.run.seq_of(index) == seq:
			path.run.remove_at(index)
			consumed = true
			break
	if not consumed:
		for index in range(other.run.first(), other.run.first() + other.run.count()):
			if other.run.seq_of(index) == seq:
				other.run.remove_at(index)
				break
	_busy.erase(key)
	_busy.erase(target_key)
	BeltPath._put_load(path.get_instance_id(), path._ride_load())
	other.wake()
	BeltPath._put_load(other.get_instance_id(), other._ride_load())
	return consumed
