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

const NATURE := "res://assets/nature/%s.glb"
const CASTLE := "res://assets/castle/%s.glb"
const WIDOWPINE_FOLD := "res://assets/environment/widowpine/widowpine_broken_fold.glb"
const CARRION_BELL_SHRINE := "res://assets/environment/carrion_cut/carrion_cut_mother_bell.glb"
const IRON_CROWN_ABBEY := "res://assets/environment/iron_crown/iron_crown_bell_abbey_blockout.glb"
const VEGETATION := "res://assets/environment/vegetation/%s.glb"
const RAVINE_ROCK := "res://assets/environment/rocks/%s.glb"
const PROPS := "res://assets/environment/props/%s.glb"

static var _noise: FastNoiseLite
static var _detail: FastNoiseLite
static var _mesh_cache := {}
static var _ice_orm_texture: ImageTexture
static var _halo: GradientTexture2D
static var _prop_bounds := {}

## Result of a build: nodes gameplay needs to know about.
class Built:
	var root: Node3D
	var lanterns: Array = []      # {node, light, position, lit}
	var campfires: Array = []     # OmniLight3D
	var bell_material: StandardMaterial3D
	var gate: Node3D
	var gate_block: StaticBody3D
	var environment: Environment
	var sky_shader: ShaderMaterial
	var moon: DirectionalLight3D
	var atmosphere := {}          # currently applied biome values (see ATMOSPHERES)
	var biome_tween: Tween
	var snowfall: GPUParticles3D
	var ash: GPUParticles3D
	var snow_material: StandardMaterial3D
	var bellthorn_storm: GPUParticles3D
	var name_lights: Array[OmniLight3D] = []
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
	_build_carrion_remains(built.root)
	_build_hero_props(built.root)
	_build_fortress(built)
	built.snowfall = _build_snowfall(built)
	_build_atmosphere_lights(built)
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
	var scans := "res://assets/materials/polyhaven/%s/%s_%s_1k.jpg"
	var set_scan := func(prefix: String, id: String) -> void:
		material.set_shader_parameter(prefix + "_albedo", load(scans % [id, id, "diff"]))
		material.set_shader_parameter(prefix + "_normal", load(scans % [id, id, "nor_gl"]))
	set_scan.call("snow", "snow_02")
	set_scan.call("forest", "forest_ground_04")
	set_scan.call("carrion", "cracked_red_ground")
	set_scan.call("crown", "burned_ground_01")
	set_scan.call("cliff", "rock_face_03")
	material.set_shader_parameter("grime_albedo", load("res://assets/materials/generated/dirty_snow_albedo.jpg"))
	material.set_shader_parameter("grime_normal", load("res://assets/materials/generated/dirty_snow_normal.jpg"))
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


## Ground dressing is projected Decals, never coloured geometry: soft-alpha
## dirty snow, glossy black ice, boot and paw prints pressed into the crust,
## dried blood and soot scorch. Decals conform to the height field, carry their
## own normals, and fade out with distance, so nothing can read as a hole.
static func _decal(root: Node3D, textures: String, at: Vector2, size: Vector2, yaw: float, tint := Color.WHITE, glossy := false, fade_normal := 0.35) -> Decal:
	var decal := Decal.new()
	decal.name = textures.capitalize().replace(" ", "")
	decal.texture_albedo = load("res://assets/materials/decals/%s_albedo.png" % textures)
	decal.texture_normal = load("res://assets/materials/decals/%s_normal.png" % textures)
	if glossy:
		decal.texture_orm = _ice_orm()
	decal.size = Vector3(size.x, 1.6, size.y)
	decal.position = Vector3(at.x, height_at(at.x, at.y), at.y)
	decal.rotation.y = yaw
	decal.modulate = tint
	decal.normal_fade = fade_normal
	decal.upper_fade = 0.4
	decal.lower_fade = 0.4
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 38.0
	decal.distance_fade_length = 14.0
	root.add_child(decal)
	return decal


static func _ice_orm() -> ImageTexture:
	if _ice_orm_texture == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		image.fill(Color(1.0, 0.07, 0.0))
		_ice_orm_texture = ImageTexture.create_from_image(image)
	return _ice_orm_texture


