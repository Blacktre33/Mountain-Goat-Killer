extends SceneTree
## Player-height surface reviews from inside each actual gameplay biome.
## Uses the normal zone/atmosphere selection rather than forcing a remote biome.

func _init() -> void:
	call_deferred("capture")


func capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Biome capture needs the rendered Godot runtime")
		quit(1)
		return
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	for view in [
		{"at": Vector2(0.0, 18.0), "pitch": 0.07, "name": "widowpine/widowpine-ground-pass.png"},
		{"at": Vector2(-5.5, -17.0), "pitch": 0.2, "name": "carrion_cut/carrion-cut-ground-pass.png"},
		{"at": Vector2(0.0, -80.0), "pitch": 0.24, "name": "iron_crown/iron-crown-ground-pass.png"},
	]:
		mission.player.global_position = Vector3(view.at.x, WorldBuilder.height_at(view.at.x, view.at.y) + 1.2, view.at.y)
		mission.player.rotation.y = 0.0
		mission.player.pitch = view.pitch
		mission.player.velocity = Vector3.ZERO
		mission._update_zone()
		mission.hud.chapter_title.visible = false
		mission.hud.chapter_line.visible = false
		for frame in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://art_direction/" + view.name
		var result := root.get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Could not save biome surface review: " + path)
			mission.audio.shutdown()
			quit(1)
			return
		print("Saved biome review: %s (zone=%s, biome=%s)" % [view.name, mission.zone, mission.current_biome])
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	quit()
