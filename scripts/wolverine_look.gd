class_name WolverineLook
extends RefCounted
## How a wolverine looks: the rigged Quaternius wolf re-tinted as the warpack,
## its bone-riding bells and rifles, and Varkas's hero dressing (iron plates,
## the Blender facial sculpt, Red Horn, embers and phase light). Also the brief
## blood effects. Everything here is presentation; behaviour stays in
## WolverineEnemy, which calls these while building and changing phase.


static func build(e: WolverineEnemy, target_height: float) -> void:
	e.model = Node3D.new()
	e.model.name = "Model"
	e.add_child(e.model)
	if e.boss:
		# Stable close-camera details share a fall rig. The skinned source supplies
		# locomotion, while this shell keeps Varkas' face and armor together during
		# the final death animation instead of leaving them suspended at the root.
		e.boss_shell = Node3D.new()
		e.boss_shell.name = "VarkasHeroShell"
		e.add_child(e.boss_shell)
	var wolf: Node = (WolverineEnemy.VARKAS_SCENE if e.boss else WolverineEnemy.WOLF_SCENE).instantiate()
	e.model.add_child(wolf)
	e.anim = _find(wolf, "AnimationPlayer") as AnimationPlayer
	e.skeleton = _find(wolf, "Skeleton3D") as Skeleton3D
	var mesh_instance := _find(wolf, "MeshInstance3D") as MeshInstance3D
	_fit_model(e, wolf, target_height)
	if e.anim:
		for name in ["Idle", "Walk", "Gallop", "Eating", "Idle_2", "Idle_2_HeadLow"]:
			if e.anim.has_animation(name):
				e.anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR

	e.body_material = StandardMaterial3D.new()
	match e.role:
		"boss":
			e.body_material.albedo_color = Color("2b211d")
		"brute":
			e.body_material.albedo_color = Color("3d464f")
		"stalker":
			e.body_material.albedo_color = Color("2a221c")
		_:
			e.body_material.albedo_color = Color("4a3d31")
	e.body_material.roughness = 0.82
	var fur_noise := NoiseTexture2D.new()
	var fur_source := FastNoiseLite.new()
	fur_source.seed = 784 if e.boss else 233
	fur_source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fur_source.frequency = 0.045
	fur_source.fractal_octaves = 4
	fur_source.fractal_lacunarity = 2.35
	fur_source.fractal_gain = 0.54
	var fur_ramp := Gradient.new()
	fur_ramp.offsets = PackedFloat32Array([0.0, 0.42, 0.72, 1.0])
	fur_ramp.colors = PackedColorArray([
		Color(0.34, 0.32, 0.3),
		Color(0.58, 0.55, 0.51),
		Color(0.82, 0.78, 0.72),
		Color(1.0, 0.94, 0.86),
	])
	fur_noise.width = 256
	fur_noise.height = 256
	fur_noise.seamless = true
	fur_noise.noise = fur_source
	fur_noise.color_ramp = fur_ramp
	e.body_material.albedo_texture = fur_noise
	if e.boss:
		# The hero has a full UV unwrap; the warpack retains its palette UVs.
		# This generated swatch already contains dark pigment, so avoid applying
		# the near-black procedural tint a second time.
		e.body_material.albedo_texture = preload("res://assets/materials/original/varkas_guard_fur.png")
		e.body_material.albedo_color = Color.WHITE
		e.body_material.uv1_scale = Vector3(4.0, 4.0, 1.0)
		e.body_material.roughness = 0.94
	e.body_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	e.body_light_material = e.body_material.duplicate() as StandardMaterial3D
	e.body_light_material.albedo_color = e.body_material.albedo_color.lightened(0.3)
	if e.boss:
		e.body_light_material.albedo_color = Color(1.5, 1.35, 1.15)
	e.eye_material = StandardMaterial3D.new()
	e.eye_material.albedo_color = Color("ffb340")
	e.eye_material.emission_enabled = true
	e.eye_material.emission = Color("6fb6ff")
	e.eye_material.emission_energy_multiplier = 2.4
	if mesh_instance:
		for i in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.mesh.surface_get_material(i)
			var surface_name := original.resource_name if original else ""
			match surface_name:
				"Main":
					mesh_instance.set_surface_override_material(i, e.body_material)
				"Main_Light":
					mesh_instance.set_surface_override_material(i, e.body_light_material)
				"Eyes_Black":
					mesh_instance.set_surface_override_material(i, e.eye_material)
	_dress(e)
	if e.boss:
		apply_phase(e)


