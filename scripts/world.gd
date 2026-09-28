class_name WorldBuilder
extends RefCounted
## Builds the Black Ravine: a noise-shaped snow valley between cliff walls,
## dressed with original Blender hero assets and small amounts of CC0 support.
## Everything static lives under one `World` node so main.gd only has to deal
## with gameplay.

const X_MIN := -30
const X_MAX := 30
const Z_MIN := -112
const Z_MAX := 44
const CHUNK_DEPTH := 26
const VALLEY_HALF_WIDTH := 11.0
## Forested shoulders climb gently for this many metres beyond the floor before the cliffs.
const SHOULDER_WIDTH := 9.0
const BELL_ORIGIN := Vector3(-6.0, 0.0, -28.0)
const GATE_Z := -92.0
const COURTYARD_Z := -100.0
## Maren's cairns sit at the ends of the flank routes: the Widowpine shoulder
## above the fold, the east shoulder of the Carrion shrine, and the sunken west
## gully beside the raised Black Ravine road, which also hides a kill-site camp.
const CAIRNS := [Vector3(-16.0, 0.0, 4.0), Vector3(15.0, 0.0, -34.0), Vector3(-17.2, 0.0, -68.8)]
const FLANK_CAMP := Vector3(-15.0, 0.0, -65.0)

const NATURE := "res://assets/nature/%s.glb"
const CASTLE := "res://assets/castle/%s.glb"
const WIDOWPINE_FOLD := "res://assets/environment/widowpine/widowpine_broken_fold.glb"
const CARRION_BELL_SHRINE := "res://assets/environment/carrion_cut/carrion_cut_mother_bell.glb"
const IRON_CROWN_ABBEY := "res://assets/environment/iron_crown/iron_crown_bell_abbey_blockout.glb"
const VEGETATION := "res://assets/environment/vegetation/%s.glb"
const RAVINE_ROCK := "res://assets/environment/rocks/%s.glb"

static var _noise: FastNoiseLite
static var _detail: FastNoiseLite
static var _mesh_cache := {}

## Result of a build: nodes gameplay needs to know about.
class Built:
	var root: Node3D
	var lanterns: Array = []      # {node, light, position, lit}
	var campfires: Array = []     # OmniLight3D
	var bell_material: StandardMaterial3D
	var gate: Node3D
	var gate_block: StaticBody3D
	var environment: Environment
	var sky_material: ProceduralSkyMaterial
	var panorama_sky_material: PanoramaSkyMaterial
	var moon: DirectionalLight3D
	var aurora: Node3D
	var snowfall: GPUParticles3D
	var snow_material: StandardMaterial3D
	var bellthorn_storm: GPUParticles3D
	var name_lights: Array[OmniLight3D] = []
	var cairns: Array = []        # {node, position, ember, light, index, kindled}
	var biome_roots: Dictionary = {}


static func _ensure_noise() -> void:
	if _noise:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = 4147
	_noise.frequency = 0.045
	_noise.fractal_octaves = 3
	_detail = FastNoiseLite.new()
	_detail.seed = 91
	_detail.frequency = 0.21


## Height of the ravine at world (x, z). Deterministic, so props and enemies
## can be planted on it without sampling the mesh.
static func height_at(x: float, z: float) -> float:
	_ensure_noise()
	var ascent := (30.0 - z) * 0.055
	var roll := _noise.get_noise_2d(x, z) * 0.55 + _detail.get_noise_2d(x, z) * 0.14
	var floor_y := ascent + roll
	# The homestead and the fortress courtyard sit on flatter ground.
	var flat := maxf(smoothstep(14.0, 4.0, absf(z - 0.0)), smoothstep(12.0, 3.0, absf(z - COURTYARD_Z)))
	floor_y = lerpf(floor_y, ascent + roll * 0.25, flat)
	# The shrine stands on a low rise.
	floor_y += 1.1 * smoothstep(9.0, 2.0, Vector2(x - BELL_ORIGIN.x, z - BELL_ORIGIN.z).length())
	# The rebuilt Iron Crown climbs through three broad terraces before reaching
	# the Iron Throat. Raising the central height field keeps enemies, debug
	# warps, checkpoints, and the Blender-authored traversal on the same ground.
	var crown_progress := clampf(inverse_lerp(-40.0, GATE_Z, z), 0.0, 1.0)
	var crown_route := 1.0 - smoothstep(10.0, 17.0, absf(x))
	floor_y += crown_route * smoothstep(0.0, 1.0, crown_progress) * 8.0
	var beyond := maxf(0.0, absf(x) - VALLEY_HALF_WIDTH)
	var pinch := 1.0 + smoothstep(-40.0, -70.0, z) * 0.25  # the ravine narrows on the ascent
	# Shoulders: gentle terraces where the pines stand.
	var shoulder_reach := minf(beyond, SHOULDER_WIDTH)
	var shoulder := shoulder_reach * 0.34 + _noise.get_noise_2d(x * 1.3, z * 1.3) * shoulder_reach * 0.12
	# Cliffs: steep walls beyond the shoulders, levelling off toward the map edge.
	var cliff_in := maxf(0.0, beyond * pinch - SHOULDER_WIDTH)
	var cliff := pow(cliff_in / 6.0, 1.7) * 14.0
	cliff = 34.0 * (1.0 - exp(-cliff / 34.0))
	cliff += _noise.get_noise_2d(x * 2.0, z * 2.0) * minf(cliff_in, 8.0) * 0.4
	return floor_y + shoulder + cliff


## Surface normal from the height field itself, identical on both sides of a chunk border.
static func normal_at(x: float, z: float) -> Vector3:
	var dx := height_at(x + 0.5, z) - height_at(x - 0.5, z)
	var dz := height_at(x, z + 0.5) - height_at(x, z - 0.5)
	return Vector3(-dx, 1.0, -dz).normalized()


static func slope_at(x: float, z: float) -> float:
	var h := height_at(x, z)
	var dx := height_at(x + 0.5, z) - h
	var dz := height_at(x, z + 0.5) - h
	return Vector2(dx, dz).length() * 2.0


static func build(parent: Node3D) -> Built:
	var built := Built.new()
	built.root = Node3D.new()
	built.root.name = "World"
	parent.add_child(built.root)
	_build_sky(built)
	_build_terrain(built.root)
	_build_route_dressing(built.root)
	_build_forest(built.root)
	_build_trailhead(built)
	_build_homestead(built)
	_build_shrine(built)
	_build_ascent(built)
	_build_flank_routes(built)
	_build_carrion_remains(built.root)
	_build_fortress(built)
	built.snowfall = _build_snowfall(built)
	set_biome(built, "whitewood")
	return built


# --- Terrain -----------------------------------------------------------------

static func _terrain_material() -> ShaderMaterial:
	var shader := preload("res://assets/materials/ravine_terrain.gdshader")
	var material := ShaderMaterial.new()
	material.shader = shader
	var grain := NoiseTexture2D.new()
	var grain_noise := FastNoiseLite.new()
	grain_noise.seed = 7
	grain_noise.frequency = 0.08
	grain.noise = grain_noise
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	material.set_shader_parameter("grain", grain)
	material.set_shader_parameter("snow_albedo", load("res://assets/materials/polyhaven/snow_04/snow_04_Diffuse.jpg"))
	material.set_shader_parameter("rock_albedo", load("res://assets/materials/polyhaven/dark_rock/dark_rock_Diffuse.jpg"))
	material.set_shader_parameter("snow_normal", load("res://assets/materials/polyhaven/snow_04/snow_04_nor_gl.jpg"))
	material.set_shader_parameter("rock_normal", load("res://assets/materials/polyhaven/dark_rock/dark_rock_nor_gl.jpg"))
	material.set_shader_parameter("snow_roughness", load("res://assets/materials/polyhaven/snow_04/snow_04_Rough.jpg"))
	material.set_shader_parameter("rock_roughness", load("res://assets/materials/polyhaven/dark_rock/dark_rock_Rough.jpg"))
	return material


