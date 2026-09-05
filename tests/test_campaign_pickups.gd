extends SceneTree
## A named bell must rest on the authored surface, not under a raised dais.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var mission: Node3D = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
	await physics_frame
	var failures: Array[String] = []
	var space := mission.get_world_3d().direct_space_state
	for enemy in mission.enemies:
		for collider in enemy.get_children():
			if not collider is CollisionShape3D:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = collider.shape
			query.transform = collider.global_transform
			query.collision_mask = 1
			query.exclude = [mission.player.get_rid()]
			for hit in space.intersect_shape(query):
				failures.append("%s starts inside %s" % [enemy.name, hit.collider.name])
	var at := Vector3(-9.0, 4.144839, -31.59594)
	mission._drop_pouch(at, 5)
	var pouch: MeshInstance3D = mission.pouches.back().node
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 8.0, at - Vector3.UP, 1, [mission.player.get_rid()])
	var surface := space.intersect_ray(ray)
	for elapsed in [0.0, 1.0, 3.0]:
		mission._update_pouches(0.016, elapsed)
		if pouch.position.y < surface.position.y + 0.2:
			failures.append("Bell is buried under MotherBellDais at t=%s" % elapsed)
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("Campaign pickup test passed: clear enemy spawns and bells above authored surfaces")
		quit()
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
