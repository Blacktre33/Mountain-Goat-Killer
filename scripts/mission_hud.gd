class_name MissionHud
extends CanvasLayer
## Every piece of the mission's interface: the in-field HUD, the title screen,
## the pause menu, options, chapter cards, and the ending. The mission drives
## it through the small set of methods below and listens to its signals; the
## HUD never changes mission state itself.

signal continue_requested
signal new_game_requested
signal difficulty_cycle_requested
signal quit_requested
signal resume_requested
signal return_to_title_requested
signal settings_changed

const NEW_GAME_CONFIRM := "PRESS AGAIN TO ERASE THE SAVED ASCENT"

var mission: Node
var ending_shown := false
var notice_until := 0.0
var has_save := false

var ground_shade: TextureRect
var objective_label: Label
var biome_label: Label
var bells_label: Label
var ammo_label: Label
var health_label: Label
var remembrance_label: Label
var stealth_label: Label
var exposure_bar: ColorRect
var exposure_fill: ColorRect
var wind_label: Label
var center_message: Label
var prompt_label: Label
var fps_label: Label
var crosshair: Label
var minimap: Minimap
var boss_label: Label
var boss_bar: ColorRect
var boss_fill: ColorRect
var chapter_title: Label
var chapter_line: Label
var chapter_tween: Tween
var victory_veil: ColorRect
var ending_actions: HBoxContainer
var return_button: Button

var start_overlay: ColorRect
var field_note: Label
var controls_label: Label
var continue_button: Button
var deploy_button: Button
var difficulty_button: Button

var pause_overlay: ColorRect
var pause_panel: VBoxContainer
var resume_button: Button
var pause_options_button: Button

var options_menu: OptionsMenu
var options_return_focus: Control


## Build the whole interface. `save_summary` is the Continue label, or "" when
## there is no saved ascent.
func build(owner_mission: Node, save_summary: String) -> void:
	mission = owner_mission
	name = "HUD"
	layer = 10
	has_save = not save_summary.is_empty()
	_build_field()
	_build_title(save_summary)
	_build_pause()
	_build_ending()
	options_menu = OptionsMenu.new()
	add_child(options_menu)
	options_menu.settings_changed.connect(func() -> void: settings_changed.emit())
	options_menu.closed.connect(_on_options_closed)
	set_field_visible(false)
	refresh_control_text(false)


