extends SceneTree
## Weapon, hands and HUD proof frames: hip, ADS, sprint, reload phases, firing with
## flash, low health. Needs a real window (not --headless).
##   Godot --path . --script res://tools/weapon_capture.gd
## Set CAPTURE_ONLY=<step> to render a single step. Output goes to
## art_direction/audit/weapon_*.png.

const OUT := "res://art_direction/audit/"

var mission: Node3D
var player: GoatPlayer


func _init() -> void:
	call_deferred("run")


func _shot(name: String, frames := 6) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("saved ", name)


func _place(x: float, z: float, yaw: float, pitch: float) -> void:
	player.global_position = Vector3(x, WorldBuilder.height_at(x, z) + 1.2, z)
	player.rotation.y = yaw
	player.pitch = pitch
	player.velocity = Vector3.ZERO
	mission._update_zone()
	mission.chapter_title.modulate.a = 0.0
	mission.chapter_line.modulate.a = 0.0
	mission.chapter_rule.modulate.a = 0.0
	mission.chapter_backdrop.modulate.a = 0.0


func _reset_pose() -> void:
	player.aiming = false
	player.sprinting = false
	player.reloading = false
	player.reload_generation += 1
	player.view.cancel_gesture()
	player.fire_cooldown = 0.0
	player.velocity = Vector3.ZERO
	player.ammo = GoatPlayer.MAGAZINE_SIZE
	player.health = 100
	player.health_changed.emit(100)


