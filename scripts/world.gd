class_name WorldBuilder
extends RefCounted
## Builds the Black Ravine: a noise-shaped snow valley between cliff walls,
## dressed with Kenney's CC0 nature and castle kits. Everything static lives
## under one `World` node so main.gd only has to deal with gameplay.

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

const NATURE := "res://assets/nature/%s.glb"
const CASTLE := "res://assets/castle/%s.glb"

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
	var moon: DirectionalLight3D
	var snowfall: GPUParticles3D
	var snow_material: StandardMaterial3D


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
	_build_forest(built.root)
	_build_trailhead(built)
	_build_homestead(built)
	_build_shrine(built)
	_build_ascent(built)
	_build_carrion_remains(built.root)
	_build_fortress(built)
	built.snowfall = _build_snowfall(built)
	return built


# --- Terrain -----------------------------------------------------------------

static func _terrain_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
	shader_type spatial;
	uniform vec3 snow_color : source_color = vec3(0.8, 0.87, 0.96);
	uniform vec3 rock_color : source_color = vec3(0.17, 0.2, 0.24);
	uniform vec3 carrion_snow : source_color = vec3(0.48, 0.43, 0.4);
	uniform vec3 carrion_rock : source_color = vec3(0.25, 0.13, 0.1);
	uniform vec3 crown_ash : source_color = vec3(0.24, 0.23, 0.24);
	uniform vec3 crown_iron : source_color = vec3(0.08, 0.09, 0.11);
	uniform sampler2D grain;
