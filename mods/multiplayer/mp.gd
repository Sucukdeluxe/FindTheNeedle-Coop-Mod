# Find The Needle - Multiplayer mod (autoload "MPMod").

# Loaded from override.cfg. Owns the ENet session, the lobby flow, the world
# hand-off and every RPC. Per-world syncing lives in mp_world.gd.
extends Node

const BuildSnapshot = preload("res://mods/multiplayer/mp_build_snapshot.gd")
const Progression = preload("res://mods/multiplayer/mp_progression.gd")
const VacUpgrades = preload("res://mods/multiplayer/mp_vac_upgrades.gd")

const VERSION := "0.19.6-xRangerDE.50"
const DEFAULT_PORT := 7777
const MAX_PEERS := 8  # players in a session, host included (Steam counts the same way)
const WORLD_CHUNK := 60000
const SESSION_DIR := "user://mp_session"
const SETTINGS_PATH := "user://mp_settings.cfg"
const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

const COLORS := [
	Color(0.95, 0.35, 0.3), Color(0.3, 0.65, 0.98), Color(0.4, 0.85, 0.4),
	Color(0.98, 0.78, 0.25), Color(0.75, 0.45, 0.95), Color(0.3, 0.9, 0.85),
	Color(0.98, 0.55, 0.8), Color(0.9, 0.9, 0.9),
]

enum Phase { OFFLINE, HOSTING, CONNECTING, LOBBY, LOADING, IN_WORLD }

var base_dir := ""
var ui: Node = null
var world_sync: Node = null
var _prestige_transition := false
var _prestige_host_reload := false
var phase: int = Phase.OFFLINE
var is_host := false
var players := {}  # peer id -> {name, color, state}
var _players_broadcast_pending := false
var my_name := "Player"  # replaced by the Steam name or the saved one
var last_ip := "127.0.0.1"
var last_port := DEFAULT_PORT

var i18n: RefCounted = null  # mp_i18n.gd: UI strings in the game's language
var steam: Node = null  # mp_steam.gd: Steam relay transport (no port forwarding)
var over_steam := false  # is the current session running through Steam?
var trace: Node = null  # mp_trace.gd: what came in last, for crash reports

var economy_sequence := 0
var tools_sequence := 0
var tool_profile := ""
var _tool_identities := {}
var _belt_visuals: Script
var _vac_upgrades := VacUpgrades.new()
var _progression := Progression.new()
var vacuum_transfer_local: Dictionary = {}
var vacuum_checkpoint: Node
var _last_scene: Node = null
var _menu_button: WeakRef
var _menu_retry := 0.0
var _world_rx := {}
var _pending_world: Variant = null
var _next_world_generation := 0
var _sent_world_generation := {}
var _world_load_generation := 0
var _world_load_aborted := false
var _pending_session := {}
var _mp_world_load := false  # client is loading a world sent by the host
var _world_watch: Node = null
var _steam_hosting := false  # waiting for our own lobby to be created
var _steam_joining := false  # we asked to join someone else (Steam also
# reports lobby_joined to the creator, which is not a join we should act on)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vac_upgrades.ensure_cards()
	_progression.ensure_cards()
	base_dir = get_script().resource_path.get_base_dir()
	load(base_dir + "/mp_hoppers.gd").ensure_catalog()
	_install_game_state()
	_install_save_manager()
	vacuum_checkpoint = load(base_dir + "/mp_vacuum_checkpoint.gd").new()
	add_child(vacuum_checkpoint)
	vacuum_checkpoint.start(self)
	_install_vacuum_tech()
	get_tree().node_added.connect(_guard_sale_stand)
	get_tree().node_added.connect(_guard_tech_panel)
	get_tree().node_added.connect(_guard_build_icons)
	get_tree().node_added.connect(_guard_save_menu)
	_belt_visuals = load(base_dir + "/mp_belt_visuals.gd")
	trace = load(base_dir + "/mp_trace.gd").new()
	trace.name = "MPTrace"
	add_child(trace)
	trace.start(VERSION)
	i18n = load(base_dir + "/mp_i18n.gd").new()
	_load_settings()
	_mp_guard_online_services()
	ui = load(base_dir + "/mp_ui.gd").new()
	ui.mp = self
	add_child(ui)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	steam = load(base_dir + "/mp_steam.gd").new()
	steam.name = "MPSteam"
	add_child(steam)
	steam.lobby_created.connect(_on_steam_lobby_created)
	steam.lobby_joined.connect(_on_steam_lobby_joined)
	steam.join_requested.connect(_on_steam_join_requested)
	_start_steam.call_deferred()
	if OS.get_environment("MP_TEST_HOST") != "" or OS.get_environment("MP_TEST_JOIN") != "" or OS.get_environment("MP_TEST_STEAM") != "" or OS.get_environment("MP_TEST_AVATAR") != "":
		# the test harness is a dev-only file and is not shipped in releases
		var test_script: Script = load(base_dir + "/mp_test.gd") if FileAccess.file_exists(base_dir + "/mp_test.gd") else null
		if test_script != null:
			var test: Node = test_script.new()
			test.mp = self
			add_child(test)
	for f in [
		"mp_arm_state.gd",
		"mp_arm_visual.gd",
		"mp_avatar.gd",
		"mp_belt_items.gd",
		"mp_belt_routes.gd",
		"mp_belt_snapshot.gd",
		"mp_belt_visuals.gd",
		"mp_belts.gd",
		"mp_boards.gd",
		"mp_build_actor.gd",
		"mp_build_camera.gd",
		"mp_build_snapshot.gd",
		"mp_build_tool.gd",
		"mp_builds.gd",
		"mp_carry.gd",
		"mp_catalog_panel.gd",
		"mp_contracts.gd",
		"mp_delivery_board.gd",
		"mp_diagnostic_state.gd",
		"mp_diagnostics.gd",
		"mp_distributor_drive.gd",
		"mp_distributor_t_splitter.gd",
		"mp_double_jump.gd",
		"mp_drone_state.gd",
		"mp_economy.gd",
		"mp_game_state.gd",
		"mp_save_manager.gd",
		"mp_hand.gd",
		"mp_hay_compressor.gd",
		"mp_hay_drone.gd",
		"mp_hay_lift.gd",
		"mp_hay_pelletizer.gd",
		"mp_hay_stairs.gd",
		"mp_hay_wrapper.gd",
		"mp_haystack_scanner.gd",
		"mp_hopper_build_tool.gd",
		"mp_hopper_icon.gd",
		"mp_hopper_model.gd",
		"mp_hopper_state.gd",
		"mp_hoppers.gd",
		"mp_hotkey_bar.gd",
		"mp_i18n.gd",
		"mp_junction_jam.gd",
		"mp_lift_cargo.gd",
		"mp_live_strand_manager.gd",
		"mp_load_panel.gd",
		"mp_machine_packet.gd",
		"mp_machines.gd",
		"mp_mice.gd",
		"mp_missions.gd",
		"mp_needle_cabinet.gd",
		"mp_needle_report.gd",
		"mp_needle_sync.gd",
		"mp_options_panel.gd",
		"mp_pause_menu.gd",
		"mp_player.gd",
		"mp_power.gd",
		"mp_power_tags.gd",
		"mp_prestige.gd",
		"mp_prestige_field.gd",
		"mp_prestige_inventory.gd",
		"mp_prestige_panel.gd",
		"mp_prestige_pile.gd",
		"mp_prestige_state.gd",
		"mp_prestige_store.gd",
		"mp_progression.gd",
		"mp_prop_manager.gd",
		"mp_props.gd",
		"mp_robotic_arm.gd",
		"mp_scanner_demolition.gd",
		"mp_scanner_sync.gd",
		"mp_selling_stand.gd",
		"mp_shop.gd",
		"mp_steam.gd",
		"mp_strands.gd",
		"mp_sweep.gd",
		"mp_t_panel.gd",
		"mp_tech.gd",
		"mp_tech_panel.gd",
		"mp_tool_prop.gd",
		"mp_tools.gd",
		"mp_trace.gd",
		"mp_ui.gd",
		"mp_vac_tech.gd",
		"mp_vac_upgrades.gd",
		"mp_vacuum_transfer.gd",
		"mp_vacuum_checkpoint.gd",
		"mp_wire_mode.gd",
		"mp_world.gd",
		"mp_yard_vac.gd"
	]:
		var s: Script = load(base_dir + "/" + f)
		if s == null or not s.can_instantiate():
			push_error("[MPMod] %s failed to compile" % f)
	print("[MPMod] v%s loaded from %s" % [VERSION, base_dir])


