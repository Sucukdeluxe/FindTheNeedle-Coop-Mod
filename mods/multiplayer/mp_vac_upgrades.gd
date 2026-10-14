extends RefCounted

const CAPACITY_LEGACY_RANK := 27
const CAPACITY_MAX_RANK := 41
const CAPACITY_MAX := 50000
const SUCTION_LEGACY_RANK := 6
const SUCTION_MAX_RANK := 20
const SUCTION_RATES := [300.0, 350.0, 400.0, 450.0, 500.0, 550.0, 600.0, 650.0, 700.0, 760.0, 820.0, 880.0, 940.0, 1000.0]
const PRICE_LIMIT := 100000.0
const PRICE_SCALE := 0.8
const PRICE_SCHEMA := "xranger_vacuum_price_v48"
const SOURCE_COSTS := "xranger_vacuum_source_costs"
const NATIVE_RANKS := 6
const CARDS := {"vac_bin": CAPACITY_MAX_RANK, "vac_suction": SUCTION_MAX_RANK}
const MARKER := "xranger_vacuum_schema"

static func capacity(rank: int, native_value: int) -> int:
	if rank <= CAPACITY_LEGACY_RANK:
		return native_value
	return mini(CAPACITY_MAX, 15000 + (rank - CAPACITY_LEGACY_RANK) * 2500)

static func suction(rank: int, native_value: float) -> float:
	if rank <= SUCTION_LEGACY_RANK:
		return native_value
	return SUCTION_RATES[clampi(rank - SUCTION_LEGACY_RANK - 1, 0, SUCTION_RATES.size() - 1)]

static func price(rank: int, native_costs: Array, maximum: int) -> float:
	if rank <= NATIVE_RANKS:
		return clampf(float(native_costs[rank - 1]), 0.0, PRICE_LIMIT) * PRICE_SCALE
	var anchor := clampf(float(native_costs[NATIVE_RANKS - 1]), 1.0, PRICE_LIMIT)
	var progress := float(rank - NATIVE_RANKS) / float(maximum - NATIVE_RANKS)
	return minf(PRICE_LIMIT, snappedf(anchor * pow(PRICE_LIMIT / anchor, progress), 100.0)) * PRICE_SCALE

func ensure_cards() -> void:
	var nodes: Dictionary = TechTree.nodes()
	var locale := TranslationServer.get_locale()
	for id in CARDS:
		var card: Variant = nodes.get(id)
		if not (card is Dictionary) or card.get("kind") != "ranked":
			continue
		var old_costs: Variant = card.get("costs")
		var old_values: Variant = card.get("values")
		if not (old_costs is Array) or old_costs.size() < 3 or not (old_values is Array) or old_values.size() != old_costs.size():
			continue
		if card.get(PRICE_SCHEMA, false) and card.has(MARKER) and card[MARKER] == locale and old_costs.size() == CARDS[id] and bool(card.get("flat", false)):
			continue
		var native_costs: Array = old_costs.slice(0, NATIVE_RANKS)
		if card.get(SOURCE_COSTS) is Array:
			native_costs = card[SOURCE_COSTS].duplicate()
		var valid := native_costs.size() >= 3 and native_costs.size() <= NATIVE_RANKS
		for cost in native_costs:
			if not (cost is float or cost is int) or not is_finite(float(cost)) or float(cost) <= 0.0:
				valid = false
		if not valid:
			continue
		var growth := 1.25 if id == "vac_bin" else 1.35
		while native_costs.size() < NATIVE_RANKS:
			native_costs.append(maxf(float(native_costs[-1]) + 1.0, snappedf(float(native_costs[-1]) * growth, 1.0)))
		var costs: Array = []
		var values: Array = []
		for rank in range(1, int(CARDS[id]) + 1):
			costs.append(price(rank, native_costs, CARDS[id]))
			var amount := capacity(rank, 1500 + rank * 500) if id == "vac_bin" else roundi(suction(rank, 100.0 + rank * 25.0))
			values.append(_number(amount))
		card["costs"] = costs
		card["values"] = values
		card["base"] = _number(1500 if id == "vac_bin" else 100)
		card["flat"] = true
		card[MARKER] = locale
		card[PRICE_SCHEMA] = true
		card[SOURCE_COSTS] = native_costs.duplicate()
		var german := locale.replace("-", "_").get_slice("_", 0) == "de"
		if id == "vac_bin":
			card["blurb"] = "Bis Stufe 27 jeweils 500 zusätzliche Halme, danach 2.500 je Stufe bis 50.000." if german else "Adds 500 strands per rank through rank 27, then 2,500 per rank up to 50,000."
		else:
			card["blurb"] = "Erhöht die Saugleistung bis auf 1.000 Halme pro Sekunde und vergrößert den Saugbereich." if german else "Increases suction up to 1,000 strands per second and widens the collection area."

static func _number(amount: int) -> String:
	var german := TranslationServer.get_locale().replace("-", "_").get_slice("_", 0) == "de"
	var number := str(amount)
	var result := ""
	while number.length() > 3:
		result = ("." if german else ",") + number.right(3) + result
		number = number.left(number.length() - 3)
	return number + result
