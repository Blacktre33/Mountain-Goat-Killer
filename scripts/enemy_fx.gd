class_name EnemyFx
extends RefCounted
## Short-lived combat effects for the warpack: muzzle flash, tracers, dust and
## spark bursts, and flying armor debris. Meshes and materials are cached so a
## firefight allocates nodes but not resources.

static var _flash_material: StandardMaterial3D
static var _tracer_material: StandardMaterial3D
static var _spark_mesh: QuadMesh
static var _dust_mesh: QuadMesh
static var _unit_box: BoxMesh
static var _streak: QuadMesh


static func sound(tree: SceneTree, name: String, at: Vector3, volume_db := 0.0, pitch := 1.0, fallback := "") -> void:
	if tree == null:
		return
	var audio := tree.get_first_node_in_group("audio") as GoatAudio
	if audio == null:
		return
	if not audio.has_sound(name) and fallback != "":
		name = fallback
	audio.play_at(name, at, volume_db, pitch)


## A hot flash at the muzzle: a brief light, a star-shaped billboard and a cone
## of sparks. Lives for a tenth of a second.
static func muzzle_flash(parent: Node, at: Vector3, direction: Vector3) -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.albedo_color = Color(1.0, 0.82, 0.5)
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.albedo_texture = _radial_texture()
		_flash_material.no_depth_test = false
	var root := Node3D.new()
	root.name = "MuzzleFlash"
	parent.add_child(root)
	root.global_position = at
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.32)
	light.light_energy = 6.0
	light.omni_range = 7.0
	light.shadow_enabled = false
	root.add_child(light)
	for index in 2:
		var star := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * (0.75 if index == 0 else 0.36)
		quad.material = _flash_material
		star.mesh = quad
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		star.position = direction.normalized() * (0.18 * index)
		root.add_child(star)
	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.09)
	tween.tween_callback(root.queue_free)
	sparks(parent, at, direction, 8, 5.0)


static func tracer(parent: Node, from: Vector3, to: Vector3, color: Color, life := 0.1, width := 0.035) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	if _tracer_material == null:
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	var streak := MeshInstance3D.new()
	streak.mesh = _unit_box
	var material := _tracer_material.duplicate() as StandardMaterial3D
	material.albedo_color = color
	streak.material_override = material
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(streak)
	streak.global_position = (from + to) * 0.5
	streak.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	streak.scale = Vector3(width, width, length)
	var tween := streak.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.tween_callback(streak.queue_free)


static func sparks(parent: Node, at: Vector3, normal: Vector3, amount := 10, speed := 4.0, color := Color(1.0, 0.72, 0.3)) -> void:
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.04, 0.04)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.vertex_color_use_as_albedo = true
		_spark_mesh.material = material
	var burst := GPUParticles3D.new()
	burst.amount = amount
	burst.lifetime = 0.35
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.draw_pass_1 = _spark_mesh
	var process := ParticleProcessMaterial.new()
	process.direction = normal.normalized()
	process.spread = 38.0
	process.initial_velocity_min = speed * 0.5
	process.initial_velocity_max = speed
	process.gravity = Vector3(0.0, -9.0, 0.0)
	process.color = color
	burst.process_material = process
	parent.add_child(burst)
	burst.global_position = at
	burst.emitting = true
	var cleanup := burst.create_tween()
	cleanup.tween_interval(0.8)
	cleanup.tween_callback(burst.queue_free)


## A ring of kicked-up snow and dust: charges, slams, and skids.
static func dust_burst(parent: Node, at: Vector3, amount := 16, radius := 1.2, color := Color(0.82, 0.86, 0.92, 0.55)) -> void:
	if _dust_mesh == null:
		_dust_mesh = QuadMesh.new()
		_dust_mesh.size = Vector2(0.55, 0.55)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = _radial_texture()
		_dust_mesh.material = material
	var puff := GPUParticles3D.new()
	puff.amount = amount
	puff.lifetime = 0.9
	puff.one_shot = true
	puff.explosiveness = 0.95
	puff.draw_pass_1 = _dust_mesh
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.4
	process.direction = Vector3.UP
	process.spread = 80.0
	process.initial_velocity_min = radius * 0.8
	process.initial_velocity_max = radius * 2.0
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.damping_min = 1.5
	process.damping_max = 3.0
	process.scale_min = 0.5
	process.scale_max = 1.3
	process.color = color
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	puff.process_material = process
	parent.add_child(puff)
	puff.global_position = at
	puff.emitting = true
	var cleanup := puff.create_tween()
	cleanup.tween_interval(1.4)
	cleanup.tween_callback(puff.queue_free)


## A piece of torn-off armor that tumbles under real physics and fades away.
static func debris(parent: Node, at: Transform3D, mesh: Mesh, material: Material, impulse: Vector3, spin: Vector3, lifetime := 6.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	body.mass = 2.0
	body.linear_damp = 0.15
	body.angular_damp = 0.4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var extent := mesh.get_aabb().size
	box.size = Vector3(maxf(extent.x, 0.08), maxf(extent.y, 0.08), maxf(extent.z, 0.08))
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	parent.add_child(body)
	body.global_transform = at
	body.linear_velocity = impulse
	body.angular_velocity = spin
	var tween := body.create_tween()
	tween.tween_interval(lifetime)
	tween.tween_property(visual, "scale", Vector3.ZERO, 0.7)
	tween.tween_callback(body.queue_free)
	return body


static func _radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture
