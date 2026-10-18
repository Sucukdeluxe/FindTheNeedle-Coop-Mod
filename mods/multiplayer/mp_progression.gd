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
	preload("res://mods/multiplayer/mp_router_catalog.gd").ensure_cards(nodes, locale)
	preload("res://mods/multiplayer/mp_sale_stations.gd").ensure_cards(nodes, locale)
	_ensure_double_jump(nodes, locale, german)
	_ensure_arm(nodes, locale, german)
	_ensure_scanner(nodes, locale)
	preload("res://mods/multiplayer/mp_arm_upgrades.gd").ensure_cards()
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

static func scanner_cycle_scale(rank: int, maximum: int, reference_seconds: float) -> float:
	if maximum <= 0 or reference_seconds <= 0.0:
		return 1.0
	return pow(minf(1.0, 0.5 / reference_seconds), float(clampi(rank, 0, maximum)) / float(maximum))

const SCANNER_DESCRIPTION := {
	"en": "Speeds up every scanner. Times shown are for Mk II at full power, before specimen bonuses. The final rank reaches 0.5 s per cycle.",
	"de": "Beschleunigt alle Scanner. Die Zeiten gelten für Mk II bei voller Stromversorgung, ohne Sammlungsboni. Die letzte Stufe erreicht 0,5 s pro Durchlauf.",
	"es": "Acelera todos los escáneres. Tiempos para Mk II a plena potencia, sin bonificaciones de colección. El último nivel alcanza 0,5 s por ciclo.",
	"fr": "Accélère tous les scanners. Durées pour le Mk II à pleine puissance, hors bonus de collection. Le dernier niveau atteint 0,5 s par cycle.",
	"it": "Accelera tutti gli scanner. Tempi per Mk II a piena potenza, senza bonus della collezione. L’ultimo livello raggiunge 0,5 s per ciclo.",
	"cs": "Zrychluje všechny skenery. Časy platí pro Mk II při plném napájení, bez bonusů sbírky. Poslední úroveň dosáhne 0,5 s na cyklus.",
	"pl": "Przyspiesza wszystkie skanery. Czasy dla Mk II przy pełnym zasilaniu, bez premii kolekcji. Ostatni poziom osiąga 0,5 s na cykl.",
	"ru": "Ускоряет все сканеры. Время указано для Mk II при полном питании без бонусов коллекции. Последний уровень: 0,5 с за цикл.",
	"tr": "Tüm tarayıcıları hızlandırır. Süreler koleksiyon bonusları olmadan tam güçte Mk II içindir. Son seviyede döngü süresi 0,5 saniyedir.",
	"ja": "すべてのスキャナーを高速化します。表示時間は標本ボーナスを含まない、電力供給が十分なMk IIの値です。最終段階では1サイクル0.5秒です。",
	"ko": "모든 스캐너를 가속합니다. 표시 시간은 수집 보너스를 제외하고 전력이 충분한 Mk II 기준입니다. 마지막 단계는 주기당 0.5초입니다.",
	"zh": "加快所有扫描仪。显示时间以供电充足且无收藏加成的 Mk II 为准。最后一级每周期为 0.5 秒。",
	"pt": "Acelera todos os scanners. Tempos para Mk II com energia total, sem bônus de coleção. O último nível atinge 0,5 s por ciclo.",
	"uk": "Прискорює всі сканери. Час для Mk II за повного живлення без бонусів колекції. Останній рівень: 0,5 с за цикл.",
	"ar": "يسرّع جميع الماسحات. الأوقات تخص Mk II بطاقة كاملة دون مكافآت المجموعة. يصل المستوى الأخير إلى 0.5 ثانية لكل دورة.",
	"fa": "همهٔ اسکنرها را سریع‌تر می‌کند. زمان‌ها برای Mk II با برق کامل و بدون پاداش مجموعه هستند. سطح آخر به 0.5 ثانیه در هر چرخه می‌رسد.",
	"zh_TW": "加快所有掃描器。顯示時間以供電充足且無收藏加成的 Mk II 為準。最後一級每週期為 0.5 秒。"
}

func _ensure_scanner(nodes: Dictionary, locale: String) -> void:
	var card: Variant = nodes.get("scan_speed")
	if not card is Dictionary or not card.get("costs") is Array or card.costs.is_empty():
		return
	var marker := locale + ":" + str(card.costs.size())
	if card.get("mp_scan_cycle_v74") == marker:
		return
	var reference: float = Cfg.SCANNER_TIERS[1]["scan_seconds"]
	var language := preload("res://mods/multiplayer/mp_i18n.gd").language_code(locale)
	var comma := language in ["de", "fr", "es", "it", "cs", "pl", "pt", "ru", "uk", "tr"]
	var values := []
	for rank in range(1, card.costs.size() + 1):
		var shown := "%.2f" % (reference * scanner_cycle_scale(rank, card.costs.size(), reference))
		values.append(shown.replace(".", ",") if comma else shown)
	card["values"] = values
	card["base"] = ("%.2f" % reference).replace(".", ",") if comma else "%.2f" % reference
	card["unit"] = " s · Mk II"
	card.erase("suffix")
	card["blurb"] = SCANNER_DESCRIPTION.get(language, SCANNER_DESCRIPTION.en)
	card["mp_scan_cycle_v74"] = marker
