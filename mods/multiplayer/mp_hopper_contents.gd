extends Node3D

const CELL_COUNT := 88
static var _native_mesh: ArrayMesh
static var _native_materials: Array[Material] = []
static var _native_scale := Vector3.ONE
static var _clipped_shader: Shader
static var _prepared := false
var _stock: MultiMeshInstance3D
var _materials: Array[ShaderMaterial] = []
var _drops: Array[MeshInstance3D] = []
var _amount := -1
var _capacity := 1
var _target_fraction := 0.0
var _fraction := 0.0
var _pour_left := 0.0
var _clock := 0.0
var _clip_transform := Transform3D.IDENTITY

func _ready() -> void:
	_prepare_native()
	if _native_mesh == null or _clipped_shader == null:
		set_process(false)
		return
	_make_stock()
	_make_drops()
	set_notify_transform(true)
	_update_visual()
	set_process(false)

static func _prepare_native() -> void:
	if _prepared:return
	_prepared = true
	var sample := HayTuft.new()
	sample._build_model()
	sample.strands = 25
	sample._apply_strands()
	if sample._meshes.is_empty():
		sample.free()
		return
	var original: MeshInstance3D = sample._meshes[0]
	_native_mesh = original.mesh as ArrayMesh
	if _native_mesh == null or _native_mesh.get_surface_count() == 0:
		sample.free()
		return
	_native_scale = sample._model.scale
	for surface in _native_mesh.get_surface_count():
		_native_materials.append(original.get_active_material(surface))
	var source := _native_materials[0] as ShaderMaterial
	if source != null and source.shader != null:
		var code := source.shader.code
		if code.contains("void vertex() {") and code.contains("void fragment() {"):
			code = code.replace("void vertex() {", "varying vec3 mp_hopper_point;\nuniform mat4 mp_hopper_inverse;\nvoid vertex() {\nmp_hopper_point = (mp_hopper_inverse * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;")
			code = code.replace("void fragment() {", "void fragment() {\nfloat mp_h = (mp_hopper_point.y - 0.43) / 1.09;\nif (abs(mp_hopper_point.x) > 0.23 + 0.62 * mp_h - 0.018 || mp_hopper_point.z > 0.12 + 0.38 * mp_h - 0.018 || mp_hopper_point.z < -0.38 - 0.48 * mp_h + 0.018) { discard; }")
			_clipped_shader = Shader.new()
			_clipped_shader.code = code
	sample.free()

func _make_stock() -> void:
	var mesh := _native_mesh.duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		var material := _native_materials[surface].duplicate() as ShaderMaterial
		material.shader = _clipped_shader
		mesh.surface_set_material(surface, material)
		_materials.append(material)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = CELL_COUNT
	var index := 0
	for row in 8:
		for col in 11:
			var yaw := sin(float(col * 4 + row * 9)) * 0.2
			var at := Vector3((col - 5) * 0.14 + sin(float(col * 7 + row * 3)) * 0.017,
				sin(float(col * 3 + row * 5)) * 0.008,
				-0.18 + (row - 3.5) * 0.14 + cos(float(col * 5 + row * 7)) * 0.015)
			instances.set_instance_transform(index, Transform3D(Basis(Vector3.UP, yaw).scaled_local(_native_scale), at))
			index += 1
	_stock = MultiMeshInstance3D.new()
	_stock.name = "StoredHay"
	_stock.multimesh = instances
	_stock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stock)

func _make_drops() -> void:
	for index in 4:
		var drop := MeshInstance3D.new()
		drop.name = "IntakeHay%d" % index
		drop.mesh = _native_mesh
		for surface in _native_materials.size():
			drop.set_surface_override_material(surface, _native_materials[surface])
		drop.scale = _native_scale * 0.65
		drop.rotation = Vector3(sin(float(index)) * 0.035, sin(float(index) * 2.5) * 0.18, cos(float(index) * 1.9) * 0.035)
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drop.hide()
		add_child(drop)
		_drops.append(drop)

func set_amount(amount: int, capacity: int) -> void:
	var checked_capacity := maxi(1, capacity)
	var checked_amount := clampi(amount, 0, checked_capacity)
	if _amount == checked_amount and _capacity == checked_capacity:return
	var first := _amount < 0
	var previous := _amount
	_capacity = checked_capacity
	_amount = checked_amount
	_target_fraction = float(_amount) / float(_capacity)
	if first:
		_fraction = _target_fraction
	elif _amount > previous:
		_pour_left = 0.8
	_update_visual()
	set_process(absf(_fraction - _target_fraction) > 0.0001 or _pour_left > 0.0)

func _process(delta: float) -> void:
	_clock += maxf(0.0, delta)
	_fraction = move_toward(_fraction, _target_fraction, maxf(0.0, delta) * 1.8)
	_pour_left = maxf(0.0, _pour_left - delta)
	_update_visual()
	set_process(absf(_fraction - _target_fraction) > 0.0001 or _pour_left > 0.0)

func _update_visual() -> void:
	if not is_instance_valid(_stock):return
	var height := lerpf(0.58, 1.41, _fraction)
	_stock.visible = _fraction > 0.0
	_stock.position.y = height
	_update_clip()
	for index in _drops.size():
		var drop := _drops[index]
		var phase := fposmod(_clock / 0.7 + float(index) / float(_drops.size()), 1.0)
		drop.position = Vector3(sin(float(index) * 2.4) * 0.085,
			1.95 - (1.95 - height + 0.08) * phase * phase,
			-0.18 + cos(float(index) * 1.7) * 0.07)
		drop.visible = _pour_left > 0.0 and _amount > 0 and phase > 0.015 and drop.position.y > height + 0.018

func _update_clip() -> void:
	if not is_inside_tree():return
	var inverse := global_transform.affine_inverse()
	if inverse == _clip_transform and not _materials.is_empty() and _materials[0].get_shader_parameter("mp_hopper_inverse") is Transform3D:
		return
	_clip_transform = inverse
	for material in _materials:
		material.set_shader_parameter("mp_hopper_inverse", inverse)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_instance_valid(_stock):
		_update_clip()
