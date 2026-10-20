extends FactoryClock

const Cells = preload("res://mods/multiplayer/mp_belt_watch_cells.gd")

class WatchView extends PropManager:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var _mp_props: PropManager
var _mp_watch: PropManager

func mp_watch_start(props: PropManager) -> void:
	_mp_props = props
	_mp_watch = WatchView.new()
	_mp_watch.name = "MPBeltWatchView"
	add_child(_mp_watch)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_mp_props) or not is_instance_valid(_mp_watch) or not Cells.should_group(_mp_props.items):
		super._physics_process(delta)
		return
	_mp_watch.items = Cells.representatives(_mp_props.items)
	_mp_watch.live = _mp_props.live
	var original := BeltWatch._props(get_tree())
	BeltWatch._props_ref = _mp_watch
	super._physics_process(delta)
	BeltWatch._props_ref = original
	_mp_watch.items.clear()

func mp_watch_stop() -> void:
	if is_instance_valid(_mp_watch):
		if BeltWatch._props_ref == _mp_watch:
			BeltWatch._props_ref = _mp_props
		_mp_watch.items.clear()
		_mp_watch.live = null
		_mp_watch.queue_free()
	_mp_watch = null
	_mp_props = null
