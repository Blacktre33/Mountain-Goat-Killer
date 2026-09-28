extends SceneTree
## Options, difficulty, input bindings, look helpers and save validation.
## Pure checks: no mission is built.

var failures: Array[String] = []


func _init() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func run() -> void:
	check(not GameSettings.persistent(), "Test scripts must never read or write the player's settings")
	_settings()
	_difficulty()
	_look()
	_bindings()
	_save_game()
	GameSettings.reset_defaults()
	InputBindings.install()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("Options, difficulty, bindings and save tests passed")
	quit()


func _settings() -> void:
	GameSettings.reset_defaults()
	var clean := GameSettings.sanitize({"fov": 400, "invert_y": "yes", "difficulty": "nightmare", "mystery": 3, "master_volume": 0.4})
	check(clean.fov == 100.0, "FOV above the range was not clamped")
	check(clean.invert_y == false, "A non-boolean toggle was accepted")
	check(clean.difficulty == "hunter", "An unknown difficulty was accepted")
	check(not clean.has("mystery"), "An unknown option survived sanitising")
	check(is_equal_approx(clean.master_volume, 0.4), "A valid volume was changed")
	check(clean.size() == GameSettings.DEFAULTS.size(), "Sanitised settings are missing defaults")

	GameSettings.set_value("mouse_sensitivity", 2.5)
	GameSettings.set_value("difficulty", "story")
	GameSettings.set_value("invert_y", true)
	GameSettings.bindings = {"jump": {"key": KEY_V}}
	var path := "user://test_settings.cfg"
	check(GameSettings.save_to(path) == OK, "Settings could not be written")
	GameSettings.reset_defaults()
	check(GameSettings.load_from(path) == OK, "Settings could not be read back")
	check(is_equal_approx(GameSettings.get_value("mouse_sensitivity"), 2.5), "Mouse sensitivity did not round-trip")
	check(GameSettings.get_value("difficulty") == "story", "Difficulty did not round-trip")
	check(GameSettings.get_value("invert_y") == true, "Invert Y did not round-trip")
	check(GameSettings.bindings.get("jump", {}).get("key", 0) == KEY_V, "A rebound key did not round-trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameSettings.reset_defaults()


func _difficulty() -> void:
	GameSettings.reset_defaults()
	var hunter: Dictionary = Difficulty.PRESETS.hunter
	for key in ["detection", "damage_taken", "accuracy", "telegraph"]:
		check(is_equal_approx(hunter[key], 1.0), "HUNTER must keep the verified tuning for %s" % key)
	check(hunter.regen_cap == GoatPlayer.REGEN_CAP, "HUNTER regen cap drifted from the player's constant")
	check(Difficulty.key() == "hunter" and Difficulty.scale_damage(26) == 26, "Default difficulty altered damage")
	for name in Difficulty.ORDER:
		for field in ["title", "line", "detection", "damage_taken", "accuracy", "telegraph", "regen_cap"]:
			check(Difficulty.PRESETS[name].has(field), "%s preset lacks %s" % [name, field])
	GameSettings.set_value("difficulty", "story")
	check(Difficulty.scale_damage(40) < 40 and Difficulty.scale_damage(1) == 1, "STORY did not soften damage safely")
	check(Difficulty.detection_multiplier() < 1.0 and Difficulty.telegraph_multiplier() > 1.0, "STORY did not ease detection and warnings")
	GameSettings.set_value("difficulty", "varkas")
	check(Difficulty.scale_damage(40) > 40 and Difficulty.telegraph_multiplier() < 1.0, "VARKAS did not sharpen damage and warnings")
	GameSettings.set_value("long_telegraphs", true)
	check(Difficulty.telegraph_multiplier() > 1.3, "Long warnings did not stretch even VARKAS telegraphs")
	check(Difficulty.scale_damage(0) == 0, "Zero damage became a hit")
	check(Difficulty.next("varkas") == "story" and Difficulty.next("story", -1) == "varkas", "Difficulty cycling is wrong")
	GameSettings.reset_defaults()


func _look() -> void:
	var base := FPSControls.apply_look(0.0, 0.0, Vector2(100.0, 50.0))
	var fast := FPSControls.apply_look(0.0, 0.0, Vector2(100.0, 50.0), 2.0)
	check(is_equal_approx(fast.x, base.x * 2.0) and is_equal_approx(fast.y, base.y * 2.0), "Mouse sensitivity does not scale look")
	var inverted := FPSControls.apply_look(0.0, 0.0, Vector2(0.0, 50.0), 1.0, true)
	check(is_equal_approx(inverted.y, -base.y), "Invert Y does not flip pitch")
	check(FPSControls.apply_stick_look(0.4, 0.1, Vector2.ZERO, 0.016) == Vector2(0.4, 0.1), "A centred stick moved the view")
	var half := FPSControls.apply_stick_look(0.0, 0.0, Vector2(0.5, 0.0), 1.0)
	var full := FPSControls.apply_stick_look(0.0, 0.0, Vector2(1.0, 0.0), 1.0)
	check(full.x < 0.0 and is_equal_approx(half.x, full.x * 0.25), "Stick look lacks its squared response curve")
	check(is_equal_approx(FPSControls.apply_stick_look(0.0, 0.0, Vector2(0.0, -1.0), 100.0).y, FPSControls.PITCH_MAX), "Stick look ignores the pitch clamp")
	var slowed := FPSControls.apply_stick_look(0.0, 0.0, Vector2(1.0, 0.0), 1.0, 1.0, false, FPSControls.AIM_FRICTION)
	check(is_equal_approx(slowed.x, full.x * FPSControls.AIM_FRICTION), "Aim friction does not slow the stick")
	var ahead := [Vector3(0.0, 0.0, -10.0)]
	check(FPSControls.aim_friction(Vector3.ZERO, Vector3.FORWARD, ahead) == FPSControls.AIM_FRICTION, "No friction on a target under the crosshair")
	check(FPSControls.aim_friction(Vector3.ZERO, Vector3.FORWARD, [Vector3(6.0, 0.0, -10.0)]) == 1.0, "Friction applied to a target well off the aim line")
	check(FPSControls.aim_friction(Vector3.ZERO, Vector3.FORWARD, [Vector3(0.0, 0.0, -80.0)]) == 1.0, "Friction applied beyond its range")


func _bindings() -> void:
	GameSettings.reset_defaults()
	InputBindings.install()
	for action in ["move_forward", "move_back", "move_left", "move_right", "look_left", "look_up", "jump", "sprint", "crouch", "fire", "aim", "reload", "interact", "throw_stone", "remembrance", "pause"]:
		check(InputMap.has_action(action), "Missing input action " + action)
	# The existing playback probe and pause test send these exact events.
	var w := InputEventKey.new()
	w.keycode = KEY_W
	w.physical_keycode = KEY_W
	w.pressed = true
	check(w.is_action_pressed("move_forward"), "Physical W does not move forward")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	check(escape.is_action_pressed("pause"), "Escape by keycode does not pause")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	check(start.is_action_pressed("pause"), "Start does not pause")
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.9
	check(trigger.is_action_pressed("fire"), "Right trigger does not fire")
	trigger.axis_value = 0.1
	check(not trigger.is_action_pressed("fire"), "A resting trigger fires")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	check(click.is_action_pressed("fire"), "Left mouse does not fire")

	check(InputBindings.prompt("interact", "keyboard") == "E" and InputBindings.prompt("interact", "gamepad") == "X", "Interact prompts are wrong")
	check(InputBindings.prompt("fire", "keyboard") == "LMB" and InputBindings.prompt("fire", "gamepad") == "RT", "Fire prompts are wrong")
	check(InputBindings.prompt("pause", "keyboard") == "ESC", "Pause prompt is wrong")

	check(not InputBindings.is_valid_binding("jump", {"key": KEY_ESCAPE}), "Escape could be bound away from pause")
	check(not InputBindings.is_valid_binding("jump", {"mouse": MOUSE_BUTTON_WHEEL_UP}), "The wheel could be bound")
	check(not InputBindings.is_valid_binding("pause", {"key": KEY_P}), "Pause could be rebound")
	check(InputBindings.binding_from_event(escape).is_empty(), "Escape was captured as a binding")
	check(InputBindings.binding_from_event(w) == {"key": KEY_W}, "A key press did not become a binding")

	# Rebinding jump onto E swaps interact onto jump's old key.
	var swapped := InputBindings.rebind("jump", {"key": KEY_E})
	check(swapped == "interact", "Rebinding onto a used key did not report the swap")
	check(InputBindings.prompt("jump", "keyboard") == "E" and InputBindings.prompt("interact", "keyboard") == "SPACE", "Rebinding did not swap the two actions")
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	check(e.is_action_pressed("jump") and not e.is_action_pressed("interact"), "The live input map did not follow the rebind")
	var pad_a := InputEventJoypadButton.new()
	pad_a.button_index = JOY_BUTTON_A
	pad_a.pressed = true
	check(pad_a.is_action_pressed("jump"), "Keyboard rebinding removed the gamepad binding")
	InputBindings.reset()
	check(InputBindings.prompt("jump", "keyboard") == "SPACE" and GameSettings.bindings.is_empty(), "Resetting keys failed")

	InputBindings.last_device = "keyboard"
	check(InputBindings.note_event(start) and InputBindings.last_device == "gamepad", "A pad press did not switch prompts to the gamepad")
	check(not InputBindings.note_event(pad_a), "Repeated pad input reported a device change")
	check(InputBindings.note_event(w) and InputBindings.last_device == "keyboard", "A key press did not switch prompts back")


func _save_game() -> void:
	var good := {
		"version": SaveGame.VERSION, "zone": "shrine", "bells": 5, "bell_rung": true,
		"dead": [0, 1, 2, 3, 5, 3.0], "drops": [{"x": 1.0, "y": 0.5, "z": -20.0, "bell": 5}],
		"reserve": 400, "seen": ["trailhead", "homestead", "shrine", 7], "playtime": 321.5, "deaths": 2,
	}
	var clean := SaveGame.sanitize(good)
	check(not clean.is_empty(), "A valid save was rejected")
	check(clean.zone == "shrine_rung", "A rung bell did not restore the rung shrine refuge")
	check(clean.dead == [0, 1, 2, 3, 5], "Dead spawn ids were not de-duplicated")
	check(clean.reserve == GoatPlayer.RESERVE_CAP, "Reserve ammunition was not capped")
	check(clean.seen == ["trailhead", "homestead", "shrine"], "Seen chapters kept junk")
	check(SaveGame.summary(clean) == "THE CARRION CUT  //  5 / 9 BELLS", "Continue summary is wrong: " + SaveGame.summary(clean))
	check(SaveGame.sanitize({}).is_empty(), "An empty save was accepted")
	check(SaveGame.sanitize({"version": 99, "zone": "shrine"}).is_empty(), "A future-version save was accepted")
	check(SaveGame.sanitize({"version": SaveGame.VERSION, "zone": "moon"}).is_empty(), "An unknown refuge was accepted")
	check(SaveGame.sanitize({"version": SaveGame.VERSION, "zone": "shrine", "bells": 2, "bell_rung": true}).is_empty(), "An impossible rung bell was accepted")
	check(SaveGame.sanitize("garbage").is_empty(), "A non-dictionary save was accepted")

	var path := "user://test_campaign.save"
	check(SaveGame.write_to(path, good) == OK, "Save could not be written")
	var loaded := SaveGame.read_from(path)
	check(loaded == clean, "Save did not round-trip through JSON")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	check(SaveGame.read_from(path).is_empty(), "A corrupt save was accepted")
	SaveGame.erase_at(path)
	check(not FileAccess.file_exists(path), "Save could not be erased")
	check(SaveGame.load_slot().is_empty(), "Test scripts read the real save slot")