static func _build_terrain(root: Node3D) -> void:
	var material := _terrain_material()
	var width := X_MAX - X_MIN + 1
	var depth := Z_MAX - Z_MIN + 1
	var heights := PackedFloat32Array()
	heights.resize(width * depth)
	for zi in depth:
		for xi in width:
			heights[zi * width + xi] = height_at(X_MIN + xi, Z_MIN + zi)

	# Chunked along z so the compatibility renderer's per-mesh light limit
	# only has to cover the lanterns of one zone at a time.
	var z0 := Z_MIN
	var chunk_index := 0
	while z0 < Z_MAX:
		var z1 := mini(Z_MAX, z0 + CHUNK_DEPTH)
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for z in range(z0, z1):
			for x in range(X_MIN, X_MAX):
				var a := Vector3(x, heights[(z - Z_MIN) * width + (x - X_MIN)], z)
				var b := Vector3(x + 1, heights[(z - Z_MIN) * width + (x + 1 - X_MIN)], z)
				var c := Vector3(x, heights[(z + 1 - Z_MIN) * width + (x - X_MIN)], z + 1)
				var d := Vector3(x + 1, heights[(z + 1 - Z_MIN) * width + (x + 1 - X_MIN)], z + 1)
				# Godot front faces use clockwise winding. The previous order
				# left collision intact but culled this entire surface from above.
				for v in [a, b, c, b, d, c]:
					tool.set_uv(Vector2(v.x, v.z) * 0.1)
					tool.set_normal(normal_at(v.x, v.z))
					tool.add_vertex(v)
		tool.generate_tangents()
		var chunk := MeshInstance3D.new()
		chunk.name = "Terrain_%02d" % chunk_index
		chunk.mesh = tool.commit()
		chunk.material_override = material
		root.add_child(chunk)
		chunk_index += 1
		z0 = z1

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = heights
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3((X_MIN + X_MAX) * 0.5, 0.0, (Z_MIN + Z_MAX) * 0.5)
	body.add_child(collider)
	root.add_child(body)


## Thin, terrain-conforming layers break up the broad height field without
## changing collision. They also put the massacre trail and worsening ground
## conditions directly under the player's feet instead of leaving them in text.
static func _build_route_dressing(root: Node3D) -> void:
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.005, 0.011, 0.018, 0.84)
	ice.metallic = 0.03
	ice.roughness = 0.62
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.vertex_color_use_as_albedo = true
	ice.vertex_color_is_srgb = true

	var old_blood := StandardMaterial3D.new()
	old_blood.albedo_color = Color(0.24, 0.006, 0.004, 0.84)
	old_blood.roughness = 0.92
	old_blood.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	old_blood.vertex_color_use_as_albedo = true
	old_blood.vertex_color_is_srgb = true

	var ash := StandardMaterial3D.new()
	ash.albedo_color = Color(0.035, 0.038, 0.045, 0.72)
	ash.roughness = 1.0
	ash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ash.vertex_color_use_as_albedo = true
	ash.vertex_color_is_srgb = true

	var ice_patches := [
		{"at": Vector2(-2.8, 27.0), "size": Vector2(4.8, 2.2), "yaw": -0.22},
		{"at": Vector2(3.1, 10.0), "size": Vector2(5.6, 2.0), "yaw": 0.2},
		{"at": Vector2(-2.0, -5.0), "size": Vector2(4.2, 1.8), "yaw": -0.35},
		{"at": Vector2(2.5, -24.0), "size": Vector2(5.4, 2.3), "yaw": 0.28},
		{"at": Vector2(-2.8, -39.0), "size": Vector2(4.6, 2.0), "yaw": -0.18},
		{"at": Vector2(2.2, -57.0), "size": Vector2(5.2, 2.1), "yaw": 0.25},
		{"at": Vector2(-2.0, -73.0), "size": Vector2(4.4, 1.8), "yaw": -0.3},
		{"at": Vector2(2.6, -86.0), "size": Vector2(5.0, 2.2), "yaw": 0.16},
	]
	_build_patch_layer(root, "BlackIceSeams", ice_patches, ice, 801, 0.034, true)

	var trail_marks: Array = []
	for step in 18:
		var z := 32.0 - step * 1.15
		var track_x := sin(step * 0.74) * 0.5
		for side in [-1.0, 1.0]:
			trail_marks.append({
				"at": Vector2(track_x + side * 0.14, z + side * 0.08),
				"size": Vector2(0.095, 0.24),
				"yaw": side * 0.2 + sin(step * 0.4) * 0.08,
			})
	_build_patch_layer(root, "WidowpineBloodTracks", trail_marks, old_blood, 414, 0.046, false)
	_build_widowpine_snow_relief(root)

	var carrion_stains := [
		{"at": Vector2(7.4, -20.0), "size": Vector2(2.4, 1.15), "yaw": 0.35},
		{"at": Vector2(-7.2, -36.0), "size": Vector2(2.0, 1.0), "yaw": -0.42},
		{"at": Vector2(6.8, -55.0), "size": Vector2(2.8, 1.25), "yaw": 0.18},
	]
	_build_patch_layer(root, "CarrionOldStains", carrion_stains, old_blood, 991, 0.04, true)

	var crown_ash: Array = []
	for index in 9:
		var z := -78.0 - index * 3.8
		crown_ash.append({
			"at": Vector2((-1.0 if index % 2 == 0 else 1.0) * (2.2 + index % 3), z),
			"size": Vector2(3.4 + index % 2, 1.4 + (index % 3) * 0.35),
			"yaw": -0.3 + index * 0.11,
		})
	_build_patch_layer(root, "IronCrownAshScars", crown_ash, ash, 1804, 0.03, true)


## Shallow, wind-cut snow ridges give the opening path physical relief at the
## player's scale. They sit above collision by only a few centimetres, so they
## model light without snagging movement or changing encounter navigation.
static func _build_widowpine_snow_relief(root: Node3D) -> void:
	var snow_crust := StandardMaterial3D.new()
	snow_crust.resource_name = "Widowpine wind crust"
	snow_crust.albedo_color = Color(0.27, 0.32, 0.38)
	snow_crust.roughness = 0.88
	snow_crust.roughness_texture = load("res://assets/materials/polyhaven/snow_04/snow_04_Rough.jpg")
	snow_crust.normal_enabled = true
	snow_crust.normal_scale = 0.42
	snow_crust.normal_texture = load("res://assets/materials/polyhaven/snow_04/snow_04_nor_gl.jpg")

	var rng := _random(1971)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 5
	for ridge_index in 26:
		var center := Vector2(rng.randf_range(-8.2, 8.2), rng.randf_range(-11.0, 39.0))
		var yaw := rng.randf_range(-0.26, 0.26)
		var direction := Vector2(cos(yaw), sin(yaw))
		var side := Vector2(-direction.y, direction.x)
		var length := rng.randf_range(0.55, 1.5)
		var width := rng.randf_range(0.1, 0.24)
		var height := rng.randf_range(0.035, 0.09)
		var curve := rng.randf_range(-0.12, 0.12)
		var rows: Array = []
		for segment in segments:
			var t := segment / float(segments - 1)
			var taper := sin(t * PI)
			var center_2d := center + direction * ((t - 0.5) * length) + side * (sin(t * PI) * curve)
			var half_width := width * (0.18 + taper * 0.82)
			var left_2d := center_2d - side * half_width
			var right_2d := center_2d + side * half_width
			rows.append([
				Vector3(left_2d.x, height_at(left_2d.x, left_2d.y) + 0.022, left_2d.y),
				Vector3(center_2d.x, height_at(center_2d.x, center_2d.y) + 0.026 + height * taper, center_2d.y),
				Vector3(right_2d.x, height_at(right_2d.x, right_2d.y) + 0.022, right_2d.y),
			])
		for segment in range(segments - 1):
			var t0 := segment / float(segments - 1)
			var t1 := (segment + 1) / float(segments - 1)
			for strip in 2:
				var quad := [
					{"point": rows[segment][strip], "uv": Vector2(t0 * length, float(strip))},
					{"point": rows[segment + 1][strip], "uv": Vector2(t1 * length, float(strip))},
					{"point": rows[segment][strip + 1], "uv": Vector2(t0 * length, float(strip + 1))},
					{"point": rows[segment][strip + 1], "uv": Vector2(t0 * length, float(strip + 1))},
					{"point": rows[segment + 1][strip], "uv": Vector2(t1 * length, float(strip))},
					{"point": rows[segment + 1][strip + 1], "uv": Vector2(t1 * length, float(strip + 1))},
				]
				for entry in quad:
					tool.set_uv(entry.uv)
					tool.add_vertex(entry.point)
	tool.generate_normals()
	tool.generate_tangents()
	var relief := MeshInstance3D.new()
	relief.name = "WidowpineWindCrust"
	relief.mesh = tool.commit()
	relief.material_override = snow_crust
	root.add_child(relief)


static func _build_patch_layer(root: Node3D, name: String, specs: Array, material: StandardMaterial3D, seed_value: int, lift: float, feathered: bool) -> void:
	var rng := _random(seed_value)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 14
	for spec in specs:
		var center_2d: Vector2 = spec.at
		var size: Vector2 = spec.size
		var yaw: float = spec.yaw
		var center := Vector3(center_2d.x, height_at(center_2d.x, center_2d.y) + lift, center_2d.y)
		var perimeter: Array[Vector3] = []
		for segment in segments:
			var angle := TAU * segment / segments
			var radial := rng.randf_range(0.78, 1.16)
			var offset := Vector2(cos(angle) * size.x * 0.5, sin(angle) * size.y * 0.5) * radial
			offset = offset.rotated(yaw)
			var x := center_2d.x + offset.x
			var z := center_2d.y + offset.y
			perimeter.append(Vector3(x, height_at(x, z) + lift, z))
		for segment in segments:
			var next := (segment + 1) % segments
			for entry in [
				{"point": center, "uv": Vector2(0.5, 0.5), "alpha": 1.0},
				{"point": perimeter[segment], "uv": Vector2(0.5 + cos(TAU * segment / segments) * 0.5, 0.5 + sin(TAU * segment / segments) * 0.5), "alpha": 0.0 if feathered else 0.72},
				{"point": perimeter[next], "uv": Vector2(0.5 + cos(TAU * next / segments) * 0.5, 0.5 + sin(TAU * next / segments) * 0.5), "alpha": 0.0 if feathered else 0.72},
			]:
				var point: Vector3 = entry.point
				tool.set_normal(normal_at(point.x, point.z))
				tool.set_uv(entry.uv)
				tool.set_color(Color(1.0, 1.0, 1.0, entry.alpha))
				tool.add_vertex(point)
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = tool.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


