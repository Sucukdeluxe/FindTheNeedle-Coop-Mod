extends "res://scripts/ui/load_panel.gd"

const NeedleReport = preload("res://mods/multiplayer/mp_needle_report.gd")
var mp_economy: Node
var _mp_needle_refresh := 0.0

func _refresh_needles() -> bool:
	var ready := super._refresh_needles()
	var report := NeedleReport.counts(GameState.needle_taken, GameState.needle_type, NeedleTypes.count())
	_write(_needles_line, _needles_line.text + "\n" + NeedleReport.line(report, TranslationServer.get_locale()))
	return ready

func _process(delta: float) -> void:
	super._process(delta)
	if not _open:
		_mp_needle_refresh = 0.0
		return
	_mp_needle_refresh -= delta
	if _mp_needle_refresh <= 0.0:
		_mp_needle_refresh = 1.0
		_refresh_needles()
