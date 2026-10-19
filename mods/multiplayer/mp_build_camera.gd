extends Node

signal notice(message: String)
signal mode_changed(enabled: bool)

const MODE := "orthographic_build_v1"
const MAP_HALF_EXTENT := 128.0
static var _map_bounds := Rect2(Vector2(-MAP_HALF_EXTENT, -MAP_HALF_EXTENT), Vector2.ONE * MAP_HALF_EXTENT * 2.0)
const MIN_HEIGHT := 8.0
const MAX_HEIGHT := 32.0
const MIN_SIZE := 6.0
const MAX_SIZE := 128.0
const BELOW_PLAYER := 8.0
const NEAR := 0.05
const CAMERA_BASIS := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0))
const CAMERA_FIELDS := ["projection", "size", "fov", "near", "far", "h_offset", "v_offset", "frustum_offset", "keep_aspect", "cull_mask", "environment", "attributes"]
const PROCESS_FLAGS := {"process": "is_processing", "physics_process": "is_physics_processing", "process_input": "is_processing_input", "process_unhandled_input": "is_processing_unhandled_input", "process_unhandled_key_input": "is_processing_unhandled_key_input"}
const HAND_TOOLS := ["hand", "shovel", "pitchfork", "broom", "detector", "yard_vac", "lighter", "carry"]

var player: Node3D
var active := false
var toggle_key: Key = KEY_F7
var _camera: Camera3D
var _source_camera: Camera3D
var _cutaway: Node
var _saved := {}
var _anchor := Vector3.ZERO
var _focus := Vector3.ZERO
var _height := 20.0
var _size := 16.0
var _rotation_cursor := Vector2.INF
var _rotation_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

func start(target: Node3D) -> void:
	if active:
		leave()
	player = target
	_map_bounds = Rect2(Vector2(-MAP_HALF_EXTENT, -MAP_HALF_EXTENT), Vector2.ONE * MAP_HALF_EXTENT * 2.0)
	var terrain := player.get_parent().get_node_or_null("YardTerrain")
	if terrain is Node3D:
		var centre: Vector3 = terrain.to_global(terrain.centre)
		var half: float = (terrain.SOLID_SAMPLES - 1) * terrain.CELL * terrain.global_basis.x.length() * 0.5
		_map_bounds = Rect2(Vector2(centre.x - half, centre.z - half), Vector2.ONE * half * 2.0)
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)

func enter() -> bool:
	if active:
		return true
	if not is_instance_valid(player) or not player.is_inside_tree() or _menu_up():
		return false
	var source: Variant = player.get("camera")
	var tool: Variant = player.get("build")
	if not (source is Camera3D) or not is_instance_valid(source) or not is_instance_valid(tool):
		return false
	_source_camera = source
	_saved = {"camera_transform": _source_camera.transform, "current_camera": player.get_viewport().get_camera_3d(), "mouse_mode": Input.mouse_mode, "flags": {}, "camera": {}, "tools": {}}
	for key in HAND_TOOLS:
		if not key in player:
			continue
		var hand_tool: Variant = player.get(key)
		if not is_instance_valid(hand_tool) or not (hand_tool is Node) or hand_tool == tool or _saved.tools.has(hand_tool):
			continue
		if key == "yard_vac":
			for action in ["set_sucking", "set_pouring"]:
				if hand_tool.has_method(action):
					hand_tool.call(action, false)
		_saved.tools[hand_tool] = hand_tool.process_mode
		hand_tool.process_mode = Node.PROCESS_MODE_DISABLED
	for key in CAMERA_FIELDS:
		_saved.camera[key] = _source_camera.get(key)
	for flag in PROCESS_FLAGS:
		_saved.flags[flag] = bool(player.call(PROCESS_FLAGS[flag]))
		player.call("set_" + flag, false)
	if "_mouse_captured" in player:
		_saved["mouse_captured"] = player.get("_mouse_captured")
		player.set("_mouse_captured", true)
	_anchor = player.global_position
	_focus = _anchor
	if not is_instance_valid(_camera):
		_camera = Camera3D.new()
		_camera.name = "MPBuildCamera"
		add_child(_camera)
	for key in ["cull_mask", "environment", "attributes"]:
		_camera.set(key, _source_camera.get(key))
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = NEAR
	_camera.far = 128.0
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	_camera.frustum_offset = Vector2.ZERO
	player.set("camera", _camera)
	_update_camera()
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = true
	if not is_instance_valid(_cutaway):
		_cutaway = preload("res://mods/multiplayer/mp_build_cutaway.gd").new()
		add_child(_cutaway)
	_cutaway.begin(player.get_parent(), _camera)
	mode_changed.emit(true)
	return true

