extends RefCounted

const MARKER := "xranger_arm_upgrades_v68"
const PAYLOAD_COSTS := [1000, 2000, 4000, 7000, 10000, 14000, 18000, 24000]
const SPACING_COSTS := [1500, 2500, 4000, 6500, 10000, 14500, 19500, 25000, 30500, 36000]

static func spacing_scale(rank: int) -> float:
	return 1.0 - 0.05 * clampi(rank, 0, SPACING_COSTS.size())

static func ensure_cards() -> void:
	var nodes: Dictionary = TechTree.nodes()
	if not nodes.has("arm_small"):
		return
	var locale := TranslationServer.get_locale()
	var text = preload("res://mods/multiplayer/mp_i18n.gd")
	var payload: Dictionary = nodes.get("arm_payload", {})
	if not payload.is_empty():
		payload.costs = PAYLOAD_COSTS.duplicate()
		payload.flat = true
	var values := []
	for rank in range(1, SPACING_COSTS.size() + 1):
		values.append("%d%%" % roundi(spacing_scale(rank) * 100.0))
	if nodes.get("arm_spacing", {}).get(MARKER) != locale:
		nodes["arm_spacing"] = {"kind": "ranked", "tuning": true, "requires": ["arm_standard"],
			"branch": "automation", "icon": "arm_spacing", "costs": SPACING_COSTS.duplicate(), "flat": true,
			"name": text.phrase("Arm-Abstand", "Arm Spacing"), "base": "100%", "values": values, MARKER: locale,
			"blurb": text.phrase("Verringert den nötigen Bauabstand zwischen Armen je Stufe um 5 %, bis auf 50 %. Die Greifreichweite bleibt erhalten. Sockel benötigen weiterhin freien Platz.", "Reduces required spacing between arms by 5% per rank, down to 50%. Working reach is unchanged. Bases still need clear space.")}
	var order: Array = TechTree.ids()
	var anchor := order.find("arm_speed")
	if anchor >= 0:
		for id in ["arm_payload", "arm_spacing"]:
			order.erase(id)
			order.insert(anchor + 1, id)
			anchor += 1
	var catalog: Dictionary = BuildCatalog.entries()
	for id in ["arm", "arm_standard", "arm_long"]:
		if catalog.has(id):
			var upgrades: Array = catalog[id].get("upgrades", []).duplicate()
			if not upgrades.has("arm_spacing"):
				upgrades.append("arm_spacing")
			catalog[id].upgrades = upgrades