static func _fit_model(e: WolverineEnemy, wolf: Node, target_height: float) -> void:
	if e.skeleton == null:
		return
	var low := INF
	var high := -INF
	var front := -INF
	var back := INF
	var head_z := 0.0
	var tail_z := 0.0
	var skeleton_to_model: Transform3D = e.model.global_transform.affine_inverse() * e.skeleton.global_transform
	for i in e.skeleton.get_bone_count():
		var origin: Vector3 = skeleton_to_model * e.skeleton.get_bone_global_rest(i).origin
		low = minf(low, origin.y)
		high = maxf(high, origin.y)
		front = maxf(front, origin.z)
		back = minf(back, origin.z)
		var bone_name := e.skeleton.get_bone_name(i)
		if bone_name == "Head":
			head_z = origin.z
		elif bone_name == "Tail1":
			tail_z = origin.z
	var height := maxf(0.01, high - low)
	var factor := target_height / height
	# Varkas is a mustelid, not a giant upright wolf. Preserve the animated rig,
	# but squash its vertical read and push mass through the chest and haunches.
	# Root-level hero details below are staged around the resulting 2.6 m crown.
	wolf.scale = Vector3(factor * 1.34, factor * 0.86, factor * 1.08) if e.boss else Vector3.ONE * factor
	# Godot's forward is -Z; turn the model round if its head points down +Z.
	if head_z > tail_z:
		wolf.rotation.y = PI
	wolf.position.y = -low * factor * (0.86 if e.boss else 1.0) + 0.02


