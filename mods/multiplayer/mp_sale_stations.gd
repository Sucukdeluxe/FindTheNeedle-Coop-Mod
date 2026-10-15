extends Node

const Store = preload("res://mods/multiplayer/mp_sale_state.gd")
const Scale = preload("res://mods/multiplayer/mp_sale_scale.gd")
const BUILD_ID := "mp_sale_scale"
const MOVE_ID := "mp_sale_move"
const UPGRADE_ID := "mp_sale_scales"
var hoppers: Node
var world_sync: Node
var mp: Node
var _state := {}
var _models := {}
var _links := {}
var _mode := ""
var _valid := true
var _moving_id := 0
var _build_yaw := 0.0
var _ghost: Node3D
var _ghost_id := -1
var _pending := {}
var _clock := 0.0
var _panel: CanvasLayer

func start(owner_service: Node) -> void:
	hoppers = owner_service
	world_sync = hoppers.world_sync
	mp = hoppers.mp
	world_sync.economy.completed.connect(_completed)
	session_started()

static func ensure_catalog() -> void:
	var entries: Dictionary = BuildCatalog.entries()
	entries[BUILD_ID] = {"name": _tr("Verkaufswaage", "Sale Scale"), "short": _tr("WAAGE", "SCALE"),
		"unlock": UPGRADE_ID, "category": "haulage", "mode": BuildTool.Mode.CONVEYOR,
		"cost": "$500", "place": _tr("Verkaufswaage auf einer freien Fläche platzieren", "Place sale scale on a clear surface"),
		"blurb": _tr("Zusätzliche Abgabestelle mit Originalwaage. Nutzt dieselben Verkaufspreise und das gemeinsame Konto.", "Additional drop-off with the original scale. Uses the same sale prices and shared account.")}
	entries[MOVE_ID] = {"name": _tr("Verkaufsstelle versetzen", "Move Sale Station"), "short": _tr("VERSETZEN", "MOVE"),
		"unlock": "", "category": "haulage", "mode": BuildTool.Mode.CONVEYOR,
		"cost": "$0", "place": _tr("Leere Verkaufsstelle auswählen und versetzen", "Select and move an empty sale station"),
		"blurb": _tr("Versetzt den vorhandenen Verkaufsstand oder eine zusätzliche Waage. E öffnet die Auswahl.", "Moves the existing selling stand or an extra scale. Press E to select.")}

static func ensure_cards(nodes: Dictionary, locale: String) -> void:
	var german := locale.begins_with("de")
	nodes[UPGRADE_ID] = {"kind": "ranked", "requires": ["belt"], "branch": "lines", "icon": "hay_price+more",
		"costs": Store.UPGRADE_COSTS.duplicate(), "flat": true, "base": "1", "values": ["2", "3", "4", "5"],
		"name": "Zusätzliche Verkaufswaagen" if german else "Additional Sale Scales",
		"blurb": "Schaltet je Stufe eine weitere Verkaufswaage frei. Höchstens fünf Verkaufsstellen einschließlich des vorhandenen Standes." if german else "Unlocks one additional sale scale per rank. Up to five sale stations including the existing stand.",
		"suffix": " Verkaufsstellen" if german else " sale stations"}
	if not TechTree.ids().has(UPGRADE_ID):
		TechTree.ids().append(UPGRADE_ID)

func session_started() -> void:
	var mode: String = hoppers._role()
	if mode == _mode:
		return
	if _mode != "":
		session_ended()
	_mode = mode
	var stand: Node3D = world_sync.builds.get("stand")
	if not is_instance_valid(stand):
		_valid = false
		return
	var saved: Variant = GameState.get("mp_sale_stations")
	_valid = saved == null or saved == {} or Store.valid(saved)
	if not _valid:
		return
	_state = Store.fresh(stand.global_position, stand.global_rotation.y) if saved == null or saved == {} else saved.duplicate(true)
	_models[1] = stand
	_rebuild_models()
	_persist()

func session_ended() -> void:
	_persist()
	_mode = ""
	cancel_preview()
	_pending.clear()

