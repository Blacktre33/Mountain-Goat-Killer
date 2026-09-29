class_name GoatPlayer
extends CharacterBody3D

signal ammo_changed(current: int, reserve: int)
signal health_changed(current: int)
signal controls_changed(captured: bool)
signal remembrance_changed(hung: int, capacity: int, sensing: bool)
signal notice(text: String, seconds: float)
signal interact_pressed
signal noise_made(source: Vector3, radius: float)
## Bearing of whatever hurt the goat, in radians clockwise from straight ahead
## (NAN when unknown), for the damage indicator.
signal damaged(bearing: float, amount: int)
## "hit", "headshot" or "kill": drives the crosshair hit marker.
signal hit_confirmed(kind: String)
signal died

const WALK_SPEED := 5.4
const CROUCH_SPEED := 2.4
const SPRINT_SPEED := 8.4
const AIM_SPEED := 3.4
## Ground response: snappy start, firm stop; turning against momentum brakes harder.
const GROUND_ACCELERATION := 44.0
const SPRINT_ACCELERATION := 24.0
const GROUND_BRAKING := 46.0
const SPRINT_BRAKING := 30.0
const OPPOSING_BOOST := 1.6
const AIR_ACCELERATION := 6.0
const AIR_DRAG := 0.8
const JUMP_VELOCITY := 7.2
## Releasing jump early trims the rise to this speed.
const JUMP_CUT_SPEED := 3.2
const FALL_GRAVITY_SCALE := 1.22
const JUMP_BUFFER_SECONDS := 0.12
## Grace period after stepping off a ledge during which a jump still counts.
const COYOTE_SECONDS := 0.12
const STEP_HEIGHT := 0.42
const FLOOR_MAX_ANGLE := 50.0
const MAGAZINE_SIZE := 24
const RESERVE_CAP := 160
const RELOAD_SECONDS := 1.05
const FIRE_INTERVAL := 0.14
const THROW_SECONDS := 0.5
const THROW_RELEASE_SECONDS := 0.2
const HIP_FOV := 68.0
const SPRINT_FOV := 74.0
const AIM_FOV := 54.0
const STAND_HEAD := 0.66
const CROUCH_HEAD := 0.12
## Second wind: after a quiet spell, will returns up to a ceiling.
const REGEN_DELAY := 4.5
const REGEN_PER_SECOND := 7.0
const REGEN_CAP := 55
const LOW_HEALTH := 35
const WORLD_MASK := 1
const TRACER_POOL := 12
## Metres travelled per footfall; sprinting strides longer but faster, crouching shorter.
const STRIDE_WALK := 2.2
const STRIDE_SPRINT := 2.9
const STRIDE_CROUCH := 1.5
const STRIDE_AIM := 1.9
const DECOY_SPEED := 14.0

var active := false
## Stealth state read by the warpack.
var crouched := false
var crouch_wanted := false
var light_exposure := 0.0
var step_distance := 0.0
var was_airborne := false
var decoys: Array = []
var pending_throws := 0
var collider_shape: CapsuleShape3D
var stand_shape: CapsuleShape3D
var health := 100
var regen_pool := 0.0
var since_damage := 0.0
var ammo := MAGAZINE_SIZE
var reserve := 96
var aiming := false
var sprinting := false
var fire_held := false
var suppress_fire_until_release := true
var reloading := false
var reload_generation := 0
var reload_started := 0.0
var pitch := 0.055
var fire_cooldown := 0.0
var recoil := 0.0
var recoil_yaw := 0.0
var walk_phase := 0.0
var bob_amount := 0.0
var air_time := 0.0
var camera_trauma := 0.0
var heartbeat_timer := 0.0

## Look: optional smoothing (off by default) and the turn rate the weapon lags behind.
var look_smoothing := false
var look_smoothing_rate := 26.0
var target_yaw := 0.0
var target_pitch := 0.055
var look_input := Vector2.ZERO
## Keys held by a script (tests, replays) and a flag that treats the mouse as captured,
## so headless runs can drive the real movement code without a window.
var held_keys := {}
var scripted_capture := false
var look_rate := Vector2.ZERO
var previous_yaw := 0.0
var previous_pitch := 0.0

## Movement feel.
var ads_blend := 0.0
var sprint_blend := 0.0
var crouch_blend := 0.0
var wall_blend := 0.0
var head_height := STAND_HEAD
var landing_offset := 0.0
var landing_velocity := 0.0
var step_offset := 0.0
var sprint_kick := 0.0
var sprint_kick_velocity := 0.0
var last_fall_speed := 0.0
var jump_buffer := 0.0
var jump_was_down := false
var jumping := false
var last_shot_time := -10.0

## Remembrance state.
var hung: Array = []
var hang_held_for := -1.0
var volley_released := false
var sensing_for := 0.0

