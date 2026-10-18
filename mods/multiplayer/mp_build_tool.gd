extends "res://scripts/build/build_tool.gd"

const Cutaway = preload("res://mods/multiplayer/mp_build_cutaway.gd")
const BuildCamera = preload("res://mods/multiplayer/mp_build_camera.gd")
const BuildSnapshot = preload("res://mods/multiplayer/mp_build_snapshot.gd")
const BuildAlignment = preload("res://mods/multiplayer/mp_build_alignment.gd")
const WallPalette = preload("res://mods/multiplayer/mp_wall_palette.gd")
const ParallelBelts = preload("res://mods/multiplayer/mp_parallel_belts.gd")


const INPUT_FIELDS := ["_state", "_anchor", "_anchor_dir", "_anchor_side", "_anchor_span",
	"_upstream", "_stair_outward", "_ghost_turn", "_roof_turn", "_t_turn", "_grid_on",
	"_snap_off", "_work_height", "_work_base", "_reach", "pipe_shape", "_fit_roll",
	"_tee_stop", "_tee_stop_at", "_finished_at", "_route", "_route_pinned",
	"_turned_since_place", "_copied_since_place", "_mp_yaw_locked", "_mp_yaw", "_mp_flow_manual", "_mp_parallel"]
const COUNTER_FIELDS := ["dismantled", "reversed", "upgraded", "downgraded", "placed",
	"placed_on_grid", "placed_turned", "placed_copied"]
var mp_economy: Node
var request_id := 0
var input_revision := 0
var sent_revision := 0
var price_limit := INF
var last_place_request := 0
var cancelled_place_request := 0
var cancel_requested := false
var _mp_yaw_locked := false
var _mp_yaw := 0.0
var _mp_rotate_held := false
var _mp_rotate_dragged := false
var _mp_rotate_pending := 0.0
var _mp_flow_manual := false
var _mp_parallel := false
var _mp_preview_flow: MultiMeshInstance3D
const FLOW_TOGGLE_KEY := KEY_F6
const ROTATE_RADIANS_PER_PIXEL := 0.008
const ROTATE_DRAG_THRESHOLD := 3.0

func _exit_tree() -> void:
	_drop_taps()

func set_mode(mode: Mode) -> void:
	_mp_flow_manual = false
	_end_rotation(false)
	_mp_yaw_locked = false
	_mp_yaw = 0.0
	_cancel_remote()
	input_revision += 1
	super.set_mode(mode)

func set_active(on: bool) -> void:
	if not on:
		_end_rotation(false)
		_cancel_remote()
		input_revision += 1
	super.set_active(on)

func cancel() -> void:
	_mp_flow_manual = false
	_end_rotation(false)
	_cancel_remote()
	input_revision += 1
	super.cancel()

func _cancel_remote() -> void:
	if last_place_request == 0 or last_place_request == cancelled_place_request:
		return
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		return
	cancel_requested = true
	_send_cancel()

func _send_cancel() -> void:
	if not cancel_requested or not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		return
	if mp_economy.request("build_cancel", {}) != 0:
		cancelled_place_request = last_place_request
		cancel_requested = false

func primary() -> void:
	if _mp_rotate_held:
		return
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		execute_native("place", null, {})
		return
	if not _active or request_id != 0:
		return
	builds.ghost_reading = true
	_update_ghost(0.0)
	builds.ghost_reading = false
	_request("place", {"max_price": maxf(0.0, float(status().get("cost", 0.0)))})

func dismantle(target: Node3D, one := false) -> void:
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		super.dismantle(target, one)
		return
	if is_instance_valid(target):
		_request("demolish", {"target": BuildSnapshot.row(target), "one": one})

func dismantle_tile(deck: Platform, tile: Rect2) -> void:
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		super.dismantle_tile(deck, tile)
		return
	if is_instance_valid(deck):
		_request("demolish_tile", {"target": deck.to_dict(), "tile": tile})