func _guard_build_icons(node: Node) -> void:
	var file := ""
	var native_path := ""
	if node is CatalogPanel:
		file = "mp_catalog_panel.gd"
		native_path = "res://scripts/ui/catalog_panel.gd"
	elif node is HotkeyBar:
		file = "mp_hotkey_bar.gd"
		native_path = "res://scripts/ui/hotkey_bar.gd"
	else:
		return
	var original: Script = node.get_script()
	if original == null or original.resource_path != native_path:
		return
	var values := {}
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = node.get(property.name)
	node.set_script(load(base_dir + "/" + file))
	for key in values:
		if key in node:
			node.set(key, values[key])

func _guard_save_menu(node: Node) -> void:
	if not node is PauseMenu:
		return
	var original: Script = node.get_script()
	if original == null or original.resource_path != "res://scripts/ui/pause_menu.gd":
		return
	var values := {}
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = node.get(property.name)
	node.set_script(load(base_dir + "/mp_pause_menu.gd"))
	for key in values:
		if key in node:
			node.set(key, values[key])


func _guard_tech_panel(node: Node) -> void:
	if not (node is TechPanel):
		return
	var original: Script = node.get_script()
	if original == null or original.resource_path != "res://scripts/ui/tech_panel.gd":
		return
	var values := {}
	for property in node.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = node.get(property.name)
	node.set_script(load(base_dir + "/mp_tech_panel.gd"))
	for key in values:
		if key in node:
			node.set(key, values[key])


func _guard_sale_stand(node: Node) -> void:
	if not (node is HaySellingStand):
		return
	var patch: Script = load(base_dir + "/mp_selling_stand.gd")
	patch.install(node, patch)


# One line in the trace for a message that just arrived: which one, from whom
# and, for the big ones, how many bytes or entries.
func _trace(what: String, size: int = -1) -> void:
	if trace == null:
		return
	var from := multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0
	trace.rx(what, from, size)


# UI string in whatever language the game is set to.
func t(key: String) -> String:
	return i18n.t(key)


func _process(_delta: float) -> void:
	_vac_upgrades.ensure_cards()
	_progression.ensure_cards()
	if _belt_visuals != null:
		_belt_visuals.install_current(_belt_visuals)
	var cs := get_tree().current_scene
	if cs != _last_scene:
		_last_scene = cs
		_on_scene_changed(cs)
	_update_menu_hook(cs, _delta)
	if _world_watch != null and is_instance_valid(_world_watch) and world_sync == null:
		if bool(_world_watch.get("_built")):
			_start_world_sync(_world_watch)


# ---------------------------------------------------------------- scenes

func is_world(n: Node) -> bool:
	# exported scripts may be remapped to .gdc, so recognise the world by its members
	return n != null and "_built" in n and "field" in n and "builds" in n


func is_menu(n: Node) -> bool:
	return n != null and (n.scene_file_path == MENU_SCENE or n.has_method("_on_multiplayer"))


func _update_menu_hook(menu: Node, delta: float) -> void:
	if not is_instance_valid(menu) or not is_menu(menu):
		_menu_button = null
		_menu_retry = 0.0
		return
	var button: Variant = _menu_button.get_ref() if _menu_button != null else null
	if is_instance_valid(button) and button.is_inside_tree() and menu.is_ancestor_of(button):
		return
	_menu_button = null
	_menu_retry -= delta
	if _menu_retry > 0.0:
		return
	_menu_retry = 0.25
	button = ui._find_mp_button(menu)
	if button == null:
		return
	_menu_button = weakref(button)
	ui.hook_menu(menu)


func _on_scene_changed(cs: Node) -> void:
	_stop_world_sync()
	_stay_last.call_deferred()
	_world_watch = null
	if is_menu(cs):
		if _world_load_aborted and not _mp_world_load:
			_world_load_aborted = false
			SaveManager.use_player_saves()
			SaveManager.block_save = false
			release_profile()
			if not _pending_session.is_empty():
				_start_pending_session()
				return
			var next: Variant = _pending_world
			_pending_world = null
			if next != null and active() and not is_host and _world_rx.is_empty():
				_enter_mp_world(next.payload, next.generation)
				return
		if active() and not is_host and phase == Phase.IN_WORLD:
			# client walked back to the title: that ends its session
			leave(t("left_game"))
		elif active() and is_host:
			# clients drop back to the lobby and get the world again when we return
			for pid in players.keys():
				if pid != 1:
					players[pid]["state"] = "lobby"
			_broadcast_host_in_world(false)
	elif is_world(cs):
		_world_watch = cs


