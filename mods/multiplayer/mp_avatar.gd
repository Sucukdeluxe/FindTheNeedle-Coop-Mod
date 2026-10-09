# Remote player puppet: an animated farmer, a name tag and the tool they are
# holding. Falls back to the old primitive figure if the model won't load.
# Poses arrive ~20 times a second and are smoothed.
# setup_local() turns it into our own headless body, seen when looking down.
extends Node3D

# the game's own msgids, so the label reads like the rest of its UI
const TOOL_NAMES := ["Hand", "Spade", "Pitchfork", "Broom", "Toy Shovel",
	"Metal Detector", "Yard Vac", "Lighter", "BUILD"]
const TOOL_MODELS := {
	1: "res://assets/downloaded/models/rusted_spade_01/rusted_spade_01_1k.gltf",
	2: "res://assets/models/pitchfork.glb",
	3: "res://assets/models/broom.glb",
	4: "res://assets/models/sand_shovel.glb",
	5: "res://assets/models/metal_detector.glb",
	6: "res://assets/models/yard_vac.glb",
}
const TOOL_LENGTH := 1.2
# tool models come in all sorts of units, so each gets a real length (m)
const TOOL_LENGTHS := {1: 1.1, 2: 1.35, 3: 1.3, 4: 0.65, 5: 0.55, 6: 1.0}
const EYE := 1.66
# hand-placed tool poses, see _load_poses. made with dev/tool_poser.gd
const POSE_FILE := "tool_poses.cfg"

# farmer from Quaternius' Ultimate Modular Men Pack (CC0), see models/CREDITS.txt
const MODEL_FILE := "models/farmer.glb"
const MODEL_HEIGHT := 1.89  # hat included, tuned in game so the eyes meet
# clip ground speeds in m/s. the player walks at 4.2 (7 sprinting), which is
# already a jog, so Walk is only used when slow or crouched
const WALK_CLIP_SPEED := 1.3
const RUN_CLIP_SPEED := 3.05
const RUN_FROM := 2.6
const IDLE := "Idle_Neutral"  # plain "Idle" stands twisted and leaves the feet behind
const CROUCH_DROP := 0.63
const CROUCH_LEAN := 0.35
const TINTS := {"LightBlue": 0.25, "Red": 0.0}  # overalls, hat band
# own body sits a bit behind the camera, more when crouched since it leans in
const LOCAL_BACK := 0.25
const LOCAL_CROUCH_BACK := 0.2

# wheelbarrow being pushed: the game's model, mounted the way its item does it
const BARROW_MODEL := "res://assets/models/wheelbarrow.glb"
const BARROW_SCALE := 0.688
const BARROW_YAW := -PI * 0.5
const BARROW_SECTION := "wheelbarrow"  # in tool_poses.cfg
# where it sits from the avatar's feet (same axes as the avatar: -Z ahead),
# nose down on its wheel and the handles up at hand height. the poser saves
# its own over this
const BARROW_POS := Vector3(0.0, 0.203, -0.902)
const BARROW_ROT := Vector3(-18.7, 0.0, 0.0)
# handle grips in the barrow's own space, used when the model can't be read
const BARROW_GRIPS := [Vector3(-0.315, 0.562, 0.763), Vector3(0.315, 0.562, 0.763)]
const BARROW_AXLE := Vector3(0.0, 0.166, -0.605)
const BARROW_LEAN := 0.3

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := 0.0
var _crouch := 0.0
var _moving := 0.0
var _tool := -1
var flip_tool := false  # turn the held tool 180 degrees (for new models)
var _has_target := false
var _walk := 0.0
var _pitch := 0.0
var _crouch_now := 0.0
var crouch_drop := CROUCH_DROP  # var so dev/avatar_calib.gd can tune it live

var _body: Node3D
var _head: Node3D
var _hand: Node3D
var _tool_node: Node3D
var _posed := {}  # holder, mount, box, longest, pose while a saved pose is in use
var _label: Label3D
var _name := ""
var _color := Color.WHITE
static var _model_cache := {}
static var _poses := {}
static var _poses_tried := false
static var _grips: Array = []
var _barrow: Node3D  # wheelbarrow they're pushing, we place it, see push_item
var _barrow_pose := {}

# farmer only
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _clip := ""
var _b_head := -1
var _b_upper := -1
var _b_lower := -1
var _b_wrist := -1
var _b_palm := -1
var _b_body := -1
var _b_hips := -1
var _legs: Array = []  # [thigh, shin, foot, thigh len, shin len]
var _arms: Array = []  # [upper, lower, upper len, lower len to the palm, bones to reset]
var _arms_bent := false
static var _farmer: PackedScene
static var _farmer_tried := false

# own body only
var _player: Node3D
var _mp: Node


func setup(pname: String, color: Color) -> void:
	_name = pname
	_color = color


