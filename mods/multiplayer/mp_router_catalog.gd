extends RefCounted

const COUNTS := [4, 6, 8]
const BUILD_COSTS := {4: 2000.0, 6: 3500.0, 8: 5000.0}
const UNLOCK_COSTS := {4: 1500.0, 6: 4000.0, 8: 8000.0}
const RADII := {4: 1.25, 6: 1.65, 8: 2.05}

static func id(count: int, distributor: bool = false) -> String:
	return ("mp_splitter" if distributor else "mp_receiver") + str(count)

static func ids() -> Array:
	var values := []
	for distributor in [false, true]:
		for count in COUNTS:
			values.append(id(count, distributor))
	return values

static func count_for(value: String) -> int:
	return int(value.right(1)) if value in ids() else 0

static func is_distributor(value: String) -> bool:
	return value.begins_with("mp_splitter") and value in ids()

static func radius(count: int) -> float:
	return float(RADII.get(count, 0.0))

static func build_cost(count: int) -> float:
	return float(BUILD_COSTS.get(count, 0.0))

static func ensure_cards(nodes: Dictionary, locale: String) -> void:
	var german := locale.begins_with("de")
	for distributor in [false, true]:
		for index in COUNTS.size():
			var count: int = COUNTS[index]
			var key := id(count, distributor)
			var costs := [UNLOCK_COSTS[count]]
			var previous := "smart_splitter" if index == 0 else id(COUNTS[index - 1], distributor)
			if nodes.get(key, {}).get("router_version") == locale and nodes[key].get("costs") == costs:
				continue
			var title := ("Verteiler" if distributor else "Sammler") if german else ("Splitter" if distributor else "Merger")
			nodes[key] = {"kind": "unlock", "flat": true, "requires": [previous], "costs": costs, "branch": "lines", "icon": "splitter" if distributor else "joiner", "router_version": locale,
				"name": "%s · %d %s" % [title, count, "Anschlüsse" if german else "ports"],
				"blurb": ("Schaltet den Bau frei. Baukosten werden pro Gebäude zusätzlich bezahlt. Der Vorgänger muss zuerst freigeschaltet sein." if german else "Unlocks construction. Each building has a separate construction cost. Unlock the previous size first."),
				"reward": ("Im Baukatalog verfügbar" if german else "Available in the build catalog")}
			if not TechTree.ids().has(key):
				TechTree.ids().append(key)
