class_name Minimap
extends Control
## Compact circular radar centred on the goat, north up: shaded terrain, landmarks,
## lit lanterns, dropped bells and pouches, hung Remembrance rounds, wolverines
## within earshot (with their view cones, coloured by what they know), the wind, and
## the objective, which pins to the ring when it is off the map. A row of nine
## bell pips above the ring shows the names recovered so far.

const SCALE := 2.0  # pixels per metre
const RADIUS := 98.0
const ENEMY_RANGE := 48.0
const PIPS_HEIGHT := 30.0
const BRASS := Color("e8c578")
const TERRAIN_PIXELS_PER_METRE := 2.0

const RADAR_CODE := """
shader_type canvas_item;
uniform sampler2D terrain : filter_linear, repeat_disable;
uniform vec2 centre_uv = vec2(0.5);
uniform vec2 half_uv = vec2(0.3);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	vec2 uv = centre_uv + p * half_uv;
	vec3 col = vec3(0.018, 0.028, 0.038);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		col = texture(terrain, uv).rgb * 1.05;
	}
	col *= 1.0 - 0.5 * smoothstep(0.6, 1.0, r);
	col += vec3(0.07, 0.09, 0.1) * smoothstep(0.02, 0.0, abs(r - 0.5));
	COLOR = vec4(col, 0.95);
}
"""

var player: GoatPlayer
var mission: Node
var terrain: ImageTexture
var radar_material: ShaderMaterial
var radar_rect: ColorRect
var terrain_size := Vector2.ONE
var font: Font
var plate := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	font = ThemeDB.fallback_font
	plate.bg_color = Color(0.015, 0.024, 0.032, 0.62)
	plate.set_corner_radius_all(6)
	var image := _shaded_terrain()
	terrain = ImageTexture.create_from_image(image)
	terrain_size = Vector2(image.get_width(), image.get_height())
	var shader := Shader.new()
	shader.code = RADAR_CODE
	radar_material = ShaderMaterial.new()
	radar_material.shader = shader
	radar_material.set_shader_parameter("terrain", terrain)
	radar_rect = ColorRect.new()
	radar_rect.name = "RadarDisc"
	radar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar_rect.material = radar_material
	radar_rect.show_behind_parent = true
	radar_rect.position = _centre() - Vector2.ONE * RADIUS
	radar_rect.size = Vector2.ONE * RADIUS * 2.0
	add_child(radar_rect)


func _centre() -> Vector2:
	return Vector2(size.x * 0.5, PIPS_HEIGHT + RADIUS + 2.0)


## Slope shading plus a soft directional hillshade, drawn once at startup.
func _shaded_terrain() -> Image:
	var scale_factor := int(TERRAIN_PIXELS_PER_METRE)
	var width := (WorldBuilder.X_MAX - WorldBuilder.X_MIN + 1) * scale_factor
	var depth := (WorldBuilder.Z_MAX - WorldBuilder.Z_MIN + 1) * scale_factor
	var image := Image.create(width, depth, false, Image.FORMAT_RGBA8)
	for zi in depth:
		for xi in width:
			var x := WorldBuilder.X_MIN + float(xi) / scale_factor
			var z := WorldBuilder.Z_MIN + float(zi) / scale_factor
			var steep := clampf(WorldBuilder.slope_at(x, z) / 1.3, 0.0, 1.0)
			var snow := Color(0.66, 0.74, 0.84)
			var rock := Color(0.12, 0.15, 0.2)
			match Story.biome_for_z(z):
				"carrion_cut":
					snow = Color(0.52, 0.41, 0.37)
					rock = Color(0.22, 0.09, 0.08)
				"iron_crown":
					snow = Color(0.34, 0.31, 0.32)
					rock = Color(0.07, 0.075, 0.09)
			var here := WorldBuilder.height_at(x, z)
			var lit := WorldBuilder.height_at(x - 0.6, z - 0.6) - here
			var color := snow.lerp(rock, steep)
			color = color.lightened(clampf(lit * 0.35, -0.3, 0.3)) if lit > 0.0 else color.darkened(clampf(-lit * 0.35, 0.0, 0.3))
			image.set_pixel(xi, zi, color)
	return image


func _to_map(world: Vector3, origin: Vector3) -> Vector2:
	return _centre() + Vector2(world.x - origin.x, world.z - origin.z) * SCALE


func _inside(point: Vector2, margin := 3.0) -> bool:
	return point.distance_to(_centre()) <= RADIUS - margin