var head: Node3D
var camera: Camera3D
var view: WeaponView
var fx: CombatFX
var world_root: Node3D
var ember_light: OmniLight3D
var ember_material: StandardMaterial3D
var beam_material: StandardMaterial3D
var tracer_material: StandardMaterial3D
var tracers: Array = []
var next_tracer := 0
var shot_query: PhysicsRayQueryParameters3D
var ground_query: PhysicsRayQueryParameters3D
var wall_query: PhysicsRayQueryParameters3D
var stand_query: PhysicsShapeQueryParameters3D
var step_collision := KinematicCollision3D.new()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE)
	floor_snap_length = 0.5
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_block_on_wall = true
	wall_min_slide_angle = deg_to_rad(12.0)
	safe_margin = 0.002
	max_slides = 6

	var collider := CollisionShape3D.new()
	collider_shape = CapsuleShape3D.new()
	collider_shape.radius = 0.36
	collider_shape.height = 1.8
	collider.shape = collider_shape
	collider.name = "Collider"
	add_child(collider)
	# Ceiling probe for standing up: a hair narrower and shorter than the body.
	stand_shape = CapsuleShape3D.new()
	stand_shape.radius = 0.34
	stand_shape.height = 1.72

	head = Node3D.new()
	head.name = "Head"
	head.position.y = STAND_HEAD
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	camera.fov = HIP_FOV
	camera.near = 0.04
	head.add_child(camera)

	shot_query = PhysicsRayQueryParameters3D.new()
	shot_query.exclude = [get_rid()]
	ground_query = PhysicsRayQueryParameters3D.new()
	ground_query.exclude = [get_rid()]
	ground_query.collision_mask = WORLD_MASK
	wall_query = PhysicsRayQueryParameters3D.new()
	wall_query.exclude = [get_rid()]
	wall_query.collision_mask = WORLD_MASK
	stand_query = PhysicsShapeQueryParameters3D.new()
	stand_query.shape = stand_shape
	stand_query.collision_mask = WORLD_MASK
	stand_query.exclude = [get_rid()]

	view = WeaponView.new()
	camera.add_child(view)
	view.cue.connect(func(sound: String, volume_db: float) -> void: _sound(sound, volume_db))
	fx = CombatFX.new()
	add_child(fx)
	view.casing_ejected.connect(fx.eject_casing)
	view.magazine_dropped.connect(fx.drop_magazine)
	fx.sound_at.connect(_sound_at)
	_build_effects()
	target_yaw = rotation.y
	target_pitch = pitch
	set_process_unhandled_input(true)


func begin() -> void:
	active = true
	fire_held = false
	suppress_fire_until_release = true
	since_damage = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	controls_changed.emit(true)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_input += event.relative
		if look_smoothing:
			var next_target := FPSControls.apply_look(target_yaw, target_pitch, event.relative)
			target_yaw = next_target.x
			target_pitch = next_target.y
		else:
			var next_look := FPSControls.apply_look(rotation.y, pitch, event.relative)
			rotation.y = next_look.x
			pitch = next_look.y
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				fire_held = false
				suppress_fire_until_release = true
				controls_changed.emit(true)
			elif event.pressed and not suppress_fire_until_release:
				_shoot()
			elif not event.pressed:
				fire_held = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			aiming = event.pressed
	elif event is InputEventKey and not event.echo:
		if event.pressed:
			match event.keycode:
				KEY_ESCAPE:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					aiming = false
					hang_held_for = -1.0
					controls_changed.emit(false)
				KEY_R:
					_reload()
				KEY_E:
					interact_pressed.emit()
				KEY_C, KEY_CTRL:
					set_crouched(not crouch_wanted)
				KEY_G:
					throw_decoy()
				KEY_F:
					hang_held_for = 0.0
					volley_released = false
		elif event.keycode == KEY_F:
			# A tap hangs a round; a hold was already resolved as a release.
			if hang_held_for >= 0.0 and not volley_released:
				hang_round()
			hang_held_for = -1.0