func shutdown() -> void:
	session_ended()
	for id in _models:
		if id != 1 and is_instance_valid(_models[id]):
			_models[id].queue_free()
	_models.clear()
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	if world_sync.economy.completed.is_connected(_completed):
		world_sync.economy.completed.disconnect(_completed)

func _usable() -> bool:
	return _valid and _mode != "" and _mode == hoppers._role()

func serialize() -> Dictionary:
	return _state.duplicate(true)

func _persist() -> void:
	if _valid and _mode in ["offline", "host"] and not _state.is_empty():
		GameState.set("mp_sale_stations", serialize())

func on_state(value: Variant) -> void:
	if not _usable() or _mode != "guest" or not Store.valid(value):
		return
	_state = value.duplicate(true)
	_rebuild_models()

func _row(id: int) -> Dictionary:
	for row in _state.get("rows", []):
		if row.id == id:
			return row
	return {}

func model(id: int) -> Node3D:
	return _models.get(id) as Node3D

func _rebuild_models() -> void:
	var live := {}
	for row in _state.rows:
		live[row.id] = true
		var station := model(row.id)
		if not is_instance_valid(station):
			station = Scale.new()
			station.name = "MPSaleScale%d" % row.id
			station.mp_station_id = row.id
			station.feed_belt = bool(row.get("feed_belt", true))
			station.live = world_sync.world.live
			station.props = world_sync.world.props
			station.transform = Transform3D(Basis(Vector3.UP, float(row.yaw)), row.position)
			world_sync.world.add_child(station)
			_models[row.id] = station
		else:
			station.mp_station_id = row.id
			station.mp_move_to(Transform3D(Basis(Vector3.UP, float(row.yaw)), row.position))
			if row.id != 1:
				station.set_feed_belt(bool(row.get("feed_belt", true)))
		for body in station.find_children("*", "CollisionObject3D", true, false):
			body.set_meta("mp_sale_station", row.id)
	for id in _models.keys():
		if not live.has(id):
			if is_instance_valid(_models[id]):
				_models[id].queue_free()
			_models.erase(id)
	_refresh_links()

func _refresh_links() -> void:
	var desired := {}
	for path in world_sync.builds.conveyors:
		if not is_instance_valid(path) or path.is_queued_for_deletion():
			continue
		var line: PackedVector3Array = path.centre_line()
		if line.size() < 2:
			continue
		for id in _models:
			var station := model(id)
			if not is_instance_valid(station) or id == 1:
				continue
			var inlet: Vector3 = station.belt_entry_point()
			if line[-1].distance_to(inlet) < 0.045 and (line[-1] - line[-2]).normalized().dot(station.intake_forward()) > 0.99:
				if not is_instance_valid(path.downstream) or path.downstream == _links.get(path) or path.downstream == station.intake_path():
					desired[path] = station.intake_path()
	for path in _links:
		if is_instance_valid(path) and not desired.has(path) and path.downstream == _links[path]:
			path.downstream = null
	for path in desired:
		if path.downstream != desired[path]:
			path.downstream = desired[path]
	_links = desired

func port_at(point: Vector3, radius: float = 0.05) -> Node3D:
	var nearest: Node3D
	var distance := radius
	for id in _models:
		var station := model(id)
		if not is_instance_valid(station):
			continue
		var current: float = station.belt_entry_point().distance_to(point)
		if current < distance:
			distance = current
			nearest = station
	return nearest

func build_yaw() -> float:
	return _build_yaw

func set_build_yaw(value: float) -> void:
	if is_finite(value):
		_build_yaw = wrapf(value, -PI, PI)

func step_build_rotation() -> void:
	set_build_yaw(_build_yaw + PI * 0.5)

func _bounds(id: int) -> AABB:
	return AABB(Vector3(-4.6, 0.06, -0.95), Vector3(9.25, 3.5, 4.65)) if id == 1 else AABB(Vector3(-0.65, 0.06, -1.0), Vector3(1.3, 1.8, 1.65))