func reverse(target: Node3D) -> void:
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		super.reverse(target)
		return
	if is_instance_valid(target):
		_request("reverse", {"target": BuildSnapshot.row(target)})

func _pay(amount: float) -> bool:
	if not is_finite(amount) or amount < 0.0 or amount > price_limit + 0.001:
		return false
	return super._pay(amount)

func prepare_mode(mode: Mode, inputs: Dictionary) -> void:
	var anchor := _tap_anchor
	var pulper := _tap_anchor_pulper
	var requested: Variant = inputs.get("_anchor")
	var keep: bool = _mode == Mode.WATER_PIPE and mode == Mode.WATER_PIPE and inputs.get("_state") == State.RUNNING \
		and requested is Vector3 and requested.is_finite() \
		and is_instance_valid(anchor) and is_instance_valid(pulper) \
		and anchor.is_inside_tree() and not anchor.is_queued_for_deletion() \
		and pulper.is_inside_tree() and not pulper.is_queued_for_deletion() \
		and anchor.get_parent() == pulper and pulper in builds.pulpers \
		and pulper.is_pending_tap(anchor) and anchor.global_position.distance_to(requested) < 0.001
	if keep:
		_tap_anchor = null
		_tap_anchor_pulper = null
	set_mode(mode)
	if keep:
		_tap_anchor = anchor
		_tap_anchor_pulper = pulper

func capture_inputs() -> Dictionary:
	var out := {}
	for key in INPUT_FIELDS:
		out[key] = get(key)
	return out.duplicate(true)

func _request(action: String, args: Dictionary) -> void:
	_send_cancel()
	if cancel_requested:
		return
	if request_id != 0:
		return
	if action == "place":
		args["build_id"] = player.build_id
		args["inputs"] = capture_inputs()
	args["body"] = player.global_transform
	args["camera"] = player.camera.global_transform
	var controller: Variant = player.get("mp_build_camera") if "mp_build_camera" in player else null
	if is_instance_valid(controller) and controller.active:
		args["build_view"] = controller.request_view()
	sent_revision = input_revision
	request_id = mp_economy.request(action, args)
	if action == "place" and request_id != 0:
		last_place_request = request_id

func accept_result(seq: int, result: Dictionary) -> void:
	_send_cancel()
	if seq != request_id:
		return
	request_id = 0
	if not result.get("ok", false):
		return
	var counters: Dictionary = result.get("counters", {})
	for key in COUNTER_FIELDS:
		set(key, int(get(key)) + maxi(0, int(counters.get(key, 0))))
	if int(counters.get("placed", 0)) > 0 and not mp_economy.mp.is_host:
		Cfg.place_build(str(result.get("build_id", player.build_id)))
	if result.has("reversed_target"):
		last_reversed = mp_economy.world_sync._find_building(result.reversed_target) as Conveyor
	if input_revision != sent_revision:
		return
	var inputs: Dictionary = result.get("inputs", {})
	for key in INPUT_FIELDS:
		if inputs.has(key):
			set(key, inputs[key])
	_pick += 1

func execute_native(action: String, target: Node3D, args: Dictionary) -> void:
	var ray := _camera_ray()
	var saved_reach := _reach
	if not ray.is_empty():
		_reach = ray.length
	match action:
		"place":
			super.primary()
		"demolish":
			super.dismantle(target, bool(args.get("one", false)))
		"demolish_tile":
			super.dismantle_tile(target as Platform, args.get("tile", Rect2()))
		"reverse":
			super.reverse(target)
	_reach = saved_reach

func _camera_ray() -> Dictionary:
	if player == null:
		return {}
	if player.has_meta("mp_build_view"):
		return player.get_meta("mp_build_view")
	var controller: Variant = player.get("mp_build_camera") if "mp_build_camera" in player else null
	if is_instance_valid(controller) and controller.active:
		var ray: Dictionary = controller.current_ray()
		if not ray.is_empty():
			ray["anchor"] = player.global_position
		return ray
	return {}

