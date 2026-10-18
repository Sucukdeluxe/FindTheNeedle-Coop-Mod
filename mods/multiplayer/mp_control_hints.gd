extends "res://scripts/ui/control_hints.gd"

const I18n = preload("res://mods/multiplayer/mp_i18n.gd")

func _hints() -> Array[PackedStringArray]:
	var rows := super._hints()
	if not is_instance_valid(player) or player.menu_is_up():
		return rows
	var mp := get_node_or_null("/root/MPMod")
	if not is_instance_valid(mp) or not is_instance_valid(mp.world_sync):
		return rows
	var hoppers: Node = mp.world_sync.hoppers_sync
	if not is_instance_valid(hoppers) or not is_instance_valid(hoppers.sale_stations):
		return rows
	var supply: Node = hoppers.get("supply_station")
	if is_instance_valid(supply) and supply.target_id(true) == 1 and player.build_id != supply.move_build_id():
		var supply_key: Key = supply.move_key()
		if supply_key != KEY_NONE:
			rows.push_front(PackedStringArray(["press:key:" + OS.get_keycode_string(supply_key), I18n.phrase("Supply Co versetzen", "Move Supply Co")]))
		return rows
	var service: Node = hoppers.sale_stations
	var id: int = service.target_id(true)
	if id == 0 or player.build_id == service.MOVE_ID:
		return rows
	var key: Key = service.move_key()
	if key != KEY_NONE:
		var label := I18n.phrase("Verkaufsstelle versetzen", "Move sale station") if service.model(id).mp_can_move() else I18n.phrase("Verkaufsstelle zuerst leeren", "Empty the sale station first")
		rows.push_front(PackedStringArray(["press:key:" + OS.get_keycode_string(key), label]))
	rows.push_front(PackedStringArray(["press:interact", I18n.phrase("Verkaufsstelle einstellen", "Sale station settings")]))
	return rows