func candidate(camera: Transform3D, reach: float, yaw: float, moving: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(camera.origin, camera.origin - camera.basis.z.normalized() * reach, Cfg.L_WORLD | Cfg.L_BUILD)
	var hit: Dictionary = world_sync.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.75:
		return {"ok": false, "reason": _tr("Auf eine freie Baufläche zielen", "Aim at a clear building surface")}
	var at: Vector3 = hit.position
	var reason := _placement_reason(at, yaw, moving)
	return {"ok": reason == "", "reason": reason, "position": at, "yaw": yaw, "cost": 0.0 if moving > 0 else Store.COST}

func _placement_reason(at: Vector3, yaw: float, moving: int) -> String:
	if moving == 0 and _state.rows.size() >= mini(Store.LIMIT, 1 + int(Tech.ranks.get(UPGRADE_ID, 0))):
		return _tr("Weitere Verkaufswaage zuerst freischalten", "Unlock another sale scale first")
	var bounds := _bounds(moving)
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var pose := Transform3D(Basis(Vector3.UP, yaw), at)
	var footprint: AABB = pose * bounds
	for row in _state.rows:
		if row.id != moving and footprint.intersects(Transform3D(Basis(Vector3.UP, float(row.yaw)), row.position) * _bounds(row.id)):
			return _tr("Hier steht bereits eine Verkaufsstelle", "A sale station is already placed here")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose.translated_local(bounds.get_center())
	query.collision_mask = Cfg.L_WORLD | Cfg.L_BUILD | Cfg.L_PILE
	query.margin = 0.01
	var current := model(moving)
	if is_instance_valid(current):
		var exclude: Array[RID] = []
		for body in current.find_children("*", "CollisionObject3D", true, false):
			exclude.append(body.get_rid())
		query.exclude = exclude
	if not world_sync.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return _tr("Hier ist kein Platz für die Verkaufsstelle", "There is no room for the sale station here")
	return ""

func build_candidate(camera: Transform3D, reach: float) -> Dictionary:
	if not _usable():
		return {"ok": false, "reason": _tr("Spielwelt wird vorbereitet", "Preparing world")}
	if world_sync.player.build_id != MOVE_ID:
		_moving_id = 0
	if world_sync.player.build_id == MOVE_ID and _moving_id == 0:
		return {"ok": false, "reason": _tr("E an einer Verkaufsstelle drücken und Versetzen wählen", "Press E at a sale station and choose Move")}
	var ray: Dictionary = hoppers._local_build_ray(camera, reach)
	var row := candidate(ray.transform, float(ray.length), _build_yaw, _moving_id)
	if row.has("position") and ray.has("view") and not _in_area(row.position, float(row.yaw), _moving_id, world_sync.player.global_position):
		row.ok = false
		row.reason = _tr("Außerhalb des Baubereichs", "Outside the build area")
	return row

func _in_area(at: Vector3, yaw: float, id: int, anchor: Vector3) -> bool:
	var pose := Transform3D(Basis(Vector3.UP, yaw), at)
	for i in 8:
		if not hoppers.BuildCamera.point_allowed(pose * _bounds(id).get_endpoint(i), anchor):
			return false
	return true

func preview(camera: Transform3D, reach: float, show: bool) -> Dictionary:
	if not show or not _usable():
		if is_instance_valid(_ghost):
			_ghost.hide()
		return {}
	var row := build_candidate(camera, reach)
	if not row.has("position"):
		if is_instance_valid(_ghost):
			_ghost.hide()
		return row
	_ensure_ghost(_moving_id)
	_ghost.show()
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, float(row.yaw)), row.position)
	var tint := Color(0.2, 0.85, 0.5, 0.42) if row.ok else Color(0.95, 0.2, 0.18, 0.42)
	for mesh in _ghost.get_children():
		mesh.material_override.albedo_color = tint
	return row

