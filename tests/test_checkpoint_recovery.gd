extends SceneTree
## Retry from each refuge using the real world collision and player controls.

func _init() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	mission.set_process(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	var player: GoatPlayer = mission.player
	var failures: Array[String] = []
	for refuge in mission.CHECKPOINTS:
		mission.checkpoint = mission.CHECKPOINTS[refuge]
		player.damage(1000)
		mission._respawn()
		for frame in 45:
			await physics_frame
		var at: Vector3 = mission.checkpoint
		if not player.is_on_floor() or Vector2(player.position.x - at.x, player.position.z - at.z).length() > 0.5:
			failures.append("Refuge %s did not settle safely at its spawn: %s" % [refuge, player.position])
		print("Refuge %s: floor=%s, height=%.2f" % [refuge, player.is_on_floor(), player.position.y])
	player.set_physics_process(false)
	# An interrupted reload must not lock the new life or refill shots later.
	player.ammo = 3
	player._reload()
	player.aiming = true
	player.hang_held_for = 0.1
	player.damage(1000)
	mission._respawn()
	if player.reloading or player.aiming or player.hang_held_for >= 0.0:
		failures.append("Retry retained reload, aim, or held Remembrance input")
	player.ammo = 20  # Four rounds fired after returning to the refuge.
	var reserve_before := player.reserve
	await create_timer(GoatPlayer.RELOAD_SECONDS + 0.1).timeout
	if player.ammo != 20 or player.reserve != reserve_before:
		failures.append("A reload from the previous life changed the new life's ammunition")
	player._reload()
	await create_timer(GoatPlayer.RELOAD_SECONDS + 0.1).timeout
	if player.reloading or player.ammo != GoatPlayer.MAGAZINE_SIZE or player.reserve != reserve_before - 4:
		failures.append("A fresh reload after retry did not spend and load four rounds")
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("Checkpoint recovery test passed: six safe refuges and no inherited inputs or reload")
		quit()
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
