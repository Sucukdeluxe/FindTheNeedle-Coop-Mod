extends Node

const Store = preload("res://mods/multiplayer/mp_hopper_state.gd")
const Model = preload("res://mods/multiplayer/mp_hopper_model.gd")
const BuildCamera = preload("res://mods/multiplayer/mp_build_camera.gd")
const Ports = preload("res://mods/multiplayer/mp_hopper_ports.gd")
const BUILD_BOUNDS := AABB(Vector3(-0.9, -0.4, -0.9), Vector3(1.8, 2.0, 1.71))
const BUILD_ID := "mp_hopper"
const OUTPUT_INTERVAL := 0.1
const CONNECTION_TOLERANCE := 0.045
var mp: Node
var world_sync: Node
var receivers: Node
var sale_stations: Node
var supply_station: Node
var tool_input: Node
var take_vacuum: Callable
var _state := Store.empty()
var _models := {}
var _paths: Array = []
var _connections := {}
var _statuses := {}
var _ghost: Node3D
var _epoch := ""
var _seq := 0
var _seen := -1
var _tick := 0.0
var _refresh := 0.0
var _publish := 0.0
var _dirty := false
var _pending := {}
var _last_preview := -1
var _focused := 0
static var _catalog_locale := ""
var _storage_valid := true
var _mode := ""
var _panel: CanvasLayer
var _intake_clock := 0.0
var _tracked := {}
var _build_yaw := 0.0
var _build_yaw_set := false
var _inlets := {}

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	receivers = preload("res://mods/multiplayer/mp_receivers.gd").new()
	receivers.hoppers = self
	add_child(receivers)
	ensure_catalog()
	if is_instance_valid(world_sync.builds) and not world_sync.builds.changed.is_connected(invalidate_connections):
		world_sync.builds.changed.connect(invalidate_connections)
	if not world_sync.economy.completed.is_connected(_completed):
		world_sync.economy.completed.connect(_completed)
	set_process(true)
	set_process_input(true)
	session_started()
	sale_stations = preload("res://mods/multiplayer/mp_sale_stations.gd").new()
	add_child(sale_stations)
	sale_stations.start(self)
	supply_station = preload("res://mods/multiplayer/mp_supply_station.gd").new()
	add_child(supply_station)
	supply_station.start(self)
	tool_input = preload("res://mods/multiplayer/mp_hopper_tool_input.gd").new()
	add_child(tool_input)
	tool_input.start(self)

func _role() -> String:
	if not is_instance_valid(mp):
		return ""
	if not mp.active():
		return "offline"
	return "host" if mp.is_host else "guest"

func session_started() -> void:
	if is_instance_valid(sale_stations):
		sale_stations.session_started()
	if is_instance_valid(supply_station):
		supply_station.session_started()
	ensure_catalog()
	var mode := _role()
	if mode == "":
		if _mode != "":
			session_ended()
		return
	if mode == _mode and _storage_valid:
		return
	if _mode != "":
		session_ended()
	_mode = mode
	var saved: Variant = GameState.get("mp_hoppers")
	_storage_valid = saved == null or saved == {} or Store.valid(saved)
	if not _storage_valid:
		push_warning("[MP] Hopper storage is invalid; preserving saved data without simulation")
		return
	_state = Store.empty() if saved == null or saved == {} else Store.migrate(saved)
	_epoch = str(Time.get_ticks_usec()) + ":" + str(randi()) if mode == "host" else ""
	_seq = 0
	_seen = -1
	_statuses.clear()
	_tick = 0.0
	_publish = 0.0
	invalidate_connections()
	_rebuild_models()

func session_ended() -> void:
	_release_inlets()
	if is_instance_valid(tool_input):
		tool_input.session_ended()
	if is_instance_valid(sale_stations):
		sale_stations.session_ended()
	if is_instance_valid(supply_station):
		supply_station.session_ended()
	if _mode in ["host", "offline"]:
		_persist()
	_mode = ""
	_epoch = ""
	_seen = -1
	_seq = 0
	_pending.clear()
	if is_instance_valid(_ghost):
		_ghost.hide()
	invalidate_connections()

func _usable() -> bool:
	return _storage_valid and _mode != "" and _role() == _mode

func shutdown() -> void:
	_release_inlets()
	if is_instance_valid(tool_input):
		tool_input.shutdown()
	if is_instance_valid(sale_stations):
		sale_stations.shutdown()
	if is_instance_valid(supply_station):
		supply_station.shutdown()
	session_ended()
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.builds) and world_sync.builds.changed.is_connected(invalidate_connections):
		world_sync.builds.changed.disconnect(invalidate_connections)
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.economy) and world_sync.economy.completed.is_connected(_completed):
		world_sync.economy.completed.disconnect(_completed)
	for model in _models.values():
		if is_instance_valid(model):
			model.queue_free()
	_models.clear()
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_connections.clear()
	_paths.clear()
	_pending.clear()
	set_process(false)
	if is_instance_valid(receivers):
		receivers.queue_free()