static func _build_route_dressing(root: Node3D) -> void:
	var decals := Node3D.new()
	decals.name = "GroundDecals"
	root.add_child(decals)
	var rng := _random(1408)

	# Black-ice seams: glossy, thin, cracked. Each is a soft-edged sheen.
	for spec in [
		[Vector2(-2.8, 27.0), Vector2(4.8, 2.4), -0.22], [Vector2(3.1, 10.0), Vector2(5.6, 2.2), 0.2],
		[Vector2(-2.0, -5.0), Vector2(4.2, 2.0), -0.35], [Vector2(2.5, -24.0), Vector2(5.4, 2.5), 0.28],
		[Vector2(-2.8, -39.0), Vector2(4.6, 2.2), -0.18], [Vector2(2.2, -57.0), Vector2(5.2, 2.3), 0.25],
		[Vector2(-2.0, -73.0), Vector2(4.4, 2.0), -0.3], [Vector2(2.6, -86.0), Vector2(5.0, 2.4), 0.16],
	]:
		_decal(decals, "ice_sheen", spec[0], spec[1], spec[2], Color(0.85, 0.95, 1.0, 0.8), true)

	# The massacre trail: one raider's bloody boot prints alternate down the
	# Widowpine lane, fading as the blood wears off his soles.
	for step in 30:
		var z := 33.0 - step * 1.0
		var side := -1.0 if step % 2 == 0 else 1.0
		var x := sin(step * 0.42) * 0.55 + side * 0.17
		var wear := clampf(1.0 - step / 30.0, 0.15, 1.0)
		var tint := Color(1.7, 0.42, 0.36, 0.5 + wear * 0.5).lerp(Color(1.0, 1.0, 1.05, 0.75), 1.0 - wear)
		_decal(decals, "footprint", Vector2(x, z), Vector2(0.24, 0.5), PI + side * 0.1 + rng.randf_range(-0.13, 0.13), tint, false, 0.25)
	# Wolverine paws cross the lane where the warpack fanned out.
	for i in 14:
		var z := 30.0 - i * 1.7
		var x := 1.4 * sin(i * 1.3) + (2.4 if i % 2 else -2.2)
		_decal(decals, "paw", Vector2(x, z), Vector2(0.34, 0.34), rng.randf() * TAU, Color(1.0, 1.0, 1.05, 0.85), false, 0.2)

	# Dirty, trampled snow breaks up the floor along the lane and in every biome.
	for i in 46:
		var z := rng.randf_range(Z_MIN + 8.0, Z_MAX - 6.0)
		var x := rng.randf_range(-5.5, 5.5)
		var size := rng.randf_range(1.6, 3.6)
		var tint := Color(0.95, 0.9, 0.92, 0.85)
		if z < -12.0:
			tint = Color(1.1, 0.72, 0.62, 0.8)
		if z < -73.0:
			tint = Color(0.7, 0.7, 0.78, 0.9)
		_decal(decals, "dirty_patch", Vector2(x, z), Vector2(size, size * rng.randf_range(0.6, 1.0)), rng.randf() * TAU, tint, false, 0.5)

	_build_widowpine_snow_relief(root)

	# Old kill-sites of the Carrion Cut: splatter with a drag mark leading away.
	for spec in [[Vector2(7.4, -20.0), 0.35], [Vector2(-7.2, -36.0), -0.42], [Vector2(6.8, -55.0), 0.18], [Vector2(-3.8, -47.0), 1.9], [Vector2(6.2, -72.5), 2.7]]:
		var at: Vector2 = spec[0]
		_decal(decals, "blood_splat", at, Vector2(2.4, 2.4), spec[1] * 2.0, Color(0.9, 0.85, 0.85, 0.9))
		_decal(decals, "blood_drag", at + Vector2(1.2, 0.5).rotated(spec[1]), Vector2(3.2, 0.9), spec[1] + 0.6, Color(0.8, 0.75, 0.75, 0.85))

	# The Iron Crown burns: soot scars where the forts were fired.
	for index in 9:
		var z := -78.0 - index * 3.8
		var at := Vector2((-1.0 if index % 2 == 0 else 1.0) * (2.2 + index % 3), z)
		_decal(decals, "scorch", at, Vector2(3.6 + index % 2, 3.2 + (index % 3) * 0.5), index * 1.1, Color.WHITE, false, 0.4)


## Shallow, wind-cut snow drifts give the opening path physical relief at the
## player's scale. They sit above collision by only a few centimetres, so they
## model light without snagging movement or changing encounter navigation; their
## alpha fades to nothing at every edge so they melt into the surrounding snow.
static func _build_widowpine_snow_relief(root: Node3D) -> void:
	var snow_crust := ShaderMaterial.new()
	snow_crust.resource_name = "Widowpine wind crust"
	snow_crust.shader = preload("res://assets/materials/snow_drift.gdshader")
	snow_crust.set_shader_parameter("snow_albedo", load("res://assets/materials/generated/dirty_snow_albedo.jpg"))
	snow_crust.set_shader_parameter("snow_normal", load("res://assets/materials/generated/dirty_snow_normal.jpg"))

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


# --- Sky ---------------------------------------------------------------------

const NIGHT_SKY_SHADER := "res://assets/materials/night_sky.gdshader"
const CRAG_SHADER := "res://assets/materials/distant_crag.gdshader"
const MOON_SURFACE := "res://assets/environment/sky/moon_surface.png"
const BIOME_BLEND_SECONDS := 5.0

## Sky-shader uniforms that a biome profile drives one-to-one.
const SKY_KEYS := [
	"zenith_color", "mid_color", "horizon_color", "glow_color", "ground_color", "cloud_tint",
	"moon_tint", "halo_tint", "panorama_energy", "star_strength", "cloud_cover",
	"aurora_strength", "moon_disc", "halo_ring", "moon_rays",
]

## The three moods. Every value here is tweened by set_biome, so crossing a
## boundary is a slow change of light rather than a pop.
const ATMOSPHERES := {
	# Widowpine: cold blue moonlit snow; the only warmth is lantern pools.
	"whitewood": {
		"zenith_color": Color("040a1c"), "mid_color": Color("0b2040"), "horizon_color": Color("2c5a80"),
		"glow_color": Color("3f7fb0"), "ground_color": Color("081420"), "cloud_tint": Color("5f86b0"),
		"moon_tint": Color("eaf2ff"), "halo_tint": Color("7aa8ff"),
		"panorama_energy": 0.05, "star_strength": 1.0, "cloud_cover": 0.42, "aurora_strength": 0.32,
		"moon_disc": 16.0, "halo_ring": 0.05, "moon_rays": 0.7,
		"fog_color": Color("2a4a66"), "fog_density": 0.011, "fog_sky": 0.0,
		"ambient_color": Color("52657b"), "ambient_energy": 1.12, "exposure": 1.05,
		"vfog_albedo": Color("7f9bb8"), "vfog_emission": Color("0e1c2e"), "vfog_density": 0.0072,
		"glow_intensity": 0.6, "saturation": 1.04, "contrast": 1.05,
		"moon_light_color": Color("a9c6e0"), "moon_light_energy": 1.18,
		"fill_color": Color("5d7fa6"), "fill_energy": 0.4, "rake_energy": 0.26,
		"snow_color": Color(0.86, 0.94, 1.0, 0.85), "snow_ratio": 1.0, "ash_ratio": 0.0,
		"crag_haze": Color("27516f"), "crag_rim": Color("24384f"),
	},
	# Carrion Cut: dusk ash, red-ochre air, a moon dimmed behind smoke.
	"carrion_cut": {
		"zenith_color": Color("1a0e12"), "mid_color": Color("3a1c18"), "horizon_color": Color("8a4628"),
		"glow_color": Color("a85a30"), "ground_color": Color("120a0a"), "cloud_tint": Color("8e5a48"),
		"moon_tint": Color("ffd8bf"), "halo_tint": Color("ff9a68"),
		"panorama_energy": 0.04, "star_strength": 0.22, "cloud_cover": 0.62, "aurora_strength": 0.0,
		"moon_disc": 9.0, "halo_ring": 0.0, "moon_rays": 0.35,
		"fog_color": Color("4a2c26"), "fog_density": 0.0115, "fog_sky": 0.0,
		"ambient_color": Color("6e5a62"), "ambient_energy": 1.3, "exposure": 1.15,
		"vfog_albedo": Color("8a6258"), "vfog_emission": Color("22100c"), "vfog_density": 0.0088,
		"glow_intensity": 0.7, "saturation": 0.94, "contrast": 1.08,
		"moon_light_color": Color("cbb8b6"), "moon_light_energy": 1.1,
		"fill_color": Color("8a5a50"), "fill_energy": 0.42, "rake_energy": 0.0,
		"snow_color": Color(0.62, 0.58, 0.58, 0.72), "snow_ratio": 0.6, "ash_ratio": 0.75,
		"crag_haze": Color("5a2e22"), "crag_rim": Color("3a2c2c"),
	},
	# Iron Crown: hostile stone lit by ember glow against a cold, high moon.
	"iron_crown": {
		"zenith_color": Color("05060c"), "mid_color": Color("10121c"), "horizon_color": Color("5c2418"),
		"glow_color": Color("8c3a16"), "ground_color": Color("0a0607"), "cloud_tint": Color("46485c"),
		"moon_tint": Color("dfe4ff"), "halo_tint": Color("ff8a52"),
		"panorama_energy": 0.035, "star_strength": 0.4, "cloud_cover": 0.66, "aurora_strength": 0.0,
		"moon_disc": 11.0, "halo_ring": 0.0, "moon_rays": 0.4,
		"fog_color": Color("2c1c1e"), "fog_density": 0.0125, "fog_sky": 0.0,
		"ambient_color": Color("4d5b70"), "ambient_energy": 1.12, "exposure": 1.1,
		"vfog_albedo": Color("7a6a78"), "vfog_emission": Color("1e0e0a"), "vfog_density": 0.0095,
		"glow_intensity": 0.75, "saturation": 1.06, "contrast": 1.1,
		"moon_light_color": Color("a9c4e3"), "moon_light_energy": 1.48,
		"fill_color": Color("5d7fa6"), "fill_energy": 0.5, "rake_energy": 0.0,
		"snow_color": Color(0.64, 0.66, 0.74, 0.7), "snow_ratio": 0.5, "ash_ratio": 1.0,
		"crag_haze": Color("4a2418"), "crag_rim": Color("2c3244"),
	},
}

