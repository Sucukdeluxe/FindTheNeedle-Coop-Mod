extends RefCounted

var hay := 0.0
var worth := 0.0
var building_value := 0.0
var buildings := 0
var needles := {}
var kept_tools := {}
var _seen := {}

func raw(count: float) -> void:
	add(count, count)

func add(count: float, value: float) -> void:
	if is_finite(count) and is_finite(value) and count > 0.0 and value >= 0.0:
		hay += count
		worth += value

func needle(index: int) -> void:
	if index >= 0:
		needles[index] = true

func record(data: Dictionary) -> void:
	var count := int(data.get("strands", 0))
	var kind := int(data.get("kind", -1))
	if kind >= 0 and kind < BeltRun.ITEM_IDS.size():
		add(count, HaySellingStand.sale_value_of(kind, count, data.get("state", {})))
	needle(int(data.get("needle", -1)))

func stored_item(data: Dictionary) -> void:
	var kind := BeltRun.ITEM_IDS.find(str(data.get("id", "")))
	var state: Dictionary = data.get("state", {})
	record({"kind": kind, "strands": int(data.get("strands", state.get("strands", 0))),
		"state": state, "needle": int(data.get("needle", state.get("needle", -1)))})

func body(item: Node) -> void:
	if not is_instance_valid(item) or _seen.has(item.get_instance_id()) or item.is_queued_for_deletion():
		return
	_seen[item.get_instance_id()] = true
	if item.has_meta("needle_index"):
		needle(int(item.get_meta("needle_index")))
		return
	if item is Carryable:
		needle(int(item.needle_index))
		var count: int = item.hay_strands()
		if item is HayContainer:
			raw(item.stored)
		elif item.has_method("sale_strands"):
			add(count, float(item.call("sale_strands")))
		else:
			raw(count)
		if count <= 0 and ItemDb.price(item.item_id) > 0:
			kept_tools[item.item_id] = int(kept_tools.get(item.item_id, 0)) + 1

func machine(node: Node) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	buildings += 1
	if node.has_method("build_cost"):
		building_value += maxf(0.0, float(node.call("build_cost")))
	if node.has_method("held_needles"):
		for index in node.call("held_needles"):
			needle(index)
	if node is HaystackScanner:
		for index in node._all_needles():
			needle(index)
	if node is HaystackScanner:
		raw(node.stored + node._outgoing)
		for spec in node.blocks:
			stored_item(spec)
	elif node is TubeLauncher:
		raw(node.stored)
		for spec in node._queue:
			stored_item(spec)
	elif node is DumpHatch:
		raw(node.stored)
	elif node is PistonRake:
		raw(maxf(0.0, node._held) + maxf(0.0, node._thrown_total - node._put_out))
	elif node is HayCompressor or node is HayPulper:
		raw(node.stored)
		var clock := "_press" if node is HayCompressor else "_run"
		if float(node.get(clock)) >= 0.0 and not bool(node.get("_released")):
			raw(node.get("_batch"))
	elif node is HayPelletizer:
		raw(node.stored)
		if node._grind >= 0.0:
			raw(node._batch)
	elif node is HayWrapper or node is PaperMachine:
		var ratio := Tech.bale_value_ratio() if node is HayWrapper else Tech.pulp_value_ratio()
		for count in node.queued:
			add(float(count), float(count) * ratio)
		var clock := "_wrap" if node is HayWrapper else "_run"
		if float(node.get(clock)) >= 0.0 and not bool(node.get("_released")):
			add(float(node.get("_batch")), float(node.get("_batch")) * ratio)
	elif node is BriquettePress:
		raw(node.stored_strands)
		for i in node.stored_bricks:
			var count: int = node.brick_hay[i] if i < node.brick_hay.size() else Tech.pellet_brick_strands()
			var value: float = node.brick_worth[i] if i < node.brick_worth.size() else float(count) * Tech.brick_value_ratio()
			add(count, value)
		if node._run >= 0.0 and not node._released:
			raw(node._batch_strands)
			add(node._batch_brick_hay, node._batch_brick_worth)
	elif node is HaySilo:
		raw(node.stored)
		for spec in node.queued:
			stored_item(spec)
	elif node is RoboticArm:
		if node._payload_prop == null:
			raw(maxi(0, node._payload_count - node._payload.size()))
	elif node is HayLift or node is HayStairs:
		for row in node._carried:
			var data: Dictionary = row.get("rec", {})
			if not data.is_empty():
				record(data)

func capture(sync: Node) -> Dictionary:
	for building in sync.builds.all_buildings():
		machine(building)
	for path in BeltPath._live:
		if is_instance_valid(path) and path.is_inside_tree():
			for data in path.records_to_save():
				record(data)
	for item in sync.world.props.items:
		body(item)
	var live: Node = sync.world.live
	for item in live.needles:
		body(item)
	for item in live._active:
		if is_instance_valid(item) and not item.is_queued_for_deletion() and not bool(item.get_meta("mp_ghost", false)) and not bool(item.get_meta(LiveStrandManager.META_LOCAL_VISUAL, false)):
			raw(1)
	var stand: Node = sync.world.stand
	add(float(stand.get("_pending_hay")), float(stand.get("_pending")))
	var hoppers: Dictionary = sync.hoppers_sync.serialize()
	for row in hoppers.get("rows", []):
		building_value += 2500.0
		buildings += 1
		raw(float(row.get("stored", 0)))
		for needle in row.get("needles", []):
			needles[int(needle)] = true
	raw(maxf(0.0, float(GameState.hay_returned)))
	return {"hay": hay, "worth": worth, "building_value": building_value, "buildings": buildings, "needles": needles.keys(), "kept_tools": kept_tools}