# our own body, follows the player every frame. no label and no tool,
# the game draws its own hand
func setup_local(player: Node3D, mp: Node) -> void:
	_player = player
	_mp = mp
	visible = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	if _mp != null:
		_build_farmer()
		return
	if not _build_farmer():
		_build_figure()

	_label = Label3D.new()
	_label.text = _name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0016
	_label.font_size = 22
	_label.outline_size = 8
	_label.modulate = _color.lightened(0.35)
	_label.position.y = EYE + 0.55
	add_child(_label)


# ---------------------------------------------------------------- farmer model

static func _load_farmer(dir: String) -> PackedScene:
	if _farmer_tried:
		return _farmer
	_farmer_tried = true
	var path := dir.path_join(MODEL_FILE)
	if not FileAccess.file_exists(path):
		push_warning("[MPMod] %s not found, using the simple avatar" % path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	var root: Node = doc.generate_scene(state) if err == OK else null
	if root == null:
		push_warning("[MPMod] could not load %s (error %d), using the simple avatar" % [path, err])
		return null
	var scene := PackedScene.new()
	if scene.pack(root) == OK:
		_farmer = scene
	root.free()
	return _farmer


func _build_farmer() -> bool:
	var scene := _load_farmer(get_script().resource_path.get_base_dir())
	if scene == null:
		return false
	var root := scene.instantiate()
	var model := root as Node3D
	if model == null:
		if root != null:
			root.free()
		return false
	var skels := model.find_children("*", "Skeleton3D", true, false)
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	if skels.is_empty() or anims.is_empty():
		model.free()
		return false
	_skel = skels[0]
	_anim = anims[0]
	_b_head = _skel.find_bone("Head")
	_b_upper = _skel.find_bone("UpperArm.R")
	_b_lower = _skel.find_bone("LowerArm.R")
	_b_wrist = _skel.find_bone("Wrist.R")
	_b_palm = _skel.find_bone("Middle1.R")
	_b_body = _skel.find_bone("Body")
	_b_hips = _skel.find_bone("Hips")
	# feet hang off the root (IK targets) so they stay put when the legs bend
	for side in ["L", "R"]:
		var thigh := _skel.find_bone("UpperLeg." + side)
		var shin := _skel.find_bone("LowerLeg." + side)
		var foot := _skel.find_bone("Foot." + side)
		if thigh < 0 or shin < 0 or foot < 0:
			continue
		var h := _skel.get_bone_global_rest(thigh).origin
		var kn := _skel.get_bone_global_rest(shin).origin
		var f := _skel.get_bone_global_rest(foot).origin
		_legs.append([thigh, shin, foot, h.distance_to(kn), kn.distance_to(f)])
	# arms reach for the wheelbarrow handles, the palm lands on the grip
	for side in ["L", "R"]:
		var up := _skel.find_bone("UpperArm." + side)
		var lo := _skel.find_bone("LowerArm." + side)
		var wr := _skel.find_bone("Wrist." + side)
		var palm := _skel.find_bone("Middle1." + side)
		if palm < 0:
			palm = wr
		if up < 0 or lo < 0 or palm < 0:
			continue
		var sh := _skel.get_bone_global_rest(up).origin
		var el := _skel.get_bone_global_rest(lo).origin
		var pa := _skel.get_bone_global_rest(palm).origin
		_arms.append([up, lo, sh.distance_to(el), el.distance_to(pa), [up, lo, wr]])

	# feet on the ground, facing -Z like the player
	var box := _aabb(model, Transform3D.IDENTITY)
	var s := MODEL_HEIGHT / maxf(box.size.y, 0.001)
	var holder := Node3D.new()
	holder.rotation.y = PI
	holder.scale = Vector3.ONE * s
	holder.position.y = -box.position.y * s
	holder.add_child(model)
	_body.add_child(holder)

	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _mp != null and mi.name == "Farmer_Head":
			# no head in our face, but it still shows in the shadow
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_dye()

	for clip in [IDLE, "Walk", "Run"]:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	# advanced by hand so we can pose the head and arm on top
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_play(IDLE, 0.0)

	# follows the right hand, tools hang off it
	_hand = Node3D.new()
	add_child(_hand)
	return true


# overalls and hat band in the player's colour
func _dye() -> void:
	for mi: MeshInstance3D in _body.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat != null and TINTS.has(mat.resource_name):
				var dyed := mat.duplicate() as BaseMaterial3D
				dyed.albedo_color = _color.darkened(TINTS[mat.resource_name])
				mi.set_surface_override_material(i, dyed)


func _play(clip: String, blend: float) -> void:
	if clip == _clip or not _anim.has_animation(clip):
		return
	_clip = clip
	_anim.play(clip, blend)


func _animate_farmer(delta: float) -> void:
	var clip := IDLE
	if _moving > RUN_FROM and _crouch < 0.5:
		clip = "Run"
	elif _moving > 0.3:
		clip = "Walk"
	_play(clip, 0.2)
	match clip:
		"Walk":
			_anim.speed_scale = clampf(_moving / WALK_CLIP_SPEED, 0.6, 2.0)
		"Run":
			_anim.speed_scale = clampf(_moving / RUN_CLIP_SPEED, 0.8, 2.0)
		_:
			_anim.speed_scale = 1.0
	var pushing := _pushing()
	# not every clip keys these, so reset them or last frame's pose sticks
	var bones := [_b_head, _b_upper, _b_lower, _b_body, _b_hips]
	if pushing or _arms_bent:
		for arm in _arms:
			bones.append_array(arm[4])
	_arms_bent = pushing
	for b in bones:
		if b >= 0:
			_skel.reset_bone_pose(b)
	for leg in _legs:
		_skel.reset_bone_pose(leg[0])
		_skel.reset_bone_pose(leg[1])
	_anim.advance(delta)

	var right := global_basis.x.normalized()
	var fwd := -global_basis.z.normalized()
	var lean := 0.0
	if _crouch_now > 0.01:
		lean = CROUCH_LEAN * _crouch_now
		_crouch_legs(_crouch_now, right)
	if pushing:
		# leaning into it
		lean += BARROW_LEAN
		if _b_hips >= 0:
			_turn_bone(_b_hips, right, -BARROW_LEAN)
	if _b_head >= 0:
		# undo the lean so the head still looks where they look
		_turn_bone(_b_head, right, clampf(_pitch, -0.7, 0.7) + lean)
	if pushing:
		_place_barrow()
		_reach_grips(right)
	var holding := _tool_node != null and not pushing
	if holding and _b_upper >= 0 and _b_lower >= 0:
		# elbow by the side, forearm out front
		_aim_bone(_b_upper, fwd.rotated(right, -1.05 + _pitch * 0.25))
		_aim_bone(_b_lower, fwd.rotated(right, -0.3 + _pitch * 0.8))
	var grip_bone := _b_palm if _b_palm >= 0 else _b_wrist
	if grip_bone >= 0:
		var grip := _skel.global_transform * _skel.get_bone_global_pose(grip_bone)
		_hand.global_transform = Transform3D(
			Basis(right, _pitch * 0.8 - 0.35) * global_basis.orthonormalized(), grip.origin)
	if not _posed.is_empty() and _posed.pose.has("crouch") and is_instance_valid(_posed.holder):
		_pose_tool(_posed.holder, _posed.mount, _posed.box, _posed.longest, _blend_pose(_posed.pose, _crouch_now))


# rotate a bone around a world axis, on top of its current pose
func _turn_bone(b: int, axis_world: Vector3, angle: float) -> void:
	var axis := (_skel.global_basis.inverse() * axis_world).normalized()
	_rotate_bone(b, Quaternion(axis, angle))


# point a bone along a world direction (bones run along +Y)
func _aim_bone(b: int, dir_world: Vector3) -> void:
	_aim_bone_local(b, _skel.global_basis.inverse() * dir_world)


func _aim_bone_local(b: int, want: Vector3) -> void:
	var cur := _skel.get_bone_global_pose(b).basis.y.normalized()
	want = want.normalized()
	if cur.is_zero_approx() or want.is_zero_approx() or cur.dot(want) > 0.9999:
		return
	_rotate_bone(b, Quaternion(cur, want))


# lower the pelvis, lean forward and bend the knees so the feet stay planted
func _crouch_legs(amount: float, right: Vector3) -> void:
	var to_skel := _skel.global_basis.inverse()
	if _b_body >= 0:
		var drop := to_skel * (Vector3.DOWN * crouch_drop * amount)
		var parent := _skel.get_bone_parent(_b_body)
		if parent >= 0:
			drop = _skel.get_bone_global_pose(parent).basis.inverse() * drop
		_skel.set_bone_pose_position(_b_body, _skel.get_bone_pose_position(_b_body) + drop)
	if _b_hips >= 0:
		_turn_bone(_b_hips, right, -CROUCH_LEAN * amount)
	var axis := (to_skel * right).normalized()
	for leg in _legs:
		var hip := _skel.get_bone_global_pose(leg[0]).origin
		var foot := _skel.get_bone_global_pose(leg[2]).origin
		var t: float = leg[3]
		var s: float = leg[4]
		var d := clampf(hip.distance_to(foot), absf(t - s) + 0.0001, t + s - 0.0001)
		var dir := (foot - hip).normalized()
		# hip angle from the law of cosines, positive = knee forward
		var a := acos(clampf((t * t + d * d - s * s) / (2.0 * t * d), -1.0, 1.0))
		var knee := hip + dir.rotated(axis, a) * t
		_aim_bone_local(leg[0], knee - hip)
		_aim_bone_local(leg[1], foot - _skel.get_bone_global_pose(leg[1]).origin)


# both palms on the wheelbarrow handles, same two-bone fit as the legs with
# the elbows bent down and out
func _reach_grips(right: Vector3) -> void:
	var s := _barrow_size()
	var xf := _barrow.global_transform
	var to_skel := _skel.global_transform.affine_inverse()
	for arm in _arms:
		var sh := _skel.get_bone_global_pose(arm[0]).origin
		var on_right := right.dot(_skel.global_transform * sh - global_position) > 0.0
		var grip: Vector3 = _barrow_pose.grip_r if on_right else _barrow_pose.grip_l
		var goal := to_skel * (xf * (grip * s))
		var out := right if on_right else -right
		var pole := (to_skel.basis * (Vector3.DOWN + out * 0.8 + global_basis.z * 0.3)).normalized()
		var t: float = arm[2]
		var l: float = arm[3]
		var d := clampf(sh.distance_to(goal), absf(t - l) + 0.0001, t + l - 0.0001)
		var dir := (goal - sh).normalized()
		pole = (pole - dir * pole.dot(dir)).normalized()
		var a := acos(clampf((t * t + d * d - l * l) / (2.0 * t * d), -1.0, 1.0))
		var elbow := sh + (dir * cos(a) + pole * sin(a)) * t
		_aim_bone_local(arm[0], elbow - sh)
		_aim_bone_local(arm[1], goal - _skel.get_bone_global_pose(arm[1]).origin)


# rot is in skeleton space
func _rotate_bone(b: int, rot: Quaternion) -> void:
	var parent := _skel.get_bone_parent(b)
	var pg := Quaternion.IDENTITY
	if parent >= 0:
		pg = _skel.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var g := _skel.get_bone_global_pose(b).basis.get_rotation_quaternion()
	_skel.set_bone_pose_rotation(b, (pg.inverse() * rot * g).normalized())


# ---------------------------------------------------------------- simple figure

func _build_figure() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = _color
	skin.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.11)
	dark.roughness = 0.35
	dark.metallic = 0.4
	var boots := StandardMaterial3D.new()
	boots.albedo_color = _color.darkened(0.55)

	var torso := _mesh(CapsuleMesh.new(), skin)
	(torso.mesh as CapsuleMesh).radius = 0.27
	(torso.mesh as CapsuleMesh).height = 0.95
	torso.position.y = 1.05
	_body.add_child(torso)
	for side in [-1.0, 1.0]:
		var leg := _mesh(CapsuleMesh.new(), boots)
		(leg.mesh as CapsuleMesh).radius = 0.11
		(leg.mesh as CapsuleMesh).height = 0.72
		leg.position = Vector3(0.12 * side, 0.36, 0.0)
		leg.name = "LegL" if side < 0 else "LegR"
		_body.add_child(leg)

	_head = Node3D.new()
	_head.position.y = EYE - 0.08
	_body.add_child(_head)
	var skull := _mesh(SphereMesh.new(), skin)
	(skull.mesh as SphereMesh).radius = 0.2
	(skull.mesh as SphereMesh).height = 0.4
	_head.add_child(skull)
	var visor := _mesh(BoxMesh.new(), dark)
	(visor.mesh as BoxMesh).size = Vector3(0.3, 0.1, 0.12)
	visor.position = Vector3(0, 0.03, -0.15)
	_head.add_child(visor)

	# left arm hangs by the side
	var left_arm := _mesh(CapsuleMesh.new(), skin)
	(left_arm.mesh as CapsuleMesh).radius = 0.085
	(left_arm.mesh as CapsuleMesh).height = 0.62
	left_arm.position = Vector3(-0.33, 1.05, 0.0)
	left_arm.rotation.z = 0.12
	_body.add_child(left_arm)

	# the right arm pivots with the look pitch, so the tool points where they aim
	_hand = Node3D.new()
	_hand.position = Vector3(0.33, 1.35, 0.0)
	_body.add_child(_hand)
	var right_arm := _mesh(CapsuleMesh.new(), skin)
	(right_arm.mesh as CapsuleMesh).radius = 0.085
	(right_arm.mesh as CapsuleMesh).height = 0.62
	right_arm.position = Vector3(0.0, 0.0, -0.26)
	right_arm.rotation.x = PI / 2.0
	_hand.add_child(right_arm)
	var fist := _mesh(SphereMesh.new(), skin)
	(fist.mesh as SphereMesh).radius = 0.085
	(fist.mesh as SphereMesh).height = 0.17
	fist.position = Vector3(0.0, 0.0, -0.52)
	_hand.add_child(fist)