## The moon disc lives in the sky shader, in the direction the Moonlight arrives
## from (its +Z axis), so shadows, rim light and the disc always agree.
const MOON_ROTATION_DEG := Vector3(-38.0, 152.0, 0.0)

static var _crag_material: ShaderMaterial


static func moon_direction() -> Vector3:
	return Basis.from_euler(MOON_ROTATION_DEG * (PI / 180.0)).z


static func _build_sky(built: Built) -> void:
	var root := built.root
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	# The sky shader reads no light or clock, so the radiance map only needs to
	# re-render while a biome tween is running; a small incremental map is cheap.
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	var moon := DirectionalLight3D.new()
	moon.name = "Moonlight"
	moon.rotation_degrees = MOON_ROTATION_DEG
	var sky_shader := ShaderMaterial.new()
	sky_shader.shader = load(NIGHT_SKY_SHADER)
	sky_shader.set_shader_parameter("panorama", load("res://assets/environment/sky/kloppenheim_07_puresky_2k.hdr"))
	sky_shader.set_shader_parameter("moon_surface", load(MOON_SURFACE))
	sky_shader.set_shader_parameter("moon_dir", moon_direction())
	sky.sky_material = sky_shader
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# The ravine keeps an authored cold ambient fill; the sky is a backdrop and
	# a source of reflections, not the scene's fill light.
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_white = 6.0
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
	environment.volumetric_fog_length = 82.0
	environment.volumetric_fog_sky_affect = 0.0
	# Forward scattering: the moon ahead of the player backlights the haze, which
	# is what turns gaps in the pines into visible light shafts.
	environment.volumetric_fog_anisotropy = 0.55
	environment.fog_enabled = true
	environment.fog_height = 2.0
	environment.fog_height_density = 0.06
	environment.glow_enabled = true
	environment.glow_bloom = 0.1
	environment.glow_hdr_threshold = 1.15
	environment.adjustment_enabled = true
	world_environment.environment = environment
	root.add_child(world_environment)
	built.environment = environment
	built.sky_shader = sky_shader

	moon.light_energy = 0.9
	moon.light_indirect_energy = 1.4
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	moon.directional_shadow_blend_splits = true
	moon.shadow_blur = 1.4
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
	_build_grade_overlay(root)


## Vignette and fine film grain above the 3D view but below the HUD. The grain
## also dithers the fog and sky gradients so they do not band on 8-bit displays.
static func _build_grade_overlay(root: Node3D) -> void:
	var layer := CanvasLayer.new()
	layer.name = "GradeOverlay"
	layer.layer = 0
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float vignette = 0.5;
uniform float grain = 0.035;
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	vec2 centered = (UV - 0.5) * vec2(1.0, 0.82);
	float edge = smoothstep(0.32, 0.78, length(centered));
	float noise = hash(FRAGCOORD.xy + fract(TIME * 7.0) * 61.0) - 0.5;
	vec3 tint = vec3(0.01, 0.015, 0.03);
	float alpha = clamp(edge * vignette + abs(noise) * grain, 0.0, 1.0);
	COLOR = vec4(tint + max(noise, 0.0) * grain * 2.0, alpha);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	var rect := ColorRect.new()
	rect.name = "Grade"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	layer.add_child(rect)
	root.add_child(layer)


## Unshadowed fills that keep the boss court out of pitch black: a cold moon
## spill from above, a low ember bounce from the braziers, and a red uplight at
## Varkas' feet so his silhouette separates from the wall behind him.
static func _build_atmosphere_lights(built: Built) -> void:
	var floor_y := height_at(0.0, COURTYARD_Z)
	var specs := [
		["CourtMoonSpill", Vector3(0.0, floor_y + 15.0, COURTYARD_Z - 3.0), Color("8aa4d6"), 1.5, 30.0, 1.3],
		["CourtEmberBounce", Vector3(0.0, floor_y + 3.0, COURTYARD_Z + 2.0), Color("ff8a48"), 1.4, 20.0, 1.6],
		["VarkasEmberUplight", Vector3(0.0, floor_y + 0.5, COURTYARD_Z - 4.5), Color("ff5a26"), 2.6, 9.0, 1.8],
	]
	for spec in specs:
		var light := OmniLight3D.new()
		light.name = spec[0]
		light.position = spec[1]
		light.light_color = spec[2]
		light.light_energy = spec[3]
		light.omni_range = spec[4]
		light.omni_attenuation = spec[5]
		light.shadow_enabled = false
		built.root.add_child(light)


