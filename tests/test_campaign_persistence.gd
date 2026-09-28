extends SceneTree
## Save and continue, playtest telemetry, difficulty in a live mission, the
## pause menu, and gamepad input, all through the real mission scene.

var failures: Array[String] = []


func _init() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func run() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	current_scene = mission
	await process_frame
	check(not mission.continue_button.visible, "Continue was offered without a save")
	mission._start_game()
	var player: GoatPlayer = mission.player
	await physics_frame
	# A title button left focused would turn Space (jump) into another Deploy.
	var focus := root.gui_get_focus_owner()
	check(focus == null, "A hidden title button kept keyboard focus during play: %s" % str(focus))
	check(mission.playtest.enabled and mission.playtest.events[0].event == "session_start", "Starting did not open a playtest session")
	check(mission.playtest.path.is_empty(), "A test run wrote a playtest file to disk")
	check(mission.playtest.events[0].difficulty == "hunter", "Session did not record the difficulty")

	# Two of the camp die; the first bell is collected, the second is left lying.
	var first: WolverineEnemy = mission.enemies[0]
	var second: WolverineEnemy = mission.enemies[1]
	var second_spot := second.global_position
	var second_bell := second.bell_index
	for enemy in [first, second]:
		enemy.set_physics_process(false)
	first.alert_to(player.global_position)
	check(mission.playtest.count("detected") >= 1 and mission.playtest.last("detected").get("reason", "") == "pack", "An alert and its reason were not logged")
	first.take_damage(5000)
	second.take_damage(5000)
	await process_frame
	check(mission.dead_spawn_ids.has(0) and mission.dead_spawn_ids.has(1), "Dead spawn ids were not tracked")
	check(mission.playtest.count("enemy_killed") == 2, "Kills were not logged")
	player.global_position = first.global_position + Vector3(0.0, 1.0, 0.0)
	for frame in 4:
		await physics_frame
	check(mission.bells == 1 and mission.playtest.count("bell_recovered") == 1, "The first bell was not recovered and logged")
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, 5.0) + 1.2, 5.0)
	for frame in 3:
		await process_frame
	check(mission.zone == "homestead" and mission.playtest.last("zone_enter").get("zone", "") == "homestead", "Zone entry was not logged")

	var snapshot: Dictionary = mission.progress_snapshot()
	var clean := SaveGame.sanitize(snapshot)
	check(not clean.is_empty(), "The live snapshot is not a valid save")
	check(clean.zone == "homestead" and clean.bells == 1 and clean.dead.size() == 2, "Snapshot lost progress: %s" % str(clean))
	check(clean.drops.size() == 1 and clean.drops[0].bell == second_bell, "The uncollected bell was not saved")

	# Death is logged with what caused it, then the respawn.
	player.damage(500, "brute")
	check(mission.playtest.last("death").get("cause", "") == "brute" and mission.deaths == 1, "Death cause was not logged")
	check(mission.center_message.text == Story.DEATH % "R", "Death text did not name the retry key")
	mission._respawn()
	check(mission.playtest.count("respawn") == 1 and player.active, "Respawn was not logged")

	# Difficulty applies to a live mission and is logged when changed mid-run.
	GameSettings.set_value("difficulty", "story")
	mission._apply_settings()
	check(mission.playtest.last("difficulty_changed").get("difficulty", "") == "story", "A mid-run difficulty change was not logged")
	var before := player.health
	player.damage(40)
	check(before - player.health == Difficulty.scale_damage(40) and before - player.health < 40, "STORY did not soften a live hit")
	mission.boss._begin_bellquake()
	check(is_equal_approx(mission.boss.boss_windup_for, 1.2 * Difficulty.PRESETS.story.telegraph), "STORY did not lengthen Varkas's warning")
	mission.boss._cancel_boss_attack()
	GameSettings.reset_defaults()
	mission._apply_settings()

	# Brightness reaches the world environment.
	GameSettings.set_value("brightness", 1.3)
	mission._apply_settings()
	check(mission.world.environment.adjustment_enabled and is_equal_approx(mission.world.environment.adjustment_brightness, 1.3), "Brightness did not apply")
	GameSettings.reset_defaults()
	mission._apply_settings()

	# The pause menu: Esc pauses; RESUME sits where the old overlay was clicked;
	# Esc inside Options closes Options but stays paused; Esc again resumes.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	player._unhandled_input(escape)
	check(paused and mission.pause_overlay.visible, "Escape did not pause")
	await process_frame
	var centre := Vector2(root.get_visible_rect().size) * 0.5
	check(mission.resume_button.get_global_rect().has_point(centre), "RESUME is not at screen centre: %s" % str(mission.resume_button.get_global_rect()))
	check(mission.resume_button.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS, "RESUME waits for release")
	mission._open_options(mission.pause_options_button)
	check(mission.options_menu.visible, "Options did not open from pause")
	mission.options_menu._input(escape)
	check(not mission.options_menu.visible and paused, "Escape in Options left the pause menu")
	mission._on_any_input(escape)
	check(not paused and not mission.pause_overlay.visible and player.suppress_fire_until_release, "Escape did not resume safely from the pause menu")
	await process_frame
	focus = root.gui_get_focus_owner()
	check(focus == null, "A pause button kept keyboard focus after resuming")

	# A gamepad press switches every prompt to pad labels.
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	mission._on_any_input(pad)
	check(InputBindings.last_device == "gamepad" and mission.controls_label.text.begins_with("LEFT STICK MOVE"), "Gamepad input did not switch the prompts")
	check(mission.playtest.last("input_device").get("device", "") == "gamepad", "The input device switch was not logged")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = -1.0
	Input.parse_input_event(stick)
	await process_frame
	check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.9, "The left stick does not drive movement")
	stick.axis_value = 0.0
	Input.parse_input_event(stick)
	InputBindings.last_device = "keyboard"

	# A second mission continues from the snapshot.
	var session: PlaytestLog = mission.playtest
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	check(not session.enabled and session.last("session_end").get("reason", "") == "exit", "Leaving the mission did not close its playtest session")

	var resumed: Node3D = load("res://main.tscn").instantiate()
	root.add_child(resumed)
	current_scene = resumed
	await process_frame
	var enemy_count: int = resumed.enemies.size()
	check(resumed.continue_from(snapshot), "Continue rejected a valid snapshot")
	await process_frame
	check(resumed.enemies.size() == enemy_count - 2, "Continue did not remove the dead")
	for enemy in resumed.enemies:
		check(not enemy.get_meta("spawn_id") in [0, 1], "A dead wolverine came back")
	check(resumed.bells == 1 and resumed.pouches.size() == 1 and resumed.pouches[0].bell == second_bell, "Continue lost bells or drops")
	check(resumed.checkpoint == resumed.CHECKPOINTS.homestead and resumed.player.global_position.distance_to(Vector3(0.0, resumed.player.global_position.y, 14.0)) < 0.5, "Continue did not place the Herdkeeper at the saved refuge")
	check(resumed.seen_zones.has("homestead") and resumed.deaths == clean.deaths, "Continue lost seen chapters or death count")
	resumed._start_game()
	check(resumed.playtest.events[0].continued == true, "Session did not record that it continued a save")
	resumed.player.global_position = second_spot + Vector3(0.0, 1.0, 0.0)
	for frame in 4:
		await physics_frame
	check(resumed.bells == 2, "The saved bell drop could not be collected")

	resumed.audio.shutdown()
	await create_timer(0.2).timeout
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Campaign persistence test passed: save, continue, telemetry, difficulty, pause menu, gamepad")
	quit()
