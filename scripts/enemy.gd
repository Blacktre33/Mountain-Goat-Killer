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
const VARKAS_SCENE := preload("res://assets/wolf/varkas_wolverine.glb")
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
var boss_windup_for := 0.0
var boss_recovery_for := 0.0
var boss_attack_kind := ""
var boss_attack_direction := Vector3.FORWARD
var boss_telegraph: MeshInstance3D
var boss_armor: Array[MeshInstance3D] = []
var boss_embers: GPUParticles3D
var boss_aura: OmniLight3D
var boss_red_horn: MeshInstance3D
var boss_shell: Node3D
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
var body_light_material: StandardMaterial3D
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
			ranged_range = 0.0
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
	return global_position + Vector3(0.0, 1.55 if boss else 0.55, 0.0)


func eye_position() -> Vector3:
	return global_position + Vector3(0.0, 2.18 if boss else 0.8, 0.0) + facing() * (1.42 if boss else 0.5)


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


## A failed climax restarts as a complete set piece rather than leaving Varkas
## half-broken, roaming as a normal patrol, or carrying an execution lock into
## the next attempt.
func reset_boss_encounter() -> void:
	if not boss or dead:
		return
	health = max_health
	_cancel_boss_attack()
	boss_phase = 1
	speed = 3.4
	attack_range = 4.0
	attack_damage = 30
	attack_cooldown = 0.9
	cooldown = 0.0
	boss_transition_lock = 0.0
	boss_ability_cooldown = 3.5
	boss_charge_for = 0.0
	execution_ready = false
	stagger = 0.0
	state = State.DORMANT
	detection = 0.0
	lost_for = 0.0
	wait_for = 0.0
	velocity = Vector3.ZERO
	global_position = home_position
	_apply_boss_phase_appearance()
	_play("Idle")


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
				if boss:
					# Varkas owns one attack timeline. The warpack's immediate bite
					# and random ranged damage must never run beneath a boss tell.
					look_at_point = target.global_position
				elif has_los:
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
		desired = boss_override
		move_speed = speed
		if boss_windup_for > 0.0 or boss_charge_for > 0.0:
			look_at_point = global_position + boss_attack_direction
		if desired.is_zero_approx():
			velocity.x = 0.0
			velocity.z = 0.0

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


## One timeline owns tells, impacts, and recovery. A charge locks its aim at
## the warning, then travels straight; both a sidestep and Convergence can beat it.
func _boss_motion(distance: float, to_goat: Vector3, delta := -1.0) -> Vector3:
	if delta < 0.0:
		delta = get_physics_process_delta_time()
	if boss_transition_lock > 0.0 or execution_ready or dead:
		return Vector3.ZERO
	if boss_recovery_for > 0.0:
		boss_recovery_for = maxf(0.0, boss_recovery_for - delta)
		return -to_goat * 0.65 if distance < 5.2 else Vector3.ZERO
	if boss_windup_for > 0.0:
		boss_windup_for = maxf(0.0, boss_windup_for - delta)
		if boss_windup_for <= 0.0:
			_clear_boss_telegraph()
			if boss_attack_kind == "charge":
				boss_charge_for = 1.15
				boss_attack.emit(self, "charge_release")
			elif boss_attack_kind == "bellquake":
				# A jump clears the ground pulse; stone cover also blocks it.
				var above_ground := target.global_position.y - WorldBuilder.height_at(target.global_position.x, target.global_position.z)
				if distance <= 11.5 and above_ground < 1.65 and _has_line_of_sight():
					target.damage(18)
					target.knockback(global_position, 7.0, 2.0)
				_shockwave_visual(Color("f8cd89"), 11.5, 0.25)
				_finish_boss_attack(1.25)
			else:
				if distance <= 6.0 and boss_attack_direction.dot(to_goat) > 0.5 and _has_line_of_sight():
					target.damage(26 if boss_phase == 1 else 32)
					target.knockback(global_position, 6.0, 2.0)
				_play("Attack", true)
				_sound("bite", 1.0, 0.7)
				_finish_boss_attack(1.15)
		return Vector3.ZERO
	if boss_charge_for > 0.0:
		boss_charge_for = maxf(0.0, boss_charge_for - delta)
		var offset := target.global_position - global_position
		offset.y = 0.0
		var forward := offset.dot(boss_attack_direction)
		var lateral := (offset - boss_attack_direction * forward).length()
		if forward >= 0.0 and forward <= 4.5 and lateral <= 1.65 and _has_line_of_sight():
			target.damage(38)
			target.knockback(global_position, 10.0, 3.0)
			_sound("bite", 4.0, 0.62)
			_finish_boss_attack(1.65)
			return Vector3.ZERO
		if boss_charge_for <= 0.0 or is_on_wall():
			_finish_boss_attack(1.65)
			return Vector3.ZERO
		return boss_attack_direction * 2.1
	if not has_los:
		return _steer_to(target.global_position) if distance > 6.0 else Vector3.ZERO
	if boss_ability_cooldown <= 0.0:
		if boss_phase == 2 and distance <= 13.0:
			_begin_bellquake()
			return Vector3.ZERO
		if boss_phase >= 3 and distance <= 18.0:
			boss_ability_cooldown = 5.2
			boss_attack_kind = "charge"
			boss_attack_direction = to_goat
			boss_windup_for = 0.95
			boss_attack.emit(self, "charge")
			_sound("growl", 3.0, 0.58)
			_show_charge_lane()
			return Vector3.ZERO
	if distance <= 6.2 and cooldown <= 0.0:
		boss_attack_kind = "swipe"
		boss_attack_direction = to_goat
		boss_windup_for = 0.85
		boss_attack.emit(self, "swipe")
		_sound("growl", 0.0, 0.65)
		boss_telegraph = _shockwave_visual(Color("d98b45"), 6.0, 0.85)
		return Vector3.ZERO
	# Keep the muzzle out of the camera between attacks, including when the
	# player walks into him. Only the announced charge closes aggressively.
	if distance < 5.2:
		return -to_goat * 0.65
	if distance > 6.4:
		return to_goat + _separation() * 0.25
	return Vector3.ZERO


