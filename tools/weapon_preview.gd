extends SceneTree
## Turntable check of the viewmodel rig outside the game: side, top and front
## views of the carbine and hands at a chosen gesture time.
##   Godot --path . --script res://tools/weapon_preview.gd
## Output goes to art_direction/audit/weaponrig_*.png.

const OUT := "res://art_direction/audit/"


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.5, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	scene.add_child(sun)
	var camera := Camera3D.new()
	scene.add_child(camera)
	var view := WeaponView.new()
	scene.add_child(view)
	await process_frame
	view.position = Vector3.ZERO
	var views := {
		"side": [Vector3(2.0, 0.0, 0.0), Vector3.ZERO],
		"top": [Vector3(0.0, 2.0, 0.0), Vector3.ZERO],
		"front": [Vector3(0.0, 0.0, -2.0), Vector3.ZERO],
		"rear": [Vector3(0.9, 0.5, 1.2), Vector3.ZERO],
	}
	for key in views:
		for roll in ([0.0, PI * 0.5, PI, -PI * 0.5] if key == "rear" else [PI]):
			view.left_roll = roll
			view.right_roll = 0.0 if roll == PI else roll
			view.gesture = WeaponView.Gesture.NONE
			view.tick(0.016)
			view.position = Vector3.ZERO
			view.rotation = Vector3.ZERO
			var from: Vector3 = views[key][0]
			camera.global_position = from.normalized() * 1.7 + Vector3(0.0, -0.1, -0.1)
			camera.look_at(Vector3(0.0, -0.1, -0.2), Vector3.UP if key != "top" else Vector3.FORWARD)
			camera.fov = 45.0
			await process_frame
			await process_frame
			view.position = Vector3.ZERO
			view.rotation = Vector3.ZERO
			await RenderingServer.frame_post_draw
			var suffix := "" if key != "rear" else "_%d" % int(roll * 10.0)
			root.get_texture().get_image().save_png(OUT + "weaponrig_" + key + suffix + ".png")
			print("saved ", key, suffix)
	quit()
