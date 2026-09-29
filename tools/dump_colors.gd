extends SceneTree
## Reports whether each imported GLB surface carries per-vertex colour and how
## much it varies (proves the Blender per-block tint survives the import).
## Usage: Godot --headless --path . --script res://tools/dump_colors.gd -- res://glb ...

func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var node: Node = (load(path) as PackedScene).instantiate()
		print("== ", path)
		var stack: Array[Node] = [node]
		while not stack.is_empty():
			var current: Node = stack.pop_back()
			stack.append_array(current.get_children())
			if not (current is MeshInstance3D and current.mesh):
				continue
			for i in current.mesh.get_surface_count():
				var arrays: Array = current.mesh.surface_get_arrays(i)
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				var material: Material = current.mesh.surface_get_material(i)
				var name: String = material.resource_name if material else "none"
				if colors.size() == 0:
					print("  %-40s no colour" % name)
					continue
				var lo := 9.0
				var hi := 0.0
				for c in colors:
					lo = minf(lo, c.r)
					hi = maxf(hi, c.r)
				print("  %-40s colours=%d red range %.2f..%.2f alpha0=%.2f" % [name, colors.size(), lo, hi, colors[0].a])
		node.free()
	quit()