static func ensure_catalog() -> void:
	preload("res://mods/multiplayer/mp_wall_palette.gd").ensure_catalog()
	preload("res://mods/multiplayer/mp_sale_stations.gd").ensure_catalog()
	preload("res://mods/multiplayer/mp_supply_station.gd").ensure_supply_catalog()
	preload("res://mods/multiplayer/mp_receivers.gd").ensure_catalog()
	var entries: Dictionary = BuildCatalog.entries()
	var locale := TranslationServer.get_locale()
	if entries.has(BUILD_ID) and _catalog_locale == locale:
		return
	_catalog_locale = locale
	entries[BUILD_ID] = {"name": _tr("Einfülltrichter", "Loading Hopper"), "short": _tr("TRICHTER", "HOPPER"),
		"unlock": "belt", "category": "haulage", "mode": BuildTool.Mode.CONVEYOR,
		"cost": _tr("$2.500", "$2,500"), "place": _tr("Trichter frei oder am Bandanfang platzieren", "Place hopper freely or at a belt input"),
		"blurb": _tr("10.000 bis 100.000 Halme. Rechtsklick füllt Heu aus Hand, Schaufeln, Heugabel und Hofsauger ein. Einwerfen von oben und Befüllen per Arm möglich. E öffnet die Einstellungen.",
			"10,000 to 100,000 strands. Right-click to fill from the hand, shovels, pitchfork or yard vacuum. Accepts hay thrown from above or delivered by an arm. E opens settings."),
		"note": _tr("rastet am freien Bandanfang ein", "snaps to a free belt input")}

func serialize() -> Dictionary:
	return _state.duplicate(true)

func restore(value: Dictionary) -> bool:
	if not Store.valid(value):
		return false
	_state = Store.migrate(value)
	invalidate_connections()
	return true

func invalidate_connections() -> void:
	_refresh = 0.0
	_connections.clear()

func _process(delta: float) -> void:
	if _role() != _mode:
		session_started()
	if not _usable() or not is_instance_valid(world_sync):
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		ensure_catalog()
		_paths.clear()
		for path in BeltPath._live:
			if is_instance_valid(path) and path is Conveyor and path.is_inside_tree() and not path.is_queued_for_deletion():
				_paths.append(path)
		_connections.clear()
		_refresh_inlets()
	_update_focus()
	if _mode not in ["host", "offline"] or world_sync._frozen:
		return
	_intake_clock += delta
	if _intake_clock >= 0.05:
		_intake_clock = 0.0
		_intake()
		_drain_inlets()
	_tick += delta
	if _tick >= OUTPUT_INTERVAL:
		_tick = fmod(_tick, OUTPUT_INTERVAL)
		var portion := 100
		if Tech.has_method("belt_portion"):
			portion = clampi(int(Tech.call("belt_portion")), 100, 1000)
		for row in _state.rows:
			var before: int = row.stored
			var path: Node = _connected_path(row)
			_statuses[row.id] = "disconnected" if path == null else ("paused" if row.paused else "empty")
			if before > 0 and path != null:
				var moved := Store.output(row, portion, _insert.bind(path, row))
				_statuses[row.id] = "running" if moved > 0 else ("paused" if row.paused else "blocked")
				if moved > 0:
					_dirty = true
			if is_instance_valid(_models.get(row.id)):
				_models[row.id].set_fill(row.stored, Store.capacity(row))
	_publish += delta
	if _dirty or _publish >= 2.0:
		_persist()
		send_all()
		_dirty = false
		_publish = 0.0

func _insert(count: int, path: Node, row: Dictionary) -> bool:
	if not is_instance_valid(path) or path.is_queued_for_deletion() or not path.is_inside_tree():
		return false
	var line: PackedVector3Array = path.centre_line()
	if line.size() < 2:
		return false
	var first: Vector3 = line[0]
	var along: Vector3 = (line[1] - first).normalized()
	var at := first + along * minf(0.4, first.distance_to(line[1]) * 0.5)
	var kind := BeltRun.Kind.WAD if count > 100 else BeltRun.Kind.TUFT
	var needle: int = row.needles[0] if not row.needles.is_empty() else -1
	if int(path.push_record(kind, count, needle, {"strands": count, "needle": needle}, at, -1.0, 0.15)) < 0:
		return false
	if needle >= 0:
		row.needles.pop_front()
	return true

func input_at(at: Vector3, distance: float = 0.05) -> Dictionary:
	return port_at(at, distance, true)

func port_at(at: Vector3, distance: float = 0.05, input_only: bool = false) -> Dictionary:
	var best := {}
	var nearest := distance
	for row in _state.get("rows", []):
		for side in Ports.INPUTS.size():
			var point := Ports.point(row, side)
			if point.distance_to(at) <= nearest:
				nearest = point.distance_to(at)
				best = {"id": row.id, "side": side, "point": point, "bearing": Ports.bearing(row, side), "input": true}
		if not input_only:
			var basis := Basis(Vector3.UP, float(row.yaw))
			var point: Vector3 = row.position + basis * Model.OUTLET
			if point.distance_to(at) <= nearest:
				nearest = point.distance_to(at)
				best = {"id": row.id, "side": -1, "point": point, "bearing": basis.z, "input": false}
	return best

func _release_inlets() -> void:
	for path in _inlets:
		if is_instance_valid(path) and _inlets[path].has("held"):
			path._records_held = _inlets[path].held
			path._eats = _inlets[path].eats
			path.run.hold_for = path._eats_kind if path._records_held else Callable()
			path._sync_run_links()
	_inlets.clear()

func _refresh_inlets() -> void:
	var desired := {}
	for path in _paths:
		if not is_instance_valid(path) or path.is_queued_for_deletion():continue
		var line: PackedVector3Array = path.centre_line()
		if line.size() < 2:continue
		var port := input_at(line[-1], CONNECTION_TOLERANCE)
		if port.is_empty() or not Ports.accepts(_row(int(port.id)), int(port.side), (line[-1] - line[-2]).normalized()):continue
		var link: Dictionary = _inlets.get(path, {"id": port.id})
		if _mode in ["host", "offline"] and not link.has("held"):
			link.held = path._records_held
			link.eats = path._eats
			path.hold_records(Callable())
		desired[path] = link
	for path in _inlets.keys():
		if not desired.has(path):
			var saved: Dictionary = _inlets[path]
			if is_instance_valid(path) and saved.has("held"):
				path._records_held = saved.held
				path._eats = saved.eats
				path.run.hold_for = path._eats_kind if path._records_held else Callable()
				path._sync_run_links()
	_inlets = desired

