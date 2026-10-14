extends RefCounted

const CAPACITY_LEGACY_RANK := 27
const CAPACITY_MAX_RANK := 41
const CAPACITY_MAX := 50000
const SUCTION_LEGACY_RANK := 6
const SUCTION_MAX_RANK := 20
const SUCTION_RATES := [300.0, 350.0, 400.0, 450.0, 500.0, 550.0, 600.0, 650.0, 700.0, 760.0, 820.0, 880.0, 940.0, 1000.0]
const PRICE_LIMIT := 100000.0
const NATIVE_RANKS := 6
const CARDS := {"vac_bin": CAPACITY_MAX_RANK, "vac_suction": SUCTION_MAX_RANK}
var _cached := {}

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
		return clampf(float(native_costs[rank - 1]), 0.0, PRICE_LIMIT)
	var anchor := maxf(float(native_costs[NATIVE_RANKS - 1]), 1.0)
	var progress := float(rank - NATIVE_RANKS) / float(maximum - NATIVE_RANKS)
	return minf(PRICE_LIMIT, snappedf(anchor * pow(PRICE_LIMIT / anchor, progress), 100.0))

func ensure_cards() -> void:
	var nodes: Dictionary = TechTree.nodes()
	if is_same(nodes, _cached):
		return
	_cached = nodes
	for id in CARDS:
		var card: Variant = nodes.get(id)
		if not (card is Dictionary) or card.get("kind") != "ranked":
			continue
		var old_costs: Variant = card.get("costs")
		var old_values: Variant = card.get("values")
		if not (old_costs is Array) or old_costs.size() < NATIVE_RANKS or not (old_values is Array) or old_values.size() != old_costs.size():
			continue
		var costs: Array = []
		var values: Array = []
		for rank in range(1, int(CARDS[id]) + 1):
			costs.append(price(rank, old_costs, CARDS[id]))
			var amount := capacity(rank, 1500 + rank * 500) if id == "vac_bin" else roundi(suction(rank, 100.0 + rank * 25.0))
			values.append(_label(amount, id == "vac_suction"))
		card["costs"] = costs
		card["values"] = values

static func _label(amount: int, per_second: bool) -> String:
	var german := TranslationServer.get_locale().replace("-", "_").get_slice("_", 0) == "de"
	var number := str(amount)
	var result := ""
	while number.length() > 3:
		result = ("." if german else ",") + number.right(3) + result
		number = number.left(number.length() - 3)
	return number + result + (" Halme" if german else " strands") + ("/s" if per_second else "")
