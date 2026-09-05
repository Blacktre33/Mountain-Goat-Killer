class_name GoatPlayer
extends CharacterBody3D

signal ammo_changed(current: int, reserve: int)
signal health_changed(current: int)
signal controls_changed(captured: bool)
signal remembrance_changed(hung: int, capacity: int, sensing: bool)
signal notice(text: String, seconds: float)
signal interact_pressed
signal noise_made(source: Vector3, radius: float)
signal died

const WALK_SPEED := 5.4
const CROUCH_SPEED := 2.4
const SPRINT_SPEED := 8.4
const AIM_SPEED := 3.4
const ACCELERATION := 18.0
const AIR_ACCELERATION := 5.0
const JUMP_VELOCITY := 7.2
## Grace period after stepping off a ledge during which a jump still counts.
const COYOTE_SECONDS := 0.12
const MAGAZINE_SIZE := 24
const RESERVE_CAP := 160
const RELOAD_SECONDS := 1.05
const FIRE_INTERVAL := 0.096
const HIP_FOV := 68.0
const SPRINT_FOV := 74.0
const AIM_FOV := 54.0
## Second wind: after a quiet spell, will returns up to a ceiling.
const REGEN_DELAY := 4.5
const REGEN_PER_SECOND := 7.0
const REGEN_CAP := 55
const WORLD_MASK := 1
const TRACER_POOL := 12
const FOOTSTEP_INTERVAL := 0.42
const DECOY_SPEED := 14.0

var active := false
## Stealth state read by the warpack.
var crouched := false
var light_exposure := 0.0
var footstep_timer := 0.0
var was_airborne := false
var decoys: Array = []
var collider_shape: CapsuleShape3D
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
var pitch := 0.055
var fire_cooldown := 0.0
var recoil := 0.0
var bob_time := 0.0
var air_time := 0.0
var camera_trauma := 0.0

## Remembrance state.
var hung: Array = []
var hang_held_for := -1.0
var volley_released := false
var sensing_for := 0.0

var head: Node3D
var camera: Camera3D
var weapon: Node3D
var muzzle_flash: OmniLight3D
var world_root: Node3D
var ember_light: OmniLight3D
var ember_material: StandardMaterial3D
var beam_material: StandardMaterial3D
var tracer_material: StandardMaterial3D
var tracers: Array = []
var next_tracer := 0
var shot_query: PhysicsRayQueryParameters3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 2

	var collider := CollisionShape3D.new()
	collider_shape = CapsuleShape3D.new()
	collider_shape.radius = 0.36
	collider_shape.height = 1.8
	collider.shape = collider_shape
	collider.name = "Collider"
	add_child(collider)

	head = Node3D.new()
	head.name = "Head"
	head.position.y = 0.66
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	camera.fov = HIP_FOV
	camera.near = 0.05
	head.add_child(camera)

	shot_query = PhysicsRayQueryParameters3D.new()
	shot_query.exclude = [get_rid()]

	_build_weapon()
	_build_effects()
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
					set_crouched(not crouched)
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
	recoil = lerpf(recoil, 0.0, 1.0 - exp(-16.0 * delta))

	if not is_on_floor():
		velocity += get_gravity() * delta
		air_time += delta
	else:
		air_time = 0.0

	var has_controls := active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if suppress_fire_until_release:
		fire_held = false
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			suppress_fire_until_release = false
	else:
		fire_held = has_controls and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var input_vector := Vector2.ZERO
	if has_controls:
		input_vector.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		input_vector.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))

		if Input.is_physical_key_pressed(KEY_SPACE) and (is_on_floor() or air_time < COYOTE_SECONDS) and velocity.y <= 0.0:
			velocity.y = JUMP_VELOCITY
			air_time = COYOTE_SECONDS
		if fire_held:
			_shoot()
		if hang_held_for >= 0.0:
			hang_held_for += delta
			if not volley_released and hang_held_for >= Remembrance.RELEASE_HOLD_SECONDS:
				volley_released = true
				release_volley("hold")
	else:
		fire_held = false

	var direction := FPSControls.movement_vector(rotation.y, input_vector)
	sprinting = has_controls and Input.is_physical_key_pressed(KEY_SHIFT) and not aiming and not crouched and direction.length_squared() > 0.0
	var target_speed := CROUCH_SPEED if crouched else (AIM_SPEED if aiming else (SPRINT_SPEED if sprinting else WALK_SPEED))
	var acceleration := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
	move_and_slide()

	if direction.length_squared() > 0.0 and is_on_floor():
		bob_time += delta * (13.0 if sprinting else (6.0 if crouched else 8.5))
	_emit_movement_noise(delta, direction.length_squared() > 0.0 and is_on_floor())

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
	_update_view(delta, direction.length_squared() > 0.0 and is_on_floor())


