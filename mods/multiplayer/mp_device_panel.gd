extends Control

const LANGUAGES := ["en", "de", "es", "fr", "it", "cs", "pl", "ru", "tr", "ja", "ko", "zh", "pt", "uk", "ar", "fa", "zh_TW"]
const WORDS := {
	"belt_line": ["Conveyor line", "Förderbandlinie", "Línea transportadora", "Ligne de convoyeurs", "Linea di trasporto", "Dopravní linka", "Linia przenośnika", "Конвейерная линия", "Konveyör hattı", "コンベアライン", "컨베이어 라인", "传送带线路", "Linha de transporte", "Конвеєрна лінія", "خط ناقل", "خط نوار نقاله", "輸送帶線路"],
	"title": ["Devices", "Geräte", "Dispositivos", "Appareils", "Dispositivi", "Zařízení", "Urządzenia", "Устройства", "Cihazlar", "装置", "장치", "设备", "Dispositivos", "Пристрої", "الأجهزة", "دستگاه‌ها", "設備"],
	"search": ["Search devices", "Geräte suchen", "Buscar dispositivos", "Rechercher un appareil", "Cerca dispositivi", "Hledat zařízení", "Szukaj urządzeń", "Поиск устройств", "Cihaz ara", "装置を検索", "장치 검색", "搜索设备", "Buscar dispositivos", "Пошук пристроїв", "البحث عن أجهزة", "جستجوی دستگاه‌ها", "搜尋設備"],
	"only_off": ["Only switched off", "Nur ausgeschaltete", "Solo apagados", "Appareils éteints", "Solo spenti", "Pouze vypnutá", "Tylko wyłączone", "Только выключенные", "Yalnızca kapalı", "停止中のみ", "꺼진 장치만", "仅显示已关闭", "Somente desligados", "Лише вимкнені", "المتوقفة فقط", "فقط خاموش‌ها", "僅顯示已關閉"],
	"on": ["Enabled", "Eingeschaltet", "Encendido", "Allumé", "Acceso", "Zapnuto", "Włączone", "Включено", "Açık", "稼働許可", "켜짐", "已开启", "Ligado", "Увімкнено", "مفعّل", "روشن", "已開啟"],
	"off": ["Switched off", "Ausgeschaltet", "Apagado", "Éteint", "Spento", "Vypnuto", "Wyłączone", "Выключено", "Kapalı", "停止中", "꺼짐", "已关闭", "Desligado", "Вимкнено", "متوقف", "خاموش", "已關閉"],
	"turn_on": ["Turn on", "Einschalten", "Encender", "Allumer", "Accendi", "Zapnout", "Włącz", "Включить", "Aç", "オン", "켜기", "开启", "Ligar", "Увімкнути", "تشغيل", "روشن کردن", "開啟"],
	"turn_off": ["Turn off", "Ausschalten", "Apagar", "Éteindre", "Spegni", "Vypnout", "Wyłącz", "Выключить", "Kapat", "オフ", "끄기", "关闭", "Desligar", "Вимкнути", "إيقاف", "خاموش کردن", "關閉"],
	"empty": ["No matching devices", "Keine passenden Geräte", "No hay dispositivos", "Aucun appareil trouvé", "Nessun dispositivo", "Žádná odpovídající zařízení", "Brak pasujących urządzeń", "Устройства не найдены", "Eşleşen cihaz yok", "該当する装置なし", "일치하는 장치 없음", "没有匹配的设备", "Nenhum dispositivo", "Пристроїв не знайдено", "لا توجد أجهزة مطابقة", "دستگاهی یافت نشد", "沒有符合的設備"],
	"focus": ["Show device", "Gerät anzeigen", "Mostrar dispositivo", "Afficher l’appareil", "Mostra dispositivo", "Zobrazit zařízení", "Pokaż urządzenie", "Показать устройство", "Cihazı göster", "装置を表示", "장치 보기", "显示设备", "Mostrar dispositivo", "Показати пристрій", "عرض الجهاز", "نمایش دستگاه", "顯示設備"],
	"pending": ["Pending", "Wird geändert", "Pendiente", "En attente", "In attesa", "Čeká", "Oczekiwanie", "Ожидание", "Bekliyor", "処理中", "처리 중", "等待中", "Pendente", "Очікування", "قيد الانتظار", "در انتظار", "等待中"]
}
var power: Node
var camera: Node
var _viewport: Viewport
var _panel: PanelContainer
var _heading: Button
var _body: VBoxContainer
var _search: LineEdit
var _off_filter: CheckButton
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _rows := {}
var _pending := {}
var _elapsed := 0.0
var _locale := ""
var _collapsed := false