func leave() -> void:
	if not active:
		return
	end_rotation()
	if is_instance_valid(_cutaway):
		_cutaway.finish()
	active = false
	if is_instance_valid(player):
		if is_instance_valid(_source_camera):
			player.set("camera", _source_camera)
			_source_camera.transform = _saved.camera_transform
			for key in _saved.camera:
				_source_camera.set(key, _saved.camera[key])
		for hand_tool in _saved.tools:
			if is_instance_valid(hand_tool):
				hand_tool.process_mode = _saved.tools[hand_tool]
		for flag in _saved.flags:
			player.call("set_" + flag, _saved.flags[flag])
		if _saved.has("mouse_captured"):
			player.set("_mouse_captured", _saved.mouse_captured)
	if is_instance_valid(_camera):
		_camera.clear_current(false)
	var previous: Variant = _saved.get("current_camera")
	if is_instance_valid(previous):
		previous.make_current()
	Input.mouse_mode = int(_saved.get("mouse_mode", Input.MOUSE_MODE_VISIBLE)) as Input.MouseMode
	_saved.clear()
	mode_changed.emit(false)

func _exit_tree() -> void:
	leave()

func _menu_up() -> bool:
	return is_instance_valid(player) and player.has_method("menu_is_up") and bool(player.call("menu_is_up"))

func _process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(player) or not player.is_inside_tree() or not is_instance_valid(_source_camera):
		leave()
		return
	if player.global_position.distance_to(_anchor) > 0.5:
		leave()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _rotation_cursor.is_finite() else Input.MOUSE_MODE_VISIBLE
	if _menu_up():
		end_rotation()
		return
	if "_mouse_captured" in player:
		player.set("_mouse_captured", true)
	var panel: Variant = (get_meta("mp_device_panel") if has_meta("mp_device_panel") else null)
	if is_instance_valid(panel) and panel.typing():
		return
	var direction := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	pan(direction, delta, Input.is_physical_key_pressed(KEY_SHIFT))

func pan(direction: Vector2, delta: float, faster: bool = false) -> void:
	if not active or not direction.is_finite() or not is_finite(delta) or delta <= 0.0:
		return
	var amount := direction.limit_length() * _size * (1.4 if faster else 0.7) * minf(delta, 0.1)
	var next := Vector2(_focus.x, _focus.z) + amount
	next = next.clamp(_map_bounds.position, _map_bounds.end)
	_focus = Vector3(next.x, _anchor.y, next.y)
	_update_camera()

func zoom(steps: float) -> void:
	if not active or not is_finite(steps):
		return
	_size = clampf(_size * pow(0.85, clampf(steps, -10.0, 10.0)), MIN_SIZE, MAX_SIZE)
	_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(_camera):
		return
	_camera.size = _size
	_camera.global_transform = Transform3D(CAMERA_BASIS, _focus + Vector3.UP * _height)

func request_view(pixel: Vector2 = Vector2.INF) -> Dictionary:
	if not active or not is_instance_valid(_camera):
		return {}
	var viewport := _camera.get_viewport()
	var dimensions := viewport.get_visible_rect().size
	if dimensions.x <= 0.0 or dimensions.y <= 0.0:
		return {}
	if not pixel.is_finite():
		pixel = _rotation_cursor if _rotation_cursor.is_finite() else viewport.get_mouse_position()
	return {"mode": MODE, "focus": _focus, "height": _height, "size": _size, "aspect": dimensions.x / dimensions.y, "cursor": pixel / dimensions * 2.0 - Vector2.ONE}

