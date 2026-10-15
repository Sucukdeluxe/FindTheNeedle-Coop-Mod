extends "res://autoload/tech.gd"

const VacUpgrades = preload("res://mods/multiplayer/mp_vac_upgrades.gd")
const Progression = preload("res://mods/multiplayer/mp_progression.gd")

func vac_capacity() -> int:
	return VacUpgrades.capacity(rank_of("vac_bin"), super.vac_capacity())

func vac_suck_rate() -> float:
	return VacUpgrades.suction(rank_of("vac_suction"), super.vac_suck_rate())

func belt_portion() -> int:
	return Progression.belt_portion(rank_of("belt_portion"))

func hay_lift_speed_scale() -> float:
	return Progression.transport_scale(rank_of("hay_lift_speed"))

func hay_stairs_speed_scale() -> float:
	return Progression.transport_scale(rank_of("hay_stairs_speed"))

func distributor_speed_scale() -> float:
	return Progression.distributor_scale(rank_of("distributor_speed"))

func from_dict(data: Dictionary, refund_v5_truncation: bool = false) -> void:
	preload("res://mods/multiplayer/mp_balance.gd").ensure_cards()
	super.from_dict(data, refund_v5_truncation)
	preload("res://mods/multiplayer/mp_balance.gd").apply_credit()
