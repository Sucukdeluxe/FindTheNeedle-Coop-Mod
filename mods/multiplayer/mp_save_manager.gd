extends "res://autoload/save_manager.gd"

var _mp_retry: Dictionary = {}

func save_game(field_heights: PackedFloat32Array, player_xform: Transform3D, buildings: Array = [], props: Array = [], loose_strands: float = 0.0, belts: Dictionary = {}, dome: PackedFloat32Array = PackedFloat32Array(), dome_seed: int = 0, background: bool = false) -> bool:
	var session := get_node_or_null("/root/MPMod")
	var checkpoint: Variant = session.get("vacuum_checkpoint") if is_instance_valid(session) else null
	if is_instance_valid(checkpoint) and checkpoint.has_pending():
		return false
	var sync: Variant = session.get("world_sync") if is_instance_valid(session) else null
	var sweep: Variant = sync.get("sweep_sync") if is_instance_valid(sync) else null
	if is_instance_valid(sweep) and sweep.busy():
		_mp_retry = {"seed": GameState.run_seed, "slot": current_slot, "dir": save_dir(), "world": weakref(sync.world)}
		if not sweep.finished.is_connected(_mp_cleanup_finished):
			sweep.finished.connect(_mp_cleanup_finished)
		return false
	_mp_retry.clear()
	return super.save_game(field_heights, player_xform, buildings, props, loose_strands, belts, dome, dome_seed, background)

func _mp_cleanup_finished(_token: String, result: Dictionary) -> void:
	if bool(result.get("pending", false)):
		return
	if bool(result.get("incomplete", false)):
		_mp_retry.clear()
		return
	_mp_retry_save.call_deferred()

func _mp_retry_save() -> void:
	var request := _mp_retry
	_mp_retry = {}
	if request.is_empty() or int(request.seed) != GameState.run_seed or int(request.slot) != current_slot or str(request.dir) != save_dir():
		return
	var target: Variant = request.world.get_ref()
	var session := get_node_or_null("/root/MPMod")
	var sync: Variant = session.get("world_sync") if is_instance_valid(session) else null
	if not is_instance_valid(target) or not is_instance_valid(sync) or sync.world != target or sync._frozen or block_save:
		return
	if is_instance_valid(sync.sweep_sync) and sync.sweep_sync.busy():
		return
	target.save_now()

func mp_cleanup_pending() -> bool:
	var session := get_node_or_null("/root/MPMod")
	var sync: Variant = session.get("world_sync") if is_instance_valid(session) else null
	var sweep: Variant = sync.get("sweep_sync") if is_instance_valid(sync) else null
	return is_instance_valid(sweep) and sweep.busy()
