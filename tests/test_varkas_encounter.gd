extends SceneTree
## Exercise the actual courtyard, CharacterBody motion and boss attack timeline
## at ordinary health. Optional rendered proof: -- --capture-varkas-combat

var mission: Node3D
var player: GoatPlayer
var boss: WolverineEnemy
var failures: Array[String] = []
const STEP := 1.0 / 60.0


func _init() -> void:
	call_deferred("run_test")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func step(sideways := 0.0, elevation := 0.0) -> void:
	await physics_frame
	if sideways != 0.0:
		player.move_and_collide(Vector3(sideways * STEP, 0.0, 0.0))
	player.global_position.y = WorldBuilder.height_at(player.global_position.x, player.global_position.z) + 0.95 + elevation
	boss._physics_process(STEP)
	mission._update_boss_hud()
	mission._update_prompt()
	var direction := boss.global_position - player.global_position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation.x = -0.04


func capture(name: String) -> void:
	if "--capture-varkas-combat" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var destination := "res://art_direction/iron_crown/iron-crown-varkas-%s.png" % name
	var result := root.get_texture().get_image().save_png(destination)
	check(result == OK, "Could not save combat proof: " + name)
	print("Saved combat proof: ", name)


func run_test() -> void:
	seed(784)
	mission = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	# Drive physics at fixed steps while keeping scene signals, collision,
	# materials and HUD intact. Other enemies are excluded from this dodge test.
	mission.set_process(false)
	player = mission.player
	boss = mission.boss
	player.set_physics_process(false)
	player.set_process(false)
	mission.bells = Story.IRON_GATE_REQUIRED
	mission.bell_rung = true
	player.global_position = boss.global_position + Vector3(0.0, 0.95, 10.0)
	mission._update_gate()
	WorldBuilder.set_biome(mission.world, "iron_crown")
	mission.current_biome = "iron_crown"
	mission.biome_label.text = "THE IRON CROWN  //  RED HORN"
	mission.objective_label.text = "OBJECTIVE  //  BREAK VARKAS  //  TAKE BACK ORIN'S BELL"
	mission.bells_label.text = "BELLS RECOVERED  //  8 / 9"
	boss.take_damage(boss.max_health)
	boss.boss_transition_lock = 0.0
	boss.take_damage(boss.max_health)
	boss.boss_transition_lock = 0.0
	boss.stagger = 0.0
	boss.boss_ability_cooldown = 0.0
	boss.rotation.y = PI
	for enemy in mission.enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
	player.health = 100
	mission._on_health_changed(100)
	mission.chapter_title.visible = false
	mission.chapter_line.visible = false
	await physics_frame
	boss.has_los = true
	await step()
	check(boss.boss_windup_for > 0.0 and boss.boss_charge_for == 0.0, "Courtyard charge has no stationary warning")
	await capture("charge-warning")
	var locked_direction := boss.boss_attack_direction
	var starting_x := player.global_position.x
	for frame in 30:
		await step(GoatPlayer.WALK_SPEED)
	check(player.global_position.x - starting_x > 2.5, "The courtyard blocks a walking sidestep out of the charge lane")
	check(boss.boss_attack_direction.is_equal_approx(locked_direction), "Courtyard charge tracks the dodging player")
	for frame in 130:
		await step()
	check(player.health == 100, "A walking sidestep was damaged by the committed charge: health=%d" % player.health)
	check(boss.boss_recovery_for > 0.0, "Missed courtyard charge has no recovery opening")
	await capture("charge-dodged")
	print("Courtyard sidestep: health=%d, lateral distance=%.2f, recovery=%.2f" % [player.health, player.global_position.x - starting_x, boss.boss_recovery_for])

	# The same pulse must hurt a grounded goat and spare a goat over its crest.
	# Fix the landing position in the unobstructed central courtyard.
	boss.reset_boss_encounter()
	boss.boss_phase = 2
	boss.state = WolverineEnemy.State.ALERT
	boss.rotation.y = PI
	player.global_position = boss.global_position + Vector3(0.0, 0.95, 8.0)
	boss._begin_bellquake()
	for frame in 76:
		await step(0.0, 1.2 if frame > 52 else 0.0)
	check(player.health == 100, "Jumping over the bellquake pulse still deals damage")
	boss.boss_recovery_for = 0.0
	boss._begin_bellquake()
	for frame in 76:
		await step()
	check(player.health == 82, "Grounded bellquake does not deal exactly one 18-point hit: health=%d" % player.health)

	# Finish from a physically reachable position, rather than teleporting the
	# camera inside the enlarged collider to make the interaction available.
	boss.reset_boss_encounter()
	boss.rotation.y = PI
	mission.boss_awake = true
	boss.take_damage(boss.max_health)
	boss.boss_transition_lock = 0.0
	boss.take_damage(boss.max_health)
	boss.boss_transition_lock = 0.0
	boss.take_damage(boss.max_health)
	for enemy in mission.enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
	player.global_position = boss.global_position + Vector3(0.0, 0.95, 8.0)
	player.rotation.y = 0.0
	await physics_frame
	player.move_and_collide(Vector3(0.0, 0.0, -8.0))
	mission._update_prompt()
	check(mission.interact_target.get("kind", "") == "boss_finish", "The new hero collider blocks the final horn-strike interaction")
	mission.chapter_title.visible = true
	mission.chapter_line.visible = true
	mission._on_interact()
	check(mission.victory and mission.bells == 9, "The reachable horn strike does not return the ninth bell")
	await create_timer(2.0).timeout
	await capture("reachable-ending")
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("Varkas encounter test passed")
	quit(0 if failures.is_empty() else 1)