func _animate_figure(delta: float, k: float) -> void:
	_head.rotation.x = _pitch
	_hand.rotation.x = lerpf(_hand.rotation.x, _target_pitch * 0.8 - 0.35, k)
	# a little walk cycle
	if _moving > 0.3:
		_walk += delta * clampf(_moving, 1.0, 9.0) * 1.6
	else:
		_walk = lerpf(_walk, round(_walk / PI) * PI, k)
	var swing := sin(_walk) * 0.5 * clampf(_moving / 4.0, 0.0, 1.0)
	var l := _body.get_node_or_null("LegL")
	var r := _body.get_node_or_null("LegR")
	if l != null:
		l.rotation.x = swing
	if r != null:
		r.rotation.x = -swing


func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


# ---------------------------------------------------------------- pose

func set_target(pos: Vector3, yaw: float, pitch: float, tool: int, crouch: float, moving: float) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_target_pitch = pitch
	_crouch = crouch
	_moving = moving
	if not _has_target:
		_has_target = true
		global_position = pos
		rotation.y = yaw
		_pitch = pitch
	if tool != _tool:
		_tool = tool
		_set_tool_model(tool)


func _process(delta: float) -> void:
	if _mp != null:
		_follow_player(delta)
		return
	if not _has_target:
		return
	var k := 1.0 - exp(-14.0 * delta)
	if global_position.distance_to(_target_pos) > 6.0:
		global_position = _target_pos
	else:
		global_position = global_position.lerp(_target_pos, k)
	rotation.y = lerp_angle(rotation.y, _target_yaw, k)
	_pitch = lerpf(_pitch, _target_pitch, k)
	_crouch_now = lerpf(_crouch_now, _crouch, k)
	if _tool_node != null:
		# both hands are on the wheelbarrow
		_tool_node.visible = not _pushing()
	if _skel != null:
		_animate_farmer(delta)
		_label.position.y = EYE + 0.55 - crouch_drop * _crouch_now
	else:
		_body.scale.y = 1.0 - 0.3 * _crouch_now
		_animate_figure(delta, k)
		if _pushing():
			_place_barrow()
	var tool_txt: String = TOOL_NAMES[_tool] if _tool >= 0 and _tool < TOOL_NAMES.size() else ""
	# no tool in the tag while both hands are on the barrow
	_label.text = _name if tool_txt == "" or _tool == 0 or _pushing() else "%s\n[%s]" % [_name, tr(tool_txt)]


