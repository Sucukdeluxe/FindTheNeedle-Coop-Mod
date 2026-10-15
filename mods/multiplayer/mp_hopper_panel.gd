extends CanvasLayer

var service: Node
var _id := 0
var _root: Control
var _card: PanelContainer
var _title: Label
var _status: Label
var _amount: Label
var _enabled: Button
var _top := {}
var _portion: HSlider
var _upgrade: Button
var _timer := 0.0

func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_card = PlateKit.card(620.0)
	_root.add_child(_card)
	var whole := VBoxContainer.new()
	whole.add_theme_constant_override("separation", 0)
	_card.add_child(whole)
	_enabled = ArmPanel.PowerToggle.new()
	_enabled.pressed.connect(func():
		_enabled.set_running(not _enabled.running)
		_apply())
	_top = PlateKit.top(whole, service._tr("EINFÜLLTRICHTER", "LOADING HOPPER"), "*", close, _enabled)
	_title = _top.name
	_status = _top.line
	var photo: Control = _top.photo
	(photo.get_child(0) as TextureRect).texture = preload("res://mods/multiplayer/mp_icons.gd").building("mp_hopper")
	photo.show()
	_top.chip.hide()
	var rows := PlateKit.body(whole, 620.0)
	rows.add_child(PlateKit.heading(service._tr("SPEICHER UND AUSGABE", "STORAGE AND OUTPUT"), "tank"))
	rows.add_child(PlateKit.note(service._tr("Heu: links, hinten, rechts oder von oben einfüllen. Ausgabe: vorne. Rechtsklick leert Hand, Werkzeug oder Hofsauger.", "Feed hay from the left, rear, right or above. Output is at the front. Right-click empties your hand, tool or vacuum."), 570.0))
	_amount = _label(rows, "", 16)
	_portion = HSlider.new()
	_portion.min_value = 100
	_portion.step = 100
	PlateKit.slider(_portion)
	rows.add_child(_portion)
	_portion.value_changed.connect(_portion_changed)
	_upgrade = PlateKit.button("", "upgrade", _buy_upgrade)
	rows.add_child(_upgrade)
	rows.add_child(PlateKit.button(service._tr("Ausgabemenge übernehmen", "Apply output amount"), "flow", _apply))
	get_viewport().size_changed.connect(_fit)
	visible = false

func _label(rows: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	UiFont.style(label, size, ArmPanel.COL_INK, 0, false)
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
	_title.text = service._tr("EINFÜLLTRICHTER", "LOADING HOPPER")
	_enabled.set_running(not row.paused)
	_portion.max_value = int(Tech.call("belt_portion"))
	_portion.set_value_no_signal(mini(row.portion, int(_portion.max_value)))
	_portion_changed(_portion.value)
	visible = true
	service.world_sync.player.set_meta("mp_build_menu", self)
	service.world_sync.player.capture_mouse(false)
	_fit()
	_refresh()

func close() -> void:
	visible = false
	if is_instance_valid(service.world_sync.player):
		if service.world_sync.player.has_meta("mp_build_menu") and service.world_sync.player.get_meta("mp_build_menu") == self:
			service.world_sync.player.remove_meta("mp_build_menu")
		service.world_sync.player.capture_mouse(true)

func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	_card.size = Vector2(minf(620.0, size.x - 24.0), 0.0)
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
	_enabled.set_running(not row.paused)
	ArmPanel.write_state(_top.word, _top.sign, 2 if row.paused else 0)
	_top.word.text = service._tr("ANGEHALTEN", "PAUSED") if row.paused else service._tr("BEREIT", "READY")
	_status.text = "%s / %s" % [service._number(row.stored), service._number(service.Store.capacity(row))]
	_upgrade.disabled = row.level >= 9 or not service._pending.is_empty()
	_upgrade.text = service._tr("Kapazität vollständig ausgebaut", "Capacity fully upgraded") if row.level >= 9 else service._tr("Kapazität auf %s erhöhen · $%s", "Increase capacity to %s · $%s") % [service._number(service.Store.capacity(row) + 10000), service._number(service.Store.UPGRADE_COSTS[row.level])]

func _apply() -> void:
	service.request_configuration(_id, not _enabled.running, int(_portion.value))

func _buy_upgrade() -> void:
	if service._pending.is_empty():
		service.request_configuration(_id, not _enabled.button_pressed, int(_portion.value), true)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("free_mouse"):
		close()
		get_viewport().set_input_as_handled()