func _raw_surface_hit() -> Dictionary:
	var ray := _camera_ray()
	if ray.is_empty():
		return super._raw_surface_hit()
	var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.origin + ray.direction * float(ray.length), Cfg.BUILD_SURFACE_MASK)
	query.collide_with_areas = false
	var hit := Cutaway.intersect_ray(get_world_3d().direct_space_state, query, true)
	var body := hit.get("collider") as Node
	return {} if body != null and body.get_parent() is DeliveryTruck else hit

func _column_hit(hit: Dictionary, on: Vector3) -> Dictionary:
	var result := super._column_hit(hit, on)
	if _camera_ray().is_empty() or not Cutaway.roof_collider(result.get("collider") as Node):
		return result
	var query := PhysicsRayQueryParameters3D.create(on + Vector3.UP * Cfg.BUILD_GRID_PROBE, on + Vector3.DOWN * Cfg.BUILD_GRID_PROBE, Cfg.BUILD_SURFACE_MASK)
	query.collide_with_areas = false
	var under := Cutaway.intersect_ray(get_world_3d().direct_space_state, query, true)
	if not under.is_empty():
		under.position = Vector3(on.x, under.position.y, on.z)
		if under.get("collider") is Platform:
			under.normal = Vector3.UP
		return under
	var fallback := hit.duplicate()
	fallback.position = on
	return fallback

func _update_ghost(delta: float) -> void:
	var ray := _camera_ray()
	var saved_reach := _reach
	if not ray.is_empty():
		_reach = ray.length
	super._update_ghost(delta)
	if not ray.is_empty():
		_reach = saved_reach
		if not BuildCamera.tool_allowed(self, ray.anchor):
			_eval = _eval.duplicate()
			_eval["ok"] = false
			_eval["done"] = false
			_eval["reason"] = preload("res://mods/multiplayer/mp_i18n.gd").phrase("Außerhalb der Karte", "Outside the map")

func dismantle_reach() -> float:
	var ray := _camera_ray()
	return float(ray.length) if not ray.is_empty() else super.dismantle_reach()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mp_parallel", false, true) and _active and _is_conveyor_mode() and is_instance_valid(player) and player.is_mouse_captured() and not player.menu_is_up():
		_mp_parallel = not _mp_parallel
		_pick += 1
		input_revision += 1
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and not event.meta_pressed and (event.physical_keycode == FLOW_TOGGLE_KEY or event.keycode == FLOW_TOGGLE_KEY):
		if toggle_flow():
			get_viewport().set_input_as_handled()
		return
	if _mp_rotate_held and event.is_action_released("build_rotate"):
		_end_rotation(_rotation_available())
		get_viewport().set_input_as_handled()
		return
	if not _rotation_available():
		_end_rotation(false)
		return
	if _mp_rotate_held and (event.is_action("primary") or event.is_action("secondary")):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_rotate") and not event.is_echo():
		_mp_rotate_held = true
		_mp_rotate_dragged = false
		_mp_rotate_pending = 0.0
		var controller: Variant = player.get("mp_build_camera") if "mp_build_camera" in player else null
		if is_instance_valid(controller) and controller.active:
			controller.begin_rotation()
		get_viewport().set_input_as_handled()
	elif _mp_rotate_held and event is InputEventMouseMotion:
		var movement: float = event.screen_relative.x if event.screen_relative != Vector2.ZERO else event.relative.x
		if is_finite(movement):
			_mp_rotate_pending += clampf(movement, -1000.0, 1000.0)
			if _mp_rotate_dragged or absf(_mp_rotate_pending) >= ROTATE_DRAG_THRESHOLD:
				if not _mp_rotate_dragged:
					_begin_free_rotation()
					_mp_rotate_dragged = true
				_rotate_free(_mp_rotate_pending * ROTATE_RADIANS_PER_PIXEL)
				_mp_rotate_pending = 0.0
		get_viewport().set_input_as_handled()

