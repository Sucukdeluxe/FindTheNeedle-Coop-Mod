extends "res://scripts/build/haystack_scanner.gd"

var mp_transport: Node

func _mp_service() -> Node:
	if not is_instance_valid(mp_transport) or not is_instance_valid(mp_transport.mp) or not mp_transport.mp.active():
		return null
	var sync: Node = mp_transport.mp.world_sync
	return sync.scanner_sync if is_instance_valid(sync) else null

func take_banked(index: int) -> bool:
	var service := _mp_service()
	if service != null and not service.mp.is_host:
		service.request(self, "take", index)
		return false
	var taken := super.take_banked(index)
	if taken and service != null:
		service.changed()
	return taken

func rebank(index: int) -> void:
	var service := _mp_service()
	if service != null and not service.mp.is_host:
		return
	super.rebank(index)
	if service != null:
		service.changed()

func dispense() -> void:
	var service := _mp_service()
	if service != null and not service.mp.is_host:
		service.request(self, "collect", -1)
		return
	super.dispense()

func _spill() -> void:
	var service := _mp_service()
	if service != null and not service.mp.is_host:
		return
	super._spill()
	if service != null:
		service.changed()

func _all_needles() -> PackedInt32Array:
	var indices := super._all_needles()
	var service := _mp_service()
	if service != null and service.mp.is_host:
		for index in service.reserved(self):
			if not indices.has(index):
				indices.append(index)
	return indices
