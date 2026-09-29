extends SceneTree
## Movement, weapon rig and combat effects run against the real world collision:
## acceleration and braking, footfall cadence by posture, ceilings blocking a stand,
## step-up over ledges (and not over walls), landing dip, slope stability, pitch and
## look defaults, the reload timeline against RELOAD_SECONDS, casing ejection, and
## the bullet-hole pool cap.

var mission: Node3D
var player: GoatPlayer
var failures: Array[String] = []
var footfalls := 0
var cues: Array[String] = []
var casings := 0
var drops := 0


func _init() -> void:
	call_deferred("run_test")


func _key(keycode: Key, pressed: bool) -> void:
	if pressed:
		player.held_keys[keycode] = true
	else:
		player.held_keys.erase(keycode)


func _release_all() -> void:
	player.held_keys.clear()


func _flat_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _settle_at(x: float, z: float) -> void:
	_release_all()
	player.global_position = Vector3(x, WorldBuilder.height_at(x, z) + 1.0, z)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player.set_crouched(false)
	for _i in 40:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func run_test() -> void:
	mission = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	mission.set_process(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	player = mission.player
	player.noise_made.connect(func(_source: Vector3, _radius: float) -> void: footfalls += 1)
	player.scripted_capture = true

	_check(not player.look_smoothing, "Look smoothing must default to off")
	_check(FPSControls.apply_look(0.0, 0.0, Vector2(0.0, -1.0e6)).y <= FPSControls.PITCH_MAX, "Pitch exceeds its ceiling")
	_check(FPSControls.PITCH_MAX < 1.5 and FPSControls.PITCH_MIN > -1.5, "Pitch clamp leaves room to flip the camera")

	await _test_ground_response()
	await _test_footfalls()
	await _test_ceiling()
	await _test_steps()
	await _test_landing()
	await _test_slope()
	await _test_weapon_rig()
	await _test_effect_pools()

	_release_all()
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Player feel tests passed: response, cadence, ceilings, steps, landing, slopes, rig, pools")
	quit()


func _test_ground_response() -> void:
	await _settle_at(0.0, 36.0)
	_key(KEY_W, true)
	var start := player.global_position
	var frames_to_walk := -1
	for frame in 60:
		await physics_frame
		if frames_to_walk < 0 and _flat_speed() >= GoatPlayer.WALK_SPEED * 0.9:
			frames_to_walk = frame + 1
	print("Ground response: %d frames to walk speed" % frames_to_walk)
	_check(frames_to_walk > 0 and frames_to_walk <= 14, "Walk start is floaty: %d frames to 90%% speed" % frames_to_walk)
	_check(player.global_position.distance_to(start) > 3.0, "Holding W did not move the goat")
	_key(KEY_W, false)
	var frames_to_stop := -1
	var stop_from := player.global_position
	for frame in 60:
		await physics_frame
		if frames_to_stop < 0 and _flat_speed() < 0.2:
			frames_to_stop = frame + 1
	print("Ground response: %d frames to stop, %.2f m slide" % [frames_to_stop, player.global_position.distance_to(stop_from)])
	_check(frames_to_stop > 0 and frames_to_stop <= 14, "Braking is floaty: %d frames to stop" % frames_to_stop)
	_check(player.global_position.distance_to(stop_from) < 1.3, "Stop slides too far: %.2f m" % player.global_position.distance_to(stop_from))
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	for _i in 60:
		await physics_frame
	_check(player.sprinting and _flat_speed() > GoatPlayer.SPRINT_SPEED * 0.93, "Sprint did not reach speed: %.2f" % _flat_speed())
	_release_all()


func _footfalls_over(seconds: float) -> int:
	footfalls = 0
	var frames := int(seconds * 60.0)
	for _i in frames:
		await physics_frame
	return footfalls


func _test_footfalls() -> void:
	await _settle_at(0.0, 40.0)
	_key(KEY_W, true)
	for _i in 40:
		await physics_frame
	var walk := await _footfalls_over(3.0)
	_key(KEY_SHIFT, true)
	for _i in 30:
		await physics_frame
	var sprint := await _footfalls_over(3.0)
	_key(KEY_SHIFT, false)
	player.set_crouched(true)
	for _i in 40:
		await physics_frame
	var crouch := await _footfalls_over(3.0)
	_release_all()
	# Noise fires per footfall for every posture that carries any radius; compare cadence.
	_check(sprint > walk, "Sprint footfalls (%d) should outpace walking (%d)" % [sprint, walk])
	_check(walk > crouch, "Crouch footfalls (%d) should be slower than walking (%d)" % [crouch, walk])
	player.set_crouched(false)


func _test_ceiling() -> void:
	await _settle_at(0.0, 30.0)
	player.set_crouched(true)
	for _i in 20:
		await physics_frame
	_check(player.crouched and player.collider_shape.height < 1.8, "Crouch did not shrink the body")
	var slab := StaticBody3D.new()
	slab.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	shape.shape = box
	slab.add_child(shape)
	mission.add_child(slab)
	slab.global_position = player.global_position + Vector3(0.0, 0.62, 0.0)
	await physics_frame
	await physics_frame
	player.set_crouched(false)
	for _i in 20:
		await physics_frame
	_check(player.crouched, "Stood up inside a low ceiling")
	slab.queue_free()
	await physics_frame
	await physics_frame
	for _i in 20:
		await physics_frame
	_check(not player.crouched, "Never stood up once the ceiling cleared")


func _ledge(height: float, distance: float) -> StaticBody3D:
	var ground := WorldBuilder.height_at(0.0, 36.0 - distance)
	var ledge := StaticBody3D.new()
	ledge.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, height + 1.0, 0.8)
	shape.shape = box
	ledge.add_child(shape)
	mission.add_child(ledge)
	ledge.global_position = Vector3(0.0, ground + height - (height + 1.0) * 0.5, 36.0 - distance)
	return ledge


