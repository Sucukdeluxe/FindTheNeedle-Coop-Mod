extends RefCounted

const MARKER := "xranger_progression_v46"
const ADDON_MARKER := "ftn_production_speed_v1"
const ARM_COSTS := [30,60,100,160,250,380,550,800,1320,2180,2918,3482,4159,4971,5945,7114,8517,10200,12220,14644]
const PORTIONS := [100, 200, 300, 500, 1000]
const PORTION_COSTS := [1500.0, 3500.0, 7000.0, 13000.0]
const TRANSPORT_SCALES := [1.0, 1.2, 1.4, 1.65, 2.0, 2.25, 2.5, 2.8, 3.1, 3.5, 4.0]
const LIFT_COSTS := [1348,1617,1941,2330,2796,3355,4026,4832,5798,6957]
const STAIRS_COSTS := [750,925,1110,1332,1599,1919,2304,2764,3317,3980]
const DISTRIBUTOR_SCALES := [1.0, 1.15, 1.3, 1.45, 1.6, 1.75, 1.9, 2.05, 2.2, 2.35, 2.5]
const DISTRIBUTOR_COSTS := [1000,2000,3500,4196,4336,4503,4705,4945,5234,5581]
const DISTRIBUTOR_BUILDS := ["splitter", "compact_splitter", "smart_splitter", "u_splitter", "t_splitter", "joiner", "u_joiner", "compact_joiner"]
const NEW_CARDS := {"belt_portion": "belt", "hay_lift_speed": "haylift", "hay_stairs_speed": "haystairs"}

static func belt_portion(rank: int) -> int:
	return PORTIONS[clampi(rank, 0, PORTIONS.size() - 1)]

static func transport_scale(rank: int) -> float:
	return TRANSPORT_SCALES[clampi(rank, 0, TRANSPORT_SCALES.size() - 1)]

static func distributor_scale(rank: int) -> float:
	return DISTRIBUTOR_SCALES[clampi(rank, 0, DISTRIBUTOR_SCALES.size() - 1)]

func ensure_cards() -> void:
	var nodes: Dictionary = TechTree.nodes()
	var locale := TranslationServer.get_locale()
	var german := locale.replace("-", "_").get_slice("_", 0) == "de"
	_ensure_double_jump(nodes, locale, german)
	_ensure_arm(nodes, locale, german)
	_ensure_distributor(nodes, locale, german)
	for id in NEW_CARDS:
		if not nodes.get(NEW_CARDS[id]) is Dictionary:
			continue
		var costs: Array = PORTION_COSTS if id == "belt_portion" else (LIFT_COSTS if id == "hay_lift_speed" else STAIRS_COSTS)
		if _ready_card(nodes.get(id), locale, costs):
			_ensure_order(id)
			continue
		var card := {"kind": "ranked", "tuning": true, "requires": [NEW_CARDS[id]], "costs": costs.duplicate(), "flat": true, MARKER: locale}
		if id == "belt_portion":
			card["name"] = "Größere Bandportionen" if german else "Larger Belt Portions"
			card["branch"] = "lines"
			card["icon"] = "belt_loaded+more"
			card["blurb"] = "Erhöht die Heumenge je Portion beim Entleeren auf ein Förderband oder über einen Einfülltrichter. Bei Stau bleibt das Heu im Behälter." if german else "Increases hay per portion when emptying onto a conveyor or through a feed hopper. Blocked output keeps the hay in its container."
			card["base"] = "100"
			card["values"] = ["200", "300", "500", "1.000" if german else "1,000"]
			card["unit"] = " Halme pro Portion" if german else " strands per portion"
		else:
			var lift: bool = id == "hay_lift_speed"
			card["name"] = ("Schnellerer Heulift" if lift else "Schnellere Heutreppe") if german else ("Faster Hay Lift" if lift else "Faster Hay Stairs")
			card["branch"] = "structures"
			card["icon"] = "hay_lift+speed" if lift else "hay_stairs+speed"
			card["blurb"] = "Erhöht das Transporttempo zusätzlich zum Bandmotor. Ein belegter Ausgang hält die Ladung weiterhin an." if german else "Increases transport speed in addition to the belt motor. A blocked output still holds the cargo."
			card["base"] = "100%"
			var values: Array = []
			for rank in range(1, TRANSPORT_SCALES.size()):
				values.append("%d%%" % roundi(TRANSPORT_SCALES[rank] * 100.0))
			card["values"] = values
		nodes[id] = card
		_ensure_order(id)

