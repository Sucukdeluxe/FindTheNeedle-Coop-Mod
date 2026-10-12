extends "res://scripts/build/hay_wrapper.gd"

var mp_transport: Node
var _mp_releasing := false

func _mp_active() -> bool:
	return is_instance_valid(mp_transport) and is_instance_valid(mp_transport.mp) and mp_transport.mp.active()

func _parks(kind: int, strands: int) -> bool:
	return super._parks(kind, strands) or (_mp_active() and kind == BeltRun.Kind.TUFT)

func _blocks_mouth(body: Object) -> bool:
	if _mp_active() and is_instance_valid(body):
		if body is HayWad or (body is RigidBody3D and body.get_parent() is LiveStrandManager and not body.has_meta("needle_index")):
			return true
	return super._blocks_mouth(body)

func _release_product() -> void:
	if not _mp_active():
		super._release_product()
		return
	if _released or _mp_releasing or not is_instance_valid(props):
		return
	var signal_names := ["wrapped", "wrapped_record"]
	var confirmation := [false]
	var watch := _mp_watch_release(signal_names, confirmation)
	if not watch.is_valid():
		super._release_product()
		return
	var pending_before := pending_needles.duplicate()
	var needle_before := _batch_needle
	_mp_releasing = true
	super._release_product()
	_mp_releasing = false
	_mp_unwatch_release(signal_names, watch)
	if _released and not confirmation[0]:
		_released = false
		pending_needles.assign(pending_before)
		_batch_needle = needle_before

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