func _drain_inlets() -> void:
	for path in _inlets:
		if not is_instance_valid(path) or path.is_queued_for_deletion():continue
		var row := _row(int(_inlets[path].id))
		var record: Dictionary = path.peek_record()
		if row.is_empty() or record.is_empty() or int(record.get("kind", -1)) not in [BeltRun.Kind.WAD, BeltRun.Kind.TUFT]:continue
		var count := int(record.get("strands", 0))
		var needle := int(record.get("needle", -1))
		if count <= 0 or count > Store.capacity(row) - int(row.stored) or (needle >= 0 and row.needles.has(needle)):continue
		var taken: Dictionary = path.take_record()
		if taken.is_empty():continue
		Store.transfer(row, int(taken.strands))
		if int(taken.needle) >= 0:row.needles.append(int(taken.needle))
		_dirty = true

func _row(id: int) -> Dictionary:
	for row in _state.rows:
		if row.id == id:
			return row
	return {}

func _connected_path(row: Dictionary) -> Node:
	if _connections.has(row.id):
		var cached: Variant = _connections[row.id]
		if is_instance_valid(cached) and cached.is_inside_tree() and not cached.is_queued_for_deletion():
			return cached
	var basis := Basis(Vector3.UP, float(row.yaw))
	var outlet: Vector3 = row.position + basis * Model.OUTLET
	var forward := basis.z
	for path in _paths:
		if not is_instance_valid(path) or not path.is_inside_tree() or path.is_queued_for_deletion():
			continue
		var line: PackedVector3Array = path.centre_line()
		if line.size() < 2 or line[0].distance_to(outlet) > CONNECTION_TOLERANCE:
			continue
		if (line[1] - line[0]).normalized().dot(forward) < 0.995:
			continue
		_connections[row.id] = path
		return path
	return null

func candidate(camera: Transform3D, reach: float, free_yaw: float = NAN, overhead: bool = false) -> Dictionary:
	var best := {}
	var best_score := INF
	var direction := -camera.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(camera.origin, camera.origin + direction * reach, Cfg.L_WORLD | Cfg.L_BUILD)
	var hit: Dictionary = preload("res://mods/multiplayer/mp_build_cutaway.gd").intersect_ray(world_sync.world.get_world_3d().direct_space_state, query, overhead)
	if not hit.is_empty():
		var splice: Dictionary = world_sync.builds.splice_spot(hit.position, 1.1, Model.OUTLET.z, 0.25)
		if splice.has("centre"):
			var yaw: float = atan2(splice.travel.x, splice.travel.z)
			var row := {"position": splice.centre, "yaw": yaw, "splice": splice, "path": splice.run}
			var plan := _splice_plan(row)
			var why := _placement_reason(splice.run, row.position, yaw, splice.get("chain", []))
			row["ok"] = why == "" and plan.ok
			row["reason"] = why if why != "" else plan.get("reason", "")
			return row
	for path in _paths:
		if not is_instance_valid(path) or path.is_queued_for_deletion():
			continue
		var line: PackedVector3Array = path.centre_line()
		if line.size() < 2:
			continue
		var along := (line[1] - line[0]).normalized()
		if absf(along.y) > 0.04:
			continue
		var delta := line[0] - camera.origin
		var ahead := delta.dot(direction)
		var side := (delta - direction * ahead).length()
		if ahead < 0.0 or ahead > reach or side > 0.85:
			continue
		var score := side + ahead * 0.015
		if score >= best_score:
			continue
		var yaw := atan2(along.x, along.z)
		var at := line[0] - Basis(Vector3.UP, yaw) * Model.OUTLET
		best = {"position": at, "yaw": yaw, "path": path}
		best_score = score
	if best.is_empty():
		if hit.is_empty() or hit.normal.y < 0.75:
			return {"ok": false, "reason": _tr("Auf eine Baufläche oder einen freien Bandanfang zielen", "Aim at a building surface or free belt input")}
		var at: Vector3 = hit.position + Vector3.UP * (Cfg.BELT_FRAME_DEPTH + Cfg.BELT_STAND_CLEAR)
		best = {"position": at, "yaw": free_yaw if is_finite(free_yaw) else snappedf(atan2(direction.x, direction.z), PI * 0.5), "path": null}
	var why := _placement_reason(best.path, best.position, best.yaw)
	best["ok"] = why == ""
	best["reason"] = why
	return best

func build_yaw() -> float:
	if _build_yaw_set or not is_instance_valid(world_sync.player):
		return _build_yaw
	var direction: Vector3 = -world_sync.player.camera.global_basis.z
	return snappedf(atan2(direction.x, direction.z), PI * 0.5)

func set_build_yaw(value: float) -> void:
	if is_finite(value):
		_build_yaw = wrapf(value, -PI, PI)
		_build_yaw_set = true

func step_build_rotation() -> void:
	set_build_yaw(build_yaw() + PI * 0.5)

