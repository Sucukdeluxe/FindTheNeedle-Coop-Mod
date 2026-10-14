extends Node

const Store = preload("res://mods/multiplayer/mp_hopper_state.gd")
const Model = preload("res://mods/multiplayer/mp_hopper_model.gd")
const BuildCamera = preload("res://mods/multiplayer/mp_build_camera.gd")
const BUILD_BOUNDS := AABB(Vector3(-0.9, -0.4, -0.9), Vector3(1.8, 2.0, 1.71))
const BUILD_ID := "mp_hopper"
const OUTPUT_INTERVAL := 0.1
const CONNECTION_TOLERANCE := 0.045
var mp: Node
var world_sync: Node
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

func start(session: Node, sync: Node) -> void:
	mp = session
	world_sync = sync
	ensure_catalog()
	if is_instance_valid(world_sync.builds) and not world_sync.builds.changed.is_connected(invalidate_connections):
		world_sync.builds.changed.connect(invalidate_connections)
	if not world_sync.economy.completed.is_connected(_completed):
		world_sync.economy.completed.connect(_completed)
	set_process(true)
	session_started()

func _role() -> String:
	if not is_instance_valid(mp) or not mp.active():
		return ""
	return "host" if mp.is_host else "guest"

func session_started() -> void:
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
	_state = Store.empty() if saved == null or saved == {} else saved.duplicate(true)
	_epoch = str(Time.get_ticks_usec()) + ":" + str(randi()) if mode == "host" else ""
	_seq = 0
	_seen = -1
	_statuses.clear()
	_tick = 0.0
	_publish = 0.0
	invalidate_connections()
	_rebuild_models()

func session_ended() -> void:
	if _mode == "host":
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

static func ensure_catalog() -> void:
	var entries: Dictionary = BuildCatalog.entries()
	var locale := TranslationServer.get_locale()
	if entries.has(BUILD_ID) and _catalog_locale == locale:
		return
	_catalog_locale = locale
	entries[BUILD_ID] = {"name": _tr("Einfülltrichter", "Loading Hopper"), "short": _tr("TRICHTER", "HOPPER"),
		"unlock": "belt", "category": "haulage", "mode": BuildTool.Mode.CONVEYOR,
		"cost": _tr("$2.500", "$2,500"), "place": _tr("Trichter am freien Bandanfang platzieren", "Place hopper at a free belt input"),
		"blurb": _tr("Speichert 50.000 Halme. Mit dem Hofsauger darauf zielen und M drücken. Gibt Heu nur bei Platz auf das Band aus.",
			"Stores 50,000 strands. Aim at it with the yard vacuum and press M. Releases hay only when the belt has room."),
		"note": _tr("rastet am freien Bandanfang ein", "snaps to a free belt input")}

func serialize() -> Dictionary:
	return _state.duplicate(true)

func restore(value: Dictionary) -> bool:
	if not Store.valid(value):
		return false
	_state = value.duplicate(true)
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
	_update_focus()
	if not mp.is_host or world_sync._frozen:
		return
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
				var moved := Store.output(row, portion, _insert.bind(path))
				_statuses[row.id] = "running" if moved > 0 else ("paused" if row.paused else "blocked")
				if moved > 0:
					_dirty = true
			if is_instance_valid(_models.get(row.id)):
				_models[row.id].set_fill(row.stored)
	_publish += delta
	if _dirty or _publish >= 2.0:
		_persist()
		send_all()
		_dirty = false
		_publish = 0.0

func _insert(count: int, path: Node) -> bool:
	if not is_instance_valid(path) or path.is_queued_for_deletion() or not path.is_inside_tree():
		return false
	var line: PackedVector3Array = path.centre_line()
	if line.size() < 2:
		return false
	var first: Vector3 = line[0]
	var along: Vector3 = (line[1] - first).normalized()
	var at := first + along * minf(0.4, first.distance_to(line[1]) * 0.5)
	var kind := BeltRun.Kind.WAD if count > 100 else BeltRun.Kind.TUFT
	return int(path.push_record(kind, count, -1, {"strands": count}, at, -1.0, 0.15)) >= 0

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

func candidate(camera: Transform3D, reach: float) -> Dictionary:
	var best := {}
	var best_score := INF
	var direction := -camera.basis.z.normalized()
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
		return {"ok": false, "reason": _tr("Auf einen freien, waagerechten Bandanfang zielen", "Aim at a free, level belt input")}
	var why := _placement_reason(best.path, best.position, best.yaw)
	best["ok"] = why == ""
	best["reason"] = why
	return best

