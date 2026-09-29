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
		fail("Three-biome atmosphere did not initialise in Widowpine")
		return
	var biome_roots: Dictionary = main_scene.world.biome_roots
	if biome_roots.size() != 3 or not biome_roots["whitewood"].visible or not biome_roots["carrion_cut"].visible or not biome_roots["iron_crown"].visible:
		fail("Continuous ravine landmarks did not initialise")
		return
	if main_scene.world.root.find_child("WidowpineWindCrust", true, false) == null or main_scene.world.root.find_child("WidowpineGroundRake", true, false) == null:
		fail("Widowpine lost its player-scale snow relief or raking light")
		return
	if biome_roots["iron_crown"].find_child("IronCrownFacadeBounce", true, false) == null:
		fail("Iron Crown lost the moonlit facade separation pass")
		return
	WorldBuilder.set_biome(main_scene.world, "carrion_cut")
	if not biome_roots["whitewood"].visible or not biome_roots["carrion_cut"].visible or not biome_roots["iron_crown"].visible:
		fail("Local atmosphere removed a ravine landmark")
		return
	WorldBuilder.set_biome(main_scene.world, "whitewood")
	if main_scene.world.bellthorn_storm == null or main_scene.world.name_lights.size() != 8:
		fail("Varkas' courtyard environment did not build")
		return
	WorldBuilder.set_varkas_phase(main_scene.world, 2)
	if main_scene.world.bellthorn_storm.amount_ratio < 0.4 or main_scene.world.name_lights[0].light_energy <= 0.0 or main_scene.world.name_lights[7].light_energy > 0.0:
		fail("Varkas phase-two environment did not wake progressively")
		return
	WorldBuilder.set_varkas_phase(main_scene.world, 3)
	if main_scene.world.bellthorn_storm.amount_ratio < 0.99 or main_scene.world.name_lights[7].light_energy <= 0.0:
		fail("Varkas final-phase environment did not become a full storm")
		return
	WorldBuilder.set_varkas_phase(main_scene.world, 0)
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
	if phase_boss.boss_armor.size() < 10 or phase_boss.boss_embers == null or phase_boss.boss_aura == null or phase_boss.boss_red_horn == null:
		fail("Varkas did not build his bespoke armor and Red Horn wake")
		return
	if (
		phase_boss.find_child("VarkasHeadRuff", true, false) == null
		or phase_boss.find_child("VarkasHeroEye_L", true, false) == null
		or phase_boss.find_child("VarkasHeroEye_R", true, false) == null
		or phase_boss.find_child("VarkasHeroNose", true, false) == null
		or phase_boss.find_child("VarkasFang_L", true, false) == null
		or phase_boss.find_child("VarkasFang_R", true, false) == null
	):
		fail("Varkas lost his custom wolverine skull silhouette")
		return
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
	if phase_boss.boss_embers.amount_ratio < 0.99 or not phase_boss.boss_red_horn.visible:
		fail("Varkas' Red Horn wake did not ignite in phase three")
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
	# Keep the loaded mission roster out of this fixture's guidance pool. A distant
	# patrol can otherwise wander onto the same aim line and make this check depend
	# on frame timing rather than Remembrance's targeting rules.
	var mission_targets: Array = main_scene.enemies.duplicate()
	for mission_target in mission_targets:
		if is_instance_valid(mission_target):
			mission_target.remove_from_group("enemies")
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
	if main_scene.hud_widgets.hung != 2:
		fail("HUD did not reflect hung rounds: %d" % main_scene.hud_widgets.hung)
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
	for mission_target in mission_targets:
		if is_instance_valid(mission_target):
			mission_target.add_to_group("enemies")

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
	if main_scene.chapter_line.text != Story.bell_memory(3):
		fail("Recovering a named bell did not reveal its personal memory")
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
	if not player.active or player.health != 100 or player.camera_trauma != 0.0 or player.global_position.distance_to(main_scene.checkpoint) > 4.0:
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

	# A death during the climax must restart the whole set piece: no carried
	# phase, execution lock, red storm, or phase-two reinforcements.
	main_scene.boss.take_damage(5000)
	main_scene.boss.boss_transition_lock = 0.0
	main_scene.boss.take_damage(5000)
	var reinforcement_count := 0
	for enemy in main_scene.enemies:
		if is_instance_valid(enemy) and enemy.name.begins_with("Varkas_Reinforcement_"):
			reinforcement_count += 1
	if main_scene.boss.boss_phase != 3 or reinforcement_count != 2:
		fail("Varkas setup did not reach the retry fixture: phase=%d reinforcements=%d" % [main_scene.boss.boss_phase, reinforcement_count])
		return
	player.active = false
	main_scene._respawn()
	await process_frame
	for enemy in main_scene.enemies:
		if is_instance_valid(enemy) and enemy.name.begins_with("Varkas_Reinforcement_"):
			fail("Varkas reinforcement survived the encounter reset")
			return
	if main_scene.boss_awake or main_scene.boss.boss_phase != 1 or main_scene.boss.state != WolverineEnemy.State.DORMANT or main_scene.boss.health != main_scene.boss.max_health:
		fail("Varkas retry did not restore Iron Hide: awake=%s phase=%d state=%d health=%d" % [main_scene.boss_awake, main_scene.boss.boss_phase, main_scene.boss.state, main_scene.boss.health])
		return
	if main_scene.world.bellthorn_storm.amount_ratio > 0.0 or main_scene.boss.execution_ready:
		fail("Varkas retry retained final-phase effects")
		return

	# Resolve the restarted climax through the same prompt and interaction path
	# used by the player's E key. This guards the ninth bell, final text, and
	# gold memorial-light state as one indivisible ending contract.
	main_scene.boss_awake = true
	main_scene.bells = Story.IRON_GATE_REQUIRED
	main_scene.player.active = true
	main_scene.boss.set_physics_process(false)
	main_scene.boss.take_damage(main_scene.boss.max_health * 4)
	main_scene.boss.boss_transition_lock = 0.0
	main_scene.boss.take_damage(main_scene.boss.max_health * 4)
	main_scene.boss.boss_transition_lock = 0.0
	main_scene.boss.take_damage(main_scene.boss.max_health * 4)
	if not main_scene.boss.execution_ready:
		fail("Restarted Varkas encounter did not reach the horn-strike beat")
		return
	main_scene.player.global_position = main_scene.boss.global_position + Vector3(0.0, 0.0, 2.65)
	main_scene._update_prompt()
	if main_scene.interact_target.get("kind", "") != "boss_finish":
		fail("Final Varkas interaction prompt did not select the horn strike")
		return
	main_scene._on_interact()
	await process_frame
	if not main_scene.victory or not main_scene.boss.dead or main_scene.bells != Story.BELL_NAMES.size() or main_scene.player.active:
		fail("Varkas execution did not resolve the nine-bell ending")
		return
	if not main_scene.victory_veil.visible or main_scene.crosshair.visible or main_scene.prompt_label.visible:
		fail("Nine-bell ending did not replace the combat HUD with its final presentation")
		return
	if main_scene.objective_position() != Vector3.INF or main_scene.world.name_lights[0].light_color != Color("ffb65a"):
		fail("Victory retained an objective or failed to return the memorial lights to bell-gold")
		return

	print("Runtime smoke test passed")
	# The dummy/headless audio server releases active generated WAV playbacks on
	# its next mix tick, not merely the next SceneTree frame.
	main_scene.audio.shutdown()
	await create_timer(0.2).timeout
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	quit()
