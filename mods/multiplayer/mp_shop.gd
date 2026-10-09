extends "res://scripts/ui/shop_menu.gd"

var mp_economy: Node

func _on_buy(id: String) -> void:
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		super._on_buy(id)
		return
	if not _open or not is_near_shop():
		return
	if not ItemDb.is_unlocked(id):
		_show_locked(id)
		return
	mp_economy.request("buy", {"id": id, "body": player.global_transform,
		"camera": player.camera.global_transform, "max_price": ItemDb.price(id)})

func _on_sell(id: String) -> void:
	if not is_instance_valid(mp_economy) or not mp_economy.mp.active():
		super._on_sell(id)
		return
	if not _open or not is_near_shop():
		return
	var item := _spare_to_sell(id)
	if not is_instance_valid(item):
		_status(mp_economy.mp.t("shared_tool_sale"), false)
		return
	mp_economy.request("sell", {"id": id, "item": int(item.get_meta("mp_id", 0)),
		"body": player.global_transform, "camera": player.camera.global_transform})