func _physics_process(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	recoil = lerpf(recoil, 0.0, 1.0 - exp(-14.0 * delta))
	recoil_yaw = lerpf(recoil_yaw, 0.0, 1.0 - exp(-10.0 * delta))

	var on_floor := is_on_floor()
	if not on_floor:
		var gravity_scale := FALL_GRAVITY_SCALE if velocity.y < 0.0 else 1.0
		velocity += get_gravity() * gravity_scale * delta
		air_time += delta
	else:
		air_time = 0.0
		jumping = false

	var has_controls := active and controls_captured()
	if suppress_fire_until_release:
		fire_held = false
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			suppress_fire_until_release = false
	else:
		fire_held = has_controls and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var input_vector := Vector2.ZERO
	if has_controls:
		input_vector.x = float(_key_down(KEY_D)) - float(_key_down(KEY_A))
		input_vector.y = float(_key_down(KEY_S)) - float(_key_down(KEY_W))

		var jump_down := _key_down(KEY_SPACE)
		if jump_down and not jump_was_down:
			jump_buffer = JUMP_BUFFER_SECONDS
		jump_was_down = jump_down
		if jump_buffer > 0.0 and (on_floor or air_time < COYOTE_SECONDS) and velocity.y <= 0.1:
			velocity.y = JUMP_VELOCITY
			air_time = COYOTE_SECONDS
			jump_buffer = 0.0
			jumping = true
			_sound("jump", -14.0, randf_range(0.95, 1.08))
		elif jumping and not jump_down and velocity.y > JUMP_CUT_SPEED:
			velocity.y = JUMP_CUT_SPEED
			jumping = false
		if fire_held:
			_shoot()
		if hang_held_for >= 0.0:
			hang_held_for += delta
			if not volley_released and hang_held_for >= Remembrance.RELEASE_HOLD_SECONDS:
				volley_released = true
				release_volley("hold")
	else:
		fire_held = false
		jump_was_down = false
	jump_buffer = maxf(0.0, jump_buffer - delta)

	_update_crouch()
	var direction := FPSControls.movement_vector(rotation.y, input_vector)
	var was_sprinting := sprinting
	sprinting = has_controls and _key_down(KEY_SHIFT) and not aiming and not crouched and direction.length_squared() > 0.0
	if sprinting and not was_sprinting:
		sprint_kick_velocity -= 0.34
	elif was_sprinting and not sprinting:
		sprint_kick_velocity += 0.26
	var target_speed := CROUCH_SPEED if crouched else (AIM_SPEED if aiming else (SPRINT_SPEED if sprinting else WALK_SPEED))
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var moving_input := direction.length_squared() > 0.0
	var rate := 0.0
	if on_floor:
		if moving_input:
			rate = SPRINT_ACCELERATION if sprinting else GROUND_ACCELERATION
			if horizontal.length() > 1.0 and horizontal.normalized().dot(direction) < 0.2:
				rate *= OPPOSING_BOOST
		else:
			rate = SPRINT_BRAKING if horizontal.length() > WALK_SPEED + 0.5 else GROUND_BRAKING
	else:
		rate = AIR_ACCELERATION if moving_input else AIR_DRAG
	horizontal = horizontal.move_toward(direction * target_speed, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	last_fall_speed = -velocity.y
	var y_before := global_position.y
	var stepped := on_floor and moving_input and _try_step_up(delta)
	move_and_slide()
	if stepped:
		# Ride the ledge with the eye instead of popping up with the body.
		step_offset -= global_position.y - y_before
	if on_floor and not jumping and velocity.y <= 0.0:
		apply_floor_snap()

	var grounded := is_on_floor()
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	_update_stride(delta, speed, grounded)
	_update_wall(delta)
	_update_landing(grounded)
	_update_heartbeat(delta)

	if active:
		since_damage += delta
		if health < REGEN_CAP and since_damage > REGEN_DELAY:
			regen_pool += REGEN_PER_SECOND * delta
			if regen_pool >= 1.0:
				var gained := int(regen_pool)
				regen_pool -= gained
				health = mini(REGEN_CAP, health + gained)
				health_changed.emit(health)

	_update_remembrance(delta)


func _process(delta: float) -> void:
	_update_look(delta)
	_update_decoys(delta)
	_update_view(delta)
	for tracer in tracers:
		if not tracer.node.visible:
			continue
		tracer.life -= delta
		if tracer.life <= 0.0:
			tracer.node.visible = false
		else:
			tracer.node.transparency = 1.0 - clampf(tracer.life / tracer.max_life, 0.0, 1.0)


func controls_captured() -> bool:
	return scripted_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _key_down(keycode: Key) -> bool:
	return held_keys.has(keycode) or Input.is_physical_key_pressed(keycode)


func _update_look(delta: float) -> void:
	if look_smoothing:
		var weight := 1.0 - exp(-look_smoothing_rate * delta)
		rotation.y = lerp_angle(rotation.y, target_yaw, weight)
		pitch = lerpf(pitch, target_pitch, weight)
	else:
		target_yaw = rotation.y
		target_pitch = pitch
	# Weapon inertia follows the real turn rate however the camera got there.
	var raw := Vector2(angle_difference(previous_yaw, rotation.y), pitch - previous_pitch) / maxf(delta, 0.0001)
	look_rate = look_rate.lerp(raw, 1.0 - exp(-24.0 * delta))
	previous_yaw = rotation.y
	previous_pitch = pitch
	look_input = Vector2.ZERO


func _update_view(delta: float) -> void:
	var aim_goal := 1.0 if aiming and not sprinting and not reloading and active else 0.0
	ads_blend = lerpf(ads_blend, aim_goal, 1.0 - exp(-13.0 * delta))
	sprint_blend = lerpf(sprint_blend, 1.0 if sprinting else 0.0, 1.0 - exp(-8.0 * delta))
	crouch_blend = lerpf(crouch_blend, 1.0 if crouched else 0.0, 1.0 - exp(-10.0 * delta))
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var moving := speed > 0.4 and is_on_floor()
	var bob_target := clampf(speed / WALK_SPEED, 0.0, 1.5) if moving else 0.0
	# Bob fades in fast and out slowly so stopping never snaps the camera.
	bob_amount = lerpf(bob_amount, bob_target, 1.0 - exp(-(9.0 if moving else 6.0) * delta))
	var phase := walk_phase
	var gain := bob_amount * (1.0 - ads_blend * 0.6) * (0.55 if crouched else 1.0)
	var sprint_gain := 1.0 + sprint_blend * 0.9

	head_height = lerpf(head_height, CROUCH_HEAD if crouched else STAND_HEAD, 1.0 - exp(-11.0 * delta))
	# Springs step at a capped rate so a hitched frame cannot fling the camera.
	var spring_dt := minf(delta, 1.0 / 40.0)
	landing_velocity += (-landing_offset * 190.0 - landing_velocity * 15.0) * spring_dt
	landing_offset += landing_velocity * spring_dt
	sprint_kick_velocity += (-sprint_kick * 150.0 - sprint_kick_velocity * 14.0) * spring_dt
	sprint_kick += sprint_kick_velocity * spring_dt
	step_offset = lerpf(step_offset, 0.0, 1.0 - exp(-12.0 * delta))

	var local_velocity := global_transform.basis.inverse() * velocity
	var strafe_roll := clampf(-local_velocity.x / SPRINT_SPEED, -1.0, 1.0) * 0.012
	head.position.y = head_height + step_offset + landing_offset + (sin(phase * 2.0 + 0.4) * 0.018 - 0.004) * gain * sprint_gain
	head.position.x = sin(phase) * 0.012 * gain * sprint_gain
	head.rotation.z = strafe_roll + sin(phase) * 0.0036 * gain * sprint_gain
	head.rotation.x = clampf(pitch - recoil + sprint_kick + sin(phase * 2.0 + 1.0) * 0.0032 * gain * sprint_gain, -1.5, 1.5)
	head.rotation.y = recoil_yaw

	var fov := lerpf(HIP_FOV, AIM_FOV, ads_blend)
	fov = lerpf(fov, SPRINT_FOV, sprint_blend)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-12.0 * delta))
	camera_trauma = move_toward(camera_trauma, 0.0, delta * 1.55)
	var trauma := camera_trauma * camera_trauma
	var shake_time := Time.get_ticks_msec() * 0.001
	camera.position = Vector3(sin(shake_time * 41.0) * 0.030, cos(shake_time * 34.0) * 0.022, 0.0) * trauma
	camera.rotation = Vector3(sin(shake_time * 37.0 + 1.3) * 0.010, sin(shake_time * 31.0) * 0.008, sin(shake_time * 29.0) * 0.022) * trauma

	view.ads = ads_blend
	view.sprint = sprint_blend
	view.crouch = crouch_blend
	view.wall = wall_blend
	view.walk_phase = phase
	view.bob_amount = bob_amount
	view.sprint_bob = sprint_blend
	view.local_velocity = local_velocity
	view.look_rate = look_rate
	view.tick(delta)


