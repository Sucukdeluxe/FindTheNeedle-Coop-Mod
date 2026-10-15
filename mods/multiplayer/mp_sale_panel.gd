extends CanvasLayer

var service: Node
var _id := 0
var _card: PanelContainer
var _title: Label
var _status: Label
var _move: Button
var _remove: Button
var _feeder: Button
var _top := {}

func _ready() -> void:
	layer = 22
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_card = PlateKit.card(620.0)
	root.add_child(_card)
	var whole := VBoxContainer.new()
	whole.add_theme_constant_override("separation", 0)
	_card.add_child(whole)
	_feeder = ArmPanel.PowerToggle.new()
	_feeder.pressed.connect(func():service.request_feed_belt(_id, not _feeder.running))
	_top = PlateKit.top(whole, service._tr("VERKAUFSSTELLE", "SALE STATION"), "*", close, _feeder)
	_title = _top.name
	_status = _top.line
	_top.chip.hide()
	var photo: Control = _top.photo
	(photo.get_child(0) as TextureRect).texture = preload("res://mods/multiplayer/mp_icons.gd").building("mp_sale_scale")
	photo.show()
	var rows := PlateKit.body(whole, 620.0)
	rows.add_child(PlateKit.note(service._tr("Schalter: Zuführband anzeigen. Versetzen und Abbauen sind nur bei vollständig leerer Waage möglich. X halten baut zusätzliche Waagen direkt ab.", "Switch: show the feed conveyor. Moving and dismantling require an empty scale. Hold X to dismantle extra scales directly."), 570.0))
	_move = PlateKit.button(service._tr("Versetzen", "Move"), "route", _begin_move)
	rows.add_child(_move)
	_remove = PlateKit.button(service._tr("Abbauen · $250 zurück", "Dismantle · $250 refund"), "drop", _dismantle)
	rows.add_child(_remove)
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
	_feeder.visible = id != 1
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
	_card.size = Vector2(minf(620.0, size.x - 24.0), 0.0)
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
	ArmPanel.write_state(_top.word, _top.sign, 0 if can_move else 1)
	_top.word.text = service._tr("LEER", "EMPTY") if can_move else service._tr("VERARBEITET", "PROCESSING")
	_status.text = service._tr("Leer · Versetzen möglich", "Empty · ready to move") if can_move else service._tr("Heu oder Auszahlung wird verarbeitet", "Processing hay or payout")
	_move.disabled = not can_move or not service._pending.is_empty()
	_remove.disabled = _move.disabled
	_feeder.disabled = _move.disabled
	_feeder.set_running(bool(service._row(_id).get("feed_belt", true)))

func _begin_move() -> void:
	service.begin_move(_id)

func _dismantle() -> void:
	service.request_remove(_id)

func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("free_mouse") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()