# --- Sky ---------------------------------------------------------------------

static func _build_sky(built: Built) -> void:
	var root := built.root
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("03060f")
	sky_material.sky_horizon_color = Color("1d3242")
	sky_material.sky_curve = 0.09
	sky_material.ground_bottom_color = Color("04070a")
	sky_material.ground_horizon_color = Color("15222b")
	sky_material.sun_angle_max = 4.0
	sky_material.sun_curve = 0.08
	var panorama_sky := PanoramaSkyMaterial.new()
	panorama_sky.panorama = load("res://assets/environment/sky/kloppenheim_07_puresky_2k.hdr")
	panorama_sky.energy_multiplier = 0.085
	sky.sky_material = panorama_sky
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# The HDRI supplies cloud structure only. Its neutral overcast lighting would
	# flatten the biome palette, so the ravine keeps an authored cold ambient fill.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("52657b")
	environment.ambient_light_energy = 1.0
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	# Desktop-first contact shadowing and low volumetric haze give the authored
	# stone, timber, and moonbeams depth without baking lighting into the assets.
	environment.ssao_enabled = true
	environment.ssao_radius = 2.8
	environment.ssao_intensity = 2.1
	environment.ssao_power = 1.35
	environment.ssil_enabled = true
	environment.ssil_radius = 3.0
	environment.ssil_intensity = 0.85
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.012
	environment.volumetric_fog_albedo = Color("7187a1")
	environment.volumetric_fog_emission = Color("030712")
	environment.volumetric_fog_emission_energy = 0.2
	environment.volumetric_fog_length = 82.0
	environment.volumetric_fog_sky_affect = 0.18
	environment.fog_enabled = true
	environment.fog_light_color = Color("24394c")
	environment.fog_light_energy = 0.7
	environment.fog_density = 0.013
	environment.fog_sky_affect = 0.35
	environment.fog_height = 2.0
	environment.fog_height_density = 0.06
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.12
	environment.glow_hdr_threshold = 1.15
	world_environment.environment = environment
	root.add_child(world_environment)
	built.environment = environment
	built.sky_material = sky_material
	built.panorama_sky_material = panorama_sky

	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.rotation_degrees = Vector3(-38.0, 152.0, 0.0)
	moon.light_color = Color("a9c6e0")
	moon.light_energy = 0.9
	moon.light_indirect_energy = 1.4
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	root.add_child(moon)
	built.moon = moon

	# A physical world-space moon remains behind the crags, unlike a HUD image,
	# and gives every biome the same navigational landmark.
	var moon_gradient := Gradient.new()
	moon_gradient.offsets = PackedFloat32Array([0.0, 0.72, 0.84, 1.0])
	moon_gradient.colors = PackedColorArray([
		Color(4.2, 4.45, 5.0, 1.0),
		Color(2.1, 2.45, 3.1, 1.0),
		Color(0.62, 0.82, 1.3, 0.34),
		Color(0.2, 0.35, 0.7, 0.0),
	])
	var moon_texture := GradientTexture2D.new()
	moon_texture.width = 256
	moon_texture.height = 256
	moon_texture.fill = GradientTexture2D.FILL_RADIAL
	moon_texture.fill_from = Vector2(0.5, 0.5)
	moon_texture.fill_to = Vector2(1.0, 0.5)
	moon_texture.gradient = moon_gradient
	var moon_disc := Sprite3D.new()
	moon_disc.name = "MoonDisc"
	moon_disc.texture = moon_texture
	moon_disc.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	moon_disc.shaded = false
	moon_disc.no_depth_test = true
	moon_disc.pixel_size = 0.105
	moon_disc.modulate = Color.WHITE
	var moon_shader := Shader.new()
	moon_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler2D moon_texture : source_color, filter_linear;
void fragment() {
	vec4 moon = texture(moon_texture, UV);
	ALBEDO = moon.rgb;
	EMISSION = moon.rgb * 3.2;
	ALPHA = moon.a;
}
"""
	var moon_material := ShaderMaterial.new()
	moon_material.shader = moon_shader
	moon_material.set_shader_parameter("moon_texture", moon_texture)
	moon_disc.material_override = moon_material
	moon_disc.position = Vector3(-150.0, 145.0, -260.0)
	moon_disc.render_priority = -10
	root.add_child(moon_disc)
	# Soft sky fill from the opposite side so shadowed wood and cliffs keep their shape.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-52.0, -40.0, 0.0)
	fill.light_color = Color("5d7fa6")
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	root.add_child(fill)

	# A low winter sidelight exists only to rake across Widowpine's scanned
	# snow normals. It stays dark in the later biomes, whose hero lighting is
	# supplied by the shrine and abbey, and it is deliberately far weaker than
	# the moon so the opening remains a stealth space rather than a showroom.
	var ground_rake := DirectionalLight3D.new()
	ground_rake.name = "WidowpineGroundRake"
	ground_rake.rotation_degrees = Vector3(-17.0, 61.0, 0.0)
	ground_rake.light_color = Color("789dc6")
	ground_rake.light_energy = 0.0
	ground_rake.light_indirect_energy = 0.0
	ground_rake.light_specular = 1.15
	ground_rake.shadow_enabled = false
	root.add_child(ground_rake)

	# Stars: an inverted dome with hashed points.
	var stars := MeshInstance3D.new()
	stars.name = "Stars"
	var dome := SphereMesh.new()
	dome.radius = 900.0
	dome.height = 1800.0
	dome.flip_faces = true
	var star_shader := Shader.new()
	star_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 uv = UV * vec2(160.0, 80.0);
	vec2 cell = floor(uv);
	float h = hash(cell);
	vec2 offset = vec2(hash(cell + 1.3), hash(cell + 7.1));
	float d = length(fract(uv) - offset);
	float star = smoothstep(0.08, 0.0, d) * step(0.93, h);
	float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + h * 3.0) + h * 40.0);
	float horizon = smoothstep(0.42, 0.55, 1.0 - UV.y);
	ALBEDO = vec3(0.8, 0.86, 1.0) * star * twinkle * horizon * 1.6;
	ALPHA = star * horizon;
}
"""
	var star_material := ShaderMaterial.new()
	star_material.shader = star_shader
	dome.material = star_material
	stars.mesh = dome
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.visible = false # The CC0 HDRI already carries physically plausible stars.
	root.add_child(stars)

	# Aurora: a ribbon of light drifting above the ravine walls.
	var aurora := MeshInstance3D.new()
	aurora.name = "Aurora"
	var ribbon := PlaneMesh.new()
	ribbon.size = Vector2(420.0, 160.0)
	ribbon.subdivide_width = 24
	var aurora_shader := Shader.new()
	aurora_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
