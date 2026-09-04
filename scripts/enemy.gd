class_name WolverineEnemy
extends CharacterBody3D
## A wolverine of Varkas' warpack: the Quaternius wolf re-tinted and re-armed,
## driven by a patrol / suspicious / alert / search state machine fed by sight,
## hearing, and scent (see Stealth).

signal killed(enemy: WolverineEnemy)
signal spotted(enemy: WolverineEnemy)
signal boss_phase_changed(enemy: WolverineEnemy, phase_index: int, phase_title: String)
signal boss_attack(enemy: WolverineEnemy, attack_name: String)

enum State { PATROL, SUSPICIOUS, ALERT, SEARCH, DORMANT }

const WOLF_SCENE := preload("res://assets/wolf/wolf.glb")
const WORLD_AND_PLAYER_MASK := 1
const PATROL_SPEED := 1.7
const HOWL_RANGE := 20.0
const LOSE_SECONDS := 9.0
const SEARCH_SECONDS := 8.0
const INVESTIGATE_WAIT := 4.0

var target: GoatPlayer
var role := "rifleman"
var boss := false
var health := 110
var max_health := 110
var speed := 2.4
var attack_damage := 12
var attack_range := 3.2
var ranged_range := 0.0
var ranged_accuracy := 0.0
var attack_cooldown := 1.15
var cooldown := 0.0
var phase := 0.0
var stagger := 0.0
var flank := 0.0
var dead := false
var bell_index := -1
var home_position := Vector3.ZERO
var boss_phase := 0
var boss_ability_cooldown := 0.0
var boss_transition_lock := 0.0
var boss_charge_for := 0.0
var boss_armor: Array[MeshInstance3D] = []
var execution_ready := false

## Perception.
var state := State.PATROL
var detection := 0.0
var sense_rate := 0.0
var last_known := Vector3.ZERO
var investigate_point := Vector3.ZERO
var lost_for := 0.0
var wait_for := 0.0
var patrol: Array = []
var patrol_index := 0
var perception_tick := 0
var has_los := false

## Model.
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var body_material: StandardMaterial3D
var eye_material: StandardMaterial3D
var eye_light: OmniLight3D
var current_anim := ""
var los_query: PhysicsRayQueryParameters3D
## Decorations that ride on bones: {node, bone, offset}. Followed manually with a
## normalized basis, because the rig bakes a large scale into its bones.
var riders: Array = []


func configure(player: GoatPlayer, enemy_role: String, spawn_position: Vector3, route: Array = [], trophy_bell := -1) -> void:
	target = player
	role = enemy_role
	bell_index = trophy_bell
	position = spawn_position
	home_position = spawn_position
	patrol = route.duplicate()
	if patrol.is_empty():
		patrol = [spawn_position]
	match role:
		"stalker":
			health = 82
			speed = 4.4
			attack_range = 2.4
			attack_damage = 15
		"rifleman":
			health = 110
			speed = 2.6
			attack_range = 2.8
			attack_damage = 10
			ranged_range = 20.0
			ranged_accuracy = 0.45
			attack_cooldown = 1.5
		"brute":
			health = 210
			speed = 2.1
			attack_range = 3.4
			attack_damage = 26
		"boss":
			boss = true
			boss_phase = 1
			health = 780
			speed = 3.4
			attack_range = 4.0
			attack_damage = 30
			ranged_range = 24.0
			ranged_accuracy = 0.6
			attack_cooldown = 0.9
			boss_ability_cooldown = 3.5
			state = State.DORMANT
	max_health = health
	phase = randf() * TAU
	flank = (1.0 if randf() < 0.5 else -1.0) * randf_range(0.35, 0.65)
	add_to_group("enemies")
	_build_body()
	_play("Idle")


func _sound(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var audio := get_tree().get_first_node_in_group("audio") as GoatAudio
	if audio:
		audio.play_at(name, global_position + Vector3(0.0, 0.8, 0.0), volume_db, pitch)


func awareness() -> String:
	return Stealth.awareness_of(detection)


func chest_position() -> Vector3:
	return global_position + Vector3(0.0, 0.95 if boss else 0.55, 0.0)


func eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.35 if boss else 0.8, 0.0) + facing() * (0.9 if boss else 0.5)


