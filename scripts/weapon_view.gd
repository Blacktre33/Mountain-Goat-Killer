class_name WeaponView
extends Node3D
## First-person rig for the Herdkeeper: Maren's carbine and two gloved forearms.
## Everything is procedural. The player feeds it movement state each frame and
## triggers one-shot gestures (bolt, reload, hang a round, horn strike, stone
## throw); the rig composes them over idle breath, walk bob, look inertia and
## recoil springs. Audio and shell ejection leave through signals.

signal cue(sound: String, volume_db: float)
signal casing_ejected(at: Transform3D, velocity: Vector3)
signal magazine_dropped(at: Transform3D, velocity: Vector3)

const CARBINE := preload("res://assets/weapon/herdkeeper.glb")
const GLOVE := preload("res://assets/weapon/glove.glb")
const FLASH_TEXTURE := preload("res://assets/weapon/fx/muzzle_flash.png")
const SMOKE_TEXTURE := preload("res://assets/weapon/fx/smoke_puff.png")

enum Gesture { NONE, BOLT, RELOAD, DRY, HANG, TAKEDOWN, THROW, EQUIP }

## Viewmodel meshes live on their own visual layer so a private fill light can lift
## them out of snow-blue shadow without touching the world.
const VIEWMODEL_LAYER := 2
const FILL_ENERGY := 0.7
## Firelight turns the olive jacket orange; a cool multiply keeps it cloth.
const GLOVE_TINT := Color(0.7, 0.78, 0.82)
const METAL_STRENGTH := 0.6
const METAL_SPECULAR := 0.35
## Multiplies the generated roughness map so polished spots stop mirroring the sky.
const ROUGHNESS_SCALE := 1.7

## The short handle rests turned down to the right, clear of the sight picture, and
## lifts upright to cycle.
## The rig reads a touch larger than life so the carbine holds the lower right of a
## 68 degree frame.
const GUN_SCALE := 1.18
const BOLT_REST_ROLL := -1.0
const BOLT_LIFT_ROLL := 1.0

const HIP_POS := Vector3(0.15, -0.155, -0.36)
const HIP_ROT := Vector3(0.02, 0.06, 0.02)
## Rear sight top sits on the optical axis; the front blade tip lands on the crosshair.
const ADS_POS := Vector3(0.0, -0.0045, -0.37)
const SPRINT_POS := Vector3(0.10, -0.21, -0.40)
const SPRINT_ROT := Vector3(-0.30, 0.70, 0.14)
const CROUCH_POS := Vector3(0.0, -0.012, 0.012)
const WALL_POS := Vector3(0.03, -0.09, 0.20)
const WALL_ROT := Vector3(0.62, 0.18, 0.0)

## Hand placement in gun space: the fist centre, roll about the forearm, yaw.
const RIGHT_HAND_POS := Vector3(0.012, -0.108, 0.285)
const RIGHT_HAND_ROT := Vector3(0.22, 0.0, 0.0)
const LEFT_HAND_POS := Vector3(-0.012, -0.105, -0.20)
const LEFT_HAND_ROT := Vector3(0.55, -0.32, PI)
const MAG_POS := Vector3(0.0, -0.07, 0.11)

var gun: Node3D
var body: Node3D
var bolt: Node3D
var bell: Node3D
var magazine: Node3D
var right_hand: Node3D
var left_hand: Node3D
var muzzle: Node3D
var eject_port: Node3D
var held_stone: MeshInstance3D
var held_magazine: Node3D
var flash_light: OmniLight3D
var fill: OmniLight3D
var flash_quads: Array[MeshInstance3D] = []
var smoke_quads: Array[MeshInstance3D] = []
var next_smoke := 0
var smoke_life: Array[float] = [0.0, 0.0, 0.0, 0.0]
var flash_time := 0.0

## Inputs the player refreshes every frame.
var ads := 0.0
var sprint := 0.0
var crouch := 0.0
var wall := 0.0
var walk_phase := 0.0
var bob_amount := 0.0
var sprint_bob := 0.0
var local_velocity := Vector3.ZERO
var look_rate := Vector2.ZERO

