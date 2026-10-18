extends "res://autoload/input_setup.gd"

const ACTION := "mp_parallel"
const LABELS := ["Parallel conveyor mode", "Förderband-Parallelmodus", "Modo paralelo de cintas", "Mode convoyeurs parallèles", "Modalità nastri paralleli", "Režim rovnoběžných pásů", "Tryb równoległych przenośników", "Режим параллельных конвейеров", "Paralel konveyör modu", "コンベア並列モード", "컨베이어 평행 모드", "传送带平行模式", "Modo de esteiras paralelas", "Режим паралельних конвеєрів", "وضع السيور المتوازية", "حالت نوار نقاله موازی", "輸送帶平行模式"]

func install() -> void:
	_row_of[ACTION] = ACTION
	_load()
	apply()

func offered_rows() -> Array[Dictionary]:
	var rows := super.offered_rows()
	var at := rows.size()
	for i in rows.size():
		if str(rows[i].actions[0]) == "build_grid_lock":
			at = i + 1
	rows.insert(at, {"group": "BUILDING", "label": row_label(ACTION), "actions": [ACTION]})
	return rows

func apply() -> void:
	super.apply()
	_install(ACTION)

func _events_for(action: String) -> Array[InputEvent]:
	if action != ACTION:
		return super._events_for(action)
	var out: Array[InputEvent] = []
	var event := event_from_spec(binding(ACTION))
	if event != null:
		out.append(event)
	return out

func binding(row: String) -> String:
	return str(_override.get(row, default_binding(row))) if row == ACTION else super.binding(row)

func default_binding(row: String) -> String:
	return spec_from_event(key_event(KEY_F9)) if row == ACTION else super.default_binding(row)

func specs(row: String) -> PackedStringArray:
	if row != ACTION:
		return super.specs(row)
	var spec := binding(row)
	return PackedStringArray() if spec.is_empty() else PackedStringArray([spec])

func is_default(row: String) -> bool:
	return binding(row) == default_binding(row) if row == ACTION else super.is_default(row)

func row_label(row: String) -> String:
	if row != ACTION:
		return super.row_label(row)
	var locale := preload("res://mods/multiplayer/mp_i18n.gd").new().locale()
	var index: int = preload("res://mods/multiplayer/mp_lobby_i18n.gd").LANGUAGES.find(locale)
	return LABELS[maxi(index, 0)]

func holder(spec: String, ignoring: String = "") -> String:
	if ignoring != ACTION and not spec.is_empty() and spec in specs(ACTION):
		return ACTION
	return super.holder(spec, ignoring)

func bind(row: String, spec: String) -> PackedStringArray:
	var taken := PackedStringArray()
	if row != ACTION and not spec.is_empty() and spec in specs(ACTION):
		_override[ACTION] = ""
		taken.append(row_label(ACTION))
	taken.append_array(super.bind(row, spec))
	return taken

func _yield_defaults_to_choices() -> void:
	super._yield_defaults_to_choices()
	if _override.has(ACTION):
		return
	var default := default_binding(ACTION)
	for row in _override:
		if row != ACTION and str(_override[row]) == default:
			_override[ACTION] = ""
			return
