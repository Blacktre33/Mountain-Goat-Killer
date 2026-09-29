extends SceneTree
## Lit studio views of the enemy glTF sources, used while iterating on the
## wolverine silhouette. Pass model paths after `--`, e.g.
##   Godot --path . --script res://tools/enemy_model_preview.gd -- res://assets/wolf/wolf.glb
## Output: art_direction/audit/model_<n>_<view>.png

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var paths: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("res://"):
			paths.append(argument)
	if paths.is_empty():
		paths = ["res://assets/wolf/wolf.glb", "res://assets/wolf/varkas_wolverine.glb"]
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.2, 0.22, 0.26)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.62, 0.7)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var index := 0
	for path in paths:
		var model: Node3D = load(path).instantiate()
		root.add_child(model)
		if model.find_child("Skeleton3D", true, false) == null:
			for child_index in model.get_child_count():
				(model.get_child(child_index) as Node3D).position.x = child_index * 0.9
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player and player.has_animation("Idle"):
			player.play("Idle")
			player.seek(0.5, true)
			player.pause()
		var box := _bounds(model)
		var center := box.get_center()
		var radius := box.size.length() * 0.9
		for view in [["side", Vector3(1, 0.25, 0)], ["front", Vector3(0.3, 0.25, -1)], ["three_quarter", Vector3(1, 0.4, -1)]]:
			camera.global_position = center + (view[1] as Vector3).normalized() * radius
			camera.look_at(center)
			for _i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://art_direction/audit/model_%d_%s.png" % [index, view[0]])
		model.queue_free()
		index += 1
	quit()


func _bounds(node: Node3D) -> AABB:
	var skeleton := node.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		var box := AABB()
		var first := true
		for found in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := found as MeshInstance3D
			var world_box: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
			box = world_box if first else box.merge(world_box)
			first = false
		return box
	var bones := AABB(skeleton.global_transform * skeleton.get_bone_global_pose(0).origin, Vector3.ZERO)
	for bone in skeleton.get_bone_count():
		bones = bones.expand(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)
	return bones
