extends Node

const ADDONS := [
	{"name": "FTNToolUpgrades", "path": "res://mods/ftn_tool_upgrades/ftn_tool_upgrades.gd"},
	{"name": "FTNProductionSpeed", "path": "res://mods/ftn_production_speed/ftn_production_speed.gd"},
	{"name": "FTNMice", "path": "res://mods/ftn_mice/ftn_mice.gd"},
]

var mp: Node
var _sync_t := 0.0
var _checked := {}


func start(mp_node: Node) -> void:
	mp = mp_node
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_addons()


func _process(delta: float) -> void:
	_sync_t -= delta
	if _sync_t > 0.0:
		return
	_sync_t = 0.25
	_ensure_addons()
	_sync_runtime()


func ensure_tech_extensions() -> void:
	_ensure_addons()
	var root := get_tree().root if is_inside_tree() else null
	if root == null:
		return
	for addon_name in ["FTNProductionSpeed", "FTNToolUpgrades"]:
		var mod := root.get_node_or_null(addon_name)
		if is_instance_valid(mod) and mod.is_node_ready() and mod.has_method("ensure_extensions"):
			mod.ensure_extensions()


func _ensure_addons() -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	if root == null:
		return
	if not root.is_node_ready():
		_ensure_addons.call_deferred()
		return
	for entry in ADDONS:
		var addon_name: String = entry.name
		var path: String = entry.path
		var existing := root.get_node_or_null(addon_name)
		if existing != null:
			if not _checked.get(addon_name, false):
				_checked[addon_name] = true
				if _needs_adaptation(addon_name, existing):
					_upgrade_existing_node(root, addon_name, existing, path)
			continue
		if _checked.get(addon_name, false):
			continue
		_checked[addon_name] = true
		if not FileAccess.file_exists(path):
			continue
		var script := _load_compatible_script(addon_name, path)
		if script == null or not script.can_instantiate():
			continue
		var instance: Node = script.new()
		instance.name = addon_name
		_prepare_extensions(instance)
		if root.is_node_ready():
			root.add_child(instance)
		else:
			root.add_child.call_deferred(instance)


func _needs_adaptation(addon_name: String, node: Node) -> bool:
	var script: Script = node.get_script()
	if script == null:
		return true
	if addon_name == "FTNProductionSpeed":
		return not node.has_method("_uses_script") or not node.has_method("_authority_runtime") or node.has_method("_feeder_holds_kind")
	if addon_name == "FTNMice":
		var src := _read_source(script, "res://mods/ftn_mice/ftn_mice.gd")
		return 'script.resource_path == "res://scripts/build/haystack_scanner.gd"' in src or not "is_server()" in src
	return false


func _upgrade_existing_node(root: Window, addon_name: String, old_node: Node, path: String) -> void:
	var script := _load_compatible_script(addon_name, path)
	if script == null or not script.can_instantiate():
		return
	if old_node.is_inside_tree():
		if addon_name == "FTNMice" and old_node.has_method("_detach"):
			old_node._detach()
		root.remove_child(old_node)
	old_node.free()
	var replacement: Node = script.new()
	replacement.name = addon_name
	_prepare_extensions(replacement)
	if root.is_node_ready():
		root.add_child(replacement)
	else:
		root.add_child.call_deferred(replacement)


func _prepare_extensions(node: Node) -> void:
	if "_number_pattern" in node and node._number_pattern is RegEx and not node._number_pattern.is_valid():
		node._number_pattern.compile("[0-9٠-٩۰-۹]+(?:[.,٬\u00a0\u202f ][0-9٠-٩۰-۹]+)*")
	if node.has_method("ensure_extensions"):
		node.ensure_extensions()


func _read_source(script: Script, path: String) -> String:
	if script != null and script.source_code != "":
		return script.source_code
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return ""


func _load_compatible_script(addon_name: String, path: String) -> Script:
	if not FileAccess.file_exists(path):
		return null
	var src := FileAccess.get_file_as_string(path)
	if src == "":
		return load(path)
	var adapted := _adapt_source(addon_name, src)
	if adapted == src:
		var direct: Script = load(path)
		if direct != null and direct.can_instantiate():
			return direct
	var runtime_script := GDScript.new()
	runtime_script.source_code = adapted
	if runtime_script.reload() != OK:
		return load(path)
	runtime_script.take_over_path(path)
	return runtime_script


