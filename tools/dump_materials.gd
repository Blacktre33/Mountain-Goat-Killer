extends SceneTree
## Lists every mesh surface in the biome GLBs with its material and how much of
## the mesh it covers, to spot flat untextured colours.
## Usage: Godot --headless --path . --script res://tools/dump_materials.gd -- <res://glb> ...

func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var scene: PackedScene = load(path)
		var node := scene.instantiate()
		print("== ", path)
		var stats := {}
		var stack := [node]
		while stack:
			var current: Node = stack.pop_back()
			stack.append_array(current.get_children())
			if not (current is MeshInstance3D and current.mesh):
				continue
			var mesh: Mesh = current.mesh
			for i in mesh.get_surface_count():
				var material := mesh.surface_get_material(i) as BaseMaterial3D
				var key := "none"
				if material:
					key = "%s | col=%s tex=%s nrm=%s" % [material.resource_name, material.albedo_color.to_html(false), material.albedo_texture != null, material.normal_texture != null]
				var arrays := mesh.surface_get_arrays(i)
				var verts: int = arrays[Mesh.ARRAY_VERTEX].size()
				stats[key] = stats.get(key, [0, 0])
				stats[key][0] += 1
				stats[key][1] += verts
		for key in stats:
			print("  %-90s surfaces=%d verts=%d" % [key, stats[key][0], stats[key][1]])
		node.free()
	quit()
