extends SceneTree


func _init() -> void:
	call_deferred("run_test")


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func run_test() -> void:
	var main_scene: Node = load("res://main.tscn").instantiate()
	root.add_child(main_scene)
	await process_frame
	main_scene._start_game()
	if main_scene.player.fire_held or not main_scene.player.suppress_fire_until_release:
		fail("Deploy did not gate the initiating mouse click")
		return
	await create_timer(2.0).timeout

	if main_scene.kills != 0:
		fail("Mission kill counter changed without player fire: %d" % main_scene.kills)
		return
	if main_scene.player.health != 100:
		fail("Enemies damaged the player during the opening runway: %d" % main_scene.player.health)
		return
	if main_scene.zone != "trailhead":
		fail("Player did not start at the trailhead: %s" % main_scene.zone)
		return
	if main_scene.audio == null or main_scene.audio.streams.size() < 25 or not main_scene.audio.has_sound("footstep") or not main_scene.audio.has_sound("howl"):
		fail("Audio engine did not build its sound bank: %d" % main_scene.audio.streams.size())
		return
	main_scene.audio.play("shot")
	main_scene.audio.play_at("howl", main_scene.player.global_position)
	if main_scene.minimap == null or main_scene.minimap.terrain == null or main_scene.objective_position() == Vector3.INF:
		fail("Minimap did not build")
		return
	if main_scene.enemies.size() != 10 or not is_instance_valid(main_scene.boss):
		fail("Warpack roster wrong: %d" % main_scene.enemies.size())
		return
	if main_scene.current_biome != "whitewood" or main_scene.world.environment == null or main_scene.world.snow_material == null:
		fail("Three-biome atmosphere did not initialise in Whitewood")
		return
	for enemy in main_scene.enemies:
		if enemy.anim == null or enemy.skeleton == null:
			fail("Wolverine model did not load with animation and skeleton")
			return
		if enemy.state == WolverineEnemy.State.ALERT:
			fail("A wolverine was alert before the goat did anything")
			return

	var isolated_enemy := WolverineEnemy.new()
	root.add_child(isolated_enemy)
	isolated_enemy.configure(main_scene.player, "stalker", Vector3(100.0, 1.0, 100.0))
	var death_count := [0]
	isolated_enemy.killed.connect(func(_enemy: WolverineEnemy) -> void: death_count[0] += 1)
	isolated_enemy.take_damage(1000)
	isolated_enemy.take_damage(1000)
	if death_count[0] != 1:
		fail("Enemy emitted more than one death signal: %d" % death_count[0])
		return

	# VARKAS: damage gates make all three phases unavoidable, then allow death.
	var phase_boss := WolverineEnemy.new()
	root.add_child(phase_boss)
	phase_boss.configure(main_scene.player, "boss", Vector3(120.0, 1.0, 120.0))
	phase_boss.set_physics_process(false)
	var phases: Array[int] = []
	var boss_deaths := [0]
	phase_boss.boss_phase_changed.connect(func(_enemy: WolverineEnemy, phase_index: int, _title: String) -> void: phases.append(phase_index))
	phase_boss.killed.connect(func(_enemy: WolverineEnemy) -> void: boss_deaths[0] += 1)
	phase_boss.take_damage(5000)
	if phase_boss.dead or phase_boss.boss_phase != 2 or phase_boss.health < ceili(phase_boss.max_health * 0.66):
		fail("Varkas skipped or died during phase two transition")
		return
	var transition_health := phase_boss.health
	phase_boss.take_damage(5000)
	if phase_boss.health != transition_health or phase_boss.boss_phase != 2:
		fail("A volley crossed Varkas' phase-two invulnerability beat")
		return
	phase_boss.boss_transition_lock = 0.0
	phase_boss.take_damage(5000)
	if phase_boss.dead or phase_boss.boss_phase != 3 or phase_boss.health < ceili(phase_boss.max_health * 0.33):
		fail("Varkas skipped or died during phase three transition")
		return
	transition_health = phase_boss.health
	phase_boss.take_damage(5000)
	if phase_boss.health != transition_health or phase_boss.boss_phase != 3:
		fail("A volley crossed Varkas' final transition beat")
		return
	phase_boss.boss_transition_lock = 0.0
	phase_boss.take_damage(5000)
	if phase_boss.dead or not phase_boss.execution_ready or phases != [2, 3] or boss_deaths[0] != 0:
		fail("Varkas did not break for the final horn strike: phases=%s ready=%s" % [phases, phase_boss.execution_ready])
		return
	phase_boss.take_damage(5000)
	if phase_boss.dead:
		fail("Bullets killed Varkas after he entered the execution beat")
		return
	phase_boss.execute_boss()
	if not phase_boss.dead or boss_deaths[0] != 1:
		fail("The final horn strike did not end Varkas exactly once")
		return

	# STEALTH: a wolverine facing away, upwind, does not notice a crouched goat; a gunshot does.
	var player: GoatPlayer = main_scene.player
	var sentry := WolverineEnemy.new()
	root.add_child(sentry)
	sentry.configure(player, "rifleman", player.global_position + Vector3(0.0, 0.0, -6.0))
	sentry.look_at(sentry.global_position + Vector3(0.0, 0.0, -10.0), Vector3.UP)
	player.set_crouched(true)
	if not player.crouched or player.collider_shape.height >= 1.8:
		fail("Crouch did not shrink the goat")
		return
	await create_timer(1.0).timeout
	if sentry.state == WolverineEnemy.State.ALERT:
		fail("Sentry facing away went alert with no stimulus (detection %f)" % sentry.detection)
		return
	player.global_position = sentry.global_position - sentry.facing() * 1.6
	var takedown_ok := Stealth.can_takedown(sentry.facing(), player.global_position - sentry.global_position, sentry.detection)
	if not takedown_ok:
		fail("Goat behind an unaware sentry should be able to strike")
		return
	sentry.hear_noise(player.global_position, Stealth.noise_radius("shot"))
	if sentry.state != WolverineEnemy.State.ALERT:
		fail("A gunshot next to the sentry should make it hunt")
		return
	var sentry_home := sentry.home_position
	sentry.global_position += Vector3(4.0, 0.0, 4.0)
	sentry.calm()
	if sentry.state != WolverineEnemy.State.PATROL or sentry.detection != 0.0 or not sentry.global_position.is_equal_approx(sentry_home):
		fail("Calm did not reset the sentry safely to its patrol")
		return
	sentry.hear_noise(player.global_position, Stealth.noise_radius("decoy"))
	if sentry.state != WolverineEnemy.State.SUSPICIOUS:
		fail("A landing stone should make the sentry investigate")
		return
	var health_before_strike := sentry.health
	player.perform_takedown(sentry)
	if not sentry.dead or health_before_strike <= 0:
		fail("Horn strike did not kill the sentry")
		return
	player.set_crouched(false)

	# REMEMBRANCE: hang two rounds toward a wolverine standing on the aim line, then release.
	var mark := WolverineEnemy.new()
	root.add_child(mark)
	var mark_spot := player.global_position + Vector3(player.aim_direction().x, 0.0, player.aim_direction().z).normalized() * 14.0
	mark.configure(player, "rifleman", Vector3(mark_spot.x, WorldBuilder.height_at(mark_spot.x, mark_spot.z) + 0.05, mark_spot.z))
	mark.killed.connect(main_scene._on_enemy_killed)
	mark.set_physics_process(false)
	await process_frame
	var ammo_before := player.ammo
	if not player.hang_round() or not player.hang_round():
		fail("Could not hang rounds with a loaded magazine")
		return
	if player.hung.size() != 2 or player.ammo != ammo_before - 2:
		fail("Hanging rounds did not spend ammo: hung=%d ammo=%d" % [player.hung.size(), player.ammo])
		return
	if main_scene.remembrance_label.text.find("[||....]") == -1:
		fail("HUD did not reflect hung rounds: %s" % main_scene.remembrance_label.text)
		return
	var health_before := mark.health
	var landed := player.release_volley("hold")
	var expected := roundi(Remembrance.BODY_DAMAGE * Remembrance.CONVERGENCE_MULTIPLIER) * 2
	if landed != 2 or mark.health != health_before - expected:
		fail("Volley did not converge on the mark: landed=%d health=%d expected loss=%d" % [landed, mark.health, expected])
		return
	if not mark.dead or not (mark.stagger > 1.0):
		fail("Two converged rounds should stagger and drop a rifleman: dead=%s stagger=%f" % [mark.dead, mark.stagger])
		return
	if not player.hung.is_empty() or main_scene.center_message.text != "CONVERGENCE":
		fail("Volley did not clear hung rounds or announce convergence: %s" % main_scene.center_message.text)
		return
	player.rotation.y = PI  # face back down the empty trail
	if not player.hang_round() or player.release_volley("hold") != 0:
		fail("A round released into the dark should land nothing")
		return
	player.rotation.y = 0.0

	# A kill beside the player drops a pouch (or a bell) that is collected by proximity.
	var victim := WolverineEnemy.new()
	root.add_child(victim)
	victim.configure(player, "stalker", player.global_position + Vector3(1.0, 0.0, 0.0), [], 3)
	victim.killed.connect(main_scene._on_enemy_killed)
	victim.set_physics_process(false)
	await process_frame
	var reserve_before := player.reserve
	var bells_before: int = main_scene.bells
	victim.take_damage(5000)
	await process_frame
	await process_frame
	if player.reserve != reserve_before + main_scene.POUCH_AMMO or main_scene.bells != bells_before + 1:
		fail("Bell was not collected: reserve %d -> %d bells %d" % [reserve_before, player.reserve, main_scene.bells])
		return

	# Second wind regenerates will after a quiet spell, but never past the cap.
	player.damage(70)
	player.since_damage = GoatPlayer.REGEN_DELAY + 1.0
	await create_timer(1.0).timeout
	if player.health <= 30 or player.health > GoatPlayer.REGEN_CAP:
		fail("Second wind misbehaved: health=%d" % player.health)
		return

	# Death and checkpoint respawn.
	player.damage(500)
	if player.active:
		fail("Player survived lethal damage")
		return
	main_scene._respawn()
	if not player.active or player.health != 100 or player.global_position.distance_to(main_scene.checkpoint) > 4.0:
		fail("Respawn did not restore the goat at the checkpoint")
		return

	# The finale gate stays shut until the mother bell and all eight carried
	# names are present, then Varkas wakes even on a later update after it opens.
	player.active = false
	main_scene.bell_rung = true
	main_scene.bells = Story.IRON_GATE_REQUIRED - 1
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, WorldBuilder.GATE_Z + 6.0) + 1.2, WorldBuilder.GATE_Z + 6.0)
	main_scene._update_gate()
	if main_scene.gate_open:
		fail("The Iron Gate opened before all eight names were recovered")
		return
	main_scene.bells = Story.IRON_GATE_REQUIRED
	main_scene._update_gate()
	if not main_scene.gate_open or main_scene.boss_awake:
		fail("The Iron Gate did not open cleanly before the arena threshold")
		return
	player.global_position.z = WorldBuilder.GATE_Z - 2.0
	main_scene._update_gate()
	if not main_scene.boss_awake or main_scene.boss.state != WolverineEnemy.State.ALERT:
		fail("Varkas did not wake after crossing an already-open gate")
		return

	print("Runtime smoke test passed")
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	quit()
