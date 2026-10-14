extends RefCounted

var used := false
var was_pressed := false

func step(grounded: bool, pressed: bool, allowed: bool) -> bool:
	var rising := pressed and not was_pressed
	was_pressed = pressed
	if grounded:
		used = false
		return false
	if not allowed or not rising or used:
		return false
	used = true
	return true
