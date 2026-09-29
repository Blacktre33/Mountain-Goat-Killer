class_name CombatFX
extends Node3D
## Pooled world-space combat effects: bullet impacts by surface (snow puffs,
## rock chips and sparks, wood splinters, flesh), lasting bullet-hole decals, and
## falling brass and magazines. Everything is preallocated and recycled so a long
## firefight never allocates per shot.

signal sound_at(name: String, at: Vector3, volume_db: float, pitch: float)

const DEBRIS_POOL := 14
const DECAL_POOL := 36
const EMITTER_POOL := 4
const SPARK_TEXTURE := preload("res://assets/weapon/fx/spark_dot.png")
const SMOKE_TEXTURE := preload("res://assets/weapon/fx/smoke_puff.png")
const HOLE_TEXTURES := {
	"snow": preload("res://assets/weapon/fx/hole_snow.png"),
	"rock": preload("res://assets/weapon/fx/hole_rock.png"),
	"wood": preload("res://assets/weapon/fx/hole_wood.png"),
	"metal": preload("res://assets/weapon/fx/hole_rock.png"),
}
const HOLE_NORMAL := preload("res://assets/weapon/fx/hole_normal.png")
const WOOD_HINTS := ["tree", "log", "fence", "stump", "plank", "wood", "trunk", "pine", "bridge", "scaffold", "cart", "crate", "barrel", "timber", "branch", "beam"]
const METAL_HINTS := ["iron", "gate", "cage", "bell", "lantern", "chain", "spike"]

var debris: Array = []
var next_debris := 0
var decals: Array[Decal] = []
var next_decal := 0
var emitters := {}
var next_emitter := {}
var brass_material: StandardMaterial3D
var magazine_material: StandardMaterial3D


func _ready() -> void:
	name = "CombatFX"
	top_level = true
	_build_debris()
	_build_decals()
	for layer in ["snow_puff", "rock_chips", "rock_dust", "sparks", "splinters", "blood", "wood_dust"]:
		emitters[layer] = []
		next_emitter[layer] = 0
		for i in EMITTER_POOL:
			var emitter := _make_emitter(layer)
			add_child(emitter)
			emitters[layer].append(emitter)


## What a raycast hit is made of: drives the puff, the decal and the sound.
static func surface_of(hit: Dictionary) -> String:
	var collider: Object = hit.get("collider")
	if collider == null:
		return "rock"
	if collider.has_method("take_damage"):
		return "flesh"
	if collider.has_meta("surface"):
		return String(collider.get_meta("surface"))
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if collider.name == "TerrainBody":
		return "snow" if normal.y > 0.7 else "rock"
	var hint := ""
	if collider is Node:
		for child in (collider as Node).get_children():
			if child is MeshInstance3D:
				hint += String(child.name).to_lower() + " "
	for word in METAL_HINTS:
		if hint.contains(word):
			return "metal"
	for word in WOOD_HINTS:
		if hint.contains(word):
			return "wood"
	return "rock"


# --- Impacts -------------------------------------------------------------------------------

func impact(at: Vector3, normal: Vector3, surface: String, silent := false) -> void:
	match surface:
		"snow":
			_burst("snow_puff", at, normal)
			_decal(at, normal, surface, 0.5)
		"rock":
			_burst("rock_chips", at, normal)
			_burst("rock_dust", at, normal)
			_burst("sparks", at, normal)
			_decal(at, normal, surface, 0.8)
		"metal":
			_burst("sparks", at, normal)
			_burst("sparks", at, normal)
			_decal(at, normal, surface, 0.9)
		"wood":
			_burst("splinters", at, normal)
			_burst("wood_dust", at, normal)
			_decal(at, normal, surface, 0.9)
		"flesh":
			_burst("blood", at, normal)
	if silent:
		return
	var sound: String = {"snow": "impact_snow", "rock": "rock_hit", "metal": "clank", "wood": "impact_wood", "flesh": "impact_flesh"}[surface]
	sound_at.emit(sound, at, -8.0 if surface != "flesh" else -6.0, randf_range(0.85, 1.15))


func _burst(layer: String, at: Vector3, normal: Vector3) -> void:
	var pool: Array = emitters[layer]
	var emitter: GPUParticles3D = pool[next_emitter[layer]]
	next_emitter[layer] = (next_emitter[layer] + 1) % pool.size()
	var up := normal.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	emitter.global_transform = Transform3D(Basis(side, up, side.cross(up)), at + up * 0.02)
	emitter.restart()
	emitter.emitting = true


