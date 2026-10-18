extends "res://scripts/ui/load_panel.gd"

const NeedleReport = preload("res://mods/multiplayer/mp_needle_report.gd")
const PrestigeState = preload("res://mods/multiplayer/mp_prestige_state.gd")
const PrestigePanel = preload("res://mods/multiplayer/mp_prestige_panel.gd")
var mp_economy: Node
var _mp_needle_refresh := 0.0
var _mp_report: Label
var _mp_prestige: Button
var _mp_dialog: Control
var _mp_scroll: ScrollContainer
var _mp_card: Control

func press_order(pay_now: bool = false) -> void:
	if not is_instance_valid(mp_economy):
		super.press_order(pay_now)
		return
	if mp_economy.request("order_pile", {"pay_now": pay_now, "pile_seed": GameState.run_seed}) > 0:
		set_open(false)

func _mp_setup() -> void:
	if is_instance_valid(_mp_report) or not is_instance_valid(_needles_line):
		return
	var column := _needles_line.get_parent()
	_mp_report = _line(H_NOTE, COL_INK, false, true)
	_mp_report.name = "RemainingNeedles"
	column.add_child(_mp_report)
	column.move_child(_mp_report, _needles_line.get_index() + 1)
	_mp_prestige = _button("PrestigeButton", _mp_open_prestige)
	_mp_prestige.text = "Prestige · Neue Karte" if TranslationServer.get_locale().begins_with("de") else "Prestige · New map"
	_style_button(_mp_prestige, true)
	column.add_child(_mp_prestige)
	column.move_child(_mp_prestige, 1)
	_mp_card = column.get_parent()
	var centre := _mp_card.get_parent()
	_mp_scroll = ScrollContainer.new()
	_mp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	centre.remove_child(_mp_card)
	centre.add_child(_mp_scroll)
	_mp_scroll.add_child(_mp_card)
	_mp_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_fit()
	get_viewport().size_changed.connect(_mp_fit)

func _mp_fit() -> void:
	if not is_instance_valid(_mp_scroll):
		return
	var available := get_viewport_rect().size - Vector2(32.0, 32.0)
	var width := minf(CARD_W, maxf(250.0, available.x))
	_mp_card.custom_minimum_size.x = width - 14.0
	for child in _mp_report.get_parent().get_children():
		if child is Label:
			child.custom_minimum_size.x = 0.0
	_mp_scroll.custom_minimum_size = Vector2(width, maxf(180.0, minf(780.0, available.y)))

func _mp_open_prestige() -> void:
	if is_instance_valid(_mp_dialog) or not is_instance_valid(mp_economy):
		return
	var service: Node = mp_economy.world_sync.get("prestige")
	if not is_instance_valid(service):
		_say("Kartenverwaltung wird vorbereitet." if TranslationServer.get_locale().begins_with("de") else "Preparing map management.")
		return
	_mp_dialog = PrestigePanel.new()
	add_child(_mp_dialog)
	_mp_dialog.setup(service)

func _input(event: InputEvent) -> void:
	if is_instance_valid(_mp_dialog):
		if event.is_action_pressed("free_mouse"):
			_mp_dialog.close()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact"):
			get_viewport().set_input_as_handled()
		return
	super._input(event)

func _refresh_needles() -> bool:
	_mp_setup()
	var ready := super._refresh_needles()
	var report := NeedleReport.counts(GameState.needle_taken, GameState.needle_type, NeedleTypes.count())
	if is_instance_valid(_mp_report):
		var message := NeedleReport.line(report, TranslationServer.get_locale())
		if int(GameState.mp_prestige.get("cycles", 0)) > 0:
			message += "\n" + PrestigeState.current_progress(GameState, NeedleTypes.pool(Cfg.DEMO_LAST_LOT), TranslationServer.get_locale())
		_write(_mp_report, message)
	if is_instance_valid(_mp_prestige):
		var progress := PrestigeState.normalize(GameState.mp_prestige, GameState.run_seed)
		var found := PrestigeState.found_count(progress, GameState.discovered, NeedleTypes.pool(Cfg.DEMO_LAST_LOT), GameState.run_seed)
		_mp_prestige.text = ("Prestige · Neue Karte" if TranslationServer.get_locale().begins_with("de") else "Prestige · New map") + " · %d / 6" % found
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
