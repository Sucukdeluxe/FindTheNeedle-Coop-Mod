extends "res://scripts/hay/hay_field.gd"

func _hand_back(progress: float) -> void:
	if _shape_report.is_valid():
		_shape_report.call(progress)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		await tree.process_frame
	_slice_start = Time.get_ticks_usec()
