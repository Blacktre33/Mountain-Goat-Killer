class_name WolverineEnemy
extends CharacterBody3D
## A wolverine of Varkas' warpack: the Quaternius wolf re-tinted and re-armed,
## driven by a patrol / suspicious / alert / search state machine fed by sight,
## hearing, and scent (see Stealth).

signal killed(enemy: WolverineEnemy)
signal spotted(enemy: WolverineEnemy)
signal boss_phase_changed(enemy: WolverineEnemy, phase_index: int, phase_title: String)
signal boss_attack(enemy: WolverineEnemy, attack_name: String)
signal body_found(enemy: WolverineEnemy, at: Vector3)

enum State { PATROL, SUSPICIOUS, ALERT, SEARCH, DORMANT }

const WOLF_SCENE := preload("res://assets/wolf/wolf.glb")
const VARKAS_SCENE := preload("res://assets/wolf/varkas_wolverine.glb")
const WORLD_AND_PLAYER_MASK := 1
const PATROL_SPEED := 1.7
const HOWL_RANGE := 20.0
## A tracker keeps this far from the goat once it has found it, calling the
## pack in rather than closing to bite.
const TRACKER_KEEP_AWAY := 7.0
const TRACKER_CALL_SECONDS := 6.0
const LOSE_SECONDS := 9.0
const SEARCH_SECONDS := 8.0
const INVESTIGATE_WAIT := 4.0
## A found body is searched for longer than a lost trail.
const BODY_SEARCH_SECONDS := 16.0

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
## Sense tuning per role. A tracker hunts by nose and calls from far off.
var sight_multiplier := 1.0
var scent_multiplier := 1.0
var scent_range := Stealth.SCENT_RANGE
var howl_range := HOWL_RANGE
var call_timer := 0.0
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
## Why this wolverine last went fully alert: "sight", "scent", "noise",
## "pack" (a howl or the mother bell), "shot", or "boss". Read by the playtest log.
var alert_reason := ""
var strongest_sense := "sight"
## The warpack's dead stay where they fall. Varkas and his summoned
## reinforcements sink away as before.
var leaves_body := true
## Seconds of sharpened senses left after finding a body.
var wary_for := 0.0
var search_seconds := SEARCH_SECONDS

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
		"tracker":
			# Lean and weak, with a nose that works twice as far down the wind.
			health = 64
			speed = 3.9
			attack_range = 2.2
			attack_damage = 8
			sight_multiplier = 0.7
			scent_multiplier = 2.4
			scent_range = Stealth.SCENT_RANGE * 1.5
			howl_range = HOWL_RANGE * 1.7
		"boss":
			boss = true
			leaves_body = false
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
		alert_reason = "boss"
		spotted.emit(self)
		if boss:
			boss_phase_changed.emit(self, boss_phase, boss_phase_title())


## Something happened at `source` loud enough to reach `radius` metres.
func hear_noise(source: Vector3, radius: float) -> void:
	if dead or state == State.DORMANT or not Stealth.hears(source, global_position, radius):
		return
	if radius >= Stealth.NOISE.volley:
		_go_alert(source, "noise")
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
	_go_alert(source, "pack")


func _go_alert(source: Vector3, reason := "") -> void:
	var was_alert := state == State.ALERT
	state = State.ALERT
	detection = Stealth.ALERT
	last_known = source
	lost_for = 0.0
	if not was_alert:
		alert_reason = reason
		spotted.emit(self)
		_sound("howl", 2.0 if boss else -2.0, 0.7 if boss else randf_range(0.9, 1.15))
		_call_pack(source)