## Shift the whole sky, fog, light and precipitation mood as the player crosses
## the three acts. The change is tweened over BIOME_BLEND_SECONDS; pass
## `instant` for captures and tests that need the final values immediately.
## Terrain and foliage already carry permanent biome silhouettes.
static func set_biome(built: Built, biome: String, instant := false) -> void:
	if built == null or built.environment == null:
		return
	# Architecture stays in the continuous world: the abbey begins along the
	# Carrion ascent, and the mother bell is visible from the broken fold.
	# Local atmosphere must never remove landmarks or hide their colliders.
	var target: Dictionary = ATMOSPHERES.get(biome, ATMOSPHERES["whitewood"])
	if is_instance_valid(built.biome_tween):
		built.biome_tween.kill()
	if instant or built.atmosphere.is_empty() or not built.root.is_inside_tree():
		_apply_atmosphere(built, target)
		return
	var from := built.atmosphere.duplicate()
	built.biome_tween = built.root.create_tween()
	built.biome_tween.tween_method(_blend_atmosphere.bind(built, from, target), 0.0, 1.0, BIOME_BLEND_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func _blend_atmosphere(weight: float, built: Built, from: Dictionary, target: Dictionary) -> void:
	var mixed := {}
	for key in target:
		mixed[key] = lerp(from[key], target[key], weight)
	_apply_atmosphere(built, mixed)


static func _apply_atmosphere(built: Built, v: Dictionary) -> void:
	built.atmosphere = v
	for key in SKY_KEYS:
		built.sky_shader.set_shader_parameter(key, v[key])
	var env := built.environment
	env.fog_light_color = v["fog_color"]
	env.fog_density = v["fog_density"]
	env.fog_sky_affect = v["fog_sky"]
	env.ambient_light_color = v["ambient_color"]
	env.ambient_light_energy = v["ambient_energy"]
	env.tonemap_exposure = v["exposure"]
	env.volumetric_fog_albedo = v["vfog_albedo"]
	env.volumetric_fog_emission = v["vfog_emission"]
	env.volumetric_fog_density = v["vfog_density"]
	env.glow_intensity = v["glow_intensity"]
	env.adjustment_saturation = v["saturation"]
	env.adjustment_contrast = v["contrast"]
	built.moon.light_color = v["moon_light_color"]
	built.moon.light_energy = v["moon_light_energy"]
	var fill := built.root.get_node_or_null("SkyFill") as DirectionalLight3D
	if fill:
		fill.light_color = v["fill_color"]
		fill.light_energy = v["fill_energy"]
	var ground_rake := built.root.get_node_or_null("WidowpineGroundRake") as DirectionalLight3D
	if ground_rake:
		ground_rake.light_energy = v["rake_energy"]
	if built.snow_material:
		built.snow_material.albedo_color = v["snow_color"]
	if is_instance_valid(built.snowfall):
		built.snowfall.amount_ratio = v["snow_ratio"]
	if is_instance_valid(built.ash):
		built.ash.amount_ratio = v["ash_ratio"]
		built.ash.emitting = v["ash_ratio"] > 0.01
	if _crag_material:
		_crag_material.set_shader_parameter("haze_color", v["crag_haze"])
		_crag_material.set_shader_parameter("rim_color", v["crag_rim"])
		_crag_material.set_shader_parameter("snow_tone", v["crag_rim"])


# --- Helpers -----------------------------------------------------------------

## Kenney's foliage is a bright park green; the ravine wants deep, frost-dusted needles.
const TINTS := {
	"leafsDark": Color(0.18, 0.34, 0.32),
	"leafs": Color(0.2, 0.37, 0.33),
	"woodBarkDark": Color(0.19, 0.13, 0.1),
	"woodBark": Color(0.22, 0.15, 0.11),
	"Widowpine needles": Color(0.28, 0.39, 0.37),
	"Widowpine bark": Color(0.2, 0.145, 0.11),
	"grass": Color(0.15, 0.27, 0.23),
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
			if material and (TINTS.has(material.resource_name) or (uses_kenney_atlas and (material.albedo_texture or SurfaceLibrary.PROP_TABLE.has(material.resource_name)))):
				retouch = true
		if retouch:
			mesh = mesh.duplicate()
			for i in mesh.get_surface_count():
				var material := mesh.surface_get_material(i)
				if material == null:
					continue
				# Kenney's flat pastel swatches become the shared scanned family.
				var swatch: Material = SurfaceLibrary.prop_material(material.resource_name) if uses_kenney_atlas else null
				if swatch:
					mesh.surface_set_material(i, swatch)
					continue
				var fixed: StandardMaterial3D = material.duplicate()
				if TINTS.has(material.resource_name):
					fixed.albedo_color = TINTS[material.resource_name]
				if uses_kenney_atlas and material.albedo_texture:
					# Kenney colour atlases are tiny swatches: filtering bleeds neighbours together.
					fixed.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				mesh.surface_set_material(i, fixed)
	if mesh and path.begins_with("res://assets/environment/rocks/"):
		# Scattered crags and boulders take the shared triplanar rock, which
		# shifts to red ironstone and ash-black by biome without new meshes.
		mesh = mesh.duplicate()
		for i in mesh.get_surface_count():
			mesh.surface_set_material(i, SurfaceLibrary.material("rock"))
	_mesh_cache[path] = mesh
	return mesh


static func _random(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Image-to-3D hero props (generated with Higgsfield/Tripo H3.1). `height` is the
## in-world height of the model's own bounds; `sink` buries the base that far
## (the bellthorn trees grow from a rooted stone plinth that should merge with
## the ground). The model is re-centred so it stands on the terrain at `at`.
static func place_prop(root: Node3D, prop: String, at: Vector2, height: float, yaw: float, collide := false, tilt := 0.0, sink := 0.0) -> Node3D:
	var packed: PackedScene = load(PROPS % prop)
	var model: Node3D = packed.instantiate()
	var box := _prop_bounds_of(prop, model)
	var factor := height / box.size.y
	model.scale = Vector3.ONE * factor
	var centre := box.get_center()
	model.position = Vector3(-centre.x, -box.position.y, -centre.z) * factor
	var holder: Node3D
	if collide:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := CylinderShape3D.new()
		shape.radius = maxf(box.size.x, box.size.z) * 0.4 * factor
		shape.height = height
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = height * 0.5
		body.add_child(collider)
		holder = body
	else:
		holder = Node3D.new()
	holder.name = prop.capitalize().replace(" ", "")
	holder.add_child(model)
	holder.position = Vector3(at.x, height_at(at.x, at.y) - 0.04 - sink, at.y)
	holder.rotation = Vector3(tilt, yaw, 0.0)
	root.add_child(holder)
	return holder


static func _prop_bounds_of(prop: String, model: Node3D) -> AABB:
	if not _prop_bounds.has(prop):
		var box := AABB()
		var first := true
		var stack: Array[Node] = [model]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			if node is MeshInstance3D and node.mesh:
				box = node.mesh.get_aabb() if first else box.merge(node.mesh.get_aabb())
				first = false
		_prop_bounds[prop] = box
	return _prop_bounds[prop]


## Pickup for a dropped bell (`bell_index >= 0`) or an ammunition pouch. The
## holder is a MeshInstance3D only because main.gd keeps its pickups typed that
## way; the visible model and a soft halo hang from it as children.
static func pickup_node(bell_index: int) -> MeshInstance3D:
	var holder := MeshInstance3D.new()
	holder.name = "BellPickup" if bell_index >= 0 else "PouchPickup"
	var model: Node3D = load(PROPS % ("neck_bell" if bell_index >= 0 else "ammo_pouch")).instantiate()
	var height := 0.46 if bell_index >= 0 else 0.34
	model.scale = Vector3.ONE * height
	holder.add_child(model)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = _halo_texture()
	material.albedo_color = Color(1.0, 0.72, 0.36, 0.4 if bell_index >= 0 else 0.22)
	material.disable_receive_shadows = true
	var quad := MeshInstance3D.new()
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2.ONE * (1.1 if bell_index >= 0 else 0.8)
	quad_mesh.material = material
	quad.mesh = quad_mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(quad)
	return holder


static func _halo_texture() -> GradientTexture2D:
	if _halo == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0)])
		_halo = GradientTexture2D.new()
		_halo.gradient = gradient
		_halo.fill = GradientTexture2D.FILL_RADIAL
		_halo.fill_from = Vector2(0.5, 0.5)
		_halo.fill_to = Vector2(1.0, 0.5)
		_halo.width = 128
		_halo.height = 128
	return _halo


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
	pole.mesh = _tube_mesh([Vector3(0, 0, 0), Vector3(0.01, 0.8, 0), Vector3(0.0, 1.6, 0.01), Vector3(0.0, 2.4, 0.02)], [0.075, 0.062, 0.055, 0.05], 8)
	pole.material_override = SurfaceLibrary.material("timber")
	holder.add_child(pole)
	# An iron crook carries the lantern out from the pole, so it hangs free.
	var crook := MeshInstance3D.new()
	crook.mesh = _tube_mesh([Vector3(0, 2.4, 0.02), Vector3(0, 2.62, 0.14), Vector3(0, 2.62, 0.3), Vector3(0, 2.56, 0.32)], [0.028, 0.024, 0.022, 0.02], 6)
	crook.material_override = SurfaceLibrary.material("iron")
	holder.add_child(crook)
	var cage := Node3D.new()
	cage.position = Vector3(0.0, 2.32, 0.32)
	holder.add_child(cage)
	var iron := SurfaceLibrary.material("iron")
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(0.2, 0.3, 0.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("ffb35c")
	glass.emission_enabled = true
	glass.emission = Color("ff8a2e")
	glass.emission_energy_multiplier = 2.6 if lit else 0.0
	glass_mesh.material = glass
	var flame := MeshInstance3D.new()
	flame.mesh = glass_mesh
	cage.add_child(flame)
	for corner in 4:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.028, 0.36, 0.028)
		post.mesh = post_mesh
		post.material_override = iron
		post.position = Vector3(0.105 * (1.0 if corner % 2 else -1.0), 0.0, 0.105 * (1.0 if corner < 2 else -1.0))
		cage.add_child(post)
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.02
	cap_mesh.bottom_radius = 0.17
	cap_mesh.height = 0.13
	cap_mesh.radial_segments = 4
	cap.mesh = cap_mesh
	cap.material_override = iron
	cap.position = Vector3(0.0, 0.245, 0.0)
	cap.rotation.y = PI * 0.25
	cage.add_child(cap)
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.25, 0.04, 0.25)
	base.mesh = base_mesh
	base.material_override = iron
	base.position = Vector3(0.0, -0.19, 0.0)
	cage.add_child(base)
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
	spark.size = Vector2(0.11, 0.11)
	var spark_material := StandardMaterial3D.new()
	# A soft round sprite, not a hard square: embers glow and fade at the edge.
	spark_material.albedo_texture = _halo_texture()
	spark_material.albedo_color = Color(1.0, 0.55, 0.2)
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.emission_enabled = true
	spark_material.emission = Color(1.0, 0.45, 0.1)
	spark_material.emission_energy_multiplier = 3.0
	spark_material.emission_texture = _halo_texture()
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


