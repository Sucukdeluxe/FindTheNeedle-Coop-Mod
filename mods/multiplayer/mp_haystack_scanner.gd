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
		var sync: Node = service.world_sync
		var peer: int = service.claiming_peer
		sync._holder[index] = peer
		sync._apply_needle("claim", index, Vector3.ZERO, peer)
		sync._needle_out("claim", index, Vector3.ZERO, peer)
		service.changed()
	return taken

func rebank(index: int) -> void:
	var service := _mp_service()
	if service != null and not service.mp.is_host:
		return
	if service != null and service.world_sync._holder_of(index) == 1:
		service.world_sync._holder.erase(index)
		service.world_sync._apply_needle("gone", index, Vector3.ZERO, 0)
		service.world_sync._needle_out("gone", index, Vector3.ZERO, 0)
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

func _bank(index: int) -> void:
	var service := _mp_service()
	if service != null and is_instance_valid(service.world_sync.needles_sync):
		if not service.world_sync.needles_sync.can_bank(index, self):
			return
	super._bank(index)
	if service != null:
		service.changed()
