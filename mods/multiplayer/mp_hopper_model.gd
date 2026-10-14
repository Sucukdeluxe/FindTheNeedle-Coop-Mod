extends Node3D

const OUTLET := Vector3(0.0, 0.0, 0.7)
const LABEL_POINT := Vector3(0.0, 1.85, -0.18)
static var _shared_mesh: ArrayMesh
static var _materials: Array[StandardMaterial3D] = []
var hopper_id := 0
var preview := false
var collision_bits := 0
var _mesh: MeshInstance3D
var _label: Label3D
var _fill: MeshInstance3D
var _shown_fill := -1

func _ready() -> void:
	_make_materials()
	if _shared_mesh == null:
		_shared_mesh = _make_mesh()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _shared_mesh
	add_child(_mesh)
	_fill = MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(1.32, 0.04, 1.0)
	_fill.mesh = fill_mesh
	_fill.material_override = _materials[3]
	_fill.position = Vector3(0.0, 1.31, -0.18)
	_fill.hide()
	add_child(_fill)
	if preview:
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var body := StaticBody3D.new()
	body.collision_layer = collision_bits
	body.collision_mask = 0
	body.set_meta("mp_hopper", self)
	add_child(body)
	var solid := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.7, 1.3, 1.35)
	solid.shape = shape
	solid.position = Vector3(0.0, 0.92, -0.18)
	body.add_child(solid)
	_label = Label3D.new()
	_label.position = LABEL_POINT
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 8
	_label.pixel_size = 0.004
	_label.modulate = Color(0.98, 0.88, 0.62)
	_label.hide()
	add_child(_label)

func set_preview_valid(ok: bool) -> void:
	if not is_instance_valid(_mesh):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.9, 0.55, 0.45) if ok else Color(0.95, 0.25, 0.18, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat

func show_status(text: String, focused: bool) -> void:
	if is_instance_valid(_label):
		if _label.text != text:
			_label.text = text
		_label.visible = focused

func set_fill(amount: int) -> void:
	var bucket := clampi(int(ceil(float(amount) / 5000.0)), 0, 10)
	if bucket == _shown_fill or not is_instance_valid(_fill):
		return
	_shown_fill = bucket
	_fill.visible = bucket > 0
	_fill.position.y = lerpf(0.58, 1.41, float(bucket) / 10.0)
	_fill.scale = Vector3(lerpf(0.38, 1.0, float(bucket) / 10.0), 1.0, lerpf(0.4, 1.0, float(bucket) / 10.0))

static func _make_materials() -> void:
	if not _materials.is_empty():
		return
	for color in [Color(0.17, 0.24, 0.24), Color(0.56, 0.6, 0.61), Color(0.9, 0.45, 0.08), Color(0.54, 0.34, 0.11)]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = 0.7 if _materials.size() < 3 else 0.0
		mat.roughness = 0.58 if _materials.size() < 3 else 1.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials.append(mat)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	for point in [a, b, c, a, c, d]:
		st.set_normal(normal)
		st.add_vertex(point)

static func _box(st: SurfaceTool, at: Vector3, size: Vector3) -> void:
	var a := at - size * 0.5
	var b := at + size * 0.5
	_quad(st, Vector3(a.x,a.y,b.z), Vector3(b.x,a.y,b.z), Vector3(b.x,b.y,b.z), Vector3(a.x,b.y,b.z))
	_quad(st, Vector3(b.x,a.y,a.z), Vector3(a.x,a.y,a.z), Vector3(a.x,b.y,a.z), Vector3(b.x,b.y,a.z))
	_quad(st, Vector3(a.x,a.y,a.z), Vector3(a.x,a.y,b.z), Vector3(a.x,b.y,b.z), Vector3(a.x,b.y,a.z))
	_quad(st, Vector3(b.x,a.y,b.z), Vector3(b.x,a.y,a.z), Vector3(b.x,b.y,a.z), Vector3(b.x,b.y,b.z))
	_quad(st, Vector3(a.x,b.y,b.z), Vector3(b.x,b.y,b.z), Vector3(b.x,b.y,a.z), Vector3(a.x,b.y,a.z))
	_quad(st, Vector3(a.x,a.y,a.z), Vector3(b.x,a.y,a.z), Vector3(b.x,a.y,b.z), Vector3(a.x,a.y,b.z))

static func _make_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for layer in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_materials[layer])
		if layer == 0:
			var top := [Vector3(-0.85,1.52,-0.86), Vector3(0.85,1.52,-0.86), Vector3(0.85,1.52,0.5), Vector3(-0.85,1.52,0.5)]
			var bottom := [Vector3(-0.23,0.43,-0.38), Vector3(0.23,0.43,-0.38), Vector3(0.23,0.43,0.12), Vector3(-0.23,0.43,0.12)]
			for i in 4:
				_quad(st, top[i], top[(i+1)%4], bottom[(i+1)%4], bottom[i])
			_box(st, Vector3(0.0,0.38,-0.12), Vector3(0.55,0.16,0.62))
			_box(st, Vector3(0.0,0.2,0.41), Vector3(0.6,0.12,0.68))
			_box(st, Vector3(0.0,0.1,0.73), Vector3(0.55,0.22,0.06))
		elif layer == 1:
			for x in [-0.7,0.7]:
				for z in [-0.69,0.31]:
					_box(st, Vector3(x,0.45,z), Vector3(0.08,1.68,0.08))
					_box(st, Vector3(x,-0.35,z), Vector3(0.24,0.06,0.24))
				_box(st, Vector3(x,0.15,-0.19), Vector3(0.08,0.08,1.08))
			for z in [-0.69,0.31]:
				_box(st, Vector3(0.0,0.15,z), Vector3(1.46,0.08,0.08))
			for x in [-0.32,0.32]:
				_box(st, Vector3(x,0.3,0.42), Vector3(0.05,0.16,0.7))
			_box(st, Vector3(0.46,0.38,-0.12), Vector3(0.35,0.3,0.35))
		else:
			for z in [-0.86,0.5]:
				_box(st, Vector3(0.0,1.55,z), Vector3(1.78,0.07,0.07))
			for x in [-0.85,0.85]:
				_box(st, Vector3(x,1.55,-0.18), Vector3(0.07,0.07,1.43))
			_box(st, Vector3(0.0,0.26,0.77), Vector3(0.62,0.05,0.06))
			_box(st, Vector3(-0.48,0.83,0.345), Vector3(0.26,0.18,0.025))
		st.commit(mesh)
	return mesh
