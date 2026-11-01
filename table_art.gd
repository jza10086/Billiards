extends Node3D
## Original metric table/lounge meshes. Play surface is XZ at Y = 0.
const BALL_RADIUS: Variant = 0.028575
const HALF_WIDTH: Variant = 0.635
const HALF_LENGTH: Variant = 1.27
var felt: StandardMaterial3D
var wood: StandardMaterial3D
var brass: StandardMaterial3D
var dark: StandardMaterial3D
var cream: StandardMaterial3D
var room_root: Node3D

func material(color: Color, roughness: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m: Variant = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metal
	return m

func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: Variant = BoxMesh.new()
	mesh.size = size
	var node: Variant = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh: Variant = CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 48
	var node: Variant = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node

func polygon_surface(points: PackedVector2Array, y: float, mat: Material) -> MeshInstance3D:
	var indices: Variant = Geometry2D.triangulate_polygon(points)
	var st: Variant = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for index: Variant in indices:
		var p: Variant = points[index]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x / 1.27, p.y / 2.54))
		st.add_vertex(Vector3(p.x, y, p.y))
	var node: Variant = MeshInstance3D.new()
	node.mesh = st.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func build() -> void:
	felt = material(Color('#164f42'), 0.94)
	felt.cull_mode = BaseMaterial3D.CULL_DISABLED
	wood = material(Color('#807267'), 0.72)
	wood.albedo_texture = load('res://games/minigame/godot_party_default_billiards/assets/textures/wood_table_001/wood_table_001_diff_1k.jpg')
	wood.normal_enabled = true
	wood.normal_texture = load('res://games/minigame/godot_party_default_billiards/assets/textures/wood_table_001/wood_table_001_nor_gl_1k.jpg')
	wood.normal_scale = 0.06
	wood.roughness_texture = load('res://games/minigame/godot_party_default_billiards/assets/textures/wood_table_001/wood_table_001_rough_1k.jpg')
	wood.roughness = 0.88
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(0.8,0.8,0.8)
	var cloth_noise: Variant = FastNoiseLite.new()
	cloth_noise.frequency = 0.24
	cloth_noise.seed = 294
	var cloth_texture: Variant = NoiseTexture2D.new()
	cloth_texture.width = 256
	cloth_texture.height = 256
	cloth_texture.noise = cloth_noise
	cloth_texture.as_normal_map = true
	cloth_texture.bump_strength = 0.2
	felt.normal_enabled = true
	felt.normal_texture = cloth_texture
	felt.normal_scale = 0.12
	felt.uv1_scale = Vector3(7,14,1)
	brass = material(Color('#978365'), 0.55, 0.5)
	dark = material(Color('#091313'), 0.82)
	cream = material(Color('#ead8a4'), 0.35)
	var floor_mat: Variant = material(Color('#151c20'), 0.72)
	room_root = Node3D.new()
	room_root.name = 'Lounge'
	add_child(room_root)
	box(room_root, Vector3(12,0.1,12), Vector3(0,-0.83,0), floor_mat)
	# Subtle floor seams and inlaid rug below the table.
	box(room_root, Vector3(2.5,0.01,4.0), Vector3(0,-0.773,0), material(Color('#102e31')))
	for x: Variant in [-1.23,1.23]:
		box(room_root, Vector3(0.012,0.012,3.94), Vector3(x,-0.764,0), brass)
	for z: Variant in [-1.97,1.97]:
		box(room_root, Vector3(2.45,0.012,0.012), Vector3(0,-0.764,z), brass)
	for z: Variant in range(-6,7):
		box(room_root,Vector3(12,0.002,0.008),Vector3(0,-0.774,float(z)*0.65),material(Color('#20282a')))
	# Table cabinet and beveled layered apron.
	box(self, Vector3(1.66,0.20,2.93), Vector3(0,-0.22,0), wood)
	box(self, Vector3(1.72,0.025,2.99), Vector3(0,-0.115,0), brass)
	box(self, Vector3(1.67,0.06,2.94), Vector3(0,-0.08,0), dark)
	box(self, Vector3(1.57,0.045,2.84), Vector3(0,-0.35,0), brass)
	for x: Variant in [-0.57,0.57]:
		for z: Variant in [-1.05,1.05]:
			cylinder(self,0.085,0.39,Vector3(x,-0.55,z),wood,0.065)
			cylinder(self,0.088,0.035,Vector3(x,-0.756,z),brass)
	# Pocket-cut cloth: side mouths and four diagonal corner mouths.
	var cloth: Variant = PackedVector2Array([
		Vector2(-.545,-1.27),Vector2(.545,-1.27),Vector2(.635,-1.18),
		Vector2(.635,-.081),Vector2(.594,-.062),Vector2(.569,-.031),Vector2(.561,0),Vector2(.569,.031),Vector2(.594,.062),Vector2(.635,.081),
		Vector2(.635,1.18),Vector2(.545,1.27),Vector2(-.545,1.27),Vector2(-.635,1.18),
		Vector2(-.635,.081),Vector2(-.594,.062),Vector2(-.569,.031),Vector2(-.561,0),Vector2(-.569,-.031),Vector2(-.594,-.062),Vector2(-.635,-.081),Vector2(-.635,-1.18)])
	polygon_surface(cloth,0.0,felt)
	# Walnut rails separated across the side pocket jaws.
	for x: Variant in [-1.0,1.0]:
		for z: Variant in [-.687,.687]:
			box(self,Vector3(.15,.075,1.12),Vector3(x*.742,.005,z),wood)
			box(self,Vector3(.016,.016,1.10),Vector3(x*.815,.042,z),brass)
			box(self,Vector3(.052,.055,1.09),Vector3(x*.661,.021,z),felt)
	for z: Variant in [-1.0,1.0]:
		box(self,Vector3(1.11,.075,.15),Vector3(0,.005,z*1.377),wood)
		box(self,Vector3(1.09,.016,.016),Vector3(0,.042,z*1.45),brass)
		box(self,Vector3(1.085,.055,.052),Vector3(0,.021,z*1.296),felt)
	# Pocket mouths are black recessed cylinders, not black decals on cloth.
	for z: Variant in [-1.27,0.0,1.27]:
		for x: Variant in [-.635,.635]:
			var p: Variant = Vector3(x,-.015,z)
			cylinder(self,.085,.018,p,dark)
			cylinder(self,.064,.13,p+Vector3(0,-.073,0),material(Color('#020707')))
			# Fine leather edge, no obstruction across the mouth.
			var torus: Variant = TorusMesh.new()
			torus.inner_radius = .069
			torus.outer_radius = .082
			torus.rings = 32
			torus.ring_segments = 12
			var rim: Variant = MeshInstance3D.new()
			rim.mesh = torus
			rim.material_override = material(Color('#33271f'),.6)
			rim.position = p + Vector3(0,.022,0)
			add_child(rim)
	# Mother-of-pearl diamond sights, three per long-rail half.
	for x: Variant in [-.746,.746]:
		for z: Variant in [-.95,-.63,-.32,.32,.63,.95]:
			var mark: Variant = box(self,Vector3(.013,.001,.022),Vector3(x,.044,z),cream)
			mark.rotation.y = PI/4.0
	for z: Variant in [-1.378,1.378]:
		for x: Variant in [-.317,0.0,.317]:
			var mark: Variant = box(self,Vector3(.013,.001,.022),Vector3(x,.044,z),cream)
			mark.rotation.y = PI/4.0
	# Baulk / foot spot, intentionally minimal and flush with cloth.
	for z: Variant in [-.635,.635]:
		cylinder(self,.003,0.0005,Vector3(0,.001,z),cream)
	# Lounge accent walls, quiet and distant from the tabletop.
	var wall: Variant = material(Color('#102326'))
	box(room_root,Vector3(8,3,.12),Vector3(0,.66,-4.2),wall)
	for x: Variant in [-3.0,-1.5,0.0,1.5,3.0]:
		box(room_root,Vector3(.025,1.5,.025),Vector3(x,.4,-4.12),brass)
		box(room_root,Vector3(1.4,.018,.025),Vector3(x,-.34,-4.12),brass)
	# Three shaded pendant pools of warm light.
	for z: Variant in [-.78,0.0,.78]:
		cylinder(room_root,.24,.18,Vector3(2.3,1.7,z),dark,.13)
		cylinder(room_root,.244,.012,Vector3(2.3,1.605,z),brass)
		var glow: Variant = material(Color('#ffe4b0'))
		glow.emission_enabled = true
		glow.emission = Color('#ffe4b0')
		glow.emission_energy_multiplier = 1.6
		cylinder(room_root,.20,.008,Vector3(2.3,1.596,z),glow)
		cylinder(room_root,.007,1.0,Vector3(2.3,2.3,z),dark)
		var light: Variant = OmniLight3D.new()
		light.position = Vector3(0,1.46,z)
		light.light_color = Color('#ffe8c5')
		light.light_energy = 0.12
		light.omni_range = 3.4
		light.shadow_enabled = false
		room_root.add_child(light)
	var sun: Variant = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62,-28,0)
	sun.light_color = Color('#c1dce6')
	sun.light_energy = .32
	sun.shadow_enabled = true
	add_child(sun)
	var env: Variant = WorldEnvironment.new()
	var e: Variant = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color('#071317')
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color('#a7c4cb')
	e.ambient_light_energy = .22
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)

