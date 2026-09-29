class_name WolverineEnemy
extends CharacterBody3D
## A wolverine of Varkas' warpack: the Quaternius wolf rig re-shaped, furred and
## armed as an iron-collared wolverine, driven by a patrol / suspicious / alert /
## search state machine fed by sight, hearing, scent and the sight of dead
## packmates (see Stealth). In a fight the pack is coordinated by PackDirector:
## melee fighters approach, circle, telegraph, strike and recover; riflemen use
## cover, aim with a visible laser and fire real rounds; Varkas owns his own
## three-phase attack timeline.

signal killed(enemy: WolverineEnemy)
signal spotted(enemy: WolverineEnemy)
signal boss_phase_changed(enemy: WolverineEnemy, phase_index: int, phase_title: String)
signal boss_attack(enemy: WolverineEnemy, attack_name: String)
## A telegraphed strike (or shot) that the goat evaded.
signal attack_dodged(enemy: WolverineEnemy)

enum State { PATROL, SUSPICIOUS, ALERT, SEARCH, DORMANT }
## What a hunting wolverine is doing inside the ALERT state.
enum Combat { NONE, APPROACH, CIRCLE, WINDUP, STRIKE, RECOVER, CHARGE, STAGGERED, RETREAT, COVER, PEEK, AIM, RELOAD }

const VARKAS_SCENE := preload("res://assets/wolf/varkas_wolverine.glb")
const GEAR_SCENE := preload("res://assets/wolf/varkas_gear.glb")
const HEAD_SCENE := preload("res://assets/wolf/wolverine_head.glb")
const FUR_SHADER := preload("res://assets/wolf/wolverine_fur.gdshader")
const HEAD_SHADER := preload("res://assets/wolf/wolverine_head.gdshader")
const FUR_A := preload("res://assets/wolf/textures/fur_a.png")
const FUR_B := preload("res://assets/wolf/textures/fur_b.png")
const WARPAINT := preload("res://assets/wolf/textures/warpaint.png")
const IRON_PLATE := preload("res://assets/wolf/textures/iron_plate.png")
const WORLD_AND_PLAYER_MASK := 1
const PATROL_SPEED := 1.35
const HOWL_RANGE := 20.0
const LOSE_SECONDS := 9.0
const SEARCH_SECONDS := 9.0
const INVESTIGATE_WAIT := 4.5
## Foot-planting speeds of the Walk and Gallop clips in rig units per second,
## measured from the IK foot bones. Multiplied by the model scale they give the
## ground speed at which a clip plays without sliding.
const WALK_RIG_SPEED := 2.3
const GALLOP_RIG_SPEED := 6.9
## In the Attack clip the crouch settles at 0.25 s and the head lunges to full
## extension at 0.38 s: the impact frame.
const ATTACK_CROUCH_TIME := 0.25
const ATTACK_IMPACT_DELAY := 0.13
const IDLE_VARIANTS := ["Idle", "Idle_2", "Idle_2_HeadLow"]
const CORPSE_LIFETIME := 34.0

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
var boss_bell: MeshInstance3D
var boss_shell: Node3D
var boss_bell_material: StandardMaterial3D
var boss_pitch := 0.0
var _pitch_tween: Tween
var boss_windup_total := 0.0
var boss_hit_landed := false
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
var found_body := false

## Combat.
var combat := Combat.NONE
var combat_time := 0.0
var pack_role := "rusher"
var flank_side := 0.0
var flank_done := false
var circle_direction := 1.0
var strike_direction := Vector3.FORWARD
var strike_landed := false
var windup_total := 0.5
var strike_from := 3.4
var recover_total := 0.9
var lunge_speed := 9.5
var lunge_time := 0.3
var charge_speed := 9.0
var feinting := false
var retreat_used := false
var sight_time := 0.0
var rounds := 4
var burst_left := 0
var cover_point := Vector3.INF
var peek_point := Vector3.INF
var cover_scan_in := 0.0
var hide_for := 0.0
var aim_direction := Vector3.FORWARD
var aim_locked := false
var laser: MeshInstance3D
var size_scale := 1.0
var hit_direction := Vector3.ZERO
var strike_kind := "bite"
var started_in_range := false
var aim_total := 0.75
var aim_blocked_for := 0.0
var reloading := false
var reload_sound_played := false

## Movement.
var _move := Vector3.ZERO
var _move_speed := PATROL_SPEED
var _look := Vector3.ZERO
var _head_target := Vector3.ZERO
var _head_weight := 0.0
var _turn_lock := false
var _nav_path := PackedVector3Array()
var _nav_index := 0
var _nav_goal := Vector3.INF
var _nav_refresh := 0.0
var _stuck_for := 0.0
var _stuck_side := 1.0
var _sidestep_for := 0.0
var _last_position := Vector3.ZERO
var _separation_cache := Vector3.ZERO
var _separation_frame := -1
var _idle_change_in := 0.0
var _idle_variant := "Idle"
var _look_sweep := 0.0
var _search_point := Vector3.INF
var _search_repick := 0.0
var _yaw_rate := 0.0
var _last_yaw := 0.0
var _planar_speed := 0.0
var _prev_planar := 0.0
var _corpse_age := 0.0
var _corpse_slide := Vector3.ZERO

## Model.
var model: Node3D
var anim: AnimationPlayer
var anim_tree: AnimationTree
var skeleton: Skeleton3D
var pose: EnemyPose
var body_material: StandardMaterial3D
var body_light_material: StandardMaterial3D
var fur_materials: Array[ShaderMaterial] = []
var eye_material: StandardMaterial3D
var eye_light: OmniLight3D
var head_material: ShaderMaterial
var eye_beam: SpotLight3D
var iron: StandardMaterial3D
var brass: StandardMaterial3D
var rifle_pivot: Node3D
var rifle_muzzle: Marker3D
var rifle_aim := Vector3.FORWARD
var collar_bell: Node3D
var current_anim := ""
var los_query: PhysicsRayQueryParameters3D
var rig_scale := 0.47
var rig_forward_scale := 0.47
var _fall_side := 1.0
var _model_yaw_flip := false
var _flash_tween: Tween
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
			speed = 5.6
			attack_range = 2.4
			attack_damage = 15
			strike_from = 3.5
			windup_total = 0.5
			recover_total = 0.95
			lunge_speed = 9.6
			lunge_time = 0.3
		"rifleman":
			health = 110
			speed = 3.6
			attack_range = 2.6
			attack_damage = 12
			ranged_range = 24.0
			ranged_accuracy = 0.45
			attack_cooldown = 1.5
			windup_total = 0.6
			recover_total = 1.0
		"brute":
			health = 230
			speed = 3.4
			attack_range = 3.3
			attack_damage = 26
			strike_from = 3.6
			windup_total = 0.8
			recover_total = 1.25
			lunge_speed = 3.5
			lunge_time = 0.2
			charge_speed = 9.2
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
	circle_direction = 1.0 if randf() < 0.5 else -1.0
	size_scale = 1.0 if boss else randf_range(0.92, 1.1)
	_idle_change_in = randf_range(2.0, 5.0)
	add_to_group("enemies")
	_build_body()
	_play("Idle")


func _sound(name: String, volume_db := 0.0, pitch := 1.0, fallback := "") -> void:
	EnemyFx.sound(get_tree(), name, global_position + Vector3(0.0, 0.8, 0.0), volume_db, pitch, fallback)


func awareness() -> String:
	return Stealth.awareness_of(detection)


func chest_position() -> Vector3:
	return global_position + Vector3(0.0, 1.55 if boss else 0.55 * size_scale, 0.0)


func eye_position() -> Vector3:
	return global_position + Vector3(0.0, 2.18 if boss else 0.8 * size_scale, 0.0) + facing() * (1.42 if boss else 0.5)


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


## A lantern went out at `at`: anything that could see it wonders who did it.
func notice_dark(at: Vector3) -> void:
	if dead or state == State.DORMANT or state == State.ALERT:
		return
	if global_position.distance_to(at) > Stealth.LANTERN_NOTICE_RANGE:
		return
	# Only a wolverine with a line to the lantern sees it die.
	if not _point_visible(eye_position(), at):
		return
	investigate_point = at
	detection = maxf(detection, Stealth.SUSPICIOUS + 0.05)
	wait_for = 0.0
	if state != State.SUSPICIOUS:
		_sound("huff", -3.0, randf_range(0.8, 1.0))
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
		combat = Combat.APPROACH
		combat_time = 0.0
		spotted.emit(self)
		_sound("howl", 2.0 if boss else -2.0, 0.7 if boss else randf_range(0.9, 1.15))
		for other in get_tree().get_nodes_in_group("enemies"):
			if other != self and not other.dead and other.global_position.distance_to(global_position) < HOWL_RANGE:
				other.alert_to(source)
		PackDirector.assign_roles(get_tree().get_nodes_in_group("enemies"), target.global_position if is_instance_valid(target) else source)


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
	_end_combat()
	found_body = false
	sight_time = 0.0
	rounds = 4
	cover_point = Vector3.INF
	peek_point = Vector3.INF
	retreat_used = false


func _end_combat() -> void:
	combat = Combat.NONE
	combat_time = 0.0
	feinting = false
	strike_landed = false
	burst_left = 0
	aim_locked = false
	PackDirector.release_all(self)
	_set_laser(0.0)
	if pose:
		pose.crouch = 0.0
	if anim_tree:
		anim_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


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
	_kill_pitch_tween()
	_apply_boss_pitch(0.0)
	_apply_boss_phase_appearance()
	_play("Idle")


