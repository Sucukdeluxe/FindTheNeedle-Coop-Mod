extends Node

const State = preload("res://mods/multiplayer/mp_diagnostic_state.gd")
const PATH := "user://mp_diagnostics.jsonl"
const PREV := "user://mp_diagnostics.prev.jsonl"
const MAX_BYTES := 524288
const TICK := 2.0
const GRACE_MS := 10000
const CATEGORIES := ["belts", "props", "buildings", "hay", "economy", "tools", "state", "machines"]

var mp: Node
var sync: Node
var state = State.new()
var _file: FileAccess
var _tick := 0.0
var _ready_at := 0
var _notified_at := -60000
var _running := false
var _observed_at := {}

func _ready() -> void:
	sync = get_parent()
	mp = sync.mp

func _available() -> bool:
	return mp.active() and (mp.is_host or mp.phase == mp.Phase.IN_WORLD) and not sync._frozen and not sync._applying_builds and not sync._builds_dirty

func _process(delta: float) -> void:
	if not _available():
		state.reset()
		_observed_at.clear()
		_ready_at = Time.get_ticks_msec() + GRACE_MS
		return
	var now := Time.get_ticks_msec()
	if not _running:
		_running = true
		_ready_at = now + GRACE_MS
		_open()
		_write({"event": "session", "version": mp.VERSION, "role": "host" if mp.is_host else "guest"})
	if now < _ready_at:
		return
	_tick += delta
	if _tick < TICK:
		return
	_tick = 0.0
	for channel in _observed_at.keys():
		if now - int(_observed_at[channel]) > 15000:
			state.entries.erase(channel)
			_observed_at.erase(channel)
	if is_instance_valid(sync.economy):
		_pending("economy", sync.economy.pending.keys(), now)
	if is_instance_valid(sync.tools_sync):
		_pending("tools", sync.tools_sync._pending.keys(), now)
		var inventory_matches: bool = sync.tools_sync.diagnostic_inventory == sync.tools_sync._local()
		observe("tools", not inventory_matches, 0 if inventory_matches else 1)
	if not mp.is_host:
		var sequences: Array = []
		for entry in sync._st_pending:
			sequences.append(entry[0])
		_pending("state", sequences, now)

func observe(category: String, bad: bool, count: int, scope: int = 0) -> void:
	var now := Time.get_ticks_msec()
	if not _running or not _available() or now < _ready_at or category not in CATEGORIES:
		return
	var channel := category + ":" + str(scope)
	if now - int(_observed_at.get(channel, -2000)) < 2000:
		return
	_observed_at[channel] = now
	_emit(category, state.observe(channel, bad, count, now), now)

func _pending(category: String, ids: Array, now: int) -> void:
	_emit(category, state.pending(category, ids, now), now)

func _emit(category: String, event: Dictionary, now: int) -> void:
	if event.is_empty():
		return
	_write({"event": event["state"], "category": category, "count": int(event["count"])})
	if event["state"] == "mismatch" and now - _notified_at >= 60000:
		_notified_at = now
		if is_instance_valid(mp.ui):
			mp.ui.notify(mp.t("sync_diagnostic_warning"))

func _open() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(PATH.get_file()):
		if dir.file_exists(PREV.get_file()):
			dir.remove(PREV.get_file())
		dir.rename(PATH.get_file(), PREV.get_file())
	_file = FileAccess.open(PATH, FileAccess.WRITE)

func _write(event: Dictionary) -> void:
	if _file == null:
		return
	if _file.get_length() >= MAX_BYTES:
		_file.close()
		_open()
	event["time_ms"] = Time.get_ticks_msec()
	if _file != null:
		_file.store_line(JSON.stringify(event))
		_file.flush()

func _exit_tree() -> void:
	if _file != null:
		_write({"event": "session_end"})
		_file.close()

func check_belts(entries: Array) -> void:
	var now := Time.get_ticks_msec()
	if not _running or not _available() or now < _ready_at or now - int(_observed_at.get("belts:0", -2000)) < 2000:
		return
	var expected: Array = []
	for entry in entries:
		expected.append_array(entry.get("records", []))
	var actual: Array = []
	for belt in BeltPath._live:
		if not is_instance_valid(belt) or not belt.is_inside_tree():
			continue
		for i in range(belt.run.first(), belt.run.first() + belt.run.count()):
			actual.append(belt.run.record(i))
	var wanted := State.cargo(expected)
	var received := State.cargo(actual)
	observe("belts", wanted != received, absi(expected.size() - actual.size()) if expected.size() != actual.size() else 1 if wanted != received else 0)