## A deterministic many-sided crag. Stepped cliff bands (a steep face, then a
## ledge) and per-rib radial variation give a ragged, faceted ridge instead of
## the smooth dome that the earlier five-ring version produced.
static func _crag_mesh(seed_value: int, width: float, height: float, depth: float) -> ArrayMesh:
	var rng := _random(seed_value)
	var segments := 18
	var ring_scales := [1.0, 0.95, 0.78, 0.72, 0.56, 0.5, 0.34, 0.28, 0.13]
	var ring_heights := [0.0, 0.14, 0.2, 0.37, 0.44, 0.6, 0.67, 0.82, 0.93]
	var ribs: Array[float] = []
	for segment in segments:
		ribs.append(rng.randf_range(0.62, 1.28))
	var rings: Array = []
	for ring_index in ring_scales.size():
		var ring: Array[Vector3] = []
		for segment in segments:
			var angle := TAU * segment / segments
			var radial: float = ribs[segment] * rng.randf_range(0.88, 1.12)
			var shear: float = (float(ring_heights[ring_index]) - 0.3) * ribs[(segment + 5) % segments] * 0.22
			var lift := rng.randf_range(-0.05, 0.05) * height * (0.3 + float(ring_heights[ring_index]))
			ring.append(Vector3(
				cos(angle) * width * 0.5 * ring_scales[ring_index] * radial + width * shear,
				height * ring_heights[ring_index] + lift,
				sin(angle) * depth * 0.5 * ring_scales[ring_index] * radial
			))
		rings.append(ring)
	var tip := Vector3(rng.randf_range(-0.1, 0.1) * width, height, rng.randf_range(-0.08, 0.08) * depth)
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
	# Peaks are dark silhouettes with haze pooled at their base (see the shader);
	# lit blue blobs read as a black ceiling against a bright sky.
	var peak := ShaderMaterial.new()
	peak.shader = load(CRAG_SHADER)
	peak.set_shader_parameter("moon_dir", moon_direction())
	_crag_material = peak
	var cap := peak
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
	_log_pile(root, Vector2(5.5, 26.0), 0.2)
	place(root, NATURE % "stump_old", Vector3(-6.0, 0.0, 20.0), 0.0, 3.0, true)
	_fallen_log(root, Vector2(4.0, 16.5), 1.2, 3.4, 0.3)
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
	SurfaceLibrary.upgrade(fold)
	root.add_child(fold)
	built.biome_roots["whitewood"] = fold
	_campfire(built, Vector3(0.0, 0.0, -0.4), false)
	# Runtime light volumes line up with the emissive Blender lantern housings.
	for at in [Vector3(-7.8, 2.25, 5.7), Vector3(7.8, 2.25, 5.0), Vector3(-7.75, 2.25, -7.0)]:
		_hero_light(built, at, Color("ff9a43"), 2.0, 7.5)