void fragment() {
	vec2 uv = UV;
	float band = sin(uv.x * 9.0 + TIME * 0.35) * 0.5 + sin(uv.x * 23.0 - TIME * 0.6) * 0.25;
	float curtain = smoothstep(0.55, 0.0, abs(uv.y - 0.5 - band * 0.12));
	float streaks = 0.55 + 0.45 * sin(uv.x * 140.0 + TIME * 1.7 + band * 6.0);
	float edge = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	vec3 green = vec3(0.25, 0.95, 0.55);
	vec3 violet = vec3(0.55, 0.3, 0.9);
	vec3 color = mix(green, violet, smoothstep(0.35, 0.75, uv.y + band * 0.2));
	ALBEDO = color * curtain * streaks * edge * 0.55;
	ALPHA = curtain * edge * 0.6;
}
"""
	var aurora_material := ShaderMaterial.new()
	aurora_material.shader = aurora_shader
	ribbon.material = aurora_material
	aurora.mesh = ribbon
	aurora.position = Vector3(-40.0, 120.0, -160.0)
	aurora.rotation_degrees = Vector3(62.0, 18.0, 0.0)
	aurora.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aurora.visible = false
	root.add_child(aurora)
	built.aurora = aurora


## Shift fog, sky light, and precipitation as the player crosses the three acts.
## Terrain and foliage already carry permanent biome silhouettes; this makes the
## boundary legible in motion without loading a new scene.
static func set_biome(built: Built, biome: String) -> void:
	if built == null or built.environment == null:
		return
	var ground_rake := built.root.get_node_or_null("WidowpineGroundRake") as DirectionalLight3D
	if ground_rake:
		ground_rake.light_energy = 0.0
	# Architecture stays in the continuous world: the abbey begins along the
	# Carrion ascent, and the mother bell is visible from the broken fold.
	# Local atmosphere must never remove landmarks or hide their colliders.
	if is_instance_valid(built.aurora):
		built.aurora.visible = false
	match biome:
		"carrion_cut":
			built.environment.fog_light_color = Color("252a36")
			built.environment.fog_density = 0.01
			built.environment.ambient_light_color = Color("5d6f89")
			built.environment.ambient_light_energy = 1.16
			built.environment.tonemap_exposure = 1.12
			built.environment.volumetric_fog_albedo = Color("4b566a")
			built.panorama_sky_material.energy_multiplier = 0.14
			built.sky_material.sky_horizon_color = Color("151c2a")
			built.sky_material.ground_horizon_color = Color("18151d")
			built.moon.light_color = Color("b8c8e0")
			built.moon.light_energy = 1.22
			var carrion_fill := built.root.get_node_or_null("SkyFill") as DirectionalLight3D
			if carrion_fill:
				carrion_fill.light_color = Color("657b9a")
				carrion_fill.light_energy = 0.42
			built.snow_material.albedo_color = Color(0.62, 0.66, 0.72, 0.76)
			built.snowfall.amount_ratio = 0.72
		"iron_crown":
			built.environment.ambient_light_color = Color("52657b")
			built.environment.tonemap_exposure = 1.1
			built.panorama_sky_material.energy_multiplier = 0.085
			built.environment.fog_light_color = Color("182333")
			built.environment.fog_density = 0.012
			built.environment.ambient_light_energy = 1.16
			built.environment.volumetric_fog_albedo = Color("617793")
			built.sky_material.sky_horizon_color = Color("101a29")
			built.sky_material.ground_horizon_color = Color("090d14")
			built.moon.light_color = Color("a9c4e3")
			built.moon.light_energy = 1.48
			var crown_fill := built.root.get_node_or_null("SkyFill") as DirectionalLight3D
			if crown_fill:
				crown_fill.light_color = Color("5d7fa6")
				crown_fill.light_energy = 0.52
			built.snow_material.albedo_color = Color(0.64, 0.72, 0.82, 0.76)
			built.snowfall.amount_ratio = 0.52
		_:
			built.environment.ambient_light_color = Color("52657b")
			built.environment.tonemap_exposure = 1.08
			built.panorama_sky_material.energy_multiplier = 0.06
			built.environment.fog_light_color = Color("24394c")
			built.environment.fog_density = 0.011
			built.environment.ambient_light_energy = 1.12
			built.environment.volumetric_fog_albedo = Color("7187a1")
			built.sky_material.sky_horizon_color = Color("1d3242")
			built.sky_material.ground_horizon_color = Color("15222b")
			built.moon.light_color = Color("a9c6e0")
			built.moon.light_energy = 1.18
			var widow_fill := built.root.get_node_or_null("SkyFill") as DirectionalLight3D
			if widow_fill:
				widow_fill.light_color = Color("5d7fa6")
				widow_fill.light_energy = 0.4
			if ground_rake:
				ground_rake.light_energy = 0.26
			built.snow_material.albedo_color = Color(0.86, 0.94, 1.0, 0.85)
			built.snowfall.amount_ratio = 1.0


# --- Helpers -----------------------------------------------------------------

## Kenney's foliage is a bright park green; the ravine wants deep, frost-dusted needles.
const TINTS := {
	"leafsDark": Color(0.18, 0.34, 0.32),
	"leafs": Color(0.2, 0.37, 0.33),
	"woodBarkDark": Color(0.19, 0.13, 0.1),
	"woodBark": Color(0.22, 0.15, 0.11),
	"Widowpine needles": Color(0.28, 0.39, 0.37),
	"Widowpine bark": Color(0.2, 0.145, 0.11),
}


static func _mesh_from(path: String) -> Mesh:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var scene: PackedScene = load(path)
	var node: Node = scene.instantiate()
	var mesh: Mesh = null
	var stack := [node]
	while stack and mesh == null:
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			mesh = current.mesh
		stack.append_array(current.get_children())
	node.free()
	if mesh:
		var uses_kenney_atlas := path.begins_with("res://assets/nature/") or path.begins_with("res://assets/castle/")
		var retouch := false
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			if material and (TINTS.has(material.resource_name) or (uses_kenney_atlas and material.albedo_texture)):
				retouch = true
		if retouch:
			mesh = mesh.duplicate()
			for i in mesh.get_surface_count():
				var material := mesh.surface_get_material(i)
				if material == null:
					continue
				var fixed: StandardMaterial3D = material.duplicate()
				if TINTS.has(material.resource_name):
					fixed.albedo_color = TINTS[material.resource_name]
				if uses_kenney_atlas and material.albedo_texture:
					# Kenney colour atlases are tiny swatches: filtering bleeds neighbours together.
					fixed.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mesh.surface_set_material(i, fixed)
	_mesh_cache[path] = mesh
	return mesh


static func _random(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Places a kit model on the terrain. Collision is a box fitted to the mesh bounds.
static func place(root: Node3D, path: String, at: Vector3, yaw: float, scale_value: float, collide := false, snap := true) -> Node3D:
	var mesh := _mesh_from(path)
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var aabb := mesh.get_aabb()
		var shape := BoxShape3D.new()
		shape.size = aabb.size * scale_value
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = (aabb.position + aabb.size * 0.5) * scale_value
		body.add_child(collider)
		holder = body
	else:
		holder = Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.scale = Vector3.ONE * scale_value
	holder.add_child(instance)
	holder.position = Vector3(at.x, height_at(at.x, at.z) + at.y if snap else at.y, at.z)
	holder.rotation.y = yaw
	root.add_child(holder)
	return holder


## Spots the scatter must keep clear: the trail, checkpoints, camps, and patrol routes.
const KEEP_CLEAR := [
	Vector2(0.0, 34.0), Vector2(0.0, 14.0), Vector2(0.0, -17.0), Vector2(0.0, -41.0), Vector2(0.0, -78.0),
	Vector2(0.0, 3.0), Vector2(-5.5, -12.0), Vector2(-6.0, -28.0), Vector2(0.0, -92.0), Vector2(0.0, -100.0),
]
## Wider clearings on the flank routes: the gully camp and Maren's cairns sit
## among rim boulders several metres across, so they need more room: (x, z, radius).
const FLANK_CLEARINGS := [
	Vector3(-15.0, -65.0, 11.0), Vector3(-17.2, -68.8, 8.0), Vector3(-16.0, 4.0, 8.0), Vector3(15.0, -34.0, 8.0),
]


static func _scatter(root: Node3D, path: String, count: int, rng: RandomNumberGenerator, x_ranges: Array, z_range: Vector2, scale_range: Vector2, sink := 0.0, max_slope := 9.0) -> MultiMeshInstance3D:
	var mesh := _mesh_from(path)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var transforms: Array[Transform3D] = []
	var attempts := 0
	while transforms.size() < count and attempts < count * 6:
		attempts += 1
		var side: Vector2 = x_ranges[rng.randi_range(0, x_ranges.size() - 1)]
		var x := rng.randf_range(side.x, side.y)
		var z := rng.randf_range(z_range.x, z_range.y)
		if slope_at(x, z) > max_slope:
			continue
		var clear := true
		for spot in KEEP_CLEAR:
			if Vector2(x, z).distance_to(spot) < 6.0:
				clear = false
				break
		for clearing in FLANK_CLEARINGS:
			if Vector2(x, z).distance_to(Vector2(clearing.x, clearing.y)) < clearing.z:
				clear = false
				break
		if not clear:
			continue
		var s := rng.randf_range(scale_range.x, scale_range.y)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		transforms.append(Transform3D(basis, Vector3(x, height_at(x, z) - sink * s, z)))
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = path.get_file().get_basename()
	instance.multimesh = multimesh
	root.add_child(instance)
	return instance


static func _lantern(built: Built, at: Vector3, lit := true) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "Lantern"
	var y := height_at(at.x, at.z)
	holder.position = Vector3(at.x, y, at.z)
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 2.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("3a2418")
	wood.roughness = 0.9
	pole_mesh.material = wood
	pole.mesh = pole_mesh
	pole.position.y = 1.2
	holder.add_child(pole)
	var cage := MeshInstance3D.new()
	var cage_mesh := BoxMesh.new()
	cage_mesh.size = Vector3(0.3, 0.42, 0.3)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("ffb35c")
	glass.emission_enabled = true
	glass.emission = Color("ff8a2e")
	glass.emission_energy_multiplier = 2.6 if lit else 0.0
	cage_mesh.material = glass
	cage.mesh = cage_mesh
	cage.position = Vector3(0.0, 2.35, 0.32)
	holder.add_child(cage)
	var light := OmniLight3D.new()
	light.light_color = Color("ff9a3c")
	light.light_energy = 3.2 if lit else 0.0
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	light.position = cage.position
	holder.add_child(light)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CylinderShape3D.new()
	shape.radius = 0.12
	shape.height = 2.4
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 1.2
	body.add_child(collider)
	holder.add_child(body)
	built.root.add_child(holder)
	var entry := {"node": holder, "light": light, "glass": glass, "position": holder.position + cage.position, "lit": lit}
	built.lanterns.append(entry)
	return entry


## Light volume for a Blender-authored lantern or shrine flame. The visible
## housing lives in the imported hero asset, so this does not duplicate it with
## the old procedural pole and cage.
static func _hero_light(built: Built, at: Vector3, color: Color, energy: float, light_range: float) -> void:
	var light := OmniLight3D.new()
	light.name = "HeroEnvironmentLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.5
	light.position = Vector3(at.x, height_at(at.x, at.z) + at.y, at.z)
	built.root.add_child(light)
	built.lanterns.append({"node": light, "light": light, "glass": null, "position": light.position, "lit": true, "fire": true})


static func _campfire(built: Built, at: Vector3, dress_with_kit := true) -> void:
	var y := height_at(at.x, at.z)
	if dress_with_kit:
		place(built.root, NATURE % "campfire_stones", Vector3(at.x, 0.0, at.z), 0.0, 2.2)
		place(built.root, NATURE % "campfire_logs", Vector3(at.x, 0.0, at.z), 0.6, 2.2)
	var light := OmniLight3D.new()
	light.light_color = Color("ff7a2a")
	light.light_energy = 5.0
	light.omni_range = 13.0
	light.omni_attenuation = 1.3
	light.position = Vector3(at.x, y + 1.0, at.z)
	built.root.add_child(light)
	built.campfires.append(light)
	var embers := GPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 1.6
	embers.position = Vector3(at.x, y + 0.4, at.z)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 18.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.6
	process.gravity = Vector3(0.3, 0.4, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.0
	embers.process_material = process
	var spark := QuadMesh.new()
	spark.size = Vector2(0.07, 0.07)
	var spark_material := StandardMaterial3D.new()
	spark_material.albedo_color = Color(1.0, 0.55, 0.2)
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.45, 0.1)
	spark_material.emission_energy_multiplier = 3.0
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark.material = spark_material
	embers.draw_pass_1 = spark
	built.root.add_child(embers)
	built.lanterns.append({"node": light, "light": light, "glass": null, "position": light.position, "lit": true, "fire": true})


# --- Zones -------------------------------------------------------------------

static func _build_forest(root: Node3D) -> void:
	var rng := _random(11)
	var flanks := [Vector2(-21.5, -12.0), Vector2(12.0, 21.5)]
	var widowpine := Vector2(-14.0, Z_MAX - 4.0)
	var carrion := Vector2(-76.0, -17.0)
	var crown := Vector2(Z_MIN + 4.0, -79.0)
	# WIDOWPINE: original Blender trees form the tall silhouette. Small CC0
	# plants remain supporting debris, never the hero vegetation.
	_scatter(root, VEGETATION % "widowpine_tree_a", 22, rng, flanks, widowpine, Vector2(0.7, 0.94), 0.08, 0.85)
	_scatter(root, VEGETATION % "widowpine_tree_b", 20, rng, flanks, widowpine, Vector2(0.76, 1.02), 0.08, 0.85)
	_scatter(root, VEGETATION % "widowpine_tree_c", 16, rng, flanks, widowpine, Vector2(0.64, 0.88), 0.08, 0.85)
	_scatter(root, NATURE % "tree_pineSmallB", 6, rng, flanks, widowpine, Vector2(1.4, 2.1), 0.08, 1.0)
	# THE CARRION CUT: sparse wind-torn trees, exposed trunks, red stone.
	_scatter(root, VEGETATION % "carrion_dead_pine", 14, rng, flanks, carrion, Vector2(0.68, 0.98), 0.12, 1.1)
	_scatter(root, NATURE % "tree_pineGroundA", 5, rng, flanks, carrion, Vector2(1.4, 2.2), 0.1, 1.2)
	_scatter(root, NATURE % "stump_oldTall", 10, rng, flanks, carrion, Vector2(1.4, 2.4), 0.08, 1.3)
	_scatter(root, CASTLE % "tree-trunk", 6, rng, flanks, carrion, Vector2(1.4, 2.5), 0.08, 1.3)
	# THE IRON CROWN: ash and siege wreckage have killed almost everything.
	_scatter(root, NATURE % "stump_old", 18, rng, flanks, crown, Vector2(2.4, 4.2), 0.12, 1.5)
	_scatter(root, RAVINE_ROCK % "ravine_cliff_b", 22, rng, flanks, crown, Vector2(1.45, 2.5), 0.1, 1.8)
	var rims := [Vector2(-20.0, -11.5), Vector2(11.5, 20.0)]
	var whole := Vector2(Z_MIN + 4, Z_MAX - 4)
	_scatter(root, RAVINE_ROCK % "ravine_boulder_a", 28, rng, rims, whole, Vector2(1.35, 2.5), 0.08, 1.2)
	_scatter(root, RAVINE_ROCK % "ravine_boulder_b", 26, rng, rims, whole, Vector2(1.3, 2.35), 0.08, 1.2)
	_scatter(root, RAVINE_ROCK % "ravine_boulder_c", 24, rng, rims, whole, Vector2(1.25, 2.2), 0.08, 1.2)
	var verges := [Vector2(-11.0, -4.5), Vector2(4.5, 11.0)]
	_scatter(root, RAVINE_ROCK % "ravine_boulder_b", 34, rng, verges, whole, Vector2(0.42, 0.86), 0.08, 2.0)
	_scatter(root, RAVINE_ROCK % "ravine_boulder_c", 44, rng, verges, whole, Vector2(0.38, 0.8), 0.08, 2.0)
	_scatter(root, NATURE % "plant_bush", 14, rng, [Vector2(-12.5, -4.5), Vector2(4.5, 12.5)], widowpine, Vector2(0.8, 1.45), 0.1, 2.0)
	var cliffs := [Vector2(-29.0, -21.0), Vector2(21.0, 29.0)]
	_scatter(root, RAVINE_ROCK % "ravine_cliff_a", 28, rng, cliffs, whole, Vector2(2.7, 4.8), 0.18, 99.0)
	_scatter(root, RAVINE_ROCK % "ravine_cliff_b", 26, rng, cliffs, whole, Vector2(2.5, 4.5), 0.18, 99.0)
	_scatter(root, RAVINE_ROCK % "ravine_cliff_c", 26, rng, cliffs, whole, Vector2(2.8, 4.9), 0.18, 99.0)
	_build_skyline(root, rng)


## A deterministic many-sided crag. Five irregular rings avoid the giant
## triangular-prism silhouette of the original placeholder skyline.
static func _crag_mesh(seed_value: int, width: float, height: float, depth: float) -> ArrayMesh:
	var rng := _random(seed_value)
	var segments := 12
	var ring_scales := [1.0, 0.88, 0.66, 0.43, 0.22]
	var ring_heights := [0.0, 0.23, 0.48, 0.72, 0.88]
	var rings: Array = []
	for ring_index in ring_scales.size():
		var ring: Array[Vector3] = []
		for segment in segments:
			var angle := TAU * segment / segments
			var radial := rng.randf_range(0.8, 1.16)
			var shear: float = (float(ring_heights[ring_index]) - 0.35) * rng.randf_range(-0.16, 0.16)
			ring.append(Vector3(
				cos(angle) * width * 0.5 * ring_scales[ring_index] * radial + width * shear,
				height * ring_heights[ring_index] + rng.randf_range(-0.025, 0.025) * height,
				sin(angle) * depth * 0.5 * ring_scales[ring_index] * radial
			))
		rings.append(ring)
	var tip := Vector3(rng.randf_range(-0.07, 0.07) * width, height, rng.randf_range(-0.06, 0.06) * depth)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_index in range(rings.size() - 1):
		for segment in segments:
			var next := (segment + 1) % segments
			var a: Vector3 = rings[ring_index][segment]
			var b: Vector3 = rings[ring_index][next]
			var c: Vector3 = rings[ring_index + 1][segment]
			var d: Vector3 = rings[ring_index + 1][next]
			for vertex in [a, b, c, b, d, c]:
				tool.add_vertex(vertex)
	var top_ring: Array = rings[-1]
	for segment in segments:
		var next := (segment + 1) % segments
		for vertex in [top_ring[segment], top_ring[next], tip]:
			tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()


## Distant peaks beyond the playable flanks so the ravine walls meet a mountain, not empty sky.
static func _build_skyline(root: Node3D, rng: RandomNumberGenerator) -> void:
	var peak := StandardMaterial3D.new()
	peak.albedo_color = Color("121c29")
	peak.roughness = 1.0
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color("52667d")
	cap.roughness = 0.9
	var crag_seed := 700
	for side in [-1.0, 1.0]:
		for i in 9:
			var z := Z_MIN + 6.0 + i * 18.0 + rng.randf_range(-5.0, 5.0)
			var x: float = side * rng.randf_range(44.0, 62.0)
			var width := rng.randf_range(34.0, 52.0)
			var height := rng.randf_range(38.0, 64.0)
			var depth := rng.randf_range(30.0, 46.0)
			var mountain := MeshInstance3D.new()
			mountain.mesh = _crag_mesh(crag_seed, width, height, depth)
			mountain.material_override = peak
			mountain.position = Vector3(x, 4.0, z)
			mountain.rotation.y = rng.randf() * TAU
			mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mountain)
			var snow_cap := MeshInstance3D.new()
			snow_cap.mesh = _crag_mesh(crag_seed + 1, width * 0.53, height * 0.38, depth * 0.53)
			snow_cap.material_override = cap
			snow_cap.position = Vector3(x, 4.0 + height * 0.62, z)
			snow_cap.rotation.y = mountain.rotation.y
			snow_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(snow_cap)
			crag_seed += 2
	for i in 7:
		var x: float = -54.0 + i * 18.0
		var width := rng.randf_range(36.0, 50.0)
		var height := rng.randf_range(44.0, 70.0)
		var depth := 40.0
		var z := Z_MIN - 40.0 - rng.randf_range(0.0, 20.0)
		var mountain := MeshInstance3D.new()
		mountain.mesh = _crag_mesh(crag_seed, width, height, depth)
		mountain.material_override = peak
		mountain.position = Vector3(x, 6.0, z)
		mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mountain)
		var snow_cap := MeshInstance3D.new()
		snow_cap.mesh = _crag_mesh(crag_seed + 1, width * 0.52, height * 0.38, depth * 0.52)
		snow_cap.material_override = cap
		snow_cap.position = Vector3(x, 6.0 + height * 0.62, z)
		snow_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(snow_cap)
		crag_seed += 2


## A top-down shading of the ravine for the minimap: bright floor, dark walls.
static func minimap_image() -> Image:
	var width := X_MAX - X_MIN + 1
	var depth := Z_MAX - Z_MIN + 1
	var image := Image.create(width, depth, false, Image.FORMAT_RGBA8)
	for zi in depth:
		for xi in width:
			var x := float(X_MIN + xi)
			var z := float(Z_MIN + zi)
			var steep := clampf(slope_at(x, z) / 1.3, 0.0, 1.0)
			var snow := Color(0.62, 0.7, 0.8)
			var rock := Color(0.1, 0.13, 0.17)
			match Story.biome_for_z(z):
				"carrion_cut":
					snow = Color(0.48, 0.38, 0.35)
					rock = Color(0.2, 0.08, 0.07)
				"iron_crown":
					snow = Color(0.3, 0.27, 0.28)
					rock = Color(0.055, 0.06, 0.075)
			image.set_pixel(xi, zi, snow.lerp(rock, steep))
	return image


static func _build_trailhead(built: Built) -> void:
	var root := built.root
	place(root, NATURE % "sign", Vector3(-3.6, 0.0, 31.0), 0.5, 2.6, true)
	place(root, NATURE % "log_stack", Vector3(5.5, 0.0, 26.0), 0.2, 2.8, true)
	place(root, NATURE % "stump_old", Vector3(-6.0, 0.0, 20.0), 0.0, 3.0, true)
	place(root, NATURE % "log_large", Vector3(4.0, 0.0, 16.5), 1.2, 3.0, true)
	place(root, RAVINE_ROCK % "ravine_boulder_a", Vector3(-7.5, 0.0, 14.0), 0.9, 1.55, true)
	_lantern(built, Vector3(-2.2, 0.0, 33.0))


static func _build_homestead(built: Built) -> void:
	var root := built.root
	# Custom Blender hero environment. The fold begins at world z=11 and runs
	# uphill into negative z; the old low-poly tent village is intentionally gone.
	var fold_scene := load(WIDOWPINE_FOLD) as PackedScene
	var fold := fold_scene.instantiate()
	fold.name = "WidowpineBrokenFold"
	fold.position = Vector3(0.0, height_at(0.0, 11.0) - 0.15, 11.0)
	root.add_child(fold)
	built.biome_roots["whitewood"] = fold
	_campfire(built, Vector3(0.0, 0.0, -0.4), false)
	# Runtime light volumes line up with the emissive Blender lantern housings.
	for at in [Vector3(-7.8, 2.25, 5.7), Vector3(7.8, 2.25, 5.0), Vector3(-7.75, 2.25, -7.0)]:
		_hero_light(built, at, Color("ff9a43"), 2.0, 7.5)


static func _build_shrine(built: Built) -> void:
	var root := built.root
	var origin := BELL_ORIGIN
	var shrine_scene := load(CARRION_BELL_SHRINE) as PackedScene
	var shrine := shrine_scene.instantiate()
	shrine.name = "CarrionCutMotherBellShrine"
	shrine.position = Vector3(origin.x, height_at(origin.x, origin.z) - 0.1, origin.z)
	root.add_child(shrine)
	built.biome_roots["carrion_cut"] = shrine
	var bell := shrine.find_child("MotherBell", true, false) as MeshInstance3D
	var source_material := bell.get_active_material(0) as StandardMaterial3D
	built.bell_material = source_material.duplicate() if source_material else StandardMaterial3D.new()
	built.bell_material.emission_enabled = true
	built.bell_material.emission = Color("7a3410")
	built.bell_material.emission_energy_multiplier = 0.7
	bell.material_override = built.bell_material
	var bell_light := OmniLight3D.new()
	bell_light.position = Vector3(origin.x, height_at(origin.x, origin.z) + 5.7, origin.z + 0.8)
	bell_light.light_color = Color("ff9341")
	bell_light.light_energy = 2.8
	bell_light.omni_range = 10.5
	root.add_child(bell_light)
	built.lanterns.append({"node": bell_light, "light": bell_light, "glass": null, "position": bell_light.position, "lit": true, "fire": true})
	for at in [Vector3(origin.x - 5.7, 2.25, origin.z + 5.8), Vector3(origin.x + 5.8, 2.25, origin.z + 4.8), Vector3(origin.x - 6.2, 3.7, origin.z - 6.7), Vector3(origin.x + 6.3, 3.7, origin.z - 7.0)]:
		_hero_light(built, at, Color("ff7b35"), 2.8, 10.0)


static func _build_ascent(built: Built) -> void:
	var root := built.root
	place(root, CASTLE % "siege-catapult-demolished", Vector3(-5.0, 0.0, -48.0), 0.6, 3.0, true)
	place(root, RAVINE_ROCK % "ravine_boulder_a", Vector3(6.0, 0.0, -45.0), 0.0, 1.75, true)
	place(root, RAVINE_ROCK % "ravine_boulder_c", Vector3(-6.8, 0.0, -57.0), 1.4, 1.85, true)
	place(root, RAVINE_ROCK % "ravine_cliff_c", Vector3(4.0, 0.0, -62.0), 0.3, 1.45, true)
	place(root, RAVINE_ROCK % "ravine_boulder_b", Vector3(-1.5, 0.0, -66.5), 2.0, 1.0, true)
	place(root, NATURE % "log_stack", Vector3(7.0, 0.0, -70.0), 0.8, 2.8, true)
	place(root, RAVINE_ROCK % "ravine_boulder_b", Vector3(-7.0, 0.0, -73.0), 0.2, 1.65, true)
	place(root, CASTLE % "tree-trunk", Vector3(2.5, 0.0, -53.0), 0.0, 3.0, true)
	_lantern(built, Vector3(-3.0, 0.0, -44.0))
	_lantern(built, Vector3(5.5, 0.0, -66.0))


## Restrained environmental gore: three old kill-sites rather than constant
## splatter. Dark stains and scattered bones turn the middle biome into a grave
## without overwhelming its stealth readability.
static func _build_carrion_remains(root: Node3D) -> void:
	var dried := StandardMaterial3D.new()
	dried.albedo_color = Color(0.24, 0.015, 0.012, 0.74)
	dried.roughness = 0.98
	dried.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dried.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color("b8ad91")
	bone.roughness = 0.9
	var sites := [
		Vector3(7.4, 0.0, -20.0),
		Vector3(-3.8, 0.0, -47.0),
		Vector3(6.2, 0.0, -72.5),
	]
	for site_index in sites.size():
		_kill_site(root, sites[site_index], site_index, dried, bone)


## One old kill-site: a dark stain, scattered bones, and a pair of horns.
static func _kill_site(root: Node3D, site: Vector3, site_index: int, dried: StandardMaterial3D, bone: StandardMaterial3D) -> void:
	var y := height_at(site.x, site.z)
	var stain := MeshInstance3D.new()
	stain.name = "OldBlood_%02d" % site_index
	var stain_mesh := PlaneMesh.new()
	stain_mesh.size = Vector2(1.8 + site_index * 0.35, 1.05 + site_index * 0.22)
	stain_mesh.material = dried
	stain.mesh = stain_mesh
	stain.position = Vector3(site.x, y + 0.035, site.z)
	stain.rotation.y = site_index * 1.7
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(stain)
	for i in 4:
		var shard := MeshInstance3D.new()
		var shard_mesh := CylinderMesh.new()
		shard_mesh.top_radius = 0.025
		shard_mesh.bottom_radius = 0.035
		shard_mesh.height = 0.45 + 0.12 * i
		shard_mesh.radial_segments = 6
		shard_mesh.material = bone
		shard.mesh = shard_mesh
		shard.position = Vector3(site.x - 0.5 + i * 0.28, y + 0.12, site.z + sin(i * 1.9) * 0.3)
		shard.rotation = Vector3(PI * 0.5, i * 0.8, 0.25 * i)
		root.add_child(shard)
	for side in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var horn_mesh := PrismMesh.new()
		horn_mesh.size = Vector3(0.12, 0.5, 0.12)
		horn_mesh.material = bone
		horn.mesh = horn_mesh
		horn.position = Vector3(site.x + side * 0.42, y + 0.15, site.z - 0.25)
		horn.rotation = Vector3(0.35, site_index + side, side * 0.8)
		root.add_child(horn)


## The flank routes. Each shoulder already carries pines and boulders; the
## gully gets a kill-site camp and a little extra cover so it reads as a route
## rather than open ground. Every route ends at one of Maren's cairns.
static func _build_flank_routes(built: Built) -> void:
	var root := built.root
	_campfire(built, FLANK_CAMP)
	place(root, NATURE % "log_large", FLANK_CAMP + Vector3(1.9, 0.0, 1.3), 0.4, 2.4, true)
	var dried := StandardMaterial3D.new()
	dried.albedo_color = Color(0.24, 0.015, 0.012, 0.74)
	dried.roughness = 0.98
	dried.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dried.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color("b8ad91")
	bone.roughness = 0.9
	_kill_site(root, FLANK_CAMP + Vector3(-1.8, 0.0, 2.4), 3, dried, bone)
	for spec in [
		[Vector3(-12.6, 0.0, -57.5), "ravine_boulder_b", 0.75, 0.4],
		[Vector3(-17.4, 0.0, -61.0), "ravine_boulder_c", 0.7, 2.2],
		[Vector3(-13.2, 0.0, -69.5), "ravine_boulder_b", 0.8, 1.1],
	]:
		place(root, RAVINE_ROCK % spec[1], spec[0], spec[3], spec[2], true)
	for index in CAIRNS.size():
		built.cairns.append(_cairn(built, CAIRNS[index], index))


## A waist-high stack of ravine stones with a cold wisp at its crown. Kindled,
## the wisp turns to an ember. Its faint light never lights the Herdkeeper up.
static func _cairn(built: Built, at: Vector3, index: int) -> Dictionary:
	var holder := StaticBody3D.new()
	holder.name = "MarensCairn_%d" % index
	holder.collision_layer = 1
	holder.position = Vector3(at.x, height_at(at.x, at.z) - 0.05, at.z)
	built.root.add_child(holder)
	var stone_mesh := _mesh_from(RAVINE_ROCK % "ravine_boulder_b")
	var stone_height := stone_mesh.get_aabb().size.y
	var y := 0.0
	var rng := _random(300 + index)
	for scale_value in [0.42, 0.34, 0.27, 0.2, 0.14]:
		var stone := MeshInstance3D.new()
		stone.mesh = stone_mesh
		stone.scale = Vector3.ONE * scale_value
		stone.position = Vector3(rng.randf_range(-0.05, 0.05), y - stone_mesh.get_aabb().position.y * scale_value, rng.randf_range(-0.05, 0.05))
		stone.rotation.y = rng.randf() * TAU
		holder.add_child(stone)
		y += stone_height * scale_value * 0.82
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, maxf(y, 0.6), 0.9)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.size.y * 0.5
	holder.add_child(collider)
	var ember_material := StandardMaterial3D.new()
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.albedo_color = Color("bcd8ff")
	ember_material.emission_enabled = true
	ember_material.emission = Color("9fc7ff")
	ember_material.emission_energy_multiplier = 1.4
	var ember := MeshInstance3D.new()
	ember.name = "Wisp"
	var ember_mesh := PrismMesh.new()
	ember_mesh.size = Vector3(0.12, 0.16, 0.12)
	ember_mesh.material = ember_material
	ember.mesh = ember_mesh
	ember.position.y = y + 0.18
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ember)
	var light := OmniLight3D.new()
	light.light_color = Color("9fc7ff")
	light.light_energy = 0.7
	light.omni_range = 4.0
	light.position.y = y + 0.3
	holder.add_child(light)
	return {"node": holder, "position": holder.position + Vector3(0.0, y, 0.0), "ember": ember, "material": ember_material, "light": light, "index": index, "kindled": false}


## Turn a cairn's cold wisp into a warm ember.
static func kindle_cairn(cairn: Dictionary) -> void:
	cairn.kindled = true
	var material: StandardMaterial3D = cairn.material
	material.albedo_color = Color("ffc36b")
	material.emission = Color("ff9a3c")
	material.emission_energy_multiplier = 2.6
	var light: OmniLight3D = cairn.light
	light.light_color = Color("ffb066")
	light.light_energy = 1.3


static func _build_fortress(built: Built) -> void:
	var root := built.root
	var z := GATE_Z

	# The custom blockout replaces the symmetric kit fortress. In Blender its
	# lower reveal begins at z=0 and the Iron Throat sits 52 metres up-route, so
	# placing the root at world z=-40 aligns the portcullis with GATE_Z.
	var abbey_scene := load(IRON_CROWN_ABBEY) as PackedScene
	var abbey := abbey_scene.instantiate()
	abbey.name = "IronCrownBellAbbey"
	var route_origin_z := GATE_Z + 52.0
	var route_origin_y := height_at(0.0, route_origin_z) - 0.4
	abbey.position = Vector3(0.0, route_origin_y, route_origin_z)
	root.add_child(abbey)
	built.biome_roots["iron_crown"] = abbey

	# A focused cold wash gives the ancient pale facade the same moonlit visual
	# authority as the concept frame without brightening the whole ravine.
	var abbey_wash := SpotLight3D.new()
	abbey_wash.name = "IronCrownMoonWash"
	abbey_wash.position = Vector3(-27.0, 35.0, -8.0)
	abbey_wash.light_color = Color("9bbce0")
	abbey_wash.light_energy = 12.5
	abbey_wash.spot_range = 82.0
	abbey_wash.spot_angle = 39.0
	abbey_wash.spot_attenuation = 0.82
	abbey_wash.shadow_enabled = true
	abbey.add_child(abbey_wash)
	abbey_wash.look_at(abbey.to_global(Vector3(0.0, 15.0, -52.0)), Vector3.UP)

	# The global moon comes from behind the facade at this bend in the ravine.
	# A weak front-facing bounce preserves the limestone courses and arches in
	# the playable approach without spilling into Widowpine or the Carrion Cut.
	var facade_fill := DirectionalLight3D.new()
	facade_fill.name = "IronCrownFacadeBounce"
	facade_fill.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
	facade_fill.light_color = Color("809bbd")
	facade_fill.light_energy = 0.9
	facade_fill.light_indirect_energy = 0.0
	facade_fill.light_specular = 0.65
	facade_fill.shadow_enabled = false
	abbey.add_child(facade_fill)

	# The recessed glow is deliberately small: it marks the threshold as a
	# destination while keeping Varkas' courtyard beyond it ominously dark.
	var throat_glow := OmniLight3D.new()
	throat_glow.name = "IronThroatEmber"
	throat_glow.position = Vector3(0.0, 11.5, -49.2)
	throat_glow.light_color = Color("ff7b35")
	throat_glow.light_energy = 4.4
	throat_glow.omni_range = 13.0
	throat_glow.omni_attenuation = 1.55
	abbey.add_child(throat_glow)

	# A narrow cold shaft crosses the boss court from the broken nave. Varkas'
	# phase light then reads as an underglow against this rim instead of flattening
	# his entire body into red.
	var court_wash := SpotLight3D.new()
	court_wash.name = "VarkasCourtMoonShaft"
	court_wash.position = Vector3(-12.0, 36.0, -96.0)
	court_wash.light_color = Color("90add2")
	court_wash.light_energy = 4.8
	court_wash.spot_range = 56.0
	court_wash.spot_angle = 27.0
	court_wash.spot_attenuation = 0.9
	court_wash.shadow_enabled = true
	root.add_child(court_wash)
	court_wash.look_at(Vector3(0.0, height_at(0.0, COURTYARD_Z - 4.5) + 1.5, COURTYARD_Z - 4.5), Vector3.UP)

	# Blender exports the bars as separate pieces so they remain editable. Gather
	# them under one runtime pivot, preserving the existing gate tween contract.
	var gate_holder := Node3D.new()
	gate_holder.name = "Gate"
	gate_holder.position = Vector3(0.0, 11.2, -52.0)
	abbey.add_child(gate_holder)
	for piece in abbey.find_children("IronThroat_*", "Node3D", true, false):
		if piece.name.begins_with("IronThroat_vertical_") or piece.name.begins_with("IronThroat_horizontal_") or piece.name.begins_with("IronThroat_spike_"):
			piece.reparent(gate_holder, true)
	built.gate = gate_holder

	built.gate_block = StaticBody3D.new()
	built.gate_block.name = "GateBlock"
	built.gate_block.collision_layer = 1
	var block := CollisionShape3D.new()
	var block_shape := BoxShape3D.new()
	block_shape.size = Vector3(7.8, 10.0, 1.2)
	block.shape = block_shape
	block.position.y = 5.0
	built.gate_block.add_child(block)
	built.gate_block.position = Vector3(0.0, route_origin_y + 11.2, z)
	root.add_child(built.gate_block)

	# Sparse warm route lights are separate from the imported emissive lantern
	# housings so their gameplay visibility can still be managed at runtime.
	for x in [-8.0, 8.0]:
		var window_light := OmniLight3D.new()
		window_light.position = Vector3(x, route_origin_y + 14.8, z + 2.4)
		window_light.light_color = Color("ff7a2e")
		window_light.light_energy = 2.4
		window_light.omni_range = 11.0
		root.add_child(window_light)
		built.lanterns.append({"node": window_light, "light": window_light, "glass": null, "position": window_light.position, "lit": true, "fire": true})
	# The imported abbey already surrounds the boss court. Keep its center free
	# for Varkas' charges instead of filling it with the old siege-tower kit.
	_campfire(built, Vector3(-5.8, 0.0, COURTYARD_Z - 1.0), false)
	_build_varkas_environment(built)


## Eight memorial niches answer the bells the player carried uphill. Bellthorn
## leaves turn their light into motion during Varkas' phase breaks.
static func _build_varkas_environment(built: Built) -> void:
	var root := built.root
	var niche_material := StandardMaterial3D.new()
	niche_material.albedo_color = Color("261513")
	niche_material.metallic = 0.55
	niche_material.roughness = 0.5
	niche_material.emission_enabled = true
	niche_material.emission = Color("7b170e")
	niche_material.emission_energy_multiplier = 0.45
	for i in 8:
		var x := -10.5 + i * 3.0
		var z := COURTYARD_Z - 10.5
		var y := height_at(x, z) + 4.2
		var niche := MeshInstance3D.new()
		niche.name = "RecoveredName_%02d" % (i + 1)
		var niche_mesh := CylinderMesh.new()
		niche_mesh.top_radius = 0.18
		niche_mesh.bottom_radius = 0.34
		niche_mesh.height = 0.72
		niche_mesh.radial_segments = 10
		niche_mesh.material = niche_material
		niche.mesh = niche_mesh
		niche.position = Vector3(x, y, z + 0.35)
		niche.rotation_degrees.x = 90.0
		root.add_child(niche)
		var answer := OmniLight3D.new()
		answer.name = "RecoveredNameLight_%02d" % (i + 1)
		answer.position = niche.position + Vector3(0.0, 0.0, 0.5)
		answer.light_color = Color("dc3928")
		answer.light_energy = 0.0
		answer.omni_range = 6.0
		answer.omni_attenuation = 1.8
		root.add_child(answer)
		built.name_lights.append(answer)

	var leaves := GPUParticles3D.new()
	leaves.name = "VarkasBellthornStorm"
	leaves.amount = 720
	leaves.amount_ratio = 0.0
	leaves.lifetime = 6.5
	leaves.randomness = 0.7
	leaves.position = Vector3(0.0, height_at(0.0, COURTYARD_Z) + 8.0, COURTYARD_Z - 2.0)
	var leaf_motion := ParticleProcessMaterial.new()
	leaf_motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	leaf_motion.emission_box_extents = Vector3(16.0, 7.0, 16.0)
	leaf_motion.direction = Vector3(-0.8, 0.25, 0.12)
	leaf_motion.spread = 52.0
	leaf_motion.initial_velocity_min = 2.2
	leaf_motion.initial_velocity_max = 6.8
	leaf_motion.gravity = Vector3(1.0, -1.1, 0.3)
	leaf_motion.angular_velocity_min = -420.0
	leaf_motion.angular_velocity_max = 420.0
	leaf_motion.turbulence_enabled = true
	leaf_motion.turbulence_noise_strength = 3.8
	leaf_motion.turbulence_noise_scale = 2.6
	leaves.process_material = leaf_motion
	var leaf_tool := SurfaceTool.new()
	leaf_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [
		Vector3(-0.085, 0.0, 0.0), Vector3(0.0, 0.04, 0.0), Vector3(0.085, 0.0, 0.0),
		Vector3(-0.085, 0.0, 0.0), Vector3(0.085, 0.0, 0.0), Vector3(0.0, -0.04, 0.0),
	]:
		leaf_tool.set_normal(Vector3(0.0, 0.0, 1.0))
		leaf_tool.add_vertex(vertex)
	var leaf_mesh := leaf_tool.commit()
	var leaf_material := StandardMaterial3D.new()
	leaf_material.albedo_color = Color(0.48, 0.008, 0.012, 0.92)
	leaf_material.emission_enabled = true
	leaf_material.emission = Color("5d0709")
	leaf_material.emission_energy_multiplier = 0.42
	leaf_material.roughness = 0.88
	leaf_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	leaf_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	leaf_mesh.surface_set_material(0, leaf_material)
	leaves.draw_pass_1 = leaf_mesh
	root.add_child(leaves)
	built.bellthorn_storm = leaves


## phase 0/1: dormant, 2: first four names answer, 3: all eight answer,
## 4: Varkas is dead and the recovered names turn from blood-red to bell-gold.
static func set_varkas_phase(built: Built, phase: int) -> void:
	if built == null:
		return
	if is_instance_valid(built.bellthorn_storm):
		built.bellthorn_storm.amount_ratio = 0.0 if phase <= 1 else (0.42 if phase == 2 else (1.0 if phase == 3 else 0.12))
	for i in built.name_lights.size():
		var light := built.name_lights[i]
		if not is_instance_valid(light):
			continue
		if phase >= 4:
			light.light_color = Color("ffb65a")
			light.light_energy = 2.4
		elif phase >= 3 or (phase == 2 and i < 4):
			light.light_color = Color("e33222")
			light.light_energy = 1.8 if phase >= 3 else 1.2
		else:
			light.light_energy = 0.0


static func _build_snowfall(built: Built) -> GPUParticles3D:
	var root := built.root
	var snow := GPUParticles3D.new()
	snow.name = "Snowfall"
	snow.amount = 1400
	snow.lifetime = 9.0
	snow.preprocess = 9.0
	snow.position = Vector3(0.0, 12.0, 0.0)
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(30.0, 8.0, 34.0)
	process_material.direction = Vector3(0.3, -1.0, 0.1)
	process_material.spread = 14.0
	process_material.initial_velocity_min = 1.4
	process_material.initial_velocity_max = 3.0
	process_material.gravity = Vector3(0.25, -0.5, 0.05)
	process_material.turbulence_enabled = true
	process_material.turbulence_noise_strength = 0.6
	process_material.turbulence_noise_scale = 4.0
	process_material.scale_min = 0.45
	process_material.scale_max = 1.1
	snow.process_material = process_material
	var flake := QuadMesh.new()
	flake.size = Vector2(0.025, 0.065)
	flake.orientation = PlaneMesh.FACE_Z
	var flake_image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for py in 32:
		for px in 32:
			var uv := Vector2((px + 0.5) / 32.0, (py + 0.5) / 32.0)
			var distance := Vector2((uv.x - 0.5) / 0.34, (uv.y - 0.5) / 0.48).length()
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 1.7)
			flake_image.set_pixel(px, py, Color(0.88, 0.95, 1.0, alpha))
	var flake_texture := ImageTexture.create_from_image(flake_image)
	var flake_material := StandardMaterial3D.new()
	flake_material.albedo_color = Color(0.86, 0.94, 1.0, 0.85)
	flake_material.albedo_texture = flake_texture
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = flake_material
	built.snow_material = flake_material
	snow.draw_pass_1 = flake
	root.add_child(snow)
	return snow