var gesture := Gesture.NONE
var gesture_time := 0.0
var gesture_length := 1.0
var gesture_cues: Dictionary = {}
var bolt_pull := 0.0
var bolt_roll := 0.0
var recoil_z := 0.0
var recoil_pitch := 0.0
var recoil_z_velocity := 0.0
var recoil_pitch_velocity := 0.0
var landing := 0.0
var landing_velocity := 0.0
var sway := Vector2.ZERO
var sway_velocity := Vector2.ZERO
var lag := Vector3.ZERO
var lag_velocity := Vector3.ZERO
var breath_time := 0.0
var bell_swing := 0.0
var bell_swing_velocity := 0.0
var left_offset := Vector3.ZERO
var left_yaw := 0.0
var right_offset := Vector3.ZERO
var right_pitch := 0.0
var mag_offset := Vector3.ZERO
var mag_visible := true
var left_roll := PI
var right_roll := 0.0
var bolt_home := Vector3.ZERO
var mag_home := Vector3.ZERO


func _ready() -> void:
	name = "Herdkeeper"
	_build()
	position = HIP_POS
	play_equip()


func _build() -> void:
	gun = Node3D.new()
	gun.name = "Gun"
	gun.scale = Vector3.ONE * GUN_SCALE
	add_child(gun)
	var carbine: Node3D = CARBINE.instantiate()
	gun.add_child(carbine)
	body = carbine.find_child("Body", true, false)
	bolt = carbine.find_child("Bolt", true, false)
	bell = carbine.find_child("Bell", true, false)
	magazine = carbine.find_child("Magazine", true, false)
	muzzle = carbine.find_child("Muzzle", true, false)
	eject_port = carbine.find_child("EjectPort", true, false)
	bolt_home = bolt.position
	mag_home = magazine.position
	right_hand = _build_hand("RightHand", false)
	left_hand = _build_hand("LeftHand", true)
	held_magazine = magazine.duplicate()
	held_magazine.name = "HeldMagazine"
	held_magazine.visible = false
	left_hand.add_child(held_magazine)
	held_magazine.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, -0.02))

	held_stone = MeshInstance3D.new()
	held_stone.name = "HeldStone"
	var stone_mesh := SphereMesh.new()
	stone_mesh.radius = 0.034
	stone_mesh.height = 0.062
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color("5c6166")
	stone_material.roughness = 0.95
	stone_mesh.material = stone_material
	held_stone.mesh = stone_mesh
	held_stone.position = Vector3(0.0, 0.02, -0.08)
	held_stone.visible = false
	right_hand.add_child(held_stone)

	_prepare_meshes(self)
	_build_flash()
	fill = OmniLight3D.new()
	fill.name = "ViewmodelFill"
	fill.light_color = Color("dfe8f5")
	fill.light_energy = FILL_ENERGY
	fill.omni_range = 2.2
	fill.light_cull_mask = VIEWMODEL_LAYER
	fill.shadow_enabled = false
	fill.position = Vector3(-0.2, -0.05, 0.25)
	add_child(fill)


func _build_hand(hand_name: String, mirrored: bool) -> Node3D:
	var hand := Node3D.new()
	hand.name = hand_name
	var glove: Node3D = GLOVE.instantiate()
	hand.add_child(glove)
	for node in glove.find_children("*", "MeshInstance3D", true, false):
		var cloth := node as MeshInstance3D
		for surface in cloth.mesh.get_surface_count():
			var tinted := cloth.get_active_material(surface).duplicate() as StandardMaterial3D
			tinted.albedo_color = GLOVE_TINT
			cloth.set_surface_override_material(surface, tinted)
	if mirrored:
		glove.scale.x = -1.0
	gun.add_child(hand)
	return hand