func _rotation_available() -> bool:
	return _active and is_instance_valid(player) and player.is_mouse_captured() and not player.menu_is_up() and (can_turn() or _mode == Mode.ROBOTIC_ARM) and _mode != Mode.BELT_GATE and not (_mode in [Mode.WATER_SPLITTER, Mode.WATER_TEE] and fitting_snapped()) and not (_is_roof(_mode) and _state == State.RUNNING)

func _begin_free_rotation() -> void:
	var direction := _aim_forward()
	if _is_roof(_mode) and is_instance_valid(_roof_ghost):
		direction = _roof_ghost.b - _roof_ghost.a
	elif _mode == Mode.ROBOTIC_ARM and is_instance_valid(_arm_ghost):
		direction = _arm_ghost.global_basis.z
	_mp_yaw = wrapf(atan2(direction.x, direction.z), -PI, PI)
	_mp_yaw_locked = true
	_ghost_turn = 0
	_roof_turn = 0

func _rotate_free(amount: float) -> void:
	if not is_finite(amount):
		return
	_mp_yaw = wrapf(_mp_yaw + clampf(amount, -TAU, TAU), -PI, PI)
	_turned_since_place = true
	input_revision += 1
	_pick += 1

func _step_rotation() -> void:
	var event := InputEventAction.new()
	event.action = "build_rotate"
	event.pressed = true
	super._unhandled_input(event)
	input_revision += 1
	_pick += 1

func _end_rotation(apply_tap: bool) -> void:
	if is_instance_valid(player) and "mp_build_camera" in player:
		var controller: Variant = player.get("mp_build_camera")
		if is_instance_valid(controller):
			controller.end_rotation()
	if _mp_rotate_held and not _mp_rotate_dragged and apply_tap:
		_step_rotation()
	_mp_rotate_held = false
	_mp_rotate_dragged = false
	_mp_rotate_pending = 0.0

func _aim_forward(fallback: Vector3 = Vector3.BACK) -> Vector3:
	if not _mp_yaw_locked:
		return super._aim_forward(fallback)
	var angle := _mp_yaw + PI * 0.5 * float(posmod(_ghost_turn, 4))
	return Vector3(sin(angle), 0.0, cos(angle))

func _turn_in_cell(a: Vector3, b: Vector3, side: int) -> Dictionary:
	if not _mp_yaw_locked:
		return super._turn_in_cell(a, b, side)
	var direction := b - a
	direction.y = 0.0
	if direction.length_squared() < 0.000001:
		return {"a": a, "b": b, "side": side}
	var right := Vector3(direction.z, 0.0, -direction.x).normalized()
	var centre := (a + b) * 0.5 + right * (float(side) * Cfg.ROOF_DEPTH * 0.5)
	var angle := _mp_yaw + PI * 0.5 * float(posmod(_roof_turn, 4)) - atan2(direction.x, direction.z)
	return {"a": centre + (a - centre).rotated(Vector3.UP, angle), "b": centre + (b - centre).rotated(Vector3.UP, angle), "side": side}

static func rotation_inputs_allowed(inputs: Dictionary) -> bool:
	if inputs.has("_mp_parallel") and not (inputs._mp_parallel is bool):
		return false
	if inputs.has("_mp_flow_manual") and not (inputs._mp_flow_manual is bool):
		return false
	if inputs.has("_mp_yaw_locked") and not (inputs._mp_yaw_locked is bool):
		return false
	if inputs.has("_mp_yaw") and (not (inputs._mp_yaw is float) or not is_finite(inputs._mp_yaw) or absf(inputs._mp_yaw) > PI):
		return false
	return not inputs.get("_mp_yaw_locked", false) or inputs.has("_mp_yaw")

func can_toggle_flow() -> bool:
	return _active and _is_conveyor_mode() and _state == State.RUNNING and is_instance_valid(player) and player.is_mouse_captured() and not player.menu_is_up() and BuildCamera.key_available(FLOW_TOGGLE_KEY)

