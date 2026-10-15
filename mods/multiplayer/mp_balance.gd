extends RefCounted

const SCHEMA := "xranger_balance_v53"
const PRICES := {
	"vac_bin": [80,160,280,292,295,298,301,305,311,317,324,333,344,357,373,391,413,440,472,511,557,613,680,760,857,972,1110,1276,1475,1714,2001,2345,2757,3253,3847,4561,5417,6444,7677,9156,10931],
	"vac_suction": [80,160,280,378,511,690,960,1172,1351,1565,1822,2131,2501,2947,3480,4120,4887,5809,6915,8241],
	"pellet_speed": [90,180,330,570,930,1500,2480,3760,4446,5269,6257,7443,8866,10574,12622,15081,18031,21571],
	"pulper_speed": [240,450,810,1350,2160,3450,7682,10190,12067,14319,17020,20262],
	"paper_speed": [300,570,1020,1710,2700,4200,8409,9887,11661,13790,16344,19409],
	"briquette_speed": [220,420,760,1260,2000,3200,7128,10329,12243,14540,17296,20604],
	"compressor_speed": [50,100,180,300,500,800,1782,3973,7928,9478,11339,13570],
	"wrapper_speed": [50,100,180,300,500,800,1782,3973,7928,9478,11339,13570],
	"belt_speed": [15,30,55,90,420,630,900,1742,3882,5021,6015,7207,8638,10355],
	"barrow_size": [80,180,350,607,658,720,794,884,991,1119,1273,1457,1679,1945,2263],
	"silo_rate": [70,140,250,420,700,1160,2579,3730,4426,5261,6264],
	"rake_speed": [90,160,280,480,800,1320,2943,5460,6496,7739,9232],
	"scan_speed": [40,80,150,280,500,830,1850,4000,4771,5695,6804],
	"hay_lift_speed": [1348,1617,1941,2330,2796,3355,4026,4832,5798,6957],
	"hay_stairs_speed": [750,925,1110,1332,1599,1919,2304,2764,3317,3980],
	"distributor_speed": [1000,2000,3500,4196,4336,4503,4705,4945,5234,5581],
	"arm_speed": [30,60,100,160,250,380,550,800,1320,2180,2918,3482,4159,4971,5945,7114,8517,10200,12220,14644],
	"hay_price": [10,25,50,135,365,250,300,350,400,500,600,700,800,900,1000,1100,1200,1300,1400,1500]
}

static func costs_for(id: String, count: int = -1) -> Array:
	var costs: Array = PRICES.get(id, []).duplicate()
	return costs if count < 0 else costs.slice(0, count)

static func ensure_cards() -> void:
	var nodes: Dictionary = TechTree.nodes()
	for id in PRICES:
		var card: Variant = nodes.get(id)
		if not card is Dictionary or card.get("kind") != "ranked":
			continue
		var current: Variant = card.get("costs")
		if not current is Array:
			continue
		var expected_size: int = PRICES[id].size() if id == "hay_price" else current.size()
		if int(card.get(SCHEMA, -1)) == current.size() and card.get("flat", false) and current.size() == expected_size and (id == "hay_price" or current.size() <= PRICES[id].size()):
			continue
		var costs := costs_for(id, current.size())
		if id == "hay_price":
			costs = costs_for(id)
		if id == "hay_price":
			var values: Array = []
			for rank in range(1, costs.size() + 1):
				values.append("x%.2f" % (1.0 + 0.05 * rank))
			card["values"] = values
			card["base"] = "x1.00"
		if current.size() > costs.size():
			costs.append_array(current.slice(costs.size()))
		card["costs"] = costs
		card["flat"] = true
		card[SCHEMA] = costs.size()

static func refund(purchases: Array, ranks: Dictionary) -> Dictionary:
	var paid_by_rank := {}
	for row in purchases:
		if not row is Array or row.size() != 5 or row[1] != "card" or not row[2] is String or not PRICES.has(row[2]):
			continue
		if not (row[3] is int or row[3] is float) or not (row[4] is int or row[4] is float):
			continue
		var rank_value := float(row[3])
		var paid := float(row[4])
		if not is_finite(rank_value) or rank_value != floor(rank_value) or not is_finite(paid) or paid < 0.0 or paid > 1000000000.0:
			continue
		var rank := int(rank_value)
		var id: String = row[2]
		if rank < 1 or rank > int(ranks.get(id, 0)) or rank > PRICES[id].size():
			continue
		var key := id + ":" + str(rank)
		var cents := roundi(paid * 100.0)
		if not paid_by_rank.has(key) or cents < int(paid_by_rank[key].paid):
			paid_by_rank[key] = {"id": id, "rank": rank, "paid": cents}
	var total := 0
	var entries: Array = []
	for receipt: Dictionary in paid_by_rank.values():
		var due := maxi(0, int(receipt.paid) - roundi(float(PRICES[receipt.id][receipt.rank - 1]) * 100.0))
		if due > 0:
			total += due
			entries.append({"id": receipt.id, "rank": receipt.rank, "cents": due})
	return {"schema": SCHEMA, "settled": true, "cents": total, "entries": entries}

static func apply_credit() -> int:
	var session := GameState.get_node_or_null("/root/MPMod")
	if is_instance_valid(session) and session.active() and not session.is_host:
		return 0
	if not GameState.mp_balance.is_empty():
		return 0
	var result := refund(GameState.purchase_log, Tech.ranks)
	GameState.mp_balance = result
	var cents := int(result.cents)
	if cents > 0:
		GameState.add_money(float(cents) / 100.0)
		print("[MPMod] Balance credit: ", float(cents) / 100.0)
	return cents

static func fresh_state() -> Dictionary:
	return {"schema": SCHEMA, "settled": true, "cents": 0, "entries": []}