func begin_rotation() -> void:
	if not active or _menu_up() or _rotation_cursor.is_finite():
		return
	_rotation_cursor = _camera.get_viewport().get_mouse_position()
	_rotation_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func end_rotation() -> void:
	if not _rotation_cursor.is_finite():
		return
	var cursor := _rotation_cursor
	_rotation_cursor = Vector2.INF
	Input.mouse_mode = _rotation_mouse_mode
	Input.warp_mouse(cursor)

func current_ray() -> Dictionary:
	return validate_view(request_view(), _anchor)

func ray_origin() -> Vector3:
	var ray := current_ray()
	return ray.origin if not ray.is_empty() else _focus + Vector3.UP * (_height - NEAR)

func ray_direction() -> Vector3:
	return Vector3.DOWN

func ray_length() -> float:
	return _height - NEAR + BELOW_PLAYER

func _input(event: InputEvent) -> void:
	var panel: Variant = (get_meta("mp_device_panel") if has_meta("mp_device_panel") else null)
	if active and is_instance_valid(panel):
		if event is InputEventMouse and panel.contains_mouse(event.position):
			return
		if event is InputEventKey and panel.typing():
			if event.pressed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
				panel.release_text_focus()
				get_viewport().set_input_as_handled()
				return
			if event.keycode != toggle_key and event.physical_keycode != toggle_key:
				return
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and not event.meta_pressed and (event.physical_keycode == toggle_key or event.keycode == toggle_key):
		if _menu_up():
			return
		if active:
			leave()
		elif key_available(toggle_key):
			enter()
		else:
			notice.emit(_tr("F7 ist bereits einer anderen Aktion zugewiesen.", "F7 is already assigned to another action."))
			return
		get_viewport().set_input_as_handled()
		return
	if not active or _menu_up():
		return
	if event is InputEventKey and (event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] or event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
		leave()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not active or _menu_up():
		return
	var tool: Variant = player.get("build")
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not is_instance_valid(tool) or not bool(tool.call("is_active")):
				get_viewport().set_input_as_handled()
				return
			if current_ray().is_empty():
				notice.emit(_tr("Außerhalb der Karte", "Outside the map"))
			else:
				tool.call("primary")
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if is_instance_valid(tool) and bool(tool.call("is_active")):
				tool.call("back_out")
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_catalog"):
		var catalog: Variant = player.get("catalog")
		if is_instance_valid(catalog):
			catalog.call("set_open", true)
		get_viewport().set_input_as_handled()

	elif InputMap.has_action("interact") and event.is_action_pressed("interact"):
		if not current_ray().is_empty():
			var opened := player.has_method("mp_open_build_console") and bool(player.call("mp_open_build_console"))
			if not opened and is_instance_valid(tool) and bool(tool.call("is_active")) and tool.has_method("begin_reverse"):
				tool.call("begin_reverse")
		get_viewport().set_input_as_handled()

static func key_available(key: Key) -> bool:
	for action in InputMap.get_actions():
		if key == KEY_F7 and action == &"bug_report":
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and (event.keycode == key or event.physical_keycode == key):
				return false
	return true

static func point_allowed(point: Vector3, origin: Vector3) -> bool:
	return point.is_finite() and origin.is_finite() and _map_bounds.grow(0.01).has_point(Vector2(point.x, point.z)) and point.y >= origin.y - BELOW_PLAYER - 0.01 and point.y <= origin.y + MAX_HEIGHT + 0.01

