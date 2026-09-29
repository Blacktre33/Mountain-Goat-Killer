class_name HudWidgets
extends Control
## The parts of the HUD that are drawn rather than laid out: a dynamic crosshair
## with hit markers, the damage direction arcs, the compass, and the ammo, will and
## Remembrance widgets. A screen-space vignette shader handles low health. Every
## widget sits on a dark backing so it stays legible over bright snow and black rock.

const BRASS := Color("e8c578")
const EMBER := Color("db6c2f")
const CREAM := Color("f2e8d4")
const TEAL := Color("8fd0c8")
const BLOOD := Color("d23b28")
const PANEL_BG := Color(0.015, 0.024, 0.032, 0.66)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const MARKER_LIFE := 0.3
const INDICATOR_LIFE := 1.3

const VIGNETTE_CODE := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float low : hint_range(0.0, 1.0) = 0.0;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float beat : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	vec2 p = (SCREEN_UV * 2.0 - 1.0) * vec2(0.9, 1.0);
	float vig = smoothstep(0.32, 1.3, length(p));
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey) * vec3(1.0, 0.93, 0.9), clamp(low * 0.72 + hurt * 0.12, 0.0, 1.0));
	col *= 1.0 - low * 0.22 * vig;
	float amount = vig * (low * (0.5 + 0.4 * beat) + hurt * 0.65);
	col = mix(col, vec3(0.5, 0.02, 0.02), clamp(amount, 0.0, 0.88));
	COLOR = vec4(col, 1.0);
}
"""

var player: GoatPlayer
var mission: Node
var font: Font
var panel_box := StyleBoxFlat.new()
var vignette: ColorRect
var vignette_material: ShaderMaterial

var hung := 0
var sensing := false
var health := 100
var health_shown := 100.0
var ammo := 24
var reserve := 96
var hit_kind := ""
var hit_time := -10.0
var indicators: Array = []
var hurt := 0.0
var ammo_flash := 0.0
var beat := 0.0
var last_time := 0.0


func _ready() -> void:
	name = "HudWidgets"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	panel_box.bg_color = PANEL_BG
	panel_box.set_corner_radius_all(3)
	panel_box.border_width_left = 3
	panel_box.border_color = BRASS
	panel_box.anti_aliasing = true
	var shader := Shader.new()
	shader.code = VIGNETTE_CODE
	vignette_material = ShaderMaterial.new()
	vignette_material.shader = shader
	vignette = ColorRect.new()
	vignette.name = "LowHealthVignette"
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = vignette_material
	vignette.visible = false
	last_time = Time.get_ticks_msec() * 0.001


func bind(target: GoatPlayer, owner_node: Node) -> void:
	player = target
	mission = owner_node
	# The grade sits on its own layer beneath the HUD so it tints the world, not the text.
	var layer := CanvasLayer.new()
	layer.name = "LowHealthGrade"
	layer.layer = 9
	layer.add_child(vignette)
	mission.add_child(layer)
	player.damaged.connect(_on_damaged)
	player.hit_confirmed.connect(_on_hit)
	player.ammo_changed.connect(_on_ammo)
	player.health_changed.connect(_on_health)
	player.remembrance_changed.connect(_on_remembrance)
	ammo = player.ammo
	reserve = player.reserve
	health = player.health
	health_shown = float(health)


func _on_damaged(bearing: float, amount: int) -> void:
	hurt = minf(1.0, hurt + 0.35 + amount / 80.0)
	indicators.append({"bearing": bearing, "life": INDICATOR_LIFE, "power": clampf(0.55 + amount / 60.0, 0.55, 1.0)})
	if indicators.size() > 6:
		indicators.pop_front()


func _on_hit(kind: String) -> void:
	hit_kind = kind
	hit_time = Time.get_ticks_msec() * 0.001


func _on_ammo(current: int, extra: int) -> void:
	if current < ammo:
		ammo_flash = 0.0
	elif current > ammo:
		ammo_flash = 1.0
	ammo = current
	reserve = extra


func _on_health(current: int) -> void:
	health = current


func _on_remembrance(count: int, _capacity: int, sense: bool) -> void:
	hung = count
	sensing = sense


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	var delta := clampf(now - last_time, 0.0, 0.1)
	last_time = now
	health_shown = lerpf(health_shown, float(health), 1.0 - exp(-8.0 * delta))
	hurt = move_toward(hurt, 0.0, delta * 1.1)
	ammo_flash = move_toward(ammo_flash, 0.0, delta * 3.0)
	for entry in indicators:
		entry.life -= delta
	indicators = indicators.filter(func(entry: Dictionary) -> bool: return entry.life > 0.0)
	var low := 0.0
	if player.active and health < GoatPlayer.LOW_HEALTH + 15:
		low = clampf(1.0 - float(health) / (GoatPlayer.LOW_HEALTH + 15), 0.0, 1.0)
	elif not player.active:
		low = 1.0
	# The vignette pulses with the heartbeat sound while will is low.
	var pulse := 0.0
	if low > 0.2:
		var rate := lerpf(1.6, 2.6, low)
		pulse = pow(maxf(0.0, sin(now * TAU * rate * 0.5)), 6.0)
	beat = lerpf(beat, pulse, 1.0 - exp(-18.0 * delta))
	vignette_material.set_shader_parameter("low", low)
	vignette_material.set_shader_parameter("hurt", hurt)
	vignette_material.set_shader_parameter("beat", beat)
	vignette.visible = low > 0.001 or hurt > 0.001
	queue_redraw()


# --- Drawing helpers -----------------------------------------------------------------

func _panel(rect: Rect2, accent := BRASS) -> void:
	panel_box.border_color = accent
	draw_style_box(panel_box, rect)


func _text(at: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var start := at
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		start.x -= width if align == HORIZONTAL_ALIGNMENT_RIGHT else width * 0.5
	draw_string_outline(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, 5, OUTLINE)
	draw_string(font, start, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	draw_line(from, to, OUTLINE, width + 2.0, true)
	draw_line(from, to, color, width, true)


func _diamond(at: Vector2, radius: float, color: Color, filled := true) -> void:
	var points := PackedVector2Array([at + Vector2(0.0, -radius), at + Vector2(radius * 0.72, 0.0), at + Vector2(0.0, radius), at + Vector2(-radius * 0.72, 0.0)])
	if filled:
		draw_colored_polygon(points, color)
	else:
		points.append(points[0])
		draw_polyline(points, color, 1.5, true)


func _draw() -> void:
	if player == null or mission == null:
		return
	var centre := size * 0.5
	if mission.crosshair.visible:
		_draw_crosshair(centre)
		_draw_damage(centre)
	if not mission.started or mission.victory:
		return
	_draw_compass()
	_draw_stealth_plate()
	_draw_ammo()
	_draw_will()
	_draw_remembrance()


func _draw_crosshair(centre: Vector2) -> void:
	var ads := player.ads_blend
	var spread := player.crosshair_spread()
	var gap := lerpf(6.0 + spread * 22.0, 4.0, ads)
	var length := lerpf(9.0, 5.0, ads)
	# The crosshair steps back while sprinting: the carbine cannot fire.
	var color := Color(CREAM, lerpf(0.92, 0.8, ads) * lerpf(1.0, 0.4, player.sprint_blend))
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		_line(centre + direction * gap, centre + direction * (gap + length), color, 2.0)
	if ads < 0.5:
		_line(centre + Vector2.UP * gap, centre + Vector2.UP * (gap + length), color, 2.0)
	draw_circle(centre, 2.6, OUTLINE)
	draw_circle(centre, 1.5, BRASS)
	var age := Time.get_ticks_msec() * 0.001 - hit_time
	if age < MARKER_LIFE:
		var fade := 1.0 - age / MARKER_LIFE
		var marker_color := Color.WHITE
		var reach := 16.0
		match hit_kind:
			"headshot":
				marker_color = BRASS
				reach = 20.0
			"kill":
				marker_color = Color("ff4a30")
				reach = 24.0
		marker_color.a = fade
		var start := 8.0 + (1.0 - fade) * 4.0
		for diagonal in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dir: Vector2 = diagonal.normalized()
			_line(centre + dir * start, centre + dir * (reach * (0.7 + 0.3 * fade) + start * 0.3), marker_color, 2.5 if hit_kind != "kill" else 3.5)


func _draw_damage(centre: Vector2) -> void:
	for entry in indicators:
		var fade: float = clampf(entry.life / INDICATOR_LIFE, 0.0, 1.0)
		var colour := Color(0.9, 0.12, 0.08, fade * entry.power)
		if is_nan(entry.bearing):
			continue
		var angle: float = entry.bearing - PI * 0.5
		draw_arc(centre, 120.0, angle - 0.34, angle + 0.34, 20, Color(0.0, 0.0, 0.0, fade * 0.5), 15.0, true)
		draw_arc(centre, 120.0, angle - 0.3, angle + 0.3, 20, colour, 9.0, true)
		draw_arc(centre, 132.0, angle - 0.18, angle + 0.18, 12, Color(1.0, 0.45, 0.3, fade * 0.7), 3.0, true)


func _draw_compass() -> void:
	var width := 360.0
	var rect := Rect2(Vector2(size.x * 0.5 - width * 0.5, 14.0), Vector2(width, 30.0))
	_panel(rect, Color(BRASS, 0.55))
	var forward := -player.global_transform.basis.z
	var heading := rad_to_deg(atan2(forward.x, -forward.z))
	var per_degree := width / 150.0
	var mid := rect.get_center()
	for step in range(-90, 91, 5):
		var bearing := snappedf(heading, 5.0) + step
		var offset := (bearing - heading) * per_degree
		if absf(offset) > width * 0.5 - 8.0:
			continue
		var wrapped := int(fposmod(bearing, 360.0))
		var x := mid.x + offset
		var fade := 1.0 - absf(offset) / (width * 0.5)
		if wrapped % 45 == 0:
			var letters := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}
			var letter: String = letters[wrapped]
			_text(Vector2(x, mid.y + 6.0), letter, 15 if letter.length() == 1 else 12, Color(BRASS if letter == "N" else CREAM, fade + 0.25), HORIZONTAL_ALIGNMENT_CENTER)
		elif wrapped % 15 == 0:
			draw_line(Vector2(x, rect.position.y + 10.0), Vector2(x, rect.end.y - 10.0), Color(CREAM, 0.6 * fade), 1.5)
		else:
			draw_line(Vector2(x, rect.position.y + 13.0), Vector2(x, rect.end.y - 13.0), Color(CREAM, 0.3 * fade), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(mid.x - 5.0, rect.end.y + 7.0), Vector2(mid.x + 5.0, rect.end.y + 7.0), Vector2(mid.x, rect.end.y + 1.0)]), BRASS)
	var goal: Vector3 = mission.objective_position()
	if goal != Vector3.INF:
		var offset_vector := goal - player.global_position
		var goal_bearing := rad_to_deg(atan2(offset_vector.x, -offset_vector.z))
		var delta_bearing := wrapf(goal_bearing - heading, -180.0, 180.0)
		var edge := width * 0.5 - 14.0
		var goal_x := mid.x + clampf(delta_bearing * per_degree, -edge, edge)
		var on_strip := absf(delta_bearing * per_degree) <= edge
		_diamond(Vector2(goal_x, mid.y - 1.0), 8.0, Color(OUTLINE, 1.0))
		_diamond(Vector2(goal_x, mid.y - 1.0), 6.0, EMBER if on_strip else Color(EMBER, 0.65))
		var metres := int(Vector2(offset_vector.x, offset_vector.z).length())
		_text(Vector2(goal_x, rect.end.y + 22.0), "%d m" % metres, 12, CREAM, HORIZONTAL_ALIGNMENT_CENTER)


## Backing for the state word, detection bar, posture and wind lines main.gd owns.
func _draw_stealth_plate() -> void:
	var rect := Rect2(Vector2(28.0, size.y - 28.0 - 42.0 - 8.0 - 104.0), Vector2(300.0, 104.0))
	_panel(rect, mission.stealth_color)


func _draw_ammo() -> void:
	var rect := Rect2(Vector2(size.x - 28.0 - 262.0, size.y - 28.0 - 88.0), Vector2(262.0, 88.0))
	var low := ammo <= GoatPlayer.MAGAZINE_SIZE / 4
	var empty := ammo == 0
	var accent := BLOOD if empty else (EMBER if low else BRASS)
	_panel(rect, accent)
	var reloading := player.reloading
	var progress := player.reload_progress()
	var pip_width := 6.0
	var pip_gap := 4.0
	var origin := rect.position + Vector2(16.0, 14.0)
	for i in GoatPlayer.MAGAZINE_SIZE:
		var x := origin.x + i * (pip_width + pip_gap)
		var filled := i < ammo
		if reloading:
			filled = float(i) / GoatPlayer.MAGAZINE_SIZE < progress
		var pip_colour := Color(BRASS, 0.95) if filled else Color(0.5, 0.5, 0.5, 0.22)
		if filled and low and not reloading:
			pip_colour = Color(EMBER, 1.0)
		draw_rect(Rect2(Vector2(x, origin.y), Vector2(pip_width, 14.0)), pip_colour)
	var number_colour := CREAM
	if empty:
		number_colour = BLOOD.lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
	elif low:
		number_colour = Color("ffb35a")
	if ammo_flash > 0.0:
		number_colour = number_colour.lerp(Color.WHITE, ammo_flash)
	_text(rect.position + Vector2(16.0, 74.0), "%02d" % ammo, 46, number_colour)
	_text(rect.position + Vector2(rect.size.x - 16.0, 74.0), "/ %02d" % reserve, 22, Color(CREAM, 0.85), HORIZONTAL_ALIGNMENT_RIGHT)
	if reloading:
		_text(rect.position + Vector2(rect.size.x - 16.0, 44.0), "RELOADING", 12, BRASS, HORIZONTAL_ALIGNMENT_RIGHT)
		var bar := Rect2(rect.position + Vector2(96.0, 54.0), Vector2(rect.size.x - 96.0 - 16.0, 3.0))
		draw_rect(bar, Color(1, 1, 1, 0.15))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), BRASS)
	elif empty and reserve > 0:
		_text(rect.position + Vector2(rect.size.x - 16.0, 44.0), "R  RELOAD", 12, Color("ff8a6a"), HORIZONTAL_ALIGNMENT_RIGHT)
	elif empty:
		_text(rect.position + Vector2(rect.size.x - 16.0, 44.0), "NO ROUNDS", 12, Color("ff8a6a"), HORIZONTAL_ALIGNMENT_RIGHT)
	elif low and reserve > 0:
		_text(rect.position + Vector2(rect.size.x - 16.0, 44.0), "R  RELOAD", 12, Color("ffb35a"), HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_will() -> void:
	var rect := Rect2(Vector2(28.0, size.y - 28.0 - 42.0), Vector2(300.0, 42.0))
	var ratio := clampf(health_shown / 100.0, 0.0, 1.0)
	var low := health < GoatPlayer.LOW_HEALTH
	var accent := BLOOD if low else TEAL
	_panel(rect, accent)
	_text(rect.position + Vector2(14.0, 26.0), "WILL", 12, Color(CREAM, 0.85))
	var bar := Rect2(rect.position + Vector2(56.0, 15.0), Vector2(178.0, 12.0))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var fill := Color("bfe6e0").lerp(Color("ff5a3c"), clampf(1.0 - ratio * 2.2, 0.0, 1.0))
	if low:
		fill = fill.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.014)))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), fill)
	# Second wind refills will only up to this mark once the fight goes quiet.
	var cap_x := bar.position.x + bar.size.x * (GoatPlayer.REGEN_CAP / 100.0)
	draw_line(Vector2(cap_x, bar.position.y - 3.0), Vector2(cap_x, bar.end.y + 3.0), Color(BRASS, 0.85), 1.5)
	for segment in range(1, 10):
		var x := bar.position.x + bar.size.x * segment / 10.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(0, 0, 0, 0.4), 1.0)
	_text(rect.position + Vector2(rect.size.x - 12.0, 28.0), "%d" % health, 20, Color("ff8a6a") if low else CREAM, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_remembrance() -> void:
	var capacity := Remembrance.CAPACITY
	var rect := Rect2(Vector2(size.x - 28.0 - 262.0, size.y - 28.0 - 88.0 - 8.0 - 34.0), Vector2(262.0, 34.0))
	_panel(rect, EMBER if hung > 0 else Color(BRASS, 0.5))
	_text(rect.position + Vector2(14.0, 22.0), "REMEMBRANCE", 11, Color(CREAM, 0.85))
	var t := Time.get_ticks_msec() * 0.001
	for i in capacity:
		var at := rect.position + Vector2(130.0 + i * 20.0, 17.0)
		if i < hung:
			var pulse := 1.0 + sin(t * 8.0 + i) * 0.12 + (0.5 if sensing else 0.0)
			draw_circle(at, 9.0 * pulse, Color(EMBER, 0.28))
			_diamond(at, 6.5 * pulse, Color("fff0c0") if sensing else BRASS)
		else:
			_diamond(at, 5.5, Color(CREAM, 0.35), false)
	_text(rect.position + Vector2(rect.size.x - 14.0, 22.0), "F", 13, BRASS, HORIZONTAL_ALIGNMENT_RIGHT)