func start(service: Node) -> void:
	power = service
	camera = power.world_sync.build_camera
	_viewport = get_viewport()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	power.completed.connect(_completed)
	camera.mode_changed.connect(_mode_changed)
	_viewport.size_changed.connect(_layout)
	_mode_changed(camera.active)

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	set_process(false)
	if is_instance_valid(camera) and camera.mode_changed.is_connected(_mode_changed):
		camera.mode_changed.disconnect(_mode_changed)
	if is_instance_valid(power) and power.completed.is_connected(_completed):
		power.completed.disconnect(_completed)
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_layout):
		_viewport.size_changed.disconnect(_layout)
	if is_instance_valid(camera) and camera.has_meta("mp_device_panel") and camera.get_meta("mp_device_panel") == self:
		camera.remove_meta("mp_device_panel")

func word(key: String) -> String:
	var index := LANGUAGES.find(power.mp.i18n.locale())
	return WORDS[key][maxi(index, 0)]

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "OverheadDevices"
	add_child(_panel)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.07, 0.045, 0.98)
	box.border_color = Color(0.28, 0.31, 0.23)
	box.set_border_width_all(1)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", box)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	_panel.add_child(stack)
	_heading = _button(18)
	_heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_heading.pressed.connect(_toggle_collapse)
	stack.add_child(_heading)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	stack.add_child(_body)
	_search = LineEdit.new()
	_search.name = "DeviceSearch"
	_search.custom_minimum_size.y = 36
	_search.add_theme_font_size_override("font_size", 14)
	power.mp.ui._style_lobby_input(_search)
	_search.text_changed.connect(func(_value): _refresh())
	_body.add_child(_search)
	_off_filter = CheckButton.new()
	_off_filter.add_theme_font_size_override("font_size", 13)
	_off_filter.toggled.connect(func(_value): _refresh())
	_body.add_child(_off_filter)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	_body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_empty = Label.new()
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_font_size_override("font_size", 14)
	_list.add_child(_empty)
	camera.set_meta("mp_device_panel", self)

func _button(size_px: int) -> Button:
	var button := Button.new()
	button.add_theme_font_size_override("font_size", size_px)
	button.add_theme_font_override("font", UiFont.regular())
	button.add_theme_color_override("font_color", Color(0.93, 0.92, 0.84))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.85, 0.38))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.border_color = Color(1.0, 0.85, 0.38)
	button.add_theme_stylebox_override("focus", focus)
	return button

func _mode_changed(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	if enabled:
		_refresh()
		_layout()
	elif is_inside_tree():
		var focus := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus) and is_ancestor_of(focus):
			focus.release_focus()

func _toggle_collapse() -> void:
	_collapsed = not _collapsed
	_body.visible = not _collapsed
	if _collapsed:
		_search.release_focus()
	_layout()

func _layout() -> void:
	if not is_instance_valid(_panel):
		return
	var view := get_viewport_rect().size
	var width := minf(330.0, maxf(250.0, view.x * 0.3))
	width = minf(width, view.x - 24.0)
	var top := minf(160.0, view.y * 0.23)
	_panel.position = Vector2(view.x - width - 12.0, top)
	_panel.size = Vector2(width, 0.0 if _collapsed else maxf(190.0, view.y - top - 150.0))

func _process(delta: float) -> void:
	if not is_instance_valid(camera) or not camera.active:
		_mode_changed(false)
		return
	_panel.visible = not power.world_sync.player.menu_is_up()
	_elapsed += delta
	if _elapsed >= 0.35:
		_elapsed = 0.0
		_refresh()

func contains_mouse(point: Vector2) -> bool:
	return visible and _panel.visible and _panel.get_global_rect().has_point(point)

func typing() -> bool:
	return visible and _search.has_focus()

func release_text_focus() -> void:
	_search.release_focus()

