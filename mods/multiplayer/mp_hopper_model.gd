extends Node3D

const OUTLET := Vector3(0.0, 0.0, 0.7)
static var _shared_mesh: ArrayMesh
static var _materials: Array[StandardMaterial3D] = []
var hopper_id := 0
var intake: Area3D
var preview := false
var collision_bits := 0
var _mesh: MeshInstance3D
var _fill: MeshInstance3D
var _shown_fill := -1
var _status_layer: CanvasLayer
var _status_panel: PanelContainer
var _status_lines: Array[Label] = []
var _status_text := ""

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
	intake = Area3D.new()
	intake.collision_layer = 0
	intake.collision_mask = Cfg.L_PROP | Cfg.L_STRAND
	add_child(intake)
	var mouth := CollisionShape3D.new()
	var mouth_shape := BoxShape3D.new()
	mouth_shape.size = Vector3(1.72, 0.9, 1.4)
	mouth.shape = mouth_shape
	mouth.position = Vector3(0.0, 1.72, -0.18)
	intake.add_child(mouth)

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
	if not focused or preview:
		if is_instance_valid(_status_layer):
			_status_layer.hide()
		return
	if not is_instance_valid(_status_layer):
		_make_status()
	if _status_text != text:
		_status_text = text
		var lines := text.split("\n")
		for i in _status_lines.size():
			_status_lines[i].text = lines[i] if i < lines.size() else ""
		_layout_status()
	_status_layer.show()

func _make_status() -> void:
	_status_layer = CanvasLayer.new()
	_status_layer.layer = 4
	add_child(_status_layer)
	_status_panel = PanelContainer.new()
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.046, 0.9)
	style.border_color = Color(0.64, 0.53, 0.29, 0.7)
	style.set_border_width_all(1)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	_status_panel.add_theme_stylebox_override("panel", style)
	_status_layer.add_child(_status_panel)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 3)
	_status_panel.add_child(rows)
	for i in 4:
		var line := Label.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.clip_text = true
		line.add_theme_font_size_override("font_size", [18, 20, 16, 14][i])
		line.add_theme_color_override("font_color", Color(0.97, 0.82, 0.45) if i == 0 else Color(0.91, 0.92, 0.89))
		rows.add_child(line)
		_status_lines.append(line)
	_status_panel.resized.connect(_position_status)
	get_viewport().size_changed.connect(_layout_status)

func _layout_status() -> void:
	if not is_instance_valid(_status_panel):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(560.0, maxf(180.0, viewport_size.x - 32.0))
	_status_panel.size = Vector2(width, 116.0)
	_position_status()

func _position_status() -> void:
	if not is_instance_valid(_status_panel):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _status_panel.size
	_status_panel.position = Vector2((viewport_size.x - panel_size.x) * 0.5, 12.0)

func set_fill(amount: int, capacity: int = 50000) -> void:
	var bucket := clampi(int(ceil(float(amount) * 10.0 / maxf(1.0, float(capacity)))), 0, 10)
	if bucket == _shown_fill or not is_instance_valid(_fill):
		return
	_shown_fill = bucket
	_fill.visible = bucket > 0
	_fill.position.y = lerpf(0.58, 1.41, float(bucket) / 10.0)
	_fill.scale = Vector3(lerpf(0.38, 1.0, float(bucket) / 10.0), 1.0, lerpf(0.4, 1.0, float(bucket) / 10.0))

static func _make_materials() -> void:
	if not _materials.is_empty():
		return
	for color in [Color(0.22, 0.32, 0.33), Color(0.5, 0.54, 0.55), Color(0.12, 0.145, 0.15), Color(0.54, 0.34, 0.11)]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = [0.35, 0.82, 0.62, 0.0][_materials.size()]
		mat.roughness = [0.66, 0.43, 0.61, 1.0][_materials.size()]
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

static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, width: float, depth: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var up := axis.cross(side).normalized()
	var corners: Array[Vector3] = []
	for end in [a, b]:
		for pair in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			corners.append(end + side * pair.x * width * 0.5 + up * pair.y * depth * 0.5)
	for i in 4:
		_quad(st, corners[i], corners[(i+1)%4], corners[(i+1)%4+4], corners[i+4])
	_quad(st, corners[3], corners[2], corners[1], corners[0])
	_quad(st, corners[4], corners[5], corners[6], corners[7])

static func _cylinder(st: SurfaceTool, center: Vector3, axis: Vector3, radius: float, length: float, sides: int = 12) -> void:
	var direction := axis.normalized()
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var up := direction.cross(side).normalized()
	var a := center - direction * length * 0.5
	var b := center + direction * length * 0.5
	for i in sides:
		var angle := TAU * float(i) / float(sides)
		var next := TAU * float(i + 1) / float(sides)
		var offset := (side * cos(angle) + up * sin(angle)) * radius
		var offset_next := (side * cos(next) + up * sin(next)) * radius
		_quad(st, a + offset, a + offset_next, b + offset_next, b + offset)
		for point in [a, a + offset_next, a + offset]:
			st.set_normal(-direction)
			st.add_vertex(point)
		for point in [b, b + offset, b + offset_next]:
			st.set_normal(direction)
			st.add_vertex(point)

