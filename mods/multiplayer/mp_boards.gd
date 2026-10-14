extends Node

# Paint boards.
#
# A board is placed and taken down like any building, but what is drawn on it
# lived only on the screen of whoever drew it. Now a finished stroke, an
# erase or a wipe goes to everyone, and their board shows the same picture.
#
# A drawing can be large, so it goes out in pieces of about a kilobyte.

const SCAN := 0.5
const SEND_DELAY := 0.3
const PIECE := 1000
const MAX_RAW := 4 << 20
const KEY_SLACK := 0.25

var mp: Node
var world: Node
var builds: Node
var _scan_t := 0.0
var _watched := {}   # board instance id -> true
var _due := {}       # board -> seconds until we send it
var _known := {}     # board instance id -> hash of the strokes last sent or received
var _applying := false
var _parts := {}     # "key|id" -> {n, raw, got: {i: bytes}}
var _next := 0
var _refresh := 0.0


func start(mp_node: Node, world_node: Node) -> void:
	mp = mp_node
	world = world_node
	builds = world.get("builds")


func shutdown() -> void:
	_due.clear()
	_parts.clear()


func _boards() -> Array:
	if builds == null or not is_instance_valid(builds):
		return []
	var arr: Variant = builds.get("paint_boards")
	return arr if arr is Array else []


func _key(b: Node3D) -> String:
	var p := b.global_position
	return "%.4f,%.4f,%.4f|%.5f" % [p.x, p.y, p.z, wrapf(b.rotation.y, -PI, PI)]


func _process(delta: float) -> void:
	if mp == null or not mp.active() or multiplayer.multiplayer_peer == null:
		return
	_refresh += delta
	if mp.is_host and _refresh >= 10.0:
		_refresh = 0.0
		for board in _boards():
			if is_instance_valid(board):
				_send(board, 0, true)
	for slot in _parts.keys():
		if Time.get_ticks_msec() - int(_parts[slot].get("time", 0)) > 15000:
			_parts.erase(slot)
	_scan_t += delta
	if _scan_t >= SCAN:
		_scan_t = 0.0
		for b in _boards():
			if is_instance_valid(b) and b.has_signal("drawing_changed"):
				var id: int = b.get_instance_id()
				if not _watched.has(id):
					_watched[id] = true
					b.drawing_changed.connect(_on_changed.bind(b))
	for b in _due.keys():
		_due[b] = float(_due[b]) - delta
		if float(_due[b]) <= 0.0:
			_due.erase(b)
			if is_instance_valid(b):
				_send(b, 0)


func _on_changed(b: Node) -> void:
	if _applying or not is_instance_valid(b):
		return
	# wait for the stroke to settle, a wipe and a redraw often come together
	_due[b] = SEND_DELAY


func _send(b: Node, pid: int, force: bool = false) -> void:
	var strokes: Array = b.visible_strokes()
	var h := hash(strokes)
	if not force and pid == 0 and int(_known.get(b.get_instance_id(), 0)) == h:
		return
	_known[b.get_instance_id()] = h
	var raw := var_to_bytes(strokes)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	_next += 1
	var id := multiplayer.get_unique_id() * 100000 + _next
	var n := int(ceil(float(packed.size()) / PIECE))
	for i in maxi(n, 1):
		var piece := packed.slice(i * PIECE, mini((i + 1) * PIECE, packed.size()))
		if pid > 0:
			mp._rx_board.rpc_id(pid, _key(b as Node3D), id, i, maxi(n, 1), raw.size(), piece, mp._outgoing_world_seed())
		elif not mp.is_host:
			mp._rx_board.rpc_id(1, _key(b as Node3D), id, i, maxi(n, 1), raw.size(), piece, mp._outgoing_world_seed())
		else:
			mp._rx_board.rpc(_key(b as Node3D), id, i, maxi(n, 1), raw.size(), piece, mp._outgoing_world_seed())


# Host: a player just came in, show them every board as it is.
func send_all(pid: int) -> void:
	for b in _boards():
		if is_instance_valid(b):
			_send(b, pid)


func on_piece(key: String, id: int, i: int, n: int, raw_size: int, piece: PackedByteArray) -> void:
	if n <= 0 or n > 4096 or i < 0 or i >= n or piece.size() > PIECE or raw_size <= 0 or raw_size > MAX_RAW:
		return
	var slot := "%s|%d" % [key, id]
	var e: Dictionary = _parts.get(slot, {"n": n, "raw": raw_size, "got": {}, "time": Time.get_ticks_msec()})
	if int(e["n"]) != n or int(e["raw"]) != raw_size:
		_parts.erase(slot)
		return
	(e["got"] as Dictionary)[i] = piece
	_parts[slot] = e
	if (e["got"] as Dictionary).size() < n:
		return
	_parts.erase(slot)
	var packed := PackedByteArray()
	for k in n:
		if not (e["got"] as Dictionary).has(k):
			return
		packed.append_array((e["got"] as Dictionary)[k])
	var strokes: Variant = bytes_to_var(packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD))
	if not (strokes is Array):
		return
	var b := _board_at(key)
	if b == null:
		return
	_known[b.get_instance_id()] = hash(strokes)
	_applying = true
	b.set_picture(strokes)
	_applying = false
	if mp.is_host:
		_send(b, 0, true)


func _board_at(key: String) -> Node:
	for board in _boards():
		if is_instance_valid(board) and _key(board) == key:
			return board
	return null