func _placement_reason(path: Node, at: Vector3, yaw: float, ignored: Array = []) -> String:
	if _state.rows.size() >= Store.LIMIT:
		return _tr("Maximal 32 Trichter", "Maximum 32 hoppers")
	for row in _state.rows:
		if row.position.distance_to(at) < 1.5:
			return _tr("Hier steht bereits ein Trichter", "A hopper is already placed here")
	for other in BeltPath._live:
		if ignored.is_empty() and is_instance_valid(path) and is_instance_valid(other) and other != path and (other.downstream == path or other.end_deck == path):
			return _tr("Dieser Bandanfang ist bereits verbunden", "This belt input is already connected")
	var exclude: Array[RID] = []
	if is_instance_valid(path):
		for body in path.find_children("*", "CollisionObject3D", true, false):
			exclude.append(body.get_rid())
	if path is CollisionObject3D:
		exclude.append(path.get_rid())
	for belt in ignored:
		for body in belt.find_children("*", "CollisionObject3D", true, false):exclude.append(body.get_rid())
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.68, 1.2, 1.31)
	var pose := Transform3D(Basis(Vector3.UP, yaw), at)
	pose.origin += pose.basis * Vector3(0.0, 0.95, -0.18)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = pose
	query.collision_mask = Cfg.L_WORLD | Cfg.L_BUILD | Cfg.L_PILE
	query.exclude = exclude
	query.margin = 0.02
	if not world_sync.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return _tr("Hier ist kein Platz für den Trichter", "There is no room for the hopper here")
	return ""

func _build_controller() -> Node:
	var controller: Node = world_sync.get("build_camera")
	if not is_instance_valid(controller) and is_instance_valid(world_sync.player):
		controller = world_sync.player.get("mp_build_camera")
	return controller

func _local_build_ray(camera: Transform3D, reach: float) -> Dictionary:
	var controller := _build_controller()
	if is_instance_valid(controller) and bool(controller.get("active")):
		var view: Dictionary = controller.request_view()
		var ray := BuildCamera.validate_view(view, world_sync.player.global_position)
		if not ray.is_empty():
			ray["view"] = view
		return ray
	return {"origin": camera.origin, "direction": -camera.basis.z.normalized(), "length": reach, "transform": camera}

func _host_build_ray(peer: int, args: Dictionary) -> Dictionary:
	var body: Variant = args.get("body")
	if not (body is Transform3D) or not body.is_finite():
		return {}
	var known: Variant = world_sync.player.global_position if peer == 1 else world_sync.avatar_positions().get(peer)
	if not (known is Vector3) or not known.is_finite() or known.distance_to(body.origin) > 4.0:
		return {}
	var ray := BuildCamera.validate_view(args.get("build_view"), known)
	if not ray.is_empty():
		ray["anchor"] = known
	return ray

func _placement_in_area(row: Dictionary, anchor: Vector3) -> bool:
	var transform := Transform3D(Basis(Vector3.UP, row.yaw), row.position)
	for i in 8:
		if not BuildCamera.point_allowed(transform * BUILD_BOUNDS.get_endpoint(i), anchor):
			return false
	return true

func build_candidate(camera: Transform3D, reach: float) -> Dictionary:
	if not _usable():
		return {"ok": false, "reason": _tr("Spielwelt wird vorbereitet", "Preparing world")}
	var ray := _local_build_ray(camera, reach)
	if ray.is_empty():
		return {"ok": false, "reason": _tr("Außerhalb des Baubereichs", "Outside the build area")}
	var row := candidate(ray.transform, float(ray.length), build_yaw(), ray.has("view"))
	if row.has("position") and ray.has("view") and not _placement_in_area(row, world_sync.player.global_position):
		row["ok"] = false
		row["reason"] = _tr("Außerhalb des Baubereichs", "Outside the build area")
	return row

func preview(camera: Transform3D, reach: float, show: bool) -> Dictionary:
	if not show or not _usable():
		if is_instance_valid(_ghost):
			_ghost.hide()
		return {}
	var row := build_candidate(camera, reach)
	if not is_instance_valid(_ghost):
		_ghost = Model.new()
		_ghost.preview = true
		world_sync.world.add_child(_ghost)
	_ghost.visible = row.has("position")
	if _ghost.visible:
		_ghost.global_transform = Transform3D(Basis(Vector3.UP, row.yaw), row.position)
		var valid := 1 if row.ok else 0
		if valid != _last_preview:
			_ghost.set_preview_valid(row.ok)
			_last_preview = valid
	return row

func request_place(camera: Transform3D, body: Transform3D, reach: float) -> int:
	var row := build_candidate(camera, reach)
	if not row.get("ok", false):
		world_sync.toast(row.get("reason", ""))
		return 0
	var args := {"camera": camera, "body": body, "position": row.position, "yaw": row.yaw, "max_price": Store.COST}
	var ray := _local_build_ray(camera, reach)
	if ray.has("view"):
		args["build_view"] = ray.view
	return _request("hopper_place", args)

func request_remove(id: int) -> int:
	var args := {"id": id, "body": world_sync.player.global_transform, "camera": world_sync.player.camera.global_transform}
	var ray := _local_build_ray(args.camera, 6.0)
	if ray.is_empty():
		return 0
	if ray.has("view"):
		args["build_view"] = ray.view
	return _request("hopper_remove", args)

func request_dump(vacuum: Node) -> bool:
	if not _usable():
		return false
	var id := target_id()
	if id == 0 or not is_instance_valid(vacuum):
		return false
	if not _pending.is_empty():
		return true
	var row := _row(id)
	if row.is_empty() or row.stored >= Store.capacity(row):
		world_sync.toast(_tr("Trichter voll", "Hopper full"))
		return true
	if int(vacuum.call("fill")) <= 0:
		world_sync.toast(_tr("Kein Heu im Hofsauger", "No hay in the yard vacuum"))
		return true
	var transfer: Node = world_sync.get("vacuum_transfer")
	if not is_instance_valid(transfer):
		world_sync.toast(_tr("Sauger wird synchronisiert", "Synchronizing vacuum"))
		return true
	var seq: int = transfer.submit(vacuum, "hopper_deposit", {"id": id, "body": world_sync.player.global_transform, "camera": world_sync.player.camera.global_transform}, Store.capacity(row))
	if seq > 0:
		_pending[seq] = "hopper_deposit"
	return true

