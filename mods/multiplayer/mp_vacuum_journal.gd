extends RefCounted

const PATH := "user://mp_vacuum_guest"
const MAX_BYTES := 1048576
var generation := 0
var state := {}
var _last := PackedByteArray()
var _files := {}
var error := ""

func read(profile: String) -> Dictionary:
	var found := false
	for slot in 2:
		var location := PATH + "." + str(slot) + ".dat"
		found = found or FileAccess.file_exists(location)
		var file := FileAccess.open(location, FileAccess.READ)
		if file == null:
			continue
		if file.get_length() < 4 or file.get_length() > MAX_BYTES:
			continue
		var declared := file.get_32()
		if declared == 0 or declared > file.get_length() - 4:
			continue
		file.seek(0)
		var outer: Variant = file.get_var(false)
		if not outer is Dictionary or outer.get("version") != 1 or not outer.get("generation") is int or outer.generation <= generation:
			continue
		if outer.get("profile") != profile or not outer.get("body") is PackedByteArray or not outer.get("digest") is String:
			continue
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(outer.body)
		if digest.finish().hex_encode() != outer.digest:
			continue
		var decoded: Variant = bytes_to_var(outer.body)
		if not decoded is Dictionary or not decoded.get("local") is Dictionary or not decoded.get("fills") is Dictionary:
			continue
		var valid: bool = decoded.fills.size() <= 128
		for realm in decoded.fills:
			var row: Variant = decoded.fills[realm]
			if not realm is String or realm.length() != 32 or not realm.is_valid_hex_number() or not row is Dictionary or not row.get("seed") is int or not row.get("fill") is int or row.fill < 0 or row.fill > 1000000:
				valid = false
		if not valid:
			continue
		generation = int(outer.generation)
		state = decoded
		_last = outer.body
	if found and state.is_empty():
		error = "Saved vacuum inventory could not be validated"
	return state.duplicate(true)

func write(profile: String, local: Dictionary, realm: String, seed: int, fill: int) -> bool:
	if error != "" or fill < 0 or fill > 1000000 or profile.length() != 32 or not profile.is_valid_hex_number() or realm.length() != 32 or not realm.is_valid_hex_number():
		return false
	var updated := state.duplicate(true)
	updated["local"] = local.duplicate(true)
	if not updated.has("fills"):
		updated["fills"] = {}
	updated.fills[realm] = {"seed": seed, "fill": fill}
	if updated.fills.size() > 128:
		error = "Too many saved vacuum inventories"
		return false
	var body := var_to_bytes(updated)
	if body == _last:
		return true
	if body.size() > MAX_BYTES / 2:
		error = "Saved vacuum inventory exceeds its size limit"
		return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(body)
	var next := generation + 1
	var slot := next % 2
	var file: FileAccess = _files.get(slot)
	if file == null:
		var location := PATH + "." + str(slot) + ".dat"
		file = FileAccess.open(location, FileAccess.READ_WRITE if FileAccess.file_exists(location) else FileAccess.WRITE_READ)
		if file != null:
			_files[slot] = file
	if file == null:
		error = "Could not write vacuum inventory"
		return false
	file.seek(0)
	file.store_var({"version": 1, "generation": next, "profile": profile, "body": body, "digest": digest.finish().hex_encode()})
	file.flush()
	var code := file.get_error()
	if code != OK:
		error = "Could not finish writing vacuum inventory"
		return false
	generation = next
	state = updated
	_last = body
	return true