func _build_field() -> void:
	# Snow and exposed stone can be much brighter than the old empty backdrop.
	# A soft lower veil keeps status and ammunition legible across every biome.
	var shade_gradient := Gradient.new()
	shade_gradient.colors = PackedColorArray([Color(0.005, 0.01, 0.018, 0.0), Color(0.005, 0.01, 0.018, 0.78)])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = shade_gradient
	shade_texture.fill_from = Vector2(0.0, 0.0)
	shade_texture.fill_to = Vector2(0.0, 1.0)
	ground_shade = TextureRect.new()
	ground_shade.name = "GroundReadabilityShade"
	ground_shade.texture = shade_texture
	ground_shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ground_shade.offset_top = -260.0
	ground_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground_shade)

	objective_label = _make_label("OBJECTIVE  //  " + Story.OBJECTIVES.trailhead, 17, Color("e6d8c1"))
	objective_label.position = Vector2(46.0, 40.0)
	add_child(objective_label)
	biome_label = _make_label("WIDOWPINE  //  FROST PINE  //  THE BROKEN FOLD", 12, Color("8fa1a8"))
	biome_label.position = Vector2(46.0, 68.0)
	add_child(biome_label)

	bells_label = _make_label("BELLS RECOVERED  //  0 / 9", 15, Color("e8c578"))
	bells_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bells_label.position = Vector2(-340.0, 42.0)
	bells_label.size = Vector2(295.0, 30.0)
	bells_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(bells_label)

	ammo_label = _make_label("24  /  96", 34, Color("f2e8d4"))
	ammo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ammo_label.position = Vector2(-230.0, 620.0)
	ammo_label.size = Vector2(190.0, 50.0)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ammo_label)

	minimap = Minimap.new()
	minimap.mission = mission
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-266.0, 80.0)
	minimap.size = Vector2(220.0, 220.0)
	add_child(minimap)

	stealth_label = _make_label("HIDDEN  //  STANDING  //  IN DARK", 14, Color("8fd0c8"))
	stealth_label.position = Vector2(46.0, 548.0)
	add_child(stealth_label)
	exposure_bar = ColorRect.new()
	exposure_bar.color = Color(1.0, 1.0, 1.0, 0.12)
	exposure_bar.position = Vector2(46.0, 574.0)
	exposure_bar.size = Vector2(180.0, 4.0)
	add_child(exposure_bar)
	exposure_fill = ColorRect.new()
	exposure_fill.color = Color("8fd0c8")
	exposure_fill.position = Vector2(46.0, 574.0)
	exposure_fill.size = Vector2(0.0, 4.0)
	add_child(exposure_fill)
	wind_label = _make_label("WIND", 13, Color("aebdc2"))
	wind_label.position = Vector2(46.0, 586.0)
	add_child(wind_label)

	remembrance_label = _make_label("", 15, Color("e8c578"))
	remembrance_label.position = Vector2(46.0, 616.0)
	add_child(remembrance_label)

	health_label = _make_label("WILL  //  100", 16, Color("d5e4e8"))
	health_label.position = Vector2(46.0, 650.0)
	add_child(health_label)

	crosshair = _make_label("+", 28, Color("e8c578"))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-14.0, -18.0)
	crosshair.size = Vector2(28.0, 36.0)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(crosshair)

	center_message = _make_label("", 24, Color("e8c578"))
	center_message.set_anchors_preset(Control.PRESET_CENTER)
	center_message.position = Vector2(-400.0, -170.0)
	center_message.size = Vector2(800.0, 100.0)
	center_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(center_message)

	boss_label = _make_label("VARKAS", 16, Color("f0e0cb"))
	boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_label.position = Vector2(-280.0, 28.0)
	boss_label.size = Vector2(560.0, 28.0)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.visible = false
	add_child(boss_label)
	boss_bar = ColorRect.new()
	boss_bar.color = Color(0.04, 0.025, 0.025, 0.9)
	boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_bar.position = Vector2(-220.0, 58.0)
	boss_bar.size = Vector2(440.0, 7.0)
	boss_bar.visible = false
	add_child(boss_bar)
	boss_fill = ColorRect.new()
	boss_fill.color = Color("c4a46b")
	boss_fill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_fill.position = Vector2(-220.0, 58.0)
	boss_fill.size = Vector2(440.0, 7.0)
	boss_fill.visible = false
	add_child(boss_fill)

	victory_veil = ColorRect.new()
	victory_veil.name = "VictoryVeil"
	victory_veil.color = Color(0.008, 0.012, 0.022, 0.0)
	victory_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_veil.z_index = 5
	victory_veil.visible = false
	add_child(victory_veil)

	chapter_title = _make_label("", 30, Color("f0e7d7"))
	chapter_title.z_index = 6
	chapter_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	chapter_title.position = Vector2(-420.0, 96.0)
	chapter_title.size = Vector2(840.0, 44.0)
	chapter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapter_title.modulate.a = 0.0
	add_child(chapter_title)
	chapter_line = _make_label("", 16, Color("cbb98f"))
	chapter_line.z_index = 6
	chapter_line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	chapter_line.position = Vector2(-360.0, 142.0)
	chapter_line.size = Vector2(720.0, 120.0)
	chapter_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapter_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chapter_line.modulate.a = 0.0
	add_child(chapter_line)

	fps_label = _make_label("", 12, Color("8fa1a8"))
	fps_label.name = "FpsCounter"
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.position = Vector2(-120.0, 12.0)
	fps_label.size = Vector2(80.0, 20.0)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.z_index = 20
	fps_label.visible = false
	add_child(fps_label)

	prompt_label = _make_label("", 16, Color("dfc186"))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.position = Vector2(-400.0, 120.0)
	prompt_label.size = Vector2(800.0, 40.0)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt_label)


