extends "res://scripts/build/build_tool.gd"

const BuildCamera = preload("res://mods/multiplayer/mp_build_camera.gd")
const BuildSnapshot = preload("res://mods/multiplayer/mp_build_snapshot.gd")


const INPUT_FIELDS := ["_state", "_anchor", "_anchor_dir", "_anchor_side", "_anchor_span",
	"_upstream", "_stair_outward", "_ghost_turn", "_roof_turn", "_t_turn", "_grid_on",
	"_snap_off", "_work_height", "_work_base", "_reach", "pipe_shape", "_fit_roll",
	"_tee_stop", "_tee_stop_at", "_finished_at", "_route", "_route_pinned",
	"_turned_since_place", "_copied_since_place"]
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

func _exit_tree() -> void:
	_drop_taps()

func set_mode(mode: Mode) -> void:
	_cancel_remote()
	input_revision += 1
	super.set_mode(mode)

func set_active(on: bool) -> void:
	if not on:
		_cancel_remote()
		input_revision += 1
	super.set_active(on)

func cancel() -> void:
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
			_eval["reason"] = "Außerhalb des Baubereichs von 24 m." if TranslationServer.get_locale().begins_with("de") else "Outside the 24 m building area."

func dismantle_reach() -> float:
	var ray := _camera_ray()
	return float(ray.length) if not ray.is_empty() else super.dismantle_reach()
