extends SceneTree
## Surface audit harness: walks the route at player height and saves frames of
## floor, walls and props. Usage:
##   Godot --path . --script res://tools/surface_capture.gd -- <tag> [prefix]
## Frames land in art_direction/audit/surfaces/<tag>/. The optional prefix
## limits the run to views whose name starts with it (for example "b0").

const OUT := "res://art_direction/audit/surfaces/"

## name, x, z, yaw (0 faces -z, positive turns left), pitch
const ROUTE := [
	["a01_trail_start", 0.0, 42.0, 0.0, -0.05],
	["a02_trail_floor", 1.0, 36.0, 0.25, -0.55],
	["a03_sign_lantern", -1.0, 33.0, 0.4, 0.0],
	["a04_logs_right", 1.5, 27.0, -1.1, -0.1],
	["a05_float_boxes", 0.0, 31.0, 0.0, -0.15],
	["a06_float_boxes_b", 2.0, 24.0, 0.45, -0.1],
	["a07_blood_tracks", 0.0, 29.0, 0.0, -0.7],
	["a08_fold_mouth", 0.0, 16.0, 0.0, 0.0],
	["a09_fold_wall_west", 0.0, 8.0, 1.5, -0.05],
	["a10_fold_wall_east", 0.0, 8.0, -1.5, -0.05],
	["a11_fold_inside", 0.0, 2.0, 0.0, 0.0],
	["a12_fold_trough", 0.0, 9.0, 1.3, -0.25],
	["a13_fold_rack", 0.0, 3.0, 0.0, 0.2],
	["a14_fold_shelter", 2.0, 8.0, -1.2, 0.0],
	["a15_fold_floor_ash", 0.0, 0.5, 0.0, -0.8],
	["a16_ice_seam", -2.0, -5.0, 0.0, -0.75],
	["b01_ascent_start", 0.0, -9.0, 0.0, 0.05],
	["b02_shrine_far", 0.0, -14.0, 0.0, 0.1],
	["b03_shrine_front", -5.5, -17.0, 0.0, 0.1],
	["b04_shrine_steps", -5.0, -20.0, 0.0, -0.3],
	["b05_shrine_left_spikes", -9.5, -19.0, 0.6, -0.05],
	["b06_shrine_right_spikes", -2.0, -19.0, -0.6, -0.05],
	["b07_shrine_bell", -6.0, -23.0, 0.0, 0.5],
	["b08_shrine_side", -12.0, -28.0, -1.5, 0.0],
	["b09_shrine_back", -6.0, -36.0, 3.14, 0.1],
	["b10_carrion_floor", 2.0, -30.0, 0.0, -0.8],
	["b11_carrion_stains", 6.0, -21.0, 1.0, -0.5],
	["c01_ravine_long", 0.0, -42.0, 0.0, 0.05],
	["c02_ravine_wall_west", 0.0, -50.0, 1.5, 0.0],
	["c03_ravine_wall_east", 0.0, -50.0, -1.5, 0.0],
	["c04_catapult", -1.0, -44.0, 0.5, 0.0],
	["c05_ascent_floor", 0.0, -58.0, 0.0, -0.75],
	["c06_ascent_mid", 0.0, -62.0, 0.0, 0.1],
	["d01_crown_approach", 0.0, -72.0, 0.0, 0.15],
	["d02_crown_terrace", 0.0, -78.0, 0.0, 0.25],
	["d03_crown_arches", 0.0, -82.0, 0.3, 0.2],
	["d04_crown_wall_west", 0.0, -80.0, 1.5, 0.05],
	["d05_crown_wall_east", 0.0, -80.0, -1.5, 0.05],
	["d06_gate", 0.0, -88.0, 0.0, 0.2],
	["d07_gate_frame_close", 3.0, -90.0, 0.7, 0.15],
	["d08_gate_floor", 0.0, -86.0, 0.0, -0.8],
	["e01_court_entry", 0.0, -96.0, 0.0, 0.1],
	["e02_court_floor", 0.0, -98.0, 0.0, -0.8],
	["e03_court_back", 0.0, -96.0, 3.14, 0.0],
	["e04_court_wall_west", 0.0, -100.0, 1.5, 0.0],
	["e05_court_wall_east", 0.0, -100.0, -1.5, 0.0],
	["e06_court_niches", 0.0, -100.0, 0.0, 0.25],
	["e07_court_cage", 5.0, -104.0, 0.6, 0.0],
	["f01_court_props_west", 0.0, -100.0, 0.9, 0.05],
	["f02_court_props_east", 0.0, -100.0, -0.9, 0.05],
	["f03_court_far", 0.0, -100.0, 3.14, 0.1],
	["f04_lantern_close", -2.0, 30.0, 0.35, 0.15],
	["f05_logpile", 3.2, 26.0, -1.5, -0.1],
	["f06_lantern_post", -0.6, 33.0, 0.7, 0.25],
]


func _init() -> void:
	call_deferred("run")


func _shot(tag_dir: String, view_name: String, frames := 34) -> void:
	for _i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + tag_dir + "/" + view_name + ".png")
	print("saved ", view_name, " fps=", Engine.get_frames_per_second())


func _place(mission: Node3D, x: float, z: float, yaw: float, pitch: float) -> void:
	mission.player.global_position = Vector3(x, WorldBuilder.height_at(x, z) + 1.2, z)
	mission.player.rotation.y = yaw
	mission.player.pitch = pitch
	mission.player.velocity = Vector3.ZERO
	mission._update_zone()
	mission.chapter_title.visible = false
	mission.chapter_line.visible = false


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var tag: String = args[0] if args.size() > 0 else "before"
	var only: String = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + tag))
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	mission._set_hud_visible(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
		enemy.visible = false
	for v in ROUTE:
		if only != "" and not String(v[0]).begins_with(only):
			continue
		_place(mission, v[1], v[2], v[3], v[4])
		await _shot(tag, v[0])
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	quit()
