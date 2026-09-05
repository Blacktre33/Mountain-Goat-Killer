extends SceneTree
## Examine the exposed sculpt at a normal approach and close combat distance.

func _init() -> void:
	call_deferred("capture")

func capture() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	mission.set_process(false)
	mission.player.set_physics_process(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	var boss: WolverineEnemy = mission.boss
	boss.rotation.y = PI
	WorldBuilder.set_biome(mission.world, "iron_crown")
	mission.chapter_title.visible = false
	mission.chapter_line.visible = false
	for view in [
		{"offset": Vector3(2.5, 1.1, 6.3), "phase": 1, "name": "three-quarter"},
		{"offset": Vector3(1.5, 1.1, 4.5), "phase": 3, "name": "close-red-horn"},
		{"offset": Vector3(-1.5, 1.1, 4.5), "phase": 3, "name": "scar-side"},
	]:
		boss.preview_boss_phase(view.phase)
		WorldBuilder.set_varkas_phase(mission.world, view.phase)
		mission.player.global_position = boss.global_position + view.offset
		var direction: Vector3 = boss.global_position + Vector3(0, 2.2, 2.5) - mission.player.aim_origin()
		mission.player.rotation.y = atan2(-direction.x, -direction.z)
		mission.player.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		mission.player.head.rotation.x = mission.player.pitch
		mission.objective_label.text = "VARKAS  //  " + boss.boss_phase_title()
		mission.biome_label.text = "THE IRON CROWN  //  THE LAST BELL"
		mission.bells_label.text = "BELLS RECOVERED  //  8 / 9"
		for frame in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_direction/iron_crown/varkas-sculpt-%s.png" % view.name)
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	quit()
