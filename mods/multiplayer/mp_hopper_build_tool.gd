extends "res://mods/multiplayer/mp_build_tool.gd"

const RouterCatalog = preload("res://mods/multiplayer/mp_router_catalog.gd")
const HOPPER_ID := "mp_hopper"
const SALE_IDS := ["mp_sale_scale", "mp_sale_move"]
var _hopper_wreck := 0
var _hopper_wreck_time := 0.0

func _hoppers() -> Node:
	if is_instance_valid(mp_economy) and is_instance_valid(mp_economy.world_sync):
		return mp_economy.world_sync.get("hoppers_sync")
	return null

func _is_hopper() -> bool:
	return is_instance_valid(player) and (player.build_id == HOPPER_ID or player.build_id in RouterCatalog.ids() or player.build_id in SALE_IDS)

func _service() -> Node:
	var hoppers := _hoppers()
	if not is_instance_valid(hoppers):
		return null
	if player.build_id in SALE_IDS:
		return hoppers.get("sale_stations")
	return hoppers.receivers if player.build_id in RouterCatalog.ids() else hoppers

func _sync_ghosts() -> void:
	var active := _active
	if _is_hopper():
		_active = false
	super._sync_ghosts()
	_active = active
	var hoppers := _service()
	var base := _hoppers()
	if is_instance_valid(base):
		for service in [base, base.receivers, base.get("sale_stations")]:
			if is_instance_valid(service) and service != hoppers:
				service.preview(player.camera.global_transform, _reach, false)
	if is_instance_valid(hoppers) and is_instance_valid(player) and is_instance_valid(player.camera):
		hoppers.preview(player.camera.global_transform, _reach, active and _is_hopper())

func _process(delta: float) -> void:
	if not _is_hopper() or not _active:
		super._process(delta)
		return
	_tick_dismantle(delta)
	var hoppers := _service()
	if is_instance_valid(hoppers):
		hoppers.preview(player.camera.global_transform, _reach, player.is_mouse_captured() and not player.menu_is_up())

func primary() -> void:
	if not _is_hopper():
		super.primary()
		return
	var hoppers := _service()
	if not _active or request_id != 0 or not is_instance_valid(hoppers):
		return
	request_id = hoppers.request_place(player.camera.global_transform, player.global_transform, _reach)

func status() -> Dictionary:
	if not _is_hopper():
		return super.status()
	var hoppers := _service()
	var evaluated := {"ok": false, "reason": ""}
	if is_instance_valid(hoppers):
		evaluated = hoppers.build_candidate(player.camera.global_transform, _reach)
	return {"kind": "mp_hopper", "placing": false, "ok": evaluated.get("ok", false),
		"reason": evaluated.get("reason", ""), "length": 0.0, "cost": float(evaluated.get("cost", RouterCatalog.build_cost(RouterCatalog.count_for(player.build_id)) if player.build_id in RouterCatalog.ids() else (0.0 if player.build_id == "mp_sale_move" else 2500.0))), "reach": _reach, "aim_note": control_hint()}

func _begin_dismantle(loud := true) -> void:
	var hoppers := _hoppers()
	var target := 0
	if is_instance_valid(hoppers):
		target = hoppers.target_id(true)
	if target == 0 or not _hold_whole:
		_hopper_wreck = 0
		super._begin_dismantle(loud)
		return
	_hopper_wreck = target
	_hopper_wreck_time = 0.0
	_wreck = null
	_wreck_chain = false

func _tick_dismantle(delta: float) -> void:
	if _hopper_wreck == 0:
		super._tick_dismantle(delta)
		return
	var hoppers := _hoppers()
	if not Input.is_action_pressed(_hold_action) or not is_instance_valid(hoppers) 			or hoppers.target_id(true) != _hopper_wreck:
		_hopper_wreck = 0
		_hopper_wreck_time = 0.0
		return
	_hopper_wreck_time += delta
	if _hopper_wreck_time >= DISMANTLE_HOLD:
		hoppers.request_remove(_hopper_wreck)
		_hopper_wreck = 0
		_hopper_wreck_time = 0.0

func dismantle_progress() -> float:
	if _hopper_wreck != 0:
		return clampf(_hopper_wreck_time / DISMANTLE_HOLD, 0.0, 1.0)
	return super.dismantle_progress()

func dismantle_name() -> String:
	if _hopper_wreck != 0:
		return "Einfülltrichter" if TranslationServer.get_locale().begins_with("de") else "Loading Hopper"
	return super.dismantle_name()

func _rotation_available() -> bool:
	if not _is_hopper():
		return super._rotation_available()
	var service := _service()
	return _active and is_instance_valid(player) and player.is_mouse_captured() and not player.menu_is_up() and is_instance_valid(service) and service.has_method("set_build_yaw")

func _begin_free_rotation() -> void:
	if not _is_hopper():
		super._begin_free_rotation()
		return
	_mp_yaw = float(_service().build_yaw())

func _rotate_free(amount: float) -> void:
	if not _is_hopper():
		super._rotate_free(amount)
		return
	if not is_finite(amount):
		return
	_mp_yaw = wrapf(_mp_yaw + clampf(amount, -TAU, TAU), -PI, PI)
	_service().set_build_yaw(_mp_yaw)
	_turned_since_place = true
	input_revision += 1

func _step_rotation() -> void:
	if not _is_hopper():
		super._step_rotation()
		return
	_service().step_build_rotation()
	_turned_since_place = true
	input_revision += 1

func cancel() -> void:
	var base := _hoppers()
	if is_instance_valid(base):
		var sale: Variant = base.get("sale_stations")
		if is_instance_valid(sale):
			sale.cancel_preview()
	super.cancel()

func can_toggle_flow() -> bool:
	return not _is_hopper() and super.can_toggle_flow()

func flow_hint() -> String:
	return "" if _is_hopper() else super.flow_hint()
