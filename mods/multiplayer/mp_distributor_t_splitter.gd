extends "res://scripts/build/conveyor_t_splitter.gd"

const Drive = preload("res://mods/multiplayer/mp_distributor_drive.gd")

func _lane_speed() -> float:
	return super._lane_speed() * Drive.scale()

func _arm_late(lead: Dictionary, to: float, ride := -1.0) -> bool:
	return super._arm_late(lead, to, ride if ride > 0.0 else Tech.belt_speed() * Drive.scale())

func _arm_blocked(marks: Array[Dictionary], to: float, ride := -1.0) -> bool:
	return super._arm_blocked(marks, to, ride if ride > 0.0 else Tech.belt_speed() * Drive.scale())
