extends Node

const Receiver = preload("res://mods/multiplayer/mp_receiver.gd")
const Distributor = preload("res://mods/multiplayer/mp_multi_splitter.gd")
const Catalog = preload("res://mods/multiplayer/mp_router_catalog.gd")
var hoppers: Node
var _ghost: Node3D
var _count := 4
var _preview_id := ""
var _turn := 0
var _build_yaw := 0.0
var _build_yaw_set := false
var _menu: CanvasLayer
var _menu_target: Node3D
var _status: Label
var _menu_card: PanelContainer

static func ensure_catalog() -> void:
	var entries: Dictionary = BuildCatalog.entries()
	for distributor in [false, true]:
		for count in Catalog.COUNTS:
			var id := Catalog.id(count, distributor)
			var title := _tr("Verteiler", "Splitter") if distributor else _tr("Sammler", "Merger")
			entries[id] = {"name": "%s · %d %s" % [title, count, _tr("Anschlüsse", "Ports")],
				"short": "%s %d" % [title.to_upper(), count], "unlock": id,
				"category": "haulage", "mode": BuildTool.Mode.CONVEYOR, "cost": "$%s" % Hud.money_text(Catalog.build_cost(count)),
				"place": _tr("Auf Band einsetzen oder frei platzieren · R drehen", "Insert into belt or place freely · R to rotate"),
				"blurb": (_tr("Ein Eingang, %d Ausgänge. E wählt den Eingang bei leerem Verteiler.", "One input, %d outputs. E selects the input when empty.") if distributor else _tr("%d Eingänge, ein Ausgang. E wählt den Ausgang bei leerem Sammler.", "%d inputs, one output. E selects the output when empty.")) % (count - 1),
				"upgrades": ["distributor_speed"], "note": _tr("Schließt Bänder und Maschinen zusammen", "Joins belts and machines")}

static func _tr(de: String, en: String) -> String:
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase(de, en)

func selected() -> bool:
	return is_instance_valid(hoppers.world_sync.player) and hoppers.world_sync.player.build_id in Catalog.ids()

func _input(event: InputEvent) -> void:
	if not hoppers._usable() or event.is_echo():
		return
	var player: Node = hoppers.world_sync.player
	if is_instance_valid(_menu) and _menu.visible:
		if event.is_action_pressed("free_mouse") or event.is_action_pressed("interact"):
			_close()
			get_viewport().set_input_as_handled()
		return
	if not player.is_mouse_captured() or player.menu_is_up():
		return
	if event.is_action_pressed("interact"):
		var target := target()
		if target != null:
			_open(target)
			get_viewport().set_input_as_handled()

func target() -> Node3D:
	var player: Node = hoppers.world_sync.player
	var ray: Dictionary = hoppers._local_build_ray(player.camera.global_transform, 6.0)
	if ray.is_empty():
		return null
	var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.origin + ray.direction * float(ray.length), Cfg.L_BUILD | Cfg.L_WORLD)
	var hit: Dictionary = preload("res://mods/multiplayer/mp_build_cutaway.gd").intersect_ray(player.get_world_3d().direct_space_state, query, ray.has("view"))
	var node: Node = hit.get("collider")
	for i in 8:
		if not is_instance_valid(node):
			break
		if node.get_script() in [Receiver, Distributor]:
			return node
		node = node.get_parent()
	return null

func build_yaw() -> float:
	if _build_yaw_set:
		return _build_yaw
	return _turn * TAU / maxi(Catalog.count_for(hoppers.world_sync.player.build_id), 1)

func set_build_yaw(value: float) -> void:
	if not is_finite(value):
		return
	_build_yaw = wrapf(value, -PI, PI)
	_build_yaw_set = true

func step_build_rotation() -> void:
	set_build_yaw(build_yaw() + TAU / maxi(Catalog.count_for(hoppers.world_sync.player.build_id), 1))