static func _dress(e: WolverineEnemy) -> void:
	if e.skeleton == null:
		return
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("657078")
	iron.albedo_texture = load("res://assets/materials/polyhaven/rust_coarse_01/rust_coarse_01_Diffuse.jpg")
	iron.metallic = 0.76
	iron.roughness = 0.64
	iron.roughness_texture = load("res://assets/materials/polyhaven/rust_coarse_01/rust_coarse_01_Rough.jpg")
	iron.normal_enabled = true
	iron.normal_scale = 0.72
	iron.normal_texture = load("res://assets/materials/polyhaven/rust_coarse_01/rust_coarse_01_nor_gl.jpg")
	iron.emission_enabled = true
	iron.emission = Color("080c10")
	iron.emission_energy_multiplier = 0.08
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("e2b768")
	brass.albedo_texture = iron.albedo_texture
	brass.metallic = 0.8
	brass.roughness = 0.72
	brass.roughness_texture = iron.roughness_texture
	brass.normal_enabled = true
	brass.normal_texture = iron.normal_texture
	brass.normal_scale = 0.28
	brass.emission_enabled = true
	brass.emission = Color("5a2a08")
	brass.emission_energy_multiplier = 0.12
	# Eyes light: a small glow that follows the head.
	var head := e._attach("Head")
	if head:
		e.eye_light = OmniLight3D.new()
		e.eye_light.light_color = Color("6fb6ff")
		e.eye_light.light_energy = 0.06 if e.boss else 0.35
		e.eye_light.omni_range = 1.6
		e.eye_light.position = Vector3(0.0, 0.0, 0.25)
		head.add_child(e.eye_light)
	# A stolen herd bell on a collar.
	if e.bell_index >= 0:
		var neck := e._attach("Neck2")
		if neck:
			var bell := MeshInstance3D.new()
			var bell_mesh := CylinderMesh.new()
			bell_mesh.top_radius = 0.07
			bell_mesh.bottom_radius = 0.12
			bell_mesh.height = 0.18
			bell_mesh.material = brass
			bell.mesh = bell_mesh
			bell.position = Vector3(0.0, -0.32, 0.05)
			neck.add_child(bell)
	if e.role == "rifleman":
		var back := e._attach("Back")
		if back:
			var rifle := MeshInstance3D.new()
			var rifle_mesh := BoxMesh.new()
			rifle_mesh.size = Vector3(0.06, 0.08, 1.05)
			rifle_mesh.material = iron
			rifle.mesh = rifle_mesh
			rifle.position = Vector3(0.0, 0.42, 0.1)
			rifle.rotation_degrees = Vector3(0.0, 0.0, 0.0)
			back.add_child(rifle)
	if e.boss:
		var hero_parent: Node3D = e.boss_shell if is_instance_valid(e.boss_shell) else e
		# Varkas wears the herd's iron: plates, a brutal muzzle cage, and Orin's
		# oversized bell. Half tears away in phase two; Red Horn keeps only a
		# few jagged remnants so the final silhouette still belongs to him.
		for bone in ["Torso", "Torso2", "Torso3"]:
			var spine := e._attach(bone)
			if spine:
				var plate := MeshInstance3D.new()
				var plate_mesh := BoxMesh.new()
				plate_mesh.size = Vector3(0.62, 0.18, 0.5)
				plate_mesh.material = iron
				plate.mesh = plate_mesh
				plate.position = Vector3(0.0, 0.38, 0.0)
				spine.add_child(plate)
				e.boss_armor.append(plate)
				for side in [-1.0, 1.0]:
					var spike := MeshInstance3D.new()
					var spike_mesh := PrismMesh.new()
					spike_mesh.size = Vector3(0.12, 0.34, 0.12)
					spike_mesh.material = iron
					spike.mesh = spike_mesh
					spike.position = Vector3(side * 0.22, 0.58, 0.0)
					spine.add_child(spike)
					if bone == "Torso3" and side > 0.0:
						spike.set_meta("red_horn_remnant", true)
					e.boss_armor.append(spike)
		var neck := e._attach("Neck2")
		if neck:
			var collar := MeshInstance3D.new()
			var collar_mesh := TorusMesh.new()
			collar_mesh.inner_radius = 0.28
			collar_mesh.outer_radius = 0.38
			collar_mesh.rings = 16
			collar_mesh.ring_segments = 8
			collar_mesh.material = iron
			collar.mesh = collar_mesh
			collar.rotation_degrees.x = 90.0
			collar.position = Vector3(0.0, -0.25, 0.02)
			neck.add_child(collar)
			collar.set_meta("red_horn_remnant", true)
			e.boss_armor.append(collar)
			var great_bell := MeshInstance3D.new()
			var great_mesh := CylinderMesh.new()
			great_mesh.top_radius = 0.19
			great_mesh.bottom_radius = 0.34
			great_mesh.height = 0.48
			great_mesh.material = brass
			great_bell.mesh = great_mesh
			great_bell.position = Vector3(0.0, -0.66, 0.12)
			neck.add_child(great_bell)
		var head_rider := e._attach("Head")
		if head_rider:
			# A smooth head ruff, compact muzzle, round ears, and black nose sit on
			# the inherited animated skull. Together with the deformed Blender mesh
			# they replace the source wolf's narrow fox-like closeup silhouette.
			var ruff_mesh := SphereMesh.new()
			ruff_mesh.radius = 0.58
			ruff_mesh.height = 0.94
			ruff_mesh.radial_segments = 24
			ruff_mesh.rings = 12
			ruff_mesh.material = e.body_material
			var ruff := MeshInstance3D.new()
			ruff.name = "VarkasHeadRuff"
			ruff.mesh = ruff_mesh
			ruff.position = Vector3(0.0, 0.01, 0.02)
			ruff.scale = Vector3(1.16, 1.0, 0.8)
			head_rider.add_child(ruff)

			var muzzle_fur_mesh := SphereMesh.new()
			muzzle_fur_mesh.radius = 0.31
			muzzle_fur_mesh.height = 0.5
			muzzle_fur_mesh.radial_segments = 20
			muzzle_fur_mesh.rings = 10
			muzzle_fur_mesh.material = e.body_light_material
			var muzzle_fur := MeshInstance3D.new()
			muzzle_fur.name = "VarkasShortMuzzle"
			muzzle_fur.mesh = muzzle_fur_mesh
			muzzle_fur.position = Vector3(0.0, 0.38, -0.02)
			muzzle_fur.scale = Vector3(1.05, 0.76, 0.92)
			head_rider.add_child(muzzle_fur)

			for side in [-1.0, 1.0]:
				var ear_mesh := SphereMesh.new()
				ear_mesh.radius = 0.115
				ear_mesh.height = 0.2
				ear_mesh.radial_segments = 16
				ear_mesh.rings = 8
				ear_mesh.material = e.body_material
				var round_ear := MeshInstance3D.new()
				round_ear.name = "VarkasRoundEar_%s" % ("L" if side < 0.0 else "R")
				round_ear.mesh = ear_mesh
				round_ear.position = Vector3(side * 0.37, -0.02, 0.32)
				round_ear.scale = Vector3(1.0, 0.92, 0.72)
				head_rider.add_child(round_ear)

			var nose_material := StandardMaterial3D.new()
			nose_material.albedo_color = Color("080706")
			nose_material.roughness = 0.38
			var nose_mesh := SphereMesh.new()
			nose_mesh.radius = 0.13
			nose_mesh.height = 0.18
			nose_mesh.radial_segments = 18
			nose_mesh.rings = 8
			nose_mesh.material = nose_material
			var nose := MeshInstance3D.new()
			nose.name = "VarkasNose"
			nose.mesh = nose_mesh
			nose.position = Vector3(0.0, 0.64, -0.05)
			nose.scale = Vector3(1.18, 0.72, 0.75)
			head_rider.add_child(nose)

			var muzzle := MeshInstance3D.new()
			var muzzle_mesh := BoxMesh.new()
			muzzle_mesh.size = Vector3(0.7, 0.32, 0.5)
			muzzle_mesh.material = iron
			muzzle.mesh = muzzle_mesh
			muzzle.position = Vector3(0.0, 0.43, -0.02)
			head_rider.add_child(muzzle)
			e.boss_armor.append(muzzle)
			for side in [-1.0, 1.0]:
				var cheek_spike := MeshInstance3D.new()
				var cheek_mesh := PrismMesh.new()
				cheek_mesh.size = Vector3(0.16, 0.46, 0.16)
				cheek_mesh.material = iron
				cheek_spike.mesh = cheek_mesh
				cheek_spike.position = Vector3(side * 0.38, 0.08, 0.2)
				cheek_spike.rotation_degrees.z = side * -34.0
				head_rider.add_child(cheek_spike)
				if side < 0.0:
					cheek_spike.set_meta("red_horn_remnant", true)
				e.boss_armor.append(cheek_spike)
			var horn_material := iron.duplicate() as StandardMaterial3D
			horn_material.albedo_color = Color("914633")
			horn_material.metallic = 0.15
			horn_material.roughness = 0.9
			horn_material.normal_scale = 0.35
			horn_material.emission_enabled = true
			horn_material.emission = Color("450b06")
			horn_material.emission_energy_multiplier = 0.2
			e.boss_red_horn = MeshInstance3D.new()
			e.boss_red_horn.name = "RedHornCrown"
			var horn_mesh := _red_horn_mesh(horn_material)
			e.boss_red_horn.mesh = horn_mesh
			e.boss_red_horn.position = Vector3(-0.18, 2.52, -2.94)
			e.boss_red_horn.rotation_degrees = Vector3(0.0, 0.0, -12.0)
			e.boss_red_horn.visible = false
			hero_parent.add_child(e.boss_red_horn)
		# One joined Blender sculpt replaces the separate spherical cheeks and jaw.
		var sculpt := load("res://assets/wolf/varkas_head.glb").instantiate() as Node3D
		sculpt.name = "VarkasSculptedFace"
		hero_parent.add_child(sculpt)
		for part in sculpt.find_children("*", "MeshInstance3D", true, false):
			for surface_index in part.mesh.get_surface_count():
				var source: StandardMaterial3D = part.mesh.surface_get_material(surface_index)
				var fur_material := source.duplicate() as StandardMaterial3D
				fur_material.metallic_specular = 0.15
				if source.resource_name.begins_with("VarkasHead"):
					fur_material.albedo_texture = e.body_material.albedo_texture
					fur_material.uv1_scale = Vector3(2.8, 2.8, 1.0)
					fur_material.albedo_color = Color(3.4, 3.0, 2.3) if source.resource_name == "VarkasHeadCheek" else Color(1.8, 1.65, 1.4)
					fur_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				elif source.resource_name.begins_with("VarkasGuardHair"):
					fur_material.albedo_color *= Color(0.5, 0.47, 0.42, 1.0)
				part.set_surface_override_material(surface_index, fur_material)

		# Uneven shoulder and cheek tufts break the subdivided source mesh's smooth
		# outline. Their dark value makes them read as coarse guard fur, not spikes.
		for side in [-1.0, 1.0]:
			var shoulder_tuft_mesh := PrismMesh.new()
			shoulder_tuft_mesh.size = Vector3(0.24, 0.58 if side < 0.0 else 0.49, 0.2)
			shoulder_tuft_mesh.material = e.body_material
			var shoulder_tuft := MeshInstance3D.new()
			shoulder_tuft.name = "VarkasShoulderTuft_%s" % ("L" if side < 0.0 else "R")
			shoulder_tuft.mesh = shoulder_tuft_mesh
			shoulder_tuft.position = Vector3(side * 0.72, 1.98 + side * 0.035, -1.72)
			shoulder_tuft.rotation_degrees.z = side * -52.0
			hero_parent.add_child(shoulder_tuft)

		var nose_material := StandardMaterial3D.new()
		nose_material.albedo_color = Color("080706")
		nose_material.roughness = 0.34
		var hero_nose_mesh := SphereMesh.new()
		hero_nose_mesh.radius = 0.095
		hero_nose_mesh.height = 0.18
		hero_nose_mesh.radial_segments = 18
		hero_nose_mesh.rings = 8
		hero_nose_mesh.material = nose_material
		var hero_nose := MeshInstance3D.new()
		hero_nose.name = "VarkasHeroNose"
		hero_nose.mesh = hero_nose_mesh
		hero_nose.position = Vector3(0.0, 2.205, -3.18)
		hero_nose.scale = Vector3(1.28, 0.72, 0.72)
		hero_parent.add_child(hero_nose)

		var tooth_material := StandardMaterial3D.new()
		tooth_material.albedo_color = Color("c5baa0")
		tooth_material.roughness = 0.72
		for side in [-1.0, 1.0]:
			var tooth_mesh := CylinderMesh.new()
			tooth_mesh.top_radius = 0.032
			tooth_mesh.bottom_radius = 0.003
			tooth_mesh.height = 0.12
			tooth_mesh.radial_segments = 9
			tooth_mesh.material = tooth_material
			var fang := MeshInstance3D.new()
			fang.name = "VarkasFang_%s" % ("L" if side < 0.0 else "R")
			fang.mesh = tooth_mesh
			fang.position = Vector3(side * 0.15, 2.065, -3.12)
			fang.rotation_degrees.z = side * 7.0
			hero_parent.add_child(fang)

		# Stable root-level eyes sit on the front of the enlarged hero shell. The
		# animated source eyes are too deeply recessed after the skull deformation
		# and disappear in the Iron Crown's hard backlight.
		for side in [-1.0, 1.0]:
			var hero_eye_mesh := SphereMesh.new()
			hero_eye_mesh.radius = 0.025
			hero_eye_mesh.height = 0.038
			hero_eye_mesh.radial_segments = 14
			hero_eye_mesh.rings = 7
			hero_eye_mesh.material = e.eye_material
			var hero_eye := MeshInstance3D.new()
			hero_eye.name = "VarkasHeroEye_%s" % ("L" if side < 0.0 else "R")
			hero_eye.mesh = hero_eye_mesh
			hero_eye.position = Vector3(side * 0.245, 2.355, -3.005)
			hero_parent.add_child(hero_eye)
		# A few root-level hero shapes guarantee that Iron Hide reads at gameplay
		# distance even when the animated rig folds smaller bone-rider plates into
		# Varkas' enlarged torso. They rotate and travel with the boss body.
		var breast_mesh := CylinderMesh.new()
		breast_mesh.top_radius = 0.55
		breast_mesh.bottom_radius = 0.78
		breast_mesh.height = 0.78
		breast_mesh.radial_segments = 8
		var breastplate := _add_boss_armor_piece(e, "IronHideBreastplate", breast_mesh, Vector3(0.0, 1.58, -1.5), iron)
		breastplate.scale.z = 0.24
		for side in [-1.0, 1.0]:
			var shoulder_mesh := PrismMesh.new()
			shoulder_mesh.size = Vector3(0.28, 0.92, 0.3)
			var shoulder := _add_boss_armor_piece(
				e,
				"IronHideShoulder_%s" % ("L" if side < 0.0 else "R"),
				shoulder_mesh,
				Vector3(side * 0.74, 1.98, -1.36),
				iron,
				side < 0.0,
			)
			shoulder.rotation_degrees.z = side * -24.0
		var brow_mesh := CapsuleMesh.new()
		brow_mesh.radius = 0.1
		brow_mesh.height = 0.76
		brow_mesh.radial_segments = 12
		brow_mesh.rings = 4
		var brow := _add_boss_armor_piece(e, "IronHideBrow", brow_mesh, Vector3(-0.13, 2.62, -2.69), iron)
		brow.rotation_degrees.z = 78.0
		brow.scale.z = 0.74
		for side in [-1.0, 1.0]:
			var cage_mesh := CapsuleMesh.new()
			cage_mesh.radius = 0.045
			cage_mesh.height = 0.54
			cage_mesh.radial_segments = 10
			cage_mesh.rings = 3
			var cheek_bar := _add_boss_armor_piece(
				e,
				"IronHideCheekBar_%s" % ("L" if side < 0.0 else "R"),
				cage_mesh,
				Vector3(side * 0.46, 2.34, -2.70),
				iron,
				side > 0.0,
			)
			cheek_bar.rotation_degrees.z = side * -12.0
		var orin_bell := MeshInstance3D.new()
		orin_bell.name = "OrinsGreatBell"
		var orin_mesh := CylinderMesh.new()
		orin_mesh.top_radius = 0.24
		orin_mesh.bottom_radius = 0.42
		orin_mesh.height = 0.58
		orin_mesh.radial_segments = 18
		orin_mesh.material = brass
		orin_bell.mesh = orin_mesh
		orin_bell.position = Vector3(0.0, 1.12, -1.7)
		orin_bell.rotation_degrees.x = -10.0
		hero_parent.add_child(orin_bell)
		_build_boss_embers(e)
		_build_boss_aura(e)


