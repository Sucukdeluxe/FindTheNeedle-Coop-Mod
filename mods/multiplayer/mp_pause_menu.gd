extends "res://scripts/ui/pause_menu.gd"

func _on_exit_to_title() -> void:
	if not _mp_save_before_leaving():
		return
	_leaving = true
	Audio.play("ui_back")
	Loading.show_screen("FIND THE NEEDLE", tr("RETURNING TO THE YARD"))
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_quit() -> void:
	if not _mp_save_before_leaving():
		return
	_leaving = true
	get_tree().quit()

func _mp_save_before_leaving() -> bool:
	if _leaving:
		return false
	var session := get_node_or_null("/root/MPMod")
	if is_instance_valid(session) and session.active() and not session.is_host:
		return true
	if _save():
		return true
	if SaveManager.has_method("mp_cleanup_pending") and SaveManager.mp_cleanup_pending():
		_status.text = "Aufräumen wird abgeschlossen. Danach speichern und beenden." if TranslationServer.get_locale().begins_with("de") else "Cleanup is finishing. Save and exit after it completes."
	else:
		_status.text = tr("Could not write the save")
	return false