varying vec3 world_pos;
varying float slope;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope = NORMAL.y;
}
void fragment() {
	float g = texture(grain, world_pos.xz * 0.11).r;
		float fine = texture(grain, world_pos.xz * 0.9).r;
		float rock = smoothstep(0.9, 0.66, slope + (g - 0.5) * 0.12);
		float carrion = 1.0 - smoothstep(-28.0, -12.0, world_pos.z);
		float crown = 1.0 - smoothstep(-88.0, -72.0, world_pos.z);
		vec3 biome_snow = mix(snow_color, carrion_snow, carrion);
		biome_snow = mix(biome_snow, crown_ash, crown);
		vec3 biome_rock = mix(rock_color, carrion_rock, carrion);
		biome_rock = mix(biome_rock, crown_iron, crown);
		vec3 snow = biome_snow * (0.86 + g * 0.22);
		// Dusted rock: ledges keep a little snow so cliffs read against the sky.
		vec3 stone = mix(biome_rock * (0.7 + fine * 0.6), biome_snow * 0.6, smoothstep(0.55, 0.85, fine) * 0.35);
		// A restrained rust-red mineral stain carries the Carrion Cut's history.
		float old_red = carrion * (1.0 - crown) * smoothstep(0.78, 0.96, fine) * (1.0 - rock) * 0.2;
		snow = mix(snow, vec3(0.29, 0.055, 0.035), old_red);
		ALBEDO = mix(snow, stone, rock);
	ROUGHNESS = mix(0.58, 0.96, rock);
	SPECULAR = mix(0.35, 0.1, rock);
	float sparkle = pow(fine, 14.0) * (1.0 - rock);
	EMISSION = vec3(0.55, 0.68, 0.9) * sparkle * 0.5;
}
"""
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
				for v in [a, c, b, b, c, d]:
					tool.set_uv(Vector2(v.x, v.z) * 0.1)
					tool.set_normal(normal_at(v.x, v.z))
					tool.add_vertex(v)
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
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	environment.ambient_light_sky_contribution = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
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
	# Soft sky fill from the opposite side so shadowed wood and cliffs keep their shape.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-52.0, -40.0, 0.0)
	fill.light_color = Color("5d7fa6")
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	root.add_child(fill)

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
	root.add_child(aurora)


## Shift fog, sky light, and precipitation as the player crosses the three acts.
## Terrain and foliage already carry permanent biome silhouettes; this makes the
## boundary legible in motion without loading a new scene.
static func set_biome(built: Built, biome: String) -> void:
	if built == null or built.environment == null:
		return
	match biome:
		"carrion_cut":
			built.environment.fog_light_color = Color("463431")
			built.environment.fog_density = 0.021
			built.environment.ambient_light_energy = 0.86
			built.sky_material.sky_horizon_color = Color("392a2c")
			built.sky_material.ground_horizon_color = Color("241b1b")
			built.moon.light_color = Color("c1aaa0")
			built.moon.light_energy = 0.78
			built.snow_material.albedo_color = Color(0.7, 0.68, 0.66, 0.78)
			built.snowfall.amount_ratio = 0.72
		"iron_crown":
			built.environment.fog_light_color = Color("2d2022")
			built.environment.fog_density = 0.027
			built.environment.ambient_light_energy = 0.68
			built.sky_material.sky_horizon_color = Color("321c22")
			built.sky_material.ground_horizon_color = Color("190f12")
			built.moon.light_color = Color("d19582")
			built.moon.light_energy = 0.62
			built.snow_material.albedo_color = Color(0.55, 0.48, 0.46, 0.72)
			built.snowfall.amount_ratio = 0.52
		_:
			built.environment.fog_light_color = Color("24394c")
			built.environment.fog_density = 0.013
			built.environment.ambient_light_energy = 1.0
			built.sky_material.sky_horizon_color = Color("1d3242")
			built.sky_material.ground_horizon_color = Color("15222b")
			built.moon.light_color = Color("a9c6e0")
			built.moon.light_energy = 0.9
			built.snow_material.albedo_color = Color(0.86, 0.94, 1.0, 0.85)
			built.snowfall.amount_ratio = 1.0


# --- Helpers -----------------------------------------------------------------

## Kenney's foliage is a bright park green; the ravine wants deep, frost-dusted needles.
const TINTS := {
	"leafsDark": Color(0.18, 0.34, 0.32),
	"leafs": Color(0.2, 0.37, 0.33),
	"woodBarkDark": Color(0.19, 0.13, 0.1),
	"woodBark": Color(0.22, 0.15, 0.11),
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
		var retouch := false
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			if material and (TINTS.has(material.resource_name) or material.albedo_texture):
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
				if material.albedo_texture:
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
	Vector2(0.0, 3.0), Vector2(-6.0, -28.0), Vector2(0.0, -92.0), Vector2(0.0, -100.0),
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


static func _campfire(built: Built, at: Vector3) -> void:
	var y := height_at(at.x, at.z)
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
	var whitewood := Vector2(-14.0, Z_MAX - 4.0)
	var carrion := Vector2(-76.0, -17.0)
	var crown := Vector2(Z_MIN + 4.0, -79.0)
	# WHITEWOOD: a dense blue-green wall of living frost pine.
	_scatter(root, NATURE % "tree_pineTallA", 72, rng, flanks, whitewood, Vector2(4.2, 6.4), 0.08, 0.85)
	_scatter(root, NATURE % "tree_pineTallB", 58, rng, flanks, whitewood, Vector2(4.0, 6.0), 0.08, 0.85)
	_scatter(root, NATURE % "tree_pineDefaultA", 48, rng, flanks, whitewood, Vector2(3.4, 5.2), 0.08, 0.85)
	_scatter(root, NATURE % "tree_pineSmallB", 55, rng, flanks, whitewood, Vector2(2.6, 4.0), 0.08, 1.0)
	# THE CARRION CUT: sparse wind-torn trees, exposed trunks, red stone.
	_scatter(root, NATURE % "tree_pineTallC", 24, rng, flanks, carrion, Vector2(3.6, 5.2), 0.12, 1.1)
	_scatter(root, NATURE % "tree_pineGroundA", 22, rng, flanks, carrion, Vector2(2.8, 4.4), 0.1, 1.2)
	_scatter(root, NATURE % "stump_oldTall", 28, rng, flanks, carrion, Vector2(2.5, 4.5), 0.08, 1.3)
	_scatter(root, CASTLE % "tree-trunk", 18, rng, flanks, carrion, Vector2(2.4, 4.0), 0.08, 1.3)
	# THE IRON CROWN: ash and siege wreckage have killed almost everything.
	_scatter(root, NATURE % "stump_old", 18, rng, flanks, crown, Vector2(2.4, 4.2), 0.12, 1.5)
	_scatter(root, NATURE % "rock_tallD", 24, rng, flanks, crown, Vector2(2.6, 4.8), 0.12, 1.8)
	var rims := [Vector2(-20.0, -11.5), Vector2(11.5, 20.0)]
	var whole := Vector2(Z_MIN + 4, Z_MAX - 4)
	_scatter(root, NATURE % "rock_largeA", 34, rng, rims, whole, Vector2(2.4, 4.6), 0.12, 1.2)
	_scatter(root, NATURE % "rock_largeC", 30, rng, rims, whole, Vector2(2.4, 4.4), 0.12, 1.2)
	_scatter(root, NATURE % "rock_tallB", 26, rng, rims, whole, Vector2(1.8, 3.4), 0.12, 1.2)
	var verges := [Vector2(-11.0, -4.5), Vector2(4.5, 11.0)]
	_scatter(root, NATURE % "stone_largeB", 40, rng, verges, whole, Vector2(0.9, 2.0), 0.15, 2.0)
	_scatter(root, NATURE % "rock_smallB", 60, rng, verges, whole, Vector2(1.0, 2.2), 0.15, 2.0)
	_scatter(root, NATURE % "plant_bush", 45, rng, [Vector2(-12.5, -4.5), Vector2(4.5, 12.5)], whitewood, Vector2(1.4, 2.6), 0.1, 2.0)
	var cliffs := [Vector2(-29.0, -21.0), Vector2(21.0, 29.0)]
	_scatter(root, NATURE % "rock_largeB", 40, rng, cliffs, whole, Vector2(5.0, 9.0), 0.3, 99.0)
	_scatter(root, NATURE % "rock_largeD", 36, rng, cliffs, whole, Vector2(5.0, 9.0), 0.3, 99.0)
	_scatter(root, NATURE % "rock_tallC", 30, rng, cliffs, whole, Vector2(3.0, 6.0), 0.3, 99.0)
	_scatter(root, NATURE % "stone_largeE", 30, rng, cliffs, whole, Vector2(4.0, 7.0), 0.3, 99.0)
	_build_skyline(root, rng)


## Distant peaks beyond the playable flanks so the ravine walls meet a mountain, not empty sky.
static func _build_skyline(root: Node3D, rng: RandomNumberGenerator) -> void:
	var peak := StandardMaterial3D.new()
	peak.albedo_color = Color("1c2630")
	peak.roughness = 1.0
	for side in [-1.0, 1.0]:
		for i in 9:
			var z := Z_MIN + 6.0 + i * 18.0 + rng.randf_range(-5.0, 5.0)
			var x: float = side * rng.randf_range(44.0, 62.0)
			var mountain := MeshInstance3D.new()
			var cone := PrismMesh.new()
			cone.size = Vector3(rng.randf_range(34.0, 52.0), rng.randf_range(38.0, 64.0), rng.randf_range(30.0, 46.0))
			cone.material = peak
			mountain.mesh = cone
			mountain.position = Vector3(x, 4.0 + cone.size.y * 0.5, z)
			mountain.rotation.y = rng.randf() * TAU
			mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mountain)
	for i in 7:
		var x: float = -54.0 + i * 18.0
		var mountain := MeshInstance3D.new()
		var cone := PrismMesh.new()
		cone.size = Vector3(rng.randf_range(36.0, 50.0), rng.randf_range(44.0, 70.0), 40.0)
		cone.material = peak
		mountain.mesh = cone
		mountain.position = Vector3(x, 6.0 + cone.size.y * 0.5, Z_MIN - 40.0 - rng.randf_range(0.0, 20.0))
		mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mountain)


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
	place(root, NATURE % "rock_largeE", Vector3(-7.5, 0.0, 14.0), 0.9, 4.2, true)
	_lantern(built, Vector3(-2.2, 0.0, 33.0))


static func _build_homestead(built: Built) -> void:
	var root := built.root
	# Ring of fence around the old pasture, broken where the warpack came through.
	for i in 9:
		var x := -9.5 + i * 2.4
		if i == 4:
			continue
		place(root, NATURE % "fence_simpleHigh", Vector3(x, 0.0, 11.0), 0.0, 2.4, true)
		place(root, NATURE % "fence_simpleHigh", Vector3(x, 0.0, -13.0), 0.0, 2.4, true)
	for i in 4:
		place(root, NATURE % "fence_simpleHigh", Vector3(-10.5, 0.0, 8.0 - i * 2.4), PI * 0.5, 2.4, true)
		place(root, NATURE % "fence_simpleHigh", Vector3(10.5, 0.0, 8.0 - i * 2.4), PI * 0.5, 2.4, true)
	place(root, NATURE % "fence_gate", Vector3(0.1, 0.0, 11.0), 0.0, 2.4, false)
	# The raiders' camp.
	place(root, NATURE % "tent_detailedClosed", Vector3(-6.5, 0.0, 2.0), 0.8, 3.4, true)
	place(root, NATURE % "tent_smallClosed", Vector3(6.8, 0.0, -1.5), -0.9, 3.2, true)
	place(root, NATURE % "tent_smallClosed", Vector3(5.5, 0.0, -8.5), 2.4, 3.2, true)
	place(root, NATURE % "log_stack", Vector3(-2.0, 0.0, -6.0), 0.4, 2.8, true)
	place(root, NATURE % "log_stack", Vector3(3.2, 0.0, 5.5), 1.9, 2.8, true)
	place(root, NATURE % "log", Vector3(-7.2, 0.0, -8.0), 0.3, 3.0, true)
	place(root, NATURE % "stone_largeA", Vector3(0.5, 0.0, -1.0), 0.0, 2.6, true)
	place(root, NATURE % "rock_largeB", Vector3(-8.5, 0.0, -4.0), 1.0, 3.6, true)
	place(root, CASTLE % "siege-ram-demolished", Vector3(8.5, 0.0, 6.0), 2.2, 2.6, true)
	_campfire(built, Vector3(0.0, 0.0, 3.0))
	_lantern(built, Vector3(-4.6, 0.0, 9.6))
	_lantern(built, Vector3(7.6, 0.0, -5.0))
	_lantern(built, Vector3(-5.5, 0.0, -11.5))


static func _build_shrine(built: Built) -> void:
	var root := built.root
	var origin := BELL_ORIGIN
	var timber := StandardMaterial3D.new()
	timber.albedo_color = Color("4a2c1b")
	timber.roughness = 0.85
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.45, 5.4, 0.45)
		post_mesh.material = timber
		post.mesh = post_mesh
		post.position = Vector3(origin.x + side * 2.1, height_at(origin.x + side * 2.1, origin.z) + 2.7, origin.z)
		root.add_child(post)
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = post_mesh.size
		collider.shape = shape
		body.add_child(collider)
		body.position = post.position
		root.add_child(body)
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(4.9, 0.5, 0.55)
	beam_mesh.material = timber
	beam.mesh = beam_mesh
	beam.position = Vector3(origin.x, height_at(origin.x, origin.z) + 5.2, origin.z)
	root.add_child(beam)
	var bell := MeshInstance3D.new()
	var bell_mesh := CylinderMesh.new()
	bell_mesh.top_radius = 0.42
	bell_mesh.bottom_radius = 0.86
	bell_mesh.height = 1.35
	built.bell_material = StandardMaterial3D.new()
	built.bell_material.albedo_color = Color("c2842f")
	built.bell_material.metallic = 0.92
	built.bell_material.roughness = 0.24
	built.bell_material.emission_enabled = true
	built.bell_material.emission = Color("7a3410")
	built.bell_material.emission_energy_multiplier = 0.7
	bell_mesh.material = built.bell_material
	bell.mesh = bell_mesh
	bell.position = Vector3(origin.x, height_at(origin.x, origin.z) + 3.9, origin.z)
	root.add_child(bell)
	var bell_light := OmniLight3D.new()
	bell_light.position = bell.position + Vector3(0.0, 0.4, 1.0)
	bell_light.light_color = Color("ff9341")
	bell_light.light_energy = 4.5
	bell_light.omni_range = 15.0
	root.add_child(bell_light)
	built.lanterns.append({"node": bell_light, "light": bell_light, "glass": null, "position": bell_light.position, "lit": true, "fire": true})
	for i in 6:
		var angle := i * TAU / 6.0
		var at := Vector3(origin.x + cos(angle) * 5.2, 0.0, origin.z + sin(angle) * 5.2)
		place(root, NATURE % "stone_largeC", at, angle, 1.9, true)
	place(root, NATURE % "tree_pineTallC", Vector3(origin.x - 6.5, 0.0, origin.z - 3.0), 0.4, 5.4, true)
	place(root, NATURE % "rock_largeD", Vector3(6.5, 0.0, -22.0), 0.7, 4.0, true)
	place(root, NATURE % "rock_largeF", Vector3(7.5, 0.0, -34.0), 2.1, 4.4, true)
	place(root, NATURE % "log_large", Vector3(-1.5, 0.0, -20.0), 0.9, 3.0, true)
	_lantern(built, Vector3(2.5, 0.0, -30.0))


static func _build_ascent(built: Built) -> void:
	var root := built.root
	place(root, CASTLE % "siege-catapult-demolished", Vector3(-5.0, 0.0, -48.0), 0.6, 3.0, true)
	place(root, NATURE % "rock_largeA", Vector3(6.0, 0.0, -45.0), 0.0, 4.6, true)
	place(root, NATURE % "rock_largeE", Vector3(-6.8, 0.0, -57.0), 1.4, 4.8, true)
	place(root, NATURE % "rock_tallD", Vector3(4.0, 0.0, -62.0), 0.3, 3.4, true)
	place(root, NATURE % "stone_largeA", Vector3(-1.5, 0.0, -66.5), 2.0, 2.4, true)
	place(root, NATURE % "log_stack", Vector3(7.0, 0.0, -70.0), 0.8, 2.8, true)
	place(root, NATURE % "rock_largeB", Vector3(-7.0, 0.0, -73.0), 0.2, 4.2, true)
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
		var site: Vector3 = sites[site_index]
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


static func _build_fortress(built: Built) -> void:
	var root := built.root
	var z := GATE_Z
	var wall_scale := 5.2
	var ground := height_at(0.0, z)
	# Curtain wall with a gate in the middle, towers at both ends.
	# The narrow gate arch is 0.63 units wide; the walls butt up against it exactly.
	var arch_half := 0.63 * wall_scale * 0.5
	for x in [-(arch_half + wall_scale * 1.5), -(arch_half + wall_scale * 0.5), arch_half + wall_scale * 0.5, arch_half + wall_scale * 1.5]:
		place(root, CASTLE % "wall", Vector3(x, 0.0, z), 0.0, wall_scale, true)
	for x in [-15.0, 15.0]:
		place(root, CASTLE % "wall", Vector3(x, 0.0, z), 0.0, wall_scale, true)
	for x in [-12.6, 12.6]:
		var base := place(root, CASTLE % "tower-square-base", Vector3(x, 0.0, z), 0.0, wall_scale, true)
		var mid := place(root, CASTLE % "tower-square-mid-windows", Vector3(x, 0.0, z), 0.0, wall_scale, true, false)
		mid.position.y = base.position.y + 1.01 * wall_scale
		var top := place(root, CASTLE % "tower-square-top-roof", Vector3(x, 0.0, z), 0.0, wall_scale, false, false)
		top.position.y = mid.position.y + 1.01 * wall_scale
	var gate_frame := place(root, CASTLE % "wall-narrow-gate", Vector3(0.0, 0.0, z), 0.0, wall_scale, false)
	gate_frame.name = "GateFrame"
	# The portcullis mesh spans Z in its own space, so turn it to sit across the arch.
	built.gate = place(root, CASTLE % "metal-gate", Vector3(0.0, 0.0, z), PI * 0.5, wall_scale, false)
	built.gate.name = "Gate"
	built.gate_block = StaticBody3D.new()
	built.gate_block.name = "GateBlock"
	built.gate_block.collision_layer = 1
	var block := CollisionShape3D.new()
	var block_shape := BoxShape3D.new()
	block_shape.size = Vector3(3.6, 8.0, 1.0)
	block.shape = block_shape
	block.position.y = 4.0
	built.gate_block.add_child(block)
	built.gate_block.position = Vector3(0.0, ground, z)
	root.add_child(built.gate_block)
	for x in [-4.4, 4.4]:
		place(root, CASTLE % "flag-banner-long", Vector3(x, 1.31 * wall_scale, z + 0.3), PI, wall_scale * 0.45, false, false).position.y += ground
	for x in [-8.0, 8.0]:
		var window_light := OmniLight3D.new()
		window_light.position = Vector3(x, ground + 4.2, z + 2.4)
		window_light.light_color = Color("ff7a2e")
		window_light.light_energy = 3.0
		window_light.omni_range = 9.0
		root.add_child(window_light)
		built.lanterns.append({"node": window_light, "light": window_light, "glass": null, "position": window_light.position, "lit": true, "fire": true})
	# Courtyard beyond the gate: pens where the herd was kept, and Varkas' throne of wreckage.
	for i in 5:
		place(root, NATURE % "fence_planks", Vector3(-8.0 + i * 1.6, 0.0, COURTYARD_Z + 3.0), 0.0, 2.2, true)
		place(root, NATURE % "fence_planks", Vector3(2.0 + i * 1.6, 0.0, COURTYARD_Z + 3.0), 0.0, 2.2, true)
	place(root, CASTLE % "siege-tower", Vector3(0.0, 0.0, COURTYARD_Z - 7.0), PI, 4.0, true)
	place(root, CASTLE % "siege-ballista", Vector3(-7.0, 0.0, COURTYARD_Z - 4.0), 0.4, 3.0, true)
	place(root, CASTLE % "siege-ballista", Vector3(7.0, 0.0, COURTYARD_Z - 4.0), -0.4, 3.0, true)
	_campfire(built, Vector3(0.0, 0.0, COURTYARD_Z - 1.0))
	# Back wall of the courtyard.
	for x in [-9.9, -4.7, 0.0, 4.7, 9.9]:
		place(root, CASTLE % "wall", Vector3(x, 0.0, COURTYARD_Z - 11.0), 0.0, wall_scale, true)


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
	snow.process_material = process_material
	var flake := QuadMesh.new()
	flake.size = Vector2(0.04, 0.04)
	flake.orientation = PlaneMesh.FACE_Z
	var flake_material := StandardMaterial3D.new()
	flake_material.albedo_color = Color(0.86, 0.94, 1.0, 0.85)
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = flake_material
	built.snow_material = flake_material
	snow.draw_pass_1 = flake
	root.add_child(snow)
	return snow