func _follow_player(delta: float) -> void:
	visible = _skel != null and is_instance_valid(_player) and _mp.active()
	if not visible:
		return
	var col: Color = _mp.player_color(multiplayer.get_unique_id())
	if col != _color:
		_color = col
		_dye()
	global_position = _player.get_global_transform_interpolated().origin
	rotation = Vector3(0.0, _player.global_rotation.y, 0.0)
	var p: Variant = _player.get("_pitch")
	_pitch = float(p) if p != null else 0.0
	_crouch = float(_player.call("crouch_amount")) if _player.has_method("crouch_amount") else 0.0
	_crouch_now = _crouch
	_body.position.z = LOCAL_BACK + LOCAL_CROUCH_BACK * _crouch
	var v: Variant = _player.get("velocity")
	_moving = (v * Vector3(1, 0, 1)).length() if v is Vector3 else 0.0
	_animate_farmer(delta)


func _set_tool_model(tool: int) -> void:
	_posed = {}
	if _tool_node != null:
		_tool_node.queue_free()
		_tool_node = null
	var path: String = TOOL_MODELS.get(tool, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene: PackedScene = _model_cache.get(path)
	if scene == null:
		scene = load(path) as PackedScene
		if scene == null:
			return
		_model_cache[path] = scene
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return
	# scale to its real length, pointing forward. the mount keeps the model's
	# own root transform intact
	var holder := Node3D.new()
	var mount := Node3D.new()
	holder.add_child(mount)
	mount.add_child(inst)
	var length: float = TOOL_LENGTHS.get(tool, TOOL_LENGTH)
	var box := _aabb(inst, Transform3D.IDENTITY)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	# a saved pose wins over the guess below (farmer only, the old figure
	# holds things differently)
	var pose := tool_pose(tool) if _skel != null else {}
	if not pose.is_empty() and longest > 0.001:
		_posed = {"holder": holder, "mount": mount, "box": box, "longest": longest, "pose": pose}
		_pose_tool(holder, mount, box, longest, _blend_pose(pose, _crouch_now))
		_hand.add_child(holder)
		_tool_node = holder
		return
	if longest > 0.001:
		var s := length / longest
		mount.scale = Vector3.ONE * s
		mount.position = -box.get_center() * s
		# Which way the tool points along its long axis. The default puts the
		# working end (blade, fork, nozzle) away from the hand; flip_tool turns
		# it 180 degrees, which is handy when trying out new tool models.
		var turn := -1.0 if flip_tool else 1.0
		if box.size.y >= box.size.x and box.size.y >= box.size.z:
			holder.rotation.x = turn * PI / 2.0  # long axis up -> forward
		elif box.size.x >= box.size.z:
			holder.rotation.y = -turn * PI / 2.0
	if _skel != null:
		# held a quarter of the way down
		holder.position = Vector3(0.0, 0.0, -length * 0.25)
	else:
		# hold it just past the fist, angled down a little like a carried tool
		holder.position = Vector3(0.0, -0.05, -0.52 - length * 0.35)
	holder.rotation.x += 0.25
	_hand.add_child(holder)
	_tool_node = holder


# the model keeps its own axes, centred on the holder, and the holder sits at
# pos / rot in _hand space: -Z where they face, +Y up, +X to their right,
# tilted with the look pitch
func _pose_tool(holder: Node3D, mount: Node3D, box: AABB, longest: float, pose: Dictionary) -> void:
	var s: float = pose.length / longest
	# built from scratch, this runs every frame while crouching
	mount.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), -box.get_center() * s)
	if flip_tool:
		# end over end, around an axis across the tool
		var across := Vector3.RIGHT if box.size.x < maxf(box.size.y, box.size.z) else Vector3.UP
		mount.transform = Transform3D(Basis(across, PI), Vector3.ZERO) * mount.transform
	holder.position = pose.pos
	holder.rotation_degrees = pose.rot