func _begin_bellquake() -> void:
	boss_ability_cooldown = 6.0
	boss_attack_kind = "bellquake"
	boss_windup_for = 1.2
	boss_attack_direction = facing()
	boss_attack.emit(self, "bellquake")
	_sound("bell", 5.0, 0.55)
	boss_telegraph = _shockwave_visual(Color("d98b45"), 11.5, 1.2)


func _finish_boss_attack(recovery: float) -> void:
	_cancel_boss_attack()
	boss_recovery_for = recovery
	cooldown = recovery + 0.65
	boss_attack.emit(self, "exposed")


func _clear_boss_telegraph() -> void:
	if is_instance_valid(boss_telegraph):
		boss_telegraph.queue_free()
	boss_telegraph = null


func _cancel_boss_attack() -> void:
	_clear_boss_telegraph()
	boss_windup_for = 0.0
	boss_charge_for = 0.0
	boss_recovery_for = 0.0
	boss_attack_kind = ""


func _show_charge_lane() -> void:
	_clear_boss_telegraph()
	boss_telegraph = MeshInstance3D.new()
	boss_telegraph.name = "RedHornChargeLane"
	# Follow the actual height field. A flat warning plane becomes buried when
	# the charge crosses even a small rise in the now-visible courtyard ground.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var across := boss_attack_direction.cross(Vector3.UP)
	for segment in 30:
		var corners: Array[Vector3] = []
		for offset in [Vector2(-1.2, 0.0), Vector2(1.2, 0.0), Vector2(-1.2, 1.0), Vector2(1.2, 1.0)]:
			var point: Vector3 = global_position + boss_attack_direction * (2.5 + (segment + offset.y) * 0.5) + across * offset.x
			point.y = WorldBuilder.height_at(point.x, point.z) + 0.12
			corners.append(point)
		var uvs := [Vector2(0.0, segment / 30.0), Vector2(1.0, segment / 30.0), Vector2(0.0, (segment + 1) / 30.0), Vector2(1.0, (segment + 1) / 30.0)]
		for index in [0, 2, 1, 1, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(uvs[index])
			surface.add_vertex(corners[index])
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	float across = abs(UV.x - 0.5);
	float edges = smoothstep(0.41, 0.46, across);
	float spine = (1.0 - smoothstep(0.018, 0.04, across)) * step(0.48, fract(UV.y * 14.0));
	ALBEDO = vec3(0.65, 0.09, 0.035);
	EMISSION = vec3(0.55, 0.035, 0.008);
	ALPHA = max(edges * 0.62, spine * 0.48);
}
"""
	material.shader = shader
	boss_telegraph.mesh = surface.commit()
	boss_telegraph.material_override = material
	boss_telegraph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(boss_telegraph)
	boss_telegraph.top_level = true
	boss_telegraph.global_transform = Transform3D.IDENTITY


func _shockwave_visual(color: Color, radius: float, seconds: float) -> MeshInstance3D:
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
	return ring


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
	var phase_before := boss_phase
	health -= amount
	_spawn_blood(amount, health <= 0 and not boss)
	if boss and boss_phase == 1 and health <= ceili(max_health * 0.66):
		health = maxi(health, ceili(max_health * 0.66))
		_enter_boss_phase(2)
	elif boss and boss_phase == 2 and health <= ceili(max_health * 0.33):
		health = maxi(health, ceili(max_health * 0.33))
		_enter_boss_phase(3)
	stagger = maxf(stagger, 0.06 if boss else stagger_seconds)
	if boss and boss_phase == phase_before and stagger_seconds >= Remembrance.CONVERGENCE_STAGGER:
		_finish_boss_attack(1.5)
		stagger = maxf(stagger, 1.0)
		boss_attack.emit(self, "convergence_break")
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
	_cancel_boss_attack()
	boss_phase = next_phase
	boss_transition_lock = 1.25
	stagger = maxf(stagger, 1.25)
	boss_ability_cooldown = 1.8
	if boss_phase == 2:
		speed = 4.5
		attack_damage = 34
		attack_cooldown = 0.72
		ranged_accuracy = 0.72
	else:
		speed = 6.2
		attack_range = 4.8
		attack_damage = 40
		attack_cooldown = 0.54
		ranged_range = 0.0
	_apply_boss_phase_appearance()
	_sound("howl", 5.0, 0.55 if boss_phase == 2 else 0.48)
	_shockwave_visual(Color("d06a32") if boss_phase == 2 else Color("a91512"), 5.0, 0.55)
	boss_phase_changed.emit(self, boss_phase, boss_phase_title())


## Shared by the real phase transitions and deterministic visual proof capture.
func preview_boss_phase(phase_index: int) -> void:
	if not boss:
		return
	boss_phase = clampi(phase_index, 1, 3)
	_apply_boss_phase_appearance()


func _apply_boss_phase_appearance() -> void:
	if not boss:
		return
	for index in boss_armor.size():
		var plate := boss_armor[index]
		if is_instance_valid(plate):
			plate.visible = boss_phase == 1 or (boss_phase == 2 and index % 2 == 1) or (boss_phase == 3 and plate.get_meta("red_horn_remnant", false))
	if body_material:
		# Fur pigment is now in the texture. Keep phase tint light enough to
		# preserve its strands instead of multiplying two near-black colors.
		body_material.albedo_color = Color("ffffff") if boss_phase == 1 else (Color("ffe1cd") if boss_phase == 2 else Color("ffc1aa"))
	if body_light_material:
		body_light_material.albedo_color = Color(1.5, 1.35, 1.15) if boss_phase == 1 else (Color(1.5, 1.15, 0.95) if boss_phase == 2 else Color(1.5, 0.95, 0.8))
	if eye_material:
		eye_material.emission = Color("6fb6ff") if boss_phase == 1 else Color("ff321f")
		eye_material.emission_energy_multiplier = 0.65 if boss_phase == 1 else 1.5
	if eye_light:
		eye_light.light_color = Color("6fb6ff") if boss_phase == 1 else Color("ff321f")
		eye_light.light_energy = 0.035 if boss_phase == 1 else 0.12
	if is_instance_valid(boss_embers):
		boss_embers.amount_ratio = 0.0 if boss_phase == 1 else (0.26 if boss_phase == 2 else 1.0)
	if is_instance_valid(boss_aura):
		boss_aura.light_color = Color("6f9fcc") if boss_phase == 1 else (Color("b84928") if boss_phase == 2 else Color("ef321f"))
		boss_aura.light_energy = 0.2 if boss_phase == 1 else (0.6 if boss_phase == 2 else 1.05)
		boss_aura.omni_range = 2.4 if boss_phase == 1 else (3.2 if boss_phase == 2 else 4.2)
	if is_instance_valid(boss_red_horn):
		boss_red_horn.visible = boss_phase >= 3


func _break_for_execution() -> void:
	_cancel_boss_attack()
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
	if is_instance_valid(boss_embers):
		boss_embers.amount_ratio = 0.12
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
	if boss and is_instance_valid(boss_shell):
		var shell_fall := boss_shell.create_tween()
		shell_fall.set_parallel(true)
		shell_fall.tween_property(boss_shell, "rotation:z", 1.18, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		shell_fall.tween_property(boss_shell, "position", Vector3(-0.58, -0.48, 0.08), 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
	var target_height := 3.0 if boss else (1.35 if role == "brute" else (0.95 if role == "stalker" else 1.1))
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42 if not boss else 1.45
	capsule.height = target_height + 0.3
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	if boss:
		# The visible muzzle reaches three metres ahead of the body root.
		# Match its collision envelope so the goat cannot walk into the face.
		collider.position.z = -1.6
	add_child(collider)

	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	if boss:
		# Stable close-camera details share a fall rig. The skinned source supplies
		# locomotion, while this shell keeps Varkas' face and armor together during
		# the final death animation instead of leaving them suspended at the root.
		boss_shell = Node3D.new()
		boss_shell.name = "VarkasHeroShell"
		add_child(boss_shell)
	var wolf: Node = (VARKAS_SCENE if boss else WOLF_SCENE).instantiate()
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
			body_material.albedo_color = Color("2b211d")
		"brute":
			body_material.albedo_color = Color("3d464f")
		"stalker":
			body_material.albedo_color = Color("2a221c")
		_:
			body_material.albedo_color = Color("4a3d31")
	body_material.roughness = 0.82
	var fur_noise := NoiseTexture2D.new()
	var fur_source := FastNoiseLite.new()
	fur_source.seed = 784 if boss else 233
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
	body_material.albedo_texture = fur_noise
	if boss:
		# The hero has a full UV unwrap; the warpack retains its palette UVs.
		# This generated swatch already contains dark pigment, so avoid applying
		# the near-black procedural tint a second time.
		body_material.albedo_texture = preload("res://assets/materials/original/varkas_guard_fur.png")
		body_material.albedo_color = Color.WHITE
		body_material.uv1_scale = Vector3(4.0, 4.0, 1.0)
		body_material.roughness = 0.94
	body_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	body_light_material = body_material.duplicate() as StandardMaterial3D
	body_light_material.albedo_color = body_material.albedo_color.lightened(0.3)
	if boss:
		body_light_material.albedo_color = Color(1.5, 1.35, 1.15)
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
					mesh_instance.set_surface_override_material(i, body_light_material)
				"Eyes_Black":
					mesh_instance.set_surface_override_material(i, eye_material)
	_dress()
	if boss:
		_apply_boss_phase_appearance()


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
	# Varkas is a mustelid, not a giant upright wolf. Preserve the animated rig,
	# but squash its vertical read and push mass through the chest and haunches.
	# Root-level hero details below are staged around the resulting 2.6 m crown.
	wolf.scale = Vector3(factor * 1.34, factor * 0.86, factor * 1.08) if boss else Vector3.ONE * factor
	# Godot's forward is -Z; turn the model round if its head points down +Z.
	if head_z > tail_z:
		wolf.rotation.y = PI
	wolf.position.y = -low * factor * (0.86 if boss else 1.0) + 0.02


func _dress() -> void:
	if skeleton == null:
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
	var head := _attach("Head")
	if head:
		eye_light = OmniLight3D.new()
		eye_light.light_color = Color("6fb6ff")
		eye_light.light_energy = 0.06 if boss else 0.35
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
		var hero_parent: Node3D = boss_shell if is_instance_valid(boss_shell) else self
		# Varkas wears the herd's iron: plates, a brutal muzzle cage, and Orin's
		# oversized bell. Half tears away in phase two; Red Horn keeps only a
		# few jagged remnants so the final silhouette still belongs to him.
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
					if bone == "Torso3" and side > 0.0:
						spike.set_meta("red_horn_remnant", true)
					boss_armor.append(spike)
		var neck := _attach("Neck2")
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
			boss_armor.append(collar)
			var great_bell := MeshInstance3D.new()
			var great_mesh := CylinderMesh.new()
			great_mesh.top_radius = 0.19
			great_mesh.bottom_radius = 0.34
			great_mesh.height = 0.48
			great_mesh.material = brass
			great_bell.mesh = great_mesh
			great_bell.position = Vector3(0.0, -0.66, 0.12)
			neck.add_child(great_bell)
		var head_rider := _attach("Head")
		if head_rider:
			# A smooth head ruff, compact muzzle, round ears, and black nose sit on
			# the inherited animated skull. Together with the deformed Blender mesh
			# they replace the source wolf's narrow fox-like closeup silhouette.
			var ruff_mesh := SphereMesh.new()
			ruff_mesh.radius = 0.58
			ruff_mesh.height = 0.94
			ruff_mesh.radial_segments = 24
			ruff_mesh.rings = 12
			ruff_mesh.material = body_material
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
			muzzle_fur_mesh.material = body_light_material
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
				ear_mesh.material = body_material
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
			boss_armor.append(muzzle)
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
				boss_armor.append(cheek_spike)
			var horn_material := iron.duplicate() as StandardMaterial3D
			horn_material.albedo_color = Color("914633")
			horn_material.metallic = 0.15
			horn_material.roughness = 0.9
			horn_material.normal_scale = 0.35
			horn_material.emission_enabled = true
			horn_material.emission = Color("450b06")
			horn_material.emission_energy_multiplier = 0.2
			boss_red_horn = MeshInstance3D.new()
			boss_red_horn.name = "RedHornCrown"
			var horn_mesh := _red_horn_mesh(horn_material)
			boss_red_horn.mesh = horn_mesh
			boss_red_horn.position = Vector3(-0.18, 2.52, -2.94)
			boss_red_horn.rotation_degrees = Vector3(0.0, 0.0, -12.0)
			boss_red_horn.visible = false
			hero_parent.add_child(boss_red_horn)
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
					fur_material.albedo_texture = body_material.albedo_texture
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
			shoulder_tuft_mesh.material = body_material
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
			hero_eye_mesh.material = eye_material
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
		var breastplate := _add_boss_armor_piece("IronHideBreastplate", breast_mesh, Vector3(0.0, 1.58, -1.5), iron)
		breastplate.scale.z = 0.24
		for side in [-1.0, 1.0]:
			var shoulder_mesh := PrismMesh.new()
			shoulder_mesh.size = Vector3(0.28, 0.92, 0.3)
			var shoulder := _add_boss_armor_piece(
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
		var brow := _add_boss_armor_piece("IronHideBrow", brow_mesh, Vector3(-0.13, 2.62, -2.69), iron)
		brow.rotation_degrees.z = 78.0
		brow.scale.z = 0.74
		for side in [-1.0, 1.0]:
			var cage_mesh := CapsuleMesh.new()
			cage_mesh.radius = 0.045
			cage_mesh.height = 0.54
			cage_mesh.radial_segments = 10
			cage_mesh.rings = 3
			var cheek_bar := _add_boss_armor_piece(
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
		_build_boss_embers()
		_build_boss_aura()


func _build_boss_embers() -> void:
	boss_embers = GPUParticles3D.new()
	boss_embers.name = "RedHornEmbers"
	boss_embers.amount = 150
	boss_embers.amount_ratio = 0.0
	boss_embers.lifetime = 1.25
	boss_embers.randomness = 0.72
	boss_embers.visibility_aabb = AABB(Vector3(-2.0, -0.5, -2.5), Vector3(4.0, 4.0, 5.0))
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
	boss_embers.process_material = motion
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
	boss_embers.draw_pass_1 = mote
	add_child(boss_embers)


func _build_boss_aura() -> void:
	boss_aura = OmniLight3D.new()
	boss_aura.name = "VarkasPhaseLight"
	boss_aura.position = Vector3(0.0, 0.45, 0.18)
	boss_aura.light_color = Color("6f9fcc")
	boss_aura.light_energy = 0.25
	boss_aura.omni_range = 2.6
	boss_aura.omni_attenuation = 1.45
	boss_aura.shadow_enabled = true
	add_child(boss_aura)


func _add_boss_armor_piece(
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
	if boss and is_instance_valid(boss_shell):
		boss_shell.add_child(piece)
	else:
		add_child(piece)
	boss_armor.append(piece)
	return piece


func _red_horn_mesh(horn_material: Material) -> ArrayMesh:
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