func build_candidate(camera: Transform3D, reach: float) -> Dictionary:
	var ray: Dictionary = hoppers._local_build_ray(camera, reach)
	var id: String = hoppers.world_sync.player.build_id
	var count := Catalog.count_for(id)
	return candidate(ray, count, build_yaw(), false, Catalog.is_distributor(id))

func candidate(ray: Dictionary, count: int, yaw: float, check_cargo: bool = false, distributor: bool = false) -> Dictionary:
	if ray.is_empty() or count not in Catalog.COUNTS or not is_finite(yaw) or absf(yaw) > TAU:
		return {"ok": false, "reason": _tr("Keine Baufläche", "No build surface")}
	var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.origin + ray.direction * ray.length, Cfg.L_WORLD | Cfg.L_BUILD)
	var hit: Dictionary = preload("res://mods/multiplayer/mp_build_cutaway.gd").intersect_ray(hoppers.world_sync.world.get_world_3d().direct_space_state, query, ray.has("view") or ray.has("anchor"))
	if hit.is_empty():
		return {"ok": false, "reason": _tr("Auf eine ebene Baufläche zielen", "Aim at a level building surface")}
	var at: Vector3 = hit.position + Vector3.UP * (Cfg.BELT_FRAME_DEPTH + Cfg.BELT_STAND_CLEAR)
	var radius := Catalog.radius(count)
	var builds: Node = hoppers.world_sync.builds
	var splice: Dictionary = builds.splice_spot(at, radius, radius, 0.25)
	if splice.has("reason"):
		return {"ok": false, "reason": _splice_reason(splice.reason)}
	if splice.has("centre"):
		at = splice.centre
		yaw = atan2(splice.travel.x, splice.travel.z)
	else:
		if hit.normal.y < 0.75:
			return {"ok": false, "reason": _tr("Auf eine ebene Baufläche zielen", "Aim at a level building surface")}
		at.x = snappedf(at.x, 0.25)
		at.z = snappedf(at.z, 0.25)
	var excluded: Array[RID] = []
	if splice.has("chain"):
		for belt in splice.chain:
			for body in belt.find_children("*", "CollisionObject3D", true, false):
				excluded.append(body.get_rid())
	var shape := BoxShape3D.new()
	shape.size = Vector3(radius * 2.0, 0.6, radius * 2.0)
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = shape
	probe.transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.22)
	probe.collision_mask = Cfg.L_BUILD | Cfg.L_PILE
	probe.exclude = excluded
	var blocked: bool = not hoppers.world_sync.world.get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty()
	var reason := _tr("Baufläche belegt", "Build surface blocked") if blocked else ""
	if check_cargo and not blocked and splice.has("run") and not builds.receiver_splice_fits(splice.run, at, yaw, count):
		blocked = true
		reason = _tr("Band an der Einbaustelle zuerst leerlaufen lassen", "Let this belt section empty before inserting")
	return {"ok": not blocked, "reason": reason, "position": at, "yaw": yaw, "count": count, "splice": splice, "distributor": distributor}

func _splice_reason(reason: String) -> String:
	match reason:
		"level": return _tr("Nur in ein gerades, waagerechtes Band einsetzen", "Insert into a straight, level belt")
		"short": return _tr("Band für dieses Modul zu kurz", "Belt is too short for this module")
		"gate": return _tr("Bandschalter an der Einbaustelle", "Belt gate at insertion point")
	return _tr("Modul passt hier nicht ins Band", "Module cannot be inserted here")

