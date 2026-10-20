extends RoboticArm

func _exit_tree() -> void:
	if is_instance_valid(_payload_prop) and not _payload_prop.is_inside_tree():
		_payload_count = _payload.size()
		_payload_prop = null
	super._exit_tree()
