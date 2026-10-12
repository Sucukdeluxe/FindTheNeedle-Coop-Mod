extends "res://scripts/world/hay_selling_stand.gd"

const NATIVE_STAND = preload("res://scripts/world/hay_selling_stand.gd")
var _visual_clock := 0.0
var _visual_hay := 0
var _visual_worth := 0.0
var _visual_payouts: Array = []
var _visual_sequence := 0
var _received_sequence := 0
var _received_epoch := ""


static func install(node: Node, patch: Script) -> void:
	if not is_instance_valid(node) or node.get_script() != NATIVE_STAND:
		return
	var saved := {}
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			saved[property.name] = node.get(property.name)
	node.set_script(patch)
	for key in saved:
		node.set(key, saved[key])


func _can_sell() -> bool:
	var mp := get_node_or_null("/root/MPMod")
	return not is_instance_valid(mp) or not mp.active() or mp.is_host


func _take_record() -> void:
	if _can_sell():
		super._take_record()


func _collect() -> void:
	if _can_sell():
		super._collect()


func _commit() -> void:
	if _can_sell():
		super._commit()


func sell_loose_strand(body: RigidBody3D) -> bool:
	return super.sell_loose_strand(body) if _can_sell() else false


func _record_scale_strands(strands: int) -> void:
	super._record_scale_strands(strands)
	_visual_hay += maxi(strands, 0)


func _earn_notch(strands: float) -> void:
	super._earn_notch(strands)
	_visual_worth += maxf(strands, 0.0)


func _celebrate(amount: float, coins: int, best := false, combo_best := false) -> void:
	super._celebrate(amount, coins, best, combo_best)
	if _visual_payouts.size() < 32:
		_visual_payouts.append([amount, best, combo_best])
	else:
		_visual_payouts[-1][0] += amount
		_visual_payouts[-1][1] = _visual_payouts[-1][1] or best
		_visual_payouts[-1][2] = _visual_payouts[-1][2] or combo_best


func _drop_coins(count: int) -> void:
	if _can_sell():
		super._drop_coins(count)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_visual_clock += delta
	if _visual_clock < 0.1:
		return
	_visual_clock = 0.0
	if _visual_hay == 0 and _visual_worth == 0.0 and _visual_payouts.is_empty():
		return
	var mp := get_node_or_null("/root/MPMod")
	if is_instance_valid(mp) and mp.active() and mp.is_host and is_instance_valid(mp.world_sync):
		var economy: Node = mp.world_sync.economy
		if is_instance_valid(economy) and economy.epoch != "":
			_visual_sequence += 1
			for peer in mp.players:
				if peer != 1 and mp.players[peer].get("state") == "world":
					mp._rx_stand_visuals.rpc_id(peer, economy.epoch, _visual_sequence,
						_visual_hay, _visual_worth, _combo, minf(_combo_gap, Cfg.SELL_COMBO_BREAK + 1.0), _visual_payouts)
	_visual_hay = 0
	_visual_worth = 0.0
	_visual_payouts.clear()


func apply_visuals(epoch: String, sequence: int, hay: int, worth: float,
		combo: int, gap: float, payouts: Array) -> void:
	if _can_sell() or sequence <= 0 or hay < 0 or combo < 0 or not is_finite(worth) \
			or worth < 0.0 or not is_finite(gap) or gap < 0.0 or payouts.size() > 32:
		return
	if epoch == _received_epoch and sequence <= _received_sequence:
		return
	for payout in payouts:
		if not (payout is Array) or payout.size() != 3 or not (payout[0] is float or payout[0] is int) \
				or not is_finite(float(payout[0])) or float(payout[0]) < 0.0 \
				or not (payout[1] is bool) or not (payout[2] is bool):
			return
	_received_epoch = epoch
	_received_sequence = sequence
	super._record_scale_strands(hay)
	super._earn_notch(worth)
	var previous_combo := _combo
	_combo = combo
	_combo_gap = gap
	if combo != previous_combo and combo_milestone(combo):
		_fly_combo(combo)
	for payout in payouts:
		super._celebrate(float(payout[0]), 0, payout[1], payout[2])