func _prepare_meshes(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mesh_node.extra_cull_margin = 2.0
		mesh_node.layers = VIEWMODEL_LAYER
		# Full-strength generated metal mirrors the bright sky like chrome; a lower
		# metallic and specular keeps blued steel and brass reading as worn metal.
		for surface in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var tuned := source.duplicate() as StandardMaterial3D
			tuned.metallic = minf(source.metallic, METAL_STRENGTH)
			tuned.metallic_specular = METAL_SPECULAR
			tuned.roughness = ROUGHNESS_SCALE
			mesh_node.set_surface_override_material(surface, tuned)


func _flash_material(texture: Texture2D, additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.albedo_texture = texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material


func _build_flash() -> void:
	var flash_root := Node3D.new()
	flash_root.name = "MuzzleFlash"
	muzzle.add_child(flash_root)
	# A ragged star, a tight core and a forward jet; billboarded so the flash
	# always faces the eye whatever the pose.
	var sizes := [0.46, 0.22, 0.30]
	for i in sizes.size():
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * sizes[i]
		mesh.material = _flash_material(FLASH_TEXTURE, true)
		quad.mesh = mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.position = Vector3(0.0, 0.0, -0.04 * i)
		quad.visible = false
		flash_root.add_child(quad)
		flash_quads.append(quad)
	for i in smoke_life.size():
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * 0.18
		mesh.material = _flash_material(SMOKE_TEXTURE, false)
		quad.mesh = mesh
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.visible = false
		quad.top_level = true
		flash_root.add_child(quad)
		smoke_quads.append(quad)
	flash_light = OmniLight3D.new()
	flash_light.name = "MuzzleLight"
	flash_light.light_color = Color("ffb44f")
	flash_light.light_energy = 0.0
	flash_light.omni_range = 6.0
	# The flash lights the world; the hands get only a small share through the fill.
	flash_light.light_cull_mask = 1
	flash_light.position = Vector3(0.0, 0.03, -0.25)
	flash_root.add_child(flash_light)


# --- One-shot gestures ---------------------------------------------------------------

func is_busy() -> bool:
	return gesture in [Gesture.RELOAD, Gesture.HANG, Gesture.TAKEDOWN, Gesture.THROW, Gesture.EQUIP]


func _start(kind: int, length: float, cues := {}) -> void:
	gesture = kind
	gesture_time = 0.0
	gesture_length = maxf(0.05, length)
	gesture_cues = cues.duplicate()
	held_stone.visible = false
	held_magazine.visible = false
	mag_visible = true


func cancel_gesture() -> void:
	gesture = Gesture.NONE
	gesture_time = 0.0
	held_stone.visible = false
	held_magazine.visible = false
	mag_visible = true
	left_offset = Vector3.ZERO
	right_offset = Vector3.ZERO
	mag_offset = Vector3.ZERO
	bolt_pull = 0.0


func play_equip() -> void:
	_start(Gesture.EQUIP, 0.7, {0.12: "equip"})


func play_reload(duration: float) -> void:
	_start(Gesture.RELOAD, duration, {0.02: "reload", 0.36: "mag_out", 0.72: "mag_in", 0.80: "bolt_open", 0.90: "bolt_close"})


func play_dry() -> void:
	if not is_busy():
		_start(Gesture.DRY, 0.22)


func play_hang() -> void:
	_start(Gesture.HANG, 0.5)


func play_takedown() -> void:
	_start(Gesture.TAKEDOWN, 0.55)


func play_throw(duration: float) -> void:
	_start(Gesture.THROW, duration)


## Recoil kick, flash and smoke; the bolt cycles on its own afterwards.
func fire(aiming: bool) -> void:
	recoil_z_velocity += 0.55 if aiming else 0.85
	recoil_pitch_velocity += 3.4 if aiming else 5.2
	sway_velocity += Vector2(randf_range(-0.6, 0.6), randf_range(0.2, 0.8))
	bell_swing_velocity += randf_range(-5.0, 5.0)
	flash_time = 0.075
	for i in flash_quads.size():
		var quad := flash_quads[i]
		quad.visible = true
		quad.rotation.z = randf() * TAU
		quad.scale = Vector3.ONE * randf_range(0.85, 1.25)
	flash_light.light_energy = 7.0
	_spawn_smoke()
	if gesture == Gesture.NONE:
		_start(Gesture.BOLT, 0.14)


func _spawn_smoke() -> void:
	var quad := smoke_quads[next_smoke]
	smoke_life[next_smoke] = 0.7
	next_smoke = (next_smoke + 1) % smoke_quads.size()
	quad.global_position = muzzle.global_position
	quad.scale = Vector3.ONE * 0.5
	quad.visible = true


func muzzle_position() -> Vector3:
	return muzzle.global_position


func kick_landing(strength: float) -> void:
	landing_velocity -= strength * 4.0


# --- Per frame ---------------------------------------------------------------------------

func tick(delta: float) -> void:
	breath_time += delta
	# Explicit springs blow up on a long frame; integrate in small fixed steps.
	var steps := clampi(ceili(delta / 0.008), 1, 12)
	for _i in steps:
		_step_springs(minf(delta, 0.1) / steps)
	_step_flash(delta)
	_step_gesture(delta)

	var idle := Vector3(sin(breath_time * 1.15) * 0.0016, sin(breath_time * 1.7) * 0.0026, 0.0)
	var idle_rot := Vector3(sin(breath_time * 1.7) * 0.0022, sin(breath_time * 0.9) * 0.0018, sin(breath_time * 1.15) * 0.003)
	# Aiming steadies the breath into a slow figure eight the player can lead.
	idle *= lerpf(1.0, 0.45, ads)
	idle_rot *= lerpf(1.0, 0.55, ads)

	var pos := HIP_POS.lerp(ADS_POS, ads)
	var rot := HIP_ROT.lerp(Vector3.ZERO, ads)
	pos = pos.lerp(SPRINT_POS, sprint)
	rot = rot.lerp(SPRINT_ROT, sprint)
	pos += CROUCH_POS * crouch
	pos = pos.lerp(pos + WALL_POS - Vector3(0.0, 0.0, 0.0), wall * (1.0 - ads * 0.6))
	rot += WALL_ROT * wall * (1.0 - ads * 0.6)

	# Walk bob: figure-eight in x/y plus roll, quieter while aiming.
	var bob_gain := bob_amount * lerpf(1.0, 0.22, ads)
	var phase := walk_phase
	var bob_scale := 1.0 + sprint_bob * 1.1
	pos.x += sin(phase) * 0.012 * bob_gain * bob_scale
	pos.y += (sin(phase * 2.0 + 0.6) * 0.010 - 0.004) * bob_gain * bob_scale
	pos.z += sin(phase * 2.0) * 0.006 * bob_gain * bob_scale
	rot.z += sin(phase) * 0.028 * bob_gain * bob_scale
	rot.x += sin(phase * 2.0 + 1.2) * 0.012 * bob_gain * bob_scale
	rot.y += sin(phase + 0.7) * 0.014 * bob_gain * bob_scale

	# Movement lean and look inertia.
	pos.x += -local_velocity.x * 0.0035 * (1.0 - ads * 0.7)
	pos.z += local_velocity.z * 0.0028 * (1.0 - ads * 0.7)
	rot.z += -local_velocity.x * 0.0032 * (1.0 - ads * 0.5)
	pos += lag * lerpf(1.0, 0.4, ads)
	rot.y += sway.x
	rot.x += sway.y

	pos.z += recoil_z
	pos.y += landing
	rot.x += recoil_pitch

	var kick := _gesture_pose()
	pos += kick.pos
	rot += kick.rot
	position = pos + idle
	rotation = rot + idle_rot

	_apply_parts()


func _step_springs(delta: float) -> void:
	# Damped springs keep recoil, landing dip and look sway from feeling canned.
	recoil_z_velocity += (-recoil_z * 340.0 - recoil_z_velocity * 24.0) * delta
	recoil_z += recoil_z_velocity * delta
	recoil_pitch_velocity += (-recoil_pitch * 260.0 - recoil_pitch_velocity * 19.0) * delta
	recoil_pitch += recoil_pitch_velocity * delta
	landing_velocity += (-landing * 210.0 - landing_velocity * 15.0) * delta
	landing += landing_velocity * delta
	# look_rate is the camera's turn rate in rad/s (x: yaw left, y: pitch up); the
	# carbine lags the opposite way and springs back.
	var target := Vector2(-look_rate.x * 0.016, -look_rate.y * 0.014)
	target = target.clamp(Vector2(-0.085, -0.06), Vector2(0.085, 0.06))
	sway_velocity += ((target - sway) * 120.0 - sway_velocity * 13.0) * delta
	sway += sway_velocity * delta
	var lag_target := Vector3(look_rate.x * 0.006, -look_rate.y * 0.006, 0.0).limit_length(0.035)
	lag_velocity += ((lag_target - lag) * 90.0 - lag_velocity * 11.0) * delta
	lag += lag_velocity * delta
	bell_swing_velocity += (-bell_swing * 90.0 - bell_swing_velocity * 4.5) * delta
	bell_swing_velocity += (-local_velocity.x * 0.06 + local_velocity.z * 0.02 * sin(walk_phase * 2.0)) * delta * 20.0
	bell_swing += bell_swing_velocity * delta
	bell_swing = clampf(bell_swing, -0.9, 0.9)


func _step_flash(delta: float) -> void:
	if flash_time > 0.0:
		flash_time -= delta
		var fade := clampf(flash_time / 0.075, 0.0, 1.0)
		for quad in flash_quads:
			quad.visible = flash_time > 0.0
			(quad.mesh as QuadMesh).material.albedo_color = Color(1.0, 0.78 + fade * 0.2, 0.5 + fade * 0.3, fade)
	flash_light.light_energy = lerpf(flash_light.light_energy, 0.0, 1.0 - exp(-38.0 * delta))
	fill.light_energy = FILL_ENERGY + flash_light.light_energy * 0.1
	for i in smoke_quads.size():
		if smoke_life[i] <= 0.0:
			continue
		smoke_life[i] -= delta
		var quad := smoke_quads[i]
		var age := 1.0 - clampf(smoke_life[i] / 0.7, 0.0, 1.0)
		quad.global_position += Vector3(0.05, 0.16, 0.0) * delta + Vector3(0.0, 0.0, -0.06) * delta
		quad.scale = Vector3.ONE * (0.5 + age * 1.6)
		(quad.mesh as QuadMesh).material.albedo_color = Color(0.72, 0.74, 0.78, (1.0 - age) * 0.34)
		quad.visible = smoke_life[i] > 0.0


func _step_gesture(delta: float) -> void:
	if gesture == Gesture.NONE:
		bolt_pull = move_toward(bolt_pull, 0.0, delta * 8.0)
		return
	var before := gesture_time
	gesture_time += delta
	var u := clampf(gesture_time / gesture_length, 0.0, 1.0)
	var u_before := clampf(before / gesture_length, 0.0, 1.0)
	for at in gesture_cues:
		if u_before < float(at) and u >= float(at):
			cue.emit(gesture_cues[at], -4.0)
	if gesture == Gesture.BOLT and u_before < 0.35 and u >= 0.35:
		var to_world := eject_port.global_transform
		var side := to_world.basis.x * randf_range(1.7, 2.4)
		casing_ejected.emit(to_world, side + to_world.basis.y * randf_range(1.2, 1.9) - to_world.basis.z * randf_range(0.1, 0.5))
	if gesture == Gesture.RELOAD and u_before < 0.34 and u >= 0.34:
		var mag_world := magazine.global_transform
		magazine_dropped.emit(mag_world, -mag_world.basis.y * 1.2 + mag_world.basis.x * 0.4)
	if u >= 1.0:
		gesture = Gesture.NONE
		gesture_time = 0.0
		held_stone.visible = false
		held_magazine.visible = false
		mag_visible = true


static func _seg(u: float, a: float, b: float) -> float:
	return smoothstep(a, b, u)


## Pose offsets the current gesture adds on top of the base pose, plus hand and
## bolt targets. Returns {pos, rot}; hand and part offsets are written to fields.
func _gesture_pose() -> Dictionary:
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var u := clampf(gesture_time / gesture_length, 0.0, 1.0)
	var left := Vector3.ZERO
	var left_turn := 0.0
	var right := Vector3.ZERO
	var right_tilt := 0.0
	var mag := Vector3.ZERO
	var pull := 0.0
	var roll := 0.0
	mag_visible = true
	held_stone.visible = false
	held_magazine.visible = false

	match gesture:
		Gesture.BOLT:
			# Handle flicks up and back, then home; fast enough for the fire rate.
			pull = _seg(u, 0.0, 0.32) - _seg(u, 0.5, 0.95)
			roll = pull
			right += Vector3(0.0, 0.0, 0.03) * pull
		Gesture.DRY:
			var press := sin(u * PI)
			rot.x += 0.012 * press
			pos.z += 0.008 * press
		Gesture.EQUIP:
			var rise := 1.0 - _seg(u, 0.0, 0.85)
			pos += Vector3(0.05, -0.34, 0.12) * rise
			rot += Vector3(-0.6, 0.35, 0.3) * rise
		Gesture.RELOAD:
			var tilt := _seg(u, 0.0, 0.15) - _seg(u, 0.84, 1.0)
			pos += Vector3(-0.12, 0.12, 0.0) * tilt
			rot += Vector3(0.30, 0.30, -0.72) * tilt
			# The right arm falls back out of the frame so the magazine well reads.
			right += Vector3(0.07, -0.13, 0.12) * tilt
			# Left hand: forend -> magazine well -> down for a fresh magazine -> back up.
			var to_well := _seg(u, 0.06, 0.20)
			var down := _seg(u, 0.36, 0.48) - _seg(u, 0.52, 0.66)
			var to_forend := _seg(u, 0.76, 0.90)
			left = (Vector3(0.0, 0.07, 0.30) * to_well + Vector3(-0.02, -0.34, 0.06) * down) * (1.0 - to_forend)
			left_turn = -0.4 * to_well * (1.0 - to_forend)
			# Old magazine slides out; the fresh one rides up with the hand.
			var out := _seg(u, 0.26, 0.36)
			var fresh := _seg(u, 0.60, 0.72)
			if u < 0.34:
				mag = Vector3(0.0, -0.13, 0.02) * out
			else:
				mag_visible = u > 0.72
				mag = Vector3(0.0, -0.13, 0.02) * (1.0 - fresh)
				held_magazine.visible = u > 0.44 and u <= 0.72
			# Bolt: right hand racks it after the magazine seats.
			pull = _seg(u, 0.78, 0.86) - _seg(u, 0.88, 0.96)
			roll = pull
			right += Vector3(0.0, 0.02, 0.05) * pull
		Gesture.HANG:
			var reach := _seg(u, 0.0, 0.32) - _seg(u, 0.62, 1.0)
			pos += Vector3(0.0, 0.03, 0.0) * reach
			rot += Vector3(0.10, 0.0, 0.0) * reach
			left = Vector3(0.0, 0.07, -0.13) * reach
			left_turn = 0.3 * reach
			held_magazine.visible = false
		Gesture.TAKEDOWN:
			var wind := _seg(u, 0.0, 0.24)
			var strike := _seg(u, 0.24, 0.38)
			var recover := _seg(u, 0.5, 1.0)
			var amount := (wind * -0.35 + strike * 1.35) * (1.0 - recover)
			pos += Vector3(-0.10, 0.06, 0.0) * wind * (1.0 - strike) + Vector3(-0.12, 0.10, -0.34) * strike * (1.0 - recover)
			rot += Vector3(0.45, 0.55, -0.35) * amount
			rot.x -= 0.25 * strike * (1.0 - recover)
		Gesture.THROW:
			var wind_up := _seg(u, 0.0, 0.38)
			var release := _seg(u, 0.38, 0.52)
			var back := _seg(u, 0.6, 1.0)
			pos += Vector3(-0.05, -0.05, 0.04) * (wind_up - back)
			rot += Vector3(-0.10, 0.10, 0.10) * (wind_up - back)
			right = (Vector3(0.05, 0.06, 0.24) * wind_up + Vector3(-0.05, 0.10, -0.55) * release) * (1.0 - back)
			right_tilt = (-0.7 * wind_up + 1.1 * release) * (1.0 - back)
			held_stone.visible = u < 0.5

	# The right forearm drops out of the sight picture when aiming.
	right += Vector3(0.03, -0.055, 0.07) * ads
	left_offset = left
	left_yaw = left_turn
	right_offset = right
	right_pitch = right_tilt
	mag_offset = mag
	bolt_pull = pull
	bolt_roll = roll
	return {"pos": pos, "rot": rot}


func _apply_parts() -> void:
	right_hand.transform = Transform3D(Basis.from_euler(RIGHT_HAND_ROT + Vector3(right_pitch, 0.0, right_roll)), RIGHT_HAND_POS + right_offset)
	left_hand.transform = Transform3D(Basis.from_euler(Vector3(LEFT_HAND_ROT.x, LEFT_HAND_ROT.y + left_yaw, left_roll)), LEFT_HAND_POS + left_offset)
	# The bolt handle lifts about the bore axis and slides back.
	bolt.rotation = Vector3(0.0, 0.0, BOLT_REST_ROLL + bolt_roll * BOLT_LIFT_ROLL)
	bolt.position = bolt_home + Vector3(0.0, 0.0, bolt_pull * 0.085)
	magazine.visible = mag_visible
	magazine.position = mag_home + mag_offset
	bell.rotation = Vector3(bell_swing, 0.0, 0.0)
