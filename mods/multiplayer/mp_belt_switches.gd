extends RefCounted

var sync: Node
var _topology: Array = []
var _saved: Dictionary = {}

const PATCH := """
func mp_belt_switchable() -> bool:
	var node: Node = self
	return node is Conveyor and not bool(get("placement_preview")) and is_inside_tree() and not is_queued_for_deletion()
func mp_belt_switch_targets() -> Array:
	var session = get_node_or_null("/root/MPMod")
	if not is_instance_valid(session) or not is_instance_valid(session.world_sync):
		return []
	return session.world_sync.belts_sync.switches.targets(self)
func is_switched_off() -> bool:
	return bool(get_meta("mp_belt_off", false))
func set_switched_off(value: bool) -> void:
	var session = get_node_or_null("/root/MPMod")
	if is_instance_valid(session) and is_instance_valid(session.world_sync):
		session.world_sync.belts_sync.switches.set_off(self, value)
func set_drive_speed(value: float) -> void:
	super.set_drive_speed(0.0 if is_switched_off() else value)
func _refresh_deck() -> void:
	super._refresh_deck()
	if is_switched_off() and not _deck_shows_held:
		_deck_shows_held = true
		_apply_deck_state()
func _sync_run_blocked() -> void:
	super._sync_run_blocked()
	if is_switched_off():
		run.set_blocked(true)
func tick_path(delta: float) -> void:
	if is_switched_off():
		run.stepped_tick = Engine.get_physics_frames()
		run.clock_live = true
		return
	super.tick_path(delta)
"""

func start(world_sync: Node) -> void:
	sync = world_sync
	_saved = GameState.get("mp_belt_switches")
	refresh(true)

func targets(path: Node) -> Array:
	if not is_instance_valid(sync) or not is_instance_valid(sync.builds) or not path is Conveyor or not sync.builds.conveyors.has(path):
		return []
	var result := []
	for piece in sync.builds.line_of(path):
		if is_instance_valid(piece) and piece.is_inside_tree() and not piece.is_queued_for_deletion() and not piece.placement_preview:
			result.append(piece)
	return result

func set_off(path: Node, off: bool) -> void:
	var pieces := targets(path)
	if pieces.is_empty():
		return
	for piece in pieces:
		apply_path(piece, off)
	refresh()

func step() -> void:
	if not is_instance_valid(sync) or not is_instance_valid(sync.builds):
		return
	var topology := [YardPorts.epoch, sync.builds.conveyors.size(), sync.builds.corners.size()]
	var changed_save := not is_same(_saved, GameState.get("mp_belt_switches"))
	if topology != _topology or changed_save:
		refresh(changed_save)

func refresh(from_save := false) -> void:
	if not is_instance_valid(sync) or not is_instance_valid(sync.builds):
		return
	var builds: Node = sync.builds
	var saved: Dictionary = GameState.get("mp_belt_switches")
	var next := {}
	var paused_corners := {}
	for path in builds.conveyors:
		if not is_instance_valid(path) or not path.is_inside_tree() or path.is_queued_for_deletion():
			continue
		var key: String = sync._bkey(path.to_dict())
		var off := bool(saved.get(key, false)) if from_save or not path.has_meta("mp_belt_off") else bool(path.get_meta("mp_belt_off"))
		apply_path(path, off)
		if off:
			next[key] = true
			var pieces: Array[Conveyor] = [path]
			for part in builds._upgrade_paths(pieces, path is EnclosedConveyor):
				if part is ConveyorCorner:
					paused_corners[part] = true
	for corner in builds.corners:
		if is_instance_valid(corner) and corner.is_inside_tree() and not corner.is_queued_for_deletion():
			apply_path(corner, paused_corners.has(corner))
	GameState.set("mp_belt_switches", next)
	_saved = GameState.get("mp_belt_switches")
	_topology = [YardPorts.epoch, builds.conveyors.size(), builds.corners.size()]

static func apply_path(path: Node, off: bool) -> void:
	var changed := not path.has_meta("mp_belt_off") or bool(path.get_meta("mp_belt_off")) != off
	path.set_meta("mp_belt_off", off)
	if not changed:
		return
	if off:
		path.set_drive_speed(0.0)
		path.run.set_blocked(true)
	else:
		path._follow_tech()
		path._sync_run_blocked()
	path._refresh_deck()
	path.wake()

func clear() -> void:
	sync = null
	_topology.clear()
	_saved = {}