# stand pose eased towards the crouch one, if the tool has one
func _blend_pose(pose: Dictionary, c: float) -> Dictionary:
	if not pose.has("crouch") or c <= 0.001:
		return pose
	var cr: Dictionary = pose.crouch
	var qa := Basis.from_euler(pose.rot * PI / 180.0).get_rotation_quaternion()
	var qb := Basis.from_euler(cr.rot * PI / 180.0).get_rotation_quaternion()
	var rot := Basis(qa.slerp(qb, c)).get_euler() * 180.0 / PI
	return {"pos": pose.pos.lerp(cr.pos, c), "rot": rot, "length": lerpf(pose.length, cr.length, c)}


# tool_poses.cfg next to this script, one section per tool id:
#   [tool_4]
#   pos=Vector3(0, 0, -0.1)   # metres
#   rot=Vector3(90, 0, 0)     # degrees, same as rotation_degrees
#   length=0.65               # metres along the longest axis
# a missing file or a bad entry just means the automatic fit
static func _load_poses(dir: String) -> Dictionary:
	if _poses_tried:
		return _poses
	_poses_tried = true
	var path := dir.path_join(POSE_FILE)
	if not FileAccess.file_exists(path):
		return _poses
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		push_warning("[MPMod] could not read %s (error %d), tools use the automatic fit" % [path, err])
		return _poses
	for sec in cfg.get_sections():
		if sec == BARROW_SECTION:
			var bp := _read_barrow(cfg)
			if bp.is_empty():
				push_warning("[MPMod] bad [%s] in %s, using the default" % [sec, path])
			else:
				_poses[BARROW_SECTION] = bp
			continue
		var id := sec.trim_prefix("tool_")
		if not sec.begins_with("tool_") or not id.is_valid_int():
			continue
		var pos: Variant = cfg.get_value(sec, "pos", Vector3.ZERO)
		var rot: Variant = cfg.get_value(sec, "rot", Vector3.ZERO)
		var length: Variant = cfg.get_value(sec, "length", 0.0)
		var ok := pos is Vector3 and rot is Vector3 and (length is float or length is int)
		if ok and pos.is_finite() and rot.is_finite() and length > 0.01 and length < 10.0:
			var pose := {"pos": pos, "rot": rot, "length": float(length)}
			# optional crouch pose, missing keys use the standing ones
			if cfg.has_section_key(sec, "pos_crouch") or cfg.has_section_key(sec, "rot_crouch") 					or cfg.has_section_key(sec, "length_crouch"):
				var pc: Variant = cfg.get_value(sec, "pos_crouch", pos)
				var rc: Variant = cfg.get_value(sec, "rot_crouch", rot)
				var lc: Variant = cfg.get_value(sec, "length_crouch", length)
				if pc is Vector3 and rc is Vector3 and (lc is float or lc is int) and lc > 0.01 and lc < 10.0:
					pose.crouch = {"pos": pc, "rot": rc, "length": float(lc)}
				else:
					push_warning("[MPMod] bad crouch pose [%s] in %s, using the standing one" % [sec, path])
			_poses[int(id)] = pose
		else:
			push_warning("[MPMod] bad tool pose [%s] in %s, skipped" % [sec, path])
	return _poses