static func validate_view(view: Variant, origin: Vector3) -> Dictionary:
	if not (view is Dictionary) or view.get("mode") != MODE or not origin.is_finite():
		return {}
	if not (view.get("focus") is Vector3) or not (view.get("cursor") is Vector2):
		return {}
	for key in ["height", "size", "aspect"]:
		if not (view.get(key) is float or view.get(key) is int) or not is_finite(float(view[key])):
			return {}
	var focus: Vector3 = view.focus
	var cursor: Vector2 = view.cursor
	var height := float(view.height)
	var size := float(view.size)
	var aspect := float(view.aspect)
	if not focus.is_finite() or not cursor.is_finite() or absf(focus.y - origin.y) > 0.5 or absf(cursor.x) > 1.0 or absf(cursor.y) > 1.0 or not point_allowed(focus, origin):
		return {}
	if height < MIN_HEIGHT or height > MAX_HEIGHT or size < MIN_SIZE or size > MAX_SIZE or aspect < 0.2 or aspect > 6.0:
		return {}
	var from := focus + Vector3(cursor.x * size * aspect * 0.5, height - NEAR, cursor.y * size * 0.5)
	if not point_allowed(from, origin):
		return {}
	return {"origin": from, "direction": Vector3.DOWN, "length": height - NEAR + BELOW_PLAYER, "transform": Transform3D(CAMERA_BASIS, from)}

static func inputs_allowed(inputs: Dictionary, origin: Vector3) -> bool:
	if not origin.is_finite():
		return false
	if inputs.get("_state", 0) == 1:
		if not (inputs.get("_anchor") is Vector3) or not point_allowed(inputs._anchor, origin):
			return false
	if inputs.has("_route") and not _points_allowed(inputs._route, origin):
		return false
	for key in ["_finished_at", "_tee_stop_at"]:
		if inputs.has(key) and not _optional_point_allowed(inputs[key], origin):
			return false
	return true

static func tool_allowed(tool: Node, origin: Vector3) -> bool:
	if not is_instance_valid(tool) or not origin.is_finite():
		return false
	var run_visible := (tool.has_method("_is_conveyor_mode") and bool(tool.call("_is_conveyor_mode"))) or _ghost_visible(tool, "_pipe_ghost")
	if run_visible:
		for key in ["_route", "_bare_knees"]:
			if key in tool and not _points_allowed(tool.get(key), origin):
				return false
		for key in ["_route_from", "_route_to"]:
			if key in tool and not _optional_point_allowed(tool.get(key), origin):
				return false
	var attached := {
		"_generator_ramp": ["_generator_ghost", "_plant_ghost"],
		"_stairs_belt": ["_stairs_ghost"],
		"_seat_stub": ["_scanner_ghost", "_pelletizer_ghost", "_launcher_ghost", "_compressor_ghost", "_pulper_ghost", "_paper_ghost", "_briquette_ghost", "_wrapper_ghost"],
		"_seat_far": ["_scanner_ghost", "_pelletizer_ghost", "_launcher_ghost", "_compressor_ghost", "_pulper_ghost", "_paper_ghost", "_briquette_ghost", "_wrapper_ghost"],
		"_t_stub": ["_t_splitter_ghost"]}
	for key in attached:
		if key in tool and _any_ghost_visible(tool, attached[key]) and not _points_allowed(tool.get(key), origin):
			return false
	if "_wye_belts" in tool and _any_ghost_visible(tool, ["_splitter_ghost", "_compact_splitter_ghost", "_smart_splitter_ghost", "_compact_joiner_ghost", "_joiner_ghost", "_u_splitter_ghost", "_u_joiner_ghost", "_t_splitter_ghost"]):
		for belt in tool.get("_wye_belts"):
			if not _points_allowed(belt, origin):
				return false
	if "_port_belts" in tool and _any_ghost_visible(tool, ["_lift_ghost", "_silo_ghost"]):
		for port in tool.get("_port_belts"):
			if not (port is Dictionary) or not _points_allowed(port.get("belt"), origin):
				return false
	var runs := {}
	for entry in [["_ghost", "_ghost_xf"], ["_pipe_ghost", "_pipe_xf"], ["_pipe_bend_ghost", "_pipe_bend_xf"]]:
		if entry[0] in tool and is_instance_valid(tool.get(entry[0])):
			runs[tool.get(entry[0])] = entry[1]
	for child in tool.get_children():
		if not (child is Node3D) or not child.is_visible_in_tree():
			continue
		if runs.has(child):
			if not (child is MultiMeshInstance3D) or not _run_allowed(child, tool.get(runs[child]), origin):
				return false
		elif child.has_method("set_preview_valid") and not _preview_allowed(tool, child, origin):
			return false
	return true