static func _build_boss_embers(e: WolverineEnemy) -> void:
	e.boss_embers = GPUParticles3D.new()
	e.boss_embers.name = "RedHornEmbers"
	e.boss_embers.amount = 150
	e.boss_embers.amount_ratio = 0.0
	e.boss_embers.lifetime = 1.25
	e.boss_embers.randomness = 0.72
	e.boss_embers.visibility_aabb = AABB(Vector3(-2.0, -0.5, -2.5), Vector3(4.0, 4.0, 5.0))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(0.85, 0.8, 1.05)
	motion.direction = Vector3(0.0, 0.8, 0.18)
	motion.spread = 48.0
	motion.initial_velocity_min = 0.35
	motion.initial_velocity_max = 1.4
	motion.gravity = Vector3(0.0, -0.35, 0.0)
	motion.scale_min = 0.45
	motion.scale_max = 1.2
	e.boss_embers.process_material = motion
	var mote := QuadMesh.new()
	mote.size = Vector2(0.034, 0.034)
	var mote_material := StandardMaterial3D.new()
	mote_material.albedo_color = Color("a91c14")
	mote_material.emission_enabled = true
	mote_material.emission = Color("7a0b08")
	mote_material.emission_energy_multiplier = 2.1
	mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.material = mote_material
	e.boss_embers.draw_pass_1 = mote
	e.add_child(e.boss_embers)