func _placement_reason(path: Node, at: Vector3, yaw: float) -> String:
	if _state.rows.size() >= Store.LIMIT:
		return _tr("Maximal 32 Trichter", "Maximum 32 hoppers")
	for row in _state.rows:
		if row.position.distance_to(at) < 1.5:
			return _tr("Hier steht bereits ein Trichter", "A hopper is already placed here")
	for other in BeltPath._live:
		if is_instance_valid(other) and other != path and (other.downstream == path or other.end_deck == path):
			return _tr("Dieser Bandanfang ist bereits verbunden", "This belt input is already connected")
	var exclude: Array[RID] = []
	for body in path.find_children("*", "CollisionObject3D", true, false):
		exclude.append(body.get_rid())
	if path is CollisionObject3D:
		exclude.append(path.get_rid())
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
		return {"ok": false, "reason": _tr("Mehrspielersitzung erforderlich", "Multiplayer session required")}
	var ray := _local_build_ray(camera, reach)
	if ray.is_empty():
		return {"ok": false, "reason": _tr("Außerhalb des Baubereichs", "Outside the build area")}
	var row := candidate(ray.transform, float(ray.length))
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
	if row.is_empty() or row.stored >= Store.CAPACITY:
		world_sync.toast(_tr("Trichter voll", "Hopper full"))
		return true
	if int(vacuum.call("fill")) <= 0:
		world_sync.toast(_tr("Kein Heu im Hofsauger", "No hay in the yard vacuum"))
		return true
	var transfer: Node = world_sync.get("vacuum_transfer")
	if not is_instance_valid(transfer):
		world_sync.toast(_tr("Sauger wird synchronisiert", "Synchronizing vacuum"))
		return true
	var seq: int = transfer.submit(vacuum, "hopper_deposit", {"id": id, "body": world_sync.player.global_transform, "camera": world_sync.player.camera.global_transform}, Store.CAPACITY)
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
	if not _usable() or _mode != "host" or not world_sync.economy.executing or world_sync._frozen:
		return _failure(_tr("Aktion nicht verfügbar", "Action unavailable"))
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
	if row.is_empty() or not _near(peer, args, row.position, 7.0, action == "hopper_remove"):
		return _failure(_tr("Trichter außer Reichweite", "Hopper out of reach"))
	if action == "hopper_remove":
		if args.has("build_view") and _target_from_ray(_host_build_ray(peer, args)) != id:
			return _failure(_tr("Trichter nicht im Blick", "Hopper is not under the cursor"))
		if row.stored > 0:
			return _failure(_tr("Trichter vor dem Abbau vollständig leeren", "Empty the hopper before dismantling it"))
		_state.rows.erase(row)
		GameState.add_money(Store.COST * 0.5)
		_changed()
		return {"ok": true}
	if action == "hopper_deposit":
		var room: int = Store.CAPACITY - int(row.stored)
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
	if not _usable() or _mode != "host" or not world_sync.economy.executing or world_sync._frozen or amount <= 0:
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

func _place(peer: int, args: Dictionary) -> Dictionary:
	var at: Variant = args.get("position")
	var yaw: Variant = args.get("yaw")
	if not (at is Vector3) or not at.is_finite() or at.length() > 10000.0 or not (yaw is float or yaw is int) or not is_finite(float(yaw)) or absf(float(yaw)) > TAU:
		return _failure(_tr("Ungültige Position", "Invalid placement"))
	if not _near(peer, args, at, Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus() + 2.0, true):
		return _failure(_tr("Position außer Reichweite", "Placement out of reach"))
	var ray := _host_build_ray(peer, args) if args.has("build_view") else {"transform": args.camera, "length": Cfg.BUILD_REACH_MAX + Tech.build_reach_bonus()}
	var row := candidate(ray.transform, float(ray.length))
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
	_state.next_id += 1
	_state.rows.append({"id": id, "position": row.position, "yaw": float(row.yaw), "stored": 0, "paused": false})
	_changed()
	return {"ok": true, "hopper": id}

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
	var hit: Dictionary = world_sync.world.get_world_3d().direct_space_state.intersect_ray(query)
	var body: Variant = hit.get("collider")
	if not is_instance_valid(body):
		return 0
	var model: Variant = body.get_meta("mp_hopper", null)
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
	model.show_status(_tr("EINFÜLLTRICHTER", "LOADING HOPPER") + "\n" + _number(row.stored) + " / " + _number(Store.CAPACITY) + "\n" + status + "\n" + _tr("M · Hofsauger leeren     X halten · Abbauen", "M · Empty yard vacuum     Hold X · Dismantle"), true)

func _changed() -> void:
	_dirty = true
	invalidate_connections()
	_rebuild_models()
	_persist()
	send_all()

func _persist() -> void:
	if _storage_valid and _mode == "host":
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
		_models[row.id].set_fill(row.stored)
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
	if peer > 0:
		mp._rx_hoppers.rpc_id(peer, _epoch, _seq, data)
	else:
		for id in mp.players:
			if id != 1 and mp.players[id].get("state") == "world":
				mp._rx_hoppers.rpc_id(id, _epoch, _seq, data)

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
	_state = data.store.duplicate(true)
	_statuses = data.statuses.duplicate()
	_rebuild_models()

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _tr(de: String, en: String) -> String:
	return de if TranslationServer.get_locale().begins_with("de") else en

static func _number(value: int) -> String:
	var out := str(value)
	var separator := "." if TranslationServer.get_locale().begins_with("de") else ","
	var at := out.length() - 3
	while at > 0:
		out = out.insert(at, separator)
		at -= 3
	return out