func tool_pose(tool: int) -> Dictionary:
	return _load_poses(get_script().resource_path.get_base_dir()).get(tool, {})


# live editing from dev/tool_poser.gd. an empty pose goes back to automatic
func set_tool_pose(tool: int, pose: Dictionary) -> void:
	var poses := _load_poses(get_script().resource_path.get_base_dir())
	if pose.is_empty():
		poses.erase(tool)
	else:
		poses[tool] = {"pos": pose.pos, "rot": pose.rot, "length": float(pose.length)}
		if pose.has("crouch"):
			var cr: Dictionary = pose.crouch
			poses[tool].crouch = {"pos": cr.pos, "rot": cr.rot, "length": float(cr.length)}
	if tool == _tool:
		_set_tool_model(tool)


# ---------------------------------------------------------------- wheelbarrow

# the wheelbarrow copy they're pushing (mp_props hands it over), null when
# they let go. while set we place it every frame and hold it by the handles
func push_item(item: Node3D) -> void:
	_barrow = item
	if item != null:
		_barrow_pose = barrow_pose()


func _pushing() -> bool:
	return _barrow != null and is_instance_valid(_barrow) and _barrow.is_inside_tree()


# barrow upgrades make the item bigger, the game scales its model by this
func _barrow_size() -> float:
	return float(_barrow.call("size_scale")) if _barrow.has_method("size_scale") else 1.0


