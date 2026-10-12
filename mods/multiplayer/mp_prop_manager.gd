extends "res://scripts/items/prop_manager.gd"

var mp_props: Node

func _process(delta: float) -> void:
	if not is_instance_valid(mp_props) or not mp_props.mp.active():
		super._process(delta)
		return
	var local_settings := {}
	var policy: Dictionary = mp_props.cleanup_policy()
	for key in policy:
		local_settings[key] = Cfg.get(key)
		Cfg.set(key, policy[key])
	super._process(delta)
	for key in local_settings:
		Cfg.set(key, local_settings[key])

func _tuft_pass() -> void:
	if Cfg.auto_clean:
		super._tuft_pass()

func _drain_pass() -> void:
	if Cfg.auto_clean:
		super._drain_pass()


func to_array() -> Array:
	if not is_instance_valid(mp_props) or not mp_props.mp.active():
		return super.to_array()
	var original_items := items
	items = items.filter(func(item): return not is_instance_valid(item) or not mp_props.is_personal_tool_body(item))
	var data := super.to_array()
	items = original_items
	return data


func is_spoken_for(item: Carryable) -> bool:
	if is_instance_valid(mp_props) and is_instance_valid(mp_props.mp) and mp_props.mp.active() and preload("res://mods/multiplayer/mp_lift_cargo.gd").is_transported(item):
		return true
	return super.is_spoken_for(item)
