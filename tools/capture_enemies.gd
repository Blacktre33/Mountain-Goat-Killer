extends SceneTree
## Rendered proof of the warpack's behaviour: a patrolling wolverine, a brute's
## charge, a stalker's telegraphed strike, a rifleman aiming and firing, deaths,
## and Varkas' three phases. Run in a real window:
##   Godot --path . --resolution 1280x720 --script res://tools/capture_enemies.gd -- patrol strike rifle death brute boss
## With no scenario names every scenario runs. Frames go to art_direction/audit/.

const OUT := "res://art_direction/audit/"

var mission: Node3D
var player: GoatPlayer
var cam: Camera3D
var cam_target: Node3D
var cam_offset := Vector3.ZERO
var cam_look := 0.6
var player_view := false
var wanted_args: Array[String] = []


func _init() -> void:
	call_deferred("run")


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("saved ", name)


## A free camera that keeps `enemy` framed from an offset in its own frame
## (x right, z behind), so geometry between the goat and the animal never
## hides the shot. The goat stays wherever the scenario put it.
func _cam_on(enemy: Node3D, offset: Vector3, look_height := 0.6) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 50.0
		root.add_child(cam)
	cam.make_current()
	player_view = false
	cam_target = enemy
	cam_offset = offset
	cam_look = look_height
	_cam_update()


## Frames the shot through the goat's own camera instead (used in the boss
## courtyard, where a free camera ends up inside pillars).
func _player_view(enemy: Node3D, look_height: float) -> void:
	player_view = true
	cam_target = enemy
	cam_look = look_height
	player.camera.make_current()
	_cam_update()


func _cam_update() -> void:
	if player_view and is_instance_valid(cam_target):
		var direction := cam_target.global_position + Vector3(0.0, cam_look, 0.0) - player.aim_origin()
		player.rotation.y = atan2(-direction.x, -direction.z)
		player.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		player.head.rotation.x = player.pitch
		return
	if cam == null or not is_instance_valid(cam_target):
		return
	var at := cam_target.global_position + cam_target.global_transform.basis * cam_offset
	at.y = maxf(at.y, WorldBuilder.height_at(at.x, at.z) + 0.25)
	cam.global_position = at
	cam.look_at(cam_target.global_position + Vector3(0.0, cam_look, 0.0), Vector3.UP)


func _frame(enemy: WolverineEnemy, distance: float, bearing: float, height := 1.3, look_offset := 0.6) -> void:
	_cam_on(enemy, Vector3(sin(bearing) * distance, height, -cos(bearing) * distance), look_offset)


func _frame_follow(_enemy: WolverineEnemy, _distance: float, _bearing: float) -> void:
	_cam_update()


func _isolate(enemy: WolverineEnemy) -> void:
	for other in mission.enemies:
		if is_instance_valid(other) and other != enemy:
			other.set_physics_process(false)
	enemy.set_physics_process(true)


func _quiet_hud() -> void:
	mission.chapter_title.visible = false
	mission.chapter_line.visible = false