func _process(delta: float) -> void:
	_update_decoys(delta)
	for tracer in tracers:
		if not tracer.node.visible:
			continue
		tracer.life -= delta
		if tracer.life <= 0.0:
			tracer.node.visible = false
		else:
			tracer.node.transparency = 1.0 - clampf(tracer.life / tracer.max_life, 0.0, 1.0)


func _update_view(delta: float, moving: bool) -> void:
	var bob := sin(bob_time) if moving else 0.0
	head.rotation.x = pitch - recoil
	head.position.y = lerpf(head.position.y, (0.12 if crouched else 0.66) + absf(bob) * 0.018, 1.0 - exp(-10.0 * delta))
	var fov := AIM_FOV if aiming else (SPRINT_FOV if sprinting else HIP_FOV)
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-14.0 * delta))
	camera_trauma = move_toward(camera_trauma, 0.0, delta * 1.55)
	var trauma := camera_trauma * camera_trauma
	var shake_time := Time.get_ticks_msec() * 0.001
	camera.position = Vector3(sin(shake_time * 41.0) * 0.042, cos(shake_time * 34.0) * 0.028, 0.0) * trauma
	camera.rotation.z = sin(shake_time * 29.0) * 0.026 * trauma

	var target_position := Vector3(0.0 if aiming else 0.42, -0.075 if aiming else -0.42, -0.55 if aiming else -0.55)
	target_position.x += bob * 0.012
	target_position.y += absf(bob) * 0.012 - recoil * 1.9
	weapon.position = weapon.position.lerp(target_position, 1.0 - exp(-12.0 * delta))
	weapon.rotation.z = lerpf(weapon.rotation.z, -bob * 0.008, 1.0 - exp(-9.0 * delta))
	muzzle_flash.light_energy = lerpf(muzzle_flash.light_energy, 0.0, 1.0 - exp(-45.0 * delta))


## Where a wolverine looks for the goat: lower when crouched.
func chest_position() -> Vector3:
	return global_position + Vector3(0.0, 0.15 if crouched else 0.5, 0.0)


func aim_origin() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z


func _shoot() -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or reloading or fire_cooldown > 0.0 or sprinting:
		return
	if ammo <= 0:
		_sound("click", -6.0)
		_reload()
		return

	gunshot_feedback()
	_sound("shot", 0.0, randf_range(0.94, 1.06))
	ammo -= 1
	fire_cooldown = FIRE_INTERVAL
	recoil = minf(recoil + (0.018 if aiming else 0.032), 0.09)
	muzzle_flash.light_energy = 7.0
	ammo_changed.emit(ammo, reserve)

	var spread := 0.0025 if aiming else 0.009
	var ray_direction := (aim_direction() + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0.0)).normalized()
	noise_made.emit(global_position, Stealth.noise_radius("shot"))
	var hit := _cast(aim_origin(), ray_direction, 160.0, 0xFFFFFFFF)
	if hit and not hit.collider.has_method("take_damage"):
		var audio := _audio()
		if audio:
			audio.play_at("rock_hit", hit.position, -10.0, randf_range(0.8, 1.2))
	if hit and hit.collider.has_method("take_damage"):
		var local_hit: Vector3 = hit.collider.to_local(hit.position)
		var critical: bool = local_hit.y > (1.3 if hit.collider.boss else 0.7)
		var ambush: float = Stealth.ambush_multiplier(hit.collider.detection)
		if ambush > 1.0:
			notice.emit("AMBUSH", 0.8)
		_sound("headshot" if critical else "hit", -4.0)
		hit.collider.take_damage(roundi((125 if critical else 42) * ambush), 0.5 if critical else 0.22)


