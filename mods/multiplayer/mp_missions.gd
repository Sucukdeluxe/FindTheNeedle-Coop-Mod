extends "res://scripts/world/mission_director.gd"

var mp_world: Node
var remote_completed := {}


func is_done(id: String) -> bool:
	if _completed_remotely(id):
		return true
	return super.is_done(id)


func _has_been_read(index: int) -> bool:
	if index >= 0 and index < MissionBook.count() and _completed_remotely(MissionBook.id_at(index)):
		return true
	return super._has_been_read(index)


func _completed_remotely(id: String) -> bool:
	return is_instance_valid(mp_world) and mp_world.mp.active() and mp_world.mp.is_host and remote_completed.has(id)