# --- Frame loop ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		_corpse_physics(delta)
		return
	EnemyNav.ensure(self)
	if not is_instance_valid(target) or not target.active or state == State.DORMANT:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		_planar_speed = Vector2(velocity.x, velocity.z).length()
		_head_weight = 0.0
		_animate(delta)
		return

	cooldown = maxf(0.0, cooldown - delta)
	boss_ability_cooldown = maxf(0.0, boss_ability_cooldown - delta)
	boss_transition_lock = maxf(0.0, boss_transition_lock - delta)
	phase += delta
	_perceive(delta)

	var offset := target.global_position - global_position
	var distance := Vector2(offset.x, offset.z).length()
	var to_goat := Vector3(offset.x, 0.0, offset.z).normalized()
	_move = Vector3.ZERO
	_move_speed = PATROL_SPEED
	_look = global_position + facing()
	_head_weight = 0.0
	_turn_lock = false
	var turn_rate := 3.5

	if stagger > 0.0 and combat != Combat.STAGGERED:
		stagger -= delta
	# A stagger slows a hunter instead of freezing it: the AI keeps running at a
	# fraction of its speed so a hit reads as a flinch, not a stun.
	var slowed := stagger > 0.0 and combat != Combat.STAGGERED
	match state:
		State.PATROL:
			_patrol_brain(delta)
		State.SUSPICIOUS:
			_suspicious_brain(delta)
			turn_rate = 5.0
		State.ALERT:
			turn_rate = 8.0
			if boss:
				# Varkas owns one attack timeline. The warpack's immediate bite
				# and random ranged damage must never run beneath a boss tell.
				_look = target.global_position
			else:
				_alert_brain(delta, distance, to_goat)
		State.SEARCH:
			_search_brain(delta)
			turn_rate = 5.0

	if boss and state == State.ALERT:
		var boss_override := _boss_motion(distance, to_goat, delta)
		_move = boss_override
		_move_speed = speed
		if boss_windup_for > 0.0 or boss_charge_for > 0.0:
			_look = global_position + boss_attack_direction
		if _move.is_zero_approx():
			velocity.x = 0.0
			velocity.z = 0.0

	var accel := 9.0 if state == State.ALERT else 6.0
	if combat == Combat.STRIKE or combat == Combat.CHARGE:
		accel = 40.0
	if slowed:
		_move = Vector3.ZERO if boss else _move * 0.4
		accel = 14.0
	velocity.x = move_toward(velocity.x, _move.x * _move_speed, accel * delta)
	velocity.z = move_toward(velocity.z, _move.z * _move_speed, accel * delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()
	_track_stuck(delta)

	if not _turn_lock:
		var flat_look := Vector3(_look.x, global_position.y, _look.z)
		if flat_look.distance_squared_to(global_position) > 0.01:
			var current := global_transform.basis.get_rotation_quaternion()
			var wanted := Transform3D().looking_at(flat_look - global_position, Vector3.UP).basis.get_rotation_quaternion()
			global_transform.basis = Basis(current.slerp(wanted, minf(1.0, delta * turn_rate)))

	_planar_speed = Vector2(velocity.x, velocity.z).length()
	var yaw := rotation.y
	_yaw_rate = wrapf(yaw - _last_yaw, -PI, PI) / maxf(delta, 0.0001)
	_last_yaw = yaw
	_animate(delta)


func _corpse_physics(delta: float) -> void:
	_corpse_age += delta
	_corpse_slide = _corpse_slide.move_toward(Vector3.ZERO, 7.0 * delta)
	velocity.x = _corpse_slide.x
	velocity.z = _corpse_slide.z
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	if _corpse_age > CORPSE_LIFETIME and not has_meta("sinking"):
		set_meta("sinking", true)
		var sink := create_tween()
		sink.tween_property(self, "position:y", position.y - 1.2, 3.5)
		sink.tween_callback(queue_free)


func _track_stuck(delta: float) -> void:
	var moved := global_position.distance_to(_last_position)
	_last_position = global_position
	var wants_move := _move.length() > 0.3 and _move_speed > 0.8 and combat != Combat.WINDUP and combat != Combat.STAGGERED
	if wants_move and moved < _move_speed * delta * 0.18:
		_stuck_for += delta
		if _stuck_for > 0.7:
			# Wedged against something the path did not know about: slide out along
			# whichever side has been free, then resume.
			_sidestep_for = 0.8
			_stuck_side = -_stuck_side
			_stuck_for = 0.0
			_nav_goal = Vector3.INF
	else:
		_stuck_for = maxf(0.0, _stuck_for - delta * 2.0)
	_sidestep_for = maxf(0.0, _sidestep_for - delta)


# --- Steering ---------------------------------------------------------------

## Direction to walk toward `goal`: along the navigation mesh when it is baked
## and the goal is reachable, whisker steering otherwise. Always avoids packmates.
func _steer_to(goal: Vector3, direct := false) -> Vector3:
	var flat := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if flat.length() < 0.01:
		return Vector3.ZERO
	var direction := flat.normalized()
	if not direct and not boss and flat.length() > 1.6 and EnemyNav.is_ready():
		direction = _nav_direction(goal, direction)
	direction = _avoid_obstacles(direction)
	if _sidestep_for > 0.0:
		direction = direction.rotated(Vector3.UP, _stuck_side * PI * 0.45)
	return (direction + _separation()).normalized()


func _nav_direction(goal: Vector3, fallback: Vector3) -> Vector3:
	_nav_refresh -= get_physics_process_delta_time()
	if _nav_path.is_empty() or _nav_goal.distance_to(goal) > 1.5 or _nav_refresh <= 0.0:
		_nav_path = EnemyNav.path(global_position, goal)
		_nav_index = 1
		_nav_goal = goal
		_nav_refresh = 1.2
	if _nav_path.is_empty():
		return fallback
	while _nav_index < _nav_path.size() - 1 and Vector2(_nav_path[_nav_index].x - global_position.x, _nav_path[_nav_index].z - global_position.z).length() < 0.8:
		_nav_index += 1
	var waypoint := _nav_path[mini(_nav_index, _nav_path.size() - 1)]
	var toward := Vector3(waypoint.x - global_position.x, 0.0, waypoint.z - global_position.z)
	return toward.normalized() if toward.length() > 0.05 else fallback


## Whisker steering: three low rays turn the heading away from rocks and walls
## the navigation mesh did not cover (props added later, dynamic gate blocks).
func _avoid_obstacles(direction: Vector3) -> Vector3:
	if los_query == null:
		_make_query()
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 0.4, 0.0)
	var reach := 1.5 + _planar_speed * 0.18
	var steer := direction
	var blocked := false
	for angle in [0.0, 0.6, -0.6]:
		var whisker := direction.rotated(Vector3.UP, angle)
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + whisker * reach, WORLD_AND_PLAYER_MASK, [get_rid()])
		var hit := space.intersect_ray(ray)
		if hit and hit.collider != target and absf(hit.normal.y) < 0.6:
			blocked = true
			var slide := whisker.slide(hit.normal)
			slide.y = 0.0
			if slide.length() > 0.05:
				steer += slide.normalized() * (1.3 if angle == 0.0 else 0.8)
			else:
				steer += direction.rotated(Vector3.UP, PI * 0.5 * signf(-angle if angle != 0.0 else _stuck_side))
	if blocked:
		steer.y = 0.0
		return steer.normalized()
	return direction


func _separation() -> Vector3:
	var frame := Engine.get_physics_frames()
	if _separation_frame == frame:
		return _separation_cache
	_separation_frame = frame
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or other.dead:
			continue
		var gap_vector: Vector3 = global_position - other.global_position
		gap_vector.y = 0.0
		var min_gap := 3.4 if boss or other.boss else 2.5
		var gap := gap_vector.length()
		if gap > 0.01 and gap < min_gap:
			push += gap_vector / gap * (1.0 - gap / min_gap) * 1.8
	_separation_cache = push
	return push


func _make_query() -> void:
	los_query = PhysicsRayQueryParameters3D.new()
	los_query.exclude = [get_rid()]
	los_query.collision_mask = WORLD_AND_PLAYER_MASK


func _has_line_of_sight() -> bool:
	if los_query == null:
		_make_query()
	los_query.from = eye_position()
	los_query.to = target.chest_position()
	var hit := get_world_3d().direct_space_state.intersect_ray(los_query)
	return hit and hit.collider == target


func _point_visible(from: Vector3, to: Vector3) -> bool:
	if los_query == null:
		_make_query()
	los_query.from = from
	los_query.to = to
	return get_world_3d().direct_space_state.intersect_ray(los_query).is_empty()


func _flat_distance_to(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


# --- Stealth brains -----------------------------------------------------------

func _patrol_brain(delta: float) -> void:
	var goal: Vector3 = patrol[patrol_index]
	var arrived := _flat_distance_to(goal) < 1.2
	_move_speed = PATROL_SPEED
	if arrived or patrol.size() == 1:
		# Pause at the post: an idle variant, a slow sweep of the head, then turn
		# toward the next leg before setting off.
		if wait_for <= 0.0:
			wait_for = randf_range(3.0, 6.0)
			_look_sweep = randf() * TAU
			_pick_idle_variant(true)
		wait_for -= delta
		_look_sweep += delta * 0.9
		_head_weight = 0.85
		_head_target = _sweep_target(0.8, 1.1)
		if patrol.size() > 1 and wait_for < 1.1:
			# Turn toward the next leg before setting off.
			_look = patrol[(patrol_index + 1) % patrol.size()]
		else:
			_look = global_position + facing().rotated(Vector3.UP, sin(phase * 0.7) * 0.08)
	else:
		_move = _steer_to(goal)
		_look = global_position + _move
		_head_weight = 0.35
		_head_target = _sweep_target(0.35, 0.4)
		_look_sweep += delta * 0.6
		_pick_idle_variant(false)


func _sweep_target(yaw_amount: float, distance: float) -> Vector3:
	var angle := sin(_look_sweep) * yaw_amount
	return global_position + Vector3(0.0, 0.7 * size_scale, 0.0) + facing().rotated(Vector3.UP, angle) * (3.0 + distance)


func _pick_idle_variant(force: bool) -> void:
	_idle_change_in -= get_physics_process_delta_time()
	if not force and _idle_change_in > 0.0:
		return
	_idle_change_in = randf_range(2.5, 5.5)
	_idle_variant = IDLE_VARIANTS[randi() % IDLE_VARIANTS.size()]


func _suspicious_brain(delta: float) -> void:
	_head_weight = 0.9
	_head_target = investigate_point + Vector3(0.0, 0.4, 0.0)
	pose_crouch_target(0.35)
	if _flat_distance_to(investigate_point) > 1.8:
		_move = _steer_to(investigate_point)
		_move_speed = PATROL_SPEED * 1.35
		_look = global_position + _move
	else:
		# At the noise: sniff the ground, then sweep the head across the area.
		wait_for += delta
		_idle_variant = "Idle_2_HeadLow" if wait_for < INVESTIGATE_WAIT * 0.5 else "Idle_2"
		_look_sweep += delta * 1.3
		_head_target = _sweep_target(1.0, 1.0)
		_look = global_position + facing().rotated(Vector3.UP, sin(phase * 0.9) * 0.6)
		if wait_for > INVESTIGATE_WAIT and detection < Stealth.SUSPICIOUS:
			state = State.PATROL
			wait_for = 0.0
			_return_to_nearest_post()


func _search_brain(delta: float) -> void:
	# A hunter that lost the goat sweeps the last known area with its eye beam,
	# checking fresh points around it instead of walking a fixed circle.
	wait_for += delta
	_move_speed = PATROL_SPEED * 1.5
	_search_repick -= delta
	if _search_point == Vector3.INF or _search_repick <= 0.0 or _flat_distance_to(_search_point) < 1.2:
		var angle := randf() * TAU
		var candidate := last_known + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.5, 7.0)
		candidate.y = WorldBuilder.height_at(candidate.x, candidate.z)
		_search_point = EnemyNav.snap(candidate) if EnemyNav.is_ready() else candidate
		_search_repick = randf_range(2.2, 3.6)
	_look_sweep += delta * 2.0
	_head_weight = 1.0
	_head_target = _sweep_target(1.05, 2.0)
	_move = _steer_to(_search_point) * 0.85
	_look = global_position + _move
	if wait_for > SEARCH_SECONDS:
		state = State.PATROL
		wait_for = 0.0
		_search_point = Vector3.INF
		_return_to_nearest_post()


func _return_to_nearest_post() -> void:
	var best := 1e9
	for index in patrol.size():
		var distance := _flat_distance_to(patrol[index])
		if distance < best:
			best = distance
			patrol_index = index
	wait_for = 0.0
	_nav_goal = Vector3.INF


func pose_crouch_target(amount: float) -> void:
	if pose:
		pose.crouch = lerpf(pose.crouch, amount, 0.12)


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
		if not found_body and state != State.ALERT:
			_look_for_bodies()
	if has_los and state == State.ALERT:
		sight_time += delta
	elif not has_los:
		sight_time = maxf(0.0, sight_time - delta * 1.5)
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


## Patrols that come across a dead packmate raise the alarm: it means the goat
## is close, so the finder searches hard around the body and warns its neighbours.
func _look_for_bodies() -> void:
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse) or corpse.get_meta("discovered", false):
			continue
		var at: Vector3 = corpse.global_position + Vector3(0.0, 0.3, 0.0)
		var seen := _point_visible(eye_position(), at)
		if Stealth.body_seen(facing(), at - eye_position(), seen, target.light_exposure):
			corpse.set_meta("discovered", true)
			found_body = true
			_sound("huff", 0.0, 0.7)
			_discover_body(at)
			return


func _discover_body(at: Vector3) -> void:
	detection = maxf(detection, Stealth.ALERT * 0.9)
	state = State.SEARCH
	wait_for = 0.0
	last_known = at
	_search_point = Vector3.INF
	_sound("howl", -6.0, 1.15)
	for other in get_tree().get_nodes_in_group("enemies"):
		if other != self and not other.dead and other.state != State.ALERT and other.global_position.distance_to(global_position) < HOWL_RANGE * 0.8:
			other.hear_noise(at, Stealth.NOISE.body_found)
	spotted.emit(self)


# --- Combat brains --------------------------------------------------------------

func _alert_brain(delta: float, distance: float, to_goat: Vector3) -> void:
	_head_weight = 0.9
	_head_target = target.global_position + Vector3(0.0, 1.3, 0.0)
	_look = target.global_position
	if has_los:
		last_known = target.global_position
		lost_for = 0.0
		if fmod(phase, 3.4) < delta:
			_sound("growl", -6.0, randf_range(0.9, 1.2))
	if combat == Combat.NONE:
		combat = Combat.APPROACH
	combat_time += delta
	if not retreat_used and health <= max_health * 0.28 and combat != Combat.RETREAT and combat != Combat.STAGGERED and combat != Combat.STRIKE and combat != Combat.CHARGE:
		_begin_retreat()
	if role == "rifleman":
		_ranged_brain(delta, distance, to_goat)
	else:
		_melee_brain(delta, distance, to_goat)


## True while the goat is out of sight: chase the last known position, then give
## up into a search.
func _chase_lost_target(delta: float) -> bool:
	if has_los:
		return false
	lost_for += delta
	_head_target = last_known + Vector3(0.0, 0.5, 0.0)
	if _flat_distance_to(last_known) > 1.5:
		_move = _steer_to(last_known)
		_move_speed = speed
		_look = global_position + _move
	else:
		_look_sweep += delta * 1.8
		_head_target = _sweep_target(0.95, 1.5)
		_look = global_position + facing().rotated(Vector3.UP, sin(phase * 1.6) * 0.7)
	if lost_for > LOSE_SECONDS:
		_end_combat()
		state = State.SEARCH
		wait_for = 0.0
		detection = Stealth.SUSPICIOUS + 0.2
		_search_point = Vector3.INF
	return true