## Scanned-style cast bronze for bells, projected triplanar so the mesh needs no UVs.
static func _bronze_material(scale_value: float) -> StandardMaterial3D:
	var bronze := StandardMaterial3D.new()
	bronze.resource_name = "Mother Bell bronze"
	bronze.albedo_texture = load("res://assets/materials/generated/bell_bronze_albedo.jpg")
	bronze.normal_enabled = true
	bronze.normal_texture = load("res://assets/materials/generated/bell_bronze_normal.jpg")
	bronze.normal_scale = 0.45
	bronze.roughness_texture = load("res://assets/materials/generated/bell_bronze_rough.jpg")
	bronze.metallic = 0.8
	bronze.metallic_specular = 0.6
	bronze.uv1_triplanar = true
	bronze.uv1_scale = Vector3.ONE * scale_value
	bronze.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return bronze


static func _build_shrine(built: Built) -> void:
	var root := built.root
	var origin := BELL_ORIGIN
	var shrine_scene := load(CARRION_BELL_SHRINE) as PackedScene
	var shrine := shrine_scene.instantiate()
	shrine.name = "CarrionCutMotherBellShrine"
	shrine.position = Vector3(origin.x, height_at(origin.x, origin.z) - 0.1, origin.z)
	SurfaceLibrary.upgrade(shrine)
	root.add_child(shrine)
	built.biome_roots["carrion_cut"] = shrine
	var bell := shrine.find_child("MotherBell", true, false) as MeshInstance3D
	# Cast bronze with verdigris in the recesses. Kept a StandardMaterial3D so the
	# ringing flash can still drive its emission from main.gd.
	built.bell_material = _bronze_material(0.6)
	built.bell_material.emission_enabled = true
	built.bell_material.emission = Color("3d1c08")
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
	place_prop(root, "siege_wreck", Vector2(-5.0, -48.0), 3.2, 0.6, true)
	place(root, RAVINE_ROCK % "ravine_boulder_a", Vector3(6.0, 0.0, -45.0), 0.0, 1.75, true)
	place(root, RAVINE_ROCK % "ravine_boulder_c", Vector3(-6.8, 0.0, -57.0), 1.4, 1.85, true)
	place(root, RAVINE_ROCK % "ravine_cliff_c", Vector3(4.0, 0.0, -62.0), 0.3, 1.45, true)
	place(root, RAVINE_ROCK % "ravine_boulder_b", Vector3(-1.5, 0.0, -66.5), 2.0, 1.0, true)
	_log_pile(root, Vector2(7.0, -70.0), 0.8)
	place(root, RAVINE_ROCK % "ravine_boulder_b", Vector3(-7.0, 0.0, -73.0), 0.2, 1.65, true)
	place(root, CASTLE % "tree-trunk", Vector3(2.5, 0.0, -53.0), 0.0, 3.0, true)
	_lantern(built, Vector3(-3.0, 0.0, -44.0))
	_lantern(built, Vector3(5.5, 0.0, -66.0))


## A wind-felled trunk lying across the lane's edge: tapered, slightly bowed,
## with a sawn ringed end where the raiders cut it, and a box collider.
static func _fallen_log(root: Node3D, at: Vector2, yaw: float, length: float, radius: float) -> void:
	var log := StaticBody3D.new()
	log.name = "FallenLog"
	log.collision_layer = 1
	log.position = Vector3(at.x, height_at(at.x, at.y) + radius * 0.8, at.y)
	log.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = Vector3(radius * 1.7, radius * 1.7, length)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	log.add_child(collider)
	var path: Array = []
	var radii: Array = []
	for i in 8:
		var t := i / 7.0
		path.append(Vector3(sin(t * 3.0) * 0.06, sin(t * 2.0) * 0.03, (t - 0.5) * length))
		radii.append(radius * (1.0 - t * 0.28) * (1.0 + 0.04 * sin(t * 19.0)))
	var trunk := MeshInstance3D.new()
	trunk.mesh = _tube_mesh(path, radii, 12)
	trunk.material_override = SurfaceLibrary.material("bark")
	log.add_child(trunk)
	var cut := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.99
	disc.bottom_radius = radius * 0.99
	disc.height = 0.015
	disc.radial_segments = 12
	cut.mesh = disc
	cut.material_override = SurfaceLibrary.material("timber")
	cut.position = path[0] + Vector3(0.0, 0.0, -0.005)
	cut.rotation.x = PI * 0.5
	log.add_child(cut)
	root.add_child(log)