static func _optional_point_allowed(point: Variant, origin: Vector3) -> bool:
	return point is Vector3 and (point == Vector3.INF or point_allowed(point, origin))

static func _points_allowed(points: Variant, origin: Vector3) -> bool:
	if not (points is PackedVector3Array or points is Array) or points.size() > 4096:
		return false
	for point in points:
		if not (point is Vector3) or not point_allowed(point, origin):
			return false
	return true

static func _ghost_visible(tool: Node, key: String) -> bool:
	if not key in tool:
		return false
	var ghost: Variant = tool.get(key)
	return is_instance_valid(ghost) and ghost is Node3D and ghost.is_visible_in_tree()

static func _any_ghost_visible(tool: Node, keys: Array) -> bool:
	for key in keys:
		if _ghost_visible(tool, key):
			return true
	return false

static func _run_allowed(ghost: MultiMeshInstance3D, transforms: Variant, origin: Vector3) -> bool:
	var mm := ghost.multimesh
	if mm == null or mm.mesh == null:
		return true
	if not (transforms is Array):
		return false
	var count := mm.visible_instance_count
	if count < 0:
		count = mm.instance_count
	if count > transforms.size() or count > mm.instance_count:
		return false
	var box := mm.mesh.get_aabb()
	for i in count:
		if not (transforms[i] is Transform3D) or not _box_allowed(ghost.global_transform * transforms[i], box, origin):
			return false
	return true

static func _box_allowed(transform: Transform3D, box: AABB, origin: Vector3) -> bool:
	if not transform.is_finite() or not box.position.is_finite() or not box.size.is_finite():
		return false
	for i in 8:
		if not point_allowed(transform * box.get_endpoint(i), origin):
			return false
	return true

static func _preview_allowed(tool: Node, ghost: Node3D, origin: Vector3) -> bool:
	if not point_allowed(ghost.global_position, origin):
		return false
	if ghost.has_method("footprint_points"):
		return _points_allowed(ghost.call("footprint_points"), origin)
	if ghost.has_method("footprint"):
		var discs: Variant = ghost.call("footprint")
		if discs is Array or discs is PackedVector4Array:
			var checked := false
			for disc in discs:
				if not (disc is Vector4):
					checked = false
					break
				checked = true
				if not disc.is_finite() or disc.w < 0.0:
					return false
				for offset in [Vector3(-disc.w, 0.0, -disc.w), Vector3(disc.w, 0.0, -disc.w), Vector3(disc.w, 0.0, disc.w), Vector3(-disc.w, 0.0, disc.w)]:
					if not point_allowed(Vector3(disc.x, disc.y, disc.z) + offset, origin):
						return false
			if checked:
				return true
	var measured := false
	if tool.has_method("_shape_box"):
		for node in ghost.find_children("*", "CollisionShape3D", true, false):
			var collision := node as CollisionShape3D
			if collision.shape == null or collision.get_parent() is Area3D:
				continue
			var box: AABB = tool.call("_shape_box", collision.shape)
			if box.has_volume():
				measured = true
				if not _box_allowed(collision.global_transform, box, origin):
					return false
	if not measured:
		for node in ghost.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh != null and mesh.is_visible_in_tree() and not _box_allowed(mesh.global_transform, mesh.mesh.get_aabb(), origin):
				return false
	return true

static func _tr(de: String, en: String) -> String:
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase(de, en)
