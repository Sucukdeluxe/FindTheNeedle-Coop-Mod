extends RefCounted

const SIZES := ["standard", "big", "huge", "mountain"]
const VERSION := 1

static func empty(seed: int = 0) -> Dictionary:
	return {"version": VERSION, "cycles": 0, "seed": seed, "indices": [], "found": [], "last_transaction": ""}

static func normalize(value: Variant, seed: int) -> Dictionary:
	if not value is Dictionary or int(value.get("version", 0)) != VERSION:
		return empty(seed)
	var data := empty(seed)
	data.cycles = maxi(0, int(value.get("cycles", 0)))
	data.seed = int(value.get("seed", seed))
	data.last_transaction = str(value.get("last_transaction", "")).substr(0, 128)
	for key in ["indices", "found"]:
		if value.get(key) is Array:
			for number in value[key]:
				if number is int and number >= 0 and not data[key].has(number):
					data[key].append(number)
	return data

static func found_count(data: Dictionary, discoveries: PackedByteArray, types: PackedInt32Array, seed: int) -> int:
	var found := 0
	for type in types:
		if int(data.get("cycles", 0)) == 0:
			if type >= 0 and type < discoveries.size() and discoveries[type] != 0:
				found += 1
		elif int(data.get("seed", -1)) == seed and data.get("found", []).has(type):
			found += 1
	return found

static func record(data: Dictionary, index: int, type: int, seed: int) -> void:
	if int(data.get("cycles", 0)) <= 0 or int(data.get("seed", -1)) != seed:
		return
	if not data.get("indices", []).has(index):
		return
	if not data.found.has(type):
		data.found.append(type)

static func next_state(previous: Dictionary, seed: int, count: int, transaction: String) -> Dictionary:
	var data := empty(seed)
	data.cycles = int(previous.get("cycles", 0)) + 1
	data.indices = range(count)
	data.last_transaction = transaction
	return data

static func allowed(remaining: float, found: int, count: int) -> bool:
	return is_finite(remaining) and remaining >= 0.0 and remaining < 0.5 and count == 6 and found == count

static func credit(strands: float, worth: float, price: float, debt: float, share: float) -> Dictionary:
	if not is_finite(strands) or not is_finite(worth) or not is_finite(price) or strands < 0.0 or worth < 0.0 or price < 0.0:
		return {}
	var gross := worth * price
	var payment := minf(maxf(0.0, debt), gross * clampf(share, 0.0, 1.0))
	return {"gross": gross, "paid": gross - payment, "debt": maxf(0.0, debt - payment)}

const RUN_PROGRESS := {
	"en": "This run: %d / %d needle types. Cabinet collection includes previous runs.",
	"de": "Dieser Durchlauf: %d / %d Nadelarten. Die Schranksammlung enthält frühere Durchläufe.",
	"es": "Partida actual: %d / %d tipos de agujas. La colección incluye partidas anteriores.",
	"fr": "Partie actuelle : %d / %d types d’aiguilles. La collection inclut les parties précédentes.",
	"it": "Partita attuale: %d / %d tipi di aghi. La collezione include le partite precedenti.",
	"cs": "Tento průchod: %d / %d druhů jehel. Sbírka obsahuje i předchozí průchody.",
	"pl": "Bieżący przebieg: %d / %d rodzajów igieł. Kolekcja obejmuje wcześniejsze przebiegi.",
	"ru": "Текущее прохождение: %d / %d типов игл. Коллекция включает прошлые прохождения.",
	"tr": "Bu tur: %d / %d iğne türü. Koleksiyona önceki turlar da dahildir.",
	"ja": "今回：針の種類 %d / %d。棚のコレクションには以前の周回分も含まれます。",
	"ko": "이번 회차: 바늘 종류 %d / %d. 진열장 컬렉션에는 이전 회차도 포함됩니다.",
	"zh": "本轮：%d / %d 种针。柜中收藏包含此前轮次。",
	"pt": "Partida atual: %d / %d tipos de agulhas. A coleção inclui partidas anteriores.",
	"uk": "Поточне проходження: %d / %d типів голок. Колекція містить попередні проходження.",
	"ar": "الجولة الحالية: %d / %d من أنواع الإبر. تضم مجموعة الخزانة الجولات السابقة.",
	"fa": "دور فعلی: %d / %d نوع سوزن. مجموعهٔ کمد شامل دورهای قبلی است.",
	"zh_TW": "本輪：%d / %d 種針。櫃中收藏包含先前輪次。"
}

static func current_progress(state: Node, types: PackedInt32Array, locale: String) -> String:
	var data := normalize(state.get("mp_prestige"), int(state.get("run_seed")))
	var found := found_count(data, state.get("discovered"), types, int(state.get("run_seed")))
	var language := preload("res://mods/multiplayer/mp_i18n.gd").language_code(locale)
	return str(RUN_PROGRESS.get(language, RUN_PROGRESS.en)) % [found, types.size()]