## Reset to patrol after the goat respawns at a checkpoint.
func calm() -> void:
	if dead or state == State.DORMANT:
		return
	state = State.PATROL
	detection = 0.0
	wary_for = 0.0
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
	WolverineLook.apply_phase(self)
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
					if role == "tracker":
						# Hang back and keep howling the pack onto the goat.
						call_timer -= delta
						if call_timer <= 0.0:
							call_timer = TRACKER_CALL_SECONDS
							_sound("howl", 0.0, randf_range(1.15, 1.3))
							_call_pack(target.global_position)
					if role == "tracker" and distance < TRACKER_KEEP_AWAY and distance > attack_range:
						desired = -to_goat + _separation()
					elif distance > attack_range and not (ranged_range > 0.0 and distance < ranged_range * 0.7):
						var spread := flank if distance > attack_range + 6.0 else 0.0
						desired = to_goat.rotated(Vector3.UP, spread) + _separation()
					else:
						desired = to_goat.rotated(Vector3.UP, PI * 0.5) * sin(phase * 1.8) * 0.5 + _separation()
						if cooldown <= 0.0:
							if distance <= attack_range:
								target.damage(attack_damage, role)
								cooldown = attack_cooldown
								_play("Attack", true)
								_sound("bite", 0.0, 0.8 if boss else 1.0)
							elif ranged_range > 0.0:
								if randf() < ranged_accuracy * Difficulty.accuracy_multiplier():
									target.damage(int(attack_damage * 0.6) + randi_range(0, 4), role + "_rifle")
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
						search_seconds = SEARCH_SECONDS
						wait_for = 0.0
						detection = Stealth.SUSPICIOUS + 0.2
			State.SEARCH:
				wait_for += delta
				move_speed = PATROL_SPEED * 1.2
				var wander := last_known + Vector3(cos(phase * 0.9), 0.0, sin(phase * 0.9)) * 5.0
				desired = _steer_to(wander) * 0.8
				look_at_point = global_position + desired
				if wait_for > search_seconds:
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
					target.damage(18, "varkas_bellquake")
					target.knockback(global_position, 7.0, 2.0)
				_shockwave_visual(Color("f8cd89"), 11.5, 0.25)
				_finish_boss_attack(1.25)
			else:
				if distance <= 6.0 and boss_attack_direction.dot(to_goat) > 0.5 and _has_line_of_sight():
					target.damage(26 if boss_phase == 1 else 32, "varkas_iron_jaw")
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
			target.damage(38, "varkas_red_horn")
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
			boss_windup_for = 0.95 * Difficulty.telegraph_multiplier()
			boss_attack.emit(self, "charge")
			_sound("growl", 3.0, 0.58)
			_show_charge_lane()
			return Vector3.ZERO
	if distance <= 6.2 and cooldown <= 0.0:
		boss_attack_kind = "swipe"
		boss_attack_direction = to_goat
		boss_windup_for = 0.85 * Difficulty.telegraph_multiplier()
		boss_attack.emit(self, "swipe")
		_sound("growl", 0.0, 0.65)
		boss_telegraph = _shockwave_visual(Color("d98b45"), 6.0, boss_windup_for)
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
	boss_windup_for = 1.2 * Difficulty.telegraph_multiplier()
	boss_attack_direction = facing()
	boss_attack.emit(self, "bellquake")
	_sound("bell", 5.0, 0.55)
	boss_telegraph = _shockwave_visual(Color("d98b45"), 11.5, boss_windup_for)


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
		var sight := Stealth.sight_rate(facing(), to_goat, has_los, target.crouched, target.light_exposure) * sight_multiplier
		var wind := Stealth.wind_at(Time.get_ticks_msec() * 0.001)
		var scent := Stealth.scent_strength(target.global_position, global_position, wind, scent_range) * Stealth.SCENT_RATE * scent_multiplier
		sense_rate = (sight + scent) * Difficulty.detection_multiplier()
		if wary_for > 0.0:
			sense_rate *= Stealth.WARY_SENSE_MULTIPLIER
		strongest_sense = "sight" if sight >= scent else "scent"
		_look_for_bodies()
		if has_los and state == State.ALERT:
			sense_rate = maxf(sense_rate, 1.0)
	wary_for = maxf(0.0, wary_for - delta)
	var before := detection
	detection = Stealth.step_detection(detection, sense_rate, delta)
	if detection >= Stealth.ALERT and state != State.ALERT:
		_go_alert(target.global_position, strongest_sense)
	elif detection >= Stealth.SUSPICIOUS and state == State.PATROL and before < Stealth.SUSPICIOUS:
		state = State.SUSPICIOUS
		investigate_point = target.global_position
		wait_for = 0.0
		_sound("huff", -4.0, randf_range(0.85, 1.1))
	elif state == State.SUSPICIOUS and sense_rate > 0.0:
		investigate_point = target.global_position


