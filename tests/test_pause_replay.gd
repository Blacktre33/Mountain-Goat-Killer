extends SceneTree
## Real pause freezes the encounter; the ending can return to a fresh title.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	current_scene = mission
	await process_frame
	mission._start_game()
	var enemy: WolverineEnemy = mission.enemies[0]
	enemy.cooldown = 2.0
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		Input.parse_input_event(escape)
		await process_frame
	else:
		mission.player._unhandled_input(escape)
	var at := enemy.position
	var cooldown := enemy.cooldown
	var failures: Array[String] = []
	if not paused or not mission.hud.pause_overlay.visible:
		failures.append("Escape displays a pause label without pausing the scene")
	for frame in 12:
		await physics_frame
	if enemy.position.distance_to(at) > 0.001 or not is_equal_approx(enemy.cooldown, cooldown):
		failures.append("Enemy movement or attack timers continue during pause")
	if rendered:
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://art_direction/interface")
		root.get_texture().get_image().save_png("res://art_direction/interface/paused.png")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	if rendered:
		click.position = Vector2(640, 360)
		Input.parse_input_event(click)
		await process_frame
	else:
		mission.hud.pause_overlay.gui_input.emit(click)
	if paused or mission.hud.pause_overlay.visible or not mission.player.suppress_fire_until_release:
		failures.append("Pause click did not resume safely without firing")
	paused = false
	if not failures.is_empty():
		mission.audio.shutdown()
		await create_timer(0.2).timeout
		mission.queue_free()
		await process_frame
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	# The full campaign probe proves the combat gates; this fixture exercises
	# the real ending signal and UI's scene replacement after the final strike.
	mission.bells = 8
	mission.boss._break_for_execution()
	mission.boss.execute_boss()
	await process_frame
	if not mission.victory or not mission.hud.ending_actions.visible:
		push_error("Victory did not expose return-to-title controls")
		quit(1)
		return
	if rendered:
		await create_timer(1.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_direction/interface/ending.png")
		click.pressed = false
		Input.parse_input_event(click)
		click = click.duplicate()
		click.pressed = true
		click.position = mission.hud.return_button.get_global_rect().get_center()
		Input.parse_input_event(click)
		click = click.duplicate()
		click.pressed = false
		Input.parse_input_event(click)
	else:
		mission.hud.return_button.pressed.emit()
	for frame in 120:
		await process_frame
		if is_instance_valid(current_scene) and current_scene != mission:
			break
	var fresh := current_scene
	if fresh == mission or fresh.started or fresh.victory or fresh.bells != 0 or not fresh.hud.start_overlay.visible:
		push_error("Returning to title did not create a fresh mission")
		quit(1)
		return
	# A newly rebuilt title has only just queued its wind playback. Let the
	# backend mix it once before stopping, then verify release during teardown.
	await create_timer(maxf(0.02, AudioServer.get_time_to_next_mix() + 0.02)).timeout
	var audio_refs := _audio_references(fresh.audio)
	fresh.audio.shutdown()
	await create_timer(0.2).timeout
	fresh.queue_free()
	await process_frame
	await process_frame
	var retained := 0
	for attempt in 50:
		retained = 0
		for reference in audio_refs:
			if reference.get_ref() != null:
				retained += 1
		if retained == 0:
			break
		await create_timer(0.02).timeout
	if retained > 0:
		push_error("Replay teardown retained %d generated streams or playbacks" % retained)
		quit(1)
		return
	print("Pause and replay test passed: frozen encounter, safe resume, fresh title")
	quit()


func _audio_references(audio: GoatAudio) -> Array:
	var refs := []
	for stream in audio.streams.values():
		if stream is AudioStreamWAV:
			refs.append(weakref(stream))
	for voice in audio.voices + audio.spatial + [audio.wind_player]:
		if voice.has_stream_playback():
			refs.append(weakref(voice.get_stream_playback()))
	return refs