func _request(action: String, args: Dictionary) -> int:
	if not _usable():
		return 0
	var seq: int = world_sync.economy.request(action, args)
	if seq != 0:
		_pending[seq] = action
	return seq

func _completed(seq: int, result: Dictionary) -> void:
	if not _pending.has(seq):
		return
	_pending.erase(seq)
	if result.get("ok", false) and int(result.get("moved", 0)) > 0:
		world_sync.toast(_tr("%s Halme in den Trichter gefüllt", "%s strands transferred to hopper") % _number(int(result.moved)))

func execute(peer: int, action: String, args: Dictionary) -> Dictionary:
	if not _usable() or _mode not in ["host", "offline"] or (_mode == "offline" and peer != 1) or not world_sync.economy.executing or world_sync._frozen:
		return _failure(_tr("Aktion nicht verfügbar", "Action unavailable"))
	if action in ["hopper_tool_deposit", "hopper_tool_ack", "hopper_tool_resolve"] and is_instance_valid(tool_input):
		return tool_input.execute(peer, action, args)
	if action == "hopper_place":
		return _place(peer, args)
	if action == "hopper_deposit":
		var transfer: Node = world_sync.get("vacuum_transfer")
		if is_instance_valid(transfer):
			return transfer.execute(peer, action, args)
	var id: Variant = args.get("id")
	if not (id is int):
		return _failure(_tr("Trichter nicht gefunden", "Hopper not found"))
	var row := _row(id)
	if row.is_empty() or not _near(peer, args, row.position, 7.0, action in ["hopper_remove", "hopper_configure"]):
		return _failure(_tr("Trichter außer Reichweite", "Hopper out of reach"))
	if action == "hopper_configure":
		return _configure(row, args)
	if action == "hopper_link":
		return _link_arm(row, args)
	if action == "hopper_remove":
		if args.has("build_view") and _target_from_ray(_host_build_ray(peer, args)) != id:
			return _failure(_tr("Trichter nicht im Blick", "Hopper is not under the cursor"))
		if not _spill_contents(row):
			return _failure(_tr("Inhalt konnte nicht abgelegt werden", "Could not release stored contents"))
		_state.rows.erase(row)
		GameState.add_money(Store.COST * 0.5)
		_changed()
		return {"ok": true}
	if action == "hopper_deposit":
		var room: int = Store.capacity(row) - int(row.stored)
		if room <= 0 or not take_vacuum.is_valid():
			return _failure(_tr("Trichter voll oder Sauger noch nicht synchron", "Hopper full or vacuum not yet synchronized"))
		var moved: int = int(take_vacuum.call(peer, room))
		if moved <= 0 or moved > room:
			return _failure(_tr("Kein übertragbares Heu im Hofsauger", "No transferable hay in the yard vacuum"))
		row.stored += moved
		_changed()
		return {"ok": true, "moved": moved}
	return _failure(_tr("Unbekannte Trichteraktion", "Unknown hopper action"))

func accept_reserved(peer: int, args: Dictionary, amount: int) -> int:
	if not _usable() or _mode not in ["host", "offline"] or (_mode == "offline" and peer != 1) or not world_sync.economy.executing or world_sync._frozen or amount <= 0:
		return 0
	var id: Variant = args.get("id")
	if not (id is int):
		return 0
	var row := _row(id)
	if row.is_empty() or not _near(peer, args, row.position, 7.0):
		return 0
	var moved := Store.transfer(row, amount)
	if moved > 0:
		_changed()
	return moved

func _spill_contents(row: Dictionary) -> bool:
	var props: Node = world_sync.world.props
	var left: int = row.stored
	var needles: Array = row.needles.duplicate()
	var made: Array[Node3D] = []
	while left > 0:
		var count := mini(2000, left - maxi(0, needles.size() - 1))
		var needle: int = needles.pop_front() if not needles.is_empty() else -1
		var angle := float(made.size()) * 2.399963
		var radius := 0.45 + 0.04 * sqrt(float(made.size()))
		var at: Vector3 = row.position + Vector3(cos(angle) * radius, 0.2 + 0.03 * float(made.size() / 12), sin(angle) * radius)
		var item: Node3D = props.spawn("hay_wad", Transform3D(Basis(Vector3.UP, angle), at), {"strands": count, "needle": needle})
		if not is_instance_valid(item) or int(item.call("hay_strands")) != count:
			if is_instance_valid(item):props.remove(item)
			for previous in made:props.remove(previous)
			return false
		made.append(item)
		left -= count
	return true