func _make_emitter(layer: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = layer.capitalize().replace(" ", "")
	particles.one_shot = true
	particles.emitting = false
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.fixed_fps = 0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.gravity = Vector3(0.0, -9.0, 0.0)
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.particles_anim_h_frames = 1
	material.particles_anim_v_frames = 1
	material.albedo_texture = SMOKE_TEXTURE
	var ramp := Gradient.new()
	match layer:
		"snow_puff":
			particles.amount = 20
			particles.lifetime = 0.85
			process.spread = 58.0
			process.initial_velocity_min = 0.6
			process.initial_velocity_max = 2.6
			process.gravity = Vector3(0.0, -1.2, 0.0)
			process.damping_min = 2.0
			process.damping_max = 3.0
			process.scale_min = 0.6
			process.scale_max = 1.4
			ramp.colors = PackedColorArray([Color(0.92, 0.95, 1.0, 0.75), Color(0.85, 0.9, 1.0, 0.0)])
			quad.size = Vector2.ONE * 0.22
		"rock_dust":
			particles.amount = 8
			particles.lifetime = 0.9
			process.spread = 40.0
			process.initial_velocity_min = 0.3
			process.initial_velocity_max = 1.2
			process.gravity = Vector3(0.0, 0.3, 0.0)
			process.damping_min = 1.5
			process.damping_max = 2.5
			ramp.colors = PackedColorArray([Color(0.55, 0.55, 0.58, 0.5), Color(0.5, 0.5, 0.52, 0.0)])
			quad.size = Vector2.ONE * 0.26
		"wood_dust":
			particles.amount = 8
			particles.lifetime = 0.7
			process.spread = 45.0
			process.initial_velocity_min = 0.4
			process.initial_velocity_max = 1.4
			process.gravity = Vector3(0.0, -0.4, 0.0)
			process.damping_min = 1.5
			process.damping_max = 2.5
			ramp.colors = PackedColorArray([Color(0.62, 0.45, 0.28, 0.45), Color(0.55, 0.4, 0.25, 0.0)])
			quad.size = Vector2.ONE * 0.2
		"sparks":
			particles.amount = 12
			particles.lifetime = 0.34
			process.spread = 70.0
			process.initial_velocity_min = 3.0
			process.initial_velocity_max = 8.0
			process.scale_min = 0.5
			process.scale_max = 1.0
			ramp.colors = PackedColorArray([Color(1.0, 0.82, 0.45, 1.0), Color(1.0, 0.4, 0.1, 0.0)])
			quad.size = Vector2.ONE * 0.05
			material.albedo_texture = SPARK_TEXTURE
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"rock_chips":
			particles.amount = 9
			particles.lifetime = 0.6
			process.spread = 65.0
			process.initial_velocity_min = 2.0
			process.initial_velocity_max = 5.5
			process.scale_min = 0.6
			process.scale_max = 1.3
			ramp.colors = PackedColorArray([Color(0.46, 0.45, 0.44, 1.0), Color(0.32, 0.32, 0.34, 0.0)])
			quad.size = Vector2.ONE * 0.032
			material.albedo_texture = SPARK_TEXTURE
		"splinters":
			particles.amount = 10
			particles.lifetime = 0.6
			process.spread = 60.0
			process.initial_velocity_min = 2.0
			process.initial_velocity_max = 5.0
			process.scale_min = 0.7
			process.scale_max = 1.5
			ramp.colors = PackedColorArray([Color(0.78, 0.56, 0.32, 1.0), Color(0.5, 0.33, 0.18, 0.0)])
			quad.size = Vector2(0.03, 0.03)
			material.albedo_texture = SPARK_TEXTURE
		"blood":
			particles.amount = 16
			particles.lifetime = 0.55
			process.spread = 55.0
			process.initial_velocity_min = 1.2
			process.initial_velocity_max = 4.2
			process.scale_min = 0.6
			process.scale_max = 1.6
			ramp.colors = PackedColorArray([Color(0.62, 0.05, 0.04, 0.95), Color(0.28, 0.02, 0.02, 0.0)])
			quad.size = Vector2.ONE * 0.085
			material.albedo_texture = SMOKE_TEXTURE
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(1.0, 1.0 if layer in ["snow_puff", "rock_dust", "wood_dust", "blood"] else 0.4))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process.scale_curve = scale_texture
	quad.material = material
	particles.process_material = process
	particles.draw_pass_1 = quad
	return particles


# --- Bullet holes -------------------------------------------------------------------------

func _build_decals() -> void:
	for i in DECAL_POOL:
		var decal := Decal.new()
		decal.name = "BulletHole_%02d" % i
		decal.size = Vector3(0.42, 0.2, 0.42)
		decal.texture_normal = HOLE_NORMAL
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		decal.normal_fade = 0.25
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 32.0
		decal.distance_fade_length = 10.0
		decal.visible = false
		add_child(decal)
		decals.append(decal)