func _start_world_sync(world: Node) -> void:
	if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree() or world != get_tree().current_scene or not bool(world.get("_built")):
		return
	if _mp_world_load:
		if _world_load_aborted:
			_return_client_to_menu()
			return
		if not _world_rx.is_empty():
			get_tree().paused = true
			if not Loading.is_active():
				Loading.show_screen("FIND THE NEEDLE", t("receiving_world"))
			return
		if _pending_world != null:
			var next: Dictionary = _pending_world
			_pending_world = null
			_mp_world_load = false
			_enter_mp_world(next.payload, next.generation)
			return
	_prestige_transition = false
	_prestige_host_reload = false
	trace.note("world sync starts (%s, %s)" % ["host" if is_host else "guest", "steam" if over_steam else "ip"])
	world_sync = load(base_dir + "/mp_world.gd").new()
	world_sync.name = "MPWorld"
	world_sync.mp = self
	world_sync.world = world
	add_child(world_sync)
	if not active():
		return
	if is_host:
		_broadcast_host_in_world(true)
		for pid in players.keys():
			if pid != 1 and str(players[pid].get("state", "")) != "world":
				send_world(pid)
	elif _mp_world_load:
		_mp_world_load = false
		phase = Phase.IN_WORLD
		world_sync.place_at_spawn()
		ui.restore_world_input(world_sync.player)
		ui.notify(t("connected_yard"))
		_rx_client_ready.rpc_id(1, _world_load_generation)


# When the game quits, Godot takes the scene tree down from the last child of
# the root to the first, so a new scene (added after us) went first and the
# world was pulled down with our guest-side changes still in it: the straw
# copies we put back into the physics world by hand, the stopped machines, the
# frozen puppets. That crashed a guest on every quit. Staying the root's last
# child means we go first and undo all of it while the world is still whole.
func _stay_last() -> void:
	var root := get_tree().root
	if get_parent() == root and get_index() != root.get_child_count() - 1:
		root.move_child(self, root.get_child_count() - 1)


func _exit_tree() -> void:
	_stop_world_sync()


func _stop_world_sync() -> void:
	if world_sync != null:
		world_sync.process_mode = Node.PROCESS_MODE_DISABLED
		world_sync.shutdown()
		world_sync.queue_free()
		world_sync = null


func in_world() -> bool:
	return world_sync != null


func active() -> bool:
	return phase != Phase.OFFLINE


# ---------------------------------------------------------------- Steam session
# Steam's relay does the NAT work: both players connect out to Steam, so
# nobody opens a port and friends join from the Steam friends list.

func _start_steam() -> void:
	var res: Dictionary = steam.setup(base_dir)
	print("[MPMod] steam: ", res["status"])
	if not res["ok"]:
		if _custom_name == "":
			my_name = default_name()
		ui.refresh()
		return
	if _custom_name == "":
		my_name = steam.persona.substr(0, 24)
	ui.refresh()
	# launched by accepting an invite while the game was closed
	var lobby: int = steam.lobby_from_command_line()
	if lobby != 0:
		join_steam(lobby)


func steam_ready() -> bool:
	return steam != null and steam.available


func host_steam() -> bool:
	if not _session_switch_ready():
		return false
	if not steam_ready():
		ui.notify(t("steam_unavailable_long"))
		return false
	if active():
		leave()
	if _world_load_aborted:
		_pending_session = {"action": "host_steam"}
		return true
	_steam_hosting = true
	_steam_joining = false
	ui.notify(t("steam_creating"))
	steam.host_lobby(MAX_PEERS)
	return true


func join_steam(lobby_id: int) -> bool:
	if not _session_switch_ready():
		return false
	if not steam_ready():
		ui.notify(t("steam_unavailable"))
		return false
	if active():
		leave()
	if _world_load_aborted:
		_pending_session = {"action": "join_steam", "lobby": lobby_id}
		return true
	ui.notify(t("steam_entering"))
	_steam_joining = true
	_steam_hosting = false
	phase = Phase.CONNECTING
	steam.join_lobby(lobby_id)
	ui.refresh()
	return true


func invite_friends() -> void:
	if steam_ready() and steam.lobby_id != 0:
		steam.invite_overlay()
	else:
		ui.notify(t("create_first"))


func _on_steam_lobby_created(ok: bool, id: int) -> void:
	if not _steam_hosting:
		return
	_steam_hosting = false
	if not ok:
		ui.notify(t("steam_create_failed"))
		return
	var peer: MultiplayerPeer = steam.make_peer()
	if peer == null:
		ui.notify(t("steam_peer_failed"))
		return
	peer.call("host_with_lobby", id)
	multiplayer.multiplayer_peer = peer
	over_steam = true
	_become_host()
	ui.notify(t("game_created"))


func _on_steam_lobby_joined(ok: bool, id: int, reason: String) -> void:
	if not _steam_joining:
		return  # Steam tells the creator it "joined" its own lobby; ignore that
	_steam_joining = false
	if not ok:
		leave(t("steam_join_failed") % reason)
		return
	var peer: MultiplayerPeer = steam.make_peer()
	if peer == null:
		leave(t("steam_peer_failed"))
		return
	peer.call("connect_to_lobby", id)
	multiplayer.multiplayer_peer = peer
	over_steam = true
	is_host = false
	phase = Phase.CONNECTING
	ui.refresh()


func _on_steam_join_requested(lobby_id: int) -> void:
	# invite accepted (overlay or friends list) while the game is running
	join_steam(lobby_id)


# ---------------------------------------------------------------- session

func _become_host() -> void:
	is_host = true
	phase = Phase.HOSTING
	players = {1: {"name": my_name, "color": COLORS[0], "state": "world" if in_world() else "menu"}}
	_mp_guard_online_services()
	if world_sync != null:
		world_sync.rebaseline()
		world_sync.apply_session_rules()
	if not in_world():
		ui.notify(t("now_load"))
	ui.refresh()


func host(port: int) -> bool:
	if not _session_switch_ready():
		return false
	if active():
		leave()
	if _world_load_aborted:
		_pending_session = {"action": "host", "port": port}
		return true
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS - 1)
	if err != OK:
		ui.notify(t("port_failed") % [port, err])
		return false
	multiplayer.multiplayer_peer = peer
	over_steam = false
	last_port = port
	_save_settings()
	ui.notify(t("server_open") % port)
	_become_host()
	return true


func join(ip: String, port: int) -> bool:
	if not _session_switch_ready():
		return false
	if active():
		leave()
	if _world_load_aborted:
		_pending_session = {"action": "join", "ip": ip, "port": port}
		return true
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		ui.notify(t("peer_failed") % err)
		return false
	multiplayer.multiplayer_peer = peer
	over_steam = false
	is_host = false
	phase = Phase.CONNECTING
	last_ip = ip
	last_port = port
	_save_settings()
	ui.notify(t("connecting"))  # no addresses on screen: people stream this
	ui.refresh()
	return true


