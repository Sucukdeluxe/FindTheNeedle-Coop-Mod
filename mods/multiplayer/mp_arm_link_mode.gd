extends "res://scripts/ui/arm_link_mode.gd"

const ArmRoutes = preload("res://mods/multiplayer/mp_arm_routes.gd")

var mp_economy: Node
var _hopper_id := 0
var _ring: MeshInstance3D

func _service() -> Node:
	return mp_economy.world_sync.hoppers_sync if is_instance_valid(mp_economy) else null

func _aim() -> void:
	super._aim()
	_hopper_id = 0
	if is_instance_valid(_arm):
		var origin := player.eye_position()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + player.look_direction() * AIM_DIST, Cfg.L_BUILD)
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var path := ArmRoutes.from_hit(hit.collider, hit.position)
			if path != null:
				_hover = path
				_hover_at = ArmRoutes.point(path, hit.position)
				_hover_ok = _arm.link_in_reach(_hover_at)
				_refused = REFUSE_NONE
				_refused_run = null
	var service := _service()
	if not is_instance_valid(service) or not is_instance_valid(_arm):
		return
	var ray := {"origin": player.eye_position(), "direction": player.look_direction(), "length": AIM_DIST}
	_hopper_id = service._target_from_ray(ray)
	if _hopper_id == 0:
		return
	var row: Dictionary = service._row(_hopper_id)
	_hover = null
	_refused = REFUSE_NONE
	_hover_ok = _arm.link_in_reach(service.arm_point(row, _arm))

func _click(role: int) -> void:
	if _hopper_id <= 0:
		if ArmRoutes.owner_of(_hover) != null and role == RoboticArm.LINK_PUT:
			_hover = ArmRoutes.drop_path(_hover, _hover_at)
			_hover_at = ArmRoutes.point(_hover, _hover_at, true)
			_hover_ok = _arm.link_in_reach(_hover_at)
		super._click(role)
		return
	if _hover_ok and role == RoboticArm.LINK_PUT:
		_service().request_arm_link(_hopper_id, _arm)
		Audio.play("ui_click")
	else:
		Audio.play("ui_error")

func _draw() -> void:
	super._draw()
	if not is_instance_valid(_ring):
		_ring = MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.76
		ring.outer_radius = 0.79
		_ring.mesh = ring
		_ring.top_level = true
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ring)
	_ring.visible = _hopper_id > 0
	if _hopper_id > 0:
		var row: Dictionary = _service()._row(_hopper_id)
		_ring.global_position = row.position + Vector3.UP * 1.65
		_ring.material_override = _mat(COL_SOLID if _hover_ok else COL_OUT)

func _write_hint() -> void:
	if _hopper_id <= 0:
		super._write_hint()
		if ArmRoutes.owner_of(_hover) != null and _hover_ok:
			_hint_sub.text = "Linksklick: Ladung aufnehmen · Rechtsklick: am Eingang ablegen" if TranslationServer.get_locale().begins_with("de") else "Left click: pick up cargo · Right click: deliver to the inlet"
		return
	_hint_sub.text = _service()._tr("Rechtsklick: Trichter als Ablage verbinden oder lösen", "Right click: link or unlink hopper as drop destination") if _hover_ok else _service()._tr("Trichter außerhalb der Armreichweite", "Hopper outside arm reach")

func end(reopen: bool) -> void:
	if is_instance_valid(_ring):
		_ring.hide()
	_hopper_id = 0
	super.end(reopen)