func _ensure_distributor(nodes: Dictionary, locale: String, german: bool) -> void:
	if not nodes.get("splitter") is Dictionary:
		return
	if not _ready_card(nodes.get("distributor_speed"), locale, DISTRIBUTOR_COSTS):
		var values: Array = []
		for rank in range(1, DISTRIBUTOR_SCALES.size()):
			values.append("%d%%" % roundi(DISTRIBUTOR_SCALES[rank] * 100.0))
		nodes["distributor_speed"] = {"kind": "ranked", "tuning": true, "requires": ["splitter"],
			"costs": DISTRIBUTOR_COSTS.duplicate(), "flat": true, MARKER: locale,
			"name": "Schnellere Verteiler und Sammler" if german else "Faster Splitters and Mergers",
			"branch": "lines", "icon": "splitter+speed", "base": "100%", "values": values,
			"blurb": "Beschleunigt die internen Förderwege aller Verteiler und Sammler zusätzlich zum Bandmotor. Filter und blockierte Ausgänge bleiben wirksam. Alle zehn Stufen kosten zusammen 40.000." if german else "Speeds up internal transport in all splitters and mergers in addition to the belt motor. Filters and blocked outputs remain effective. All ten ranks cost 40,000 in total."}
	_ensure_order("distributor_speed")
	var catalog: Dictionary = BuildCatalog.entries()
	for id in DISTRIBUTOR_BUILDS:
		var entry: Variant = catalog.get(id)
		if not entry is Dictionary:
			continue
		var upgrades: Array = entry.get("upgrades", []).duplicate()
		if not upgrades.has("distributor_speed"):
			upgrades.append("distributor_speed")
			entry["upgrades"] = upgrades

func _ensure_arm(nodes: Dictionary, locale: String, german: bool) -> void:
	var card: Variant = nodes.get("arm_speed")
	if not card is Dictionary or card.get("kind") != "ranked":
		return
	if _ready_card(card, locale, ARM_COSTS):
		if not card.has(ADDON_MARKER):
			card[ADDON_MARKER] = {"managed_by": MARKER, "original_max": 8, "extra": 12}
		_ensure_order("arm_speed")
		return
	var old_costs: Variant = card.get("costs")
	var old_values: Variant = card.get("values")
	if not old_costs is Array or old_costs.size() < 8 or not old_values is Array or old_values.size() != old_costs.size():
		return
	var work: float = Cfg.ROBOT_ARM_WORK_SECONDS * float(Cfg.ROBOT_ARM_TIERS[1]["cycle_scale"])
	var idle: float = Cfg.ROBOT_ARM_IDLE_SECONDS
	var values: Array = []
	for rank in range(1, ARM_COSTS.size() + 1):
		var cycle: float = work * pow(0.92, float(rank)) + idle
		values.append("+%d%%" % roundi(((work + idle) / cycle - 1.0) * 100.0))
	card["costs"] = ARM_COSTS.duplicate()
	card["values"] = values
	card["base"] = "+0%"
	card["suffix"] = " mehr Heu" if german else " more hay"
	card["blurb"] = "Erhöht das Arbeitstempo aller Roboterarme. Die Werte gelten für einen Standardarm. Alle 20 Stufen kosten zusammen 80.000." if german else "Increases the working speed of every robot arm. Values are for a Standard Arm. All 20 ranks cost 80,000 in total."
	card["flat"] = true
	card[MARKER] = locale
	card[ADDON_MARKER] = {"managed_by": MARKER, "original_max": 8, "extra": 12}
	_ensure_order("arm_speed")

static func _ready_card(card: Variant, locale: String, costs: Array) -> bool:
	return card is Dictionary and card.get("kind") == "ranked" and card.get(MARKER) == locale and bool(card.get("flat", false)) and card.get("costs") == costs and card.get("values") is Array and card["values"].size() == costs.size()

static func _ensure_order(id: String) -> void:
	var order: Array = TechTree.ids()
	if not order.has(id):
		order.append(id)

func _ensure_double_jump(nodes: Dictionary, locale: String, german: bool) -> void:
	if not nodes.get("jump_height") is Dictionary:
		return
	var card: Variant = nodes.get("double_jump")
	if not card is Dictionary or card.get(MARKER) != locale or card.get("costs") != [2500.0]:
		nodes["double_jump"] = {"kind": "unlock", "requires": ["jump_height"], "branch": "fitness", "icon": "jump_height",
			"costs": [2500.0], "flat": true, MARKER: locale,
			"name": "Doppelsprung" if german else "Double Jump",
			"blurb": "Nach dem Absprung die Sprungtaste loslassen und in der Luft erneut drücken. Ein zusätzlicher Sprung pro Landung, für alle Spieler freigeschaltet. Ein ausgerüstetes Jetpack behält seine eigene Steuerung." if german else "Release jump after taking off, then press it again in mid-air. One extra jump per landing, unlocked for all players. An equipped jetpack keeps its own controls.",
			"reward": "Doppelsprung freigeschaltet" if german else "Double jump unlocked"}
	_ensure_order("double_jump")