func facing() -> Vector3:
	return -global_transform.basis.z


func wake() -> void:
	if state == State.DORMANT:
		state = State.ALERT
		detection = Stealth.ALERT
		last_known = target.global_position
		spotted.emit(self)
		if boss:
			boss_phase_changed.emit(self, boss_phase, boss_phase_title())


## Something happened at `source` loud enough to reach `radius` metres.
func hear_noise(source: Vector3, radius: float) -> void:
	if dead or state == State.DORMANT or not Stealth.hears(source, global_position, radius):
		return
	if radius >= Stealth.NOISE.volley:
		_go_alert(source)
	elif state != State.ALERT:
		detection = maxf(detection, Stealth.SUSPICIOUS)
		investigate_point = source
		wait_for = 0.0
		if state != State.SUSPICIOUS:
			_sound("huff", -4.0, randf_range(0.85, 1.1))
		state = State.SUSPICIOUS


## A packmate howled: converge on the goat.
func alert_to(source: Vector3) -> void:
	if dead or state == State.DORMANT:
		return
	_go_alert(source)


func _go_alert(source: Vector3) -> void:
	var was_alert := state == State.ALERT
	state = State.ALERT
	detection = Stealth.ALERT
	last_known = source
	lost_for = 0.0
	if not was_alert:
		spotted.emit(self)
		_sound("howl", 2.0 if boss else -2.0, 0.7 if boss else randf_range(0.9, 1.15))
		for other in get_tree().get_nodes_in_group("enemies"):
			if other != self and not other.dead and other.global_position.distance_to(global_position) < HOWL_RANGE:
				other.alert_to(source)


## Reset to patrol after the goat respawns at a checkpoint.
func calm() -> void:
	if dead or state == State.DORMANT:
		return
	state = State.PATROL
	detection = 0.0
	lost_for = 0.0
	wait_for = 0.0
	patrol_index = 0
	velocity = Vector3.ZERO
	global_position = home_position