static func _build_boss_aura(e: WolverineEnemy) -> void:
	e.boss_aura = OmniLight3D.new()
	e.boss_aura.name = "VarkasPhaseLight"
	e.boss_aura.position = Vector3(0.0, 0.45, 0.18)
	e.boss_aura.light_color = Color("6f9fcc")
	e.boss_aura.light_energy = 0.25
	e.boss_aura.omni_range = 2.6
	e.boss_aura.omni_attenuation = 1.45
	e.boss_aura.shadow_enabled = true
	e.add_child(e.boss_aura)


static func _add_boss_armor_piece(
	e: WolverineEnemy,
	piece_name: String,
	piece_mesh: PrimitiveMesh,
	piece_position: Vector3,
	piece_material: Material,
	red_horn_remnant := false,
) -> MeshInstance3D:
	piece_mesh.material = piece_material
	var piece := MeshInstance3D.new()
	piece.name = piece_name
	piece.mesh = piece_mesh
	piece.position = piece_position
	if red_horn_remnant:
		piece.set_meta("red_horn_remnant", true)
	if e.boss and is_instance_valid(e.boss_shell):
		e.boss_shell.add_child(piece)
	else:
		e.add_child(piece)
	e.boss_armor.append(piece)
	return piece


static func _red_horn_mesh(horn_material: Material) -> ArrayMesh:
	# Four uneven rings form a short, scarred hook instead of a pristine cone.
	# The bend is part of the mesh, so the silhouette stays readable when Varkas
	# turns during his final charge.
	var centers: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.025, 0.2, -0.006),
		Vector3(0.072, 0.38, -0.018),
		Vector3(0.25, 0.48, -0.09),
	]
	var radii: Array[float] = [0.105, 0.082, 0.048, 0.008]
	var sides := 7
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(horn_material)
	for ring in centers.size() - 1:
		for side in sides:
			var next := (side + 1) % sides
			var angle := TAU * side / sides + ring * 0.14
			var next_angle := TAU * next / sides + ring * 0.14
			var upper_angle := TAU * side / sides + (ring + 1) * 0.14
			var upper_next_angle := TAU * next / sides + (ring + 1) * 0.14
			var p0: Vector3 = centers[ring] + Vector3(cos(angle) * radii[ring], 0.0, sin(angle) * radii[ring])
			var p1: Vector3 = centers[ring] + Vector3(cos(next_angle) * radii[ring], 0.0, sin(next_angle) * radii[ring])
			var q0: Vector3 = centers[ring + 1] + Vector3(cos(upper_angle) * radii[ring + 1], 0.0, sin(upper_angle) * radii[ring + 1])
			var q1: Vector3 = centers[ring + 1] + Vector3(cos(upper_next_angle) * radii[ring + 1], 0.0, sin(upper_next_angle) * radii[ring + 1])
			var points := [p0, p1, q1, p0, q1, q0]
			var uvs := [Vector2(side, ring), Vector2(side + 1, ring), Vector2(side + 1, ring + 1), Vector2(side, ring), Vector2(side + 1, ring + 1), Vector2(side, ring + 1)]
			for index in points.size():
				tool.set_uv(uvs[index] / Vector2(sides, centers.size() - 1))
				tool.add_vertex(points[index])
	for side in sides:
		var next := (side + 1) % sides
		tool.add_vertex(Vector3.ZERO)
		tool.add_vertex(Vector3(cos(TAU * next / sides) * radii[0], 0.0, sin(TAU * next / sides) * radii[0]))
		tool.add_vertex(Vector3(cos(TAU * side / sides) * radii[0], 0.0, sin(TAU * side / sides) * radii[0]))
	tool.generate_normals()
	return tool.commit()