func _place(peer: int, args: Dictionary) -> Dictionary:
	var at: Variant = args.get("position")
	var yaw: Variant = args.get("yaw")
	if not (at is Vector3) or not at.is_finite() or at.length() > 10000.0 or not (yaw is float or yaw is int) or not is_finite(float(yaw)) or absf(float(yaw)) > TAU:
		return _failure(_tr("Ungültige Position", "Invalid placement"))
	if not _near(peer, args, at, Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus() + 2.0, true):
		return _failure(_tr("Position außer Reichweite", "Placement out of reach"))
	var ray := _host_build_ray(peer, args) if args.has("build_view") else {"transform": args.camera, "length": Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus()}
	var row := candidate(ray.transform, float(ray.length), float(yaw), ray.has("anchor"))
	if args.has("build_view") and row.has("position") and not _placement_in_area(row, ray.anchor):
		return _failure(_tr("Außerhalb des Baubereichs", "Outside the build area"))
	if not row.get("ok", false) or row.position.distance_to(at) > 0.05 or absf(angle_difference(row.yaw, float(yaw))) > 0.01:
		return _failure(row.get("reason", _tr("Verbindung hat sich geändert", "Connection has changed")))
	var limit: Variant = args.get("max_price")
	if not (limit is float or limit is int) or not is_finite(float(limit)) or float(limit) < Store.COST or not BuildCatalog.is_unlocked(BUILD_ID):
		return _failure(_tr("Trichter noch nicht verfügbar", "Hopper is not available yet"))
	if not GameState.spend_money(Store.COST):
		return _failure(_tr("Zu wenig Geld", "Not enough money"))
	var id: int = _state.next_id
	var stored := Store.create(id, row.position, float(row.yaw))
	if row.has("splice"):
		var plan := _splice_plan(row)
		if not plan.ok:
			GameState.add_money(Store.COST)
			return _failure(plan.get("reason", ""))
		for taken in plan.records:
			for index in range(taken.indices.size() - 1, -1, -1):taken.path.take_record_at(taken.indices[index])
		stored.stored = plan.strands
		stored.needles = plan.needles
		var make := func() -> Node3D:
			_state.next_id += 1
			_state.rows.append(stored)
			_changed()
			return _models[id]
		var through := func(_model: Node3D) -> Array[BeltPath]:return []
		var axis := Basis(Vector3.UP, row.yaw).z
		world_sync.builds.splice_built(row.path, row.position - axis * 1.1, row.position + axis * Model.OUTLET.z, make, through)
	else:
		_state.next_id += 1
		_state.rows.append(stored)
		_changed()
	return {"ok": true, "hopper": id}

func _splice_plan(row: Dictionary) -> Dictionary:
	var plan := {"ok": true, "records": [], "strands": 0, "needles": []}
	var axis := Basis(Vector3.UP, float(row.yaw)).z
	var builds: Node = world_sync.builds
	var taken: Array = builds._splice_taken(row.path, row.position - axis * 1.1, row.position + axis * Model.OUTLET.z)
	for path in taken:
		var indices := []
		for index in range(path.run.first(), path.run.first() + path.run.count()):
			var record: Dictionary = path.run.record(index)
			var distance: float = (path._point_at(record.s) - row.position).dot(axis)
			if distance < -1.1 or distance > Model.OUTLET.z:continue
			if int(record.kind) not in [BeltRun.Kind.WAD, BeltRun.Kind.TUFT]:
				return {"ok": false, "reason": _tr("Einbaustelle enthält verarbeitetes Material", "Insertion point contains processed material")}
			indices.append(index)
			plan.strands += int(record.strands)
			if int(record.needle) >= 0:plan.needles.append(int(record.needle))
		plan.records.append({"path": path, "indices": indices})
	if plan.strands > Store.capacity(Store.create(1, Vector3.ZERO, 0.0)):
		return {"ok": false, "reason": _tr("Zu viel Heu an der Einbaustelle", "Too much hay at the insertion point")}
	return plan

func _near(peer: int, args: Dictionary, at: Vector3, reach: float, allow_build_view := false) -> bool:
	if args.has("build_view"):
		if not allow_build_view:
			return false
		var ray := _host_build_ray(peer, args)
		return not ray.is_empty() and BuildCamera.point_allowed(at, ray.anchor)
	var body: Variant = args.get("body")
	var camera: Variant = args.get("camera")
	if not (body is Transform3D) or not (camera is Transform3D) or not body.is_finite() or not camera.is_finite():
		return false
	if absf(camera.basis.determinant()) < 0.01 or body.origin.distance_to(camera.origin) > 5.0:
		return false
	if at.distance_to(camera.origin) > reach:
		return false
	var known: Variant = world_sync.player.global_position if peer == 1 else world_sync.avatar_positions().get(peer)
	return known is Vector3 and known.distance_to(body.origin) <= 4.0

func target_id(allow_build_camera := false) -> int:
	if not is_instance_valid(world_sync.player) or not world_sync.player.is_mouse_captured() or world_sync.player.menu_is_up():
		return 0
	var camera: Camera3D = world_sync.player.camera
	var ray := _local_build_ray(camera.global_transform, 6.0) if allow_build_camera else {"origin": camera.global_position, "direction": -camera.global_basis.z, "length": 6.0}
	return _target_from_ray(ray)

func _target_from_ray(ray: Dictionary) -> int:
	if ray.is_empty():
		return 0
	var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.origin + ray.direction * float(ray.length), Cfg.L_BUILD | Cfg.L_WORLD)
	var hit: Dictionary = preload("res://mods/multiplayer/mp_build_cutaway.gd").intersect_ray(world_sync.world.get_world_3d().direct_space_state, query, ray.has("view") or ray.has("anchor"))
	var body: Variant = hit.get("collider")
	if not is_instance_valid(body) or not body.has_meta("mp_hopper"):
		return 0
	var model: Variant = body.get_meta("mp_hopper")
	return int(model.hopper_id) if is_instance_valid(model) else 0