func make_ball(number: int) -> Node3D:
	var root: Variant = Node3D.new()
	root.name = 'Ball%02d' % number
	var sphere: Variant = SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS*2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var mesh: Variant = MeshInstance3D.new()
	mesh.mesh = sphere
	var mat: Variant = material(Color.WHITE,.17,.05)
	mat.albedo_texture = load('res://games/minigame/godot_party_default_billiards/assets/balls/ball_%02d.png' % number)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mesh.material_override = mat
	# Number medallions start facing upward for an immediately readable rack.
	mesh.rotation_degrees = Vector3(0,0,90)
	root.add_child(mesh)
	return root

func make_cue() -> Node3D:
	var root: Variant = Node3D.new()
	root.name = 'Cue'
	var tilt: Variant = Node3D.new()
	tilt.rotation.x = -0.075
	root.add_child(tilt)
	var maple: Variant = material(Color('#ddbd83'),.28)
	var grip: Variant = material(Color('#253d3e'),.7)
	var tip: Variant = material(Color('#60a4a6'),.7)
	var shaft: Variant = cylinder(tilt,.008,1.35,Vector3(0,0,.685),maple,.004)
	shaft.rotation.x = PI/2.0
	var wrap: Variant = cylinder(tilt,.009,.34,Vector3(0,0,1.06),grip)
	wrap.rotation.x = PI/2.0
	var ferrule: Variant = cylinder(tilt,.0048,.025,Vector3(0,0,.021),cream)
	ferrule.rotation.x = PI/2.0
	var chalk: Variant = cylinder(tilt,.0048,.009,Vector3(0,0,.0045),tip)
	chalk.rotation.x = PI/2.0
	for z: Variant in [.87,1.24,1.35]:
		var band: Variant = cylinder(tilt,.0093,.008,Vector3(0,0,z),brass)
		band.rotation.x = PI/2.0
	return root
