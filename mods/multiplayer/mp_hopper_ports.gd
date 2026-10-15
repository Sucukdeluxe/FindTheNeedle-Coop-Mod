extends RefCounted

const INPUTS := [Vector3(-1.1, 0.0, -0.16), Vector3(0.0, 0.0, -1.1), Vector3(1.1, 0.0, -0.16)]

static func point(row: Dictionary, side: int) -> Vector3:
	return row.position + Basis(Vector3.UP, float(row.yaw)) * INPUTS[side]

static func bearing(row: Dictionary, side: int) -> Vector3:
	var local: Vector3 = INPUTS[side]
	return Basis(Vector3.UP, float(row.yaw)) * Vector3(-local.x, 0.0, -local.z).normalized()
