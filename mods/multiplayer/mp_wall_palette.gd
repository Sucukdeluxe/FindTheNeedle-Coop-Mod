extends RefCounted

const COLORS := [Color.WHITE, Color(0.23, 0.25, 0.27), Color(0.88, 0.83, 0.69), Color(0.55, 0.19, 0.15), Color(0.25, 0.37, 0.26)]
const KEYS := ["", "charcoal", "cream", "red", "green"]
const BASE_IDS := ["wall", "wall_window", "wall_door"]

static func color(index: int) -> Color:
	return COLORS[clampi(index, 0, COLORS.size() - 1)]

static func index(id: String) -> int:
	for i in range(1, KEYS.size()):
		if id in ids_for(i):
			return i
	return 0

static func ids_for(index: int) -> Array[String]:
	var ids: Array[String] = []
	for base in BASE_IDS:
		ids.append("mp_%s_%s" % [base, KEYS[index]])
	return ids

static func base_id(id: String) -> String:
	for base in BASE_IDS:
		for i in range(1, KEYS.size()):
			if id == "mp_%s_%s" % [base, KEYS[i]]:
				return base
	return id

static func ensure_catalog() -> void:
	var entries: Dictionary = BuildCatalog.entries()
	var ordered := {}
	var text := preload("res://mods/multiplayer/mp_i18n.gd")
	var names := ["", text.phrase("Anthrazit", "Charcoal"), text.phrase("Creme", "Cream"), text.phrase("Rot", "Red"), text.phrase("Grün", "Green")]
	for id in entries:
		if index(str(id)) > 0:
			continue
		ordered[id] = entries[id]
		if id not in BASE_IDS:
			continue
		for i in range(1, KEYS.size()):
			var entry: Dictionary = entries[id].duplicate(true)
			entry.name = "%s · %s" % [entry.name, names[i]]
			entry.short = "%s · %s" % [entry.short, names[i].to_upper()]
			ordered["mp_%s_%s" % [id, KEYS[i]]] = entry
	BuildCatalog._entries = ordered

static func apply(wall: YardWall, index: int) -> YardWall:
	if not is_instance_valid(wall):
		return wall
	var replacement := load("res://mods/multiplayer/mp_yard_wall.gd") as Script
	if wall.get_script() != replacement:
		var values := {}
		for property in wall.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				values[property.name] = wall.get(property.name)
		wall.set_script(replacement)
		for key in values:
			if key in wall:
				wall.set(key, values[key])
	wall.call("set_wall_color", index)
	return wall