func _update_focus() -> void:
	if _models.is_empty():
		return
	var target := target_id(true)
	if target != _focused and is_instance_valid(_models.get(_focused)):
		_models[_focused].show_status("", false)
	_focused = target
	var model: Node = _models.get(target)
	if not is_instance_valid(model):
		return
	var row := _row(target)
	if row.is_empty():
		return
	var state: String = _statuses.get(target, "empty")
	var status := _tr("Wartet auf Heu", "Waiting for hay")
	if state == "disconnected":
		status = _tr("Kein Band verbunden", "No belt connected")
	elif state == "blocked":
		status = _tr("Band voll · Heu bleibt gespeichert", "Belt full · hay stays stored")
	elif state == "running":
		status = _tr("Gibt Heu auf das Band aus", "Feeding hay onto belt")
	elif state == "paused":
		status = _tr("Angehalten", "Paused")
	model.show_status(_tr("EINFÜLLTRICHTER", "LOADING HOPPER") + "\n" + _number(row.stored) + " / " + _number(Store.capacity(row)) + "\n" + status + "\n" + _tr("Rechtsklick · Einfüllen    E · Einstellen    X · Abbauen", "Right-click · Fill    E · Settings    X · Dismantle"), true)

func _changed() -> void:
	_dirty = true
	invalidate_connections()
	_rebuild_models()
	_persist()
	send_all()

func _persist() -> void:
	if _storage_valid and _mode in ["host", "offline"]:
		GameState.set("mp_hoppers", serialize())

func _rebuild_models() -> void:
	var active := {}
	for row in _state.rows:
		active[row.id] = true
		if not is_instance_valid(_models.get(row.id)):
			var model := Model.new()
			model.hopper_id = row.id
			model.collision_bits = Cfg.L_BUILD
			world_sync.world.add_child(model)
			_models[row.id] = model
		_models[row.id].global_transform = Transform3D(Basis(Vector3.UP, row.yaw), row.position)
		_models[row.id].set_fill(row.stored, Store.capacity(row))
	for id in _models.keys():
		if not active.has(id):
			if is_instance_valid(_models[id]):
				_models[id].queue_free()
			_models.erase(id)
			_statuses.erase(id)

func send_all(peer: int = 0) -> void:
	if not _usable() or _mode != "host" or _epoch == "":
		return
	_seq += 1
	var data := {"store": serialize(), "statuses": _statuses.duplicate()}
	if is_instance_valid(sale_stations):
		data["sales"] = sale_stations.serialize()
	if is_instance_valid(supply_station):
		data["supply"] = supply_station.serialize()
	if peer > 0:
		mp._rx_hoppers.rpc_id(peer, _epoch, _seq, data, mp._outgoing_world_seed())
	else:
		for id in mp.players:
			if id != 1 and mp.players[id].get("state") == "world":
				mp._rx_hoppers.rpc_id(id, _epoch, _seq, data, mp._outgoing_world_seed())

func on_state(epoch: String, seq: int, data: Dictionary) -> void:
	if not _usable() or _mode != "guest" or epoch == "" or epoch.length() > 128 or seq < 1 or var_to_bytes(data).size() > 32768:
		return
	if epoch == _epoch and seq <= _seen:
		return
	if not Store.valid(data.get("store")) or not (data.get("statuses") is Dictionary):
		return
	var known := {}
	for row in data.store.rows:
		known[row.id] = true
	for id in data.statuses:
		if not (id is int) or not known.has(id) or data.statuses[id] not in ["disconnected", "paused", "empty", "running", "blocked"]:
			return
	_epoch = epoch
	_seen = seq
	_state = Store.migrate(data.store)
	_statuses = data.statuses.duplicate()
	_rebuild_models()
	if is_instance_valid(sale_stations) and data.has("sales"):
		sale_stations.on_state(data.sales)
	if is_instance_valid(supply_station) and data.has("supply"):
		supply_station.on_state(data.supply)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _tr(de: String, en: String) -> String:
	return preload("res://mods/multiplayer/mp_i18n.gd").phrase(de, en)

static func _number(value: int) -> String:
	var out := str(value)
	var separator := "." if TranslationServer.get_locale().begins_with("de") else ","
	var at := out.length() - 3
	while at > 0:
		out = out.insert(at, separator)
		at -= 3
	return out

func _input(event: InputEvent) -> void:
	if not _usable() or not event.is_action_pressed("interact") or event.is_echo():
		return
	if is_instance_valid(_panel) and _panel.visible:
		_panel.close()
		get_viewport().set_input_as_handled()
		return
	var id := target_id(true)
	if id <= 0:
		return
	if not is_instance_valid(_panel):
		_panel = load("res://mods/multiplayer/mp_hopper_panel.gd").new()
		_panel.service = self
		add_child(_panel)
	_panel.open(id)
	get_viewport().set_input_as_handled()

func request_configuration(id: int, paused: bool, portion: int, upgrade: bool = false) -> int:
	var row := _row(id)
	if row.is_empty():
		return 0
	var args := {"id": id, "paused": paused, "portion": portion,
		"upgrade": upgrade, "revision": row.revision, "level": row.level,
		"body": world_sync.player.global_transform, "camera": world_sync.player.camera.global_transform}
	var ray := _local_build_ray(args.camera, 6.0)
	if ray.has("view"):
		args["build_view"] = ray.view
	return _request("hopper_configure", args)

func request_capacity_upgrade(id: int) -> int:
	var row := _row(id)
	if row.is_empty():return 0
	return request_configuration(id, row.paused, row.portion, true)

func _configure(row: Dictionary, args: Dictionary) -> Dictionary:
	if not (args.get("paused") is bool) or not (args.get("portion") is int) or not (args.get("upgrade") is bool):
		return _failure(_tr("Ungültige Einstellung", "Invalid setting"))
	if args.get("revision") != row.revision or args.get("level") != row.level:
		return _failure(_tr("Einstellung wurde bereits geändert", "Settings have already changed"))
	var portion: int = args.portion
	if not args.upgrade and (portion < 100 or portion > 1000 or portion % 100 != 0 or portion > int(Tech.call("belt_portion"))):
		return _failure(_tr("Größere Bandportion zuerst freischalten", "Unlock the larger belt portion first"))
	if args.upgrade:
		if row.level >= 9:
			return _failure(_tr("Maximale Kapazität erreicht", "Maximum capacity reached"))
		if not GameState.spend_money(Store.UPGRADE_COSTS[row.level]):
			return _failure(_tr("Zu wenig Geld", "Not enough money"))
		row.level += 1
	if not args.upgrade:
		row.paused = args.paused
		row.portion = portion
	row.revision += 1
	_changed()
	return {"ok": true}