func _melee_brain(delta: float, distance: float, to_goat: Vector3) -> void:
	match combat:
		Combat.NONE, Combat.APPROACH, Combat.CIRCLE:
			if _chase_lost_target(delta):
				return
			_melee_hunt(delta, distance, to_goat)
		Combat.WINDUP:
			_windup_step(delta, distance, to_goat)
		Combat.STRIKE:
			_strike_step(delta, distance)
		Combat.CHARGE:
			_charge_step(delta, distance, to_goat)
		Combat.RECOVER:
			_turn_lock = combat_time < 0.35
			_move = to_goat.rotated(Vector3.UP, PI * 0.5 * circle_direction) * 0.25
			if combat_time >= recover_total:
				combat = Combat.CIRCLE
				combat_time = 0.0
		Combat.STAGGERED:
			_turn_lock = true
			if combat_time >= 2.0:
				combat = Combat.CIRCLE
				combat_time = 0.0
				if pose:
					pose.crouch = 0.0
		Combat.RETREAT:
			_retreat_step(delta, distance, to_goat)
		_:
			combat = Combat.CIRCLE


func _melee_hunt(delta: float, distance: float, to_goat: Vector3) -> void:
	var player_forward := -target.global_transform.basis.z
	var ring := strike_from * 0.85
	var flanking := pack_role == "flanker" and not boss and not flank_done
	if flanking:
		# Swing wide to the goat's flank before closing, so the pack arrives from
		# more than one side.
		var goal := target.global_position + (-to_goat).rotated(Vector3.UP, flank_side * 1.35) * strike_from * 1.7
		goal.y = WorldBuilder.height_at(goal.x, goal.z)
		if _flat_distance_to(goal) < 1.8 or distance < strike_from + 1.5:
			flank_done = true
		else:
			combat = Combat.APPROACH
			_move = _steer_to(goal)
			_move_speed = speed if distance > 9.0 else speed * 0.7
			return
	if distance > strike_from + 0.9:
		combat = Combat.APPROACH
		_move = _steer_to(target.global_position)
		_move_speed = speed
	else:
		combat = Combat.CIRCLE
		if fmod(phase, 3.0) < delta and randf() < 0.4:
			circle_direction = -circle_direction
		var tangent := to_goat.rotated(Vector3.UP, PI * 0.5 * circle_direction)
		var radial := clampf((distance - ring) * 0.9, -1.0, 1.0)
		_move = (to_goat * radial + tangent * 0.8 + _separation()).normalized()
		_move_speed = speed * 0.5
	# Ready to strike? The pack shares two attack tokens, so a wolverine that is
	# not the rusher waits for the goat to turn its back or for the rusher to be spent.
	if cooldown > 0.0 or stagger > 0.0:
		return
	var behind := player_forward.dot(-to_goat) < 0.3
	var may_attack := pack_role != "flanker" or behind or PackDirector.holders("melee") == 0
	if role == "brute" and distance > 6.5 and distance < 14.0 and may_attack and _clear_lane(to_goat, distance):
		if PackDirector.request("melee", self):
			_begin_windup(to_goat, "charge")
		return
	if distance <= strike_from and may_attack and PackDirector.request("melee", self):
		_begin_windup(to_goat, "bite")


