extends SceneTree
## The adaptive score: synthesis, layer mixes, the relax hold, and what the
## mission asks for as the warpack's awareness changes.

var failures: Array[String] = []


func _init() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func run() -> void:
	_synthesis()
	_mixing()
	await _mission_states()
	await _real_lifecycle()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Music test passed: loops, mixes, relax hold, mission states")
	quit()


func _synthesis() -> void:
	var started := Time.get_ticks_msec()
	for layer in GameMusic.LAYERS:
		var samples := GameMusic.synthesize(layer, 4.0, 4000)
		check(samples.size() == 16000, "%s has the wrong length" % layer)
		var peak := 0.0
		var energy := 0.0
		for sample in samples:
			check(is_finite(sample), "%s produced a non-finite sample" % layer)
			peak = maxf(peak, absf(sample))
			energy += sample * sample
		check(peak <= 1.0, "%s clips (peak %.2f)" % [layer, peak])
		check(energy / samples.size() > 0.0005, "%s is silent" % layer)
		# The loop seam must not click: the last and first samples are close.
		check(absf(samples[samples.size() - 1] - samples[0]) < 0.15, "%s clicks at its loop point" % layer)
	print("Synthesised four 4-second test layers in %d ms" % (Time.get_ticks_msec() - started))


func _mixing() -> void:
	for music_state in ["title", "calm", "tension", "combat", "boss", "victory", "silent"]:
		var targets := GameMusic.layer_targets(music_state)
		check(targets.keys().size() == GameMusic.LAYERS.size(), "%s does not set every layer" % music_state)
	check(GameMusic.layer_targets("calm").combat == 0.0 and GameMusic.layer_targets("combat").combat == 1.0, "Combat drums play outside a fight")
	check(GameMusic.layer_targets("boss").boss == 1.0 and GameMusic.layer_targets("combat").boss == 0.0, "Varkas's layer leaks into ordinary fights")
	check(GameMusic.layer_targets("silent").values().all(func(v: float) -> bool: return v == 0.0), "Silent is not silent")
	# Escalation is immediate; calming down waits for the hold.
	var step := GameMusic.step_state("calm", "combat", 0.0, 0.1)
	check(step[0] == "combat", "Combat did not take over at once")
	step = GameMusic.step_state("combat", "calm", GameMusic.RELAX_HOLD_SECONDS, 1.0)
	check(step[0] == "combat" and is_equal_approx(step[1], GameMusic.RELAX_HOLD_SECONDS - 1.0), "Combat dropped without the hold")
	var state := "combat"
	var hold: float = GameMusic.RELAX_HOLD_SECONDS
	for i in 60:
		var next := GameMusic.step_state(state, "calm", hold, 0.1)
		state = next[0]
		hold = next[1]
	check(state == "calm", "Combat never relaxed")
	step = GameMusic.step_state("combat", "victory", GameMusic.RELAX_HOLD_SECONDS, 0.1)
	check(step[0] == "victory", "The ending waited for the relax hold")


func _mission_states() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	current_scene = mission
	await process_frame
	check(GameMusic.building_task == -1 and GameMusic.bank.is_empty(), "A test run started music synthesis")
	mission._start_game()
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	check(mission._music_state() == "calm", "Music is not calm at the trailhead")
	var watcher: WolverineEnemy = mission.enemies[0]
	watcher.detection = Stealth.SUSPICIOUS + 0.1
	check(mission._music_state() == "tension", "Suspicion did not raise tension")
	watcher.detection = Stealth.ALERT
	check(mission._music_state() == "combat", "An alert did not start combat music")
	watcher.detection = 0.0
	watcher.state = WolverineEnemy.State.SEARCH
	watcher.global_position = mission.player.global_position + Vector3(8.0, 0.0, 0.0)
	check(mission._music_state() == "tension", "A nearby search did not keep the tension")
	watcher.state = WolverineEnemy.State.PATROL
	mission.boss_awake = true
	check(mission._music_state() == "boss", "Varkas did not get his own layer")
	mission.boss_awake = false
	# Let the backend mix the just-started wind once before stopping it, then
	# wait until its stream and playback are released (see test_pause_replay).
	await create_timer(maxf(0.05, AudioServer.get_time_to_next_mix() + 0.05)).timeout
	var refs := []
	for voice in mission.audio.voices + mission.audio.spatial + [mission.audio.wind_player]:
		if voice.has_stream_playback():
			refs.append(weakref(voice.get_stream_playback()))
	for stream in mission.audio.streams.values():
		if stream is AudioStreamWAV:
			refs.append(weakref(stream))
	mission.audio.shutdown()
	mission.music.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	for attempt in 50:
		if refs.all(func(r: WeakRef) -> bool: return r.get_ref() == null):
			break
		await create_timer(0.02).timeout
	await process_frame
	await process_frame


## The real path: layers build on a worker thread, all four start together and
## loop, then shutdown and release leave nothing behind (the runner fails on
## any leak warning at exit).
func _real_lifecycle() -> void:
	GameMusic.allow_in_scripts = true
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	current_scene = mission
	var waited := 0.0
	while not mission.music.playing and waited < 20.0:
		await create_timer(0.1).timeout
		waited += 0.1
	check(mission.music.playing, "Music never finished building (%.1f s)" % waited)
	if mission.music.playing:
		print("Music built and started in %.1f s" % waited)
		for layer in GameMusic.LAYERS:
			var player: AudioStreamPlayer = mission.music.players[layer]
			check(player.playing and player.bus == &"Music", "%s is not playing on the Music bus" % layer)
			var stream: AudioStreamWAV = player.stream
			check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and is_equal_approx(stream.get_length(), GameMusic.LOOP_SECONDS), "%s does not loop at 16 s" % layer)
		await create_timer(0.6).timeout
		check(mission.music.gains.calm > 0.1 and mission.music.gains.combat == 0.0, "The title does not fade in the calm layer alone")
	await create_timer(maxf(0.05, AudioServer.get_time_to_next_mix() + 0.05)).timeout
	var refs := []
	for player in mission.music.players.values() + mission.audio.voices + mission.audio.spatial + [mission.audio.wind_player]:
		if player.has_stream_playback():
			refs.append(weakref(player.get_stream_playback()))
		if player.stream:
			refs.append(weakref(player.stream))
	mission.audio.shutdown()
	mission.music.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	check(GameMusic.bank.is_empty(), "Leaving the game kept the music bank")
	for attempt in 50:
		if refs.all(func(r: WeakRef) -> bool: return r.get_ref() == null):
			break
		await create_timer(0.02).timeout
	GameMusic.allow_in_scripts = false
