extends CanvasLayer

var service: Node
var _id := 0
var _root: Control
var _card: PanelContainer
var _title: Label
var _status: Label
var _amount: Label
var _enabled: CheckButton
var _portion: HSlider
var _upgrade: Button
var _timer := 0.0

func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.06, 0.98)
	style.border_color = Color(0.64, 0.53, 0.29)
	style.set_border_width_all(1)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_card.add_theme_stylebox_override("panel", style)
	_root.add_child(_card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	_card.add_child(rows)
	_title = _label(rows, "", 22)
	_status = _label(rows, "", 16)
	_enabled = CheckButton.new()
	_enabled.text = service._tr("Ausgabe eingeschaltet", "Output enabled")
	_enabled.add_theme_font_size_override("font_size", 17)
	rows.add_child(_enabled)
	_amount = _label(rows, "", 16)
	_portion = HSlider.new()
	_portion.min_value = 100
	_portion.step = 100
	_portion.custom_minimum_size.y = 30
	rows.add_child(_portion)
	_portion.value_changed.connect(_portion_changed)
	_upgrade = _button(rows, "", _buy_upgrade)
	_button(rows, service._tr("Einstellungen übernehmen", "Apply settings"), _apply)
	_button(rows, service._tr("Schließen", "Close"), close)
	get_viewport().size_changed.connect(_fit)
	visible = false

func _label(rows: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	rows.add_child(label)
	return label

func _button(rows: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	rows.add_child(button)
	return button

func open(id: int) -> void:
	var row: Dictionary = service._row(id)
	if row.is_empty():
		return
	_id = id
	_title.text = service._tr("Einfülltrichter", "Loading Hopper")
	_enabled.set_pressed_no_signal(not row.paused)
	_portion.max_value = int(Tech.call("belt_portion"))
	_portion.set_value_no_signal(mini(row.portion, int(_portion.max_value)))
	_portion_changed(_portion.value)
	visible = true
	service.world_sync.player.capture_mouse(false)
	_fit()
	_refresh()

func close() -> void:
	visible = false
	if is_instance_valid(service.world_sync.player):
		service.world_sync.player.capture_mouse(true)

func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	_card.size = Vector2(minf(500.0, size.x - 24.0), 360.0)
	_card.position = (size - _card.size) * 0.5

func _portion_changed(value: float) -> void:
	_amount.text = service._tr("Ausgabe: %s Halme je Portion", "Output: %s strands per portion") % service._number(int(value))

func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.2
		_refresh()

func _refresh() -> void:
	var row: Dictionary = service._row(_id)
	if row.is_empty():
		close()
		return
	_status.text = "%s / %s" % [service._number(row.stored), service._number(service.Store.capacity(row))]
	_upgrade.disabled = row.level >= 9 or not service._pending.is_empty()
	_upgrade.text = service._tr("Kapazität vollständig ausgebaut", "Capacity fully upgraded") if row.level >= 9 else service._tr("Kapazität auf %s erhöhen · $%s", "Increase capacity to %s · $%s") % [service._number(service.Store.capacity(row) + 10000), service._number(service.Store.UPGRADE_COSTS[row.level])]

func _apply() -> void:
	service.request_configuration(_id, not _enabled.button_pressed, int(_portion.value))

func _buy_upgrade() -> void:
	if service._pending.is_empty():
		service.request_configuration(_id, not _enabled.button_pressed, int(_portion.value), true)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("free_mouse"):
		close()
		get_viewport().set_input_as_handled()