## Clips a segment to the radar disc; returns [] when nothing of it is inside.
func _clip(a: Vector2, b: Vector2) -> Array:
	var centre := _centre()
	var reach := RADIUS - 3.0
	var direction := b - a
	var length_squared := direction.length_squared()
	if length_squared < 0.0001:
		return [a, b] if _inside(a) else []
	var offset := a - centre
	var quad_b := 2.0 * offset.dot(direction)
	var quad_c := offset.length_squared() - reach * reach
	var discriminant := quad_b * quad_b - 4.0 * length_squared * quad_c
	if discriminant < 0.0:
		return []
	var root := sqrt(discriminant)
	var t0 := clampf((-quad_b - root) / (2.0 * length_squared), 0.0, 1.0)
	var t1 := clampf((-quad_b + root) / (2.0 * length_squared), 0.0, 1.0)
	if t1 <= t0:
		return []
	return [a + direction * t0, a + direction * t1]


func _bell_pip(at: Vector2, filled: bool) -> void:
	var body := PackedVector2Array([at + Vector2(-2.5, 4.0), at + Vector2(-4.0, 4.0), at + Vector2(-3.0, 0.5), at + Vector2(-1.8, -3.0), at + Vector2(1.8, -3.0), at + Vector2(3.0, 0.5), at + Vector2(4.0, 4.0), at + Vector2(2.5, 4.0)])
	if filled:
		draw_colored_polygon(body, BRASS)
		draw_circle(at + Vector2(0.0, 5.5), 1.4, BRASS)
	else:
		body.append(body[0])
		draw_polyline(body, Color(0.75, 0.75, 0.75, 0.55), 1.2, true)


