extends RefCounted

static func commit(saves: Node, before: Dictionary, after: Dictionary, token: String) -> Dictionary:
	if token.length() != 32 or not token.is_valid_hex_number() or saves.block_save:
		return _unchanged("preflight")
	if str(after.get("state", {}).get("mp_prestige", {}).get("last_transaction", "")) != token:
		return _unchanged("transaction")
	var slot: int = saves.current_slot
	var path: String = saves.slot_path(slot)
	var secondary: String = saves.backup_path(slot)
	if path == secondary:
		return _unchanged("paths")
	var main_before := _read_image(path)
	var backup_before := _read_image(secondary)
	if not main_before.ok or not backup_before.ok:
		return _unchanged("read")
	var initial: Dictionary = saves._inspect(slot)
	var current: Dictionary = saves._read(slot)
	if str(current.get("state", {}).get("mp_prestige", {}).get("last_transaction", "")) == token:
		return {"ok": true, "replayed": true, "unchanged": true, "requires_recovery": false}
	var folder := path.get_base_dir().path_join("prestige-backups")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		return _unchanged("directory")
	var backup := folder.path_join("slot_%d_%s.snapshot" % [slot, token])
	if not _backup_image(backup + ".original", main_before) or not _backup_image(backup + ".backup", backup_before):
		return _unchanged("backup", backup)
	if not _backup_snapshot(backup, before):
		return _unchanged("snapshot", backup)
	var quarantine := ""
	if bool(initial.get("from_backup", false)) and main_before.exists:
		quarantine = path + ".prestige-source-" + token
		if FileAccess.file_exists(quarantine) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(quarantine)):
			return _unchanged("quarantine_exists", backup)
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(quarantine)) != OK:
			return _failed("quarantine", backup, _restore_pair(path, main_before, secondary, backup_before, token))
	if not saves._write_payload(slot, after):
		return _finish(_failed("write", backup, _restore_pair(path, main_before, secondary, backup_before, token)), quarantine)
	var inspected: Dictionary = saves._inspect(slot)
	var actual: Variant = inspected.get("data")
	if not bool(inspected.get("from_backup", true)) and actual is Dictionary and var_to_bytes(actual) == var_to_bytes(after):
		return _finish({"ok": true, "backup": backup, "restored": false, "requires_recovery": false}, quarantine)
	return _finish(_failed("verify", backup, _restore_pair(path, main_before, secondary, backup_before, token)), quarantine)

static func _finish(result: Dictionary, quarantine: String) -> Dictionary:
	if quarantine != "":
		if bool(result.get("ok", false)) or bool(result.get("restored", false)):
			result["cleanup_pending"] = DirAccess.remove_absolute(ProjectSettings.globalize_path(quarantine)) != OK
		else:
			result["recovery_source"] = quarantine
	return result

static func _unchanged(stage: String, backup := "") -> Dictionary:
	return {"ok": false, "unchanged": true, "restored": true, "requires_recovery": false, "stage": stage, "backup": backup}

static func _failed(stage: String, backup: String, restored: bool) -> Dictionary:
	return {"ok": false, "unchanged": false, "restored": restored, "requires_recovery": not restored, "stage": stage, "backup": backup}

static func _read_image(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			return {"ok": false, "exists": true, "bytes": PackedByteArray()}
		return {"ok": true, "exists": false, "bytes": PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "exists": true, "bytes": PackedByteArray()}
	var length := file.get_length()
	var data := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	return {"ok": data.size() == length and error in [OK, ERR_FILE_EOF], "exists": true, "bytes": data}

static func _write_image(path: String, data: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(data)
	file.flush()
	var error := file.get_error()
	file.close()
	var actual := _read_image(path)
	return error == OK and actual.ok and actual.exists and actual.bytes == data

static func _backup_image(path: String, image: Dictionary) -> bool:
	if not image.exists:
		return true
	if FileAccess.file_exists(path):
		var previous := _read_image(path)
		return previous.ok and previous.bytes == image.bytes
	return _write_image(path, image.bytes)

static func _backup_snapshot(path: String, data: Dictionary) -> bool:
	if not FileAccess.file_exists(path):
		var output := FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			return false
		output.store_var(data, false)
		output.flush()
		var error := output.get_error()
		output.close()
		if error != OK:
			return false
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return false
	var restored: Variant = input.get_var(false)
	input.close()
	return restored is Dictionary and var_to_bytes(restored) == var_to_bytes(data)

static func _restore_pair(path: String, main: Dictionary, secondary: String, backup: Dictionary, token: String) -> bool:
	if backup.exists and not _restore_image(secondary, backup, token):
		return false
	if not _restore_image(path, main, token):
		return false
	return backup.exists or _restore_image(secondary, backup, token)

static func _restore_image(path: String, image: Dictionary, token: String) -> bool:
	var actual := _read_image(path)
	if not actual.ok:
		return false
	if not image.exists:
		return not actual.exists or DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
	if actual.exists and actual.bytes == image.bytes:
		return true
	var staged := path + ".prestige-restore-" + token
	if not _write_image(staged, image.bytes):
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(staged), ProjectSettings.globalize_path(path)) != OK:
		return false
	actual = _read_image(path)
	return actual.ok and actual.exists and actual.bytes == image.bytes
