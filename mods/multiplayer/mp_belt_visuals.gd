extends "res://scripts/build/belt_run_batch.gd"

const NATIVE_RENDERER = preload("res://scripts/build/belt_run_batch.gd")
const STABLE_HAY_DISTANCE := 1.0e20


static func install_current(patch: Script) -> void:
	var batch: Node = NATIVE_RENDERER.active()
	if not is_instance_valid(batch) or batch.get_script() != NATIVE_RENDERER:
		return
	var saved := {}
	for property in batch.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			saved[property.name] = batch.get(property.name)
	batch.set_script(patch)
	for key in saved:
		batch.set(key, saved[key])
	for kind in batch._kinds:
		batch._stabilize_hay(kind, batch._kinds[kind])


func _kind_draw(kind: int) -> RefCounted:
	var draw: RefCounted = super._kind_draw(kind)
	_stabilize_hay(kind, draw)
	return draw


func _stabilize_hay(kind: int, draw: RefCounted) -> void:
	if kind not in [0, 1] or draw == null or draw.cuts.is_empty():
		return
	draw.cuts[0] = STABLE_HAY_DISTANCE
