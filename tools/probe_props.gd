extends SceneTree
## Lists every mesh instance under the built world whose bounds touch a given
## x/z window, so a stray prop seen in a frame can be traced to its source.
## Usage: Godot --headless --path . --script res://tools/probe_props.gd -- x0 x1 z0 z1

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var window := Rect2(float(args[0]), float(args[2]), float(args[1]) - float(args[0]), float(args[3]) - float(args[2]))
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	var stack: Array[Node] = [mission.world.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MultiMeshInstance3D:
			var multi := node as MultiMeshInstance3D
			for i in multi.multimesh.instance_count:
				var origin := multi.global_transform * multi.multimesh.get_instance_transform(i)
				if window.has_point(Vector2(origin.origin.x, origin.origin.z)):
					print("MULTI %s | mesh=%s | at %s scale %s" % [multi.name, multi.multimesh.mesh.resource_path.get_file(), origin.origin, origin.basis.get_scale()])
			continue
		var instance := node as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var box: AABB = instance.global_transform * instance.mesh.get_aabb()
		if box.size.length() > 30.0:
			continue
		if window.intersects(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)):
			var materials := []
			for i in instance.mesh.get_surface_count():
				var m := instance.get_active_material(i)
				materials.append(m.resource_name if m else "none")
			print("%s | mesh=%s | pos=%s size=%s | %s" % [instance.get_path(), instance.mesh.resource_path.get_file(), box.position, box.size, materials])
	quit()
