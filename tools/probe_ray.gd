extends SceneTree
## Casts a ray through a screen pixel of a view (x z yaw pitch px py) and prints
## what it hits, to trace a stray object seen in a captured frame.
## Usage: Godot --path . --script res://tools/probe_ray.gd -- x z yaw pitch px py

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	var x := float(args[0])
	var z := float(args[1])
	mission.player.global_position = Vector3(x, WorldBuilder.height_at(x, z) + 1.2, z)
	mission.player.rotation.y = float(args[2])
	mission.player.pitch = float(args[3])
	mission.player.velocity = Vector3.ZERO
	for _i in 12:
		await process_frame
	var camera := root.get_viewport().get_camera_3d()
	var pixel := Vector2(float(args[4]), float(args[5]))
	var from := camera.project_ray_origin(pixel)
	var to := from + camera.project_ray_normal(pixel) * 80.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF)
	var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
	print("hit: ", hit.get("position"), " collider: ", hit.get("collider"))
	if hit.has("collider"):
		var node: Node = hit.collider
		print("path: ", node.get_path())
		for child in node.get_children():
			print("  child: ", child.name, " ", child.get_class())
	mission.audio.shutdown()
	quit()
