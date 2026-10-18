extends "res://scripts/build/needle_cabinet.gd"

var mp_needles: Node

func factory_tick(delta: float) -> void:
	if is_instance_valid(mp_needles) and mp_needles.mp.active() and not mp_needles.mp.is_host:
		return
	super.factory_tick(delta)

func prompt() -> String:
	var original := super.prompt()
	if int(GameState.mp_prestige.get("cycles", 0)) == 0:
		return original
	return original + "\n" + preload("res://mods/multiplayer/mp_prestige_state.gd").current_progress(GameState, NeedleTypes.pool(Cfg.DEMO_LAST_LOT), TranslationServer.get_locale())
