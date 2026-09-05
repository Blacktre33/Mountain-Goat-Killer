extends SceneTree
## Staged visual check of the real carbine hit, brief spray and death stain.

func _init() -> void:
	call_deferred("capture")

func capture() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	mission.player.set_physics_process(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	var victim: WolverineEnemy = mission.enemies[0]
	victim.global_position = Vector3(0, WorldBuilder.height_at(0, 23) + 0.05, 23)
	mission.player.global_position = Vector3(0, WorldBuilder.height_at(0, 27) + 0.95, 27)
	var direction: Vector3 = victim.position + Vector3.UP * 0.85 - mission.player.aim_origin()
	mission.player.rotation.y = atan2(-direction.x, -direction.z)
	mission.player.pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	mission.player.head.rotation.x = mission.player.pitch
	mission.player.aiming = true
	mission.chapter_title.visible = false
	mission.chapter_line.visible = false
	await physics_frame
	await physics_frame
	mission.player._shoot()
	if not victim.dead:
		push_error("Carbine hit did not reach the staged target")
		quit(1)
		return
	await create_timer(0.18).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_direction/widowpine/carbine-hit-effects.png")
	print("Captured real carbine kill with brief blood spray and ground stain")
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	quit()