# from our feet by its pose. a bigger one grows around its handles so they
# stay in the hands
func _place_barrow() -> void:
	var p := _barrow_pose
	var c := _crouch_now
	var pos: Vector3 = p.pos
	var b := Basis.from_euler(p.rot * PI / 180.0)
	if p.has("pos_crouch") and c > 0.001:
		# its own crouch pose, eased into like the tools
		var qc := Basis.from_euler(p.rot_crouch * PI / 180.0).get_rotation_quaternion()
		b = Basis(b.get_rotation_quaternion().slerp(qc, c))
		pos = pos.lerp(p.pos_crouch, c)
	var mid: Vector3 = (p.grip_l + p.grip_r) * 0.5
	var xf := Transform3D(b, pos + b * (mid * (1.0 - _barrow_size())))
	if c > 0.01 and not p.has("pos_crouch"):
		# crouched, it tips back down onto its legs around the wheel
		var axle := xf * (BARROW_AXLE * _barrow_size())
		var tip := Basis(Vector3.RIGHT, -deg_to_rad(p.rot.x) * c)
		xf = Transform3D(tip, axle - tip * axle) * xf
	var world_xf := global_transform * xf
	_barrow.global_transform = world_xf
	# its shape has to travel with it: moving a frozen body by its transform
	# alone leaves an invisible barrow standing wherever it was, and that one
	# eats the aim of anybody trying to pick something up
	PhysicsServer3D.body_set_state(_barrow.get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM, world_xf)


# [wheelbarrow] in tool_poses.cfg:
#   pos=Vector3(0, 0.2, -0.9)    # its origin from the avatar's feet, metres
#   rot=Vector3(-18, 0, 0)       # degrees
#   grip_l=Vector3(...)          # optional, handle grips in the barrow's own
#   grip_r=Vector3(...)          # space. found on the model when missing
#   pos_crouch / rot_crouch      # optional crouch pose, else it just tips back
# filled=false gives just what was saved
func barrow_pose(filled := true) -> Dictionary:
	var p: Dictionary = _load_poses(get_script().resource_path.get_base_dir()).get(BARROW_SECTION, {}).duplicate()
	if not filled:
		return p
	if not p.has("pos"):
		p.pos = BARROW_POS
		p.rot = BARROW_ROT
	if not p.has("grip_l"):
		var g := barrow_grips()
		p.grip_l = g[0]
		p.grip_r = g[1]
	return p


# live editing from dev/tool_poser.gd, an empty pose goes back to the default
func set_barrow_pose(pose: Dictionary) -> void:
	var poses := _load_poses(get_script().resource_path.get_base_dir())
	if pose.is_empty():
		poses.erase(BARROW_SECTION)
	else:
		poses[BARROW_SECTION] = pose.duplicate()
	_barrow_pose = barrow_pose()


static func _read_barrow(cfg: ConfigFile) -> Dictionary:
	var out := {}
	for k in ["pos", "rot", "grip_l", "grip_r", "pos_crouch", "rot_crouch"]:
		# a null default makes godot complain about every missing key
		if not cfg.has_section_key(BARROW_SECTION, k):
			continue
		var v: Variant = cfg.get_value(BARROW_SECTION, k)
		if v is Vector3 and v.is_finite():
			out[k] = v
		elif v != null:
			return {}
	# pos and rot go together, and so do the grips
	if out.has("pos") != out.has("rot") or out.has("grip_l") != out.has("grip_r") 			or out.has("pos_crouch") != out.has("rot_crouch"):
		return {}
	return out


# the game's model, mounted like its item does it
static func barrow_model() -> Node3D:
	if not ResourceLoader.exists(BARROW_MODEL):
		return null
	var scene: PackedScene = _model_cache.get(BARROW_MODEL)
	if scene == null:
		scene = load(BARROW_MODEL) as PackedScene
		if scene == null:
			return null
		_model_cache[BARROW_MODEL] = scene
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	inst.transform = Transform3D(Basis(Vector3.UP, BARROW_YAW).scaled(Vector3.ONE * BARROW_SCALE), Vector3.ZERO)
	var root := Node3D.new()
	root.add_child(inst)
	return root


# the handle ends: whatever sticks out furthest back, on each side
static func barrow_grips() -> Array:
	if not _grips.is_empty():
		return _grips
	_grips = BARROW_GRIPS.duplicate()
	var model := barrow_model()
	if model == null:
		return _grips
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != model:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for i in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * v)
	model.free()
	var back := -INF
	for v in pts:
		back = maxf(back, v.z)
	for side in 2:
		var sum := Vector3.ZERO
		var n := 0
		for v in pts:
			if (v.x > 0.0) == (side == 1) and v.z > back - 0.12:
				sum += v
				n += 1
		if n > 0:
			_grips[side] = sum / n
	return _grips


func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is VisualInstance3D:
		var b := here * (n as VisualInstance3D).get_aabb()
		out = b
		first = false
	for c in n.get_children():
		var cb := _aabb(c, here)
		if cb.size != Vector3.ZERO:
			if first:
				out = cb
				first = false
			else:
				out = out.merge(cb)
	return out