func toggle_flow() -> bool:
	if not can_toggle_flow():
		return false
	var reversed := _upstream or _out_of_t(_aim_point())
	_mp_flow_manual = true
	_upstream = not reversed
	_drop_route()
	input_revision += 1
	_pick += 1
	return true

func flow_hint() -> String:
	if not _active or not _is_conveyor_mode() or not BuildCamera.key_available(FLOW_TOGGLE_KEY):
		return ""
	var reversed := _upstream or (_state == State.RUNNING and _out_of_t(_aim_point()))
	var direction := "B → A" if reversed else "A → B"
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase("F6 · Bandrichtung umkehren (%s)", "F6 · Reverse belt direction (%s)") % direction

func _out_of_t(point: Vector3) -> bool:
	return false if _mp_flow_manual else super._out_of_t(point)

func _chain_on(end: Vector3, joined: bool) -> void:
	super._chain_on(end, joined)
	if _state == State.AIMING:
		_mp_flow_manual = false

func _wrong_side_reason(from: Vector3, to: Vector3) -> String:
	if is_instance_valid(builds) and (builds.intake_at(from) or is_instance_valid(builds.outfeed_owner_at(to))):
		return tr("wrong side  ·  hay goes the other way here")
	return super._wrong_side_reason(from, to)

func _update_run(from: Vector3, to: Vector3, delta: float) -> void:
	if _mp_parallel and _is_conveyor_mode() and _state == State.RUNNING and _parallel_route(from, to):
		if _aim_off_ground:
			_eval.ok = false
			_eval.reason = tr("aim at ground")
		_shape_route_ghost()
		_update_belt_arm_columns(_route)
		return
	if _mp_parallel and _is_conveyor_mode() and _state == State.AIMING:
		var aligned := ParallelBelts.alignment(builds, from)
		if not aligned.is_empty():
			to = from + ParallelBelts.preview_direction(aligned, to - from, STUB_LENGTH) * STUB_LENGTH
	super._update_run(from, to, delta)
	if _state != State.RUNNING or not _is_conveyor_mode() or _mp_flow_manual or bool(_eval.get("ok", false)) or not is_instance_valid(builds):
		return
	var wrong := builds.intake_at(from) or is_instance_valid(builds.outfeed_owner_at(to)) or builds.t_role_at(from) == ConveyorTSplitter.ROLE_IN or builds.t_role_at(to) == ConveyorTSplitter.ROLE_OUT
	if not wrong:
		return
	var opposite := _evaluate(to, from, true)
	if opposite.get("ok", false):
		_upstream = from.is_equal_approx(_anchor)
		_drop_route()
		super._update_run(to, from, delta)
	else:
		super._update_run(from, to, 0.0)

func _aim_point() -> Vector3:
	var native := super._aim_point()
	if not _mp_parallel or not _is_conveyor_mode():
		return native
	var raw := _heighted(_raw_surface_point(Cfg.BELT_FRAME_DEPTH + Cfg.BELT_STAND_CLEAR))
	var aligned := ParallelBelts.alignment(builds, raw, _anchor if _state == State.RUNNING else Vector3.INF)
	if not aligned.is_empty():
		_joined = false
		return aligned.point
	return native

func _guided(anchor: Vector3, point: Vector3) -> Vector3:
	if _mp_parallel and _is_conveyor_mode():
		var aligned := ParallelBelts.alignment(builds, point, anchor)
		if not aligned.is_empty():
			_guide_turn = NAN
			return aligned.point
	return super._guided(anchor, point)

func _parallel_route(from: Vector3, to: Vector3) -> bool:
	var points := ParallelBelts.route(builds, from, to)
	if points.size() < 3 or points.size() > 256:
		return false
	_drop_route()
	if _router == null:
		_router = BeltRouter.new(self)
	_router.pipe = false
	var valid: bool = _router._clears(points, {})
	var reason := tr("blocked")
	for i in points.size() - 1:
		var evaluated := _evaluate(points[i], points[i + 1], true)
		if not evaluated.ok:
			reason = evaluated.reason
			valid = false
			break
	_route = points
	_route_from = from
	_route_to = to
	_apply_route()
	if not valid:
		_eval.ok = false
		_eval.reason = reason
	straight_reason = "" if _eval.ok else str(_eval.reason)
	return true

