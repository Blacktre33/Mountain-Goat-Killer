extends SceneTree
## Phase-three stealth systems in a live mission: bodies that stay where they
## fall and are found by patrols.

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
	mission._start_game()
	var player: GoatPlayer = mission.player
	# Park the Herdkeeper far from the camp so only the staged senses matter.
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, 40.0) + 1.2, 40.0)
	await physics_frame
	await _bodies(mission)
	await _tracker(mission)
	await _cairns(mission)
	mission.audio.shutdown()
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
	print("Stealth depth test passed: bodies, trackers, cairns")
	quit()


func _bodies(mission: Node3D) -> void:
	var victim: WolverineEnemy = mission.enemies[0]
	var finder: WolverineEnemy = mission.enemies[1]
	var neighbour: WolverineEnemy = mission.enemies[2]
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	# Stage on the open trailhead road, clear of the fold's props.
	victim.global_position = Vector3(1.0, WorldBuilder.height_at(1.0, 24.0) + 0.3, 24.0)
	# A silent horn strike leaves a body where the wolverine fell.
	victim.takedown()
	await create_timer(4.5).timeout
	check(is_instance_valid(victim) and victim.is_in_group("bodies") and not victim.get_meta("body_found", true), "A killed wolverine did not leave an undiscovered body")
	var at := victim.global_position
	# A packmate whose back is turned does not notice it.
	finder.global_position = Vector3(at.x, WorldBuilder.height_at(at.x, at.z + 6.0) + 0.3, at.z + 6.0)
	finder.look_at(finder.global_position + Vector3(0.0, 0.0, 1.0), Vector3.UP)
	finder.state = WolverineEnemy.State.PATROL
	finder._look_for_bodies()
	check(finder.state == WolverineEnemy.State.PATROL and not victim.get_meta("body_found"), "A body behind the patrol was noticed")
	# Facing it with a clear view, it is found.
	finder.look_at(Vector3(at.x, finder.global_position.y, at.z), Vector3.UP)
	neighbour.global_position = Vector3(at.x - 5.0, WorldBuilder.height_at(at.x - 5.0, at.z + 4.0) + 0.3, at.z + 4.0)
	neighbour.state = WolverineEnemy.State.PATROL
	neighbour.detection = 0.0
	finder._look_for_bodies()
	check(victim.get_meta("body_found"), "A body in plain view was not found")
	check(finder.state == WolverineEnemy.State.SEARCH and finder.wary_for > 0.0 and finder.search_seconds == WolverineEnemy.BODY_SEARCH_SECONDS, "The finder did not search warily")
	check(neighbour.state == WolverineEnemy.State.SUSPICIOUS and neighbour.investigate_point.distance_to(at) < 0.5, "A nearby packmate was not drawn to the body")
	check(mission.playtest.last("body_found").get("role", "") == finder.role, "The discovery was not logged")
	check(mission.hud.center_message.text.begins_with("THEY FOUND A BODY"), "The discovery was not announced")
	# A found body does not trigger again.
	finder.state = WolverineEnemy.State.PATROL
	finder._look_for_bodies()
	check(finder.state == WolverineEnemy.State.PATROL, "A found body was discovered twice")
	# Wariness sharpens the senses, and a respawn calms it.
	finder.calm()
	check(finder.wary_for == 0.0, "Respawn calm did not clear wariness")
	# Varkas's summoned reinforcements leave no body behind.
	mission._spawn_reinforcement(Vector2(at.x + 3.0, at.z))
	var summoned: WolverineEnemy = mission.enemies[mission.enemies.size() - 1]
	summoned.set_physics_process(false)
	summoned.take_damage(5000)
	await create_timer(4.5).timeout
	check(not is_instance_valid(summoned), "A reinforcement left a body")


func _tracker(mission: Node3D) -> void:
	var trackers: Array = mission.enemies.filter(func(e: WolverineEnemy) -> bool: return e.role == "tracker")
	check(trackers.size() == 2, "Expected two trackers, found %d" % trackers.size())
	if trackers.is_empty():
		return
	var tracker: WolverineEnemy = trackers[0]
	var stalker: WolverineEnemy = mission.enemies.filter(func(e: WolverineEnemy) -> bool: return e.role == "stalker")[0]
	check(tracker.max_health < stalker.max_health and tracker.scent_multiplier > 1.0 and tracker.sight_multiplier < 1.0, "Tracker is not a weak, keen-nosed hunter")
	check(tracker.howl_range > WolverineEnemy.HOWL_RANGE and tracker.scent_range > Stealth.SCENT_RANGE, "Tracker does not smell or call further than the pack")
	# Downwind at 30 m, only the tracker's nose reaches the goat.
	var wind := Vector3(1.0, 0.0, 0.0)
	check(Stealth.scent_strength(Vector3.ZERO, Vector3(30.0, 0.0, 0.0), wind) == 0.0 and Stealth.scent_strength(Vector3.ZERO, Vector3(30.0, 0.0, 0.0), wind, tracker.scent_range) > 0.0, "Tracker scent range is not longer")
	# An alerted tracker calls packmates from beyond a normal howl.
	var far: WolverineEnemy = mission.enemies.filter(func(e: WolverineEnemy) -> bool: return e != tracker and not e.boss and not e.dead)[0]
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
		if not enemy.boss:
			enemy.calm()
	far.global_position = tracker.global_position + Vector3(WolverineEnemy.HOWL_RANGE + 4.0, 0.0, 0.0)
	tracker.alert_to(tracker.global_position)
	check(far.state == WolverineEnemy.State.ALERT, "A tracker's howl did not reach beyond a normal howl")
	for enemy in mission.enemies:
		if not enemy.boss:
			enemy.calm()


func _cairns(mission: Node3D) -> void:
	var player: GoatPlayer = mission.player
	check(mission.world.cairns.size() == 3, "Expected three of Maren's cairns")
	check(player.remembrance_capacity == Remembrance.BASE_CAPACITY, "Remembrance did not start at its base capacity")
	var cairn: Dictionary = mission.world.cairns[0]
	player.global_position = cairn.position + Vector3(0.0, 0.5, 1.6)
	mission._update_prompt()
	check(mission.interact_target.get("kind", "") == "cairn", "Standing at a cairn did not offer to kindle it")
	mission._on_interact()
	check(cairn.kindled and player.remembrance_capacity == Remembrance.BASE_CAPACITY + 1, "Kindling a cairn did not deepen Remembrance")
	check(mission.hud.remembrance_label.text.contains("[....]"), "HUD did not show the new slot: " + mission.hud.remembrance_label.text)
	check(mission.playtest.last("cairn_kindled").get("capacity", 0) == 4, "Kindling was not logged")
	check(mission.progress_snapshot().cairns == [0], "The kindled cairn is not in the save")
	mission._update_prompt()
	check(mission.interact_target.get("kind", "") != "cairn", "A kindled cairn offered itself again")
	for other in mission.world.cairns.slice(1):
		mission._kindle_cairn(other, false)
	check(player.remembrance_capacity == Remembrance.CAPACITY, "Three cairns did not restore the full six rounds")
	# Every cairn stands on open, reachable ground.
	for each in mission.world.cairns:
		var at: Vector3 = each.position
		check(WorldBuilder.slope_at(at.x, at.z) < 1.0, "Cairn %d sits on a cliff" % each.index)
