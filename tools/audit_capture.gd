extends SceneTree
## Audit harness: player-height frames of every biome, enemies up close, the
## carbine, and a live firefight. Output goes to art_direction/audit/.

const OUT := "res://art_direction/audit/final/"

func _init() -> void:
	call_deferred("run")


func _shot(mission: Node3D, name: String, frames := 40) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("saved ", name)


func _place(mission: Node3D, x: float, z: float, yaw: float, pitch: float) -> void:
	mission.player.global_position = Vector3(x, WorldBuilder.height_at(x, z) + 1.2, z)
	mission.player.rotation.y = yaw
	mission.player.pitch = pitch
	mission.player.velocity = Vector3.ZERO
	mission._update_zone()
	mission.chapter_title.visible = false
	mission.chapter_line.visible = false


func run() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	var views := [
		["w1_trailhead", 0.0, 34.0, 0.0, 0.05],
		["w2_trail_mid", 3.0, 24.0, 0.3, 0.0],
		["w3_fold_close", 0.0, 8.0, 0.0, 0.0],
		["w4_side_wall", 0.0, 12.0, 1.57, 0.0],
		["w5_look_up", 0.0, 20.0, 0.0, 0.7],
		["w6_look_down", 0.0, 20.0, 0.0, -0.9],
		["c1_shrine", -5.5, -17.0, 0.0, 0.1],
		["c2_bell", -3.0, -24.0, 0.5, 0.15],
		["c3_ravine", 0.0, -45.0, 0.0, 0.05],
		["c4_side", 0.0, -50.0, -1.57, 0.0],
		["i1_approach", 0.0, -70.0, 0.0, 0.15],
		["i2_gate", 0.0, -84.0, 0.0, 0.2],
		["i3_court", 0.0, -96.0, 0.0, 0.1],
		["i4_court_back", 0.0, -96.0, 3.14, 0.0],
	]
	for v in views:
		_place(mission, v[1], v[2], v[3], v[4])
		await _shot(mission, v[0])
	# enemies close up
	for i in [0, 1, 2, 7, 9]:
		var e: Node3D = mission.enemies[i]
		var p: Vector3 = e.global_position
		var back: Vector3 = Vector3(0, 0, 1)
		_place(mission, p.x, p.z + 4.5, 0.0, 0.05)
		await _shot(mission, "e%d_%s" % [i, e.kind if "kind" in e else "x"], 20)
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	quit()