static func _make_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var top := [Vector3(-0.85,1.52,-0.86), Vector3(0.85,1.52,-0.86), Vector3(0.85,1.52,0.5), Vector3(-0.85,1.52,0.5)]
	var bottom := [Vector3(-0.23,0.43,-0.38), Vector3(0.23,0.43,-0.38), Vector3(0.23,0.43,0.12), Vector3(-0.23,0.43,0.12)]
	for layer in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_materials[layer])
		if layer == 0:
			for i in 4:
				_quad(st, top[i], top[(i+1)%4], bottom[(i+1)%4], bottom[i])
			_box(st, Vector3(0.0,0.38,-0.12), Vector3(0.55,0.16,0.62))
			_box(st, Vector3(0.0,0.2,0.41), Vector3(0.6,0.12,0.68))
			_box(st, Vector3(0.0,0.1,0.73), Vector3(0.55,0.22,0.06))
			_box(st, Vector3(0.63,0.44,-0.12), Vector3(0.26,0.27,0.31))
			for x in [-0.32,0.32]:
				_box(st, Vector3(x,0.31,0.42), Vector3(0.045,0.18,0.7))
		elif layer == 1:
			for i in 4:
				var j := (i + 1) % 4
				var inner_a: Vector3 = top[i] + (Vector3(0.0,1.52,-0.18) - top[i]).normalized() * 0.025
				var inner_b: Vector3 = top[j] + (Vector3(0.0,1.52,-0.18) - top[j]).normalized() * 0.025
				var low_a: Vector3 = bottom[i] + (Vector3(0.0,0.43,-0.13) - bottom[i]).normalized() * 0.025
				var low_b: Vector3 = bottom[j] + (Vector3(0.0,0.43,-0.13) - bottom[j]).normalized() * 0.025
				_quad(st, inner_b, inner_a, low_a, low_b)
				_beam(st, top[i], top[j], 0.045, 0.045)
			for z in [-0.86,0.5]:
				for x in [-0.75,-0.38,0.0,0.38,0.75]:
					_cylinder(st, Vector3(x,1.523,z), Vector3.UP,0.012,0.056,6)
			for x in [-0.85,0.85]:
				for z in [-0.74,-0.36,0.0,0.38]:
					_cylinder(st, Vector3(x,1.523,z), Vector3.UP,0.012,0.056,6)
			for x in [-0.7,0.7]:
				for z in [-0.69,0.31]:
					_box(st, Vector3(x,0.94,z), Vector3(0.11,0.17,0.11))
					for y in [0.90,0.98]:
						_cylinder(st,Vector3(x, y,z + 0.066),Vector3.FORWARD,0.019,0.023,6)
					for dx in [-0.075,0.075]:
						_cylinder(st,Vector3(x+dx,-0.309,z),Vector3.UP,0.014,0.027,6)
			_box(st, Vector3(-0.43,0.98,0.317), Vector3(0.25,0.13,0.018))
			for y in [0.96,0.995]:
				_box(st,Vector3(-0.43,y,0.329),Vector3(0.16,0.008,0.006))
			_cylinder(st,Vector3(0.76,0.45,-0.12),Vector3.RIGHT,0.08,0.12)
			for z in [-0.24,0.0]:
				_cylinder(st,Vector3(0.77,0.54,z),Vector3.RIGHT,0.012,0.025,6)
		else:
			for x in [-0.7,0.7]:
				for z in [-0.69,0.31]:
					_box(st, Vector3(x,0.39,z), Vector3(0.08,1.56,0.08))
					_box(st, Vector3(x,-0.35,z), Vector3(0.24,0.06,0.24))
				_box(st, Vector3(x,0.15,-0.19), Vector3(0.08,0.08,1.08))
				_beam(st,Vector3(x,0.18,-0.67),Vector3(x,0.68,0.29),0.04,0.04)
			for z in [-0.69,0.31]:
				_box(st, Vector3(0.0,0.15,z), Vector3(1.46,0.08,0.08))
			for i in 4:
				_beam(st, top[i].lerp(bottom[i],0.06), top[i].lerp(bottom[i],0.95),0.025,0.025)
			_cylinder(st,Vector3(0.42,0.39,-0.12),Vector3.RIGHT,0.115,0.24)
			for x in [0.33,0.37,0.41,0.45,0.49]:
				_cylinder(st,Vector3(x,0.39,-0.12),Vector3.RIGHT,0.126,0.014)
			_box(st,Vector3(0.0,0.27,0.74),Vector3(0.54,0.017,0.11))
			_box(st,Vector3(0.0,0.448,-0.13),Vector3(0.43,0.02,0.44))
		st.commit(mesh)
	return mesh
