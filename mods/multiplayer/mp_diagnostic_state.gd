extends RefCounted

const BuildSnapshot = preload("res://mods/multiplayer/mp_build_snapshot.gd")

const CONFIRM_MS := 6000
const MIN_SAMPLES := 3
const REPEAT_MS := 60000
const MAX_CHANNELS := 64
const MAX_PENDING := 256
const WAIT_MS := 12000

var entries := {}
var waiting := {}

func observe(channel: String, bad: bool, count: int, now: int) -> Dictionary:
	if not bad:
		var previous: Dictionary = entries.get(channel, {})
		entries.erase(channel)
		if previous.get("reported", false):
			return {"state": "recovered", "count": count}
		return {}
	if not entries.has(channel):
		if entries.size() >= MAX_CHANNELS:
			return {}
		entries[channel] = {"first": now, "last": now, "samples": 1, "reported": false, "logged": now}
		return {}
	var entry: Dictionary = entries[channel]
	if now <= int(entry["last"]):
		return {}
	entry["last"] = now
	entry["samples"] = int(entry["samples"]) + 1
	if now - int(entry["first"]) < CONFIRM_MS or int(entry["samples"]) < MIN_SAMPLES:
		return {}
	if entry["reported"] and now - int(entry["logged"]) < REPEAT_MS:
		return {}
	entry["reported"] = true
	entry["logged"] = now
	return {"state": "mismatch", "count": count}

func pending(channel: String, ids: Array, now: int) -> Dictionary:
	if not waiting.has(channel):
		if waiting.size() >= MAX_CHANNELS:
			return {}
		waiting[channel] = {}
	var tracked: Dictionary = waiting[channel]
	var current := {}
	for id in ids:
		current[id] = true
	for id in tracked.keys():
		if not current.has(id):
			tracked.erase(id)
	for id in ids:
		if tracked.size() < MAX_PENDING and not tracked.has(id):
			tracked[id] = now
	var overdue := 0
	for id in tracked:
		if now - int(tracked[id]) >= WAIT_MS:
			overdue += 1
	var result := observe(channel, overdue > 0, overdue, now)
	if ids.is_empty():
		waiting.erase(channel)
	return result

func reset() -> void:
	entries.clear()
	waiting.clear()

static func cargo(rows: Array) -> Dictionary:
	var totals := {}
	for row in rows:
		var kind := int(row.get("kind", -1))
		if not totals.has(kind):
			totals[kind] = [0, 0]
		totals[kind][0] += 1
		totals[kind][1] += int(row.get("strands", 0))
	return totals

static func machine_shape(machine: Node, parts: Array) -> Array:
	var shape: Array = [machine.get_instance_id(), machine.get_script()]
	for part in parts:
		if not is_instance_valid(part) or not part.is_inside_tree() or part.is_queued_for_deletion():
			return []
		shape.append(part.get_instance_id())
		shape.append(part.get_parent().get_instance_id())
		shape.append(part.get_index())
		shape.append(part.name)
		shape.append(part.get_script())
	return shape

static func owner_key(node: Node, world: Node, cache: Dictionary, key_for: Callable) -> String:
	var visited: Array = []
	var current := node
	var key := ""
	while is_instance_valid(current) and current != world:
		if cache.has(current):
			key = cache[current]
			break
		visited.append(current)
		if current.has_method("to_dict"):
			var data: Variant = BuildSnapshot.row(current)
			if data is Dictionary and data.has("type"):
				key = str(key_for.call(data))
				break
		current = current.get_parent()
	for item in visited:
		cache[item] = key
	return key
