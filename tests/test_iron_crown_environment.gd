extends SceneTree


const MODEL_PATH := "res://assets/environment/iron_crown/iron_crown_bell_abbey_blockout.glb"
const PREVIEW_PATH := "res://art_direction/iron_crown/iron_crown_preview.tscn"


func _init() -> void:
	call_deferred("run_test")


func fail(message: String) -> void:
	push_error(message)
	quit(1)


func run_test() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		fail("Iron Crown GLB did not import")
		return
	var abbey := packed.instantiate()
	root.add_child(abbey)
	await process_frame

	var required_landmarks := [
		"NinefoldTower_body",
		"NinefoldBellGable",
		"FoundingBell_body",
		"IronThroat_Arch",
		"IronThroat_vertical_04",
		"BrokenNave_Back",
		"GateScaffold_deck_2",
		"BellthornAbbey_trunk",
		"TerraceThree",
	]
	for landmark in required_landmarks:
		if abbey.find_child(landmark, true, false) == null:
			fail("Missing Iron Crown landmark: %s" % landmark)
			return

	var mesh_count := 0
	var surface_count := 0
	var vertex_count := 0
	var combined := AABB()
	var has_bounds := false
	for node in abbey.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		mesh_count += 1
		for surface in mesh_instance.mesh.get_surface_count():
			surface_count += 1
			vertex_count += mesh_instance.mesh.surface_get_array_len(surface)
		var bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if not has_bounds:
			combined = bounds
			has_bounds = true
		else:
			combined = combined.merge(bounds)

	if mesh_count < 8 or surface_count < 14 or vertex_count < 12000:
		fail("Iron Crown blockout is incomplete: %d meshes, %d surfaces, %d vertices" % [mesh_count, surface_count, vertex_count])
		return
	var collision_count := abbey.find_children("*", "StaticBody3D", true, false).size()
	if collision_count < 4:
		fail("Iron Crown traversal collision did not import: %d bodies" % collision_count)
		return
	if not has_bounds or combined.size.x < 45.0 or combined.size.y < 40.0 or combined.size.z < 75.0:
		fail("Iron Crown scale is wrong: %s" % combined.size)
		return
	if load(PREVIEW_PATH) == null:
		fail("Iron Crown live review scene did not load")
		return

	print("Iron Crown environment test passed: %d meshes, %d surfaces, %d vertices, %d collision bodies, bounds %s" % [mesh_count, surface_count, vertex_count, collision_count, combined.size])
	abbey.queue_free()
	await process_frame
	quit()