func _draw() -> void:
	if player == null or mission == null:
		return
	var centre := _centre()
	var origin := player.global_position
	radar_material.set_shader_parameter("centre_uv", Vector2((origin.x - WorldBuilder.X_MIN) / (WorldBuilder.X_MAX - WorldBuilder.X_MIN + 1.0), (origin.z - WorldBuilder.Z_MIN) / (WorldBuilder.Z_MAX - WorldBuilder.Z_MIN + 1.0)))
	var half_metres := RADIUS / SCALE
	radar_material.set_shader_parameter("half_uv", Vector2(half_metres / (WorldBuilder.X_MAX - WorldBuilder.X_MIN + 1.0), half_metres / (WorldBuilder.Z_MAX - WorldBuilder.Z_MIN + 1.0)))

	# Dark plate behind the pips keeps them legible over snow.
	draw_style_box(plate, Rect2(Vector2(0.0, 0.0), Vector2(size.x, PIPS_HEIGHT - 4.0)))
	var recovered: int = mission.bells
	var total := Story.BELL_NAMES.size()
	var spacing := 20.0
	var pip_origin := Vector2(size.x * 0.5 - spacing * (total - 1) * 0.5, 13.0)
	for i in total:
		_bell_pip(pip_origin + Vector2(i * spacing, 0.0), i < recovered)

	# Landmarks.
	var bell := _to_map(WorldBuilder.BELL_ORIGIN, origin)
	if _inside(bell, 8.0):
		draw_arc(bell, 6.0, 0.0, TAU, 20, BRASS, 1.5, true)
		draw_circle(bell, 1.6, BRASS)
	var gate_left := _to_map(Vector3(-13.0, 0.0, WorldBuilder.GATE_Z), origin)
	var gate_right := _to_map(Vector3(13.0, 0.0, WorldBuilder.GATE_Z), origin)
	var gate := _clip(gate_left, gate_right)
	if not gate.is_empty():
		draw_line(gate[0], gate[1], Color("c7d3dc"), 2.5, true)
	for lantern in mission.world.lanterns:
		if lantern.lit:
			var at := _to_map(lantern.position, origin)
			if _inside(at):
				draw_circle(at, 2.8, Color(1.0, 0.62, 0.25, 0.28))
				draw_circle(at, 1.7, Color(1.0, 0.68, 0.3, 0.95))
	for pouch in mission.pouches:
		var node: Node3D = pouch.node
		var at := _to_map(node.global_position, origin)
		if _inside(at):
			draw_circle(at, 4.2 if pouch.bell >= 0 else 3.0, Color(0.0, 0.0, 0.0, 0.6))
			draw_circle(at, 3.0 if pouch.bell >= 0 else 2.0, Color("ffd27a"))

	# Hung Remembrance rounds and their beams.
	for round in player.hung:
		var start := _to_map(round.origin, origin)
		var stop := _to_map(round.origin + round.direction * round.reach, origin)
		var beam := _clip(start, stop)
		if not beam.is_empty():
			draw_line(beam[0], beam[1], Color(1.0, 0.76, 0.42, 0.5), 1.4, true)
		if _inside(start):
			draw_circle(start, 3.2, Color("ffc36b"))

	# Wolverines close enough to matter, coloured by what they know.
	for enemy in mission.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		if enemy.global_position.distance_to(origin) > ENEMY_RANGE:
			continue
		var color := Color("6fb6ff")
		if enemy.detection >= Stealth.ALERT:
			color = Color("ff3b2a")
		elif enemy.detection >= Stealth.SUSPICIOUS:
			color = Color("ffb03a")
		var at := _to_map(enemy.global_position, origin)
		if not _inside(at, 4.0):
			continue
		var facing: Vector3 = enemy.facing()
		var heading := Vector2(facing.x, facing.z).normalized()
		var side := Vector2(-heading.y, heading.x)
		draw_colored_polygon(PackedVector2Array([at, at + heading * 15.0 + side * 8.0, at + heading * 15.0 - side * 8.0]), Color(color, 0.16))
		draw_circle(at, 5.2 if enemy.boss else 4.2, Color(0.0, 0.0, 0.0, 0.7))
		draw_circle(at, 4.0 if enemy.boss else 3.0, color)

	# Objective marker, pinned to the ring when it is off the map.
	var goal: Vector3 = mission.objective_position()
	if goal != Vector3.INF:
		var at := _to_map(goal, origin)
		var offset := at - centre
		var pinned := offset.length() > RADIUS - 10.0
		if pinned:
			at = centre + offset.normalized() * (RADIUS - 10.0)
		draw_circle(at, 6.0, Color(0.0, 0.0, 0.0, 0.7))
		draw_circle(at, 4.5, Color("f0e7d7", 0.95 if not pinned else 0.7))
		draw_circle(at, 2.2, Color("db6c2f"))

	# The goat: a view cone and an arrow pointing the way it faces (north is up).
	var yaw := player.rotation.y
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-forward.y, forward.x)
	var cone := 0.62
	var cone_points := PackedVector2Array([centre])
	for step in 7:
		var angle := lerpf(-cone, cone, step / 6.0)
		cone_points.append(centre + forward.rotated(angle) * 30.0)
	draw_colored_polygon(cone_points, Color(0.56, 0.82, 0.78, 0.13))
	var body := PackedVector2Array([centre + forward * 8.0, centre - forward * 5.5 + right * 5.5, centre - forward * 2.0, centre - forward * 5.5 - right * 5.5])
	var outline := body.duplicate()
	outline.append(outline[0])
	draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.85), 3.0, true)
	draw_colored_polygon(body, Color("8fd0c8") if not player.crouched else Color("5fa89f"))

	# Ring, cardinal ticks and the north mark.
	draw_arc(centre, RADIUS + 1.0, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.9), 6.0, true)
	draw_arc(centre, RADIUS - 1.0, 0.0, TAU, 96, Color(BRASS, 0.85), 2.0, true)
	for quarter in 4:
		var direction := Vector2.UP.rotated(quarter * PI * 0.5)
		draw_line(centre + direction * (RADIUS - 8.0), centre + direction * (RADIUS - 1.0), Color(BRASS, 0.9), 2.0)
	_label(centre + Vector2(0.0, -RADIUS + 20.0), "N", 12, BRASS)

	# Wind: a small arrow in the lower-left corner showing where the air blows.
	var wind := Stealth.wind_at(Time.get_ticks_msec() * 0.001)
	var wind_dir := Vector2(wind.x, wind.z).normalized()
	var corner := Vector2(20.0, size.y - 22.0)
	var wind_side := Vector2(-wind_dir.y, wind_dir.x)
	var tip := corner + wind_dir * 11.0
	draw_line(corner - wind_dir * 11.0, tip, Color(0.0, 0.0, 0.0, 0.85), 4.0, true)
	draw_line(corner - wind_dir * 11.0, tip, Color("aebdc2"), 2.0, true)
	draw_colored_polygon(PackedVector2Array([tip + wind_dir * 3.0, tip - wind_dir * 5.0 + wind_side * 5.0, tip - wind_dir * 5.0 - wind_side * 5.0]), Color("aebdc2"))
	_label(corner + Vector2(0.0, 19.0), "WIND", 9, Color("aebdc2"))


func _label(at: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var start := at - Vector2(width * 0.5, -font_size * 0.35)
	draw_string_outline(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 4, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
