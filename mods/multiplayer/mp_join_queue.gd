extends RefCounted

const WAIT_MS := 60000
var pending := {}

func add(peer: int, pname: String, identity: String, now: int) -> void:
	if not pending.has(peer):
		pending[peer] = {"peer": peer, "name": pname, "identity": identity, "deadline": now + WAIT_MS}

func remove(peer: int) -> void:
	pending.erase(peer)

func clear() -> void:
	pending.clear()

func poll(players: Dictionary, identities: Dictionary, connected: PackedInt32Array, now: int) -> Dictionary:
	var occupied := {}
	for peer in players:
		if identities.has(peer):
			occupied[identities[peer]] = peer
	var ready := []
	var expired := []
	for peer in pending.keys():
		if not connected.has(peer) or players.has(peer):
			pending.erase(peer)
			continue
		var entry: Dictionary = pending[peer]
		if not occupied.has(entry.identity):
			occupied[entry.identity] = peer
			ready.append(entry)
			pending.erase(peer)
		elif now >= int(entry.deadline):
			expired.append(peer)
			pending.erase(peer)
	return {"ready": ready, "expired": expired}
