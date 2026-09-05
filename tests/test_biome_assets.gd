extends SceneTree


const TREES := [
	"res://assets/environment/vegetation/widowpine_tree_a.glb",
	"res://assets/environment/vegetation/widowpine_tree_b.glb",
	"res://assets/environment/vegetation/widowpine_tree_c.glb",
	"res://assets/environment/vegetation/carrion_dead_pine.glb",
]

const HERO_ENVIRONMENTS := [
	"res://assets/environment/widowpine/widowpine_broken_fold.glb",
	"res://assets/environment/carrion_cut/carrion_cut_mother_bell.glb",
]

const ROCKS := [
	"res://assets/environment/rocks/ravine_boulder_a.glb",
	"res://assets/environment/rocks/ravine_boulder_b.glb",
	"res://assets/environment/rocks/ravine_boulder_c.glb",
	"res://assets/environment/rocks/ravine_cliff_a.glb",
	"res://assets/environment/rocks/ravine_cliff_b.glb",
	"res://assets/environment/rocks/ravine_cliff_c.glb",
]

const VARKAS_HERO := "res://assets/wolf/varkas_wolverine.glb"


func _init() -> void:
	call_deferred("run_test")


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func run_test() -> void:
	for path in TREES:
		var packed := load(path) as PackedScene
		if packed == null:
			fail("Biome tree did not import: %s" % path)
			return
		var tree := packed.instantiate()
		root.add_child(tree)
		await process_frame
		var mesh_instance := tree.find_child("*", true, false) as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			fail("Biome tree has no mesh: %s" % path)
			return
		var bounds := mesh_instance.mesh.get_aabb()
		if bounds.size.y < 15.0 or bounds.size.y > 28.0 or bounds.size.x > 18.0 or bounds.size.z > 18.0:
			fail("Biome tree bounds are unsafe for scattering: %s => %s" % [path, bounds.size])
			return
		var material_report := []
		for surface in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.mesh.surface_get_material(surface)
			if mat:
				material_report.append("%s transparency=%s texture=%s" % [
					mat.resource_name,
					mat.transparency if mat is BaseMaterial3D else -1,
					(mat as BaseMaterial3D).albedo_texture != null if mat is BaseMaterial3D else false,
				])
		print("%s bounds=%s materials=%s" % [path.get_file(), bounds.size, material_report])
		tree.queue_free()
		await process_frame
	for path in ROCKS:
		var packed := load(path) as PackedScene
		if packed == null:
			fail("Ravine rock did not import: %s" % path)
			return
		var rock := packed.instantiate()
		root.add_child(rock)
		await process_frame
		var mesh_instance := rock.find_child("*", true, false) as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			fail("Ravine rock has no mesh: %s" % path)
			return
		var bounds := mesh_instance.mesh.get_aabb()
		if bounds.size.x < 1.0 or bounds.size.y < 1.0 or bounds.size.z < 1.0 or bounds.size.x > 4.0 or bounds.size.y > 4.0 or bounds.size.z > 4.0:
			fail("Ravine rock bounds are unsafe for scattering: %s => %s" % [path, bounds.size])
			return
		var material := mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
		if material == null or material.albedo_texture == null or not material.normal_enabled:
			fail("Ravine rock lost its PBR surface: %s" % path)
			return
		print("%s bounds=%s PBR=true" % [path.get_file(), bounds.size])
		rock.queue_free()
		await process_frame
	for path in HERO_ENVIRONMENTS:
		var packed := load(path) as PackedScene
		if packed == null:
			fail("Biome hero environment did not import: %s" % path)
			return
		var environment := packed.instantiate()
		root.add_child(environment)
		await process_frame
		var meshes := environment.find_children("*", "MeshInstance3D", true, false)
		var bodies := environment.find_children("*", "StaticBody3D", true, false)
		var surface_count := 0
		var vertex_count := 0
		for node in meshes:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in mesh_instance.mesh.get_surface_count():
				surface_count += 1
				vertex_count += mesh_instance.mesh.surface_get_array_len(surface)
		if meshes.is_empty() or surface_count < 6 or vertex_count < 3000:
			fail("Biome hero environment is incomplete: %s has %d meshes, %d surfaces, %d vertices" % [path, meshes.size(), surface_count, vertex_count])
			return
		if bodies.is_empty():
			fail("Biome hero environment has no traversal collision: %s" % path)
			return
		if path.contains("widowpine"):
			if vertex_count < 45000 or bodies.size() < 10:
				fail("Widowpine regressed below its rebuilt fold and traversal budget: %d vertices, %d bodies" % [vertex_count, bodies.size()])
				return
		if path.contains("carrion_cut"):
			if environment.find_child("MotherBell", true, false) == null:
				fail("Carrion Cut hero environment lost the interactive MotherBell landmark")
				return
			if vertex_count < 50000 or bodies.size() < 10:
				fail("Carrion Cut regressed below its rebuilt shrine and traversal budget: %d vertices, %d bodies" % [vertex_count, bodies.size()])
				return
		print("%s meshes=%d surfaces=%d vertices=%d collision_bodies=%d" % [path.get_file(), meshes.size(), surface_count, vertex_count, bodies.size()])
		environment.queue_free()
		await process_frame
	var varkas_packed := load(VARKAS_HERO) as PackedScene
	if varkas_packed == null:
		fail("Varkas hero mesh did not import")
		return
	var varkas := varkas_packed.instantiate()
	root.add_child(varkas)
	await process_frame
	var varkas_vertices := 0
	for node in varkas.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			for surface in mesh_instance.mesh.get_surface_count():
				varkas_vertices += mesh_instance.mesh.surface_get_array_len(surface)
	var varkas_anim := varkas.find_child("*", true, false) as AnimationPlayer
	for node in varkas.find_children("*", "AnimationPlayer", true, false):
		varkas_anim = node as AnimationPlayer
		break
	if varkas_vertices < 5000 or varkas_anim == null or varkas_anim.get_animation_list().size() < 8:
		fail("Varkas hero lost geometry or inherited animation: vertices=%d animations=%d" % [varkas_vertices, varkas_anim.get_animation_list().size() if varkas_anim else 0])
		return
	print("varkas_wolverine.glb vertices=%d animations=%d" % [varkas_vertices, varkas_anim.get_animation_list().size()])
	varkas.queue_free()
	await process_frame
	print("Biome asset tests passed")
	quit()
