extends RefCounted

const ArmVisual = preload("res://mods/multiplayer/mp_arm_visual.gd")

static func valid(batch: Variant) -> bool:
	if not (batch is Dictionary):
		return false
	for key in batch:
		if not (key is String) or not (batch[key] is Dictionary):
			return false
		var entry: Dictionary = batch[key]
		if entry.has("a") and not ArmVisual.valid(entry.a):
			return false
		if entry.has("i") != entry.has("t") or entry.has("xi") != entry.has("xv"):
			return false
		if entry.has("i"):
			if not (entry.i is PackedInt32Array) or not (entry.t is PackedFloat32Array):
				return false
			if entry.i.size() > 120 or entry.t.size() != entry.i.size() * 12:
				return false
			for value in entry.t:
				if not is_finite(value):
					return false
		if entry.has("f"):
			if not (entry.f is PackedInt32Array) or entry.f.size() > 240 or entry.f.size() % 2 != 0:
				return false
		if entry.has("xi"):
			if not (entry.xi is PackedInt32Array) or not (entry.xv is PackedFloat32Array):
				return false
			if entry.xi.size() != entry.xv.size() * 2:
				return false
			for value in entry.xv:
				if not is_finite(value):
					return false
	return true
