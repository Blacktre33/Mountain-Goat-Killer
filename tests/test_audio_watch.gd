extends SceneTree
## GoatWatch: the sound layer follows the campaign (score, narration, Varkas,
## barks, heartbeat) by reading main.gd's public state.
## Run: Godot --headless --path . --script res://tests/test_audio_watch.gd

var failures: Array[String] = []


func _init() -> void:
	call_deferred("run_test")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func run_test() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var audio: GoatAudio = main.audio
	var watch: GoatWatch = audio._watch
	var player: GoatPlayer = main.player
	audio.settings_path = "user://test_audio_watch.cfg"

	watch.drive(audio, main)
	check(audio.music.state == "title", "Before the start button the score should be the title theme, got %s" % audio.music.state)

	main._start_game()
	await process_frame
	watch.drive(audio, main)
	check(audio.music.state == "stealth", "Unalerted pack should give the stealth score, got %s" % audio.music.state)
	check(audio.voice.current_id == "intro_0" and audio.voice.queue.size() >= 3, "Starting the game should begin the four-line intro narration")
	check(audio.music.biome == "widowpine", "Widowpine should use the widowpine stems, got %s" % audio.music.biome)

	# One alerted wolverine near the player: combat music and a contact bark.
	var wolf: WolverineEnemy = null
	for enemy in main.enemies:
		if not enemy.boss:
			wolf = enemy
			break
	wolf.global_position = player.global_position + Vector3(9.0, 0.0, 0.0)
	wolf.state = WolverineEnemy.State.ALERT
	watch.drive(audio, main)
	check(audio.music.state == "combat", "An alert wolverine should give the combat score, got %s" % audio.music.state)
	check(audio.voice.last_said.any(func(id: String) -> bool: return id.begins_with("bark_contact")), "Alerting did not trigger a contact bark: %s" % [audio.voice.last_said])
	audio.voice._any_bark_ready = 0.0
	wolf.state = WolverineEnemy.State.SEARCH
	watch.drive(audio, main)
	check(audio.voice.last_said.any(func(id: String) -> bool: return id.begins_with("bark_lost")), "Losing the player should trigger a lost bark: %s" % [audio.voice.last_said])
	wolf.state = WolverineEnemy.State.PATROL

	# Zones and bell memories are narrated from the story state.
	main.zone = "homestead"
	watch.drive(audio, main)
	check(watch.narrated.has("homestead"), "Entering the homestead was not narrated")
	main.bells = 2
	main.chapter_title.text = Story.bell_name(1) + "  //  A NAME RETURNED"
	watch.drive(audio, main)
	check(audio.voice.queue.any(func(item: Dictionary) -> bool: return item.id == "memory_1") or audio.voice.current_id == "memory_1", "Recovering ROWAN's bell should queue memory_1")
	main.bell_rung = true
	watch.drive(audio, main)
	check(audio.voice.queue.any(func(item: Dictionary) -> bool: return item.id == "bell_rung"), "Ringing the mother bell was not narrated")

	# Low health: the heartbeat plays and speeds up as health falls.
	audio.voice.stop_narration()
	player.health = 20
	var before := audio.last_played_msec("heartbeat")
	watch.drive(audio, main)
	check(audio.last_played_msec("heartbeat") > before, "Low health did not start the heartbeat")
	player.health = 100

	# Varkas wakes, changes phase, and the score follows.
	main.boss_awake = true
	watch.drive(audio, main)
	check(audio.music.state == "boss1", "Waking Varkas should start boss1, got %s" % audio.music.state)
	check(audio.voice.last_said.any(func(id: String) -> bool: return id.begins_with("varkas_alert")), "Varkas did not speak on waking")
	main.boss.boss_phase = 3
	watch.drive(audio, main)
	check(audio.music.state == "boss3" and audio.voice.last_said.has("varkas_phase_3"), "Phase 3 should start boss3 and Varkas' phase line, got %s" % audio.music.state)
	check(audio.voice._pending.any(func(entry: Array) -> bool: return entry[0] == "boss_phase_3"), "The phase narration should be scheduled after Varkas' line")

	# Death then victory.
	player.health = 0
	watch.drive(audio, main)
	check(audio.music.state == "death" and audio.voice.last_said.any(func(id: String) -> bool: return id.begins_with("varkas_kill")), "Death should switch the score and Varkas should gloat while he is awake, got %s" % audio.music.state)
	player.health = 100
	main.victory = true
	watch.drive(audio, main)
	check(audio.music.state == "victory" and audio.voice.last_said.has("varkas_final"), "Victory should start the ending score and Varkas' last words")
	check(audio.voice._pending.size() >= 4, "The four victory lines should be scheduled")

	audio.set_bus_volume("music", 0.8, false)
	# Same leak hygiene as the other suites: wait until the mixer has released every playback.
	await create_timer(maxf(0.02, AudioServer.get_time_to_next_mix() + 0.02)).timeout
	var refs: Array = []
	for node in audio.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
			if node.stream != null:
				refs.append(weakref(node.stream))
			if node.has_stream_playback():
				refs.append(weakref(node.get_stream_playback()))
	audio.shutdown()
	await create_timer(0.2).timeout
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	var retained := 0
	for attempt in 60:
		retained = 0
		for reference in refs:
			if reference.get_ref() != null:
				retained += 1
		if retained == 0:
			break
		await create_timer(0.02).timeout
	check(retained == 0, "Audio backend retained %d streams or playbacks after teardown" % retained)
	if failures.is_empty():
		print("Audio watch test passed: score, narration, taunts, barks and heartbeat follow the campaign")
		quit()
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