func _build_title(save_summary: String) -> void:
	start_overlay = ColorRect.new()
	start_overlay.color = Color(0.01, 0.02, 0.028, 0.94)
	start_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(start_overlay)
	var start_stack := VBoxContainer.new()
	# The stack carries the menu too, so it uses nearly the full height.
	_center(start_stack, Rect2(-420.0, -350.0, 840.0, 700.0))
	start_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	start_stack.add_theme_constant_override("separation", 8)
	start_overlay.add_child(start_stack)
	var eyebrow := _make_label("MISSION 01  //  " + Story.SUBTITLE, 15, Color("db6c2f"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_stack.add_child(eyebrow)
	var title := _make_label("MOUNTAIN\nGOAT KILLER", 52, Color("f0e7d7"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_stack.add_child(title)
	for line in Story.INTRO:
		var story := _make_label(line, 16, Color("aebdc2"))
		story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.custom_minimum_size = Vector2(760.0, 0.0)
		start_stack.add_child(story)
	field_note = _make_label("", 13, Color("e8c578"))
	field_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field_note.custom_minimum_size = Vector2(760.0, 0.0)
	start_stack.add_child(field_note)
	controls_label = _make_label("", 12, Color("8fa1a8"))
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label.custom_minimum_size = Vector2(760.0, 0.0)
	start_stack.add_child(controls_label)
	continue_button = _menu_button("CONTINUE  //  " + save_summary, func() -> void: continue_requested.emit(), 52.0)
	continue_button.visible = has_save
	start_stack.add_child(continue_button)
	deploy_button = _menu_button("NEW CLIMB  //  FORGET THE SAVED ASCENT" if has_save else "DEPLOY  //  ENTER THE RAVINE", _on_new_game_pressed, 42.0 if has_save else 52.0)
	start_stack.add_child(deploy_button)
	var menu_row := HBoxContainer.new()
	menu_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_row.add_theme_constant_override("separation", 14)
	start_stack.add_child(menu_row)
	difficulty_button = _menu_button("", func() -> void: difficulty_cycle_requested.emit(), 40.0)
	difficulty_button.custom_minimum_size.x = 300.0
	menu_row.add_child(difficulty_button)
	var title_options := _menu_button("OPTIONS", Callable(), 40.0)
	title_options.custom_minimum_size.x = 180.0
	title_options.pressed.connect(func() -> void: open_options(title_options))
	menu_row.add_child(title_options)
	var title_quit := _menu_button("LEAVE", func() -> void: quit_requested.emit(), 40.0)
	title_quit.custom_minimum_size.x = 140.0
	menu_row.add_child(title_quit)
	(continue_button if has_save else deploy_button).call_deferred("grab_focus")


func _build_pause() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.0, 0.0, 0.0, 0.58)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Only this modal receives input while the rest of the scene is paused.
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.z_index = 10
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.focus_mode = Control.FOCUS_ALL
	pause_overlay.gui_input.connect(_on_pause_input)
	pause_overlay.visible = false
	add_child(pause_overlay)
	var pause_text := _make_label("FIELD PAUSED", 26, Color("e8c578"))
	_center(pause_text, Rect2(-230.0, -110.0, 460.0, 50.0))
	pause_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_overlay.add_child(pause_text)
	# RESUME sits exactly at screen centre, where the old click-anywhere
	# overlay was most often clicked.
	pause_panel = VBoxContainer.new()
	_center(pause_panel, Rect2(-170.0, -26.0, 340.0, 190.0))
	pause_panel.add_theme_constant_override("separation", 12)
	pause_overlay.add_child(pause_panel)
	resume_button = _menu_button("RESUME", func() -> void: resume_requested.emit(), 52.0)
	# Resume on press, not release. The held button is then suppressed as fire
	# until it is let go, so re-entering the field never fires a shot.
	resume_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	pause_panel.add_child(resume_button)
	pause_options_button = _menu_button("OPTIONS", func() -> void: open_options(pause_options_button), 44.0)
	pause_panel.add_child(pause_options_button)
	pause_panel.add_child(_menu_button("RETURN TO TITLE  //  PROGRESS KEPT", func() -> void: return_to_title_requested.emit(), 44.0))


func _build_ending() -> void:
	ending_actions = HBoxContainer.new()
	ending_actions.z_index = 6
	ending_actions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ending_actions.position = Vector2(-244.0, -105.0)
	ending_actions.size = Vector2(488.0, 50.0)
	ending_actions.add_theme_constant_override("separation", 18)
	ending_actions.visible = false
	add_child(ending_actions)
	return_button = Button.new()
	return_button.text = "RETURN TO TITLE  [R]"
	return_button.custom_minimum_size = Vector2(260.0, 50.0)
	return_button.pressed.connect(func() -> void: return_to_title_requested.emit())
	ending_actions.add_child(return_button)
	var quit_button := Button.new()
	quit_button.text = "LEAVE THE MOUNTAIN"
	quit_button.custom_minimum_size = Vector2(210.0, 50.0)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	ending_actions.add_child(quit_button)


# --- Title and menus ----------------------------------------------------------------

func hide_title() -> void:
	start_overlay.visible = false
	options_menu.close()
	set_field_visible(true)


## With a save on disk, the first press only asks; the second erases it.
func _on_new_game_pressed() -> void:
	if has_save and deploy_button.text != NEW_GAME_CONFIRM:
		deploy_button.text = NEW_GAME_CONFIRM
		return
	new_game_requested.emit()


func open_options(return_focus: Control) -> void:
	options_return_focus = return_focus
	options_menu.open()


func _on_options_closed() -> void:
	settings_changed.emit()
	if is_instance_valid(options_return_focus) and options_return_focus.is_visible_in_tree():
		options_return_focus.grab_focus()


func show_pause(open: bool) -> void:
	pause_overlay.visible = open
	if open:
		resume_button.grab_focus()
	else:
		options_menu.close()


func is_pause_open() -> bool:
	return pause_overlay.visible


func _on_pause_input(event: InputEvent) -> void:
	var resume_click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var resume_key: bool = event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo
	if get_tree().paused and (resume_click or resume_key):
		pause_overlay.accept_event()
		resume_requested.emit()


# --- Field HUD -----------------------------------------------------------------------

func set_field_visible(visible_state: bool) -> void:
	for node in [ground_shade, objective_label, biome_label, ammo_label, health_label, bells_label, remembrance_label, stealth_label, exposure_bar, exposure_fill, wind_label, center_message, prompt_label, minimap, crosshair]:
		node.visible = visible_state


func set_objective(text: String) -> void:
	objective_label.text = "OBJECTIVE  //  " + text


func set_biome(biome: String) -> void:
	var info: Dictionary = Story.BIOMES.get(biome, {})
	biome_label.text = "%s  //  %s" % [info.get("title", ""), info.get("line", "")]


func set_bells(count: int) -> void:
	bells_label.text = "BELLS RECOVERED  //  %d / %d" % [count, Story.BELL_NAMES.size()]


func set_ammo(current: int, reserve: int) -> void:
	ammo_label.text = "%02d  /  %02d" % [current, reserve]


func set_health(current: int) -> void:
	health_label.text = "WILL  //  %03d" % current
	health_label.modulate = Color("ff6845") if current < 32 else Color.WHITE


func set_remembrance(hung: int, capacity: int, sensing: bool) -> void:
	var slots := ""
	for i in capacity:
		slots += "|" if i < hung else "."
	remembrance_label.text = "REMEMBRANCE  //  [%s]  %s" % [slots, "CONTACT" if sensing else InputBindings.prompt("remembrance")]
	remembrance_label.modulate = Color("fff0c0") if sensing else Color.WHITE


func set_prompt(text: String) -> void:
	if text != prompt_label.text:
		prompt_label.text = text


func set_crosshair(visible_state: bool) -> void:
	crosshair.visible = visible_state


## Stealth readout: the highest awareness among active wolverines, posture,
## light, and where the wind carries the Herdkeeper's scent.
func update_stealth(enemies: Array, player: GoatPlayer, now: float) -> void:
	var highest := 0.0
	var nearest: WolverineEnemy = null
	var nearest_distance := INF
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.state == WolverineEnemy.State.DORMANT:
			continue
		highest = maxf(highest, enemy.detection)
		var distance: float = enemy.global_position.distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	exposure_fill.size.x = 180.0 * highest
	var state_text := "HIDDEN"
	var color := Color("8fd0c8")
	if highest >= Stealth.ALERT:
		state_text = "HUNTED"
		color = Color("ff5a3c")
	elif highest >= Stealth.SUSPICIOUS:
		state_text = "SUSPICION"
		color = Color("ffb03a")
	exposure_fill.color = color
	var posture := "CROUCHED" if player.crouched else ("SPRINTING" if player.sprinting else "STANDING")
	var lit := "IN LIGHT" if player.light_exposure > 0.25 else "IN DARK"
	stealth_label.text = "%s  //  %s  //  %s" % [state_text, posture, lit]
	stealth_label.modulate = color
	var wind := Stealth.wind_at(now)
	var relative := wind.rotated(Vector3.UP, -player.rotation.y)
	var arrow := "AHEAD" if relative.z < -0.5 else ("BEHIND" if relative.z > 0.5 else ("RIGHT" if relative.x > 0.0 else "LEFT"))
	var scent := ""
	if nearest:
		scent = "  //  SCENT CARRIED AWAY" if Stealth.is_upwind(player.global_position, nearest.global_position, wind) else "  //  SCENT CARRIED TO THEM"
	wind_label.text = "WIND BLOWS %s%s" % [arrow, scent]


func update_boss(boss: WolverineEnemy, show: bool) -> void:
	boss_label.visible = show
	boss_bar.visible = show
	boss_fill.visible = show
	if not show:
		return
	var ratio := clampf(float(boss.health) / boss.max_health, 0.0, 1.0)
	boss_fill.size.x = 440.0 * ratio
	boss_label.text = "VARKAS  //  HORN STRIKE" if boss.execution_ready else "VARKAS  //  %s" % boss.boss_phase_title()
	boss_fill.color = Color("d23b28") if boss.boss_phase >= 3 else (Color("df7837") if boss.boss_phase == 2 else Color("c4a46b"))


# --- Messages -----------------------------------------------------------------------

func notice(text: String, seconds: float) -> void:
	if ending_shown:
		return
	center_message.text = text
	notice_until = Time.get_ticks_msec() * 0.001 + seconds


func _process(_delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


## Clear an expired notice.
func tick(now: float) -> void:
	if not ending_shown and notice_until > 0.0 and now > notice_until:
		notice_until = 0.0
		center_message.text = ""


func clear_center() -> void:
	center_message.text = ""
	notice_until = 0.0


func show_death() -> void:
	center_message.text = Story.DEATH % InputBindings.prompt("reload")
	notice_until = 0.0
	pause_overlay.visible = false


func show_chapter(title: String, line: String) -> void:
	if chapter_tween and chapter_tween.is_valid():
		chapter_tween.kill()
	chapter_title.text = title
	chapter_line.text = line
	chapter_title.modulate.a = 0.0
	chapter_line.modulate.a = 0.0
	chapter_tween = create_tween()
	chapter_tween.set_parallel(true)
	chapter_tween.tween_property(chapter_title, "modulate:a", 1.0, 0.8)
	chapter_tween.tween_property(chapter_line, "modulate:a", 1.0, 1.4).set_delay(0.4)
	chapter_tween.chain().tween_interval(6.5 if not ending_shown else 40.0)
	chapter_tween.chain().tween_property(chapter_title, "modulate:a", 0.0, 1.2)
	chapter_tween.parallel().tween_property(chapter_line, "modulate:a", 0.0, 1.2)


## Replace the combat HUD with the ending: veil, the victory lines, and the
## return/leave buttons.
func show_ending() -> void:
	ending_shown = true
	set_field_visible(false)
	update_boss(null, false)
	victory_veil.visible = true
	ending_actions.visible = true
	victory_veil.color.a = 0.0
	var ending_fade := create_tween()
	ending_fade.tween_property(victory_veil, "color:a", 0.72, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	chapter_title.add_theme_font_size_override("font_size", 34)
	chapter_line.add_theme_font_size_override("font_size", 17)
	chapter_line.add_theme_color_override("font_color", Color("e1d2b4"))
	chapter_line.offset_left = -520.0
	chapter_line.offset_right = 520.0
	chapter_line.offset_top = 142.0
	chapter_line.offset_bottom = 292.0
	show_chapter("THE MOUNTAIN REMEMBERS.", "\n".join(Story.VICTORY))
	center_message.text = ""
	return_button.call_deferred("grab_focus")


## Keep every on-screen key hint true to the current bindings and device.
func refresh_control_text(dead: bool) -> void:
	field_note.text = "STEALTH  //  Crouch (%s) to move quietly and stay small. Keep the wind in your face: wolverines smell what it carries. Snuff lanterns (%s), throw stones (%s) to pull them away, and strike from behind (%s) for a silent kill.\nREMEMBRANCE  //  Tap %s to hang a live round where you stand. Hold %s and the mountain fires them all at once." % [
		_key("crouch"), _key("interact"), _key("throw_stone"), _key("interact"), _key("remembrance"), _key("remembrance")]
	controls_label.text = controls_text()
	difficulty_button.text = "DIFFICULTY  //  " + Difficulty.title()
	difficulty_button.tooltip_text = Difficulty.preset().line
	if dead and not ending_shown:
		center_message.text = Story.DEATH % InputBindings.prompt("reload")


func controls_text() -> String:
	var move := "LEFT STICK"
	var look := "RIGHT STICK"
	if InputBindings.last_device != "gamepad":
		var keys: Array[String] = []
		for action in ["move_forward", "move_left", "move_back", "move_right"]:
			keys.append(_key(action))
		move = "".join(keys) if keys.all(func(k: String) -> bool: return k.length() == 1) else "/".join(keys)
		look = "MOUSE"
	return "%s MOVE   %s AIM   %s FIRE   %s FOCUS   %s SPRINT   %s JUMP   %s CROUCH   %s STONE   %s INTERACT   %s REMEMBER   %s RELOAD   %s PAUSE" % [
		move, look, _key("fire"), _key("aim"), _key("sprint"), _key("jump"), _key("crouch"),
		_key("throw_stone"), _key("interact"), _key("remembrance"), _key("reload"), _key("pause")]


# --- Helpers ------------------------------------------------------------------------

func _key(action: String) -> String:
	return InputBindings.prompt(action)


func _menu_button(text_value: String, action: Callable, height := 46.0) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, height)
	button.add_theme_font_size_override("font_size", 18 if height >= 50.0 else 15)
	if action.is_valid():
		button.pressed.connect(action)
	return button


## Anchor a control to its parent's centre with an explicit rectangle.
func _center(control: Control, rect: Rect2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
