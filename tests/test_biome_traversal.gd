extends SceneTree
## Landmarks belong to the continuous ravine, independently of local weather.

func _init() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	mission.player.set_physics_process(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	var failures: Array[String] = []
	for z in [18.0, -15.9, -16.1, -39.9, -40.1, -64.0, -75.9, -76.1, -15.9]:
		mission.player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, z) + 1.2, z)
		mission._update_zone()
		for biome in mission.world.biome_roots:
			if not mission.world.biome_roots[biome].is_visible_in_tree():
				failures.append("%s landmark disappears at z=%.1f (%s atmosphere)" % [biome, z, mission.current_biome])
		if "--capture-traversal" in OS.get_cmdline_user_args() and z in [-15.9, -16.1, -64.0, -75.9, -76.1]:
			mission.player.pitch = 0.18
			mission.player.head.rotation.x = 0.18
			mission.hud.chapter_title.visible = false
			mission.hud.chapter_line.visible = false
			for frame in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "res://art_direction/traversal/route-%s.png" % str(absf(z)).replace(".", "-")
			DirAccess.make_dir_recursive_absolute("res://art_direction/traversal")
			root.get_texture().get_image().save_png(path)
			print("Traversal view %s: %s, draw calls=%s" % [z, mission.current_biome, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	# The headless route queues every chapter in one frame. Its audio buffer is
	# longer than a render frame: allow one mix before tearing down the cues.
	await create_timer(maxf(0.02, AudioServer.get_time_to_next_mix() + 0.02)).timeout
	var audio_refs := _audio_references(mission.audio)
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	# Validate completion rather than assuming a fixed delay drained the mixer.
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
		failures.append("Audio backend retained %d generated streams or playbacks after teardown" % retained)
	if failures.is_empty():
		print("Biome traversal test passed: landmarks persist through forward and backward crossings")
		quit()
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _audio_references(audio: GoatAudio) -> Array:
	var refs := []
	for stream in audio.streams.values():
		if stream is AudioStreamWAV:
			refs.append(weakref(stream))
	for voice in audio.voices + audio.spatial + [audio.wind_player]:
		if voice.has_stream_playback():
			refs.append(weakref(voice.get_stream_playback()))
	return refs
