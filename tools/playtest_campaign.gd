extends SceneTree
## Automated skilled-player probe. Real movement, collision, bullets, pickups,
## enemy AI and mission gates; no warps, health grants or direct damage calls.
## This diagnoses route/progression problems, not human difficulty or pacing.

var mission: Node3D
var player: GoatPlayer
var navigation := AStar3D.new()
var floors := {}
var held := {}
var deaths := 0
var shots := 0
var last_report := ""
var route: Array[Vector3] = []
var route_goal := Vector2i(999, 999)
var last_position := Vector3.ZERO
var stuck := 0
var progress_frame := 0
var phases_seen := {}
var reinforcement_count := 0
const CELL := 0.75
const KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE]

func _init() -> void:
	call_deferred("run")

func cell(at: Vector3) -> Vector2i:
	return Vector2i(roundi(at.x / CELL), roundi(at.z / CELL))

func key(code: int, pressed: bool) -> void:
	if held.get(code, false) == pressed:
		return
	held[code] = pressed
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func map_route() -> void:
	navigation.clear()
	floors.clear()
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	for x in range(-18, 19):
		for z in range(-159, 50):
			var id := Vector2i(x, z)
			var at := Vector3(x * CELL, 0.0, z * CELL)
			var base := WorldBuilder.height_at(at.x, at.z)
			var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x, base + 2.5, at.z), Vector3(at.x, base - 2.0, at.z), 1, [player.get_rid()])
			var floor_hit := space.intersect_ray(ray)
			var solid := floor_hit.is_empty()
			if not solid:
				at.y = floor_hit.position.y
				solid = floor_hit.normal.y < 0.7 or at.y - base > 1.5
				query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.0)
				solid = solid or not space.intersect_shape(query, 1).is_empty()
			if not solid:
				floors[id] = at
				navigation.add_point(point_id(id), at)
	# Free endpoint samples alone do not imply a walkable connection: the old
	# flat grid routed straight into the side of a raised terrace. Respect
	# floor height between cells and prevent diagonal cuts around solid corners.
	for id in floors:
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
			var neighbor: Vector2i = id + offset
			if not floors.has(neighbor):
				continue
			if offset.x != 0 and offset.y != 0:
				if not floors.has(id + Vector2i(offset.x, 0)) or not floors.has(id + Vector2i(0, offset.y)):
					continue
			var run: float = Vector2(offset).length() * CELL
			if absf(floors[id].y - floors[neighbor].y) <= run * 0.9:
				navigation.connect_points(point_id(id), point_id(neighbor))
	print("Campaign navigation: %d walkable samples" % floors.size())

func point_id(id: Vector2i) -> int:
	return (id.x + 18) * 209 + id.y + 159

