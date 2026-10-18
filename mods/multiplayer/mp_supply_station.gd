extends "res://mods/multiplayer/mp_sale_stations.gd"

const SUPPLY_MOVE_ID := "mp_supply_move"
var _footprint := AABB(Vector3(-4.65, 0.06, -1.7), Vector3(8.4, 3.8, 5.5))

static func ensure_supply_catalog() -> void:
	BuildCatalog.entries()[SUPPLY_MOVE_ID] = {"name": _tr("Supply Co versetzen", "Move Supply Co"), "short": _tr("VERSETZEN", "MOVE"),
		"unlock": "", "category": "haulage", "mode": BuildTool.Mode.CONVEYOR,
		"cost": "$0", "place": _tr("Supply Co auswählen und versetzen", "Select and move Supply Co"),
		"blurb": _tr("Linksklick · Platzieren    Rechtsklick · Abbrechen", "Left-click · Place    Right-click · Cancel")}

func move_build_id() -> String:
	return SUPPLY_MOVE_ID

func _station_meta() -> String:
	return "mp_supply_station"

func _station_can_move(station: Node3D) -> bool:
	return is_instance_valid(station)

func _request_action(action: String) -> String:
	return "supply_move" if action == "sale_move" else ""

func session_started() -> void:
	var mode: String = hoppers._role()
	if mode == _mode:
		return
	if _mode != "":
		session_ended()
	_mode = mode
	var shop: Node3D = world_sync.world.shop
	if not is_instance_valid(shop):
		_valid = false
		return
	var saved: Variant = GameState.get("mp_supply_station")
	_valid = saved == null or saved == {} or _valid_state(saved)
	if not _valid:
		return
	_state = Store.fresh(shop.global_position, shop.global_rotation.y) if saved == null or saved == {} else saved.duplicate(true)
	_models[1] = shop
	var bounds := AABB()
	var first := true
	var inverse := shop.global_transform.affine_inverse()
	for mesh in shop.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var part: AABB = inverse * mesh.global_transform * mesh.get_aabb()
		bounds = part if first else bounds.merge(part)
		first = false
	if not first:
		_footprint = AABB(Vector3(bounds.position.x, 0.06, bounds.position.z), Vector3(bounds.size.x, maxf(0.1, bounds.end.y - 0.06), bounds.size.z))
	_rebuild_models()
	_persist()

static func _valid_state(value: Variant) -> bool:
	return Store.valid(value) and value.rows.size() == 1 and value.rows[0].id == 1 and value.next_id == 2

func _persist() -> void:
	if _valid and _mode in ["offline", "host"] and not _state.is_empty():
		GameState.set("mp_supply_station", serialize())

func on_state(value: Variant) -> void:
	if not _usable() or _mode != "guest" or not _valid_state(value):
		return
	_state = value.duplicate(true)
	_rebuild_models()

func _rebuild_models() -> void:
	var shop := model(1)
	if not is_instance_valid(shop) or _state.is_empty():
		return
	var row := _row(1)
	shop.global_transform = Transform3D(Basis(Vector3.UP, float(row.yaw)), row.position)
	shop.reset_physics_interpolation()
	for body in shop.find_children("*", "CollisionObject3D", true, false):
		body.set_meta(_station_meta(), 1)
	var menu: Node = world_sync.world.shop_menu
	if is_instance_valid(menu) and menu.get("_open") == true and not menu.is_near_shop():
		menu.set_open(false)

func _refresh_links() -> void:
	pass

func _bounds(_id: int) -> AABB:
	return _footprint

func _placement_reason(at: Vector3, yaw: float, _moving: int) -> String:
	var shape := BoxShape3D.new()
	shape.size = _footprint.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), at).translated_local(_footprint.get_center())
	query.collision_mask = Cfg.L_WORLD | Cfg.L_BUILD | Cfg.L_PILE
	query.margin = 0.01
	query.exclude = _station_bodies(1)
	if not world_sync.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return _tr("Hier ist kein Platz für Supply Co", "There is no room for Supply Co here")
	return ""

func build_candidate(camera: Transform3D, reach: float) -> Dictionary:
	if _usable() and _moving_id == 0:
		return {"ok": false, "reason": _tr("Supply Co zum Versetzen auswählen", "Select Supply Co to move it")}
	return super.build_candidate(camera, reach)

func begin_move(id: int) -> void:
	if id != 1:
		return
	ensure_supply_catalog()
	super.begin_move(id)

func execute(peer: int, action: String, args: Dictionary) -> Dictionary:
	if action != "supply_move" or args.get("id") != 1:
		return _failure(_tr("Ungültige Aktion für Supply Co", "Invalid Supply Co action"))
	var result := super.execute(peer, "sale_move", args)
	if result.get("message", "") == _tr("Verkaufsstelle wurde geändert oder ist außer Reichweite", "Sale station changed or out of reach"):
		result.message = _tr("Supply Co wurde geändert oder ist außer Reichweite", "Supply Co changed or is out of reach")
	return result

func _input(event: InputEvent) -> void:
	if not _usable() or event.is_echo() or world_sync._frozen:
		return
	var key := move_key()
	if key == KEY_NONE or not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed or (event.physical_keycode != key and event.keycode != key):
		return
	var id := target_id(true)
	if id == 1:
		begin_move(id)
		get_viewport().set_input_as_handled()
