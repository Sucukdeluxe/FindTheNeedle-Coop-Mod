extends RefCounted

const INPUTS := [Vector3(-1.1, 0.0, -0.16), Vector3(0.0, 0.0, -1.1), Vector3(1.1, 0.0, -0.16)]

static func point(row: Dictionary, side: int) -> Vector3:
	return row.position + Basis(Vector3.UP, float(row.yaw)) * INPUTS[side]

static func bearing(row: Dictionary, side: int) -> Vector3:
	return Basis(Vector3.UP, float(row.yaw)) * local_bearing(side)

static func local_bearing(side: int) -> Vector3:
	return [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][side]

static func accepts(row: Dictionary, side: int, direction: Vector3) -> bool:
	if direction.dot(bearing(row, side)) >= 0.995:
		return true
	var local: Vector3 = INPUTS[side]
	var previous := Basis(Vector3.UP, float(row.yaw)) * Vector3(-local.x, 0.0, -local.z).normalized()
	return direction.dot(previous) >= 0.995