# ---------------------------------------------------------------- hands

# What the player is holding in their bare hands: a number of straws, and a
# needle by type (-1 for none). The straws themselves are parked here by
# mp_strands, which owns the straw pool; the needle is a mesh of our own.
var _straws_held := 0
var _needle_mi: MeshInstance3D


func set_hands(straws: int, needle_type: int) -> void:
	_straws_held = clampi(straws, 0, 15)
	_show_needle(needle_type)
	_show_clump(_straws_held)


func straws_held() -> int:
	return _straws_held


# where a held thing sits, in world space
func hand_xform() -> Transform3D:
	if _hand != null and is_instance_valid(_hand):
		return _hand.global_transform
	return global_transform


func _show_needle(type: int) -> void:
	if type < 0:
		if _needle_mi != null and is_instance_valid(_needle_mi):
			_needle_mi.queue_free()
		_needle_mi = null
		return
	if _needle_mi == null or not is_instance_valid(_needle_mi):
		_needle_mi = MeshInstance3D.new()
		_needle_mi.name = "HeldNeedle"
		if _hand != null and is_instance_valid(_hand):
			_hand.add_child(_needle_mi)
		else:
			add_child(_needle_mi)
	if int(_needle_mi.get_meta("type", -99)) == type:
		return
	_needle_mi.set_meta("type", type)
	_needle_mi.mesh = StrandFactory.needle_model(type)
	var mats: Array[Material] = StrandFactory.needle_surface_materials(type)
	for i in mats.size():
		_needle_mi.set_surface_override_material(i, mats[i])
	# pinched between the fingers, pointing the way they look
	_needle_mi.transform = Transform3D(Basis(Vector3.RIGHT, -1.2), Vector3(0.0, -0.02, -0.14)) \
		* StrandFactory.needle_visual_xform(type)


# One straw is drawn as one straw. From two up it becomes a small ball of
# hay, the wad the belts carry, growing a little with each one, because a
# handful of loose strands reads as a bunch of sticks. It never gets near the
# size of the real thing: a full hand is about nine straws.
const CLUMP_AT := 2
const CLUMP_ITEM := "hay_wad"
const CLUMP_SCALE := 0.19
const CLUMP_STEP := 0.022
const CLUMP_MAX := 9
var _clump: Node3D


func _show_clump(straws: int) -> void:
	if straws < CLUMP_AT:
		if _clump != null and is_instance_valid(_clump):
			_clump.visible = false
		return
	if _clump == null or not is_instance_valid(_clump):
		var made: Variant = ItemDb.make(CLUMP_ITEM)
		if made == null:
			return
		_clump = made as Node3D
		_clump.name = "HandfulOfHay"
		var yard := get_parent()
		if yard != null and "live" in _clump:
			_clump.set("live", yard.get("live"))
		if _hand != null and is_instance_valid(_hand):
			_hand.add_child(_clump)
		else:
			add_child(_clump)
		# after add_child, never before: the item puts itself on the prop layer
		# in its own _ready, and a solid wad hanging off a hand would eat other
		# players' aim and could even be picked up
		_clump.set("freeze", true)
		_clump.set("collision_layer", 0)
		_clump.set("collision_mask", 0)
		_clump.set_physics_process(false)
		_clump.set_process(false)
		_clump.position = Vector3(0.0, -0.05, -0.15)
	# a hand holds about the same however full it is: size it once, and never
	# feed it strands, or it grows with every pose packet that arrives
	_clump.scale = Vector3.ONE * (CLUMP_SCALE + CLUMP_STEP * float(mini(straws, CLUMP_MAX)))
	_clump.visible = true


var _tool_hay: Node3D

func set_tool_load(fill: float) -> void:
	if fill <= 0.0 or _tool not in [1, 2, 4] or not is_instance_valid(_hand):
		if is_instance_valid(_tool_hay):
			_tool_hay.visible = false
		return
	if not is_instance_valid(_tool_hay):
		_tool_hay = ItemDb.make("hay_wad") as Node3D
		if _tool_hay == null:
			return
		_tool_hay.name = "ToolHay"
		_hand.add_child(_tool_hay)
		_tool_hay.set("freeze", true)
		_tool_hay.set("collision_layer", 0)
		_tool_hay.set("collision_mask", 0)
		_tool_hay.set_physics_process(false)
		_tool_hay.set_process(false)
	_tool_hay.position = Vector3(0.0, -0.1, -0.65)
	if not _posed.is_empty() and is_instance_valid(_posed.get("mount")):
		var box: AABB = _posed.box
		var axis := box.size.max_axis_index()
		var point := box.get_center()
		point[axis] -= box.size[axis] * 0.35
		_tool_hay.global_position = _posed.mount.to_global(point)
	_tool_hay.scale = Vector3.ONE * lerpf(0.18, 0.55, clampf(fill, 0.0, 1.0))
	_tool_hay.visible = true
