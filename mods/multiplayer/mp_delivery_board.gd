extends "res://scripts/world/delivery_board.gd"

const NeedleReport = preload("res://mods/multiplayer/mp_needle_report.gd")
var mp_economy: Node

func _refresh_note() -> void:
	super._refresh_note()
	if not is_instance_valid(_note):
		return
	var german := TranslationServer.get_locale().begins_with("de")
	var report := NeedleReport.counts(GameState.needle_taken, GameState.needle_type, NeedleTypes.count())
	_write(_note_detail, NeedleReport.line(report, TranslationServer.get_locale()))
	_write(_note_foot, ("%s · Nächste Ladung / Prestige" if german else "%s · Next load / Prestige") % InputSetup.hint("interact"))