func _adapt_source(addon_name: String, src: String) -> String:
	var out := src
	if addon_name == "FTNProductionSpeed":
		out = out.replace(
			"if body.has_meta(BeltPath.META_JOINS_QUEUE):body.remove_meta(BeltPath.META_JOINS_QUEUE)",
			'if body.has_meta("belt_queue_bounce"):body.remove_meta("belt_queue_bounce")'
		)
		if not "func _authority_runtime(" in out:
			var helpers := """func _authority_runtime() -> bool:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return true
	return multiplayer.is_server()

func _uses_script(node:Node,paths:Array) -> bool:
	if not is_instance_valid(node):return false
	var script:Script=node.get_script()
	while script!=null:
		var path:String=script.resource_path
		if path.ends_with(".gdc"):path=path.trim_suffix("c")
		if path in paths:return true
		script=script.get_base_script()
	return false

func _is_preview(node:Node) -> bool:
	var current:Node=node
	while is_instance_valid(current):
		if "placement_preview" in current and bool(current.get("placement_preview")):return true
		current=current.get_parent()
	return false

"""
			out = out.replace("func _ready() -> void:", helpers + "func _ready() -> void:")
		out = out.replace(
			"multiplayer.multiplayer_peer!=null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer",
			"not _authority_runtime()"
		)
		out = out.replace(
			"node.get_script()!=null and node.get_script().resource_path==PULPER_SCRIPT",
			"_uses_script(node,[PULPER_SCRIPT])"
		)
		out = out.replace(
			"node.get_script()==null or node.get_script().resource_path not in GUARDED_PROCESSORS",
			"not _uses_script(node,GUARDED_PROCESSORS)"
		)
		out = out.replace(
			'machine.get_script().resource_path=="res://scripts/build/hay_wrapper.gd"',
			'_uses_script(machine,["res://scripts/build/hay_wrapper.gd"])'
		)
		out = out.replace(
			"path.get_script()!=null and path.get_script().resource_path in RECOVERY_PATHS",
			"_uses_script(path,RECOVERY_PATHS)"
		)
		out = out.replace(
			"path.get_script()==null or path.get_script().resource_path not in RECOVERY_PATHS",
			"not _uses_script(path,RECOVERY_PATHS)"
		)
		out = out.replace(
			"not is_instance_valid(path) or _uses_script(path,RECOVERY_PATHS)",
			"not _uses_script(path,RECOVERY_PATHS)"
		)
		out = out.replace(
			"func _pulper_feeder_hold(kind:int,prior:Callable,enabled:bool) -> bool:\n\treturn kind==0 or (enabled and (not prior.is_valid() or bool(prior.call(kind))))",
			"func _pulper_feeder_hold(body:Object,prior:Callable,enabled:bool) -> bool:\n\tif enabled and (not prior.is_valid() or bool(prior.call(body))):return true\n\tvar rigid:=body as RigidBody3D\n\treturn is_instance_valid(rigid) and BeltPath.filter_kind(rigid)==BeltRun.Kind.WAD"
		)
		out = out.replace(
			"if entry.prior_outlet and (not entry.prior_hold.is_valid() or entry.prior_hold.call(0)):continue",
			"if entry.prior_outlet:continue"
		)
		out = out.replace(
			'Callable(self,"_feeder_holds_kind")',
			'Callable(self,"_feeder_holds_body")'
		)
		out = out.replace(
			"func _feeder_holds_kind(kind: int,machine_ref: WeakRef,prior: Callable,prior_enabled: bool) -> bool:\n\t# A native enabled outlet without a predicate holds every kind. Preserve\n\t# that contract, but do not turn an inactive native hold into a new one.\n\tif prior_enabled and (not prior.is_valid() or bool(prior.call(kind))):return true\n\treturn _refuses_kind(kind,machine_ref,Callable())",
			"func _feeder_holds_body(body: RigidBody3D,machine_ref: WeakRef,prior: Callable,prior_enabled: bool) -> bool:\n\tif prior_enabled and (not prior.is_valid() or bool(prior.call(body))):return true\n\treturn _refuses_body(body,machine_ref,Callable())"
		)
		out = out.replace(
			"machine.tree_exiting.connect(_forget_processor.bind(path.get_instance_id()),CONNECT_ONE_SHOT)",
			"if not machine.tree_exiting.is_connected(_forget_processor):\n\t\t\tmachine.tree_exiting.connect(_forget_processor.bind(path.get_instance_id()),CONNECT_ONE_SHOT)"
		)
		out = out.replace("BeltPath.record_kind(body)", "BeltPath.filter_kind(body)")
		out = out.replace("return kind in [0,4,5,6,7]", "return kind in [BeltRun.Kind.WAD,BeltRun.Kind.TUFT,4,5,6,7]")
	elif addon_name == "FTNMice":
		out = out.replace(
			'script != null and script.resource_path == "res://scripts/build/haystack_scanner.gd"',
			"(node is HaystackScanner)"
		)
		out = out.replace(
			"func peer_allowed(peer: Object) -> bool:\n\treturn peer == null or peer.get_class() == \"OfflineMultiplayerPeer\"",
			"func peer_allowed(peer: Object) -> bool:\n\tif peer == null or peer.get_class() == \"OfflineMultiplayerPeer\":\n\t\treturn true\n\treturn multiplayer.is_server()"
		)
	return out


