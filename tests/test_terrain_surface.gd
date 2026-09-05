extends SceneTree
## Godot displays clockwise faces. Terrain must face the sky while its shading
## normals point upward; physics can still work when the render faces are wrong.

func _init() -> void:
	call_deferred("run_test")


func run_test() -> void:
	var world := Node3D.new()
	root.add_child(world)
	WorldBuilder._build_terrain(world)
	var wrong_faces := 0
	var triangles := 0
	for child in world.get_children():
		if not child is MeshInstance3D:
			continue
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in range(0, vertices.size(), 3):
			var cross: Vector3 = (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
			if cross.dot(normals[index]) >= 0.0:
				wrong_faces += 1
			triangles += 1
	var render_ok := true
	if "--render-terrain-proof" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			push_error("The terrain rendering proof requires a graphical renderer")
			render_ok = false
		else:
			render_ok = await check_rendered_surface(world)
	world.queue_free()
	await process_frame
	if wrong_faces > 0 or not render_ok:
		push_error("Terrain faces point away from the playable surface: %d / %d" % [wrong_faces, triangles])
		quit(1)
	else:
		print("Terrain surface test passed: %d upward-facing triangles" % triangles)
		quit()


func count_surface_pixels(image: Image) -> int:
	var samples := 0
	for y in range(image.get_height() / 3, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			if color.r > 0.7 and color.g > 0.12 and color.g < 0.6 and color.b < 0.1:
				samples += 1
	return samples


func check_rendered_surface(world: Node3D) -> bool:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0.0, WorldBuilder.height_at(0.0, 18.0) + 1.6, 18.0)
	camera.rotation.x = -0.25
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	diagnostic.albedo_color = Color(1.0, 0.3, 0.0)
	for node in world.get_children():
		if node is MeshInstance3D:
			node.material_override = diagnostic
	await RenderingServer.frame_post_draw
	var front := count_surface_pixels(root.get_texture().get_image())
	diagnostic.cull_mode = BaseMaterial3D.CULL_DISABLED
	await process_frame
	await RenderingServer.frame_post_draw
	var both := count_surface_pixels(root.get_texture().get_image())
	print("Terrain rendering: front-face coverage=%d, double-sided coverage=%d" % [front, both])
	if front < 1000 or front < both * 0.95:
		push_error("Terrain disappears when ordinary back-face culling is enabled")
		return false
	return true
