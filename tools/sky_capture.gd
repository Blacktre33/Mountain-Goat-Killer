extends SceneTree
## Sky and lighting review: player-height frames in all three biomes looking
## forward, up, down and sideways, plus a frame-time measurement per biome.
## Usage: Godot --path . --script res://tools/sky_capture.gd -- <tag> [hud]
## Output goes to art_direction/audit/sky/<tag>_<view>.png

const OUT := "res://art_direction/audit/sky/"

var tag := "after"
var only := ""


func _init() -> void:
	call_deferred("run")


func _shot(mission: Node3D, name: String, frames := 45) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + tag + "_" + name + ".png")
	print("saved ", name)


func _place(mission: Node3D, biome: String, x: float, z: float, yaw: float, pitch: float) -> void:
	mission.player.global_position = Vector3(x, WorldBuilder.height_at(x, z) + 1.2, z)
	mission.player.rotation.y = yaw
	mission.player.pitch = pitch
	mission.player.velocity = Vector3.ZERO
	mission._update_zone()
	mission.current_biome = biome
	WorldBuilder.set_biome(mission.world, biome, true)
	mission.chapter_title.visible = false
	mission.chapter_line.visible = false


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = args[0]
	if args.size() > 1:
		only = args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	mission.hud.visible = "hud" in args
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	var views := [
		["w1", "whitewood", 0.0, 34.0, 0.0, 0.05],
		["w5", "whitewood", 0.0, 20.0, 0.0, 0.7],
		["w_moon", "whitewood", 0.0, 26.0, 0.0, 0.45],
		["w_side", "whitewood", 0.0, 12.0, 1.57, 0.3],
		["w6", "whitewood", 0.0, 20.0, 0.0, -0.9],
		["w2", "whitewood", 3.0, 24.0, 0.3, 0.0],
		["w3", "whitewood", 0.0, 8.0, 0.0, 0.0],
		["c1", "carrion_cut", -5.5, -17.0, 0.0, 0.1],
		["c2", "carrion_cut", -3.0, -24.0, 0.5, 0.15],
		["c3", "carrion_cut", 0.0, -45.0, 0.0, 0.05],
		["c_up", "carrion_cut", 0.0, -45.0, 0.0, 0.55],
		["c_side", "carrion_cut", 0.0, -50.0, -1.57, 0.25],
		["i1", "iron_crown", 0.0, -70.0, 0.0, 0.15],
		["i_up", "iron_crown", 0.0, -70.0, 0.0, 0.6],
		["i2", "iron_crown", 0.0, -84.0, 0.0, 0.2],
		["i3", "iron_crown", 0.0, -96.0, 0.0, 0.1],
		["i4", "iron_crown", 0.0, -96.0, 3.14, 0.0],
		["i_court_up", "iron_crown", 0.0, -96.0, 0.0, 0.7],
	]
	var frame_times := {}
	for v in views:
		if only != "" and only != "hud" and not v[0].begins_with(only):
			continue
		_place(mission, v[1], v[2], v[3], v[4], v[5])
		await _shot(mission, v[0])
	# Frame time with vsync off: average wall-clock milliseconds over 240 frames per biome.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.scaling_3d_scale = 2.0 # 4x the pixels so the GPU, not vsync, sets the frame time
	mission.hud.visible = true
	for biome in [["whitewood", 0.0, 26.0, 0.0, 0.1], ["carrion_cut", 0.0, -45.0, 0.0, 0.05], ["iron_crown", 0.0, -96.0, 0.0, 0.1]]:
		_place(mission, biome[0], biome[1], biome[2], biome[3], biome[4])
		for _i in 60:
			await process_frame
		# force_draw without a buffer swap is not throttled by vsync, so it times the renderer.
		var start := Time.get_ticks_usec()
		for _i in 240:
			RenderingServer.force_draw(false)
		frame_times[biome[0]] = "%.2f ms/frame" % ((Time.get_ticks_usec() - start) / 240000.0)
	print("FRAME_TIMES ", tag, " ", frame_times)
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	quit()