static func apply_phase(e: WolverineEnemy) -> void:
	if not e.boss:
		return
	for index in e.boss_armor.size():
		var plate := e.boss_armor[index]
		if is_instance_valid(plate):
			plate.visible = e.boss_phase == 1 or (e.boss_phase == 2 and index % 2 == 1) or (e.boss_phase == 3 and plate.get_meta("red_horn_remnant", false))
	if e.body_material:
		# Fur pigment is now in the texture. Keep phase tint light enough to
		# preserve its strands instead of multiplying two near-black colors.
		e.body_material.albedo_color = Color("ffffff") if e.boss_phase == 1 else (Color("ffe1cd") if e.boss_phase == 2 else Color("ffc1aa"))
	if e.body_light_material:
		e.body_light_material.albedo_color = Color(1.5, 1.35, 1.15) if e.boss_phase == 1 else (Color(1.5, 1.15, 0.95) if e.boss_phase == 2 else Color(1.5, 0.95, 0.8))
	if e.eye_material:
		e.eye_material.emission = Color("6fb6ff") if e.boss_phase == 1 else Color("ff321f")
		e.eye_material.emission_energy_multiplier = 0.65 if e.boss_phase == 1 else 1.5
	if e.eye_light:
		e.eye_light.light_color = Color("6fb6ff") if e.boss_phase == 1 else Color("ff321f")
		e.eye_light.light_energy = 0.035 if e.boss_phase == 1 else 0.12
	if is_instance_valid(e.boss_embers):
		e.boss_embers.amount_ratio = 0.0 if e.boss_phase == 1 else (0.26 if e.boss_phase == 2 else 1.0)
	if is_instance_valid(e.boss_aura):
		e.boss_aura.light_color = Color("6f9fcc") if e.boss_phase == 1 else (Color("b84928") if e.boss_phase == 2 else Color("ef321f"))
		e.boss_aura.light_energy = 0.2 if e.boss_phase == 1 else (0.6 if e.boss_phase == 2 else 1.05)
		e.boss_aura.omni_range = 2.4 if e.boss_phase == 1 else (3.2 if e.boss_phase == 2 else 4.2)
	if is_instance_valid(e.boss_red_horn):
		e.boss_red_horn.visible = e.boss_phase >= 3


