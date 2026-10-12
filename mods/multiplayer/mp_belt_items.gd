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
