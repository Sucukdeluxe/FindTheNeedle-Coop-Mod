extends "res://scripts/ui/t_junction_panel.gd"

var mp_economy: Node
var _request_id := 0
var _request_centre := Vector3.ZERO
var _completion := {}
var _completed_at := 0
var _shown := ""
var _was_active := true

func _active() -> bool:
	return is_instance_valid(mp_economy) and mp_economy.mp.active()

func _manual() -> bool:
	return not _pending.is_empty() or super._manual()

func _on_auto() -> void:
	if not _active():
		super._on_auto()
		return
	if _request_id != 0:
		return
	_pending.clear()
	_went_manual = false
	if _is_live(_t) and bool(_t.get("manual")):
		_request(false, [])
	else:
		_refusal = ""
		_refresh()

func _on_manual() -> void:
	if not _active():
		super._on_manual()
		return
	if _request_id == 0 and _is_live(_t) and not bool(_t.get("manual")):
		_request(true, ConveyorTSplitter.roles_of(_t))

func _apply(roles: Array[int]) -> void:
	if not _active():
		super._apply(roles)
		return
	if _request_id != 0 or not _is_live(_t):
		return
	_refusal = ""
	if ConveyorTSplitter.shape_of(roles) == "":
		_pending = roles.duplicate()
		_refresh()
		return
	_request(true, roles)

func _on_pick(id: String) -> void:
	if _request_id == 0:
		super._on_pick(id)

func _request(manual: bool, roles: Array[int]) -> void:
	var builds: Variant = _builds()
	if not is_instance_valid(builds) or not _is_live(_t):
		return
	_request_id = builds.request_t_configuration(_t, manual, roles)
	if _request_id != 0:
		_request_centre = _centre
		_completion.clear()
		_pending = roles.duplicate() if manual else []
		_refusal = mp_economy.mp.t("economy_wait")
	else:
		_refusal = mp_economy.mp.t("economy_wait")
	_refresh()

func accept_result(seq: int, result: Dictionary) -> void:
	if seq != _request_id:
		return
	_completion = result.duplicate(true)
	_completed_at = Time.get_ticks_msec()

func _process(delta: float) -> void:
	if not _active():
		if _was_active:
			reset_mp_request()
			_was_active = false
		super._process(delta)
		return
	_was_active = true
	if _request_id != 0:
		if not _completion.is_empty():
			var sync: Node = mp_economy.world_sync
			if sync._applying_builds:
				return
			var now: Node3D
			if _completion.get("ok", false):
				now = sync._find_building(_completion.get("target", {}))
				if now == null:
					now = sync.builds.t_at(_request_centre)
				if now == null or int(now.get_meta("mp_t_revision", 0)) < int(_completion.get("t_revision", 1)):
					if Time.get_ticks_msec() - _completed_at < 10000:
						return
					_completion["ok"] = false
					_completion["message"] = mp_economy.mp.t("economy_wait")
			_request_id = 0
			if _open and _centre.distance_squared_to(_request_centre) < 0.001:
				_pending.clear()
				_refusal = str(_completion.get("message", ""))
				if now != null:
					_swap_to(now)
				elif _completion.get("ok", false):
					_refusal = mp_economy.mp.t("building_missing")
			_completion.clear()
			_shown = ""
			_refresh()
		elif not mp_economy.pending.has(_request_id):
			reset_mp_request()
		if _request_id != 0 and not _is_live(_t):
			return
	super._process(delta)
	if _open and _is_live(_t):
		var state: Array = [_t.get_instance_id(), _t.manual]
		if _t is ConveyorTSplitter:
			state.append_array([_t.entry, _t.closed_lane, _t.forced_side, _t.priority_side])
		elif _t is ConveyorTJoiner:
			state.append(_t.out_lane)
		var signature := str(state)
		if signature != _shown:
			_shown = signature
			_refresh()

func _refresh() -> void:
	super._refresh()
	if not is_instance_valid(_auto_button):
		return
	var busy := _request_id != 0
	_auto_button.disabled = busy
	_manual_button.disabled = busy
	_fix_button.disabled = busy
	for roles in _role_buttons.values():
		for button in roles.values():
			button.disabled = busy
	for button in _pick_buttons.values():
		button.disabled = busy

func reset_mp_request() -> void:
	if _request_id == 0 and _completion.is_empty() and _pending.is_empty():
		return
	_request_id = 0
	_completion.clear()
	_pending.clear()
	_refusal = ""
	_shown = ""
	_refresh()
