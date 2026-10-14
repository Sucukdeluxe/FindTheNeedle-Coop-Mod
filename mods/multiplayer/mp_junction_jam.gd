extends "res://scripts/build/junction_jam.gd"

var _mp_signature := 0
var _mp_since := -INF
var _mp_handed := -1

func _check(paths: Array, machine: Node, time: float) -> BeltPath:
	var physical := false
	var fingerprint: Array = []
	var handed := 0
	for path in paths:
		if not is_instance_valid(path):
			continue
		handed += int(path.run.handed)
		fingerprint.append([path.get_instance_id(), path.run.count(), path.run.handed])
		if path.run.count() > 0:
			var first: int = path.run.first()
			fingerprint.append([path.run.seq_of(first), snappedf(path.run.s_of(first), 0.001)])
		for rider in path._riders:
			var body: Variant = rider.body
			if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion():
				continue
			physical = true
			fingerprint.append([body.get_instance_id(), snappedf(float(rider.s), 0.001)])
	if not physical:
		_mp_since = -INF
		return super._check(paths, machine, time)
	var signature := hash(fingerprint)
	if handed != _mp_handed:
		_fails = 0
		_until = -INF
	if _mp_since == -INF or signature != _mp_signature:
		_mp_signature = signature
		_mp_handed = handed
		_mp_since = time
		return null
	if suspended() or time - _mp_since < JAM_SECONDS * float(1 << mini(_fails, MAX_BACKOFF)):
		return null
	var candidate: BeltPath = null
	var nearest := INF
	for path in paths:
		if not is_instance_valid(path) or path.is_blocked():
			continue
		var distance := INF
		if path.run.count() > 0 and has_room_after(path, machine):
			distance = path.path_length() - path.run.s_of(path.run.first())
		var next: Variant = path.downstream
		if is_instance_valid(next) and not next.is_blocked():
			for rider in path._riders:
				var body: Variant = rider.body
				if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion():
					continue
				if path.door_refuses(body):
					continue
				if next.accepts_handover(rider.gap, rider.side, rider.reach, path, body, maxf(path.path_length() - rider.s, 0.0)):
					distance = minf(distance, path.path_length() - rider.s)
		if distance < nearest:
			nearest = distance
			candidate = path
	if candidate == null:
		return null
	_mp_since = time
	_until = time + SUSPEND
	_fails += 1
	fired += 1
	return candidate