## A small, dark spray on impact and one ground stain on a fatal hit. The effect
## is intentionally brief and stylised; it supports the grittier tone without
## turning every encounter into a particle fog.
static func spawn_blood(e: WolverineEnemy, amount: int, fatal: bool) -> void:
	if not e.is_inside_tree():
		return
	var spray := GPUParticles3D.new()
	spray.name = "BloodSpray"
	spray.amount = 16 if fatal else clampi(4 + amount / 28, 5, 10)
	spray.lifetime = 0.65
	spray.one_shot = true
	spray.explosiveness = 1.0
	spray.position = Vector3(0.0, 0.75 if e.boss else 0.48, 0.0)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.55, 0.6)
	process.spread = 72.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.6 if fatal else 2.3
	process.gravity = Vector3(0.0, -8.5, 0.0)
	process.scale_min = 0.5
	process.scale_max = 1.35
	spray.process_material = process
	var drop := QuadMesh.new()
	drop.size = Vector2(0.045, 0.045)
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color("7e0d0a")
	blood.emission_enabled = true
	blood.emission = Color("3a0303")
	blood.emission_energy_multiplier = 0.35
	blood.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blood.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	drop.material = blood
	spray.draw_pass_1 = drop
	e.add_child(spray)
	spray.emitting = true
	var cleanup := spray.create_tween()
	cleanup.tween_interval(1.6)
	cleanup.tween_callback(spray.queue_free)
	if not fatal or e.get_parent() == null:
		return
	var stain := MeshInstance3D.new()
	stain.name = "BloodStain"
	var stain_mesh := PlaneMesh.new()
	stain_mesh.size = Vector2(1.45 if e.boss else 0.72, 0.9 if e.boss else 0.48)
	var stain_material := StandardMaterial3D.new()
	stain_material.albedo_color = Color(0.19, 0.005, 0.004, 0.72)
	stain_material.roughness = 0.98
	stain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stain_mesh.material = stain_material
	stain.mesh = stain_mesh
	stain.position = Vector3(e.global_position.x, e.global_position.y + 0.035, e.global_position.z)
	stain.rotation.y = e.phase
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.get_parent().add_child(stain)


static func _find(node: Node, type_name: String) -> Node:
	var stack := [node]
	while stack:
		var current: Node = stack.pop_back()
		if current.get_class() == type_name:
			return current
		stack.append_array(current.get_children())
	return null