func leave(reason: String = "") -> void:
	trace.note("leave session")
	var was_client := active() and not is_host
	var was_in_mp_world := was_client and (in_world() or _mp_world_load)
	if is_instance_valid(world_sync):
		world_sync.session_ended()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if steam_ready():
		steam.leave_lobby()
	over_steam = false
	_steam_hosting = false
	_steam_joining = false
	phase = Phase.OFFLINE
	is_host = false
	players.clear()
	_world_rx.clear()
	_pending_world = null
	_sent_world_generation.clear()
	_pending_session.clear()
	if world_sync != null:
		world_sync.clear_avatars()
	if was_in_mp_world:
		_exit_client_world()
	elif not _world_load_aborted:
		_mp_world_load = false
		if was_client:
			SaveManager.block_save = false
			SaveManager.use_player_saves()
		release_profile()
	if reason != "":
		ui.notify(reason)
	ui.refresh()


func _exit_client_world() -> void:
	_pending_world = null
	_world_rx.clear()
	_world_load_aborted = true
	SaveManager.block_save = true
	if _mp_world_load:
		return
	_return_client_to_menu()


func _return_client_to_menu() -> void:
	_mp_world_load = false
	_world_watch = null
	_stop_world_sync()
	get_tree().paused = false
	Loading.hide_screen()
	get_tree().change_scene_to_file(MENU_SCENE)


func _start_pending_session() -> void:
	var request := _pending_session
	_pending_session = {}
	match request.get("action", ""):
		"host":
			host(request.port)
		"join":
			join(request.ip, request.port)
		"host_steam":
			host_steam()
		"join_steam":
			join_steam(request.lobby)


func _session_switch_ready() -> bool:
	if _mp_world_load or _world_load_aborted:
		ui.notify(t("loading_world"))
		return false
	return true


func _mp_guard_online_services() -> void:
	# keep modded runs off the public leaderboard
	var lb := get_node_or_null("/root/Leaderboard")
	if lb != null and "enabled" in lb:
		lb.enabled = false


# Career stats. The shared GameState carries everyone's digging, selling and
# needles, and the game's Profile adds up whatever GameState gains, so a
# session would credit each player with the whole team's work. While a session
# runs the profile is held: pending stats are written first, then nothing is
# saved; when the session ends the profile is read back from disk, which drops
# the team's totals, and the yard is re-baselined so solo play counts again.
var _profile_held := false


func hold_profile() -> void:
	if _profile_held:
		return
	var pf := get_node_or_null("/root/Profile")
	if pf == null or not ("_inert" in pf):
		return
	if not bool(pf.get("_inert")) and pf.has_method("save_profile"):
		pf.save_profile()
	pf.set("_inert", true)
	_profile_held = true


func release_profile() -> void:
	if not _profile_held:
		return
	_profile_held = false
	var pf := get_node_or_null("/root/Profile")
	if pf == null:
		return
	pf.set("_inert", false)
	if pf.has_method("load_profile"):
		pf.load_profile()
	if in_world() and bool(pf.get("_in_yard")) and pf.has_method("enter_yard"):
		pf.enter_yard()