func _refresh() -> void:
	for id in _pending.keys():
		if not power._requests.has(_pending[id]):
			_pending.erase(id)
	var language: String = power.mp.i18n.locale()
	if _locale != language:
		_locale = language
		layout_direction = Control.LAYOUT_DIRECTION_RTL if language in ["ar", "fa"] else Control.LAYOUT_DIRECTION_LTR
		_search.placeholder_text = word("search")
		_off_filter.text = word("only_off")
		_empty.text = word("empty")
		for control in find_children("*", "Control", true, false):
			if control is Label or control is Button or control is LineEdit:
				control.add_theme_font_override("font", UiFont.regular())
	var live := {}
	var names: Array = []
	var grouped := {}
	for machine in power._candidates():
		if not power._switchable(machine) or grouped.has(machine.get_instance_id()):
			continue
		var belt: bool = machine.has_method("mp_belt_switch_targets")
		if belt:
			for part in power._switch_targets(machine):
				grouped[part.get_instance_id()] = true
		var id: int = machine.get_instance_id()
		live[id] = true
		if not _rows.has(id):
			_rows[id] = _make_row(machine)
		var row: Dictionary = _rows[id]
		var title: String = word("belt_line") if belt else power.builds.name_of(machine)
		var off: bool = machine.is_switched_off()
		var pending: bool = _pending.has(id)
		var ready: bool = power.ready_for_switch(machine)
		row.name.text = title
		row.name.tooltip_text = word("focus") + ": " + title
		row.status.text = word("pending") if pending or not ready else word("off" if off else "on")
		row.toggle.text = word("turn_on" if off else "turn_off")
		row.toggle.disabled = pending or not ready
		row.control.visible = (not _off_filter.button_pressed or off) and (_search.text.strip_edges().is_empty() or title.to_lower().contains(_search.text.to_lower().strip_edges()))
		names.append({"id": id, "name": title})
	for id in _rows.keys():
		if not live.has(id):
			_rows[id].control.queue_free()
			_rows.erase(id)
			_pending.erase(id)
	names.sort_custom(func(a,b):return a.name < b.name if a.name != b.name else a.id < b.id)
	var shown := 0
	var index := 1
	for entry in names:
		var row: Dictionary = _rows[entry.id]
		if row.control.get_index() != index:
			_list.move_child(row.control, index)
		index += 1
		if row.control.visible:
			shown += 1
	_empty.visible = shown == 0
	_heading.text = word("title") + " · " + _number(shown) + " / " + _number(_rows.size())

func _number(value: int) -> String:
	var text := str(value)
	var separator := "." if _locale in ["de", "es", "it", "tr", "pt"] else (" " if _locale in ["fr", "cs", "pl", "ru", "uk"] else ",")
	var result := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0:
			result += separator
		result += text[i]
	return result

func _make_row(machine: Node3D) -> Dictionary:
	var box := VBoxContainer.new()
	box.name = "Device_" + str(machine.get_instance_id())
	box.add_theme_constant_override("separation", 2)
	_list.add_child(box)
	var name_button := _button(14)
	name_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_button.clip_text = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.pressed.connect(_focus_device.bind(weakref(machine)))
	box.add_child(name_button)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var status := Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_override("font", UiFont.regular())
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color(0.72, 0.76, 0.67))
	actions.add_child(status)
	var toggle := _button(13)
	toggle.custom_minimum_size = Vector2(104, 30)
	toggle.pressed.connect(_toggle_device.bind(weakref(machine)))
	actions.add_child(toggle)
	return {"node": weakref(machine), "control": box, "name": name_button, "status": status, "toggle": toggle}

func _focus_device(reference: WeakRef) -> void:
	var machine: Variant = reference.get_ref()
	if not is_instance_valid(machine) or not camera.active:
		return
	var point: Vector3 = (machine.a + machine.b) * 0.5 if machine.has_method("mp_belt_switch_targets") else machine.global_position
	camera._focus = Vector3(point.x, camera._anchor.y, point.z)
	camera._update_camera()
	_search.release_focus()

func _toggle_device(reference: WeakRef) -> void:
	var machine: Variant = reference.get_ref()
	if not is_instance_valid(machine) or _pending.has(machine.get_instance_id()):
		return
	var sequence: int = power.request_machine(machine, not machine.is_switched_off())
	if sequence != 0:
		_pending[machine.get_instance_id()] = sequence
	_refresh()

func _completed(sequence: int, _result: Dictionary) -> void:
	for id in _pending.keys():
		if _pending[id] == sequence:
			_pending.erase(id)
	if visible:
		_refresh()