func preview(camera: Transform3D, reach: float, show: bool) -> Dictionary:
	if not show:
		if is_instance_valid(_ghost):
			_ghost.hide()
		return {}
	var row := build_candidate(camera, reach)
	var id: String = hoppers.world_sync.player.build_id
	var count := Catalog.count_for(id)
	if is_instance_valid(_ghost) and _preview_id != id:
		_ghost.queue_free()
		_ghost = null
	_count = count
	_preview_id = id
	if not is_instance_valid(_ghost):
		_ghost = Distributor.new() if Catalog.is_distributor(id) else Receiver.new()
		if Catalog.is_distributor(id):_ghost.input_port = count / 2
		_ghost.port_count = count
		_ghost.placement_preview = true
		hoppers.world_sync.world.add_child(_ghost)
	_ghost.visible = row.has("position")
	if _ghost.visible:
		_ghost.global_transform = Transform3D(Basis(Vector3.UP, row.yaw), row.position)
		_ghost.set_preview_valid(row.ok)
	return row

func request_place(camera: Transform3D, body: Transform3D, reach: float) -> int:
	var row := build_candidate(camera, reach)
	if not row.get("ok", false):
		hoppers.world_sync.toast(row.get("reason", ""))
		return 0
	var args := {"camera": camera, "body": body, "position": row.position, "yaw": row.yaw, "count": row.count, "distributor": row.distributor}
	if row.splice.has("run"):
		args.splice = {"a": row.splice.run.a, "b": row.splice.run.b}
	var ray: Dictionary = hoppers._local_build_ray(camera, reach)
	if ray.has("view"):
		args.build_view = ray.view
	return hoppers._request("receiver_place", args)

func execute(peer: int, action: String, args: Dictionary) -> Dictionary:
	if not hoppers._usable() or hoppers._mode not in ["host", "offline"] or hoppers.world_sync._frozen or not hoppers.world_sync.economy.executing:
		return {"ok": false}
	var at: Variant = args.get("position")
	if not (at is Vector3) or not at.is_finite() or not hoppers._near(peer, args, at, Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus() + 2.0, true):
		return {"ok": false}
	if not (args.get("distributor", false) is bool):return {"ok": false}
	var distributor: bool = args.get("distributor", false)
	if action == "receiver_configure":
		for target in (hoppers.world_sync.builds.splitters if distributor else hoppers.world_sync.builds.joiners):
			if target.get_script() != (Distributor if distributor else Receiver) or target.global_position.distance_to(at) > 0.05:
				continue
			if not (args.get("output") is int) or args.output < 0 or args.output >= target.port_count or (target.input_port if distributor else target.output_port) != args.get("previous") or not target.empty():
				return {"ok": false, "message": _tr("Modul zuerst leerlaufen lassen", "Let the module empty first")}
			var covered: Variant = args.get("covered", target.covered)
			if not covered is bool or (args.has("covered") and args.get("previous_covered") != target.covered):
				return {"ok": false}
			if covered and not target.covered and not Tech.is_unlocked("enclosed_belt"):
				return {"ok": false, "message": _cover_text(2)}
			if args.output == (target.input_port if distributor else target.output_port):
				target.set_covered(covered)
				hoppers.world_sync.builds.changed.emit()
				return {"ok": true}
			var count: int = target.port_count
			var yaw: float = target.global_rotation.y
			var builds: Node = hoppers.world_sync.builds
			(builds.splitters if distributor else builds.joiners).erase(target)
			builds.remove_child(target)
			target.queue_free()
			var replacement: Node3D = builds.add_multi_splitter(at, yaw, count, args.output) if distributor else builds.add_receiver(at, yaw, count, args.output)
			replacement.set_covered(covered)
			builds.changed.emit()
			return {"ok": true}
		return {"ok": false}
	if args.get("count") not in Catalog.COUNTS or not (args.get("yaw") is float) or not is_finite(args.yaw) or absf(args.yaw) > TAU or not BuildCatalog.is_unlocked(Catalog.id(args.count, distributor)):
		return {"ok": false}
	var ray: Dictionary = hoppers._host_build_ray(peer, args) if args.has("build_view") else {"origin": args.camera.origin, "direction": -args.camera.basis.z, "length": Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus()}
	var row := candidate(ray, args.count, args.yaw, true, distributor)
	if not row.get("ok", false) or row.position.distance_to(at) > 0.05 or absf(angle_difference(row.yaw, args.yaw)) > 0.01:
		return {"ok": false, "message": row.get("reason", "")}
	var splice: Dictionary = row.splice
	if splice.has("run") != args.has("splice"):
		return {"ok": false}
	if splice.has("run") and (not (args.splice is Dictionary) or args.splice.get("a") != splice.run.a or args.splice.get("b") != splice.run.b):
		return {"ok": false}
	var price := Catalog.build_cost(args.count)
	if splice.has("run"):
		price = maxf(0.0, price - hoppers.world_sync.builds.t_splice_refund(splice.run, row.position, splice.travel, Catalog.radius(args.count)))
	if not GameState.spend_money(price):
		return {"ok": false, "message": _tr("Zu wenig Geld", "Not enough money")}
	if splice.has("run"):
		if hoppers.world_sync.builds.splice_receiver(splice.run, row.position, row.yaw, args.count, distributor) == null:
			GameState.add_money(price)
			return {"ok": false}
	else:
		hoppers.world_sync.builds.add_multi_splitter(row.position, row.yaw, args.count) if distributor else hoppers.world_sync.builds.add_receiver(row.position, row.yaw, args.count)
	return {"ok": true}

