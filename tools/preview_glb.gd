extends SceneTree
## Renders a GLB from three angles on a neutral backdrop and prints its bounds.
## Usage: Godot --path . --script res://tools/preview_glb.gd -- res://path/model.glb <out.png>

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: PackedScene = load(args[0])
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	var bounds := AABB()
	var first := true
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D and node.mesh:
			var box: AABB = node.global_transform * node.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	print("bounds pos=", bounds.position, " size=", bounds.size)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.36, 0.42)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	environment.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.6
	root.add_child(sun)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var center := bounds.get_center()
	var radius := bounds.size.length() * 0.85
	var image_out := Image.create(1920, 640, false, Image.FORMAT_RGB8)
	for i in 3:
		var angle := i * 1.9 + 0.5
		camera.position = center + Vector3(sin(angle) * radius, bounds.size.y * 0.15, cos(angle) * radius)
		camera.look_at(center)
		for _f in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		frame.convert(Image.FORMAT_RGB8)
		frame.resize(640, 640)
		image_out.blit_rect(frame, Rect2i(0, 0, 640, 640), Vector2i(i * 640, 0))
	image_out.save_png(args[1])
	quit()