func arm_hopper(arm: Node3D, explicit_only := false) -> Dictionary:
	for row in _state.rows:
		if row.arms.any(func(at: Vector3) -> bool: return at.distance_to(arm.global_position) < 0.05):
			return row
	if explicit_only:
		return {}
	var best := {}
	var distance := INF
	for row in _state.rows:
		var point := arm_point(row, arm)
		var d := arm.global_position.distance_squared_to(point)
		if arm.link_in_reach(point) and row.stored < Store.capacity(row) and d < distance:
			best = row
			distance = d
	return best

func arm_point(row: Dictionary, arm: Node3D) -> Vector3:
	var pose := Transform3D(Basis(Vector3.UP, row.yaw), row.position)
	var local: Vector3 = pose.affine_inverse() * arm._shoulder_world()
	return pose * Vector3(clampf(local.x, -0.72, 0.72), 1.6, clampf(local.z, -0.73, 0.37))

func arm_room(id: int, count: int) -> bool:
	var row := _row(id)
	return _usable() and not row.is_empty() and count > 0 and count <= Store.capacity(row) - int(row.stored)

func receive_arm(id: int, count: int, needle: int = -1) -> bool:
	if _mode not in ["host", "offline"] or world_sync._frozen or not arm_room(id, count):
		return false
	var row := _row(id)
	if needle >= 0 and row.needles.has(needle):
		return false
	Store.transfer(row, count)
	if needle >= 0:
		row.needles.append(needle)
	_dirty = true
	return true

func request_arm_link(id: int, arm: Node3D) -> void:
	_request("hopper_link", {"id": id, "arm": arm.global_position,
		"body": world_sync.player.global_transform, "camera": world_sync.player.camera.global_transform})

func _link_arm(row: Dictionary, args: Dictionary) -> Dictionary:
	var at: Variant = args.get("arm")
	if not (at is Vector3) or not at.is_finite():
		return _failure(_tr("Arm nicht gefunden", "Arm not found"))
	var arm: Node3D
	for other in world_sync.builds.robotic_arms:
		if is_instance_valid(other) and other.global_position.distance_to(at) < 0.05:
			arm = other
			break
	if arm == null or not arm.link_in_reach(arm_point(row, arm)):
		return _failure(_tr("Trichter außerhalb der Armreichweite", "Hopper outside arm reach"))
	var linked: bool = row.arms.has(at)
	for other in _state.rows:
		other.arms.erase(at)
	if not linked:
		row.arms.append(at)
	row.revision += 1
	_changed()
	return {"ok": true}

func _intake() -> void:
	if _state.rows.is_empty() or not is_instance_valid(world_sync.world.props):
		return
	var alive := {}
	for item in world_sync.world.props.items.duplicate():
		if not is_instance_valid(item) or not item.is_inside_tree() or item.is_queued_for_deletion() or not item is HayWad:
			continue
		var id: int = item.get_instance_id()
		alive[id] = true
		var now: Vector3 = item.global_position
		var previous: Vector3 = _tracked.get(id, now)
		_tracked[id] = now
		var claimed: bool = item.has_meta(PropManager.META_CLAIM) and int(item.get_meta(PropManager.META_CLAIM)) != world_sync.props_sync.get_instance_id()
		if item.is_held() or BeltPath.is_rider(item) or claimed:
			continue
		for row in _state.rows:
			var inverse := Transform3D(Basis(Vector3.UP, row.yaw), row.position).affine_inverse()
			var a: Vector3 = inverse * previous
			var b: Vector3 = inverse * now
			var mouth := AABB(Vector3(-0.86, 1.3, -0.88), Vector3(1.72, 0.95, 1.4))
			if not mouth.has_point(b) and mouth.intersects_segment(a, b) == null:
				continue
			if maxi(int(row.stored), 0) >= Store.capacity(row):
				continue
			var sync: Node = world_sync.props_sync
			if _mode == "host" and int(item.get_meta("mp_id", 0)) > 0 and not sync._mine(int(item.get_meta("mp_id"))) and not sync.host_take(item):
				continue
			var count: int = item.hay_strands()
			var moved := mini(count, Store.capacity(row) - int(row.stored))
			var needle: int = item.needle_index
			if moved <= 0 or (needle >= 0 and row.needles.has(needle)):
				continue
			if moved == count:
				world_sync.world.props.remove(item)
				if needle >= 0:
					row.needles.append(needle)
			else:
				item.set_strands(count - moved)
			Store.transfer(row, moved)
			_dirty = true
			break
	for id in _tracked.keys():
		if not alive.has(id):
			_tracked.erase(id)
	for row in _state.rows:
		var model: Node = _models.get(row.id)
		if not is_instance_valid(model) or not is_instance_valid(model.intake):
			continue
		for body in model.intake.get_overlapping_bodies():
			if row.stored >= Store.capacity(row):
				break
			if not is_instance_valid(body) or not body is RigidBody3D or body.get_parent() != world_sync.world.live or body.has_meta("needle_index") or body.freeze:
				continue
			if world_sync.world.live.consume(body):
				Store.transfer(row, 1)
				_dirty = true