func _cast(from: Vector3, direction: Vector3, length: float, mask: int) -> Dictionary:
	shot_query.from = from
	shot_query.to = from + direction * length
	shot_query.collision_mask = mask
	return get_world_3d().direct_space_state.intersect_ray(shot_query)


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


func _audio() -> GoatAudio:
	return get_tree().get_first_node_in_group("audio") as GoatAudio


func _sound(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var audio := _audio()
	if audio:
		audio.play(name, volume_db, pitch)


func set_crouched(value: bool) -> void:
	if crouched == value:
		return
	crouched = value
	collider_shape.height = 1.2 if crouched else 1.8
	var collider: Node3D = get_node("Collider")
	collider.position.y = -0.3 if crouched else 0.0


func _emit_movement_noise(delta: float, moving: bool) -> void:
	if not active:
		return
	if was_airborne and is_on_floor():
		noise_made.emit(global_position, Stealth.noise_radius("land"))
		_sound("land", -8.0)
	was_airborne = not is_on_floor()
	footstep_timer -= delta
	if moving and footstep_timer <= 0.0:
		footstep_timer = FOOTSTEP_INTERVAL
		var radius := Stealth.movement_noise(true, sprinting, crouched)
		if radius > 0.0:
			noise_made.emit(global_position, radius)
		_sound("footstep", -16.0 if crouched else (-6.0 if sprinting else -10.0), randf_range(0.9, 1.1))


## G: lob a stone; where it lands, the pack hears it.
func throw_decoy() -> void:
	if not active or decoys.size() >= 3:
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
	gunshot_feedback()
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
	camera.rotation.z = 0.0
	health = 100
	regen_pool = 0.0
	since_damage = 0.0
	ammo = MAGAZINE_SIZE
	reserve = maxi(reserve, 48)
	set_crouched(false)
	clear_hung()
	active = true
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
	hang_held_for = -1.0
	volley_released = false
	sensing_for = 0.0
	air_time = 0.0
	was_airborne = false
	footstep_timer = 0.0


func _reload() -> void:
	if not active or reloading or ammo == MAGAZINE_SIZE or reserve <= 0:
		return
	reloading = true
	reload_generation += 1
	var generation := reload_generation
	_sound("reload", -8.0)
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


func damage(amount: int) -> void:
	if not active:
		return
	health = maxi(0, health - amount)
	since_damage = 0.0
	regen_pool = 0.0
	_sound("hurt", -2.0, randf_range(0.9, 1.1))
	add_camera_trauma(0.16 + minf(0.46, amount / 90.0))
	health_changed.emit(health)
	if health == 0:
		active = false
		_reset_action_state()
		clear_hung()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()


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


func gunshot_feedback() -> void:
	var tween := create_tween()
	weapon.rotation.x = -0.035
	tween.tween_property(weapon, "rotation:x", 0.0, 0.08)


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


func _build_weapon() -> void:
	weapon = Node3D.new()
	weapon.name = "Herdkeeper"
	weapon.position = Vector3(0.42, -0.42, -0.55)
	weapon.scale = Vector3.ONE * 0.62
	camera.add_child(weapon)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("2b3237")
	metal.metallic = 0.85
	metal.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("14181b")
	dark.metallic = 0.7
	dark.roughness = 0.35
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("b9833c")
	brass.metallic = 0.9
	brass.roughness = 0.22
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("5a3118")
	wood.roughness = 0.62
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color("3d2a1e")
	leather.roughness = 0.95

	# Stock and grip.
	_weapon_part(_box(Vector3(0.19, 0.17, 0.36), wood), Vector3(0.0, -0.07, 0.22), Vector3(0.06, 0.0, 0.0))
	_weapon_part(_prism(Vector3(0.19, 0.1, 0.3), wood), Vector3(0.0, 0.05, 0.26), Vector3(PI, 0.0, 0.0))
	_weapon_part(_box(Vector3(0.2, 0.05, 0.06), leather), Vector3(0.0, -0.02, 0.4), Vector3.ZERO)
	_weapon_part(_capsule(0.055, 0.2, wood), Vector3(0.0, -0.17, -0.08), Vector3(-0.4, 0.0, 0.0))
	# Receiver, plate, ejection port, magazine.
	_weapon_part(_box(Vector3(0.19, 0.16, 0.52), metal), Vector3(0.0, 0.0, -0.2), Vector3.ZERO)
	_weapon_part(_box(Vector3(0.2, 0.05, 0.3), brass), Vector3(0.0, 0.09, -0.26), Vector3.ZERO)
	_weapon_part(_box(Vector3(0.012, 0.07, 0.2), dark), Vector3(0.1, 0.03, -0.3), Vector3.ZERO)
	_weapon_part(_box(Vector3(0.12, 0.3, 0.2), metal), Vector3(0.0, -0.2, -0.3), Vector3(-0.15, 0.0, 0.0))
	_weapon_part(_box(Vector3(0.14, 0.03, 0.05), metal), Vector3(0.0, 0.135, -0.32), Vector3.ZERO)
	# Bolt with a brass knob, trigger guard.
	_weapon_part(_cylinder(0.017, 0.017, 0.18, brass), Vector3(0.16, 0.05, -0.24), Vector3(0.0, 0.0, PI * 0.5))
	_weapon_part(_sphere(0.032, brass), Vector3(0.25, 0.03, -0.24), Vector3.ZERO)
	_weapon_part(_torus(0.06, 0.01, brass), Vector3(0.0, -0.1, -0.28), Vector3(0.0, 0.0, PI * 0.5))
	# Handguard, barrel bands, barrel, front sight, muzzle collar.
	var guard := _weapon_part(_cylinder(0.07, 0.08, 0.6, wood), Vector3(0.0, -0.01, -0.72), Vector3(PI * 0.5, 0.0, 0.0))
	guard.scale.x = 0.85
	for z in [-0.5, -0.98]:
		_weapon_part(_torus(0.075, 0.012, metal), Vector3(0.0, -0.01, z), Vector3(PI * 0.5, 0.0, 0.0))
	_weapon_part(_cylinder(0.034, 0.04, 0.95, metal), Vector3(0.0, 0.035, -1.05), Vector3(PI * 0.5, 0.0, 0.0))
	_weapon_part(_box(Vector3(0.05, 0.03, 0.4), metal), Vector3(0.0, 0.11, -0.62), Vector3.ZERO)
	_weapon_part(_torus(0.05, 0.009, brass), Vector3(0.0, 0.11, -1.42), Vector3.ZERO)
	_weapon_part(_cylinder(0.055, 0.055, 0.1, brass), Vector3(0.0, 0.035, -1.5), Vector3(PI * 0.5, 0.0, 0.0))
	# The Herdkeeper's mark: a small bell charm on the sling ring.
	_weapon_part(_cylinder(0.02, 0.035, 0.05, brass), Vector3(-0.1, -0.09, 0.3), Vector3.ZERO)

	muzzle_flash = OmniLight3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.position = Vector3(0.0, 0.04, -1.6)
	muzzle_flash.light_color = Color("ffb44f")
	muzzle_flash.light_energy = 0.0
	muzzle_flash.omni_range = 5.0
	weapon.add_child(muzzle_flash)


func _weapon_part(mesh: Mesh, at: Vector3, rotation_value: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rotation_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon.add_child(instance)
	return instance


func _box(size: Vector3, material: Material) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return mesh


func _prism(size: Vector3, material: Material) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.material = material
	return mesh


func _cylinder(top: float, bottom: float, height: float, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 14
	mesh.material = material
	return mesh


func _sphere(radius: float, material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = material
	return mesh


func _capsule(radius: float, height: float, material: Material) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height + radius * 2.0
	mesh.material = material
	return mesh


func _torus(radius: float, ring: float, material: Material) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - ring
	mesh.outer_radius = radius + ring
	mesh.material = material
	return mesh
