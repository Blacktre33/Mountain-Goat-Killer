extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("run_test")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func run_test() -> void:
	var player := GoatPlayer.new()
	root.add_child(player)
	player.set_physics_process(false)
	player.active = true
	var boss := WolverineEnemy.new()
	root.add_child(boss)
	boss.configure(player, "boss", Vector3.ZERO)
	boss.set_physics_process(false)
	boss.state = WolverineEnemy.State.ALERT
	boss.has_los = true
	boss.boss_phase = 3
	boss.boss_ability_cooldown = 0.0
	var boss_events: Array[String] = []
	boss.boss_attack.connect(func(_who: WolverineEnemy, attack_name: String) -> void: boss_events.append(attack_name))
	player.global_position = Vector3(0.0, 0.0, -12.0)
	var opening_motion := boss._boss_motion(12.0, Vector3.FORWARD)
	check(opening_motion.is_zero_approx(), "Red Horn moves immediately on its warning; there is no dodge windup")
	var warning_vertices: PackedVector3Array = boss.boss_telegraph.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in warning_vertices:
		var point: Vector3 = boss.boss_telegraph.global_transform * vertex
		check(point.y > WorldBuilder.height_at(point.x, point.z) + 0.05, "The charge warning is buried beneath the terrain")
	boss._boss_motion(12.0, Vector3.FORWARD, 1.0)
	var forward_motion := boss._boss_motion(12.0, Vector3.FORWARD, 0.05)
	player.global_position = Vector3(12.0, 0.0, 0.0)
	var sidestep_motion := boss._boss_motion(12.0, Vector3.RIGHT, 0.05)
	check(not forward_motion.is_zero_approx(), "Red Horn never leaves its windup")
	check(forward_motion.is_equal_approx(sidestep_motion), "A committed Red Horn charge steers after a sidestep")
	boss._boss_motion(12.0, Vector3.RIGHT, 1.2)
	check(boss.boss_recovery_for > 1.0, "A missed charge does not leave a punish window")
	check("dodged" in boss_events and "exposed" in boss_events, "A sidestepped charge gave no dodge or opening feedback: %s" % [boss_events])
	check(boss._boss_motion(12.0, Vector3.RIGHT, 0.1).is_zero_approx(), "Varkas attacks again during recovery")

	# Convergence has a distinct tactical purpose: stop a pending or active
	# charge, without bypassing the existing health phase gates.
	boss.health = boss.max_health
	boss.boss_recovery_for = 0.0
	boss.boss_charge_for = 0.8
	boss.take_damage(10, Remembrance.CONVERGENCE_STAGGER)
	check(boss.boss_charge_for == 0.0 and boss.boss_recovery_for >= 1.0, "Convergence does not break Varkas's charge")

	# A quake must belong to its encounter. Reset during its tell and wait
	# longer than the old delayed callback: no damage may arrive on the retry.
	boss.boss_phase = 2
	boss._begin_bellquake()
	boss.reset_boss_encounter()
	player.global_position = Vector3(0.0, 0.0, -5.0)
	var retry_health := player.health
	await create_timer(0.8).timeout
	check(player.health == retry_health, "A cancelled bellquake damages the next attempt")
	check(boss.boss_windup_for == 0.0 and boss.boss_charge_for == 0.0 and boss.boss_recovery_for == 0.0, "Retry retains a pending boss attack")
	check(is_equal_approx(boss.speed, 3.4) and is_equal_approx(boss.attack_range, 4.0), "Retry retains Red Horn's combat statistics")

	# Enter the real physics brain during a phase card. The normal warpack
	# contact attack must not run beneath the boss's transition lock.
	boss.reset_boss_encounter()
	boss.state = WolverineEnemy.State.ALERT
	boss.has_los = true
	boss.stagger = 0.0
	boss.boss_transition_lock = 1.0
	boss.cooldown = 0.0
	player.global_position = Vector3(0.0, 0.0, -3.0)
	var health_before := player.health
	boss._physics_process(1.0 / 60.0)
	check(player.health == health_before, "Varkas deals contact damage during a phase transition")

	# Every announced attack has a body pose that matches it: the Bellquake rears
	# the whole body up during its tell and slams it back down on release.
	boss.reset_boss_encounter()
	boss.state = WolverineEnemy.State.ALERT
	boss.has_los = true
	boss.boss_phase = 2
	player.global_position = Vector3(0.0, 0.0, -8.0)
	boss._begin_bellquake()
	boss._boss_motion(8.0, Vector3.FORWARD, 0.9)
	check(boss.boss_pitch > 0.4, "The Bellquake tell does not rear Varkas up (pitch %.2f)" % boss.boss_pitch)
	boss._boss_motion(8.0, Vector3.FORWARD, 0.5)
	await create_timer(0.3).timeout
	check(boss.boss_pitch < 0.05 and boss.boss_pitch > -0.2 and boss.boss_recovery_for > 0.0, "The Bellquake slam did not bring Varkas down into recovery (pitch %.2f, recovery %.2f)" % [boss.boss_pitch, boss.boss_recovery_for])

	# The phase break is a beat, not a flag: he rears, the plates that phase
	# discards leave as physical debris, and Red Horn's horn grows from nothing.
	boss.reset_boss_encounter()
	var plates_before := 0
	for plate in boss.boss_armor:
		if plate.visible:
			plates_before += 1
	boss.state = WolverineEnemy.State.ALERT
	boss.take_damage(boss.max_health)
	check(boss.boss_phase == 2, "Test setup: Varkas did not enter phase two")
	await create_timer(0.75).timeout
	check(boss.boss_pitch > 0.3, "Varkas does not rear up through the phase break (pitch %.2f)" % boss.boss_pitch)
	await create_timer(1.0).timeout
	var plates_after := 0
	for plate in boss.boss_armor:
		if plate.visible:
			plates_after += 1
	check(plates_after < plates_before, "Phase two kept every armor plate")
	var debris := 0
	for child in root.get_children():
		if child is RigidBody3D:
			debris += 1
	check(debris > 0, "Torn-off armor did not fly away as debris")
	boss.boss_transition_lock = 0.0
	boss.take_damage(boss.max_health)
	check(boss.boss_phase == 3 and boss.boss_red_horn.visible and boss.boss_red_horn.scale.x < 0.9, "Red Horn's horn did not start growing at the phase break")
	await create_timer(1.6).timeout
	check(boss.boss_red_horn.scale.x > 0.95, "Red Horn's horn never finished growing")
	boss.reset_boss_encounter()
	var restored := 0
	for plate in boss.boss_armor:
		if plate.visible:
			restored += 1
	check(restored == plates_before and absf(boss.boss_pitch) < 0.01 and not boss.boss_red_horn.visible, "Retry did not restore Varkas' armor, stance and horn")

	# Walk the actual player capsule into the front of the hero. Collision
	# should stop before the camera can enter the visible muzzle at z = -3.13.
	boss.global_position = Vector3.ZERO
	boss.rotation = Vector3.ZERO
	player.global_position = Vector3(0.0, 1.0, -8.0)
	await physics_frame
	player.move_and_collide(Vector3(0.0, 0.0, 8.0))
	check(player.global_position.z < -3.3, "The player capsule enters Varkas's visible muzzle")

	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("Varkas combat tests passed")
	quit(0 if failures.is_empty() else 1)
