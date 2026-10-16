extends Control

const Report = preload("res://mods/multiplayer/mp_needle_report.gd")
const SIZES := ["standard", "big", "huge", "mountain"]
var service: Node
var _card: PanelContainer
var _scroll: ScrollContainer
var _status: Label
var _summary: Label
var _preview_button: Button
var _confirm_button: Button
var _close_button: Button
var _choices: Array[Button] = []
var _selected := "standard"
var _token := ""
var _pending := false
var _clock := 0.0
signal closed

func setup(owner_service: Node) -> void:
	service = owner_service
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var wash := ColorRect.new()
	wash.color = Color(0.02, 0.025, 0.03, 0.88)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(wash)
	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.085, 0.09)
	style.border_color = Color(0.48, 0.43, 0.3)
	style.set_border_width_all(1)
	style.set_content_margin_all(18.0)
	_card.add_theme_stylebox_override("panel", style)
	add_child(_card)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card.add_child(_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	_scroll.add_child(column)
	_label(column, _t("PRESTIGE · NEUER HEUHAUFEN", "PRESTIGE · NEW HAYSTACK"), 22)
	_status = _label(column, "", 16)
	_label(column, _t("Werkzeuge, Freischaltungen, gekaufte Upgrades und bisherige Entdeckungen bleiben erhalten. Gebäude und übrige Verkaufsgüter werden abgerechnet. Die neue Karte startet ohne Gebäude; die sechs Nadelarten müssen dort erneut gesammelt werden.", "Tools, unlocks, purchased upgrades and existing discoveries are retained. Buildings and remaining saleable goods are sold. The new map starts without buildings; collect its six needle types again."), 15)
	_label(column, _t("Größe des neuen Heuhaufens", "New haystack size"), 16)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	var titles := [_t("Standard", "Standard"), _t("Groß", "Large"), _t("Riesig", "Huge"), _t("Der Berg", "Mountain")]
	for index in SIZES.size():
		var button := _button(grid, titles[index], _select.bind(SIZES[index]))
		button.toggle_mode = true
		_choices.append(button)
	_preview_button = _button(column, _t("Abrechnung prüfen", "Preview sale"), _preview)
	_summary = _label(column, "", 15)
	_confirm_button = _button(column, _t("Verkaufen und neue Karte starten", "Sell and start new map"), _confirm)
	_confirm_button.disabled = true
	_close_button = _button(column, _t("Zurück", "Back"), close)
	if is_instance_valid(service) and service.has_signal("finished"):
		service.finished.connect(_finished)
	_select(_selected)
	_fit()
	get_viewport().size_changed.connect(_fit)
	_refresh()

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _fit() -> void:
	if not is_instance_valid(_card):
		return
	var viewport := get_viewport_rect().size
	var target := Vector2(minf(620.0, maxf(280.0, viewport.x - 32.0)), minf(720.0, maxf(180.0, viewport.y - 32.0)))
	_card.size = target
	_card.position = (viewport - target) * 0.5
	_scroll.custom_minimum_size = target - Vector2(36.0, 36.0)

func _select(size_id: String) -> void:
	if _pending:
		return
	_selected = size_id
	_token = ""
	_summary.text = ""
	_confirm_button.disabled = true
	for index in _choices.size():
		_choices[index].set_pressed_no_signal(SIZES[index] == size_id)

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= 1.0:
		_clock = 0.0
		_refresh()

func _refresh() -> void:
	if not is_instance_valid(service):
		_status.text = _t("Kartenverwaltung nicht verfügbar.", "Map management unavailable.")
		_preview_button.disabled = true
		_confirm_button.disabled = true
		return
	var state: Dictionary = service.status()
	var remaining := Report.number(int(ceil(maxf(0.0, float(state.get("remaining", 0.0))))), "." if _de() else ",")
	_status.text = _t("Heu im Haufen: %s · Nadelarten: %d / %d", "Hay in stack: %s · Needle types: %d / %d") % [remaining, int(state.get("found", 0)), int(state.get("total", 6))]
	if not str(state.get("reason", "")).is_empty():
		_status.text += "\n" + str(state.reason)
	_preview_button.disabled = _pending or not bool(state.get("allowed", false))
	_confirm_button.disabled = _pending or _token.is_empty() or not bool(state.get("allowed", false))
	for button in _choices:
		button.disabled = _pending
	_close_button.disabled = _pending

func _preview() -> void:
	if _pending or not is_instance_valid(service):
		return
	var quote: Dictionary = service.preview(_selected)
	_token = str(quote.get("token", "")) if bool(quote.get("ok", false)) else ""
	if _token.is_empty():
		_summary.text = str(quote.get("reason", _t("Abrechnung derzeit nicht möglich.", "Sale preview currently unavailable.")))
	else:
		var separator := "." if _de() else ","
		_summary.text = _t("%s Gebäude: $%s\nVerkaufsgüter: $%s\nAuszahlung mindestens: $%s\nVerbliebenes Heu in Spielersaugern wird zusätzlich abgerechnet. Vor dem Wechsel wird eine Sicherung erstellt.", "%s buildings: $%s\nSaleable goods: $%s\nMinimum payout: $%s\nHay remaining in player vacuums is sold additionally. A backup is created before changing maps.") % [Report.number(int(quote.get("buildings", 0)), separator), _money(float(quote.get("building_value", 0.0))), _money(float(quote.get("goods_value", 0.0))), _money(float(quote.get("payout", 0.0)))]
	_refresh()

func _confirm() -> void:
	if _pending or _token.is_empty() or not is_instance_valid(service):
		return
	_pending = true
	_refresh()
	if not bool(service.confirm(_token)):
		_pending = false
		_token = ""
		_summary.text = _t("Der Zustand hat sich geändert. Abrechnung erneut prüfen.", "The state has changed. Preview the sale again.")
		_refresh()

func _finished(ok: bool, message: String) -> void:
	_pending = false
	_token = ""
	_summary.text = message
	_refresh()
	if ok:
		close()

func close() -> void:
	if _pending:
		return
	closed.emit()
	queue_free()

func _money(value: float) -> String:
	var cents := int(round(maxf(0.0, value) * 100.0))
	return Report.number(cents / 100, "." if _de() else ",") + ("," if _de() else ".") + "%02d" % (cents % 100)

func _de() -> bool:
	return TranslationServer.get_locale().begins_with("de")

func _t(german: String, english: String) -> String:
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase(german, english)
