class_name Minimap
extends Control
## Top-down map of the ravine centred on the goat: terrain shading, landmarks,
## lit lanterns, recovered-bell drops, bodies of the warpack, hung
## Remembrance rounds, nearby
## wolverines coloured by what they know, the wind, and the objective.

const SCALE := 2.6  # pixels per metre
const ENEMY_RANGE := 48.0

var player: GoatPlayer
var mission: Node
var terrain: ImageTexture


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	terrain = ImageTexture.create_from_image(WorldBuilder.minimap_image())


func _to_map(world: Vector3, origin: Vector3) -> Vector2:
	return size * 0.5 + Vector2(world.x - origin.x, world.z - origin.z) * SCALE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.035, 0.05, 0.82))
	if player == null or mission == null:
		return
	var origin := player.global_position
	var tex_size := Vector2(terrain.get_width(), terrain.get_height()) * SCALE
	draw_texture_rect(terrain, Rect2(_to_map(Vector3(WorldBuilder.X_MIN, 0.0, WorldBuilder.Z_MIN), origin), tex_size), false, Color(1.0, 1.0, 1.0, 0.85))

	# Landmarks.
	var bell := WorldBuilder.BELL_ORIGIN
	draw_arc(_to_map(bell, origin), 5.0, 0.0, TAU, 20, Color("e8c578"), 1.5)
	var gate_left := _to_map(Vector3(-13.0, 0.0, WorldBuilder.GATE_Z), origin)
	var gate_right := _to_map(Vector3(13.0, 0.0, WorldBuilder.GATE_Z), origin)
	draw_line(gate_left, gate_right, Color("c7d3dc"), 2.0)
	for lantern in mission.world.lanterns:
		if lantern.lit:
			draw_circle(_to_map(lantern.position, origin), 2.2, Color(1.0, 0.62, 0.25, 0.9))
	for pouch in mission.pouches:
		var node: Node3D = pouch.node
		draw_circle(_to_map(node.global_position, origin), 2.5 if pouch.bell >= 0 else 1.8, Color("ffd27a"))

	# Maren's cairns, once the goat is close enough to have seen them.
	for cairn in mission.world.cairns:
		if cairn.position.distance_to(origin) < 35.0:
			var at := _to_map(cairn.position, origin)
			var tint := Color("ffb066") if cairn.kindled else Color("bcd8ff")
			draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -3.5), at + Vector2(3.0, 0.0), at + Vector2(0.0, 3.5), at + Vector2(-3.0, 0.0)]), tint)

	# Bodies of the warpack: a dark cross, red once the pack has found it.
	for body in get_tree().get_nodes_in_group("bodies"):
		var at := _to_map(body.global_position, origin)
		var mark := Color("ff5a3c", 0.8) if body.get_meta("body_found", false) else Color(0.8, 0.8, 0.8, 0.55)
		draw_line(at - Vector2(2.5, 2.5), at + Vector2(2.5, 2.5), mark, 1.5)
		draw_line(at - Vector2(2.5, -2.5), at + Vector2(2.5, -2.5), mark, 1.5)

	# Hung Remembrance rounds and their beams.
	for round in player.hung:
		var at := _to_map(round.origin, origin)
		var to := _to_map(round.origin + round.direction * round.reach, origin)
		draw_line(at, to, Color(1.0, 0.76, 0.42, 0.45), 1.0)
		draw_circle(at, 2.6, Color("ffc36b"))

	# Wolverines close enough to matter, coloured by what they know.
	for enemy in mission.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var distance: float = enemy.global_position.distance_to(origin)
		if distance > ENEMY_RANGE:
			continue
		var color := Color("6fb6ff")
		if enemy.detection >= Stealth.ALERT:
			color = Color("ff3b2a")
		elif enemy.detection >= Stealth.SUSPICIOUS:
			color = Color("ffb03a")
		var at := _to_map(enemy.global_position, origin)
		var facing: Vector3 = enemy.facing()
		draw_line(at, at + Vector2(facing.x, facing.z) * 7.0, Color(color, 0.5), 1.5)
		draw_circle(at, 4.0 if enemy.boss else 3.0, color)

	# Objective marker, pinned to the edge when it is off the map.
	var goal: Vector3 = mission.objective_position()
	if goal != Vector3.INF:
		var at := _to_map(goal, origin)
		var centre := size * 0.5
		var edge := Rect2(Vector2(8.0, 8.0), size - Vector2(16.0, 16.0))
		var pinned := not edge.has_point(at)
		if pinned:
			var direction := (at - centre).normalized()
			var t := INF
			for axis in 2:
				if direction[axis] != 0.0:
					var bound := edge.end[axis] if direction[axis] > 0.0 else edge.position[axis]
					t = minf(t, (bound - centre[axis]) / direction[axis])
			at = centre + direction * t
		draw_circle(at, 4.5, Color("f0e7d7", 0.9 if not pinned else 0.6))
		draw_circle(at, 2.0, Color("db6c2f"))

	# The goat: an arrow pointing the way it faces (north is up).
	var centre := size * 0.5
	var yaw := player.rotation.y
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([
		centre + forward * 7.0,
		centre - forward * 5.0 + right * 5.0,
		centre - forward * 2.0,
		centre - forward * 5.0 - right * 5.0,
	]), Color("8fd0c8") if not player.crouched else Color("5fa89f"))

	# Wind: a small arrow in the corner showing where the air blows.
	var wind := Stealth.wind_at(Time.get_ticks_msec() * 0.001)
	var wind_dir := Vector2(wind.x, wind.z)
	var corner := Vector2(size.x - 18.0, 18.0)
	draw_line(corner - wind_dir * 8.0, corner + wind_dir * 8.0, Color("aebdc2"), 1.5)
	draw_line(corner + wind_dir * 8.0, corner + wind_dir * 8.0 - (wind_dir + Vector2(-wind_dir.y, wind_dir.x)) * 4.0, Color("aebdc2"), 1.5)
	draw_line(corner + wind_dir * 8.0, corner + wind_dir * 8.0 - (wind_dir - Vector2(-wind_dir.y, wind_dir.x)) * 4.0, Color("aebdc2"), 1.5)

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.85, 0.7, 0.35), false, 1.0)