## Howl: every packmate within earshot converges on `source`.
func _call_pack(source: Vector3) -> void:
	for other in get_tree().get_nodes_in_group("enemies"):
		if other != self and not other.dead and other.global_position.distance_to(global_position) < howl_range:
			other.alert_to(source)


## A patrolling or suspicious wolverine that sees an undiscovered body searches
## around it, stays wary, and draws nearby packmates to investigate.
func _look_for_bodies() -> void:
	if boss or state == State.ALERT or state == State.DORMANT:
		return
	for body in get_tree().get_nodes_in_group("bodies"):
		if body.get_meta("body_found", false):
			continue
		var at: Vector3 = body.global_position + Vector3(0.0, 0.35, 0.0)
		if not Stealth.sees_body(facing(), at - eye_position()) or not _clear_view(at):
			continue
		body.set_meta("body_found", true)
		discover_body(body.global_position)
		return


func discover_body(at: Vector3) -> void:
	wary_for = Stealth.WARY_SECONDS
	detection = maxf(detection, Stealth.SUSPICIOUS + 0.2)
	last_known = at
	investigate_point = at
	wait_for = 0.0
	lost_for = 0.0
	state = State.SEARCH
	search_seconds = BODY_SEARCH_SECONDS
	_sound("growl", -2.0, randf_range(0.75, 0.9))
	body_found.emit(self, at)
	for other in get_tree().get_nodes_in_group("enemies"):
		if other != self and not other.dead and other.global_position.distance_to(global_position) < howl_range:
			other.investigate(at)


## Walk over to look at something without going fully alert.
func investigate(at: Vector3) -> void:
	if dead or boss or state == State.ALERT or state == State.DORMANT:
		return
	wary_for = maxf(wary_for, Stealth.WARY_SECONDS * 0.5)
	detection = maxf(detection, Stealth.SUSPICIOUS)
	investigate_point = at
	wait_for = 0.0
	state = State.SUSPICIOUS


## Line of sight through world geometry only (bodies have no collision).
func _clear_view(to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(eye_position(), to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target


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
	WolverineLook.spawn_blood(self, amount, health <= 0 and not boss)
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
		_go_alert(target.global_position if target else global_position, "shot")


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
	WolverineLook.apply_phase(self)
	_sound("howl", 5.0, 0.55 if boss_phase == 2 else 0.48)
	_shockwave_visual(Color("d06a32") if boss_phase == 2 else Color("a91512"), 5.0, 0.55)
	boss_phase_changed.emit(self, boss_phase, boss_phase_title())


## Shared by the real phase transitions and deterministic visual proof capture.
func preview_boss_phase(phase_index: int) -> void:
	if not boss:
		return
	boss_phase = clampi(phase_index, 1, 3)
	WolverineLook.apply_phase(self)


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
	WolverineLook.spawn_blood(self, 240, true)
	_die()


## A horn strike from behind: instant, silent.
func takedown() -> void:
	if dead:
		return
	health = 0
	WolverineLook.spawn_blood(self, 180, true)
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
	if leaves_body:
		add_to_group("bodies")
		set_meta("body_found", false)
		return
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(self, "position:y", position.y - 1.4, 1.2)
	tween.tween_callback(queue_free)


# --- Model --------------------------------------------------------------------

func _build_body() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	var target_height: float = 3.0 if boss else ({"brute": 1.35, "stalker": 0.95, "tracker": 0.88} as Dictionary).get(role, 1.1)
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

	WolverineLook.build(self, target_height)


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