func _sync_runtime() -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	if root == null:
		return
	for addon_name in ["FTNProductionSpeed", "FTNToolUpgrades"]:
		var mod := root.get_node_or_null(addon_name)
		if is_instance_valid(mod) and mod.is_node_ready() and mod.has_method("ensure_extensions"):
			mod.ensure_extensions()
	var authoritative: bool = mp == null or not mp.active() or mp.is_host
	var mice_mod := root.get_node_or_null("FTNMice")
	var cs := get_tree().current_scene
	var in_built_world: bool = mp != null and mp.is_world(cs) and bool(cs.get("_built"))
	var builds: Node = cs.get("builds") if in_built_world else null
	if is_instance_valid(mice_mod):
		if authoritative:
			if not mice_mod.is_processing():
				mice_mod.set_process(true)
			if is_instance_valid(builds) and "scanners" in builds and "sensors" in mice_mod:
				var sensors: Array = mice_mod.get("sensors")
				for scanner in builds.scanners:
					if is_instance_valid(scanner) and scanner.is_inside_tree() and not scanner.is_queued_for_deletion() and not bool(scanner.get("placement_preview")):
						if not (scanner in sensors):
							sensors.append(scanner)
		else:
			if mice_mod.get("world") != null and mice_mod.has_method("_detach"):
				mice_mod._detach()
	var speed_mod := root.get_node_or_null("FTNProductionSpeed")
	if is_instance_valid(speed_mod) and authoritative and is_instance_valid(builds):
		if speed_mod.has_method("_guard_processor") and "processor_paths" in speed_mod:
			var proc_paths: Dictionary = speed_mod.get("processor_paths")
			for group in ["compressors", "wrappers"]:
				var arr: Variant = builds.get(group)
				if arr is Array:
					for machine in arr:
						if is_instance_valid(machine) and machine.is_inside_tree() and not machine.is_queued_for_deletion() and not bool(machine.get("placement_preview")):
							var belt: Variant = machine.get("_belt")
							if belt is BeltPath and not proc_paths.has(belt.get_instance_id()):
								speed_mod._guard_processor(machine)
		if speed_mod.has_method("_guard_pulper") and "pulper_guards" in speed_mod:
			var pulper_guards: Dictionary = speed_mod.get("pulper_guards")
			var arr_p: Variant = builds.get("pulpers")
			if arr_p is Array:
				for machine in arr_p:
					if is_instance_valid(machine) and machine.is_inside_tree() and not machine.is_queued_for_deletion() and not bool(machine.get("placement_preview")):
						var belt: Variant = machine.get("_belt")
						if belt is BeltPath and not pulper_guards.has(belt.get_instance_id()):
							speed_mod._guard_pulper(machine)
		if "feeder_paths" in speed_mod and "conveyors" in builds:
			var f_paths: Dictionary = speed_mod.get("feeder_paths")
			for conv in builds.conveyors:
				if is_instance_valid(conv) and conv is BeltPath and conv.is_inside_tree() and not conv.is_queued_for_deletion() and not bool(conv.get("placement_preview")):
					var cid: int = conv.get_instance_id()
					if not f_paths.has(cid):
						f_paths[cid] = weakref(conv)
						if speed_mod.has_method("_forget_path") and not conv.tree_exiting.is_connected(speed_mod._forget_path):
							conv.tree_exiting.connect(speed_mod._forget_path.bind(cid), CONNECT_ONE_SHOT)
