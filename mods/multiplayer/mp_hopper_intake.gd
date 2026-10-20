extends RefCounted

const MOUTH := AABB(Vector3(-0.86, 1.3, -0.88), Vector3(1.72, 0.95, 1.4))

static func prepare(rows: Array) -> Array:
	var prepared := []
	for row in rows:
		var transform := Transform3D(Basis(Vector3.UP, row.yaw), row.position)
		prepared.append({"row": row, "inverse": transform.affine_inverse(), "bounds": (transform * MOUTH).grow(0.001)})
	return prepared

static func intersects(entry: Dictionary, previous: Vector3, current: Vector3) -> bool:
	var bounds: AABB = entry.bounds
	if not bounds.has_point(current) and bounds.intersects_segment(previous, current) == null:
		return false
	var inverse: Transform3D = entry.inverse
	var local_current := inverse * current
	return MOUTH.has_point(local_current) or MOUTH.intersects_segment(inverse * previous, local_current) != null

static func index(entries: Array) -> Dictionary:
	var cells := {}
	for i in entries.size():
		var bounds: AABB = entries[i].bounds
		var lower := _cell(bounds.position)
		var upper := _cell(bounds.end)
		for x in range(lower.x, upper.x + 1):
			for y in range(lower.y, upper.y + 1):
				for z in range(lower.z, upper.z + 1):
					var key := Vector3i(x, y, z)
					if not cells.has(key):
						cells[key] = []
					cells[key].append(i)
	var direct := {}
	for key in cells:
		direct[key] = []
		for i in cells[key]:
			direct[key].append(entries[i])
	return {"entries": entries, "cells": cells, "direct": direct}

static func candidates(indexed: Dictionary, previous: Vector3, current: Vector3) -> Array:
	var lower := _cell(previous.min(current))
	var upper := _cell(previous.max(current))
	if lower == upper:
		return indexed.direct.get(lower, [])
	var size := upper - lower + Vector3i.ONE
	if size.x * size.y * size.z > 64:
		return indexed.entries
	var found := {}
	for x in range(lower.x, upper.x + 1):
		for y in range(lower.y, upper.y + 1):
			for z in range(lower.z, upper.z + 1):
				for i in indexed.cells.get(Vector3i(x, y, z), []):
					found[i] = true
	var keys := found.keys()
	keys.sort()
	var result := []
	for i in keys:
		result.append(indexed.entries[i])
	return result

static func _cell(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / 4.0), floori(point.y / 4.0), floori(point.z / 4.0))
