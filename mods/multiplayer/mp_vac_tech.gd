extends "res://autoload/tech.gd"

const VacUpgrades = preload("res://mods/multiplayer/mp_vac_upgrades.gd")

func vac_capacity() -> int:
	return VacUpgrades.capacity(rank_of("vac_bin"), super.vac_capacity())

func vac_suck_rate() -> float:
	return VacUpgrades.suction(rank_of("vac_suction"), super.vac_suck_rate())
