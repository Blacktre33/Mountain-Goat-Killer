class_name OptionsMenu
extends ColorRect
## Options, reachable from the title and the pause menu. Every change applies
## immediately; settings are written to disk when the menu closes.

signal settings_changed
signal closed

const LABEL_COLOR := Color("e6d8c1")
const DIM_COLOR := Color("8fa1a8")
const ACCENT := Color("e8c578")

var waiting_action := ""
var rebind_buttons := {}
var difficulty_note: Label
var rebind_note: Label
var first_focus: Control
var controls_by_key := {}


func _ready() -> void:
	name = "OptionsMenu"
	color = Color(0.01, 0.02, 0.028, 1.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 20
	visible = false
	_build()


func open() -> void:
	_refresh()
	visible = true
	if first_focus:
		first_focus.grab_focus()


func close() -> void:
	if not visible:
		return
	waiting_action = ""
	visible = false
	GameSettings.save()
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not waiting_action.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			waiting_action = ""
			_refresh()
			get_viewport().set_input_as_handled()
			return
		var binding := InputBindings.binding_from_event(event)
		if not binding.is_empty():
			var action := waiting_action
			waiting_action = ""
			var swapped := InputBindings.rebind(action, binding)
			_refresh()
			rebind_note.text = "%s MOVED TO %s" % [_action_title(swapped), InputBindings.prompt(swapped, "keyboard")] if not swapped.is_empty() else ""
			settings_changed.emit()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var frame := VBoxContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 120.0
	frame.offset_right = -120.0
	frame.offset_top = 36.0
	frame.offset_bottom = -30.0
	frame.add_theme_constant_override("separation", 10)
	add_child(frame)
	frame.add_child(_label("OPTIONS", 30, LABEL_COLOR))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	_section(list, "DIFFICULTY")
	var difficulty := OptionButton.new()
	for key in Difficulty.ORDER:
		difficulty.add_item(Difficulty.title(key))
	difficulty.item_selected.connect(func(index: int) -> void:
		GameSettings.set_value("difficulty", Difficulty.ORDER[index])
		_refresh()
		settings_changed.emit()
	)
	_row(list, "PRESET", difficulty)
	controls_by_key["difficulty"] = difficulty
	first_focus = difficulty
	difficulty_note = _label("", 13, DIM_COLOR)
	difficulty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(difficulty_note)
	_toggle(list, "long_telegraphs", "LONG BOSS WARNINGS  (ACCESSIBILITY)")

	_section(list, "CONTROLS")
	_slider(list, "mouse_sensitivity", "MOUSE SENSITIVITY", 0.05, "%.2fx")
	_slider(list, "gamepad_sensitivity", "GAMEPAD LOOK SPEED", 0.05, "%.2fx")
	_toggle(list, "invert_y", "INVERT VERTICAL LOOK")
	_toggle(list, "aim_assist", "GAMEPAD AIM ASSIST  (SLOWS LOOK ON TARGETS)")

	_section(list, "VIDEO")
	_slider(list, "fov", "FIELD OF VIEW", 1.0, "%d°")
	_slider(list, "brightness", "BRIGHTNESS", 0.05, "%.2f")
	_slider(list, "camera_shake", "CAMERA SHAKE", 0.05, "%d%%", 100.0)

	_section(list, "AUDIO")
	_slider(list, "master_volume", "MASTER VOLUME", 0.05, "%d%%", 100.0)
	_slider(list, "sfx_volume", "EFFECTS VOLUME", 0.05, "%d%%", 100.0)
	_slider(list, "ambience_volume", "WIND  /  AMBIENCE VOLUME", 0.05, "%d%%", 100.0)

	_section(list, "KEYBOARD AND MOUSE")
	for entry in InputBindings.REBINDABLE:
		var action: String = entry[0]
		var button := Button.new()
		button.custom_minimum_size = Vector2(220.0, 0.0)
		button.pressed.connect(func() -> void:
			waiting_action = action
			rebind_note.text = "PRESS A KEY OR MOUSE BUTTON FOR %s  //  ESC CANCELS" % entry[1]
			_refresh()
		)
		rebind_buttons[action] = button
		_row(list, entry[1], button)
	rebind_note = _label("", 13, ACCENT)
	list.add_child(rebind_note)
	var reset_keys := Button.new()
	reset_keys.text = "RESTORE DEFAULT KEYS"
	reset_keys.pressed.connect(func() -> void:
		InputBindings.reset()
		rebind_note.text = ""
		_refresh()
		settings_changed.emit()
	)
	list.add_child(reset_keys)
	list.add_child(_label("GAMEPAD  //  LEFT STICK MOVE   RIGHT STICK LOOK   RT FIRE   LT FOCUS   A JUMP   B CROUCH   X INTERACT   Y RELOAD   LB STONE   RB REMEMBRANCE   L3 SPRINT   START PAUSE", 12, DIM_COLOR))

	_section(list, "PLAYTESTING")
	_toggle(list, "playtest_log", "RECORD A LOCAL PLAYTEST LOG  (NEVER UPLOADED)")
	var folder := _label("LOGS  //  " + PlaytestLog.folder(), 12, DIM_COLOR)
	folder.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	list.add_child(folder)
	var open_folder := Button.new()
	open_folder.text = "OPEN LOG FOLDER"
	open_folder.pressed.connect(func() -> void:
		DirAccess.make_dir_recursive_absolute(PlaytestLog.DIR)
		OS.shell_open(PlaytestLog.folder())
	)
	list.add_child(open_folder)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	frame.add_child(actions)
	var back := Button.new()
	back.name = "Back"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(200.0, 46.0)
	back.pressed.connect(close)
	actions.add_child(back)
	var defaults := Button.new()
	defaults.text = "RESET ALL OPTIONS"
	defaults.custom_minimum_size = Vector2(240.0, 46.0)
	defaults.pressed.connect(func() -> void:
		GameSettings.reset_defaults()
		InputBindings.install()
		rebind_note.text = ""
		_refresh()
		settings_changed.emit()
	)
	actions.add_child(defaults)


func _refresh() -> void:
	var difficulty: OptionButton = controls_by_key.difficulty
	difficulty.select(Difficulty.ORDER.find(Difficulty.key()))
	difficulty_note.text = Difficulty.preset().line
	for key in controls_by_key:
		var control: Control = controls_by_key[key]
		if control is HSlider:
			control.set_value_no_signal(float(GameSettings.get_value(key)))
			control.value_changed.emit(control.value)
		elif control is CheckButton:
			control.set_pressed_no_signal(GameSettings.get_value(key))
	for action in rebind_buttons:
		rebind_buttons[action].text = "..." if action == waiting_action else InputBindings.prompt(action, "keyboard")


func _section(list: VBoxContainer, title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	list.add_child(spacer)
	list.add_child(_label(title, 16, Color("db6c2f")))


func _row(list: VBoxContainer, title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var label := _label(title, 14, LABEL_COLOR)
	label.custom_minimum_size = Vector2(430.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	list.add_child(row)
	return row


func _slider(list: VBoxContainer, key: String, title: String, step: float, format: String, display_scale := 1.0) -> void:
	var slider := HSlider.new()
	var bounds: Vector2 = GameSettings.RANGES[key]
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = step
	slider.custom_minimum_size = Vector2(280.0, 24.0)
	var readout := _label("", 14, ACCENT)
	readout.custom_minimum_size = Vector2(80.0, 0.0)
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = format % (roundi(value * display_scale) if format.contains("%d") else value * display_scale)
		if not is_equal_approx(float(GameSettings.get_value(key)), value):
			GameSettings.set_value(key, value)
			settings_changed.emit()
	)
	var row := _row(list, title, slider)
	row.add_child(readout)
	controls_by_key[key] = slider


func _toggle(list: VBoxContainer, key: String, title: String) -> void:
	var toggle := CheckButton.new()
	toggle.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(key, on)
		settings_changed.emit()
	)
	_row(list, title, toggle)
	controls_by_key[key] = toggle


func _action_title(action: String) -> String:
	for entry in InputBindings.REBINDABLE:
		if entry[0] == action:
			return entry[1]
	return action.to_upper()


func _label(text_value: String, font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	return label
