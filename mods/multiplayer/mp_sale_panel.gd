extends CanvasLayer

var service: Node
var _id := 0
var _card: PanelContainer
var _title: Label
var _status: Label
var _move: Button
var _remove: Button

func _ready() -> void:
	layer = 22
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_card = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.055, 0.06, 0.98)
	style.border_color = Color(0.5, 0.5, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(18.0)
	_card.add_theme_stylebox_override("panel", style)
	root.add_child(_card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	_card.add_child(rows)
	_title = _label(rows, 21)
	_status = _label(rows, 16)
	_move = _button(rows, service._tr("Versetzen", "Move"), _begin_move)
	_remove = _button(rows, service._tr("Abbauen · $250 zurück", "Dismantle · $250 refund"), _dismantle)
	_button(rows, service._tr("Schließen", "Close"), close)
	get_viewport().size_changed.connect(_fit)
	visible = false

func _label(parent: Node, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func open(id: int) -> void:
	_id = id
	_title.text = service._tr("Verkaufsstand", "Selling Stand") if id == 1 else service._tr("Verkaufswaage", "Sale Scale")
	_remove.visible = id != 1
	visible = true
	service.world_sync.player.set_meta("mp_build_menu", self)
	service.world_sync.player.capture_mouse(false)
	_fit()
	_refresh()

func close() -> void:
	visible = false
	if is_instance_valid(service.world_sync.player):
		if service.world_sync.player.get_meta("mp_build_menu", null) == self:
			service.world_sync.player.remove_meta("mp_build_menu")
		service.world_sync.player.capture_mouse(true)

func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	_card.size = Vector2(minf(480.0, size.x - 24.0), 280.0)
	_card.position = (size - _card.size) * 0.5

func _process(_delta: float) -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	var station: Node = service.model(_id)
	if not is_instance_valid(station):
		close()
		return
	var can_move: bool = station.mp_can_move()
	_status.text = service._tr("Leer · Versetzen möglich", "Empty · ready to move") if can_move else service._tr("Heu oder Auszahlung wird verarbeitet", "Processing hay or payout")
	_move.disabled = not can_move or not service._pending.is_empty()
	_remove.disabled = _move.disabled

func _begin_move() -> void:
	service.begin_move(_id)

func _dismantle() -> void:
	service.request_remove(_id)

func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("free_mouse") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()