func _test_steps() -> void:
	await _settle_at(0.0, 36.0)
	var low := _ledge(0.3, 2.4)
	await physics_frame
	_key(KEY_W, true)
	for _i in 120:
		await physics_frame
	_release_all()
	_check(player.global_position.z < 36.0 - 3.0, "Could not step up a 0.3 m ledge: z=%.2f" % player.global_position.z)
	low.queue_free()
	await physics_frame
	await _settle_at(0.0, 36.0)
	var wall := _ledge(0.9, 2.4)
	await physics_frame
	_key(KEY_W, true)
	for _i in 120:
		await physics_frame
	_release_all()
	_check(player.global_position.z > 36.0 - 2.4, "Walked up a 0.9 m wall like a stair: z=%.2f" % player.global_position.z)
	wall.queue_free()
	await physics_frame


func _test_landing() -> void:
	await _settle_at(0.0, 34.0)
	player.global_position.y += 0.4
	player.velocity = Vector3.ZERO
	var small := 0.0
	for _i in 50:
		await physics_frame
		await process_frame
		small = minf(small, player.landing_offset)
	await _settle_at(0.0, 34.0)
	player.global_position.y += 7.0
	var hard := 0.0
	var noticed_camera := false
	for _i in 90:
		await physics_frame
		await process_frame
		hard = minf(hard, player.landing_offset)
		noticed_camera = noticed_camera or player.head.position.y < GoatPlayer.STAND_HEAD - 0.06
	_check(hard < small - 0.05, "Hard landing dip (%.3f) should exceed a hop (%.3f)" % [hard, small])
	_check(noticed_camera, "Camera did not dip on a long fall")
	for _i in 90:
		await process_frame
	_check(absf(player.landing_offset) < 0.01, "Landing dip did not recover")


