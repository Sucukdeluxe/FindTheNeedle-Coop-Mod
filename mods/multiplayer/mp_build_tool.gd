extends "res://scripts/build/build_tool.gd"

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

func set_mode(mode: Mode) -> void:
	input_revision += 1
	super.set_mode(mode)

func set_active(on: bool) -> void:
	if not on:
		input_revision += 1
	super.set_active(on)

func cancel() -> void:
	input_revision += 1
	super.cancel()

func primary() -> void:
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		super.primary()
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
		_request("demolish", {"target": target.to_dict(), "one": one})

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
		_request("reverse", {"target": target.to_dict()})

func _pay(amount: float) -> bool:
	if not is_finite(amount) or amount < 0.0 or amount > price_limit + 0.001:
		return false
	return super._pay(amount)

func capture_inputs() -> Dictionary:
	var out := {}
	for key in INPUT_FIELDS:
		out[key] = get(key)
	return out.duplicate(true)

func _request(action: String, args: Dictionary) -> void:
	if request_id != 0:
		return
	args["build_id"] = player.build_id
	args["inputs"] = capture_inputs()
	args["body"] = player.global_transform
	args["camera"] = player.camera.global_transform
	sent_revision = input_revision
	request_id = mp_economy.request(action, args)

func accept_result(seq: int, result: Dictionary) -> void:
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
	match action:
		"place":
			super.primary()
		"demolish":
			super.dismantle(target, bool(args.get("one", false)))
		"demolish_tile":
			super.dismantle_tile(target as Platform, args.get("tile", Rect2()))
		"reverse":
			super.reverse(target)
