extends RefCounted

const MAX_WAIT := 3

static var _frame := -1
static var _taken := false

var _waited := 0


func take() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_taken = false
	if _taken and _waited < MAX_WAIT:
		_waited += 1
		return false
	_taken = true
	_waited = 0
	return true