func _update_route(from: Vector3, to: Vector3, delta: float, corners := false) -> void:
	if _mp_parallel and _is_conveyor_mode():
		if _parallel_route(from, to):
			return
		if ParallelBelts.route(builds, from, to).size() == 2:
			_drop_route()
			return
	super._update_route(from, to, delta, corners)

func _leg_shape_reason(from: Vector3, to: Vector3, length: float) -> String:
	if not _is_conveyor_mode() or length <= Cfg.BELT_MAX_LENGTH:
		return super._leg_shape_reason(from, to, length)
	if not from.is_finite() or not to.is_finite() or not is_finite(length) or length > 400.0:
		return tr("too long")
	if not is_instance_valid(player) or not BuildCamera.point_allowed(from, player.global_position) or not BuildCamera.point_allowed(to, player.global_position):
		return preload("res://mods/multiplayer/mp_i18n.gd").phrase("Außerhalb der Karte", "Outside the map")
	return super._leg_shape_reason(from, from + (to - from) * (Cfg.BELT_MAX_LENGTH / length), Cfg.BELT_MAX_LENGTH)

func _lay_run(from: Vector3, to: Vector3, line_id := 0) -> void:
	var points := _port_knees(from, to)
	var long := false
	for i in points.size() - 1:
		long = long or points[i].distance_to(points[i + 1]) > Cfg.BELT_MAX_LENGTH
	if not long:
		super._lay_run(from, to, line_id)
		return
	if line_id == 0:
		line_id = builds.new_line_id()
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if length < 0.0001:
			continue
		var count := ceili(length / Cfg.BELT_MAX_LENGTH)
		for j in count:
			var start := points[i].lerp(points[i + 1], float(j) / count)
			var end := points[i].lerp(points[i + 1], float(j + 1) / count)
			if _mode == Mode.ENCLOSED_CONVEYOR:
				builds.add_enclosed_conveyor(start, end, line_id)
			else:
				builds.add_conveyor(start, end, line_id)

func _port_knees(from: Vector3, to: Vector3) -> PackedVector3Array:
	var points := super._port_knees(from, to)
	var service: Node = builds.call("_mp_sale_stations") if is_instance_valid(builds) and builds.has_method("_mp_sale_stations") else null
	if not is_instance_valid(service) or points.size() != 4:
		return points
	var stub := minf(Cfg.BELT_PORT_STUB, from.distance_to(to) * 0.5)
	if stub < Cfg.BELT_MIN_LENGTH * 0.5:
		return points
	var station: Node3D = service.port_at(to)
	if is_instance_valid(station) and station.mp_station_id > 1 and points[2].is_equal_approx(to):
		points[2] = to - station.intake_forward() * stub
	station = service.port_at(from)
	if is_instance_valid(station) and station.mp_station_id > 1 and points[1].is_equal_approx(from):
		points[1] = from + station.intake_forward() * stub
	return points

func control_hint() -> String:
	var hints := PackedStringArray()
	var i18n := preload("res://mods/multiplayer/mp_i18n.gd")
	if _is_conveyor_mode():
		hints.append(flow_hint())
		if InputMap.has_action("mp_parallel") and not InputMap.action_get_events("mp_parallel").is_empty():
			hints.append(i18n.phrase("F9 · Parallel-Modus: %s", "F9 · Parallel mode: %s").replace("F9", InputSetup.hint("mp_parallel")) % (i18n.phrase("Ein", "On") if _mp_parallel else i18n.phrase("Aus", "Off")))
	if can_turn() or _mode == Mode.ROBOTIC_ARM or (has_method("_is_hopper") and call("_is_hopper")):
		hints.append(i18n.phrase("R halten + Maus · Frei drehen", "Hold R + mouse · Rotate freely"))
	return "  ·  ".join(hints)