func run() -> void:
	mission = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	player = mission.player
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	_place(0.0, 34.0, 0.0, 0.05)
	player.suppress_fire_until_release = false
	player.set_physics_process(false)
	await create_timer(1.0).timeout
	var only: String = OS.get_environment("CAPTURE_ONLY")

	var steps := {
		"hip": func() -> void:
			await _shot("weapon_hip", 20),
		"ads": func() -> void:
			player.aiming = true
			await create_timer(0.6).timeout
			await _shot("weapon_ads", 4),
		"sprint": func() -> void:
			player.sprinting = true
			player.velocity = Vector3(0, 0, -8.4)
			await create_timer(0.6).timeout
			await _shot("weapon_sprint", 4),
		"reload1": func() -> void:
			player.ammo = 5
			player._reload()
			await create_timer(0.22).timeout
			await _shot("weapon_reload_1", 1),
		"reload2": func() -> void:
			player.ammo = 5
			player._reload()
			await create_timer(0.50).timeout
			await _shot("weapon_reload_2", 1),
		"reload3": func() -> void:
			player.ammo = 5
			player._reload()
			await create_timer(0.85).timeout
			await _shot("weapon_reload_3", 1),
		"fire": func() -> void:
			player._shoot()
			await process_frame
			await process_frame
			await _shot("weapon_fire", 0),
		"lowhealth": func() -> void:
			player.health = 100
			player.damage(78, player.global_position + Vector3(6.0, 0.0, -4.0))
			await create_timer(0.15).timeout
			await _shot("weapon_lowhealth", 2),
		"impacts": func() -> void:
			player.suppress_fire_until_release = false
			# Snow, a log stack (wood), a boulder (rock): a burst frame, then the decals.
			var targets := {"snow": Vector3(0.6, 0.0, 26.0), "wood": Vector3(4.0, 0.9, 16.5), "rock": Vector3(-7.5, 1.0, 14.0)}
			for key in targets:
				var from: Vector3 = targets[key] + Vector3(0.0, 0.0, 6.0)
				if key == "rock":
					from = targets[key] + Vector3(3.5, 0.0, 6.0)
				_place(from.x, from.z, 0.0, 0.0)
				player.set_physics_process(false)
				player.global_position.y = WorldBuilder.height_at(from.x, from.z) + 1.2
				var dir: Vector3 = targets[key] - player.camera.global_position
				dir.y = targets[key].y + WorldBuilder.height_at(targets[key].x, targets[key].z) - player.camera.global_position.y
				player.rotation.y = atan2(-dir.x, -dir.z)
				player.pitch = asin(dir.normalized().y)
				await create_timer(0.4).timeout
				for i in 3:
					player.fire_cooldown = 0.0
					player._shoot()
					await create_timer(0.03).timeout
				await _shot("fx_impact_" + key, 2)
			await create_timer(1.0).timeout
			var hit := player._cast(player.aim_origin(), player.aim_direction(), 50.0, 1)
			if hit:
				# Step up to the scar for a close look at the decals.
				var stand: Vector3 = hit.position + hit.normal * 0.9
				player.global_position = stand - Vector3(0.0, 0.66, 0.0)
				var look: Vector3 = hit.position - stand
				player.rotation.y = atan2(-look.x, -look.z)
				player.pitch = asin(look.normalized().y)
			await _shot("fx_decals_rock", 4),
		"bolt": func() -> void:
			player.suppress_fire_until_release = false
			player.fire_cooldown = 0.0
			player._shoot()
			await create_timer(0.07).timeout
			await _shot("weapon_bolt_open", 0)
			await create_timer(0.18).timeout
			await _shot("weapon_casing", 0),
		"hit": func() -> void:
			# Hit markers: a headshot (gold) and a kill (red, larger) on the crosshair.
			player.hit_confirmed.emit("headshot")
			await _shot("hud_hitmarker_headshot", 1)
			player.hit_confirmed.emit("kill")
			await _shot("hud_hitmarker_kill", 1),
		"hang": func() -> void:
			player.active = true
			player.hang_round()
			await create_timer(0.16).timeout
			await _shot("gesture_hang", 0)
			player.clear_hung(),
		"throw": func() -> void:
			player.view.play_throw(GoatPlayer.THROW_SECONDS)
			await create_timer(0.14).timeout
			await _shot("gesture_throw_windup", 0)
			await create_timer(0.12).timeout
			await _shot("gesture_throw_release", 0),
		"takedown": func() -> void:
			player.view.play_takedown()
			await create_timer(0.08).timeout
			await _shot("gesture_takedown_windup", 0)
			await create_timer(0.14).timeout
			await _shot("gesture_takedown_strike", 0),
		"wall": func() -> void:
			_place(0.0, 30.0, 0.0, 0.0)
			# Stand a step from the nearest rock so the short ray finds it.
			var rock := Vector3(-7.5, 0.0, 14.0)
			_place(-7.5, 15.5, 0.0, 0.0)
			player.global_position.y = WorldBuilder.height_at(-7.5, 15.5) + 1.2
			player.set_physics_process(true)
			await create_timer(0.8).timeout
			await _shot("gesture_wall", 2)
			player.set_physics_process(false),
		"decals": func() -> void:
			# Shallow bullet holes in the snow crust: a group, then a look from above them.
			player.suppress_fire_until_release = false
			_place(0.0, 30.0, 0.0, -0.36)
			player.set_physics_process(false)
			for i in 6:
				player.fire_cooldown = 0.0
				player.rotation.y = randf_range(-0.03, 0.03)
				player.pitch = randf_range(-0.42, -0.34)
				player._shoot()
				await create_timer(0.05).timeout
			await create_timer(1.2).timeout
			var hit := player._cast(player.aim_origin(), Vector3(0.0, -0.37, -1.0).normalized(), 30.0, 1)
			player.global_position += Vector3(0.0, 0.0, -2.8)
			player.global_position.y = WorldBuilder.height_at(player.global_position.x, player.global_position.z) + 1.2
			player.rotation.y = 0.0
			player.pitch = -1.15
			await _shot("fx_decals_snow", 4),
		"pause": func() -> void:
			mission.pause_overlay.visible = true
			await _shot("hud_pause", 3)
			mission.pause_overlay.visible = false,
		"chapter": func() -> void:
			mission._show_chapter("CARRION CUT  //  THE MOTHER BELL", "Rust-red stone and old kill-sites. The bell above the shrine still remembers every name.")
			await create_timer(1.6).timeout
			await _shot("hud_chapter", 2),
		"death": func() -> void:
			player.damage(500)
			await create_timer(1.3).timeout
			await _shot("hud_death", 2)
			mission._respawn(),
		"ending": func() -> void:
			mission.boss_awake = true
			mission.bells = Story.IRON_GATE_REQUIRED
			player.active = true
			mission.boss.set_physics_process(false)
			for i in 3:
				mission.boss.take_damage(mission.boss.max_health * 4)
				mission.boss.boss_transition_lock = 0.0
			player.global_position = mission.boss.global_position + Vector3(0.0, 0.0, 2.65)
			mission._update_zone()
			mission._update_prompt()
			mission._on_interact()
			await create_timer(2.0).timeout
			await _shot("hud_ending", 2),
	}
	for key in steps:
		if only != "" and only != key:
			continue
		_reset_pose()
		await create_timer(0.7).timeout
		await steps[key].call()
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	quit()