func run() -> void:
	seed(21)
	var wanted: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		wanted.append(argument)
	wanted_args = wanted
	var everything := wanted.is_empty()
	mission = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	player = mission.player
	player.set_physics_process(false)
	_quiet_hud()
	mission._set_hud_visible(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	# Give the navigation mesh a moment to bake.
	mission.enemies[0].set_physics_process(true)
	await _frames(30)
	mission.enemies[0].set_physics_process(false)

	if everything or "look" in wanted:
		await _scenario_look()
	if everything or "patrol" in wanted:
		await _scenario_patrol()
	if everything or "hit" in wanted:
		await _scenario_hit()
	if everything or "search" in wanted:
		await _scenario_search()
	if everything or "strike" in wanted:
		await _scenario_strike()
	if everything or "brute" in wanted:
		await _scenario_brute()
	if everything or "rifle" in wanted:
		await _scenario_rifle()
	if everything or "death" in wanted:
		await _scenario_death()
	if everything or "boss" in wanted:
		await _scenario_boss()
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	quit()


func _scenario_look() -> void:
	for pick in [[3, "stalker"]] if "one" in wanted_args else [[3, "stalker"], [1, "rifleman"], [2, "brute"]]:
		var enemy: WolverineEnemy = mission.enemies[pick[0]]
		enemy.global_position = Vector3(2.0 + pick[0] * 0.0, WorldBuilder.height_at(2.0, 24.0) + 0.3, 24.0)
		for other in mission.enemies:
			if other != enemy:
				other.global_position = Vector3(-20.0, 10.0, 60.0)
		enemy.rotation.y = 0.0
		enemy.patrol = [enemy.global_position]
		_isolate(enemy)
		enemy.wait_for = 99.0
		await _frames(40)
		for view in [["side", PI * 0.5], ["front", 0.55], ["three", 2.3]]:
			_frame(enemy, 2.6, view[1], 0.9, 0.45)
			enemy.set_physics_process(false)
			await _frames(3)
			await _shot("en_look_%s_%s" % [pick[1], view[0]])
		enemy.set_physics_process(false)


func _scenario_patrol() -> void:
	var enemy: WolverineEnemy = mission.enemies[0]
	for other in mission.enemies:
		if other != enemy:
			other.global_position = Vector3(-20.0, 10.0, 60.0)
	var here := Vector3(2.0, WorldBuilder.height_at(2.0, 22.0) + 0.3, 22.0)
	enemy.global_position = here
	enemy.patrol = [here, Vector3(-3.0, WorldBuilder.height_at(-3.0, 17.0), 17.0), Vector3(4.0, WorldBuilder.height_at(4.0, 15.0), 15.0)]
	enemy.patrol_index = 0
	enemy.wait_for = 0.0
	_isolate(enemy)
	player.global_position = Vector3(30.0, WorldBuilder.height_at(20.0, 40.0) + 0.95, 40.0)
	_frame(enemy, 4.2, 2.6, 1.0, 0.5)
	for index in 6:
		for _tick in 45:
			await physics_frame
			enemy.detection = 0.0
			enemy.sense_rate = 0.0
			_cam_update()
		await _shot("en_patrol_%d" % index)


func _scenario_hit() -> void:
	var enemy: WolverineEnemy = mission.enemies[0]
	for other in mission.enemies:
		if other != enemy:
			other.global_position = Vector3(-20.0, 10.0, 60.0)
	var here := Vector3(2.0, WorldBuilder.height_at(2.0, 22.0) + 0.3, 22.0)
	enemy.global_position = here
	enemy.rotation.y = 0.0
	enemy.patrol = [here]
	_isolate(enemy)
	player.global_position = here + Vector3(0.0, 0.6, 9.0)
	_frame(enemy, 3.2, 1.0, 0.7, 0.4)
	await _frames(30)
	enemy.take_damage(20, 0.22, true)
	for index in 4:
		await _frames(5)
		_cam_update()
		await _shot("en_hit_%d" % index)


func _scenario_search() -> void:
	var enemy: WolverineEnemy = mission.enemies[0]
	for other in mission.enemies:
		if other != enemy:
			other.global_position = Vector3(-20.0, 10.0, 60.0)
	var here := Vector3(2.0, WorldBuilder.height_at(2.0, 22.0) + 0.3, 22.0)
	enemy.global_position = here
	enemy.rotation.y = 0.0
	enemy.patrol = [here]
	_isolate(enemy)
	player.global_position = Vector3(30.0, WorldBuilder.height_at(20.0, 40.0) + 0.95, 40.0)
	_frame(enemy, 5.0, 2.7, 1.2, 0.5)
	enemy.state = WolverineEnemy.State.SEARCH
	enemy.last_known = here + Vector3(0.0, 0.0, -3.0)
	enemy.wait_for = 0.0
	enemy.detection = 0.5
	for index in 3:
		for _tick in 50:
			await physics_frame
			enemy.detection = 0.5
			_cam_update()
		await _shot("en_search_%d" % index)


func _scenario_strike() -> void:
	var enemy: WolverineEnemy = mission.enemies[3]
	enemy.global_position = Vector3(3.0, WorldBuilder.height_at(3.0, 9.0) + 0.4, 9.0)
	_isolate(enemy)
	player.global_position = enemy.global_position + Vector3(0.0, 0.6, 4.6)
	_frame(enemy, 2.9, 1.2, 0.7, 0.4)
	enemy.alert_to(player.global_position)
	var captured := 0
	var last := -1
	for tick in 420:
		await physics_frame
		_frame_follow(enemy, 4.6, 0.25)
		if enemy.combat == WolverineEnemy.Combat.WINDUP and captured < 2 and enemy.combat_time > 0.18 * (captured + 1):
			await _shot("en_strike_windup_%d" % captured)
			captured += 1
		elif enemy.combat == WolverineEnemy.Combat.STRIKE and last != 1 and enemy.combat_time > 0.08:
			last = 1
			await _shot("en_strike_impact")
		elif enemy.combat == WolverineEnemy.Combat.RECOVER and last != 2 and enemy.combat_time > 0.3:
			last = 2
			await _shot("en_strike_recover")
			break
	print("strike scenario combat=", enemy.combat, " player health=", player.health)


func _scenario_brute() -> void:
	var enemy: WolverineEnemy = mission.enemies[2]
	enemy.global_position = Vector3(2.0, WorldBuilder.height_at(2.0, 26.0) + 0.4, 26.0)
	enemy.rotation.y = 0.0
	for other in mission.enemies:
		if other != enemy:
			other.global_position = Vector3(-20.0, 10.0, 60.0)
	_isolate(enemy)
	player.global_position = Vector3(2.0, WorldBuilder.height_at(2.0, 12.0) + 0.95, 12.0)
	player.health = 100
	_frame(enemy, 5.0, 1.1, 1.0, 0.6)
	enemy.alert_to(player.global_position)
	enemy.cooldown = 0.0
	var seen := {}
	for tick in 600:
		await physics_frame
		_frame_follow(enemy, 8.0, 0.0)
		player.health = 100
		player.global_position = Vector3(2.0, WorldBuilder.height_at(2.0, 12.0) + 0.95, 12.0)
		if enemy.combat == WolverineEnemy.Combat.WINDUP and not seen.has("w") and enemy.combat_time > 0.6:
			seen["w"] = true
			await _shot("en_brute_windup")
		elif enemy.combat == WolverineEnemy.Combat.CHARGE and not seen.has("c") and enemy.combat_time > 0.35:
			seen["c"] = true
			await _shot("en_brute_charge")
		elif enemy.combat == WolverineEnemy.Combat.STAGGERED and not seen.has("s") and enemy.combat_time > 0.25:
			seen["s"] = true
			await _shot("en_brute_wall")
		elif enemy.combat == WolverineEnemy.Combat.RECOVER and not seen.has("r") and enemy.combat_time > 0.4:
			seen["r"] = true
			await _shot("en_brute_recover")
		if seen.size() >= 3:
			break
	print("brute scenario ", seen.keys())


func _scenario_rifle() -> void:
	var enemy: WolverineEnemy = mission.enemies[1]
	enemy.global_position = Vector3(6.0, WorldBuilder.height_at(6.0, -2.0) + 0.4, -2.0)
	_isolate(enemy)
	player.global_position = Vector3(2.0, WorldBuilder.height_at(2.0, 12.0) + 0.95, 12.0)
	_frame(enemy, 3.4, 0.9, 0.8, 0.5)
	enemy.alert_to(player.global_position)
	var seen := {}
	for tick in 700:
		await physics_frame
		_frame_follow(enemy, 12.0, 0.0)
		player.health = 100
		if enemy.combat == WolverineEnemy.Combat.AIM and not seen.has("a") and enemy.combat_time > enemy.aim_total * 0.8:
			seen["a"] = true
			await _shot("en_rifle_aim")
		if enemy.rounds < 4 and not seen.has("f"):
			seen["f"] = true
			await _shot("en_rifle_fire")
			await _frames(4)
			await _shot("en_rifle_fire_2")
		if seen.size() >= 2:
			break
	print("rifle scenario ", seen.keys(), " rounds=", enemy.rounds)


func _scenario_death() -> void:
	var enemy: WolverineEnemy = mission.enemies[3]
	enemy.global_position = Vector3(-3.0, WorldBuilder.height_at(-3.0, 8.0) + 0.4, 8.0)
	enemy.state = WolverineEnemy.State.PATROL
	enemy.calm()
	enemy.global_position = Vector3(-3.0, WorldBuilder.height_at(-3.0, 8.0) + 0.4, 8.0)
	_isolate(enemy)
	player.global_position = enemy.global_position + Vector3(0.0, 0.6, 6.0)
	_frame(enemy, 3.0, 1.0, 0.8, 0.4)
	await _frames(20)
	enemy.take_damage(999, 0.5)
	for index in 4:
		await _frames(12)
		_frame_follow(enemy, 4.0, 0.9)
		await _shot("en_death_%d" % index)


func _scenario_boss() -> void:
	var boss: WolverineEnemy = mission.boss
	WorldBuilder.set_biome(mission.world, "iron_crown")
	for enemy in mission.enemies:
		if is_instance_valid(enemy) and enemy != boss:
			enemy.set_physics_process(false)
	boss.set_physics_process(true)
	boss.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, WorldBuilder.COURTYARD_Z - 4.5) + 0.3, WorldBuilder.COURTYARD_Z - 4.5)
	boss.rotation.y = 0.0
	player.global_position = boss.global_position + Vector3(2.5, 0.95, 12.0)
	mission.boss_awake = true
	boss.wake()
	_quiet_hud()
	_player_view(boss, 1.6)
	boss.cooldown = 99.0
	boss.boss_ability_cooldown = 99.0
	await _frames(20)
	_frame_follow(boss, 11.0, 0.0)
	await _shot("en_boss_phase1")
	# Phase 1 -> 2 transition beat.
	boss.take_damage(int(boss.max_health * 0.4))
	_quiet_hud()
	for step in 5:
		await _frames(18)
		_frame_follow(boss, 11.0, 0.0)
		await _shot("en_boss_transition_%d" % step)
	boss.boss_transition_lock = 0.0
	boss.cooldown = 0.0
	boss.boss_ability_cooldown = 0.0
	boss.boss_recovery_for = 0.0
	# Bellquake wind-up (rear-up) and its slam.
	boss._begin_bellquake()
	for step in 3:
		await _frames(24)
		_frame_follow(boss, 11.0, 0.0)
		await _shot("en_boss_bellquake_%d" % step)
	await _frames(14)
	await _shot("en_boss_slam")
	# Phase 3 with the red horn.
	boss.boss_recovery_for = 0.0
	boss.take_damage(int(boss.max_health * 0.4))
	_quiet_hud()
	for step in 4:
		await _frames(22)
		_frame_follow(boss, 11.0, 0.0)
		await _shot("en_boss_phase3_%d" % step)
	boss.boss_transition_lock = 0.0
	boss.boss_recovery_for = 0.0
	boss.boss_ability_cooldown = 0.0
	boss.state = WolverineEnemy.State.ALERT
	await _frames(4)
	boss.boss_ability_cooldown = 0.0
	boss.has_los = true
	await _frames(20)
	await _shot("en_boss_charge_windup")
	# Broken for execution.
	boss.boss_transition_lock = 0.0
	boss.take_damage(boss.max_health * 2)
	_frame_follow(boss, 8.0, 0.0)
	await _frames(40)
	_quiet_hud()
	await _shot("en_boss_broken")