func _test_slope() -> void:
	# A walk down the trail on the real terrain keeps the goat on the ground and
	# moving steadily; snap and slope handling must not jitter or stick.
	await _settle_at(0.0, 42.0)
	_key(KEY_W, true)
	var grounded := 0
	var frames := 240
	var worst_step := 0.0
	var previous := player.global_position
	for _i in frames:
		await physics_frame
		if player.is_on_floor():
			grounded += 1
		worst_step = maxf(worst_step, absf(player.global_position.y - previous.y))
		previous = player.global_position
	_release_all()
	_check(float(grounded) / frames > 0.9, "Lost the ground while walking the trail: %d/%d frames" % [grounded, frames])
	_check(worst_step < 0.25, "Vertical pop of %.2f m walking the trail" % worst_step)
	_check(player.global_position.z < 40.0, "Barely advanced walking the trail: z=%.2f" % player.global_position.z)


func _test_weapon_rig() -> void:
	var view := player.view
	view.cue.connect(func(sound: String, _volume: float) -> void: cues.append(sound))
	view.casing_ejected.connect(func(_at: Transform3D, _velocity: Vector3) -> void: casings += 1)
	view.magazine_dropped.connect(func(_at: Transform3D, _velocity: Vector3) -> void: drops += 1)
	view.cancel_gesture()
	view.play_reload(GoatPlayer.RELOAD_SECONDS)
	var elapsed := 0.0
	while elapsed < GoatPlayer.RELOAD_SECONDS + 0.05:
		view.tick(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	_check(view.gesture == WeaponView.Gesture.NONE, "Reload gesture outlasts RELOAD_SECONDS")
	for expected in ["reload", "mag_out", "mag_in", "bolt_open", "bolt_close"]:
		_check(cues.has(expected), "Reload never cued '%s': %s" % [expected, cues])
	_check(drops == 1, "Reload should drop exactly one magazine, got %d" % drops)
	_check(cues.find("mag_out") < cues.find("mag_in") and cues.find("mag_in") < cues.find("bolt_close"), "Reload cues out of order: %s" % [cues])
	player.suppress_fire_until_release = false
	player.fire_cooldown = 0.0
	player.ammo = GoatPlayer.MAGAZINE_SIZE
	player._shoot()
	for _i in 30:
		view.tick(1.0 / 60.0)
	_check(casings == 1, "A shot should eject one casing, got %d" % casings)
	_check(player.ammo == GoatPlayer.MAGAZINE_SIZE - 1, "Shot did not spend a round")
	# ADS aligns the rear sight top on the optical axis.
	view.ads = 1.0
	for _i in 4:
		view.tick(0.016)
	_check(absf(view.position.x) < 0.004 and absf(view.position.y) < 0.02, "ADS pose is off the optical axis: %s" % view.position)
	view.ads = 0.0


func _test_effect_pools() -> void:
	var fx := player.fx
	for i in CombatFX.DECAL_POOL * 3:
		fx.impact(Vector3(float(i % 9) * 0.3, 0.1, 30.0 - float(i) * 0.05), Vector3.UP, "snow", true)
	_check(fx.decal_count() <= CombatFX.DECAL_POOL, "Bullet-hole pool exceeded its cap: %d" % fx.decal_count())
	_check(fx.decal_count() == CombatFX.DECAL_POOL, "Bullet-hole pool did not fill: %d" % fx.decal_count())
	var wood := {"collider": null}
	_check(CombatFX.surface_of(wood) == "rock", "Unknown hits default to rock")
	var terrain := StaticBody3D.new()
	terrain.name = "TerrainBody"
	_check(CombatFX.surface_of({"collider": terrain, "normal": Vector3.UP}) == "snow", "Flat terrain should read as snow")
	_check(CombatFX.surface_of({"collider": terrain, "normal": Vector3(0.9, 0.3, 0.0).normalized()}) == "rock", "Steep terrain should read as rock")
	terrain.free()