func _physics_process(delta: float) -> void:
	if dead:
		return
	if not is_instance_valid(target) or not target.active or state == State.DORMANT:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		_play("Idle")
		_follow_bones()
		return

	cooldown = maxf(0.0, cooldown - delta)
	boss_ability_cooldown = maxf(0.0, boss_ability_cooldown - delta)
	boss_transition_lock = maxf(0.0, boss_transition_lock - delta)
	phase += delta
	_perceive(delta)

	var offset := target.global_position - global_position
	var distance := Vector2(offset.x, offset.z).length()
	var to_goat := Vector3(offset.x, 0.0, offset.z).normalized()
	var desired := Vector3.ZERO
	var move_speed := PATROL_SPEED
	var look_at_point := global_position + facing()

	if stagger > 0.0:
		stagger -= delta
	else:
		match state:
			State.PATROL:
				var goal: Vector3 = patrol[patrol_index]
				if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 1.2 or patrol.size() == 1:
					if wait_for <= 0.0:
						wait_for = randf_range(2.0, 4.5)
					wait_for -= delta
					if wait_for <= 0.0 and patrol.size() > 1:
						patrol_index = (patrol_index + 1) % patrol.size()
					look_at_point = global_position + facing().rotated(Vector3.UP, sin(phase * 0.7) * 0.02)
				else:
					desired = _steer_to(goal)
					look_at_point = global_position + desired
			State.SUSPICIOUS:
				if Vector2(investigate_point.x - global_position.x, investigate_point.z - global_position.z).length() > 1.6:
					desired = _steer_to(investigate_point)
					move_speed = PATROL_SPEED * 1.35
					look_at_point = global_position + desired
				else:
					wait_for += delta
					look_at_point = global_position + Vector3(cos(phase * 1.3), 0.0, sin(phase * 1.3))
					if wait_for > INVESTIGATE_WAIT and detection < Stealth.SUSPICIOUS:
						state = State.PATROL
						wait_for = 0.0
			State.ALERT:
				move_speed = speed
				if has_los:
					last_known = target.global_position
					lost_for = 0.0
					look_at_point = target.global_position
					if fmod(phase, 3.4) < delta:
						_sound("growl", -6.0, 0.7 if boss else randf_range(0.9, 1.2))
					if distance > attack_range and not (ranged_range > 0.0 and distance < ranged_range * 0.7):
						var spread := flank if distance > attack_range + 6.0 else 0.0
						desired = to_goat.rotated(Vector3.UP, spread) + _separation()
					else:
						desired = to_goat.rotated(Vector3.UP, PI * 0.5) * sin(phase * 1.8) * 0.5 + _separation()
						if cooldown <= 0.0:
							if distance <= attack_range:
								target.damage(attack_damage)
								cooldown = attack_cooldown
								_play("Attack", true)
								_sound("bite", 0.0, 0.8 if boss else 1.0)
							elif ranged_range > 0.0:
								if randf() < ranged_accuracy:
									target.damage(int(attack_damage * 0.6) + randi_range(0, 4))
								cooldown = attack_cooldown + randf_range(0.0, 0.6)
								_play("Attack", true)
								_sound("shot", -6.0, 0.85)
				else:
					lost_for += delta
					if Vector2(last_known.x - global_position.x, last_known.z - global_position.z).length() > 1.5:
						desired = _steer_to(last_known)
						look_at_point = global_position + desired
					else:
						look_at_point = global_position + Vector3(cos(phase * 1.6), 0.0, sin(phase * 1.6))
					if lost_for > LOSE_SECONDS:
						state = State.SEARCH
						wait_for = 0.0
						detection = Stealth.SUSPICIOUS + 0.2
			State.SEARCH:
				wait_for += delta
				move_speed = PATROL_SPEED * 1.2
				var wander := last_known + Vector3(cos(phase * 0.9), 0.0, sin(phase * 0.9)) * 5.0
				desired = _steer_to(wander) * 0.8
				look_at_point = global_position + desired
				if wait_for > SEARCH_SECONDS:
					state = State.PATROL
					wait_for = 0.0

	if boss and state == State.ALERT:
		var boss_override := _boss_motion(distance, to_goat)
		if boss_override.length_squared() > 0.0:
			desired = boss_override
			move_speed = speed

	if stagger > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, desired.x * move_speed, 8.0 * delta)
		velocity.z = move_toward(velocity.z, desired.z * move_speed, 8.0 * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

	var flat_look := Vector3(look_at_point.x, global_position.y, look_at_point.z)
	if flat_look.distance_squared_to(global_position) > 0.01:
		var current := global_transform.basis.get_rotation_quaternion()
		var wanted := Transform3D().looking_at(flat_look - global_position, Vector3.UP).basis.get_rotation_quaternion()
		global_transform.basis = Basis(current.slerp(wanted, minf(1.0, delta * (7.0 if state == State.ALERT else 3.5))))

	_animate(delta)


func _steer_to(goal: Vector3) -> Vector3:
	var direction := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if direction.length() < 0.01:
		return Vector3.ZERO
	return (direction.normalized() + _separation()).normalized()


func boss_phase_title() -> String:
	if not boss:
		return ""
	return Story.BOSS_PHASES.get(boss_phase, {}).get("title", "VARKAS")


## Varkas keeps the normal hunt brain, then layers readable set-piece attacks
## on top: a radial bellquake in phase two and a committed charge in phase three.
func _boss_motion(distance: float, to_goat: Vector3) -> Vector3:
	if boss_transition_lock > 0.0:
		return Vector3.ZERO
	if boss_charge_for > 0.0:
		boss_charge_for = maxf(0.0, boss_charge_for - get_physics_process_delta_time())
		if distance <= attack_range + 0.9 and cooldown <= 0.0:
			target.damage(38)
			target.knockback(global_position, 10.0, 4.5)
			cooldown = 1.1
			boss_charge_for = 0.0
			_sound("bite", 4.0, 0.62)
		return to_goat * 2.1
	if not has_los or boss_ability_cooldown > 0.0:
		return Vector3.ZERO
	if boss_phase == 2 and distance <= 13.0:
		boss_ability_cooldown = 5.6
		_begin_bellquake()
	elif boss_phase >= 3 and distance <= 18.0:
		boss_ability_cooldown = 3.7
		boss_charge_for = 1.25
		boss_attack.emit(self, "charge")
		_sound("growl", 3.0, 0.58)
		_shockwave_visual(Color("b92f1f"), 3.0, 0.28)
		return to_goat * 2.1
	return Vector3.ZERO


func _begin_bellquake() -> void:
	boss_transition_lock = 0.72
	boss_attack.emit(self, "bellquake")
	_sound("bell", 5.0, 0.55)
	_shockwave_visual(Color("d98b45"), 12.0, 0.74)
	await get_tree().create_timer(0.68).timeout
	if dead or not is_instance_valid(target) or not target.active:
		return
	var distance := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()
	if distance <= 11.5:
		target.damage(18)
		target.knockback(global_position, 8.0, 3.0)


func _shockwave_visual(color: Color, radius: float, seconds: float) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "Bellquake"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.0
	mesh.rings = 24
	mesh.ring_segments = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	ring.mesh = mesh
	ring.position.y = 0.12
	ring.scale = Vector3.ONE * 0.2
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * radius, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, seconds)
	tween.chain().tween_callback(ring.queue_free)