func _open(target: Node3D) -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu_target = target
	_menu = CanvasLayer.new()
	_menu.layer = 20
	add_child(_menu)
	var card := PlateKit.card(620.0)
	_menu_card = card
	_menu.add_child(card)
	var whole := VBoxContainer.new()
	whole.add_theme_constant_override("separation", 0)
	card.add_child(whole)
	var splitter: bool = target.get_script() == Distributor
	var title := ("%s · %d %s" % [_tr("Verteiler", "Splitter") if splitter else _tr("Sammler", "Merger"), target.port_count, _tr("Anschlüsse", "Ports")]).to_upper()
	var top := PlateKit.top(whole, title, "*", _close, null)
	var photo: Control = top.photo
	(photo.get_child(0) as TextureRect).texture = preload("res://mods/multiplayer/mp_receiver_icon.gd").texture(target.port_count, splitter)
	photo.show()
	top.chip.hide()
	ArmPanel.write_state(top.word, top.sign, 0)
	top.word.text = _tr("FLUSSRICHTUNG", "FLOW DIRECTION")
	top.line.text = _tr("Eingang wählen", "Select input") if splitter else _tr("Ausgang wählen", "Select output")
	var rows := PlateKit.body(whole, 620.0)
	var diagram := preload("res://mods/multiplayer/mp_port_diagram.gd").new()
	diagram.target = target
	diagram.port_selected.connect(_set_output)
	rows.add_child(diagram)
	var legend := Label.new()
	legend.text = _tr("Blau: Eingang   ·   Gold: Ausgang\nAnschluss wählen · Gerät muss leer sein", "Blue: input   ·   Gold: output\nSelect a port · device must be empty")
	UiFont.style(legend, 14, ArmPanel.COL_INK_SOFT, 0, false)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(legend)
	var cover := PlateKit.button(_cover_text(0 if target.covered else 1), "", _toggle_cover)
	cover.name = "RouterCoverToggle"
	cover.toggle_mode = true
	cover.button_pressed = target.covered
	cover.disabled = not target.covered and not Tech.is_unlocked("enclosed_belt")
	cover.tooltip_text = _cover_text(2) if cover.disabled else ""
	rows.add_child(cover)
	var done := PlateKit.button(_tr("Schließen", "Close"), "", _close)
	rows.add_child(done)
	if not get_viewport().size_changed.is_connected(_fit_menu):
		get_viewport().size_changed.connect(_fit_menu)
	_fit_menu.call_deferred()
	hoppers.world_sync.player.set_meta("mp_build_menu", _menu)
	hoppers.world_sync.player.capture_mouse(false)

func _fit_menu() -> void:
	if not is_instance_valid(_menu_card):return
	var view := get_viewport().get_visible_rect().size
	_menu_card.size = Vector2(minf(620.0, view.x - 24.0), 0.0)
	_menu_card.position = (view - _menu_card.size) * 0.5