## Footfalls come from distance travelled, so cadence follows speed and posture.
func _update_stride(delta: float, speed: float, grounded: bool) -> void:
	if not active:
		return
	var stride := STRIDE_CROUCH if crouched else (STRIDE_SPRINT if sprinting else (STRIDE_AIM if aiming else STRIDE_WALK))
	if grounded and speed > 0.4:
		var travelled := speed * delta
		step_distance += travelled
		walk_phase += travelled / stride * PI
		if step_distance >= stride:
			step_distance -= stride
			_footfall()
	elif not grounded:
		step_distance = stride * 0.5


func _footfall() -> void:
	var radius := Stealth.movement_noise(true, sprinting, crouched)
	if radius > 0.0:
		noise_made.emit(global_position, radius)
	var volume := -16.0 if crouched else (-6.0 if sprinting else -10.0)
	var surface := _surface_under()
	# Snow crunches everywhere; hard ground adds its own layer once supplied.
	var pitch_scale := randf_range(0.9, 1.1) * (0.92 if sprinting else 1.0)
	_sound("footstep", volume - (3.0 if surface != "snow" else 0.0), pitch_scale)
	if surface == "rock":
		_sound("footstep_rock", volume, pitch_scale)
	elif surface == "wood":
		_sound("footstep_wood", volume, pitch_scale)


func _surface_under() -> String:
	ground_query.from = global_position
	ground_query.to = global_position + Vector3(0.0, -1.6, 0.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(ground_query)
	return CombatFX.surface_of(hit) if hit else "snow"


func _update_landing(grounded: bool) -> void:
	if not active:
		was_airborne = not grounded
		return
	if was_airborne and grounded:
		var fall := clampf((last_fall_speed - 3.0) / 11.0, 0.0, 1.0)
		var noise := Stealth.noise_radius("land") * (0.6 + fall * 0.6)
		noise_made.emit(global_position, noise)
		_sound("land", -14.0 + fall * 10.0, 1.1 - fall * 0.25)
		if fall > 0.0:
			landing_velocity -= fall * 3.2
			view.kick_landing(fall)
			add_camera_trauma(fall * 0.16)
		sprint_kick_velocity -= fall * 0.3
	was_airborne = not grounded


## A short ray ahead of the eye: near walls the carbine rises and pulls in.
func _update_wall(delta: float) -> void:
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	wall_query.from = origin
	wall_query.to = origin + forward * 1.15
	var hit := get_world_3d().direct_space_state.intersect_ray(wall_query)
	var target := 0.0
	if hit:
		target = clampf((1.0 - (origin.distance_to(hit.position) - 0.32) / 0.8), 0.0, 1.0)
	wall_blend = lerpf(wall_blend, target, 1.0 - exp(-(14.0 if target > wall_blend else 7.0) * delta))


func _update_heartbeat(delta: float) -> void:
	if not active or health >= LOW_HEALTH or health <= 0:
		heartbeat_timer = 0.0
		return
	heartbeat_timer -= delta
	if heartbeat_timer <= 0.0:
		var urgency := 1.0 - float(health) / LOW_HEALTH
		heartbeat_timer = lerpf(1.0, 0.5, urgency)
		_sound("heartbeat", lerpf(-12.0, -3.0, urgency))


func _update_crouch() -> void:
	if crouched and not crouch_wanted and can_stand():
		_apply_crouch(false)
	elif not crouched and crouch_wanted:
		_apply_crouch(true)


func _apply_crouch(value: bool) -> void:
	crouched = value
	collider_shape.height = 1.2 if crouched else 1.8
	var collider: Node3D = get_node("Collider")
	collider.position.y = -0.3 if crouched else 0.0


## Shape cast for the standing capsule: a low ceiling keeps the goat crouched.
func can_stand() -> bool:
	if not is_inside_tree():
		return true
	stand_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, 0.02, 0.0))
	return get_world_3d().direct_space_state.intersect_shape(stand_query, 1).is_empty()