func _ensure_ghost(id: int) -> void:
	if is_instance_valid(_ghost) and _ghost_id == id:
		return
	if is_instance_valid(_ghost):
		_ghost.free()
	_ghost = Node3D.new()
	_ghost_id = id
	world_sync.world.add_child(_ghost)
	var station := model(id)
	var temporary := false
	if not is_instance_valid(station):
		station = Scale.new()
		station.set_physics_process(false)
		station.set_process(false)
		world_sync.world.add_child(station)
		temporary = true
	var inverse := station.global_transform.affine_inverse()
	for source in station.find_children("*", "MeshInstance3D", true, false):
		if not source.is_visible_in_tree():
			continue
		var mesh := MeshInstance3D.new()
		mesh.mesh = source.mesh
		mesh.transform = inverse * source.global_transform
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
		_ghost.add_child(mesh)
	if temporary:
		station.free()

func cancel_preview() -> void:
	_moving_id = 0
	if is_instance_valid(_ghost):
		_ghost.hide()

func begin_move(id: int) -> void:
	var station := model(id)
	if not is_instance_valid(station) or not station.mp_can_move():
		world_sync.toast(_tr("Verkaufsstelle zuerst vollständig leeren", "Empty the sale station first"))
		return
	if is_instance_valid(_panel):
		_panel.close()
	world_sync.player.equip_build(MOVE_ID)
	_moving_id = id
	set_build_yaw(float(_row(id).yaw))

func request_place(camera: Transform3D, body: Transform3D, reach: float) -> int:
	var row := build_candidate(camera, reach)
	if not row.get("ok", false):
		world_sync.toast(row.get("reason", ""))
		return 0
	var old := _row(_moving_id)
	var args := {"camera": camera, "body": body, "position": row.position, "yaw": row.yaw,
		"id": _moving_id, "revision": old.get("revision", 0), "max_price": Store.COST}
	var ray: Dictionary = hoppers._local_build_ray(camera, reach)
	if ray.has("view"):
		args.build_view = ray.view
	return _request("sale_move" if _moving_id > 0 else "sale_place", args)

func _request(action: String, args: Dictionary) -> int:
	if not _usable() or not _pending.is_empty():
		return 0
	var sequence: int = world_sync.economy.request(action, args)
	if sequence > 0:
		_pending[sequence] = action
	return sequence

func _completed(sequence: int, result: Dictionary) -> void:
	if not _pending.has(sequence):
		return
	var action: String = _pending[sequence]
	_pending.erase(sequence)
	if result.get("ok", false) and action == "sale_move":
		cancel_preview()

func execute(peer: int, action: String, args: Dictionary) -> Dictionary:
	if not _usable() or _mode not in ["host", "offline"] or not world_sync.economy.executing or world_sync._frozen:
		return _failure(_tr("Aktion nicht verfügbar", "Action unavailable"))
	var id: Variant = args.get("id")
	if not id is int or id < 0:
		return _failure(_tr("Ungültige Verkaufsstelle", "Invalid sale station"))
	var old := _row(id)
	if action != "sale_place":
		if old.is_empty() or args.get("revision") != old.revision or not hoppers._near(peer, args, old.position, Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus() + 8.0, true):
			return _failure(_tr("Verkaufsstelle wurde geändert oder ist außer Reichweite", "Sale station changed or out of reach"))
		var station := model(id)
		if not is_instance_valid(station) or not station.mp_can_move():
			return _failure(_tr("Verkaufsstelle zuerst vollständig leeren", "Empty the sale station first"))
	if action == "sale_configure":
		if id == 1 or not args.get("feed_belt") is bool:
			return _failure(_tr("Ungültige Einstellung", "Invalid setting"))
		old.feed_belt = args.feed_belt
		old.revision += 1
		_changed()
		return {"ok": true}
	if action == "sale_remove":
		if id == 1:
			return _failure(_tr("Der vorhandene Verkaufsstand kann nur versetzt werden", "The existing selling stand can only be moved"))
		_state.rows.erase(old)
		GameState.add_money(Store.COST * 0.5)
		_changed()
		return {"ok": true}
	if action not in ["sale_place", "sale_move"] or (action == "sale_place" and id != 0):
		return _failure(_tr("Ungültige Verkaufsaktion", "Invalid sale action"))
	var at: Variant = args.get("position")
	var yaw: Variant = args.get("yaw")
	if not at is Vector3 or not at.is_finite() or at.length() > 10000.0 or not (yaw is float or yaw is int) or not is_finite(float(yaw)) or absf(float(yaw)) > TAU:
		return _failure(_tr("Ungültige Position", "Invalid position"))
	if not hoppers._near(peer, args, at, Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus() + 2.0, true):
		return _failure(_tr("Position außer Reichweite", "Position out of reach"))
	var ray: Dictionary = hoppers._host_build_ray(peer, args) if args.has("build_view") else {"transform": args.camera, "length": Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus()}
	if ray.is_empty():
		return _failure(_tr("Ungültige Bauansicht", "Invalid build view"))
	var row := candidate(ray.transform, float(ray.length), float(yaw), id)
	if not row.get("ok", false) or row.position.distance_to(at) > 0.05 or (ray.has("anchor") and not _in_area(at, float(yaw), id, ray.anchor)):
		return _failure(row.get("reason", _tr("Position hat sich geändert", "Position changed")))
	if action == "sale_place":
		var limit: Variant = args.get("max_price")
		if not (limit is float or limit is int) or not is_finite(float(limit)) or float(limit) < Store.COST or not GameState.spend_money(Store.COST):
			return _failure(_tr("Zu wenig Geld", "Not enough money"))
		id = _state.next_id
		_state.next_id += 1
		_state.rows.append({"id": id, "position": at, "yaw": float(yaw), "revision": 0})
	else:
		old.position = at
		old.yaw = float(yaw)
		old.revision += 1
	_changed()
	return {"ok": true, "station": id}

