extends "res://scripts/build/hay_compressor.gd"

var mp_transport: Node
var _mp_releasing := false

func _mp_active() -> bool:
	return is_instance_valid(mp_transport) and is_instance_valid(mp_transport.mp) and mp_transport.mp.active()

func _eats(kind: int, strands: int) -> bool:
	return super._eats(kind, strands) or (_mp_active() and kind == BeltRun.Kind.TUFT)

func _parks(kind: int, strands: int) -> bool:
	return super._parks(kind, strands) or (_mp_active() and kind == BeltRun.Kind.TUFT)

func _held_in_mouth(body: Object) -> bool:
	if _mp_active() and is_instance_valid(body):
		if body is HayWad or (body is RigidBody3D and body.get_parent() is LiveStrandManager and not body.has_meta("needle_index")):
			return true
	return super._held_in_mouth(body)

func _release_bale() -> void:
	if not _mp_active():
		super._release_bale()
		return
	if _released or _mp_releasing or not is_instance_valid(props):
		return
	var signal_names := ["baled", "baled_record"]
	var confirmation := [false]
	var watch := _mp_watch_release(signal_names, confirmation)
	if not watch.is_valid():
		super._release_bale()
		return
	var pending_before := pending_needles.duplicate()
	_mp_releasing = true
	super._release_bale()
	_mp_releasing = false
	_mp_unwatch_release(signal_names, watch)
	if _released and not confirmation[0]:
		_released = false
		pending_needles = pending_before

func _mp_watch_release(signal_names: Array, confirmation: Array) -> Callable:
	for signal_name in signal_names:
		if not has_signal(signal_name):
			return Callable()
	for info in get_signal_list():
		if info.name in signal_names and info.args.size() != 1:
			return Callable()
	var watch := Callable(self, "_mp_release_seen").bind(confirmation)
	for signal_name in signal_names:
		if connect(signal_name, watch) != OK:
			_mp_unwatch_release(signal_names, watch)
			return Callable()
	return watch

func _mp_unwatch_release(signal_names: Array, watch: Callable) -> void:
	for signal_name in signal_names:
		if has_signal(signal_name) and is_connected(signal_name, watch):
			disconnect(signal_name, watch)

func _mp_release_seen(_value: Variant, confirmation: Array) -> void:
	confirmation[0] = true

func to_dict() -> Dictionary:
	var data := super.to_dict()
	if _press >= 0.0 and not _released:
		data["stored"] = int(data.get("stored", 0)) + _batch
	return data

func factory_tick(delta: float) -> void:
	if _mp_active() and mp_transport.mp.is_host:
		_mp_restore_intake()
	super.factory_tick(delta)

func _mp_restore_intake() -> void:
	if not is_instance_valid(_belt):
		return
	var mouth := _belt.s_at(_mouth())
	var limit := mouth + INTAKE_LENGTH * 0.5
	var target := clampf(mouth, 0.0, maxf(0.0, _belt.path_length() - _belt.run.hold_back))
	var late: Array[int] = []
	for index in range(_belt.run.first(), _belt.run.first() + _belt.run.count()):
		var record: Dictionary = _belt.run.record(index)
		if _eats(int(record.kind), int(record.strands)) and float(record.s) > limit + 0.001:
			late.append(int(record.seq))
	for seq in late:
		for index in range(_belt.run.first(), _belt.run.first() + _belt.run.count()):
			if _belt.run.seq_of(index) != seq:
				continue
			var gap: float = _belt.run.gap_of(index)
			var record: Dictionary = _belt.take_record_at(index)
			var insert_at: int = _belt.run._row_behind(target)
			_belt.run._insert_row(insert_at, target, record.reach, gap, record.side, record.lift,
				record.speed, record.kind, record.strands, record.needle, record.seq, record.state)
			_belt.run._ev_board(insert_at)
			_belt.run.wake()
			_belt.wake()
			break
	if not late.is_empty():
		BeltPath._put_load(_belt.get_instance_id(), _belt._ride_load())

func _intake_hay() -> void:
	super._intake_hay()
	if not _mp_active() or not mp_transport.mp.is_host or is_full():
		return
	var paths := _mp_wrapper_feed()
	for path in paths:
		var record: Dictionary = path.take_record(_eats, 0.0, path.path_length())
		if not record.is_empty():
			_mp_accept_recovered(int(record.strands), int(record.needle))
			return
	if not is_instance_valid(props):
		return
	if is_instance_valid(_belt):
		paths.push_front(_belt)
	for path in paths:
		for rider in path._riders:
			var item: Variant = rider.body
			if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion() \
					or not (item is HayWad or item is HayTuft) or item.is_held():
				continue
			if not item.has_meta(LiveStrandManager.META_RIDER) or item.get_meta(LiveStrandManager.META_RIDER) != path:
				continue
			if path == _belt and float(rider.s) < _belt.s_at(_mouth()) - INTAKE_LENGTH * 0.5:
				continue
			var sync: Node = mp_transport.mp.world_sync.props_sync
			var id := int(item.get_meta("mp_id", 0))
			if id > 0 and not sync._mine(id) and not sync.host_take(item):
				continue
			var count: int = item.hay_strands()
			if count <= 0:
				continue
			var state: Dictionary = item.to_dict()
			BeltPath.release(item)
			_mp_accept_recovered(count, int(state.get("needle", -1)))
			props.remove(item)
			return

func _mp_accept_recovered(count: int, needle: int) -> void:
	stored += count
	if needle >= 0:
		pending_needles.append(needle)

func _mp_wrapper_feed() -> Array[BeltPath]:
	var paths: Array[BeltPath] = []
	var path := _outfeed()
	while is_instance_valid(path) and path.is_inside_tree() and not path.is_queued_for_deletion():
		if path.get_parent() is HayWrapper:
			paths.append(path)
			return paths
		if not (path is Conveyor or path is ConveyorCorner) or paths.has(path) or paths.size() >= 64:
			break
		paths.append(path)
		path = path.downstream
	return []

func _mp_holds_output_kind(kind: int) -> bool:
	return _mp_active() and kind in [BeltRun.Kind.WAD, BeltRun.Kind.TUFT]