## A stacked cord of split pine: irregular logs with sawn, ringed ends instead of
## the kit's faceted crate. One shared mesh, three layers, collision as one box.
static func _log_pile(root: Node3D, at: Vector2, yaw: float) -> void:
	var rng := _random(int(absf(at.x * 31.0 + at.y * 17.0)))
	var pile := StaticBody3D.new()
	pile.name = "LogPile"
	pile.collision_layer = 1
	pile.position = Vector3(at.x, height_at(at.x, at.y) - 0.05, at.y)
	pile.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 0.8, 1.6)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, 0.4, 0.0)
	pile.add_child(collider)
	var bark := SurfaceLibrary.material("bark")
	var end_grain := SurfaceLibrary.material("timber")
	var log_mesh := _tube_mesh([Vector3(0, 0, -0.8), Vector3(0.01, 0, -0.4), Vector3(0, 0.01, 0.4), Vector3(0, 0, 0.8)], [0.12, 0.13, 0.13, 0.12], 9)
	var layers := [4, 3, 2]
	for layer in layers.size():
		var count: int = layers[layer]
		for i in count:
			var log := MeshInstance3D.new()
			log.mesh = log_mesh
			log.material_override = bark
			var x: float = (i - (count - 1) * 0.5) * 0.27 + rng.randf_range(-0.02, 0.02)
			log.position = Vector3(x, 0.13 + layer * 0.235, rng.randf_range(-0.05, 0.05))
			log.rotation = Vector3(0.0, rng.randf_range(-0.05, 0.05), rng.randf_range(-0.04, 0.04))
			log.scale = Vector3(rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.05))
			pile.add_child(log)
			for end in [-1.0, 1.0]:
				var cap := MeshInstance3D.new()
				var disc := CylinderMesh.new()
				disc.top_radius = 0.118
				disc.bottom_radius = 0.118
				disc.height = 0.012
				disc.radial_segments = 9
				cap.mesh = disc
				cap.material_override = end_grain
				cap.position = log.position + Vector3(0.0, 0.0, end * 0.8 * log.scale.z)
				cap.rotation = Vector3(PI * 0.5, 0.0, 0.0)
				pile.add_child(cap)
	root.add_child(pile)


## Generated hero props: kill stakes and caged remains mark the warpack's
## kill-sites, war banners mark its territory and thicken toward the Crown.
static func _build_hero_props(root: Node3D) -> void:
	var stakes := [
		[Vector2(-10.6, -21.0), 2.6, 0.4], [Vector2(0.6, -21.6), 2.3, -0.7], [Vector2(-6.4, -38.0), 2.2, 1.9],
		[Vector2(5.8, -52.0), 2.6, 0.2], [Vector2(-7.4, -66.0), 2.4, 2.6], [Vector2(6.6, -76.0), 2.5, -1.2],
		[Vector2(-3.4, -106.0), 2.6, 0.9], [Vector2(4.8, -108.0), 2.4, -2.1], [Vector2(-9.0, -95.0), 2.5, 0.3],
	]
	for spec in stakes:
		place_prop(root, "kill_stakes", spec[0], spec[1], spec[2], true)
	var banners := [
		[Vector2(5.4, -33.0), 5.2, 0.35], [Vector2(-7.6, -58.0), 5.4, -0.25], [Vector2(6.2, -70.0), 5.6, 0.1],
		[Vector2(-6.2, -77.0), 5.6, -0.15], [Vector2(9.0, 8.0), 4.6, 0.5],
		[Vector2(-10.0, -99.0), 5.8, 0.2], [Vector2(10.5, -103.0), 5.8, -0.3], [Vector2(-5.0, -111.0), 5.6, 0.0],
	]
	for spec in banners:
		place_prop(root, "war_banner", spec[0], spec[1], spec[2], true)
	# Bellthorn: living red-belled trees on the shoulders of the Carrion Cut and
	# the Crown, low thorn shrubs along the verges.
	var trees := [
		[Vector2(-12.5, -45.0), 7.0, 0.4], [Vector2(14.0, -74.0), 6.6, 2.0], [Vector2(-20.5, -88.5), 8.4, 1.1],
		[Vector2(17.4, -92.0), 6.8, 3.4], [Vector2(11.5, -30.0), 6.2, 0.9], [Vector2(-13.5, -62.0), 6.8, 2.6],
	]
	for spec in trees:
		place_prop(root, "bellthorn_tree", spec[0], spec[1], spec[2], true, 0.0, spec[1] * 0.06)
	var shrubs := [
		[Vector2(8.6, -26.5), 1.7], [Vector2(-8.8, -41.0), 2.0], [Vector2(9.6, -58.0), 1.8], [Vector2(-9.2, -71.0), 2.1],
		[Vector2(8.9, -84.0), 1.9], [Vector2(-12.0, -96.0), 2.2], [Vector2(10.5, -108.0), 2.0],
	]
	for i in shrubs.size():
		place_prop(root, "bellthorn_shrub", shrubs[i][0], shrubs[i][1], i * 1.7, true, 0.0, 0.05)
	var cages := [
		[Vector2(-4.4, -34.0), 1.5, 0.3, 0.06], [Vector2(3.6, -60.5), 1.5, -0.5, -0.08], [Vector2(7.6, 2.0), 1.4, 0.8, 0.05],
		[Vector2(7.0, -101.0), 1.6, 0.6, 0.05], [Vector2(-8.0, -105.0), 1.6, -0.4, -0.06], [Vector2(2.5, -109.0), 1.5, 1.2, 0.04],
	]
	for spec in cages:
		place_prop(root, "iron_cage", spec[0], spec[1], spec[2], true, spec[3])


