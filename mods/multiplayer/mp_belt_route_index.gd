extends RefCounted

const Routes = preload("res://mods/multiplayer/mp_belt_routes.gd")

var _signature: Array = []
var _paths: Array = []
var _index: Dictionary = {}

func get_index(sync: Node, paths: Array) -> Dictionary:
	var signature := [sync.world.get_instance_id(), YardPorts.epoch]
	if signature == _signature and paths == _paths:
		return _index
	_signature = signature
	_paths = paths.duplicate()
	_index = Routes.index(sync, paths)
	return _index

func clear() -> void:
	_signature.clear()
	_paths.clear()
	_index.clear()
