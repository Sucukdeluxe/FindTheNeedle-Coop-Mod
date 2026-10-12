extends "res://scripts/ui/wire_mode.gd"

var mp_power: Node
var _power_request := 0
var _power_generation := 0
var _power_pending_generation := 0
var _power_span_cut := false
var _power_from: PowerPole
var _power_to: PowerPole

func begin(pole: PowerPole) -> void:
	if is_instance_valid(pole) and _builds() != null:
		_power_generation += 1
		_power_request = 0
	super.begin(pole)

func end() -> void:
	_power_generation += 1
	_power_request = 0
	super.end()

func click() -> void:
	if not is_instance_valid(mp_power) or not mp_power.mp.active() or mp_power.applying:
		super.click()
		return
	if _power_request != 0:
		return
	if _builds() == null or not is_instance_valid(_from):
		super.click()
		return
	var span_cut := not _span.is_empty()
	if not span_cut and _answer not in [BuildManager.Wire.JOIN, BuildManager.Wire.CUT]:
		super.click()
		return
	var source: PowerPole = _from
	var target: PowerPole = _hover
	if span_cut:
		if _span.size() < 2:
			return
		source = _span[0] as PowerPole
		target = _span[1] as PowerPole
	_power_pending_generation = _power_generation
	_power_span_cut = span_cut
	_power_from = source
	_power_to = target
	_power_request = mp_power.request_wire(source, target, not span_cut and _answer == BuildManager.Wire.JOIN)

func _power_completed(seq: int, result: Dictionary) -> void:
	if _power_request == 0 or seq != _power_request:
		return
	_power_request = 0
	if not _active or _power_pending_generation != _power_generation or not result.get("ok", false):
		return
	var lines := maxi(0, int(result.get("lines", 0)))
	if bool(result.get("joined", false)):
		Audio.play("build_place_metal")
		_toast(tr_n("Joined. Your yard has %d power line now.", "Joined. Your yard has %d power lines now.", lines) % lines)
		end()
		return
	Audio.play("build_dismantle")
	if bool(result.get("still_connected", false)):
		_toast(tr("Cut. Power still gets there another way."))
	else:
		_toast(tr_n("Cut. Your yard has %d power line now.", "Cut. Your yard has %d power lines now.", lines) % lines)
	if not _power_span_cut:
		end()
		return
	if _span.size() >= 2 and ((_span[0] == _power_from and _span[1] == _power_to) or (_span[1] == _power_from and _span[0] == _power_to)):
		_span = []
		_span_key = ""
		_span_mesh.visible = false
	_tag_clock = 0.0
	_tint_lines(true)