func _set_output(side: int) -> void:
	if is_instance_valid(_menu_target):
		_configure(side, _menu_target.covered)

func _toggle_cover() -> void:
	if is_instance_valid(_menu_target):
		_configure(_menu_target.input_port if _menu_target.get_script() == Distributor else _menu_target.output_port, not _menu_target.covered)

func _configure(side: int, covered: bool) -> void:
	if not is_instance_valid(_menu_target):
		_close()
		return
	var player: Node = hoppers.world_sync.player
	var args := {"position": _menu_target.global_position, "output": side, "previous": (_menu_target.input_port if _menu_target.get_script() == Distributor else _menu_target.output_port), "distributor": _menu_target.get_script() == Distributor, "covered": covered, "previous_covered": _menu_target.covered, "body": player.global_transform, "camera": player.camera.global_transform}
	var ray: Dictionary = hoppers._local_build_ray(player.camera.global_transform, 6.0)
	if ray.has("view"):
		args.build_view = ray.view
	hoppers._request("receiver_configure", args)
	_close()

func _close() -> void:
	if hoppers.world_sync.player.has_meta("mp_build_menu") and hoppers.world_sync.player.get_meta("mp_build_menu") == _menu:
		hoppers.world_sync.player.remove_meta("mp_build_menu")
	if is_instance_valid(_menu):
		_menu.hide()
	hoppers.world_sync.player.capture_mouse(true)

func _exit_tree() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()

const COVER_TEXT := {
	"en": ["Enclosure: on", "Enclosure: off", "Unlock enclosed conveyors first."],
	"de": ["Abdeckung: An", "Abdeckung: Aus", "Zuerst geschlossene Förderbänder freischalten."],
	"es": ["Cubierta: activada", "Cubierta: desactivada", "Desbloquea primero las cintas cerradas."],
	"fr": ["Capot : activé", "Capot : désactivé", "Débloquez d’abord les convoyeurs fermés."],
	"it": ["Copertura: attiva", "Copertura: disattiva", "Sblocca prima i nastri chiusi."],
	"cs": ["Kryt: zapnutý", "Kryt: vypnutý", "Nejprve odemkněte uzavřené dopravníky."],
	"pl": ["Osłona: włączona", "Osłona: wyłączona", "Najpierw odblokuj zamknięte przenośniki."],
	"ru": ["Кожух: включён", "Кожух: выключен", "Сначала откройте закрытые конвейеры."],
	"tr": ["Kapak: açık", "Kapak: kapalı", "Önce kapalı konveyörlerin kilidini açın."],
	"ja": ["カバー：あり", "カバー：なし", "先に密閉型コンベヤーをアンロックしてください。"],
	"ko": ["덮개: 켜짐", "덮개: 꺼짐", "먼저 밀폐형 컨베이어를 해제하세요."],
	"zh": ["外罩：开启", "外罩：关闭", "请先解锁封闭式传送带。"],
	"pt": ["Cobertura: ativada", "Cobertura: desativada", "Desbloqueie primeiro as esteiras fechadas."],
	"uk": ["Кожух: увімкнено", "Кожух: вимкнено", "Спочатку відкрийте закриті конвеєри."],
	"ar": ["الغطاء: مفعّل", "الغطاء: معطّل", "افتح الناقلات المغلقة أولاً."],
	"fa": ["پوشش: فعال", "پوشش: غیرفعال", "ابتدا نوار نقاله‌های بسته را باز کنید."],
	"zh_TW": ["外罩：開啟", "外罩：關閉", "請先解鎖封閉式輸送帶。"]
}

static func _cover_text(index: int) -> String:
	var language := preload("res://mods/multiplayer/mp_i18n.gd").language_code(TranslationServer.get_locale())
	return str(COVER_TEXT.get(language, COVER_TEXT.en)[index])
