extends "res://scripts/ui/options_panel.gd"

var mp_economy: Node
var _mp_sweep_request := 0
var _mp_sweep_token := ""
var _mp_sweep_done := ""
var _mp_sweep_scope := ""

func _on_sweep_pressed() -> void:
	var service := preload("res://mods/multiplayer/mp_sweep.gd").find_service(self)
	if not is_instance_valid(service):
		if preload("res://mods/multiplayer/mp_sweep.gd").native_allowed(self):
			super._on_sweep_pressed()
		else:
			_disarm_sweep()
			_say_sweep(_mp_text("Aufräumen wird noch vorbereitet.", "Cleanup is still being prepared."), COL_WARN)
		return
	mp_economy = service.world_sync.economy
	var scope := str(service.get_instance_id()) + ":" + str(mp_economy.epoch) + ":" + str(service.request_args().pile_seed)
	if scope != _mp_sweep_scope:
		_mp_sweep_scope = scope
		_mp_sweep_request = 0
		_mp_sweep_token = ""
		_mp_sweep_done = ""
		_disarm_sweep()
	if _mp_sweep_request > 0 or service.busy() or service.world_sync._frozen:
		_say_sweep(_mp_text("Aufräumen oder Weltwechsel läuft bereits. Bitte warten.", "Cleanup or a world transition is already in progress. Please wait."), COL_WARN)
		return
	if not _sweep_armed:
		super._on_sweep_pressed()
		return
	if not mp_economy.completed.is_connected(_mp_sweep_result):
		mp_economy.completed.connect(_mp_sweep_result)
	if not service.finished.is_connected(_mp_sweep_finished):
		service.finished.connect(_mp_sweep_finished)
	_mp_sweep_done = ""
	var args: Dictionary = service.request_args()
	_mp_sweep_token = service.request_token(args)
	_mp_sweep_request = mp_economy.request("sweep_floor", args)
	_disarm_sweep()
	if _mp_sweep_request > 0:
		_sweep_button.disabled = true
		_say_sweep(_mp_text("Heu wird gemeinsam zurückgelegt …", "Returning loose hay for all players …"), COL_DIM)
	else:
		_say_sweep(_mp_text("Aufräumen derzeit nicht möglich. Bitte warten.", "Cleanup is currently unavailable. Please wait."), COL_WARN)

func _mp_sweep_result(seq: int, result: Dictionary) -> void:
	if seq != _mp_sweep_request:
		return
	_mp_sweep_request = 0
	if not result.get("ok", false):
		_disarm_sweep()
		_say_sweep(str(result.get("message", _mp_text("Aufräumen fehlgeschlagen.", "Cleanup failed."))), COL_WARN)
		return
	_mp_sweep_token = str(result.get("token", ""))
	if _mp_sweep_done == _mp_sweep_token:
		return
	if not result.get("pending", false):
		_mp_sweep_finished(_mp_sweep_token, result)

func _mp_sweep_finished(token: String, result: Dictionary) -> void:
	if _mp_sweep_token == "" or token != _mp_sweep_token:
		return
	if result.get("pending", false):
		_sweep_button.disabled = true
		_say_sweep(_mp_text("Warte auf die Bestätigung eines Mitspielers. Verbindung prüfen; vor Abschluss bleibt der Weltwechsel gesperrt.", "Waiting for a player to confirm. Check the connection; world changes remain locked until cleanup completes."), COL_WARN)
		return
	_mp_sweep_done = token
	_disarm_sweep()
	if result.get("incomplete", false):
		_say_sweep(_mp_text("Bestätigtes Heu wurde zurückgelegt. Ein Mitspieler konnte nicht vollständig erreicht werden.", "Confirmed hay was returned. One player could not be fully reached."), COL_WARN)
	else:
		var things := int(result.get("things", 0))
		var straws := int(result.get("straws", 0))
		if things == 0 and straws == 0:
			_say_sweep(tr("Nothing was lying around. The floor is already clear."), COL_DIM)
			Audio.play("ui_back", -6.0)
		else:
			_say_sweep(_mp_text("%s Gegenstände und %s Halme zurückgelegt.", "Returned %s things and %s strands.") % [_mp_number(things), _mp_number(straws)], COL_ACCENT)
			Audio.play("ui_drop", -2.0)
	if is_instance_valid(_yard_note):
		_yard_note.text = _yard_verdict()

func _mp_text(de: String, en: String) -> String:
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase(de, en)

func _mp_number(value: int) -> String:
	var text := str(value)
	var separator := "." if TranslationServer.get_locale().begins_with("de") else ","
	var at := text.length() - 3
	while at > 0:
		text = text.insert(at, separator)
		at -= 3
	return text
