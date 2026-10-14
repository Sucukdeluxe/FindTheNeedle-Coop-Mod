extends HayStairs

func _follow_tech() -> void:
	super._follow_tech()
	if Tech.has_method("hay_stairs_speed_scale"):
		_speed *= float(Tech.call("hay_stairs_speed_scale"))