func status() -> Dictionary:
	var state := super.status()
	var note := control_hint()
	if not note.is_empty():
		state["aim_note"] = (str(state.get("aim_note", "")) + "\n" + note).strip_edges()
	return state

func _update_arm_ghost() -> void:
	super._update_arm_ghost()
	if _mp_yaw_locked and is_instance_valid(_arm_ghost):
		var forward := _aim_forward()
		_arm_ghost.global_rotation = Vector3(0.0, atan2(forward.x, forward.z), 0.0)
		_update_arm_feeds(_arm_ghost.global_position)
		_tint_arm_feeds(bool(_eval.get("ok", false)))

func _wall_point() -> Vector3:
	var native := super._wall_point()
	if snap_stopped():
		return native
	return BuildAlignment.wall_point(builds, _raw_surface_point(0.0), _square_wall(_surface_point(0.0)), native, _anchor if _state == State.RUNNING else Vector3.INF, _gridding())

func _roof_point() -> Vector3:
	var native := super._roof_point()
	if _state == State.RUNNING or snap_stopped():
		return native
	return BuildAlignment.roof_point(builds, player.eye_position(), player.look_direction(), _reach, native)

func _roof_heading(at: Vector3) -> Vector3:
	if not snap_stopped() and not _mp_yaw_locked:
		var aligned := BuildAlignment.roof_heading(builds, at, player.look_direction())
		if aligned.is_finite():
			return aligned
	return super._roof_heading(at)

func _roof_side(from: Vector3, to: Vector3) -> int:
	var native := super._roof_side(from, to)
	return native if snap_stopped() else BuildAlignment.roof_side(builds, from, to, native)

func _wall_primary() -> void:
	var had_color := builds.has_meta("mp_wall_color")
	var previous: Variant = builds.get_meta("mp_wall_color") if had_color else 0
	builds.set_meta("mp_wall_color", WallPalette.index(player.build_id))
	super._wall_primary()
	if had_color:
		builds.set_meta("mp_wall_color", previous)
	else:
		builds.remove_meta("mp_wall_color")

func _draw_custom_preview_flow(chains: Array, delta: float) -> void:
	if chains.is_empty():
		if is_instance_valid(_mp_preview_flow):
			_mp_preview_flow.hide()
		return
	if not is_instance_valid(_mp_preview_flow):
		_mp_preview_flow = MultiMeshInstance3D.new()
		_mp_preview_flow.name = "CustomPreviewFlow"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = ConveyorKit.flow_arrow_mesh()
		mm.instance_count = 256
		_mp_preview_flow.multimesh = mm
		_mp_preview_flow.material_override = ConveyorKit.flow_material()
		_mp_preview_flow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mp_preview_flow)
		_mp_preview_flow.top_level = true
		_mp_preview_flow.global_transform = Transform3D.IDENTITY
	_flow_phase = fmod(_flow_phase + maxf(0.0, delta) * ARROW_SPEED, 1024.0)
	_fill_flow(_mp_preview_flow.multimesh, chains, WYE_ARROW_PITCH, ARROW_LIFT, Color.WHITE)
	_mp_preview_flow.show()

func _draw_wye_hint() -> void:
	if is_instance_valid(_hint_wye) and _hint_wye.has_method("port_is_output"):
		var chains := _custom_router_chains(_hint_wye)
		_hint_flow.show()
		_fill_flow(_hint_flow.multimesh, chains, WYE_ARROW_PITCH, ARROW_LIFT, Color(1.0, 1.0, 1.0, _hint_level))
		return
	super._draw_wye_hint()

func _custom_router_chains(node: Node3D) -> Array:
	var chains := []
	for side in int(node.port_count):
		var tip: Vector3 = node.port(side)
		var outward := (tip - node.global_position).normalized()
		tip += outward * WYE_FLOW_REACH
		chains.append(PackedVector3Array([node.global_position, tip] if node.port_is_output(side) else [tip, node.global_position]))
	return chains