func _changed() -> void:
	_rebuild_models()
	_persist()
	world_sync.builds.changed.emit()
	hoppers.send_all()

func target_id(allow_build_camera := false) -> int:
	if not _usable() or not is_instance_valid(world_sync.player) or world_sync.player.menu_is_up() or not world_sync.player.is_mouse_captured():
		return 0
	var camera: Camera3D = world_sync.player.camera
	var ray: Dictionary = hoppers._local_build_ray(camera.global_transform, 6.0) if allow_build_camera else {"origin": camera.global_position, "direction": -camera.global_basis.z, "length": 6.0}
	var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.origin + ray.direction * float(ray.length), Cfg.L_BUILD | Cfg.L_WORLD)
	var hit: Dictionary = world_sync.world.get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Variant = hit.get("collider")
	return int(collider.get_meta("mp_sale_station", 0)) if is_instance_valid(collider) else 0

func request_remove(id: int) -> int:
	var row := _row(id)
	if row.is_empty():
		return 0
	var args := {"id": id, "revision": row.revision, "body": world_sync.player.global_transform, "camera": world_sync.player.camera.global_transform}
	var ray: Dictionary = hoppers._local_build_ray(args.camera, 6.0)
	if ray.has("view"):
		args.build_view = ray.view
	return _request("sale_remove", args)

func request_feed_belt(id: int, enabled: bool) -> int:
	var row := _row(id)
	if row.is_empty() or id == 1:return 0
	var args := {"id": id, "revision": row.revision, "feed_belt": enabled, "body": world_sync.player.global_transform, "camera": world_sync.player.camera.global_transform}
	var ray: Dictionary = hoppers._local_build_ray(args.camera, 6.0)
	if ray.has("view"):args.build_view = ray.view
	return _request("sale_configure", args)

func _process(delta: float) -> void:
	if not _usable():
		return
	_clock += delta
	if _clock > 0.25:
		_clock = 0.0
		_refresh_links()

func _input(event: InputEvent) -> void:
	if not _usable() or not event.is_action_pressed("interact") or event.is_echo():
		return
	var id := target_id(true)
	if id == 0:
		return
	if not is_instance_valid(_panel):
		_panel = load("res://mods/multiplayer/mp_sale_panel.gd").new()
		_panel.service = self
		add_child(_panel)
	_panel.open(id)
	get_viewport().set_input_as_handled()

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _tr(de: String, en: String) -> String:
	return de if TranslationServer.get_locale().begins_with("de") else en