func _perceive(delta: float) -> void:
	perception_tick += 1
	if perception_tick % 3 == 0:
		has_los = _has_line_of_sight()
		var to_goat := target.chest_position() - eye_position()
		var sight := Stealth.sight_rate(facing(), to_goat, has_los, target.crouched, target.light_exposure)
		var wind := Stealth.wind_at(Time.get_ticks_msec() * 0.001)
		var scent := Stealth.scent_strength(target.global_position, global_position, wind) * Stealth.SCENT_RATE
		sense_rate = sight + scent
		if has_los and state == State.ALERT:
			sense_rate = maxf(sense_rate, 1.0)
	var before := detection
	detection = Stealth.step_detection(detection, sense_rate, delta)
	if detection >= Stealth.ALERT and state != State.ALERT:
		_go_alert(target.global_position)
	elif detection >= Stealth.SUSPICIOUS and state == State.PATROL and before < Stealth.SUSPICIOUS:
		state = State.SUSPICIOUS
		investigate_point = target.global_position
		wait_for = 0.0
		_sound("huff", -4.0, randf_range(0.85, 1.1))
	elif state == State.SUSPICIOUS and sense_rate > 0.0:
		investigate_point = target.global_position


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or other.dead:
			continue
		var gap_vector: Vector3 = global_position - other.global_position
		gap_vector.y = 0.0
		var min_gap := 3.4 if boss or other.boss else 2.4
		var gap := gap_vector.length()
		if gap > 0.01 and gap < min_gap:
			push += gap_vector / gap * (1.0 - gap / min_gap) * 1.6
	return push


func _has_line_of_sight() -> bool:
	if los_query == null:
		los_query = PhysicsRayQueryParameters3D.new()
		los_query.exclude = [get_rid()]
		los_query.collision_mask = WORLD_AND_PLAYER_MASK
	los_query.from = eye_position()
	los_query.to = target.chest_position()
	var hit := get_world_3d().direct_space_state.intersect_ray(los_query)
	return hit and hit.collider == target


func take_damage(amount: int, stagger_seconds := 0.22, silent := false) -> void:
	if dead or execution_ready:
		return
	# Phase breaks are real beats, not thresholds a multi-shot volley can cross in
	# one frame. Iron and bell-light reject damage during the short transition.
	if boss and boss_transition_lock > 0.0:
		return
	health -= amount
	_spawn_blood(amount, health <= 0 and not boss)
	if boss and boss_phase == 1 and health <= ceili(max_health * 0.66):
		health = maxi(health, ceili(max_health * 0.66))
		_enter_boss_phase(2)
	elif boss and boss_phase == 2 and health <= ceili(max_health * 0.33):
		health = maxi(health, ceili(max_health * 0.33))
		_enter_boss_phase(3)
	stagger = maxf(stagger, 0.06 if boss else stagger_seconds)
	if body_material:
		body_material.emission_enabled = true
		body_material.emission = Color("ff5b27")
		body_material.emission_energy_multiplier = 1.8
		var tween := create_tween()
		tween.tween_property(body_material, "emission_energy_multiplier", 0.0, 0.16)
	if boss and boss_phase >= 3 and health <= 0:
		_break_for_execution()
		return
	if health <= 0:
		_die()
		return
	_play("Idle_HitReact_Left" if randf() < 0.5 else "Idle_HitReact_Right", true)
	_sound("yelp", -6.0, 0.6 if boss else randf_range(0.9, 1.2))
	if not silent:
		_go_alert(target.global_position if target else global_position)