## Walks a small ledge instead of stopping at it: lift, check the way ahead, and
## let floor snap bring the body back down on top.
func _try_step_up(delta: float) -> bool:
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 0.000001:
		return false
	if not test_move(global_transform, motion, step_collision):
		return false
	if step_collision.get_normal().y > 0.6:
		return false
	var lift := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, lift):
		return false
	var raised := global_transform.translated(lift)
	var reach := motion.normalized() * maxf(motion.length(), 0.14)
	if test_move(raised, reach):
		return false
	# Only a flat-topped ledge counts; a steep slope must not be climbed like stairs.
	if not test_move(raised.translated(reach), Vector3.DOWN * (STEP_HEIGHT + 0.05), step_collision):
		return false
	if step_collision.get_normal().y < cos(deg_to_rad(FLOOR_MAX_ANGLE)):
		return false
	global_position += lift
	return true


func _shoot() -> void:
	if not active or not controls_captured() or reloading or fire_cooldown > 0.0 or sprinting:
		return
	if ammo <= 0:
		_sound("click", -6.0)
		fire_cooldown = 0.25
		view.play_dry()
		_reload()
		return

	_sound("shot", 0.0, randf_range(0.94, 1.06))
	ammo -= 1
	fire_cooldown = FIRE_INTERVAL
	last_shot_time = Time.get_ticks_msec() * 0.001
	recoil = minf(recoil + (0.018 if aiming else 0.030), 0.09)
	recoil_yaw = clampf(recoil_yaw + randf_range(-0.004, 0.004), -0.02, 0.02)
	view.fire(aiming)
	add_camera_trauma(0.035 if aiming else 0.055)
	ammo_changed.emit(ammo, reserve)

	var spread := 0.0025 if aiming else 0.009
	var ray_direction := (aim_direction() + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0.0)).normalized()
	noise_made.emit(global_position, Stealth.noise_radius("shot"))
	var hit := _cast(aim_origin(), ray_direction, 160.0, 0xFFFFFFFF)
	var end: Vector3 = hit.position if hit else aim_origin() + ray_direction * 80.0
	_fire_tracer(view.muzzle_position(), end, Color(1.0, 0.86, 0.55), 0.06, 0.007)
	if not hit:
		return
	var surface := CombatFX.surface_of(hit)
	if not hit.collider.has_method("take_damage"):
		fx.impact(hit.position, hit.normal, surface)
		return
	var local_hit: Vector3 = hit.collider.to_local(hit.position)
	var critical: bool = local_hit.y > (1.3 if hit.collider.boss else 0.7)
	var ambush: float = Stealth.ambush_multiplier(hit.collider.detection)
	if ambush > 1.0:
		notice.emit("AMBUSH", 0.8)
	_sound("headshot" if critical else "hit", -4.0)
	fx.impact(hit.position, hit.normal, "flesh", true)
	var target: Node = hit.collider
	target.take_damage(roundi((125 if critical else 42) * ambush), 0.5 if critical else 0.22)
	var kind := "headshot" if critical else "hit"
	if is_instance_valid(target) and target.dead:
		kind = "kill"
	_sound("hitmarker", -9.0, 1.3 if kind == "kill" else (1.15 if critical else 1.0))
	hit_confirmed.emit(kind)


func _cast(from: Vector3, direction: Vector3, length: float, mask: int) -> Dictionary:
	shot_query.from = from
	shot_query.to = from + direction * length
	shot_query.collision_mask = mask
	return get_world_3d().direct_space_state.intersect_ray(shot_query)


func reload_progress() -> float:
	if not reloading:
		return 0.0
	return clampf((Time.get_ticks_msec() * 0.001 - reload_started) / RELOAD_SECONDS, 0.0, 1.0)


## How wide the crosshair should bloom: 0 planted and aimed, 1 sprinting or firing.
func crosshair_spread() -> float:
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var spread := clampf(speed / SPRINT_SPEED, 0.0, 1.0) * 0.55
	if not is_on_floor():
		spread += 0.35
	spread += clampf(1.0 - (Time.get_ticks_msec() * 0.001 - last_shot_time) / 0.3, 0.0, 1.0) * 0.45
	if crouched:
		spread *= 0.6
	return clampf(spread * (1.0 - ads_blend * 0.85), 0.0, 1.0)