func nearest_cell(at: Vector3) -> Vector2i:
	var best := cell(at)
	var distance := INF
	for x in range(best.x - 4, best.x + 5):
		for z in range(best.y - 4, best.y + 5):
			var id := Vector2i(x, z)
			if floors.has(id):
				var d: float = Vector2(floors[id].x - at.x, floors[id].z - at.z).length_squared()
				if d < distance:
					distance = d
					best = id
	return best

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Campaign input playback needs the graphical runtime for mouse capture")
		quit(1)
		return
	seed(9182)
	mission = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	player = mission.player
	await physics_frame
	map_route()
	last_position = player.global_position
	var was_open := false
	for frame in 18000:
		await physics_frame
		if mission.victory:
			break
		if mission.boss_awake:
			phases_seen[mission.boss.boss_phase] = true
		for enemy in mission.enemies:
			if enemy.name.begins_with("Varkas_Reinforcement_"):
				reinforcement_count = maxi(reinforcement_count, int(enemy.name.get_slice("_", 2)) + 1)
		if not player.active:
			deaths += 1
			print("Campaign death %d: bells=%d, position=%s" % [deaths, mission.bells, player.position])
			if deaths > 6:
				break
			mission._respawn()
			route_goal = Vector2i(999, 999)
		if mission.gate_open and not was_open:
			await physics_frame
			map_route()
			was_open = true
		var goal := Vector3(0.0, 0.0, -98.0)
		if not mission.bell_rung and mission.bells >= 4:
			goal = mission._bell_position()
		elif mission.bells < 8:
			goal = mission._nearest_stolen_bell()
			var closest := INF
			for pouch in mission.pouches:
				if pouch.bell >= 0 and player.global_position.distance_squared_to(pouch.node.position) < closest:
					closest = player.global_position.distance_squared_to(pouch.node.position)
					goal = pouch.node.position
		elif mission.boss_awake:
			goal = mission.boss.global_position
		mission._update_prompt()
		if mission.interact_target.get("kind", "") in ["bell", "boss_finish"]:
			mission._on_interact()
		var target: WolverineEnemy
		var target_distance := INF
		for enemy in mission.enemies:
			if enemy.dead or enemy.state == WolverineEnemy.State.DORMANT or enemy.execution_ready:
				continue
			var distance: float = player.global_position.distance_to(enemy.global_position)
			if distance < 32.0 and distance < target_distance:
				var aim: Vector3 = enemy.global_position + Vector3.UP * (1.7 if enemy.boss else 0.85)
				var hit := player._cast(player.aim_origin(), (aim - player.aim_origin()).normalized(), distance + 3.0, 0xFFFFFFFF)
				if hit.get("collider") == enemy:
					target = enemy
					target_distance = distance
		var next := nearest_cell(goal)
		if next != route_goal or frame % 90 == 0:
			route_goal = next
			route.clear()
			var start := nearest_cell(player.position)
			if floors.has(start) and floors.has(next):
				for point in navigation.get_point_path(point_id(start), point_id(next), true):
					route.append(point)
		while not route.is_empty() and Vector2(route[0].x - player.position.x, route[0].z - player.position.z).length() < 0.35:
			route.pop_front()
		var movement := (goal - player.position) if route.is_empty() else (route[0] - player.position)
		movement.y = 0.0
		movement = movement.normalized()
		var aim_at := player.position + movement * 10.0
		if is_instance_valid(target):
			aim_at = target.global_position + Vector3.UP * (1.7 if target.boss else 0.85)
			if target_distance < 10.0 and not target.boss:
				movement = -Vector3(target.position.x - player.position.x, 0.0, target.position.z - player.position.z).normalized()
		var look := aim_at - player.aim_origin()
		player.rotation.y = atan2(-look.x, -look.z)
		player.pitch = atan2(look.y, Vector2(look.x, look.z).length())
		player.head.rotation.x = player.pitch
		player.aiming = is_instance_valid(target)
		if is_instance_valid(target) and frame % 6 == 0:
			var before := player.ammo
			player._shoot()
			shots += maxi(0, before - player.ammo)
		var local := player.global_basis.inverse() * movement
		key(KEY_W, local.z < -0.25)
		key(KEY_S, local.z > 0.25)
		key(KEY_A, local.x < -0.25)
		key(KEY_D, local.x > 0.25)
		if frame % 60 == 0:
			var moved := Vector2(player.position.x - last_position.x, player.position.z - last_position.z).length()
			stuck = stuck + 1 if moved < 0.35 and movement.length() > 0.1 else 0
			last_position = player.position
		key(KEY_SPACE, stuck > 0 and frame % 60 < 15)
		var report := "%s bells=%d rung=%s boss=%d" % [mission.zone, mission.bells, mission.bell_rung, mission.boss.boss_phase]
		if report != last_report or frame % 600 == 0:
			print("Campaign %.1fs %s health=%d ammo=%d/%d at=%s goal=%s route=%d stuck=%d" % [frame / 60.0, report, player.health, player.ammo, player.reserve, player.position, goal, route.size(), stuck])
			if report != last_report:
				progress_frame = frame
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://art_direction/campaign")
				root.get_texture().get_image().save_png("res://art_direction/campaign/bells-%d-phase-%d.png" % [mission.bells, mission.boss.boss_phase])
			last_report = report
		if stuck > 8 or frame - progress_frame > 1800:
			print("Campaign navigation stalled toward ", goal)
			break
	for code in KEYS:
		key(code, false)
	print("Campaign result: victory=%s bells=%d deaths=%d shots=%d health=%d ammo=%d/%d" % [mission.victory, mission.bells, deaths, shots, player.health, player.ammo, player.reserve])
	await create_timer(1.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_direction/campaign/result.png")
	for pouch in mission.pouches:
		print("Remaining pickup: bell=%d at=%s" % [pouch.bell, pouch.node.position])
	var success: bool = mission.victory and mission.bells == 9 and mission.bell_rung and mission.gate_open and phases_seen.size() == 3 and reinforcement_count > 0
	print("Campaign gates: mother=%s gate=%s phases=%s reinforcements=%s" % [mission.bell_rung, mission.gate_open, phases_seen.keys(), reinforcement_count > 0])
	mission.audio.shutdown()
	await create_timer(0.2).timeout
	mission.queue_free()
	await process_frame
	await process_frame
	quit(0 if success else 1)
