extends Node

const MODEL := "res://mods/ftn_mice/mouse.glb"
const MAX_MICE := 10
const MAX_RAW := 16384
const TICK := 0.1
const SMOOTH := 20.0

var mp: Node
var world_sync: Node
var _running := false
var _clock := 0.0
var _sequence := 0
var _received := 0
var _epoch := ""
var _views := {}
var _template: Node3D
var _model_attempted := false

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	_running = true
	set_process(true)

func shutdown() -> void:
	_running = false
	set_process(false)
	_clear_views()
	if is_instance_valid(_template):
		_template.free()
	_template = null

func _exit_tree() -> void:
	shutdown()

func _ready_for_state() -> bool:
	return _running and is_instance_valid(mp) and mp.active() and is_instance_valid(world_sync) and is_instance_valid(world_sync.world) and not world_sync._frozen and is_instance_valid(world_sync.economy) and world_sync.economy.epoch != ""

func _process(delta: float) -> void:
	if not _ready_for_state():
		_clear_views()
		return
	if _epoch != world_sync.economy.epoch:
		_clear_views()
		_epoch = world_sync.economy.epoch
		_received = 0
	if mp.is_host:
		_clock += delta
		if _clock >= TICK:
			_clock = 0.0
			publish()
	else:
		for entry in _views.values():
			var node: Node3D = entry.node
			if is_instance_valid(node):
				node.global_transform = node.global_transform.interpolate_with(entry.goal, 1.0 - exp(-SMOOTH * delta))

func _capture() -> Array:
	var rows: Array = []
	var addon := get_node_or_null("/root/FTNMice")
	if not is_instance_valid(addon) or addon.get("world") != world_sync.world or not (addon.get("mice") is Array):
		return rows
	var ids := {}
	for mouse in addon.get("mice"):
		if not (mouse is Node3D) or not is_instance_valid(mouse) or not mouse.is_inside_tree() or mouse.is_queued_for_deletion():
			continue
		var id := int(mouse.get("mouse_id"))
		var visual: Variant = mouse.get("visual")
		if id < 0 or id >= MAX_MICE or ids.has(id) or not (visual is Node3D) or not is_instance_valid(visual):
			continue
		ids[id] = true
		var animation: Variant = mouse.get("animation")
		var clip := ""
		var position := 0.0
		var speed := 1.0
		if animation is AnimationPlayer and is_instance_valid(animation):
			clip = animation.current_animation
			if not clip.is_empty():
				position = animation.current_animation_position
				speed = animation.speed_scale
		rows.append([id, mouse.global_transform, visual.transform, visual.is_visible_in_tree(), clip, position, speed])
	return rows

func publish(pid: int = 0) -> void:
	if not _ready_for_state() or not mp.is_host:
		return
	var rows := _capture()
	if not _valid_rows(rows):
		return
	var raw := var_to_bytes(rows)
	if raw.size() > MAX_RAW:
		return
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	_sequence += 1
	if pid != 0:
		mp._rx_mice.rpc_id(pid, world_sync.economy.epoch, _sequence, packed, raw.size(), mp._outgoing_world_seed())
	else:
		for peer in mp.players:
			if peer != 1 and mp.players[peer].get("state") == "world":
				mp._rx_mice.rpc_id(peer, world_sync.economy.epoch, _sequence, packed, raw.size(), mp._outgoing_world_seed())

func on_state(epoch: String, sequence: int, packed: PackedByteArray, raw_size: int) -> void:
	if not _ready_for_state() or mp.is_host or epoch != world_sync.economy.epoch or sequence <= 0:
		return
	if epoch == _epoch and sequence <= _received:
		return
	if raw_size <= 0 or raw_size > MAX_RAW or packed.is_empty() or packed.size() > MAX_RAW:
		return
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return
	var rows: Variant = bytes_to_var(raw)
	if not _valid_rows(rows):
		return
	if epoch != _epoch:
		_clear_views()
		_epoch = epoch
	_received = sequence
	if not rows.is_empty() and not _load_template():
		return
	var seen := {}
	for row in rows:
		var id: int = row[0]
		seen[id] = true
		if not _views.has(id):
			_views[id] = _create_view(id, row[1])
		var entry: Dictionary = _views[id]
		entry.goal = row[1]
		entry.visual.transform = row[2]
		entry.visual.visible = row[3]
		var animation: AnimationPlayer = entry.animation
		if animation != null:
			var clip: String = row[4]
			if clip.is_empty() or not animation.has_animation(clip):
				animation.stop()
			else:
				if animation.current_animation != clip:
					animation.play(clip, 0.15)
				animation.speed_scale = row[6]
				if absf(animation.current_animation_position - row[5]) > 0.2:
					animation.seek(row[5], true)
	for id in _views.keys():
		if not seen.has(id):
			_remove_view(id)

func _valid_rows(rows: Variant) -> bool:
	if not (rows is Array) or rows.size() > MAX_MICE:
		return false
	var ids := {}
	for row in rows:
		if not (row is Array) or row.size() != 7 or not (row[0] is int) or row[0] < 0 or row[0] >= MAX_MICE or ids.has(row[0]):
			return false
		ids[row[0]] = true
		if not _valid_transform(row[1]) or not _valid_transform(row[2]) or not (row[3] is bool) or not (row[4] is String) or row[4].length() > 128:
			return false
		for i in [5, 6]:
			if not (row[i] is float or row[i] is int) or not is_finite(float(row[i])):
				return false
		if row[5] < 0.0 or row[5] > 86400.0 or absf(row[6]) > 10.0:
			return false
	return true

func _valid_transform(value: Variant) -> bool:
	if not (value is Transform3D) or not value.is_finite() or value.origin.length() > 100000.0:
		return false
	return absf(value.basis.determinant()) > 0.000000000001 and value.basis.x.length() <= 10.0 and value.basis.y.length() <= 10.0 and value.basis.z.length() <= 10.0

func _load_template() -> bool:
	if is_instance_valid(_template):
		return true
	if _model_attempted:
		return false
	_model_attempted = true
	if not FileAccess.file_exists(MODEL) or not ClassDB.class_exists("GLTFDocument"):
		return false
	var document: Object = ClassDB.instantiate("GLTFDocument")
	var state: Object = ClassDB.instantiate("GLTFState")
	if int(document.call("append_from_file", MODEL, state)) != OK:
		return false
	_template = document.call("generate_scene", state)
	return is_instance_valid(_template)

func _create_view(id: int, pose: Transform3D) -> Dictionary:
	var node := Node3D.new()
	node.name = "MPMouse%d" % id
	world_sync.world.add_child(node)
	node.global_transform = pose
	var visual := _template.duplicate(0) as Node3D
	node.add_child(visual)
	var animation: AnimationPlayer
	var pending: Array[Node] = [visual]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		for next in child.get_children():
			pending.append(next)
		if child is AnimationPlayer:
			animation = child
			for clip in animation.get_animation_list():
				animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return {"node": node, "visual": visual, "animation": animation, "goal": pose}

func _remove_view(id: int) -> void:
	var node: Node = _views[id].node
	if is_instance_valid(node):
		node.queue_free()
	_views.erase(id)

func _clear_views() -> void:
	for id in _views.keys():
		_remove_view(id)