## True when nothing but the goat stands on the straight line to her: a charge
## needs open ground, and the ray follows the slope up to her chest.
func _clear_lane(_direction: Vector3, _length: float) -> bool:
	var origin := global_position + Vector3(0.0, 0.6, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(origin, target.chest_position(), WORLD_AND_PLAYER_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == target


func _begin_windup(to_goat: Vector3, kind: String) -> void:
	combat = Combat.WINDUP
	combat_time = 0.0
	strike_direction = to_goat
	strike_landed = false
	strike_kind = kind
	started_in_range = _flat_distance_to(target.global_position) <= strike_from + 0.4
	windup_total = (1.0 if kind == "charge" else (0.55 if kind == "bayonet" else windup_total)) * randf_range(0.92, 1.12)
	feinting = role == "stalker" and kind == "bite" and randf() < 0.25
	_play_attack(windup_total)
	_flash_eyes(Color(1.0, 0.95, 0.85), 0.5)
	_sound("growl", 2.0 if role != "stalker" else 0.0, randf_range(0.8, 1.0) if role == "brute" else randf_range(1.0, 1.25))
	if kind == "charge":
		_sound("roar", 2.0, 0.85, "growl")
		EnemyFx.dust_burst(get_parent(), global_position + facing() * 0.6, 10, 0.8)


func _windup_step(delta: float, distance: float, to_goat: Vector3) -> void:
	var kind := strike_kind
	if pose:
		pose.crouch = lerpf(pose.crouch, 1.0, minf(1.0, delta * 8.0))
	var lock_time := windup_total - (0.25 if kind == "charge" else 0.18)
	if combat_time < lock_time:
		# Track the goat until the last beat; after that the aim is committed and
		# a sidestep beats the strike.
		strike_direction = strike_direction.slerp(to_goat, minf(1.0, delta * 9.0)).normalized()
		_look = target.global_position
	else:
		_turn_lock = true
		_look = global_position + strike_direction
	if kind == "charge" and fmod(combat_time, 0.28) < delta:
		EnemyFx.dust_burst(get_parent(), global_position + facing() * 0.5, 5, 0.5)
	if feinting and combat_time >= windup_total * 0.85:
		# A feint: rock forward, then slip sideways to bait a dodge.
		feinting = false
		combat = Combat.CIRCLE
		combat_time = 0.0
		cooldown = randf_range(0.5, 0.9)
		circle_direction = -circle_direction
		velocity += to_goat.rotated(Vector3.UP, PI * 0.5 * circle_direction) * 5.0
		PackDirector.release("melee", self)
		if anim_tree:
			anim_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		if pose:
			pose.crouch = 0.0
		return
	if combat_time >= windup_total:
		combat = Combat.STRIKE if kind != "charge" else Combat.CHARGE
		combat_time = 0.0
		_release_attack()
		if kind == "charge":
			boss_attack_direction = strike_direction
			_sound("roar", 4.0, 0.8, "growl")
		else:
			_sound("bite", 0.0, 0.9 if role == "brute" else 1.1, "growl")


func _strike_step(delta: float, distance: float) -> void:
	_turn_lock = true
	var kind := strike_kind
	if pose:
		pose.crouch = lerpf(pose.crouch, 0.0, minf(1.0, delta * 10.0))
	_look = global_position + strike_direction
	if combat_time < lunge_time and kind == "bite":
		_move = strike_direction
		_move_speed = lunge_speed
		if combat_time < delta * 1.5:
			EnemyFx.dust_burst(get_parent(), global_position, 6, 0.5)
	if combat_time >= ATTACK_IMPACT_DELAY and not strike_landed:
		strike_landed = true
		_melee_impact(attack_damage, attack_range + 0.7, 3.5 if role == "brute" else 2.5)
	if combat_time >= lunge_time + 0.22:
		_finish_melee(recover_total)


func _melee_impact(damage: int, reach: float, push: float) -> void:
	var offset := target.global_position - global_position
	offset.y = 0.0
	var flat := offset.length()
	var aligned := strike_direction.dot(offset.normalized()) > 0.35 if flat > 0.2 else true
	if flat <= reach and aligned and _point_visible(eye_position() - Vector3(0.0, 0.2, 0.0), target.chest_position()):
		target.damage(damage, global_position)
		target.knockback(global_position, push, 1.2)
		_sound("bite", 2.0, 0.9)
		boss_hit_landed = true
	elif started_in_range:
		attack_dodged.emit(self)
		_sound("whoosh", -2.0, randf_range(0.85, 1.1), "growl")


func _finish_melee(recovery: float) -> void:
	combat = Combat.RECOVER
	combat_time = 0.0
	recover_total = recovery
	flank_done = false
	cooldown = recovery * 0.8 + randf_range(0.2, 0.9)
	PackDirector.release("melee", self)
	if pose:
		pose.crouch = 0.0


func _charge_step(delta: float, distance: float, to_goat: Vector3) -> void:
	_turn_lock = true
	_look = global_position + strike_direction
	_move = strike_direction
	_move_speed = charge_speed
	if fmod(combat_time, 0.16) < delta:
		EnemyFx.dust_burst(get_parent(), global_position, 4, 0.5)
	var offset := target.global_position - global_position
	offset.y = 0.0
	var forward := offset.dot(strike_direction)
	var lateral := (offset - strike_direction * forward).length()
	if forward > -0.4 and forward < 1.8 and lateral < 1.15 and not strike_landed:
		strike_landed = true
		target.damage(int(attack_damage * 1.15), global_position)
		target.knockback(global_position, 9.0, 3.0)
		_sound("bite", 5.0, 0.7)
		_finish_melee(1.4)
		return
	if is_on_wall() and combat_time > 0.3:
		# Shoulder into stone: the brute's ruin. Long stagger, shaken camera.
		combat = Combat.STAGGERED
		combat_time = 0.0
		recover_total = 2.0
		PackDirector.release("melee", self)
		velocity = -strike_direction * 2.5
		EnemyFx.dust_burst(get_parent(), global_position + strike_direction * 0.9, 24, 1.6)
		_sound("wall_slam", 3.0, 0.8, "thud")
		_sound("yelp", -2.0, 0.7)
		_react(randf() < 0.5)
		if global_position.distance_to(target.global_position) < 16.0:
			target.add_camera_trauma(0.3)
		if not strike_landed:
			attack_dodged.emit(self)
		return
	if combat_time > 1.9:
		if not strike_landed:
			attack_dodged.emit(self)
		EnemyFx.dust_burst(get_parent(), global_position, 12, 1.0)
		_finish_melee(1.3)


func _begin_retreat() -> void:
	retreat_used = true
	combat = Combat.RETREAT
	combat_time = 0.0
	PackDirector.release_all(self)
	_set_laser(0.0)
	_sound("yelp", 0.0, 0.85)
	if pose:
		pose.crouch = 0.0
	if anim_tree:
		anim_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func _retreat_step(delta: float, distance: float, to_goat: Vector3) -> void:
	# Fall back from the goat toward cover, or straight away when there is none.
	var away := -to_goat
	if cover_point != Vector3.INF and role == "rifleman":
		_move = _steer_to(cover_point)
	else:
		_move = _steer_to(global_position + away * 8.0)
	_move_speed = speed * 1.15
	_look = global_position + _move
	_head_target = target.global_position + Vector3(0.0, 1.0, 0.0)
	_head_weight = 0.5
	var flanked := role == "rifleman" and distance < 6.0 and combat_time > 1.0
	if combat_time > 4.5 or distance > 17.0 or flanked:
		combat = Combat.CIRCLE
		combat_time = 0.0
		if role == "rifleman":
			combat = Combat.NONE


# --- Riflemen -----------------------------------------------------------------

func _ranged_brain(delta: float, distance: float, to_goat: Vector3) -> void:
	cover_scan_in -= delta
	match combat:
		Combat.NONE, Combat.APPROACH, Combat.CIRCLE, Combat.RECOVER:
			if combat == Combat.RECOVER:
				_turn_lock = false
				_move = to_goat.rotated(Vector3.UP, PI * 0.5 * circle_direction) * 0.4
				_move_speed = speed * 0.5
				if combat_time >= recover_total:
					combat = Combat.NONE
					combat_time = 0.0
				return
			if _chase_lost_target(delta):
				return
			_ranged_hunt(delta, distance, to_goat)
		Combat.COVER:
			_cover_step(delta, distance, to_goat)
		Combat.PEEK:
			_peek_step(delta, distance, to_goat)
		Combat.AIM:
			_aim_step(delta, distance, to_goat)
		Combat.RELOAD:
			_reload_step(delta, distance)
		Combat.WINDUP:
			_windup_step(delta, distance, to_goat)
		Combat.STRIKE:
			_strike_step(delta, distance)
		Combat.RETREAT:
			_retreat_step(delta, distance, to_goat)
		_:
			combat = Combat.NONE


func _ranged_hunt(delta: float, distance: float, to_goat: Vector3) -> void:
	# Flanked: the goat is too close for a rifle. Back off toward cover; if
	# cornered, use the bayonet.
	if distance < 6.0:
		if _stuck_for > 0.3 or distance < attack_range + 0.3:
			if cooldown <= 0.0 and distance <= attack_range + 0.6 and PackDirector.request("melee", self):
				_begin_windup(to_goat, "bayonet")
				return
		combat = Combat.RETREAT
		combat_time = 0.0
		if cover_scan_in <= 0.0:
			_find_cover()
			cover_scan_in = 2.0
		return
	if rounds <= 0:
		_begin_reload()
		return
	if distance > ranged_range - 2.0:
		combat = Combat.APPROACH
		_move = _steer_to(target.global_position)
		_move_speed = speed
		return
	# In range with a line on the goat: take a token and aim, or hold and strafe
	# while a packmate has the floor.
	if cooldown <= 0.0 and _muzzle_clear() and PackDirector.request("ranged", self):
		_begin_aim(1.0 if pack_role == "marksman" else 0.75)
		return
	if cover_point == Vector3.INF and cover_scan_in <= 0.0:
		_find_cover()
		cover_scan_in = 2.5
	if cover_point != Vector3.INF and _flat_distance_to(cover_point) > 0.8 and distance > 9.0:
		combat = Combat.COVER
		combat_time = 0.0
		return
	combat = Combat.CIRCLE
	var tangent := to_goat.rotated(Vector3.UP, PI * 0.5 * circle_direction)
	var radial := clampf((distance - 13.0) * 0.4, -1.0, 1.0)
	_move = (to_goat * radial + tangent * 0.7).normalized()
	_move_speed = speed * 0.5


func _begin_aim(seconds: float) -> void:
	combat = Combat.AIM
	combat_time = 0.0
	aim_total = seconds
	aim_locked = false
	aim_blocked_for = 0.0
	if burst_left <= 0:
		burst_left = 2 if pack_role != "suppressor" else 1
	aim_direction = (target.chest_position() - _muzzle_position()).normalized()
	_sound("aim_charge", -8.0, 1.0, "click")
	_flash_eyes(Color(1.0, 0.15, 0.08), 0.6)


func _aim_step(delta: float, distance: float, to_goat: Vector3) -> void:
	var total := aim_total
	_look = target.global_position
	_head_weight = 0.4
	# A rifleman takes a stance: still, low, and pointed at the goat.
	if pose:
		pose.crouch = lerpf(pose.crouch, 0.55, minf(1.0, delta * 6.0))
	if not _muzzle_clear():
		aim_blocked_for += delta
		if aim_blocked_for > 0.6:
			_abort_aim()
			return
	else:
		aim_blocked_for = 0.0
	var flight := distance / EnemyBullet.SPEED
	var lead: Vector3 = Vector3(target.velocity.x, 0.0, target.velocity.z) * flight * 0.55
	var aim_point := target.chest_position() + lead
	var wanted := (aim_point - _muzzle_position()).normalized()
	if not aim_locked:
		aim_direction = aim_direction.slerp(wanted, minf(1.0, delta * 5.5)).normalized()
		if combat_time >= total - 0.22:
			aim_locked = true
	rifle_aim = aim_direction
	_set_laser(clampf(combat_time / total, 0.0, 1.0))
	if combat_time >= total:
		_fire_rifle(distance)


func _abort_aim() -> void:
	_set_laser(0.0)
	combat = Combat.NONE
	combat_time = 0.0
	aim_locked = false
	burst_left = 0
	cooldown = 0.6
	PackDirector.release("ranged", self)
	if pose:
		pose.crouch = 0.0


## Accuracy climbs with time in sight and falls when the goat is moving or
## crouched, or far away. 0..1.
func rifle_accuracy(distance: float) -> float:
	var accuracy := clampf(0.3 + sight_time * 0.12, 0.3, 0.88)
	var moving := clampf(Vector2(target.velocity.x, target.velocity.z).length() / 5.5, 0.0, 1.0)
	accuracy -= moving * 0.32
	if target.crouched:
		accuracy -= 0.12
	accuracy -= clampf((distance - 8.0) / 34.0, 0.0, 0.25)
	if pack_role == "suppressor":
		accuracy -= 0.15
	return clampf(accuracy, 0.08, 0.92)


func _fire_rifle(distance: float) -> void:
	_set_laser(0.0)
	if not _muzzle_clear():
		_abort_aim()
		return
	var spread := lerpf(0.11, 0.008, rifle_accuracy(distance))
	var jitter := Basis(Vector3.UP, randf_range(-spread, spread)) * Basis(Vector3.RIGHT, randf_range(-spread, spread))
	var direction := (jitter * aim_direction).normalized()
	var muzzle := _muzzle_position()
	EnemyBullet.fire(get_parent(), muzzle, direction, 11 + randi_range(0, 3), self, target)
	EnemyFx.muzzle_flash(get_parent(), muzzle + direction * 0.15, direction)
	_sound("rifle_crack", 0.0, randf_range(0.9, 1.1), "shot")
	rounds -= 1
	burst_left -= 1
	if rifle_pivot:
		rifle_recoil = 1.0
	velocity -= facing() * 1.3
	cooldown = attack_cooldown * 0.5
	if rounds <= 0:
		burst_left = 0
		PackDirector.release("ranged", self)
		_begin_reload()
	elif burst_left > 0:
		combat_time = 0.0
		aim_total = 0.3
		aim_locked = false
	else:
		PackDirector.release("ranged", self)
		cooldown = attack_cooldown + randf_range(0.2, 1.0)
		if cover_point != Vector3.INF and _flat_distance_to(cover_point) > 0.6 and cover_point.distance_to(target.global_position) > 7.0:
			combat = Combat.COVER
		else:
			combat = Combat.RECOVER
			recover_total = randf_range(0.7, 1.3)
			circle_direction = -circle_direction
		combat_time = 0.0
		hide_for = randf_range(1.4, 2.6)
		if pose:
			pose.crouch = 0.0


func _begin_reload() -> void:
	combat = Combat.RELOAD if cover_point == Vector3.INF else Combat.COVER
	combat_time = 0.0
	hide_for = 2.4
	reloading = true
	_set_laser(0.0)
	PackDirector.release("ranged", self)


func _reload_step(delta: float, distance: float) -> void:
	# No cover nearby: crouch and reload where standing, slowly backing off.
	if pose:
		pose.crouch = lerpf(pose.crouch, 0.8, minf(1.0, delta * 6.0))
	_move = -(target.global_position - global_position).normalized() * 0.3
	_move.y = 0.0
	_move_speed = speed * 0.4
	if combat_time < delta * 1.5:
		_sound("reload", -4.0, randf_range(0.9, 1.1), "click")
	if combat_time >= 2.4:
		rounds = 4
		reloading = false
		reload_sound_played = false
		combat = Combat.NONE
		combat_time = 0.0
		if pose:
			pose.crouch = 0.0


func _cover_step(delta: float, distance: float, to_goat: Vector3) -> void:
	if cover_point == Vector3.INF:
		combat = Combat.NONE
		return
	if distance < 6.0:
		combat = Combat.RETREAT
		combat_time = 0.0
		cover_point = Vector3.INF
		return
	if _flat_distance_to(cover_point) > 0.7:
		_move = _steer_to(cover_point)
		_move_speed = speed * 1.25
		_look = global_position + _move
		return
	# Behind cover: crouch out of sight, reload if empty, then work back to a peek.
	if pose:
		pose.crouch = lerpf(pose.crouch, 1.0, minf(1.0, delta * 6.0))
	_look = target.global_position
	if reloading and not reload_sound_played:
		reload_sound_played = true
		_sound("reload", -4.0, randf_range(0.9, 1.1), "click")
	hide_for -= delta
	_idle_variant = "Idle_2_HeadLow"
	if hide_for <= 0.0:
		if reloading:
			rounds = 4
			reloading = false
			reload_sound_played = false
		combat = Combat.PEEK
		combat_time = 0.0
		if pose:
			pose.crouch = 0.0


func _peek_step(delta: float, distance: float, to_goat: Vector3) -> void:
	if peek_point == Vector3.INF or combat_time > 3.5:
		cover_point = Vector3.INF
		peek_point = Vector3.INF
		combat = Combat.NONE
		cover_scan_in = 0.0
		return
	_move = _steer_to(peek_point)
	_move_speed = speed * 0.9
	_look = target.global_position
	if (_flat_distance_to(peek_point) < 0.6 or _muzzle_clear()) and cooldown <= 0.0:
		if PackDirector.request("ranged", self):
			_begin_aim(0.7 if pack_role != "marksman" else 0.95)


## Scans a ring of candidate points around the rifleman for one that stone or
## wall hides from the goat, with a lateral peek point that sees the goat again.
func _find_cover() -> bool:
	var best := Vector3.INF
	var best_peek := Vector3.INF
	var best_score := INF
	var goat_chest := target.chest_position()
	var goat_position := target.global_position
	var claimed: Array[Vector3] = []
	for other in get_tree().get_nodes_in_group("enemies"):
		if other != self and not other.dead and other.cover_point != Vector3.INF:
			claimed.append(other.cover_point)
	for ring in [3.5, 6.5, 9.5]:
		for index in 10:
			var angle := TAU * index / 10.0 + randf() * 0.35
			var point: Vector3 = global_position + Vector3(cos(angle), 0.0, sin(angle)) * ring
			point.y = WorldBuilder.height_at(point.x, point.z)
			if EnemyNav.is_ready():
				var on_mesh := EnemyNav.snap(point)
				if Vector2(on_mesh.x - point.x, on_mesh.z - point.z).length() > 0.8:
					continue
				point = on_mesh
			var from_goat := Vector2(point.x - goat_position.x, point.z - goat_position.z).length()
			if from_goat < 7.5 or from_goat > ranged_range - 3.0:
				continue
			if not _blocked_from(point + Vector3(0.0, 0.9, 0.0), goat_chest):
				continue
			var taken := false
			for other_cover in claimed:
				if other_cover.distance_to(point) < 2.2:
					taken = true
			if taken:
				continue
			var lateral := Vector3(goat_position.x - point.x, 0.0, goat_position.z - point.z).cross(Vector3.UP).normalized()
			var peek := Vector3.INF
			for side in [1.0, -1.0]:
				for reach in [1.6, 2.6]:
					var candidate: Vector3 = point + lateral * side * reach
					candidate.y = WorldBuilder.height_at(candidate.x, candidate.z)
					if EnemyNav.walkable(candidate) and not _blocked_from(candidate + Vector3(0.0, 0.9, 0.0), goat_chest):
						peek = candidate
						break
				if peek != Vector3.INF:
					break
			if peek == Vector3.INF:
				continue
			var score := global_position.distance_to(point) + absf(from_goat - 14.0) * 0.4
			if score < best_score:
				best_score = score
				best = point
				best_peek = peek
	cover_point = best
	peek_point = best_peek
	return best != Vector3.INF


func _blocked_from(from: Vector3, to: Vector3) -> bool:
	if los_query == null:
		_make_query()
	los_query.from = from
	los_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(los_query)
	return not hit.is_empty() and hit.collider != target


func _muzzle_position() -> Vector3:
	if is_instance_valid(rifle_muzzle) and rifle_muzzle.is_inside_tree():
		return rifle_muzzle.global_position
	return eye_position()


## A shot is only taken when the barrel itself sees the goat: nothing fires
## through a wall, and a rifleman peeking past a rock has to actually clear it.
func _muzzle_clear() -> bool:
	if los_query == null:
		_make_query()
	var muzzle := _muzzle_position()
	# The barrel itself must be in open air: an animal pressed against stone
	# would otherwise start its round inside the wall and shoot straight through.
	var mount := rifle_pivot.global_position if is_instance_valid(rifle_pivot) else eye_position()
	los_query.from = mount
	los_query.to = muzzle
	if not get_world_3d().direct_space_state.intersect_ray(los_query).is_empty():
		return false
	los_query.from = muzzle
	los_query.to = target.chest_position()
	var hit := get_world_3d().direct_space_state.intersect_ray(los_query)
	return not hit.is_empty() and hit.collider == target


## The aiming beam: a thin red line from the muzzle to whatever it lands on,
## brightening as the shot commits. `intensity` 0 hides it.
func _set_laser(intensity: float) -> void:
	if intensity <= 0.001:
		if is_instance_valid(laser):
			laser.visible = false
		return
	if laser == null:
		laser = MeshInstance3D.new()
		laser.name = "AimBeam"
		var beam := BoxMesh.new()
		beam.size = Vector3.ONE
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 0.05, 0.03, 0.5)
		beam.material = material
		laser.mesh = beam
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(laser)
		laser.top_level = true
	var origin := _muzzle_position()
	var end := origin + aim_direction * 45.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, WORLD_AND_PLAYER_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		end = hit.position
	var length := origin.distance_to(end)
	laser.visible = true
	laser.global_position = (origin + end) * 0.5
	laser.look_at(end, Vector3.UP if absf(aim_direction.y) < 0.99 else Vector3.RIGHT)
	var width := 0.006 + intensity * 0.012
	laser.scale = Vector3(width, width, length)
	var material := (laser.mesh as BoxMesh).material as StandardMaterial3D
	material.albedo_color.a = 0.15 + intensity * 0.6


# --- Varkas ----------------------------------------------------------------------

func boss_phase_title() -> String:
	if not boss:
		return ""
	return Story.BOSS_PHASES.get(boss_phase, {}).get("title", "VARKAS")


## One timeline owns tells, impacts, and recovery. A charge locks its aim at
## the warning, then travels straight; both a sidestep and Convergence can beat it.
## Every attack is announced by a body pose (rear, slam, crouch) that matches it.
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
		_boss_windup_pose()
		if boss_windup_for <= 0.0:
			_clear_boss_telegraph()
			if boss_attack_kind == "charge":
				boss_charge_for = 1.15
				_set_boss_pitch(0.0, 0.18)
				_release_attack()
				boss_attack.emit(self, "charge_release")
			elif boss_attack_kind == "bellquake":
				# A jump clears the ground pulse; stone cover also blocks it.
				var above_ground := target.global_position.y - WorldBuilder.height_at(target.global_position.x, target.global_position.z)
				if distance <= 11.5 and above_ground < 1.65 and _has_line_of_sight():
					target.damage(18, global_position)
					target.knockback(global_position, 7.0, 2.0)
					boss_hit_landed = true
				_shockwave_visual(Color("f8cd89"), 11.5, 0.25)
				_boss_slam(11.5, 0.5)
				_finish_boss_attack(1.25)
			else:
				if distance <= 6.0 and boss_attack_direction.dot(to_goat) > 0.5 and _has_line_of_sight():
					target.damage(26 if boss_phase == 1 else 32, global_position)
					target.knockback(global_position, 6.0, 2.0)
					boss_hit_landed = true
				_release_attack()
				_sound("bite", 1.0, 0.7)
				_boss_slam(6.0, 0.22)
				_finish_boss_attack(1.15)
		return Vector3.ZERO
	if boss_charge_for > 0.0:
		boss_charge_for = maxf(0.0, boss_charge_for - delta)
		var offset := target.global_position - global_position
		offset.y = 0.0
		var forward := offset.dot(boss_attack_direction)
		var lateral := (offset - boss_attack_direction * forward).length()
		if forward >= 0.0 and forward <= 4.5 and lateral <= 1.65 and _has_line_of_sight():
			target.damage(38, global_position)
			target.knockback(global_position, 10.0, 3.0)
			boss_hit_landed = true
			_sound("bite", 4.0, 0.62)
			_finish_boss_attack(1.65)
			return Vector3.ZERO
		if boss_charge_for <= 0.0:
			_finish_boss_attack(1.65)
			return Vector3.ZERO
		if is_on_wall() and boss_charge_for < 1.0:
			# Horn into stone: the arena is the answer to Red Horn. A long stun
			# and a cloud of shattered rime give the goat her longest opening.
			_boss_slam(8.0, 0.4)
			_sound("wall_slam", 5.0, 0.6, "thud")
			_finish_boss_attack(3.0)
			boss_attack.emit(self, "wall_stun")
			return Vector3.ZERO
		if fmod(boss_charge_for, 0.12) < delta:
			EnemyFx.dust_burst(get_parent(), global_position + Vector3(0.0, 0.1, 0.0), 6, 1.4)
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
			boss_windup_total = 0.95
			boss_hit_landed = false
			boss_attack.emit(self, "charge")
			_sound("roar", 3.0, 0.6, "growl")
			_show_charge_lane()
			return Vector3.ZERO
	if distance <= 6.2 and cooldown <= 0.0:
		boss_attack_kind = "swipe"
		boss_attack_direction = to_goat
		boss_windup_for = 0.85
		boss_windup_total = 0.85
		boss_hit_landed = false
		boss_attack.emit(self, "swipe")
		_play_attack(0.85)
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
	boss_windup_total = 1.2
	boss_hit_landed = false
	boss_attack_direction = facing()
	boss_attack.emit(self, "bellquake")
	_sound("bell", 5.0, 0.55)
	boss_telegraph = _shockwave_visual(Color("d98b45"), 11.5, 1.2)


func _finish_boss_attack(recovery: float, count_dodge := true) -> void:
	var was_kind := boss_attack_kind
	_cancel_boss_attack(false)
	boss_recovery_for = recovery
	cooldown = recovery + 0.65
	if count_dodge and was_kind != "" and not boss_hit_landed:
		boss_attack.emit(self, "dodged")
		attack_dodged.emit(self)
	boss_attack.emit(self, "exposed")
	_boss_expose(recovery)


## The wind-up pose that matches the announced attack: Iron Jaw rears half up,
## the Bellquake rears fully with the ground trembling, Red Horn drops to a crouch.
func _boss_windup_pose() -> void:
	if boss_windup_total <= 0.0:
		return
	var progress := clampf(1.0 - boss_windup_for / boss_windup_total, 0.0, 1.0)
	var eased := progress * progress * (3.0 - 2.0 * progress)
	match boss_attack_kind:
		"swipe":
			_set_boss_pitch(0.42 * eased)
		"bellquake":
			_set_boss_pitch(0.78 * eased)
			if boss_windup_for > 0.05 and fmod(boss_windup_for, 0.3) < get_physics_process_delta_time() and is_instance_valid(target):
				target.add_camera_trauma(0.05)
		"charge":
			_set_boss_pitch(-0.16 * eased)
			if fmod(boss_windup_for, 0.22) < get_physics_process_delta_time():
				EnemyFx.dust_burst(get_parent(), global_position + facing() * 1.8, 6, 1.0)


## The hit that ends a wind-up: forebody slams back down, a ring of rime jumps
## out and the goat's camera takes it.
func _boss_slam(radius: float, trauma: float) -> void:
	_set_boss_pitch(0.0, 0.13)
	EnemyFx.dust_burst(get_parent(), global_position + facing() * 1.5, int(radius * 4.0), radius * 0.35)
	if is_instance_valid(target) and target.global_position.distance_to(global_position) < radius + 8.0:
		target.add_camera_trauma(trauma)


## Pitches the whole body (skinned mesh and root-level hero shell together)
## about the hind paws: positive lifts the muzzle.
func _set_boss_pitch(angle: float, seconds := 0.0) -> void:
	if not boss or not is_instance_valid(model):
		return
	_kill_pitch_tween()
	if seconds > 0.0 and is_inside_tree():
		_pitch_tween = create_tween()
		_pitch_tween.tween_method(_apply_boss_pitch, boss_pitch, angle, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	_apply_boss_pitch(angle)


## Only one motion owns Varkas' stance at a time; a new one replaces the last.
func _kill_pitch_tween() -> void:
	if _pitch_tween and _pitch_tween.is_valid():
		_pitch_tween.kill()
	_pitch_tween = null


func _apply_boss_pitch(angle: float) -> void:
	if not is_instance_valid(model):
		return
	boss_pitch = angle
	var rotation_basis := Basis(Vector3.RIGHT, angle)
	var pivot := Vector3(0.0, 0.5, 1.15)
	var pitched := Transform3D(rotation_basis, pivot - rotation_basis * pivot)
	model.transform = pitched
	if is_instance_valid(boss_shell):
		boss_shell.transform = pitched


## In the recovery window Varkas is visibly open: head hung, Orin's bell glowing.
func _boss_expose(seconds: float) -> void:
	if not is_inside_tree():
		return
	_set_boss_pitch(-0.09, 0.2)
	if boss_bell_material:
		var glow := create_tween()
		glow.tween_property(boss_bell_material, "emission_energy_multiplier", 2.6, 0.2)
		glow.tween_interval(maxf(0.1, seconds - 0.5))
		glow.tween_property(boss_bell_material, "emission_energy_multiplier", 0.15, 0.35)
	var recover_pose := create_tween()
	recover_pose.tween_interval(maxf(0.1, seconds - 0.25))
	recover_pose.tween_callback(func() -> void:
		# Only settle back if nothing else has taken over the stance meanwhile.
		if boss_windup_for <= 0.0 and boss_charge_for <= 0.0 and boss_transition_lock <= 0.0 and not execution_ready and not dead:
			_set_boss_pitch(0.0, 0.25))


func _clear_boss_telegraph() -> void:
	if is_instance_valid(boss_telegraph):
		boss_telegraph.queue_free()
	boss_telegraph = null


func _cancel_boss_attack(abort_animation := true) -> void:
	_clear_boss_telegraph()
	boss_windup_for = 0.0
	boss_charge_for = 0.0
	boss_recovery_for = 0.0
	boss_attack_kind = ""
	if anim_tree and abort_animation:
		anim_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


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


# --- Damage, death, and phase beats ----------------------------------------------

func take_damage(amount: int, stagger_seconds := 0.22, silent := false) -> void:
	if dead or execution_ready:
		return
	# Phase breaks are real beats, not thresholds a multi-shot volley can cross in
	# one frame. Iron and bell-light reject damage during the short transition.
	if boss and boss_transition_lock > 0.0:
		return
	var phase_before := boss_phase
	var heavy := stagger_seconds >= 0.5
	var was_unaware := detection < Stealth.SUSPICIOUS
	health -= amount
	if is_instance_valid(target):
		hit_direction = Vector3(global_position.x - target.global_position.x, 0.0, global_position.z - target.global_position.z).normalized()
	_spawn_blood(amount, health <= 0 and not boss)
	if boss and boss_phase == 1 and health <= ceili(max_health * 0.66):
		health = maxi(health, ceili(max_health * 0.66))
		_enter_boss_phase(2)
	elif boss and boss_phase == 2 and health <= ceili(max_health * 0.33):
		health = maxi(health, ceili(max_health * 0.33))
		_enter_boss_phase(3)
	stagger = maxf(stagger, 0.06 if boss else stagger_seconds)
	if boss and boss_phase == phase_before and stagger_seconds >= Remembrance.CONVERGENCE_STAGGER:
		_finish_boss_attack(1.5, false)
		stagger = maxf(stagger, 1.0)
		boss_attack.emit(self, "convergence_break")
	_flash_hit()
	if boss and boss_phase >= 3 and health <= 0:
		_break_for_execution()
		return
	if health <= 0:
		_die(4.5 if heavy or was_unaware else 3.0, heavy or was_unaware)
		return
	if not boss:
		_flinch(amount, heavy)
	else:
		_react(randf() < 0.5)
	_sound("yelp", -6.0, 0.6 if boss else randf_range(0.9, 1.2))
	if not silent:
		_go_alert(target.global_position if target else global_position)


## Directional flinch that keeps the AI running: a shove away from the shot, an
## upper-body hit clip on the side it came from, and a spoiled wind-up or aim.
func _flinch(amount: int, heavy: bool) -> void:
	var attacker := global_transform.basis.inverse() * -hit_direction
	_react(attacker.x < 0.0)
	velocity += hit_direction * (3.6 if heavy else 1.8)
	match combat:
		Combat.WINDUP:
			# Poise: brutes shrug light hits off mid-windup; everyone else is broken.
			if role != "brute" or heavy or amount > 60:
				if anim_tree:
					anim_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
				PackDirector.release("melee", self)
				combat = Combat.RECOVER
				combat_time = 0.0
				recover_total = 0.55
				cooldown = 0.5
				if pose:
					pose.crouch = 0.0
		Combat.AIM:
			aim_locked = false
			combat_time = maxf(0.0, combat_time - (0.45 if heavy else 0.22))
		Combat.CHARGE:
			if heavy:
				_finish_melee(1.3)


func _flash_hit() -> void:
	if body_material:
		body_material.emission_enabled = true
		body_material.emission = Color("ff5b27")
		body_material.emission_energy_multiplier = 1.8
		var tween := create_tween()
		tween.tween_property(body_material, "emission_energy_multiplier", 0.0, 0.16)
	if not fur_materials.is_empty():
		if _flash_tween and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash_tween = create_tween()
		for material in fur_materials:
			material.set_shader_parameter("flash", 1.0)
		_flash_tween.set_parallel(true)
		for material in fur_materials:
			_flash_tween.tween_method(func(value: float) -> void: material.set_shader_parameter("flash", value), 1.0, 0.0, 0.18)


func _enter_boss_phase(next_phase: int) -> void:
	if not boss or next_phase <= boss_phase:
		return
	_cancel_boss_attack()
	boss_phase = next_phase
	boss_transition_lock = 1.35
	stagger = maxf(stagger, 1.35)
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
	# Eyes, embers, light and the horn's presence change at once; the plates
	# stay on until the beat's roar tears them off.
	_apply_boss_phase_appearance(false)
	if is_instance_valid(boss_red_horn) and boss_phase >= 3:
		boss_red_horn.scale = Vector3.ONE * 0.05
	boss_phase_changed.emit(self, boss_phase, boss_phase_title())
	_boss_transition_beat()


## The cinematic beat between phases: Varkas rears back and roars as his armor
## tears free and flies off, the arena flashes, and he drops with a slam that
## throws rime across the courtyard. Red Horn's horn grows out of the break.
func _boss_transition_beat() -> void:
	_sound("howl", 5.0, 0.55 if boss_phase == 2 else 0.48)
	_play_roar_pose()
	_kill_pitch_tween()
	var beat := create_tween()
	_pitch_tween = beat
	beat.tween_method(_apply_boss_pitch, boss_pitch, 0.7, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	beat.tween_callback(func() -> void:
		_sound("roar", 6.0, 0.55 if boss_phase == 2 else 0.45, "howl")
		_shed_plates()
		_grow_horn()
		_arena_flash(Color("ff8a3a") if boss_phase == 2 else Color("ff2a18"))
		_shockwave_visual(Color("d06a32") if boss_phase == 2 else Color("a91512"), 7.0, 0.7)
		if is_instance_valid(target):
			target.add_camera_trauma(0.35))
	beat.tween_interval(0.3)
	beat.tween_method(_apply_boss_pitch, 0.7, 0.0, 0.14).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	beat.tween_callback(func() -> void:
		_boss_slam(13.0, 0.5)
		_shockwave_visual(Color("f8cd89"), 13.0, 0.5)
		boss_attack.emit(self, "phase_slam"))


func _play_roar_pose() -> void:
	_react(true)


## A flash of coloured light over the courtyard.
func _arena_flash(color: Color) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 9.0
	flash.omni_range = 22.0
	flash.shadow_enabled = false
	add_child(flash)
	flash.position = Vector3(0.0, 2.2, 0.0)
	var fade := flash.create_tween()
	fade.tween_property(flash, "light_energy", 0.0, 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	fade.tween_callback(flash.queue_free)


## Shared by the real phase transitions and deterministic visual proof capture.
func preview_boss_phase(phase_index: int) -> void:
	if not boss:
		return
	boss_phase = clampi(phase_index, 1, 3)
	_apply_boss_phase_appearance()


func _apply_boss_phase_appearance(plates := true) -> void:
	if not boss:
		return
	if plates:
		for index in boss_armor.size():
			var plate := boss_armor[index]
			if is_instance_valid(plate):
				plate.visible = _plate_kept(plate, index)
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
		if plates:
			boss_red_horn.scale = Vector3.ONE


func _plate_kept(plate: MeshInstance3D, index: int) -> bool:
	return boss_phase == 1 or (boss_phase == 2 and index % 2 == 1) or (boss_phase == 3 and plate.get_meta("red_horn_remnant", false))


## Armor the new phase no longer keeps is torn off as flying debris.
func _shed_plates() -> void:
	for index in boss_armor.size():
		var plate := boss_armor[index]
		if not is_instance_valid(plate):
			continue
		var keep := _plate_kept(plate, index)
		if plate.visible and not keep:
			_shed_armor(plate)
		plate.visible = keep


## The horn grows out of the break rather than popping into place.
func _grow_horn() -> void:
	if not is_instance_valid(boss_red_horn) or boss_phase < 3:
		return
	boss_red_horn.visible = true
	boss_red_horn.scale = Vector3.ONE * 0.05
	var growth := boss_red_horn.create_tween()
	growth.tween_property(boss_red_horn, "scale", Vector3.ONE, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	EnemyFx.sparks(get_parent(), boss_red_horn.global_position, Vector3.UP, 30, 6.0, Color("ff3b1c"))


## A torn plate leaves the body as a physical piece and tumbles away.
func _shed_armor(plate: MeshInstance3D) -> void:
	if not is_inside_tree() or plate.mesh == null:
		return
	var outward := (plate.global_position - global_position - Vector3(0.0, 1.4, 0.0))
	outward.y = 0.0
	outward = outward.normalized() if outward.length() > 0.05 else Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var impulse := outward * randf_range(4.5, 8.0) + Vector3(0.0, randf_range(4.0, 7.0), 0.0)
	var spin := Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
	var material := plate.mesh.surface_get_material(0) if plate.mesh.get_surface_count() > 0 else iron
	var body := EnemyFx.debris(get_parent(), plate.global_transform, plate.mesh, material if material else iron, impulse, spin, 7.0)
	body.mass = 8.0
	EnemyFx.sparks(get_parent(), plate.global_position, outward + Vector3.UP, 8, 5.0)


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
	_set_boss_pitch(-0.3, 0.9)
	_arena_flash(Color("ffc36b"))
	EnemyFx.dust_burst(get_parent(), global_position + facing() * 1.5, 30, 3.0)
	_hitstop(0.12, 0.35)
	boss_attack.emit(self, "broken")
	# Orin's bell glows through the wreck: the mark to strike at.
	if is_instance_valid(boss_bell) and boss_bell_material:
		var pulse := boss_bell.create_tween().set_loops()
		pulse.tween_property(boss_bell_material, "emission_energy_multiplier", 3.2, 0.55).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(boss_bell_material, "emission_energy_multiplier", 0.8, 0.55).set_trans(Tween.TRANS_SINE)


func execute_boss() -> void:
	if not boss or dead or not execution_ready:
		return
	execution_ready = false
	health = 0
	boss_transition_lock = 0.0
	_spawn_blood(240, true)
	for plate in boss_armor:
		if is_instance_valid(plate) and plate.visible:
			_shed_armor(plate)
			plate.visible = false
	_arena_flash(Color("fff0c0"))
	_hitstop(0.08, 0.5)
	_die(0.0, true)


## A horn strike from behind: instant, silent, and staged. The victim is
## hauled back onto the horn, thrown a little, and goes down without a sound.
func takedown() -> void:
	if dead:
		return
	health = 0
	var pull := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z) if is_instance_valid(target) else Vector3.ZERO
	hit_direction = -pull.normalized() if pull.length() > 0.05 else Vector3.ZERO
	_spawn_blood(180, true)
	_die(0.0, true, true)
	if pull.length() > 0.05:
		_corpse_slide = pull.normalized() * 2.4
	if is_instance_valid(target):
		target.add_camera_trauma(0.16)
	EnemyFx.sparks(get_parent(), global_position + Vector3(0.0, 0.7 * size_scale, 0.0), Vector3.UP, 10, 3.0, Color(0.5, 0.03, 0.02))


func _die(kick := 3.0, feedback := false, quiet := false) -> void:
	dead = true
	collision_layer = 0
	collision_mask = 1
	remove_from_group("enemies")
	if not boss:
		add_to_group("corpses")
	PackDirector.release_all(self)
	killed.emit(self)
	_set_laser(0.0)
	if not quiet:
		_sound("death", 0.0, 0.6 if boss else randf_range(0.9, 1.15))
	if eye_light:
		eye_light.light_energy = 0.0
	if eye_material:
		eye_material.emission_energy_multiplier = 0.0
	if head_material:
		head_material.set_shader_parameter("eye_energy", 0.0)
	if is_instance_valid(eye_beam):
		eye_beam.visible = false
	if pose:
		pose.look_weight = 0.0
		pose.crouch = 0.0
	_drop_gear()
	if boss:
		_apply_boss_pitch(0.0)
	if anim_tree:
		anim_tree.active = false
	if anim:
		anim.speed_scale = 1.35 if quiet else 1.0
		anim.play("Death", 0.08)
	_corpse_slide = hit_direction * kick
	velocity = Vector3(_corpse_slide.x, 0.0, _corpse_slide.z)
	if not boss and is_instance_valid(model):
		# The clip supplies the fall to one side; a lean away from the shot sells
		# where the force came from.
		var lean := hit_direction
		if lean.length() > 0.05:
			var local_lean := global_transform.basis.inverse() * lean
			var tip := model.create_tween()
			tip.tween_property(model, "rotation", Vector3(local_lean.z * 0.32, 0.0, -local_lean.x * 0.32), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if feedback:
		_hitstop(0.35, 0.07)
	if boss and is_instance_valid(boss_shell):
		var shell_fall := boss_shell.create_tween()
		shell_fall.set_parallel(true)
		shell_fall.tween_property(boss_shell, "rotation:z", 1.18, 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		shell_fall.tween_property(boss_shell, "position", Vector3(-0.58, -0.48, 0.08), 0.62).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if boss:
		var tween := create_tween()
		tween.tween_interval(2.6)
		tween.tween_property(self, "position:y", position.y - 1.4, 1.2)
		tween.tween_callback(queue_free)
	_pool_blood()


## Real physics props for what a wolverine carried: the rifle slides off its
## harness and the neck-bell drops, rings once and rolls.
func _drop_gear() -> void:
	if boss:
		return
	if is_instance_valid(rifle_pivot):
		var rifle := rifle_pivot.get_child(0) as Node3D
		if rifle:
			var transform_at := rifle.global_transform
			var body := RigidBody3D.new()
			body.collision_layer = 0
			body.collision_mask = 1
			body.mass = 3.0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.14, 0.2, 0.9)
			shape.shape = box
			body.add_child(shape)
			get_parent().add_child(body)
			body.global_transform = Transform3D(transform_at.basis.orthonormalized(), transform_at.origin)
			rifle.reparent(body, true)
			rifle.position = Vector3(0.0, 0.0, 0.0)
			body.linear_velocity = hit_direction * 2.4 + Vector3(0.0, 2.0, 0.0)
			body.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
			var timer := body.create_tween()
			timer.tween_interval(CORPSE_LIFETIME)
			timer.tween_callback(body.queue_free)
		rifle_pivot.queue_free()
		rifle_pivot = null
	if is_instance_valid(collar_bell):
		var bell := collar_bell
		var bell_transform := bell.global_transform
		var body := RigidBody3D.new()
		body.collision_layer = 0
		body.collision_mask = 1
		body.mass = 0.8
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.1
		shape.shape = sphere
		shape.position.y = -0.08
		body.add_child(shape)
		get_parent().add_child(body)
		body.global_transform = Transform3D(bell_transform.basis.orthonormalized(), bell_transform.origin)
		bell.reparent(body, true)
		body.linear_velocity = hit_direction * 1.8 + Vector3(0.0, 2.6, 0.0)
		body.angular_velocity = Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
		body.contact_monitor = true
		body.max_contacts_reported = 2
		var rung := [false]
		body.body_entered.connect(func(_other: Node) -> void:
			if not rung[0]:
				rung[0] = true
				EnemyFx.sound(body.get_tree(), "bell_strike", body.global_position, -8.0, randf_range(1.6, 2.1), "bell"))
		var timer := body.create_tween()
		timer.tween_interval(CORPSE_LIFETIME)
		timer.tween_callback(body.queue_free)
		collar_bell = null


## A dark pool spreads under the fallen wolverine.
func _pool_blood() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var pool := MeshInstance3D.new()
	pool.name = "BloodPool"
	var pool_mesh := PlaneMesh.new()
	pool_mesh.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.004, 0.003, 0.0)
	material.roughness = 0.35
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_mesh.material = material
	pool.mesh = pool_mesh
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(pool)
	pool.global_position = Vector3(global_position.x, WorldBuilder.height_at(global_position.x, global_position.z) + 0.03, global_position.z)
	pool.rotation.y = randf() * TAU
	pool.scale = Vector3.ONE * 0.2
	var size := 1.9 if boss else 1.15 * size_scale
	var spread := pool.create_tween()
	spread.set_parallel(true)
	spread.tween_property(pool, "scale", Vector3(size, 1.0, size * 0.8), 5.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	spread.tween_property(material, "albedo_color:a", 0.7, 1.5)
	spread.chain().tween_interval(CORPSE_LIFETIME)
	spread.chain().tween_property(material, "albedo_color:a", 0.0, 3.0)
	spread.chain().tween_callback(pool.queue_free)


static var _hitstop_active := false


## A short freeze-frame on a kill: the world drops to a fraction of its speed
## and returns. Guarded so overlapping kills never stack.
func _hitstop(scale: float, real_seconds: float) -> void:
	if _hitstop_active or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	_hitstop_active = true
	Engine.time_scale = scale
	var timer := get_tree().create_timer(real_seconds, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = 1.0
		_hitstop_active = false)


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



# --- Model ---------------------------------------------------------------------

func _build_body() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(52.0)
	var target_height := (3.0 if boss else (1.6 if role == "brute" else (1.1 if role == "stalker" else 1.22))) * size_scale
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.45 if boss else (0.55 if role == "brute" else 0.42) * size_scale
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
	var wolf: Node = VARKAS_SCENE.instantiate()
	model.add_child(wolf)
	anim = _find(wolf, "AnimationPlayer") as AnimationPlayer
	skeleton = _find(wolf, "Skeleton3D") as Skeleton3D
	var mesh_instance := _find(wolf, "MeshInstance3D") as MeshInstance3D
	_fit_model(wolf, target_height)
	if anim:
		for name in ["Idle", "Walk", "Gallop", "Eating", "Idle_2", "Idle_2_HeadLow"]:
			if anim.has_animation(name):
				anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	_make_metals()
	if boss:
		_make_boss_materials(mesh_instance)
	else:
		_make_pack_materials(mesh_instance)
	_dress()
	if boss:
		_apply_boss_phase_appearance()
	_build_anim_tree(wolf)
	_build_pose()
	if skeleton:
		skeleton.skeleton_updated.connect(_follow_bones)


func _make_metals() -> void:
	iron = StandardMaterial3D.new()
	iron.albedo_color = Color("9aa2aa")
	iron.albedo_texture = IRON_PLATE
	iron.metallic = 0.72
	iron.roughness = 0.6
	iron.roughness_texture = load("res://assets/materials/polyhaven/rust_coarse_01/rust_coarse_01_Rough.jpg")
	iron.normal_enabled = true
	iron.normal_scale = 0.6
	iron.normal_texture = load("res://assets/materials/polyhaven/rust_coarse_01/rust_coarse_01_nor_gl.jpg")
	iron.emission_enabled = true
	iron.emission = Color("080c10")
	iron.emission_energy_multiplier = 0.08
	brass = StandardMaterial3D.new()
	brass.albedo_color = Color("e2b768")
	brass.albedo_texture = load("res://assets/materials/polyhaven/rust_coarse_01/rust_coarse_01_Diffuse.jpg")
	brass.metallic = 0.8
	brass.roughness = 0.5
	brass.roughness_texture = iron.roughness_texture
	brass.normal_enabled = true
	brass.normal_texture = iron.normal_texture
	brass.normal_scale = 0.28
	brass.emission_enabled = true
	brass.emission = Color("5a2a08")
	brass.emission_energy_multiplier = 0.12


func _make_pack_materials(mesh_instance: MeshInstance3D) -> void:
	# One rendered fur per animal: the shared swatches, tinted by role and
	# marked with its own war paint, so no two wolverines read as clones.
	var tint := Color(0.5, 0.45, 0.41)
	var paint := Color(0.6, 0.05, 0.03)
	var paint_amount := 0.65
	var flank_band := 0.5
	match role:
		"brute":
			tint = Color(0.36, 0.36, 0.4)
			paint_amount = 0.95
			flank_band = 0.25
		"stalker":
			tint = Color(0.42, 0.36, 0.3)
			paint_amount = 0.75
		_:
			tint = Color(0.55, 0.46, 0.36)
			paint_amount = 0.55
	if randf() < 0.4:
		paint = Color(0.78, 0.74, 0.62)
	tint = tint.lerp(Color(0.5, 0.5, 0.5), randf() * 0.25).lightened(randf_range(-0.06, 0.06))
	var seed_offset := randf() * 8.0
	eye_material = StandardMaterial3D.new()
	eye_material.albedo_color = Color("ffb340")
	eye_material.emission_enabled = true
	eye_material.emission = Color("6fb6ff")
	eye_material.emission_energy_multiplier = 2.4
	if mesh_instance == null:
		return
	for surface in mesh_instance.mesh.get_surface_count():
		var original := mesh_instance.mesh.surface_get_material(surface)
		var surface_name := original.resource_name if original else ""
		match surface_name:
			"Main", "Main_Light":
				var fur := ShaderMaterial.new()
				fur.shader = FUR_SHADER
				fur.set_shader_parameter("fur_a", FUR_A)
				fur.set_shader_parameter("fur_b", FUR_B)
				fur.set_shader_parameter("paint_mask", WARPAINT)
				fur.set_shader_parameter("base_tint", Vector3(tint.r, tint.g, tint.b) * 2.0)
				fur.set_shader_parameter("pale_tint", Vector3(tint.r, tint.g, tint.b) * 2.6)
				fur.set_shader_parameter("paint_color", Vector3(paint.r, paint.g, paint.b))
				fur.set_shader_parameter("paint_amount", paint_amount)
				fur.set_shader_parameter("paint_seed", seed_offset)
				fur.set_shader_parameter("flank_band", flank_band)
				fur.set_shader_parameter("light_amount", 0.55 if surface_name == "Main_Light" else 0.0)
				fur_materials.append(fur)
				mesh_instance.set_surface_override_material(surface, fur)
			"Eyes_Black":
				mesh_instance.set_surface_override_material(surface, eye_material)


## Varkas keeps his hand-tuned guard-fur material (a UV-mapped hero coat).
func _make_boss_materials(mesh_instance: MeshInstance3D) -> void:
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = Color("2b211d")
	body_material.roughness = 0.82
	# The hero has a full UV unwrap. This generated swatch already contains dark
	# pigment, so avoid applying a near-black procedural tint a second time.
	body_material.albedo_texture = preload("res://assets/materials/original/varkas_guard_fur.png")
	body_material.albedo_color = Color.WHITE
	body_material.uv1_scale = Vector3(4.0, 4.0, 1.0)
	body_material.roughness = 0.94
	body_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	body_light_material = body_material.duplicate() as StandardMaterial3D
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


func _fit_model(wolf: Node, target_height: float) -> void:
	if skeleton == null:
		return
	var low := INF
	var high := -INF
	var head_z := 0.0
	var tail_z := 0.0
	var skeleton_to_model: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform
	for i in skeleton.get_bone_count():
		var origin: Vector3 = skeleton_to_model * skeleton.get_bone_global_rest(i).origin
		low = minf(low, origin.y)
		high = maxf(high, origin.y)
		var bone_name := skeleton.get_bone_name(i)
		if bone_name == "Head":
			head_z = origin.z
		elif bone_name == "Tail1":
			tail_z = origin.z
	var height := maxf(0.01, high - low)
	var factor := target_height / height
	rig_scale = factor
	# Varkas is a mustelid, not a giant upright wolf. Preserve the animated rig,
	# but squash its vertical read and push mass through the chest and haunches.
	# Root-level hero details below are staged around the resulting 2.6 m crown.
	if boss:
		wolf.scale = Vector3(factor * 1.34, factor * 0.86, factor * 1.08)
	else:
		# Warpack wolverines: broad and low-slung rather than a leggy wolf.
		var bulk := 1.24 if role == "brute" else 1.14
		wolf.scale = Vector3(factor * bulk, factor * 0.86, factor * 1.0)
	rig_forward_scale = factor * (1.08 if boss else 1.0)
	# Godot's forward is -Z; turn the model round if its head points down +Z.
	if head_z > tail_z:
		wolf.rotation.y = PI
		_model_yaw_flip = true
	wolf.position.y = -low * factor * 0.86 + 0.02 - (0.0 if boss else 0.3 * factor)


## Bulks the forequarters and head into a wolverine's build and shortens the tail.
func _build_pose() -> void:
	if skeleton == null:
		return
	pose = EnemyPose.new()
	pose.name = "EnemyPose"
	if not boss:
		var chest := 1.26 if role == "brute" else 1.16
		var stub := 0.8
		pose.bulk = {
			"Torso3": Vector3(chest, 1.0, chest * 0.96),
			"Torso": Vector3(1.06, 1.0, 1.06),
			"Neck1": Vector3(1.15, 1.0, 1.15),
			# The wolf skull collapses to a point: the generated wolverine head
			# rides the bone rigidly in its place (see _dress).
			"Head": Vector3.ONE * 0.02,
			"FrontUpperLeg.L": Vector3(1.12, stub, 1.12),
			"FrontUpperLeg.R": Vector3(1.12, stub, 1.12),
			"BackLeg.L": Vector3(1.1, stub + 0.02, 1.1),
			"BackLeg.R": Vector3(1.1, stub + 0.02, 1.1),
			"Tail1": Vector3(1.3, 0.62, 1.3),
		}
	skeleton.add_child(pose)
	pose.setup(skeleton)


func _make_head_lights() -> void:
	var head := _attach("Head")
	if head == null:
		return
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color("6fb6ff")
	eye_light.light_energy = 0.06 if boss else 0.35
	eye_light.omni_range = 1.6
	eye_light.position = Vector3(0.0, 0.25 * rig_scale, 0.1)
	head.add_child(eye_light)
	if boss:
		return
	# A shadowless spotlight from the brow reads as a sweeping torch when the
	# wolverine hunts. Kept off while it patrols, so the ravine stays dark.
	eye_beam = SpotLight3D.new()
	eye_beam.name = "EyeBeam"
	eye_beam.rotation_degrees.x = 90.0
	eye_beam.position = Vector3(0.0, 0.35 * rig_scale, 0.08)
	eye_beam.spot_angle = 26.0
	eye_beam.spot_range = 15.0
	eye_beam.spot_attenuation = 1.3
	eye_beam.light_energy = 1.3
	eye_beam.shadow_enabled = false
	eye_beam.light_color = Color("ffb03a")
	eye_beam.visible = false
	head.add_child(eye_beam)


func _dress() -> void:
	if skeleton == null:
		return
	_make_head_lights()
	if boss:
		_dress_boss()
		return
	var gear_size := rig_scale / 0.47
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color("2a1b12")
	leather.roughness = 0.85
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("4a2f1c")
	wood.roughness = 0.7
	gear_materials = {"Iron": iron, "Brass": brass, "Wood": wood, "Leather": leather}
	# The generated snarling head (spiked collar included) replaces the wolf skull.
	var head_size := (1.0 if role != "brute" else 1.22) * gear_size
	var head_mesh := _mount("WolverineHead", "Head", head_offset, 0.62 * head_size, GEAR_FRAME_HEAD, HEAD_SCENE, true) as MeshInstance3D
	if head_mesh:
		var source := head_mesh.mesh.surface_get_material(0) as StandardMaterial3D
		head_material = ShaderMaterial.new()
		head_material.shader = HEAD_SHADER
		head_material.set_shader_parameter("albedo_texture", source.albedo_texture if source else null)
		head_mesh.set_surface_override_material(0, head_material)
		fur_materials.append(head_material)
	_mount_neck(gear_size)
	# The stolen bell hangs from the collar of wolverines that carry a name.
	if bell_index >= 0:
		collar_bell = _mount("Bell", "Neck3", Vector3(0.0, 0.0, -0.3), 0.85 * gear_size, GEAR_FRAME)
	var pauldron_size := (0.8 if role != "brute" else 1.1) * gear_size
	var shoulder := 0.34 * (1.2 if role == "brute" else 1.0)
	_mount("Pauldron_R", "Torso3", Vector3(shoulder, 0.0, 0.22), pauldron_size, GEAR_FRAME)
	if role != "stalker" or randf() < 0.5:
		_mount("Pauldron_L", "Torso3", Vector3(-shoulder, 0.0, 0.22), pauldron_size, GEAR_FRAME)
	var plates := 3 if role == "brute" else (1 if role == "stalker" else 2)
	for index in plates:
		_mount("SpinePlate", ["Torso2", "Torso", "Back"][index], Vector3(0.0, 0.0, 0.2), 0.85 * gear_size, GEAR_FRAME)
	if role == "rifleman":
		_mount_rifle(gear_size)


## Maps gear authored in Godot axes (up Y, forward -Z) onto a bone frame (up Z,
## forward Y, lateral X).
const GEAR_FRAME := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, -1.0, 0.0))
## The generated head is authored nose toward -Z and pivoted at the skull base;
## the same mapping carries it onto the Head bone (nose along bone +Y).
const GEAR_FRAME_HEAD := GEAR_FRAME
## Where the head mesh sits on the Head bone, in rig units (lateral, forward, up).
var head_offset := Vector3(0.0, -0.1, -0.32)
var gear_materials := {}
var _riders_by_bone := {}


## Picks one named piece out of the shared gear scene and mounts it on a bone.
func _mount(piece_name: String, bone_name: String, offset: Vector3, piece_scale: float, frame: Basis, scene: PackedScene = GEAR_SCENE, keep_materials := false) -> Node3D:
	var rider := _attach(bone_name)
	if rider == null:
		return null
	var gear := scene.instantiate()
	var piece := gear.find_child(piece_name, true, false) as MeshInstance3D
	if piece == null:
		gear.queue_free()
		return null
	piece.get_parent().remove_child(piece)
	piece.owner = null
	gear.queue_free()
	if not keep_materials:
		for surface in piece.mesh.get_surface_count():
			var source := piece.mesh.surface_get_material(surface)
			var surface_name := source.resource_name if source else "Iron"
			piece.set_surface_override_material(surface, gear_materials.get(surface_name, iron))
	piece.transform = Transform3D(frame.scaled(Vector3.ONE * piece_scale), offset * rig_scale)
	rider.add_child(piece)
	return piece


## The collapsed wolf skull took the neck's fur with it: a furred mantle bridges
## the shoulders to the generated head so the head never floats off the body,
## even when a flinch throws it back.
func _mount_neck(gear_size: float) -> void:
	if fur_materials.is_empty():
		return
	var rider := _attach("Neck2")
	if rider == null:
		return
	var mantle := MeshInstance3D.new()
	mantle.name = "NeckMantle"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.115 * gear_size * (1.15 if role == "brute" else 1.0)
	mesh.height = 0.5 * gear_size
	mesh.radial_segments = 16
	mesh.rings = 6
	mantle.mesh = mesh
	var fur := fur_materials[0].duplicate() as ShaderMaterial
	fur.set_shader_parameter("position_scale", 4.0)
	fur.set_shader_parameter("paint_amount", 0.0)
	mantle.material_override = fur
	mantle.position = Vector3(0.0, 0.3, -0.02) * rig_scale
	fur_materials.append(fur)
	rider.add_child(mantle)


func _mount_rifle(gear_size: float) -> void:
	rifle_pivot = Node3D.new()
	rifle_pivot.name = "RifleHarness"
	add_child(rifle_pivot)
	rifle_pivot.top_level = true
	var gear := GEAR_SCENE.instantiate()
	var rifle := gear.find_child("Rifle", true, false) as MeshInstance3D
	if rifle == null:
		gear.queue_free()
		return
	rifle.get_parent().remove_child(rifle)
	rifle.owner = null
	gear.queue_free()
	for surface in rifle.mesh.get_surface_count():
		var source := rifle.mesh.surface_get_material(surface)
		rifle.set_surface_override_material(surface, gear_materials.get(source.resource_name if source else "Iron", iron))
	rifle.scale = Vector3.ONE * 0.85 * gear_size
	rifle_pivot.add_child(rifle)
	rifle_muzzle = Marker3D.new()
	rifle_muzzle.name = "Muzzle"
	rifle_muzzle.position = Vector3(0.0, 0.02, -1.0)
	rifle.add_child(rifle_muzzle)
	rifle_aim = facing()
	_follow_rifle()


func _attach(bone_name: String) -> Node3D:
	if _riders_by_bone.has(bone_name):
		return _riders_by_bone[bone_name]
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return null
	var rider := Node3D.new()
	rider.name = "Rider_" + bone_name
	add_child(rider)
	rider.top_level = true
	riders.append({"node": rider, "bone": index})
	_riders_by_bone[bone_name] = rider
	_follow_bones()
	return rider


func _follow_bones() -> void:
	if skeleton == null or not skeleton.is_inside_tree():
		return
	for rider in riders:
		var bone_pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(rider.bone)
		rider.node.global_transform = Transform3D(bone_pose.basis.orthonormalized(), bone_pose.origin)
	_follow_rifle()


## The rifle rides a swivel harness on the back: it rests pointing ahead and
## slews onto the goat when the wolverine aims, kicking back on each shot.
func _follow_rifle() -> void:
	if not is_instance_valid(rifle_pivot) or skeleton == null:
		return
	var back := skeleton.find_bone("Back")
	if back < 0:
		return
	var anchor: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(back)).origin
	anchor += Vector3.UP * 0.2 * rig_scale / 0.47 - facing() * 0.05
	var resting := (facing() + Vector3.UP * 0.1).normalized()
	var wanted := rifle_aim if combat == Combat.AIM else resting
	rifle_smoothed = rifle_smoothed.slerp(wanted, 0.22).normalized() if rifle_smoothed != Vector3.ZERO else wanted
	if rifle_recoil > 0.0:
		rifle_recoil = maxf(0.0, rifle_recoil - 0.08)
	var basis := Basis.looking_at(rifle_smoothed, Vector3.UP)
	rifle_pivot.global_transform = Transform3D(basis, anchor - rifle_smoothed * 0.14 * rifle_recoil)


var rifle_smoothed := Vector3.ZERO
var rifle_recoil := 0.0


func _find(node: Node, type_name: String) -> Node:
	var stack := [node]
	while stack:
		var current: Node = stack.pop_back()
		if current.get_class() == type_name:
			return current
		stack.append_array(current.get_children())
	return null


# --- Animation -----------------------------------------------------------------

## Locomotion (idle variants, walk-to-gallop blend space) with one-shot layers
## for the strike and for upper-body hit reactions, all on the source clips.
func _build_anim_tree(root_node: Node) -> void:
	if anim == null:
		return
	var graph := AnimationNodeBlendTree.new()
	var idle_pick := AnimationNodeTransition.new()
	idle_pick.input_count = IDLE_VARIANTS.size()
	idle_pick.xfade_time = 0.5
	for index in IDLE_VARIANTS.size():
		idle_pick.set_input_name(index, IDLE_VARIANTS[index])
		var idle_clip := AnimationNodeAnimation.new()
		idle_clip.animation = IDLE_VARIANTS[index]
		graph.add_node("idle_%d" % index, idle_clip)
	graph.add_node("idle_pick", idle_pick)
	for index in IDLE_VARIANTS.size():
		graph.connect_node("idle_pick", index, "idle_%d" % index)
	var walk_clip := AnimationNodeAnimation.new()
	walk_clip.animation = "Walk"
	var gallop_clip := AnimationNodeAnimation.new()
	gallop_clip.animation = "Gallop"
	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.add_blend_point(walk_clip, 0.0, -1, "walk")
	locomotion.add_blend_point(gallop_clip, 1.0, -1, "gallop")
	graph.add_node("loco_space", locomotion)
	graph.add_node("loco_ts", AnimationNodeTimeScale.new())
	graph.connect_node("loco_ts", 0, "loco_space")
	graph.add_node("loco_mix", AnimationNodeBlend2.new())
	graph.connect_node("loco_mix", 0, "idle_pick")
	graph.connect_node("loco_mix", 1, "loco_ts")
	var attack_clip := AnimationNodeAnimation.new()
	attack_clip.animation = "Attack"
	graph.add_node("attack_anim", attack_clip)
	graph.add_node("attack_ts", AnimationNodeTimeScale.new())
	graph.connect_node("attack_ts", 0, "attack_anim")
	var attack_shot := AnimationNodeOneShot.new()
	attack_shot.fadein_time = 0.08
	attack_shot.fadeout_time = 0.3
	graph.add_node("attack_shot", attack_shot)
	graph.connect_node("attack_shot", 0, "loco_mix")
	graph.connect_node("attack_shot", 1, "attack_ts")
	for side in ["left", "right"]:
		var hit_clip := AnimationNodeAnimation.new()
		hit_clip.animation = "Idle_HitReact_Left" if side == "left" else "Idle_HitReact_Right"
		graph.add_node("hit_%s" % side, hit_clip)
	var hit_pick := AnimationNodeTransition.new()
	hit_pick.input_count = 2
	hit_pick.set_input_name(0, "left")
	hit_pick.set_input_name(1, "right")
	hit_pick.xfade_time = 0.0
	graph.add_node("hit_pick", hit_pick)
	graph.connect_node("hit_pick", 0, "hit_left")
	graph.connect_node("hit_pick", 1, "hit_right")
	var hit_shot := AnimationNodeOneShot.new()
	hit_shot.fadein_time = 0.05
	hit_shot.fadeout_time = 0.22
	# The flinch only takes the spine, neck and head: the legs keep their gait.
	hit_shot.filter_enabled = true
	var reference := anim.get_animation("Idle")
	if reference and reference.get_track_count() > 0:
		var prefix := str(reference.track_get_path(0)).get_slice(":", 0)
		for bone in ["Torso", "Torso2", "Torso3", "Neck1", "Neck2", "Neck3", "Head", "Ear1.L", "Ear2.L", "Ear3.L", "Ear4.L", "Ear1.R", "Ear2.R", "Ear3.R", "Ear4.R", "Back"]:
			hit_shot.set_filter_path(NodePath("%s:%s" % [prefix, bone]), true)
	graph.add_node("hit_shot", hit_shot)
	graph.connect_node("hit_shot", 0, "attack_shot")
	graph.connect_node("hit_shot", 1, "hit_pick")
	graph.connect_node("output", 0, "hit_shot")
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimTree"
	root_node.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim)
	anim_tree.tree_root = graph
	anim_tree.active = true
	anim_tree.set("parameters/attack_ts/scale", 1.0)


func _play(name: String, _oneshot := false) -> void:
	match name:
		"Idle":
			_idle_variant = "Idle"
		"Attack":
			_play_attack(0.0)
		"Idle_HitReact_Left":
			_react(true)
		"Idle_HitReact_Right":
			_react(false)


## Starts the strike clip. With a wind-up length, the clip's crouch (its first
## quarter second) is stretched over it and holds until `_release_attack`.
func _play_attack(windup := 0.0) -> void:
	if anim_tree == null or dead:
		return
	anim_tree.set("parameters/attack_ts/scale", ATTACK_CROUCH_TIME / windup if windup > 0.0 else 1.0)
	anim_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _release_attack() -> void:
	if anim_tree:
		anim_tree.set("parameters/attack_ts/scale", 1.0)


func _react(left: bool) -> void:
	if anim_tree == null or dead:
		return
	anim_tree.set("parameters/hit_pick/transition_request", "left" if left else "right")
	anim_tree.set("parameters/hit_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


var _applied_idle := "Idle"
var _eye_flash_color := Color.WHITE
var _eye_flash_time := 0.0


func _flash_eyes(color: Color, seconds: float) -> void:
	_eye_flash_color = color
	_eye_flash_time = seconds


func _animate(delta: float) -> void:
	if pose:
		pose.look_target = _head_target
		pose.look_weight = lerpf(pose.look_weight, _head_weight, minf(1.0, delta * 6.0))
	_update_eyes(delta)
	if anim_tree == null or not anim_tree.active:
		return
	var walk_natural := WALK_RIG_SPEED * rig_forward_scale
	var gallop_natural := GALLOP_RIG_SPEED * rig_forward_scale
	var planar := _planar_speed
	var turning := planar < 0.6 and absf(_yaw_rate) > 0.7
	var move_amount := clampf(planar / 0.35, 0.0, 1.0)
	var gallop_mix := clampf(inverse_lerp(walk_natural * 1.3, gallop_natural * 0.9, planar), 0.0, 1.0)
	var clip_scale := 1.0
	if turning:
		# Pivot in place: walk the feet at a pace matching the turn.
		move_amount = 0.9
		clip_scale = clampf(absf(_yaw_rate) / 3.4, 0.35, 1.1)
	else:
		# Foot-slide fix: play the gait at exactly the pace the body covers ground.
		var natural := lerpf(walk_natural, gallop_natural, gallop_mix)
		clip_scale = clampf(planar / maxf(natural, 0.01), 0.3, 2.4)
	anim_tree.set("parameters/loco_mix/blend_amount", move_amount)
	anim_tree.set("parameters/loco_space/blend_position", gallop_mix)
	anim_tree.set("parameters/loco_ts/scale", clip_scale)
	if _applied_idle != _idle_variant:
		_applied_idle = _idle_variant
		anim_tree.set("parameters/idle_pick/transition_request", _idle_variant)
	if boss or model == null:
		_prev_planar = planar
		return
	# Procedural lean: nose-down into acceleration, roll into turns and strafes.
	var accel := (planar - _prev_planar) / maxf(delta, 0.0001)
	_prev_planar = planar
	var right := global_transform.basis.x
	var lateral := velocity.dot(right)
	var pitch_goal := clampf(-accel * 0.012, -0.1, 0.1)
	var roll_goal := clampf(-_yaw_rate * planar * 0.018 - lateral * 0.03, -0.18, 0.18)
	model.rotation.x = lerpf(model.rotation.x, pitch_goal, minf(1.0, delta * 7.0))
	model.rotation.z = lerpf(model.rotation.z, roll_goal, minf(1.0, delta * 7.0))
	if is_instance_valid(collar_bell):
		collar_bell.rotation.x = sin(phase * 9.0) * 0.28 * clampf(planar / 3.0, 0.1, 1.0)


func _update_eyes(delta: float) -> void:
	# Eyes tell the goat what the wolverine knows: cold blue, amber, then red.
	var color := Color("6fb6ff")
	if detection >= Stealth.ALERT:
		color = Color("ff2a1a")
	elif detection >= Stealth.SUSPICIOUS:
		color = Color("ffb03a")
	if _eye_flash_time > 0.0:
		_eye_flash_time -= delta
		color = _eye_flash_color
	if eye_material:
		eye_material.emission = eye_material.emission.lerp(color, minf(1.0, delta * 6.0))
		if eye_light:
			eye_light.light_color = eye_material.emission
			eye_light.light_energy = 0.35 + detection * 0.6
	if head_material and eye_material:
		var shown := eye_material.emission
		head_material.set_shader_parameter("eye_color", Vector3(shown.r, shown.g, shown.b))
		head_material.set_shader_parameter("eye_energy", 1.6 + detection * 2.4)
	if is_instance_valid(eye_beam):
		var hunting := state == State.SUSPICIOUS or state == State.SEARCH or (state == State.ALERT and combat != Combat.AIM)
		var near := is_instance_valid(target) and global_position.distance_to(target.global_position) < 42.0
		eye_beam.visible = hunting and near
		eye_beam.light_color = eye_material.emission if eye_material else Color("ffb03a")


func _dress_boss() -> void:
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
	boss_bell_material = brass.duplicate() as StandardMaterial3D
	orin_mesh.material = boss_bell_material
	orin_bell.mesh = orin_mesh
	orin_bell.position = Vector3(0.0, 1.12, -1.7)
	orin_bell.rotation_degrees.x = -10.0
	hero_parent.add_child(orin_bell)
	boss_bell = orin_bell
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