## A tapered tube swept along `path`, with per-point radii. Used for horns,
## bones and thorn vines so nothing in the set dressing is a primitive cylinder.
static func _tube_mesh(path: Array, radii: Array, sides := 8) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var side_vector := Vector3.RIGHT
	for i in path.size():
		var tangent: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		side_vector = (side_vector - tangent * side_vector.dot(tangent))
		if side_vector.length() < 0.001:
			side_vector = tangent.cross(Vector3.UP)
		side_vector = side_vector.normalized()
		var up_vector := tangent.cross(side_vector)
		var ring: Array = []
		for k in sides:
			var angle := TAU * k / sides
			ring.append(path[i] + (side_vector * cos(angle) + up_vector * sin(angle)) * radii[i])
		rings.append(ring)
	for i in path.size() - 1:
		for k in sides:
			var n := (k + 1) % sides
			var v0: Vector3 = rings[i][k]
			var v1: Vector3 = rings[i][n]
			var v2: Vector3 = rings[i + 1][k]
			var v3: Vector3 = rings[i + 1][n]
			# Godot front faces wind clockwise; rings run counter-clockwise, so reverse.
			for vertex in [v0, v2, v1, v1, v2, v3]:
				tool.add_vertex(vertex)
	tool.generate_normals()
	return tool.commit()


static func _bone_mesh(length: float, radius: float) -> ArrayMesh:
	var path: Array = []
	var radii: Array = []
	for i in 9:
		var t := i / 8.0
		path.append(Vector3(0.0, 0.0, (t - 0.5) * length))
		# Knobbed joints at both ends, a narrow shaft between.
		var knob := pow(absf(t - 0.5) * 2.0, 6.0)
		radii.append(radius * (0.72 + knob * 0.75))
	return _tube_mesh(path, radii, 7)


static func _horn_mesh(length: float, radius: float) -> ArrayMesh:
	var path: Array = []
	var radii: Array = []
	for i in 12:
		var t := i / 11.0
		var angle := t * 1.7
		path.append(Vector3(sin(angle) * length * 0.45, t * length * 0.6, (1.0 - cos(angle)) * length * 0.25))
		# Growth ridges every few centimetres along a tapering keratin cone.
		radii.append(radius * (1.0 - t * 0.9) * (1.0 + 0.09 * sin(t * 40.0)))
	return _tube_mesh(path, radii, 8)


## Restrained environmental gore: three old kill-sites rather than constant
## splatter. Bones, ribs and goat horns turn the middle biome into a grave
## without overwhelming its stealth readability; the blood itself is decals.
static func _build_carrion_remains(root: Node3D) -> void:
	var bone_material := SurfaceLibrary.material("bone")
	var rng := _random(3301)
	var bone_mesh := _bone_mesh(0.5, 0.028)
	var long_bone_mesh := _bone_mesh(0.72, 0.034)
	var horn_mesh := _horn_mesh(0.55, 0.055)
	var rib_path: Array = []
	var rib_radii: Array = []
	for i in 9:
		var t := i / 8.0
		rib_path.append(Vector3(sin(t * PI * 0.9) * 0.22, 0.0, t * 0.42 - 0.21 + cos(t * PI * 0.9) * 0.02))
		rib_radii.append(0.014 * (1.0 - t * 0.5))
	var rib_mesh := _tube_mesh(rib_path, rib_radii, 6)
	var sites := [
		Vector3(7.4, 0.0, -20.0),
		Vector3(-3.8, 0.0, -47.0),
		Vector3(6.2, 0.0, -72.5),
	]
	for site_index in sites.size():
		var site: Vector3 = sites[site_index]
		var group := Node3D.new()
		group.name = "KillSite_%02d" % site_index
		root.add_child(group)
		var place_piece := func(mesh: Mesh, offset: Vector2, lift: float, rotation: Vector3, piece_scale := 1.0) -> void:
			var piece := MeshInstance3D.new()
			piece.mesh = mesh
			piece.material_override = bone_material
			var x: float = site.x + offset.x
			var z: float = site.z + offset.y
			piece.position = Vector3(x, height_at(x, z) + lift, z)
			piece.rotation = rotation
			piece.scale = Vector3.ONE * piece_scale
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			group.add_child(piece)
		for i in 5:
			place_piece.call(bone_mesh if i % 2 else long_bone_mesh, Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.7, 0.7)), 0.03, Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, 0.0))
		for i in 5:
			place_piece.call(rib_mesh, Vector2(-0.35 + i * 0.09, -0.2), 0.05, Vector3(0.5, PI * 0.5 + rng.randf_range(-0.1, 0.1), 0.0), 1.2)
		for side in [-1.0, 1.0]:
			place_piece.call(horn_mesh, Vector2(side * 0.45, -0.3), 0.04, Vector3(-0.35, site_index + side, side * 0.3))


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
	SurfaceLibrary.upgrade(abbey)
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
	built.ash = _build_ash(snow)
	return snow


## Charcoal flakes and glowing embers riding the wind through the Carrion Cut and
## Iron Crown. Parented to the snowfall so it follows the player; a hard-stop
## colour ramp gives each particle either ash grey or ember orange.
static func _build_ash(snow: GPUParticles3D) -> GPUParticles3D:
	var ash := GPUParticles3D.new()
	ash.name = "AshDrift"
	ash.amount = 520
	ash.lifetime = 7.0
	ash.preprocess = 7.0
	ash.amount_ratio = 0.0
	ash.emitting = false
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(28.0, 8.0, 32.0)
	motion.direction = Vector3(0.7, 0.1, -0.3)
	motion.spread = 30.0
	motion.initial_velocity_min = 1.2
	motion.initial_velocity_max = 3.4
	motion.gravity = Vector3(0.6, -0.12, -0.15)
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 1.2
	motion.turbulence_noise_scale = 3.0
	motion.scale_min = 0.5
	motion.scale_max = 1.5
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array([0.0, 0.78, 0.92])
	ramp.colors = PackedColorArray([Color(0.30, 0.28, 0.29, 0.75), Color(2.6, 0.95, 0.28, 1.0), Color(3.4, 1.5, 0.5, 1.0)])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	motion.color_initial_ramp = ramp_texture
	ash.process_material = motion
	var flake := QuadMesh.new()
	flake.size = Vector2(0.06, 0.06)
	var disc_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for py in 16:
		for px in 16:
			var radius := Vector2((px + 0.5) / 8.0 - 1.0, (py + 0.5) / 8.0 - 1.0).length()
			disc_image.set_pixel(px, py, Color(1.0, 1.0, 1.0, clampf(1.6 - radius * 1.6, 0.0, 1.0)))
	var flake_material := StandardMaterial3D.new()
	flake_material.albedo_texture = ImageTexture.create_from_image(disc_image)
	flake_material.vertex_color_use_as_albedo = true
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = flake_material
	ash.draw_pass_1 = flake
	snow.add_child(ash)
	return ash