func _on_peer_connected(id: int) -> void:
	trace.note("peer %d connected" % id)
	if is_host:
		print("[MPMod] peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	trace.note("peer %d disconnected" % id)
	_sent_world_generation.erase(id)
	if players.has(id):
		ui.notify(t("left") % players[id]["name"], players[id]["color"])
		players.erase(id)
	if world_sync != null:
		world_sync.remove_avatar(id)
	if is_host:
		_queue_player_broadcast()
		if world_sync != null:
			world_sync.forget_peer(id)
	ui.refresh()


func _queue_player_broadcast() -> void:
	if _players_broadcast_pending:
		return
	_players_broadcast_pending = true
	_broadcast_players.call_deferred()


func _broadcast_players() -> void:
	_players_broadcast_pending = false
	if not is_host or not active():
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	for id in multiplayer.get_peers():
		if not players.has(id):
			continue
		if peer is ENetMultiplayerPeer:
			var connection: ENetPacketPeer = peer.get_peer(id)
			if connection == null or connection.get_state() != ENetPacketPeer.STATE_CONNECTED:
				continue
		_rx_players.rpc_id(id, players)


func _on_connected() -> void:
	phase = Phase.LOBBY
	ui.notify(t("connected_waiting"))
	_rx_hello.rpc_id(1, my_name, VERSION, tool_profile)
	ui.refresh()


func _on_connection_failed() -> void:
	leave(t("connect_failed"))


func _on_server_disconnected() -> void:
	trace.note("lost the host")
	leave(t("host_closed"))


func _broadcast_host_in_world(on: bool) -> void:
	if not on:
		_sent_world_generation.clear()
	if players.has(1):
		players[1]["state"] = "world" if on else "menu"
	_broadcast_players()
	ui.refresh()


func player_name(id: int) -> String:
	if players.has(id):
		return str(players[id]["name"])
	return t("player_fallback") % id


func player_color(id: int) -> Color:
	if players.has(id):
		return players[id]["color"]
	return Color.WHITE


# ---------------------------------------------------------------- lobby RPCs

@rpc("any_peer", "call_remote", "reliable")
func _rx_hello(pname: String, ver: String, profile: String) -> void:
	_trace("hello")
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if ver != VERSION:
		_rx_kick.rpc_id(id, t("version_mismatch") % [VERSION, ver])
		return
	if profile.length() != 32 or not profile.is_valid_hex_number(false):
		_rx_kick.rpc_id(id, t("connect_failed"))
		return
	var identity := "profile:" + profile
	if over_steam and multiplayer.multiplayer_peer.has_method("get_steam_id_for_peer_id"):
		var steam_id := int(multiplayer.multiplayer_peer.call("get_steam_id_for_peer_id", id))
		if steam_id > 0:
			identity = "steam:" + str(steam_id)
	for connected in _tool_identities:
		if connected != id and players.has(connected) and _tool_identities[connected] == identity:
			_rx_kick.rpc_id(id, t("connect_failed"))
			return
	_tool_identities[id] = identity
	var used := {}
	for p in players.values():
		used[p["color"]] = true
	var col: Color = COLORS[players.size() % COLORS.size()]
	for c in COLORS:
		if not used.has(c):
			col = c
			break
	pname = pname.strip_edges().substr(0, 24)
	if pname == "":
		pname = t("player_fallback") % id
	players[id] = {"name": pname, "color": col, "state": "lobby"}
	ui.notify(t("joined") % pname, col)
	_broadcast_players()
	ui.refresh()
	if in_world():
		send_world(id)


@rpc("authority", "call_remote", "reliable")
func _rx_kick(reason: String) -> void:
	_trace("kick")
	leave(reason)


@rpc("authority", "call_remote", "reliable")
func _rx_players(list: Dictionary) -> void:
	_trace("players", list.size())
	var before := players.keys()
	players = list
	if world_sync != null:
		for id in before:
			if not players.has(id):
				world_sync.remove_avatar(id)
	if not is_host and players.has(1) and phase in [Phase.IN_WORLD, Phase.LOADING] and str(players[1].get("state", "")) == "menu":
		phase = Phase.LOBBY
		ui.notify(t("host_back_menu"))
		if in_world() or _mp_world_load:
			_exit_client_world()
		else:
			_pending_world = null
			_world_rx.clear()
	elif not is_host and players.has(1) and phase == Phase.LOBBY:
		if str(players[1].get("state", "")) != "world":
			ui.set_status(t("host_in_menu"))
	ui.refresh()


@rpc("any_peer", "call_remote", "reliable")
func _rx_client_ready(generation: int) -> void:
	_trace("client_ready")
	if not is_host or not is_instance_valid(world_sync) or not is_instance_valid(world_sync.world) or world_sync.world != get_tree().current_scene:
		return
	var id := multiplayer.get_remote_sender_id()
	if generation <= 0 or int(_sent_world_generation.get(id, -1)) != generation or not players.has(id) or players[id].get("state") != "loading":
		return
	_sent_world_generation.erase(id)
	if players.has(id):
		players[id]["state"] = "world"
		_broadcast_players()
	if world_sync != null:
		world_sync._peer_ack.erase(id)
		world_sync.send_full_sync(id)
	ui.refresh()


@rpc("any_peer", "call_remote", "reliable")
func _rx_chat(text: String) -> void:
	_trace("chat")
	var id := multiplayer.get_remote_sender_id()
	ui.chat_line(player_name(id), player_color(id), text.substr(0, 200))


func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text == "" or not active():
		return
	_rx_chat.rpc(text)
	ui.chat_line(my_name, player_color(multiplayer.get_unique_id()), text)


# ---------------------------------------------------------------- world hand-off

func send_world(id: int) -> void:
	if not is_host or not active() or not is_instance_valid(world_sync) or not players.has(id):
		return
	if players.has(id):
		players[id]["state"] = "loading"
	_next_world_generation += 1
	_sent_world_generation[id] = _next_world_generation
	var payload: Dictionary = world_sync.build_payload(id)
	var raw := var_to_bytes(payload)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var n := int(ceil(float(packed.size()) / WORLD_CHUNK))
	print("[MPMod] sending world to %d: %d KB (%d KB raw), %d chunks" % [id, packed.size() / 1024, raw.size() / 1024, n])
	_rx_world_begin.rpc_id(id, raw.size(), packed.size(), n, _next_world_generation)
	for i in n:
		_rx_world_chunk.rpc_id(id, i, packed.slice(i * WORLD_CHUNK, mini((i + 1) * WORLD_CHUNK, packed.size())))
	_rx_world_end.rpc_id(id)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_world_begin(raw_size: int, packed_size: int, chunks: int, generation: int) -> void:
	_trace("world_begin")
	if not active() or is_host or generation <= 0:
		return
	_world_rx = {"raw": raw_size, "size": packed_size, "n": chunks, "parts": {}, "generation": generation}
	phase = Phase.LOADING
	ui.set_status(t("receiving_world"))
	ui.set_progress(0.0)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_world_chunk(i: int, data: PackedByteArray) -> void:
	_trace("world_chunk", data.size())
	if _world_rx.is_empty():
		return
	_world_rx["parts"][i] = data
	ui.set_progress(float(_world_rx["parts"].size()) / maxf(1.0, float(_world_rx["n"])))


@rpc("authority", "call_remote", "reliable", 0)
func _rx_world_end() -> void:
	_trace("world_end")
	if _world_rx.is_empty():
		return
	var packed := PackedByteArray()
	for i in int(_world_rx["n"]):
		if not _world_rx["parts"].has(i):
			leave(t("world_incomplete"))
			return
		packed.append_array(_world_rx["parts"][i])
	var raw := packed.decompress(int(_world_rx["raw"]), FileAccess.COMPRESSION_ZSTD)
	var generation: int = _world_rx["generation"]
	_world_rx.clear()
	var payload: Variant = bytes_to_var(raw)
	if typeof(payload) != TYPE_DICTIONARY:
		leave(t("world_unreadable"))
		return
	ui.set_progress(-1.0)
	_enter_mp_world(payload, generation)


func _enter_mp_world(payload: Dictionary, generation: int) -> void:
	if _mp_world_load or _world_load_aborted:
		_pending_world = {"payload": payload, "generation": generation}
		return
	_world_load_generation = generation
	hold_profile()
	ui.prepare_world_load()
	_world_watch = null
	_stop_world_sync()
	SaveManager.use_scratch_dir(SESSION_DIR)
	var path := SaveManager.slot_path(0)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_world_load_aborted = true
		SaveManager.block_save = true
		leave(t("world_write_failed") % FileAccess.get_open_error())
		_return_client_to_menu()
		return
	f.store_var(payload, true)
	f.close()
	SaveManager.block_save = false
	SaveManager.begin_load(0)
	_mp_world_load = true
	get_tree().paused = true
	phase = Phase.LOADING
	ui.set_status(t("loading_world"))
	Loading.show_screen("FIND THE NEEDLE", t("entering_yard") % player_name(1).to_upper())
	Loading.enter_scene(GAME_SCENE)


# Host: re-send the whole world to every client (after a new pile, or on demand).
func resync_all() -> void:
	if not is_host or world_sync == null:
		return
	for pid in players.keys():
		if pid != 1:
			send_world(pid)


@rpc("any_peer", "call_remote", "reliable")
func _rx_request_world(world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("request_world")
	if is_host and world_sync != null:
		world_sync.send_full_sync(multiplayer.get_remote_sender_id())


func request_resync() -> void:
	if not active() or not is_instance_valid(world_sync):
		return
	if is_host:
		for pid in players:
			if pid != 1 and players[pid].get("state") == "world":
				world_sync.send_full_sync(pid)
		ui.notify(t("resyncing_all"))
	else:
		if world_sync != null:
			world_sync._state_tick()
		_rx_request_world.rpc_id(1, _outgoing_world_seed())
		ui.notify(t("asking_world"))


# ---------------------------------------------------------------- in-world RPCs (forwarded to mp_world)

@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _rx_pose(pos: Vector3, yaw: float, pitch: float, tool: int, crouch: float, moving: float, hands: int, tool_fill: float = 0.0, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null:
		world_sync.on_pose(multiplayer.get_remote_sender_id(), pos, yaw, pitch, tool, crouch, moving, hands, tool_fill)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_hay(idx: PackedInt32Array, vals: PackedFloat32Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("hay", idx.size())
	if world_sync != null:
		world_sync.on_hay(multiplayer.get_remote_sender_id(), idx, vals)


# Host -> guest: a checksum per block of the pile, so a guest can find where it
# drifted from the host and ask for just those blocks.
@rpc("authority", "call_remote", "reliable", 0)
func _rx_hay_sums(sums: PackedFloat32Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("hay_sums", sums.size())
	if world_sync != null:
		world_sync.on_hay_sums(sums)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_hay_want(blocks: PackedInt32Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("hay_want", blocks.size())
	if is_host and world_sync != null:
		world_sync.on_hay_want(multiplayer.get_remote_sender_id(), blocks)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_builds(adds: Array, removes: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("builds", adds.size())
	if is_host or multiplayer.get_remote_sender_id() != 1:
		return
	if world_sync != null:
		world_sync.on_builds(adds, removes)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_state_delta(seq: int, delta: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("state_delta", delta.size())
	if is_host and world_sync != null:
		world_sync.on_state_delta(multiplayer.get_remote_sender_id(), seq, delta)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_state_snap(ack: int, snap: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("state_snap", snap.size())
	if world_sync != null:
		world_sync.on_state_snap(ack, snap)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_tech(id: String, rank: int, paid: bool, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("tech")
	if world_sync != null:
		world_sync.on_tech(multiplayer.get_remote_sender_id(), id, rank, paid)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_full_sync(heights: PackedFloat32Array, builds: Array, tech: Dictionary, needles: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("full_sync", heights.size())
	if world_sync != null:
		world_sync.on_full_sync(heights, builds, tech, needles)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_new_pile_request(on_credit: bool, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("new_pile_request")
	if is_host and world_sync != null:
		world_sync.host_new_pile_for_client(multiplayer.get_remote_sender_id(), on_credit)


# Host -> everyone: what happened to a loose needle. The host decides who holds
# it, so two players grabbing the same needle cannot both hand it in.
@rpc("authority", "call_remote", "reliable", 0)
func _rx_needle(kind: String, idx: int, pos: Vector3, holder: int, velocity: Vector3 = Vector3.ZERO, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("needle")
	if world_sync != null:
		world_sync.on_needle(kind, idx, pos, holder, velocity)


# Guest -> host: a guest picked a needle up, put it down or used it up.
@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_needle_req(kind: String, idx: int, pos: Vector3, velocity: Vector3 = Vector3.ZERO, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("needle_req")
	if is_host and world_sync != null:
		world_sync.on_needle_req(multiplayer.get_remote_sender_id(), kind, idx, pos, velocity)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_event(kind: String, data: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("event", data.size())
	if world_sync != null:
		world_sync.on_event(multiplayer.get_remote_sender_id(), kind, data)


# ---------------------------------------------------------------- loose items

func _props() -> Node:
	if world_sync == null:
		return null
	return world_sync.props_sync


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_add(id: int, item_id: String, xf: Transform3D, state: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_add", state.size())
	var p := _props()
	if p != null:
		p.on_add(multiplayer.get_remote_sender_id(), id, item_id, xf, state)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_del(ids: PackedInt64Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_del", ids.size())
	var p := _props()
	if p != null:
		p.on_del(multiplayer.get_remote_sender_id(), ids)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _rx_prop_move(ids: PackedInt64Array, xfs: Array, sequence: int = 0, epochs: PackedInt64Array = PackedInt64Array(), world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_move", ids.size())
	var p := _props()
	if p != null:
		p.on_move(multiplayer.get_remote_sender_id(), ids, xfs, sequence, epochs)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_rest(ids: PackedInt64Array, xfs: Array, sequence: int, epochs: PackedInt64Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_rest", ids.size())
	var p := _props()
	if p != null:
		p.on_move(multiplayer.get_remote_sender_id(), ids, xfs, sequence, epochs)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_state(ids: PackedInt64Array, states: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_state", ids.size())
	var p := _props()
	if p != null:
		p.on_state(multiplayer.get_remote_sender_id(), ids, states)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_claim(id: int, expected: int, holding: bool, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_claim")
	var p := _props()
	if p != null and is_host:
		p.on_claim_request(multiplayer.get_remote_sender_id(), id, expected, holding)


# A guest's belt took one of its items. Only the host's belts count, so the
# host puts its own copy down there instead.
@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_board(id: int, xf: Transform3D, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_board")
	var p := _props()
	if p != null and is_host:
		p.on_board(multiplayer.get_remote_sender_id(), id, xf)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_want(ids: PackedInt64Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_want", ids.size())
	var p := _props()
	if p != null:
		p.on_want(multiplayer.get_remote_sender_id(), ids)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_prop_census(ids: PackedInt64Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_census", ids.size())
	var p := _props()
	if p != null:
		p.on_census(multiplayer.get_remote_sender_id(), ids)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_prop_reset(first: bool, ids: PackedInt64Array, owners: PackedInt32Array, entries: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_reset", ids.size())
	var p := _props()
	if p != null:
		p.on_reset(first, ids, owners, entries)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_prop_reset_end(world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("prop_reset_end")
	var p := _props()
	if p != null:
		p.on_reset_end()


@rpc("authority", "call_remote", "reliable", 0)
func _rx_belts(packed: PackedByteArray, raw_size: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("belts", packed.size())
	if world_sync == null or world_sync.belts_sync == null:
		return
	world_sync.belts_sync.on_belts(packed, raw_size)


# ---------------------------------------------------------------- machines

@rpc("authority", "call_remote", "unreliable_ordered", 0)
func _rx_machines(packed: PackedByteArray, raw_size: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("machines", packed.size())
	if world_sync == null or world_sync.machines_sync == null:
		return
	world_sync.machines_sync.on_poses(packed, raw_size)


# The same, for batches too big for one packet (a lost fragment would drop the
# whole batch on the unreliable channel) and the periodic full refresh.
@rpc("authority", "call_remote", "reliable", 0)
func _rx_machines_big(packed: PackedByteArray, raw_size: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("machines_big", packed.size())
	if world_sync == null or world_sync.machines_sync == null:
		return
	world_sync.machines_sync.on_poses(packed, raw_size)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_scanner_state(epoch: String, sequence: int, state: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null and is_instance_valid(world_sync.scanner_sync):
		world_sync.scanner_sync.on_state(epoch, sequence, state)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_scanner_request(epoch: String, sequence: int, key: String, mode: String, index: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and world_sync != null and is_instance_valid(world_sync.scanner_sync):
		world_sync.scanner_sync.on_request(multiplayer.get_remote_sender_id(), epoch, sequence, key, mode, index)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_scanner_result(epoch: String, sequence: int, result: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null and is_instance_valid(world_sync.scanner_sync):
		world_sync.scanner_sync.on_result(epoch, sequence, result)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_scanner_ack(epoch: String, sequence: int, success: bool, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and world_sync != null and is_instance_valid(world_sync.scanner_sync):
		world_sync.scanner_sync.on_ack(multiplayer.get_remote_sender_id(), epoch, sequence, success)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_mice(epoch: String, sequence: int, packed: PackedByteArray, raw_size: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null and is_instance_valid(world_sync.mice_sync):
		world_sync.mice_sync.on_state(epoch, sequence, packed, raw_size)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_power_state(epoch: String, state: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null and is_instance_valid(world_sync.power_sync):
		world_sync.power_sync.on_state(epoch, state)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_machine_fields(batch: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("machine_fields", batch.size())
	if world_sync == null or world_sync.machines_sync == null:
		return
	world_sync.machines_sync.on_fields(batch)


# A guest worked a machine's panel. The machine runs on the host, so the host
# is the only one that acts on this; everyone else hears about it in the next
# field tick like any other change.
@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_machine_edit(batch: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("machine_edit", batch.size())
	if not is_host or world_sync == null or world_sync.machines_sync == null:
		return
	world_sync.machines_sync.on_edit(multiplayer.get_remote_sender_id(), batch)


# A piece of a paint board's drawing; boards_sync puts the pieces together.
@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_board(key: String, id: int, i: int, n: int, raw_size: int, piece: PackedByteArray, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("board", piece.size())
	if world_sync == null or world_sync.boards_sync == null:
		return
	if is_host or multiplayer.get_remote_sender_id() == 1:
		world_sync.boards_sync.on_piece(key, id, i, n, raw_size, piece)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_contract(state: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("contract", state.size())
	if world_sync == null or world_sync.contracts_sync == null:
		return
	world_sync.contracts_sync.on_state(state)


# ---------------------------------------------------------------- loose straw

func _straws() -> Node:
	if world_sync == null:
		return null
	return world_sync.strands_sync


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_straw_add(adds: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("straw_add", adds.size())
	var s := _straws()
	if s != null:
		s.on_add(multiplayer.get_remote_sender_id(), adds)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _rx_straw_move(ids: PackedInt64Array, rows: PackedFloat32Array, sequence: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("straw_move", ids.size())
	var s := _straws()
	if s != null:
		s.on_move(multiplayer.get_remote_sender_id(), ids, rows, sequence)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_straw_del(ids: PackedInt64Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("straw_del", ids.size())
	var s := _straws()
	if s != null:
		s.on_del(multiplayer.get_remote_sender_id(), ids)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_straw_census(ids: PackedInt64Array, rows: PackedFloat32Array, sequence: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("straw_census", ids.size())
	var s := _straws()
	if s != null:
		s.on_census(multiplayer.get_remote_sender_id(), ids, rows, sequence)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_straw_claim(sid: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	_trace("straw_claim")
	var s := _straws()
	if s != null:
		s.on_claim(multiplayer.get_remote_sender_id(), sid)


# ---------------------------------------------------------------- settings

var _custom_name := ""  # a name typed in the panel; empty = use the Steam name


func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) == OK:
		_custom_name = str(c.get_value("mp", "custom_name", ""))
		last_ip = str(c.get_value("mp", "ip", last_ip))
		last_port = int(c.get_value("mp", "port", DEFAULT_PORT))
		tool_profile = str(c.get_value("mp", "tool_profile", ""))
	if tool_profile.length() != 32 or not tool_profile.is_valid_hex_number(false):
		tool_profile = Crypto.new().generate_random_bytes(16).hex_encode()
		_save_settings()
	# the Steam persona replaces this once Steam is up (see _start_steam); the
	# slower lookup in default_name() only runs when Steam is not available
	var user := OS.get_environment("USERNAME").substr(0, 24)
	my_name = _custom_name if _custom_name != "" else (user if user != "" else t("default_name"))


func _save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("mp", "custom_name", _custom_name)
	c.set_value("mp", "ip", last_ip)
	c.set_value("mp", "port", last_port)
	c.set_value("mp", "tool_profile", tool_profile)
	c.save(SETTINGS_PATH)


# Called by the panel when the player edits the name field.
func set_player_name(n: String) -> void:
	n = n.strip_edges().substr(0, 24)
	if n == "":
		return
	my_name = n
	_custom_name = "" if n == default_name() else n
	_save_settings()


func default_name() -> String:
	var steam := steam_name()
	if steam != "":
		return steam.substr(0, 24)
	var user := OS.get_environment("USERNAME")
	return user.substr(0, 24) if user != "" else t("default_name")


var _steam_name_cache: Variant = null


# The demo has no Steam API, so read the persona name Steam keeps on disk
# (config/loginusers.vdf): the MostRecent account, else the newest login.
func steam_name() -> String:
	if _steam_name_cache != null:
		return _steam_name_cache
	_steam_name_cache = ""
	var roots: Array[String] = []
	var out: Array = []
	if OS.execute("reg", ["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"], out) == 0 and not out.is_empty():
		var rx := RegEx.create_from_string("SteamPath\\s+REG_SZ\\s+(.+)")
		var hit := rx.search(str(out[0]))
		if hit != null:
			roots.append(hit.get_string(1).strip_edges())
	var pf := OS.get_environment("ProgramFiles(x86)")
	if pf != "":
		roots.append(pf.replace("\\", "/") + "/Steam")
	for root in roots:
		var f := FileAccess.open(root + "/config/loginusers.vdf", FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var best := ""
		var best_stamp := -1
		var block_rx := RegEx.create_from_string("\"\\d+\"\\s*\\{([^}]*)\\}")
		var name_rx := RegEx.create_from_string("\"PersonaName\"\\s*\"([^\"]*)\"")
		var stamp_rx := RegEx.create_from_string("\"Timestamp\"\\s*\"(\\d+)\"")
		var recent_rx := RegEx.create_from_string("\"MostRecent\"\\s*\"1\"")
		for b in block_rx.search_all(text):
			var body := b.get_string(1)
			var n := name_rx.search(body)
			if n == null:
				continue
			var stamp := 0
			var s := stamp_rx.search(body)
			if s != null:
				stamp = int(s.get_string(1))
			if recent_rx.search(body) != null:
				stamp = 1 << 62
			if stamp > best_stamp:
				best_stamp = stamp
				best = n.get_string(1)
		if best != "":
			_steam_name_cache = best
			break
	return _steam_name_cache


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_belt_pick(seq: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and is_instance_valid(world_sync):
		world_sync.belts_sync.on_pick(multiplayer.get_remote_sender_id(), seq)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_belt_pick_result(owner: int, id: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if not is_host and is_instance_valid(world_sync):
		world_sync.belts_sync.on_pick_result(owner, id)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_mission_done(completed: PackedStringArray, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and is_instance_valid(world_sync):
		world_sync.on_mission_done(multiplayer.get_remote_sender_id(), completed)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_build_digest(digest: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_instance_valid(world_sync):
		world_sync.on_build_digest(digest)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_build_repair_request(revision: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and is_instance_valid(world_sync) and not world_sync._applying_builds:
		_rx_build_repair.rpc_id(multiplayer.get_remote_sender_id(), BuildSnapshot.buildings(world_sync.builds), revision, _outgoing_world_seed())


@rpc("authority", "call_remote", "reliable", 0)
func _rx_build_repair(buildings: Array, revision: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_instance_valid(world_sync):
		world_sync.on_build_repair(buildings, revision)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_tools_request(epoch: String, seq: int, added: Array, removed: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and world_sync != null:
		world_sync.tools_sync.on_request(multiplayer.get_remote_sender_id(), epoch, seq, added, removed)

@rpc("authority", "call_remote", "reliable", 0)
func _rx_tools_inventory(epoch: String, revision: int, ack: int, ids: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null:
		world_sync.tools_sync.on_inventory(epoch, revision, ack, ids)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_prop_owner(id: int, owner: int, epoch: int, holding: bool, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	var p := _props()
	if p != null:
		p.on_owner(id, owner, epoch, holding)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_tech_purchase(id: String, expected_rank: int, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and world_sync != null:
		world_sync.on_tech_purchase(multiplayer.get_remote_sender_id(), id, expected_rank)

@rpc("authority", "call_remote", "reliable", 0)
func _rx_tech_purchase_result(id: String, accepted: bool, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null:
		world_sync.on_tech_purchase_result(id, accepted)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_economy_request(epoch: String, seq: int, action: String, args: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host and world_sync != null and world_sync.economy != null:
		world_sync.economy.on_request(multiplayer.get_remote_sender_id(), epoch, seq, action, args)

@rpc("authority", "call_remote", "reliable", 0)
func _rx_economy_result(epoch: String, seq: int, result: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null and world_sync.economy != null:
		world_sync.economy.on_result(epoch, seq, result)

@rpc("authority", "call_remote", "reliable", 0)
func _rx_economy_state(epoch: String, state: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null and world_sync.economy != null:
		world_sync.economy.on_state(epoch, state)


@rpc("authority", "call_remote", "reliable", 0)
func _rx_stand_visuals(epoch: String, sequence: int, hay: int, worth: float,
		combo: int, gap: float, payouts: Array, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_host or not active() or not is_instance_valid(world_sync) \
			or not is_instance_valid(world_sync.economy) or epoch != world_sync.economy.epoch \
			or not is_instance_valid(world_sync.builds):
		return
	var stand: Node = world_sync.builds.get("stand") as Node
	if is_instance_valid(stand) and stand.has_method("apply_visuals"):
		stand.apply_visuals(epoch, sequence, hay, worth, combo, gap, payouts)


@rpc("authority", "call_remote", "reliable")
func _rx_prop_cleanup(policy: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if world_sync != null and is_instance_valid(world_sync.props_sync):
		world_sync.props_sync.on_cleanup(policy)


func _install_game_state() -> void:
	var values := {}
	for property in GameState.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = GameState.get(property.name)
	GameState.set_script(load(base_dir + "/mp_game_state.gd"))
	for key in values:
		if key in GameState:
			GameState.set(key, values[key])


func _install_save_manager() -> void:
	var values := {}
	for property in SaveManager.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = SaveManager.get(property.name)
	SaveManager.set_script(load(base_dir + "/mp_save_manager.gd"))
	for key in values:
		if key in SaveManager:
			SaveManager.set(key, values[key])


func _install_vacuum_tech() -> void:
	var values := {}
	for property in Tech.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = Tech.get(property.name)
	Tech.set_script(load(base_dir + "/mp_vac_tech.gd"))
	for key in values:
		if key in Tech:
			Tech.set(key, values[key])


func tool_identity(pid: int) -> String:
	return "host" if pid == 1 else str(_tool_identities.get(pid, "peer:" + str(pid)))

@rpc("authority", "call_remote", "reliable", 0)
func _rx_needle_catalog(epoch: String, data: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.needles_sync):
		world_sync.needles_sync.on_catalog(epoch, data)

@rpc("authority", "call_remote", "reliable", 0)
func _rx_hoppers(epoch: String, seq: int, data: Dictionary, world_seed: int = -1) -> void:
	if not _accept_world_seed(world_seed):
		return
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.hoppers_sync):
		world_sync.hoppers_sync.on_state(epoch, seq, data)


func _outgoing_world_seed() -> int:
	if not is_instance_valid(world_sync) or _prestige_transition or world_sync._frozen:
		return -1
	return GameState.run_seed

func _accept_world_seed(seed: int) -> bool:
	if seed < 0 or not active() or not is_instance_valid(world_sync) or seed != GameState.run_seed:
		return false
	var peer := multiplayer.get_remote_sender_id()
	if is_host and peer != 1 and (not players.has(peer) or str(players[peer].get("state", "")) != "world"):
		return false
	if _prestige_transition or world_sync._frozen:
		return is_host and is_instance_valid(world_sync.prestige) and world_sync.prestige.accept_draining(peer)
	return true

@rpc("authority", "call_remote", "reliable")
func _rx_prestige_prepare(token: String, seed: int) -> void:
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.prestige):
		world_sync.prestige.on_prepare(token, seed)

@rpc("any_peer", "call_remote", "reliable")
func _rx_prestige_ready(token: String, seed: int, report: Dictionary) -> void:
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.prestige):
		world_sync.prestige.on_ready(multiplayer.get_remote_sender_id(), token, seed, report)

@rpc("authority", "call_remote", "reliable")
func _rx_prestige_cancel(token: String, seed: int) -> void:
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.prestige):
		world_sync.prestige.on_cancel(token, seed)

@rpc("authority", "call_remote", "reliable")
func _rx_sweep_command(epoch: String, seed: int, token: String) -> void:
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.sweep_sync):
		world_sync.sweep_sync.on_command(epoch, seed, token)

@rpc("any_peer", "call_remote", "reliable")
func _rx_sweep_report(epoch: String, seed: int, token: String, rows: Array, ok: bool) -> void:
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.sweep_sync):
		world_sync.sweep_sync.on_report(multiplayer.get_remote_sender_id(), epoch, seed, token, rows, ok)

@rpc("authority", "call_remote", "reliable")
func _rx_sweep_finished(epoch: String, seed: int, token: String, result: Dictionary) -> void:
	if is_instance_valid(world_sync) and is_instance_valid(world_sync.sweep_sync):
		world_sync.sweep_sync.on_finished(epoch, seed, token, result)