func _enter_boss_phase(next_phase: int) -> void:
	if not boss or next_phase <= boss_phase:
		return
	boss_phase = next_phase
	boss_transition_lock = 1.25
	stagger = maxf(stagger, 1.25)
	boss_ability_cooldown = 1.8
	if boss_phase == 2:
		speed = 4.5
		attack_damage = 34
		attack_cooldown = 0.72
		ranged_accuracy = 0.72
		for i in boss_armor.size():
			if i % 2 == 0 and is_instance_valid(boss_armor[i]):
				boss_armor[i].visible = false
	else:
		speed = 6.2
		attack_range = 4.8
		attack_damage = 40
		attack_cooldown = 0.54
		ranged_range = 0.0
		for plate in boss_armor:
			if is_instance_valid(plate):
				plate.visible = false
		if body_material:
			body_material.albedo_color = Color("7e1e15")
	if eye_material:
		eye_material.emission = Color("ff321f")
		eye_material.emission_energy_multiplier = 4.6
	if eye_light:
		eye_light.light_color = Color("ff321f")
		eye_light.light_energy = 1.4
	_sound("howl", 5.0, 0.55 if boss_phase == 2 else 0.48)
	_shockwave_visual(Color("d06a32") if boss_phase == 2 else Color("a91512"), 5.0, 0.55)
	boss_phase_changed.emit(self, boss_phase, boss_phase_title())


func _break_for_execution() -> void:
	execution_ready = true
	health = 1
	state = State.DORMANT
	velocity = Vector3.ZERO
	stagger = 999.0
	boss_transition_lock = 999.0
	if eye_light:
		eye_light.light_energy = 0.18
	if eye_material:
		eye_material.emission_energy_multiplier = 0.5
	_play("Idle_HitReact_Left", true)
	_sound("death", -1.0, 0.5)
	boss_attack.emit(self, "broken")


func execute_boss() -> void:
	if not boss or dead or not execution_ready:
		return
	execution_ready = false
	health = 0
	boss_transition_lock = 0.0
	_spawn_blood(240, true)
	_die()


## A horn strike from behind: instant, silent.
func takedown() -> void:
	if dead:
		return
	health = 0
	_spawn_blood(180, true)
	_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	remove_from_group("enemies")
	killed.emit(self)
	set_physics_process(false)
	_sound("death", 0.0, 0.6 if boss else randf_range(0.9, 1.15))
	if eye_light:
		eye_light.light_energy = 0.0
	if eye_material:
		eye_material.emission_energy_multiplier = 0.0
	for rider in riders:
		rider.node.queue_free()
	riders.clear()
	_play("Death", true)
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(self, "position:y", position.y - 1.4, 1.2)
	tween.tween_callback(queue_free)


## A small, dark spray on impact and one ground stain on a fatal hit. The effect
## is intentionally brief and stylised; it supports the grittier tone without
## turning every encounter into a particle fog.
func _spawn_blood(amount: int, fatal: bool) -> void:
	if not is_inside_tree():
		return
	var spray := GPUParticles3D.new()
	spray.name = "BloodSpray"
	spray.amount = 16 if fatal else clampi(4 + amount / 28, 5, 10)
	spray.lifetime = 0.65
	spray.one_shot = true
	spray.explosiveness = 1.0
	spray.position = Vector3(0.0, 0.75 if boss else 0.48, 0.0)
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
	add_child(spray)
	spray.emitting = true
	var cleanup := spray.create_tween()
	cleanup.tween_interval(1.6)
	cleanup.tween_callback(spray.queue_free)
	if not fatal or get_parent() == null:
		return
	var stain := MeshInstance3D.new()
	stain.name = "BloodStain"
	var stain_mesh := PlaneMesh.new()
	stain_mesh.size = Vector2(1.45 if boss else 0.72, 0.9 if boss else 0.48)
	var stain_material := StandardMaterial3D.new()
	stain_material.albedo_color = Color(0.19, 0.005, 0.004, 0.72)
	stain_material.roughness = 0.98
	stain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stain_mesh.material = stain_material
	stain.mesh = stain_mesh
	stain.position = Vector3(global_position.x, global_position.y + 0.035, global_position.z)
	stain.rotation.y = phase
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(stain)