## Tap F: spend one live round and leave it hanging where you stand, aimed where you look.
func hang_round() -> bool:
	if not active or not Remembrance.can_hang(hung.size(), ammo, reloading, sprinting):
		return false
	ammo -= 1
	var direction := aim_direction()
	var origin := aim_origin() + direction * 1.1 + Vector3(0.0, -0.12, 0.0)
	var wall := _cast(origin, direction, Remembrance.BEAM_LENGTH, WORLD_MASK)
	var reach: float = origin.distance_to(wall.position) if wall else Remembrance.BEAM_LENGTH
	var round := Remembrance.HungRound.new(origin, direction, reach)
	round.node = _build_ember(round)
	hung.append(round)
	view.play_hang()
	_sound("hang", -6.0, 1.0 + hung.size() * 0.06)
	recoil = minf(recoil + 0.012, 0.09)
	ember_light.global_position = origin
	ember_light.light_energy = 2.0
	ammo_changed.emit(ammo, reserve)
	remembrance_changed.emit(hung.size(), Remembrance.CAPACITY, false)
	return true


## Hold F (or ring the bell): every hung round fires at once from where it was left.
func release_volley(reason: String) -> int:
	if hung.is_empty():
		return 0
	var targets: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.dead:
			continue
		targets.append({"id": enemy.get_instance_id(), "position": enemy.chest_position(), "boss": enemy.boss})
	var shots := Remembrance.plan_volley(hung, targets, func(round: Remembrance.HungRound, direction: Vector3, distance: float) -> bool:
		return not _cast(round.origin, direction, maxf(0.0, distance - 0.7), WORLD_MASK).is_empty()
	)
	_sound("volley", 0.0)
	var converged := false
	var landed := 0
	for shot in shots:
		var round: Remembrance.HungRound = hung[shot.round]
		noise_made.emit(round.origin, Stealth.noise_radius("volley"))
		var travel: float = shot.distance if shot.target != -1 else minf(round.reach, shot.distance)
		var to: Vector3 = round.origin + shot.direction * travel
		_fire_tracer(round.origin, to, Color("fff0c0") if shot.converged else Color("ffc36b"), 0.24, 0.045)
		var enemy: Node = instance_from_id(shot.target) if shot.target != -1 else null
		if is_instance_valid(enemy) and not enemy.dead:
			landed += 1
			enemy.take_damage(shot.damage, Remembrance.CONVERGENCE_STAGGER if shot.converged else 0.3)
			converged = converged or shot.converged
			hit_confirmed.emit("kill" if enemy.dead else "hit")
		elif shot.target == -1:
			var wall := _cast(round.origin, shot.direction, travel + 0.5, WORLD_MASK)
			if wall:
				fx.impact(wall.position, wall.normal, CombatFX.surface_of(wall), true)
	if converged:
		_sound("converge", -4.0)
		notice.emit("CONVERGENCE", 1.6)
	elif reason == "bell":
		notice.emit("THE BELL RELEASES ITS MEMORY", 1.8)
	elif landed == 0:
		notice.emit("THE MOUNTAIN FIRED INTO THE DARK", 1.2)
	clear_hung()
	return landed


func clear_hung() -> void:
	for round in hung:
		if is_instance_valid(round.node):
			round.node.queue_free()
	hung.clear()
	ember_light.light_energy = 0.0
	remembrance_changed.emit(0, Remembrance.CAPACITY, false)


func _update_remembrance(delta: float) -> void:
	if hung.is_empty():
		return
	var before := hung.size()
	var kept := Remembrance.age_rounds(hung, delta)
	if kept.size() != before:
		for round in hung:
			if not kept.has(round) and is_instance_valid(round.node):
				round.node.queue_free()
		hung = kept
		remembrance_changed.emit(hung.size(), Remembrance.CAPACITY, sensing_for > 0.0)
	var was_sensing := sensing_for > 0.0
	sensing_for = maxf(0.0, sensing_for - delta)
	var enemies := get_tree().get_nodes_in_group("enemies")
	var camera_position := camera.global_position
	var t := Time.get_ticks_msec() * 0.001
	for i in hung.size():
		var round: Remembrance.HungRound = hung[i]
		round.sense = maxf(0.0, round.sense - delta * 2.2)
		round.sense_cooldown -= delta
		# Hung rounds keep watch: an enemy crossing a beam makes the ember flare.
		for enemy in enemies:
			if enemy.dead:
				continue
			if Remembrance.beam_distance(round, enemy.chest_position()) < Remembrance.SENSE_RADIUS:
				if round.sense < 0.5:
					_sound("sense", -12.0)
				round.sense = 1.0
				sensing_for = 0.32
				break
		if not is_instance_valid(round.node):
			continue
		var ember: Node3D = round.node.get_node("Ember")
		var pulse := 1.0 + sin(t * 9.0 + i) * 0.18 + round.sense * 1.4
		var fade_out := minf(1.0, (Remembrance.LIFETIME_SECONDS - round.age) / 4.0)
		# A round hung a moment ago sits at the muzzle: shrink it until the player steps away.
		var proximity := clampf((round.origin.distance_to(camera_position) - 0.9) / 2.2, 0.12, 1.0)
		ember.scale = Vector3.ONE * pulse * fade_out * proximity
		ember.rotation.y = t * 2.4 + i
	var last: Remembrance.HungRound = hung[hung.size() - 1]
	var light_proximity := clampf((last.origin.distance_to(camera_position) - 0.9) / 2.2, 0.1, 1.0)
	ember_light.light_energy = (1.6 + sin(t * 12.0) * 0.5) * light_proximity
	if (sensing_for > 0.0) != was_sensing:
		remembrance_changed.emit(hung.size(), Remembrance.CAPACITY, sensing_for > 0.0)


