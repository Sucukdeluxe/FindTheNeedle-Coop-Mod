extends "res://scripts/ui/pole_panel.gd"

var mp_power: Node
var _line_request := 0

func _remote() -> bool:
	return is_instance_valid(mp_power) and mp_power.mp.active() and not mp_power.applying

func _on_switch() -> void:
	if not _remote():
		super._on_switch()
		return
	var grid := _grid()
	if grid == null or not is_instance_valid(_pole) or mp_power.switch_pending(_pole):
		return
	_line_request = mp_power.request_switch(_pole, grid.line_running(_pole), true)
	_refresh()

func _on_pole_switch() -> void:
	if not _remote():
		super._on_pole_switch()
		return
	var grid := _grid()
	if grid == null or not is_instance_valid(_pole) or mp_power.switch_pending(_pole):
		return
	mp_power.request_switch(_pole, grid.pole_running(_pole), false)
	_refresh()

func _power_completed(sequence: int, result: Dictionary) -> void:
	if sequence == _line_request:
		_line_request = 0
		if result.get("ok", false) and int(result.get("switched", 0)) > 0:
			if result.get("off", false):
				line_offs += 1
			else:
				line_ons += 1
	_refresh()

func _refresh() -> void:
	super._refresh()
	if is_instance_valid(mp_power) and is_instance_valid(_pole) and mp_power.switch_pending(_pole):
		_switch.set_dead(true)
		_pole_switch.set_dead(true)
		if is_instance_valid(mp_power.device_panel):
			_readout.text += "\n" + mp_power.device_panel.word("pending")