# --- Model --------------------------------------------------------------------

func _build_body() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	var target_height := 1.9 if boss else (1.35 if role == "brute" else (0.95 if role == "stalker" else 1.1))
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42 if not boss else 0.8
	capsule.height = target_height + 0.3
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	add_child(collider)

	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var wolf: Node = WOLF_SCENE.instantiate()
	model.add_child(wolf)
	anim = _find(wolf, "AnimationPlayer") as AnimationPlayer
	skeleton = _find(wolf, "Skeleton3D") as Skeleton3D
	var mesh_instance := _find(wolf, "MeshInstance3D") as MeshInstance3D
	_fit_model(wolf, target_height)
	if anim:
		for name in ["Idle", "Walk", "Gallop", "Eating", "Idle_2", "Idle_2_HeadLow"]:
			if anim.has_animation(name):
				anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR

	body_material = StandardMaterial3D.new()
	match role:
		"boss":
			body_material.albedo_color = Color("6a2418")
		"brute":
			body_material.albedo_color = Color("3d464f")
		"stalker":
			body_material.albedo_color = Color("2a221c")
		_:
			body_material.albedo_color = Color("4a3d31")
	body_material.roughness = 0.82
	var light_material := body_material.duplicate() as StandardMaterial3D
	light_material.albedo_color = body_material.albedo_color.lightened(0.3)
	eye_material = StandardMaterial3D.new()
	eye_material.albedo_color = Color("ffb340")
	eye_material.emission_enabled = true
	eye_material.emission = Color("6fb6ff")
	eye_material.emission_energy_multiplier = 2.4
	if mesh_instance:
		for i in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.mesh.surface_get_material(i)
			var surface_name := original.resource_name if original else ""
			match surface_name:
				"Main":
					mesh_instance.set_surface_override_material(i, body_material)
				"Main_Light":
					mesh_instance.set_surface_override_material(i, light_material)
				"Eyes_Black":
					mesh_instance.set_surface_override_material(i, eye_material)
	_dress()


func _fit_model(wolf: Node, target_height: float) -> void:
	if skeleton == null:
		return
	var low := INF
	var high := -INF
	var front := -INF
	var back := INF
	var head_z := 0.0
	var tail_z := 0.0
	var skeleton_to_model: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform
	for i in skeleton.get_bone_count():
		var origin: Vector3 = skeleton_to_model * skeleton.get_bone_global_rest(i).origin
		low = minf(low, origin.y)
		high = maxf(high, origin.y)
		front = maxf(front, origin.z)
		back = minf(back, origin.z)
		var bone_name := skeleton.get_bone_name(i)
		if bone_name == "Head":
			head_z = origin.z
		elif bone_name == "Tail1":
			tail_z = origin.z
	var height := maxf(0.01, high - low)
	var factor := target_height / height
	wolf.scale = Vector3.ONE * factor
	# Godot's forward is -Z; turn the model round if its head points down +Z.
	if head_z > tail_z:
		wolf.rotation.y = PI
	wolf.position.y = -low * factor + 0.02