## Where a wolverine looks for the goat: lower when crouched.
func chest_position() -> Vector3:
	return global_position + Vector3(0.0, 0.15 if crouched else 0.5, 0.0)


func aim_origin() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func _audio() -> GoatAudio:
	return get_tree().get_first_node_in_group("audio") as GoatAudio


func _sound(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var audio := _audio()
	if audio:
		audio.play(name, volume_db, pitch)


func _sound_at(name: String, at: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var audio := _audio()
	if audio:
		audio.play_at(name, at, volume_db, pitch)


## C: crouch or stand. Standing is refused, and retried each frame, under a low ceiling.
func set_crouched(value: bool) -> void:
	crouch_wanted = value
	if value:
		if not crouched:
			_apply_crouch(true)
	elif crouched and can_stand():
		_apply_crouch(false)


## G: lob a stone; where it lands, the pack hears it.
func throw_decoy() -> void:
	if not active or decoys.size() + pending_throws >= 3:
		return
	pending_throws += 1
	view.play_throw(THROW_SECONDS)
	_sound("throw", -8.0, randf_range(0.95, 1.1))
	await get_tree().create_timer(THROW_RELEASE_SECONDS).timeout
	pending_throws = maxi(0, pending_throws - 1)
	if not is_inside_tree() or not active:
		return
	var stone := MeshInstance3D.new()
	var stone_mesh := SphereMesh.new()
	stone_mesh.radius = 0.11
	stone_mesh.height = 0.22
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color("5c6166")
	stone_mesh.material = stone_material
	stone.mesh = stone_mesh
	world_root.add_child(stone)
	stone.global_position = aim_origin() + aim_direction() * 0.6
	var launch := (aim_direction() + Vector3(0.0, 0.32, 0.0)).normalized() * DECOY_SPEED
	decoys.append({"node": stone, "velocity": launch, "life": 4.0})
	noise_made.emit(global_position, Stealth.noise_radius("snuff"))


func _update_decoys(delta: float) -> void:
	for i in range(decoys.size() - 1, -1, -1):
		var decoy: Dictionary = decoys[i]
		var node: MeshInstance3D = decoy.node
		decoy.velocity += Vector3(0.0, -18.0, 0.0) * delta
		node.global_position += decoy.velocity * delta
		decoy.life -= delta
		var ground := WorldBuilder.height_at(node.global_position.x, node.global_position.z)
		if node.global_position.y <= ground + 0.1 or decoy.life <= 0.0:
			node.global_position.y = ground + 0.1
			noise_made.emit(node.global_position, Stealth.noise_radius("decoy"))
			var audio := _audio()
			if audio:
				audio.play_at("stone", node.global_position, -4.0)
			notice.emit("THE STONE LANDS. THEY HEARD IT.", 1.0)
			decoys.remove_at(i)
			var tween := create_tween()
			tween.tween_interval(6.0)
			tween.tween_callback(node.queue_free)


## A horn strike from behind an unaware wolverine.
func perform_takedown(enemy: Node) -> void:
	enemy.takedown()
	recoil = 0.07
	view.play_takedown()
	add_camera_trauma(0.22)
	_sound("takedown", -2.0)
	_sound("thud", -6.0)
	noise_made.emit(global_position, Stealth.noise_radius("takedown"))
	notice.emit("HORN STRIKE", 1.0)


func respawn(at: Vector3) -> void:
	_reset_action_state()
	global_position = at
	velocity = Vector3.ZERO
	camera_trauma = 0.0
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	landing_offset = 0.0
	landing_velocity = 0.0
	step_offset = 0.0
	health = 100
	regen_pool = 0.0
	since_damage = 0.0
	ammo = MAGAZINE_SIZE
	reserve = maxi(reserve, 48)
	set_crouched(false)
	clear_hung()
	active = true
	view.play_equip()
	health_changed.emit(health)
	ammo_changed.emit(ammo, reserve)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	controls_changed.emit(true)


func _reset_action_state() -> void:
	# Invalidate any timer started before this life, including a reload whose
	# timeout arrives after the player has already begun firing again.
	reload_generation += 1
	reloading = false
	aiming = false
	sprinting = false
	fire_held = false
	suppress_fire_until_release = true
	fire_cooldown = 0.0
	recoil = 0.0
	recoil_yaw = 0.0
	hang_held_for = -1.0
	volley_released = false
	sensing_for = 0.0
	air_time = 0.0
	was_airborne = false
	step_distance = 0.0
	jump_buffer = 0.0
	jumping = false
	heartbeat_timer = 0.0
	pending_throws = 0
	view.cancel_gesture()


func _reload() -> void:
	if not active or reloading or ammo == MAGAZINE_SIZE or reserve <= 0:
		return
	reloading = true
	reload_started = Time.get_ticks_msec() * 0.001
	reload_generation += 1
	var generation := reload_generation
	view.play_reload(RELOAD_SECONDS)
	await get_tree().create_timer(RELOAD_SECONDS).timeout
	if not is_inside_tree() or generation != reload_generation:
		return
	var amount := mini(MAGAZINE_SIZE - ammo, reserve)
	ammo += amount
	reserve -= amount
	reloading = false
	ammo_changed.emit(ammo, reserve)


func add_reserve(amount: int) -> void:
	reserve = mini(RESERVE_CAP, reserve + amount)
	ammo_changed.emit(ammo, reserve)


## Damage from `source` (a world position; pass it so the indicator points true).
## Without one, the nearest living wolverine is assumed to be the culprit.
func damage(amount: int, source := Vector3.INF) -> void:
	if not active:
		return
	health = maxi(0, health - amount)
	since_damage = 0.0
	regen_pool = 0.0
	_sound("hurt", -2.0, randf_range(0.9, 1.1))
	add_camera_trauma(0.14 + minf(0.4, amount / 90.0))
	recoil = minf(recoil + 0.02, 0.09)
	damaged.emit(_bearing_to(source), amount)
	health_changed.emit(health)
	if health == 0:
		active = false
		_reset_action_state()
		clear_hung()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()


func _bearing_to(source: Vector3) -> float:
	if source == Vector3.INF:
		var best := 34.0
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.dead:
				continue
			var distance := global_position.distance_to(enemy.global_position)
			if distance < best:
				best = distance
				source = enemy.global_position
	if source == Vector3.INF:
		return NAN
	var offset := source - global_position
	offset.y = 0.0
	if offset.length_squared() < 0.0001:
		return NAN
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	return atan2(offset.dot(right), offset.dot(forward))


func knockback(from: Vector3, strength: float, lift := 2.5) -> void:
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.BACK
	velocity += away.normalized() * strength
	velocity.y = maxf(velocity.y, lift)
	add_camera_trauma(minf(0.42, strength / 28.0))


func add_camera_trauma(amount: float) -> void:
	camera_trauma = clampf(camera_trauma + amount, 0.0, 1.0)


## A short recoil flinch of the carbine: used by scripted strikes and the last horn strike.
func gunshot_feedback() -> void:
	view.recoil_pitch_velocity += 2.4
	view.recoil_z_velocity += 0.4


func _fire_tracer(from: Vector3, to: Vector3, color: Color, life: float, thickness := 0.025) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var tracer: Dictionary = tracers[next_tracer]
	next_tracer = (next_tracer + 1) % TRACER_POOL
	var node: MeshInstance3D = tracer.node
	_aim_node(node, from.lerp(to, 0.5), to)
	node.scale = Vector3(thickness, thickness, length)
	node.material_override.albedo_color = color
	node.transparency = 0.0
	node.visible = true
	tracer.life = life
	tracer.max_life = life


func _aim_node(node: Node3D, at: Vector3, toward: Vector3) -> void:
	var up := Vector3.UP if absf((toward - at).normalized().y) < 0.99 else Vector3.RIGHT
	node.look_at_from_position(at, toward, up)


func _build_effects() -> void:
	world_root = Node3D.new()
	world_root.name = "GoatEffects"
	world_root.top_level = true
	add_child(world_root)

	ember_material = StandardMaterial3D.new()
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.albedo_color = Color("ffc36b")
	ember_material.emission_enabled = true
	ember_material.emission = Color("ffb066")
	ember_material.emission_energy_multiplier = 3.0
	beam_material = StandardMaterial3D.new()
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_material.albedo_color = Color(0.91, 0.66, 0.35, 0.28)
	tracer_material = StandardMaterial3D.new()
	tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_material.albedo_color = Color(1.0, 0.76, 0.42, 0.8)

	ember_light = OmniLight3D.new()
	ember_light.name = "EmberLight"
	ember_light.light_color = Color("ffb066")
	ember_light.light_energy = 0.0
	ember_light.omni_range = 7.0
	world_root.add_child(ember_light)

	# Tracers are a fixed pool of stretched unit boxes reused round-robin.
	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3.ONE
	tracer_mesh.material = tracer_material
	for i in TRACER_POOL:
		var node := MeshInstance3D.new()
		node.name = "Tracer_%02d" % i
		node.mesh = tracer_mesh
		node.material_override = tracer_material.duplicate()
		node.visible = false
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(node)
		tracers.append({"node": node, "life": 0.0, "max_life": 1.0})


func _build_ember(round: Remembrance.HungRound) -> Node3D:
	var holder := Node3D.new()
	holder.name = "HungRound"
	world_root.add_child(holder)
	holder.global_position = round.origin

	var ember := MeshInstance3D.new()
	ember.name = "Ember"
	var ember_mesh := PrismMesh.new()
	ember_mesh.size = Vector3(0.13, 0.15, 0.13)
	ember_mesh.material = ember_material
	ember.mesh = ember_mesh
	ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ember.scale = Vector3.ONE * 0.12
	holder.add_child(ember)

	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3.ONE
	beam_mesh.material = beam_material
	beam.mesh = beam_mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(beam)
	var end := round.origin + round.direction * round.reach
	_aim_node(beam, round.origin.lerp(end, 0.5), end)
	beam.scale = Vector3(0.012, 0.012, round.reach)
	return holder