func _decal(at: Vector3, normal: Vector3, surface: String, strength: float) -> void:
	var decal := decals[next_decal]
	next_decal = (next_decal + 1) % decals.size()
	decal.texture_albedo = HOLE_TEXTURES[surface]
	# Scars on near-black rock need lifting or the night grade swallows them.
	var lift := 3.2 if surface in ["rock", "metal"] else (1.6 if surface == "wood" else 1.0)
	decal.modulate = Color(lift, lift, lift, strength)
	decal.albedo_mix = 1.0
	var up := normal.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var basis := Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	var scale_value := randf_range(0.8, 1.25)
	decal.global_transform = Transform3D(basis.scaled(Vector3.ONE * scale_value), at + up * 0.02)
	decal.visible = true


func decal_count() -> int:
	var count := 0
	for decal in decals:
		if decal.visible:
			count += 1
	return count


# --- Falling brass and magazines ----------------------------------------------------------

func _build_debris() -> void:
	brass_material = StandardMaterial3D.new()
	brass_material.albedo_color = Color("c99a44")
	brass_material.metallic = 1.0
	brass_material.roughness = 0.28
	magazine_material = StandardMaterial3D.new()
	magazine_material.albedo_color = Color("15181b")
	magazine_material.metallic = 0.85
	magazine_material.roughness = 0.4
	for i in DEBRIS_POOL:
		var node := MeshInstance3D.new()
		node.name = "Brass_%02d" % i
		node.mesh = _casing_mesh()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		add_child(node)
		debris.append({"node": node, "velocity": Vector3.ZERO, "spin": Vector3.ZERO, "life": 0.0, "bounces": 0, "rest": 0.006, "kind": "brass"})


func eject_casing(from: Transform3D, velocity: Vector3) -> void:
	var item: Dictionary = debris[next_debris]
	next_debris = (next_debris + 1) % debris.size()
	var node: MeshInstance3D = item.node
	node.mesh = _casing_mesh()
	node.visible = true
	node.global_transform = Transform3D(from.basis.orthonormalized(), from.origin)
	item.velocity = velocity
	item.spin = Vector3(randf_range(-30.0, 30.0), randf_range(-12.0, 12.0), randf_range(-40.0, 40.0))
	item.life = 7.0
	item.bounces = 0
	item.rest = 0.006
	item.kind = "brass"


func drop_magazine(from: Transform3D, velocity: Vector3) -> void:
	var item: Dictionary = debris[next_debris]
	next_debris = (next_debris + 1) % debris.size()
	var node: MeshInstance3D = item.node
	node.mesh = _magazine_mesh()
	node.visible = true
	node.global_transform = Transform3D(from.basis.orthonormalized(), from.origin)
	item.velocity = velocity
	item.spin = Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0))
	item.life = 10.0
	item.bounces = 0
	item.rest = 0.03
	item.kind = "magazine"


var _casing: CylinderMesh
var _magazine: BoxMesh


func _casing_mesh() -> Mesh:
	if _casing == null:
		_casing = CylinderMesh.new()
		_casing.top_radius = 0.0048
		_casing.bottom_radius = 0.0056
		_casing.height = 0.034
		_casing.radial_segments = 8
		_casing.material = brass_material
	return _casing


func _magazine_mesh() -> Mesh:
	if _magazine == null:
		_magazine = BoxMesh.new()
		_magazine.size = Vector3(0.036, 0.15, 0.095)
		_magazine.material = magazine_material
	return _magazine


func _process(delta: float) -> void:
	for item in debris:
		var node: MeshInstance3D = item.node
		if not node.visible:
			continue
		item.life -= delta
		if item.life <= 0.0:
			node.visible = false
			continue
		if item.velocity.length_squared() < 0.0004 and item.bounces > 0:
			continue
		item.velocity.y -= 9.8 * delta
		node.global_position += item.velocity * delta
		node.rotate_object_local(Vector3.RIGHT, item.spin.x * delta)
		node.rotate_object_local(Vector3.UP, item.spin.y * delta)
		node.rotate_object_local(Vector3.FORWARD, item.spin.z * delta)
		var ground: float = WorldBuilder.height_at(node.global_position.x, node.global_position.z) + item.rest
		if node.global_position.y <= ground and item.velocity.y < 0.0:
			node.global_position.y = ground
			item.bounces += 1
			var hard: float = item.velocity.length()
			if hard > 1.0 or item.bounces == 1:
				var sound: String = "casing" if item.kind == "brass" else "thud"
				sound_at.emit(sound, node.global_position, -20.0 if item.kind == "brass" else -8.0, randf_range(0.9, 1.15))
			item.velocity = Vector3(item.velocity.x * 0.55, -item.velocity.y * 0.32, item.velocity.z * 0.55)
			item.spin *= 0.5
			if item.velocity.y < 0.6:
				item.velocity = Vector3.ZERO
				item.spin = Vector3.ZERO
				# Lie brass on its side and let a magazine settle flat.
				node.rotation = Vector3(PI * 0.5 if item.kind == "brass" else 0.0, node.rotation.y, 0.0)