func _dress() -> void:
	if skeleton == null:
		return
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("2a3136")
	iron.metallic = 0.9
	iron.roughness = 0.35
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("c58a34")
	brass.metallic = 0.9
	brass.roughness = 0.25
	brass.emission_enabled = true
	brass.emission = Color("5a2a08")
	brass.emission_energy_multiplier = 0.5
	# Eyes light: a small glow that follows the head.
	var head := _attach("Head")
	if head:
		eye_light = OmniLight3D.new()
		eye_light.light_color = Color("6fb6ff")
		eye_light.light_energy = 0.35
		eye_light.omni_range = 1.6
		eye_light.position = Vector3(0.0, 0.0, 0.25)
		head.add_child(eye_light)
	# A stolen herd bell on a collar.
	if bell_index >= 0:
		var neck := _attach("Neck2")
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
	if role == "rifleman":
		var back := _attach("Back")
		if back:
			var rifle := MeshInstance3D.new()
			var rifle_mesh := BoxMesh.new()
			rifle_mesh.size = Vector3(0.06, 0.08, 1.05)
			rifle_mesh.material = iron
			rifle.mesh = rifle_mesh
			rifle.position = Vector3(0.0, 0.42, 0.1)
			rifle.rotation_degrees = Vector3(0.0, 0.0, 0.0)
			back.add_child(rifle)
	if boss:
		# Varkas wears the herd's iron: plates along the spine and a great bell.
		for bone in ["Torso", "Torso2", "Torso3"]:
			var spine := _attach(bone)
			if spine:
				var plate := MeshInstance3D.new()
				var plate_mesh := BoxMesh.new()
				plate_mesh.size = Vector3(0.62, 0.18, 0.5)
				plate_mesh.material = iron
				plate.mesh = plate_mesh
				plate.position = Vector3(0.0, 0.38, 0.0)
				spine.add_child(plate)
				boss_armor.append(plate)
				for side in [-1.0, 1.0]:
					var spike := MeshInstance3D.new()
					var spike_mesh := PrismMesh.new()
					spike_mesh.size = Vector3(0.12, 0.34, 0.12)
					spike_mesh.material = iron
					spike.mesh = spike_mesh
					spike.position = Vector3(side * 0.22, 0.58, 0.0)
					spine.add_child(spike)
					boss_armor.append(spike)
		var neck := _attach("Neck2")
		if neck:
			var great_bell := MeshInstance3D.new()
			var great_mesh := CylinderMesh.new()
			great_mesh.top_radius = 0.14
			great_mesh.bottom_radius = 0.24
			great_mesh.height = 0.34
			great_mesh.material = brass
			great_bell.mesh = great_mesh
			great_bell.position = Vector3(0.0, -0.55, 0.1)
			neck.add_child(great_bell)


func _attach(bone_name: String) -> Node3D:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return null
	var rider := Node3D.new()
	rider.name = "Rider_" + bone_name
	add_child(rider)
	rider.top_level = true
	riders.append({"node": rider, "bone": index})
	_follow_bones()
	return rider


func _follow_bones() -> void:
	if skeleton == null:
		return
	for rider in riders:
		var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(rider.bone)
		rider.node.global_transform = Transform3D(pose.basis.orthonormalized(), pose.origin)


func _find(node: Node, type_name: String) -> Node:
	var stack := [node]
	while stack:
		var current: Node = stack.pop_back()
		if current.get_class() == type_name:
			return current
		stack.append_array(current.get_children())
	return null


func _play(name: String, oneshot := false) -> void:
	if anim == null or not anim.has_animation(name):
		return
	if oneshot:
		anim.play(name, 0.12)
		current_anim = name
		return
	if current_anim == name and anim.is_playing():
		return
	if anim.is_playing() and current_anim in ["Attack", "Idle_HitReact_Left", "Idle_HitReact_Right", "Death"]:
		return
	current_anim = name
	anim.play(name, 0.25)


func _animate(delta: float) -> void:
	_follow_bones()
	if anim == null:
		return
	if current_anim in ["Attack", "Idle_HitReact_Left", "Idle_HitReact_Right"] and anim.is_playing():
		return
	var planar := Vector2(velocity.x, velocity.z).length()
	if planar < 0.25:
		_play("Idle" if state != State.PATROL else ("Eating" if int(phase) % 9 == 0 else "Idle"))
		anim.speed_scale = 1.0
	elif planar < 2.6:
		_play("Walk")
		anim.speed_scale = clampf(planar / 1.7, 0.6, 1.6)
	else:
		_play("Gallop")
		anim.speed_scale = clampf(planar / 4.0, 0.8, 1.5)
	# Eyes tell the goat what the wolverine knows: cold blue, amber, then red.
	if eye_material:
		var color := Color("6fb6ff")
		if detection >= Stealth.ALERT:
			color = Color("ff2a1a")
		elif detection >= Stealth.SUSPICIOUS:
			color = Color("ffb03a")
		eye_material.emission = eye_material.emission.lerp(color, minf(1.0, delta * 6.0))
		if eye_light:
			eye_light.light_color = eye_material.emission
			eye_light.light_energy = 0.35 + detection * 0.6
