class_name InputBindings
extends RefCounted
## The game's input actions, built at startup so keyboard/mouse bindings can be
## rebound from the options menu and saved with the other settings.
##
## Keyboard bindings match physical key positions, so WASD stays under the
## same fingers on AZERTY and other layouts. Pause is fixed to Escape (by
## keycode) and Start. The gamepad layout is fixed and follows Xbox labels.

## Rebindable actions in the order the options menu lists them.
const REBINDABLE := [
	["move_forward", "MOVE FORWARD"],
	["move_back", "MOVE BACK"],
	["move_left", "MOVE LEFT"],
	["move_right", "MOVE RIGHT"],
	["jump", "JUMP"],
	["sprint", "SPRINT"],
	["crouch", "CROUCH"],
	["fire", "FIRE"],
	["aim", "FOCUS AIM"],
	["reload", "RELOAD  /  RETRY"],
	["interact", "INTERACT"],
	["throw_stone", "THROW STONE"],
	["remembrance", "REMEMBRANCE"],
]

## Default keyboard/mouse bindings: {"key": physical keycode} or {"mouse": button}.
const KEYBOARD_DEFAULTS := {
	"move_forward": [{"key": KEY_W}],
	"move_back": [{"key": KEY_S}],
	"move_left": [{"key": KEY_A}],
	"move_right": [{"key": KEY_D}],
	"jump": [{"key": KEY_SPACE}],
	"sprint": [{"key": KEY_SHIFT}],
	"crouch": [{"key": KEY_C}, {"key": KEY_CTRL}],
	"fire": [{"mouse": MOUSE_BUTTON_LEFT}],
	"aim": [{"mouse": MOUSE_BUTTON_RIGHT}],
	"reload": [{"key": KEY_R}],
	"interact": [{"key": KEY_E}],
	"throw_stone": [{"key": KEY_G}],
	"remembrance": [{"key": KEY_F}],
}

## Fixed gamepad layout: {"button": JoyButton} or {"axis": JoyAxis, "value": ±1}.
const GAMEPAD_DEFAULTS := {
	"move_forward": [{"axis": JOY_AXIS_LEFT_Y, "value": -1.0}, {"button": JOY_BUTTON_DPAD_UP}],
	"move_back": [{"axis": JOY_AXIS_LEFT_Y, "value": 1.0}, {"button": JOY_BUTTON_DPAD_DOWN}],
	"move_left": [{"axis": JOY_AXIS_LEFT_X, "value": -1.0}, {"button": JOY_BUTTON_DPAD_LEFT}],
	"move_right": [{"axis": JOY_AXIS_LEFT_X, "value": 1.0}, {"button": JOY_BUTTON_DPAD_RIGHT}],
	"look_left": [{"axis": JOY_AXIS_RIGHT_X, "value": -1.0}],
	"look_right": [{"axis": JOY_AXIS_RIGHT_X, "value": 1.0}],
	"look_up": [{"axis": JOY_AXIS_RIGHT_Y, "value": -1.0}],
	"look_down": [{"axis": JOY_AXIS_RIGHT_Y, "value": 1.0}],
	"jump": [{"button": JOY_BUTTON_A}],
	"crouch": [{"button": JOY_BUTTON_B}],
	"interact": [{"button": JOY_BUTTON_X}],
	"reload": [{"button": JOY_BUTTON_Y}],
	"throw_stone": [{"button": JOY_BUTTON_LEFT_SHOULDER}],
	"remembrance": [{"button": JOY_BUTTON_RIGHT_SHOULDER}],
	"sprint": [{"button": JOY_BUTTON_LEFT_STICK}],
	"fire": [{"axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0}],
	"aim": [{"axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0}],
	"pause": [{"button": JOY_BUTTON_START}],
}

const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.35
const GAMEPAD_LABELS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "START", JOY_BUTTON_BACK: "BACK",
	JOY_BUTTON_DPAD_UP: "D-PAD UP", JOY_BUTTON_DPAD_DOWN: "D-PAD DOWN",
	JOY_BUTTON_DPAD_LEFT: "D-PAD LEFT", JOY_BUTTON_DPAD_RIGHT: "D-PAD RIGHT",
}
const MOUSE_LABELS := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_XBUTTON1: "MOUSE 4", MOUSE_BUTTON_XBUTTON2: "MOUSE 5",
}

## "keyboard" or "gamepad": whichever the player touched last. Drives prompts.
static var last_device := "keyboard"


## (Re)build every action from defaults plus the saved keyboard overrides.
static func install() -> void:
	for action in _all_actions():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		var deadzone := TRIGGER_DEADZONE if action in ["fire", "aim"] else STICK_DEADZONE
		InputMap.action_set_deadzone(action, deadzone)
		for binding in keyboard_bindings(action):
			InputMap.action_add_event(action, _event_from(binding))
		for binding in GAMEPAD_DEFAULTS.get(action, []):
			InputMap.action_add_event(action, _event_from(binding))
	# Escape pauses by keycode, not position, so it is always the key labelled Esc.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	InputMap.action_add_event("pause", escape)


static func _all_actions() -> Array:
	var actions := KEYBOARD_DEFAULTS.keys()
	for action in GAMEPAD_DEFAULTS:
		if not action in actions:
			actions.append(action)
	return actions


## The keyboard/mouse bindings in effect for `action`.
static func keyboard_bindings(action: String) -> Array:
	if GameSettings.bindings.has(action):
		return [GameSettings.bindings[action]]
	return KEYBOARD_DEFAULTS.get(action, [])


## Replace an action's keyboard/mouse binding and apply it immediately. If
## another action already uses that input, the two swap so nothing is lost.
## Returns the action that was swapped, or "".
static func rebind(action: String, binding: Dictionary) -> String:
	if not is_valid_binding(action, binding):
		return ""
	var previous: Array = keyboard_bindings(action)
	var swapped := ""
	for entry in REBINDABLE:
		var other: String = entry[0]
		if other != action and binding in keyboard_bindings(other):
			swapped = other
			if previous.is_empty():
				GameSettings.bindings.erase(other)
			else:
				GameSettings.bindings[other] = previous[0]
			break
	GameSettings.bindings[action] = binding
	install()
	return swapped


static func reset() -> void:
	GameSettings.bindings = {}
	install()


static func is_valid_binding(action: Variant, binding: Variant) -> bool:
	if not (action is String) or not KEYBOARD_DEFAULTS.has(action) or not (binding is Dictionary):
		return false
	if binding.size() != 1:
		return false
	if binding.has("key"):
		return binding.key is int and binding.key > 0 and binding.key != KEY_ESCAPE
	if binding.has("mouse"):
		return binding.mouse is int and binding.mouse >= MOUSE_BUTTON_LEFT and binding.mouse <= MOUSE_BUTTON_XBUTTON2 \
			and not binding.mouse in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	return false


## Turn a captured key or mouse-button press into a binding, or {} if it cannot be bound.
static func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_NONE or code == KEY_ESCAPE:
			return {}
		return {"key": code}
	if event is InputEventMouseButton and event.pressed:
		var candidate := {"mouse": event.button_index}
		return candidate if is_valid_binding("fire", candidate) else {}
	return {}


static func _event_from(binding: Dictionary) -> InputEvent:
	if binding.has("key"):
		var key := InputEventKey.new()
		key.physical_keycode = binding.key
		return key
	if binding.has("mouse"):
		var mouse := InputEventMouseButton.new()
		mouse.button_index = binding.mouse
		return mouse
	if binding.has("button"):
		var button := InputEventJoypadButton.new()
		button.button_index = binding.button
		return button
	var motion := InputEventJoypadMotion.new()
	motion.axis = binding.axis
	motion.axis_value = binding.value
	return motion


static func binding_label(binding: Dictionary) -> String:
	if binding.has("key"):
		return OS.get_keycode_string(binding.key).to_upper()
	if binding.has("mouse"):
		return MOUSE_LABELS.get(binding.mouse, "MOUSE %d" % binding.mouse)
	if binding.has("button"):
		return GAMEPAD_LABELS.get(binding.button, "PAD %d" % binding.button)
	if binding.has("axis"):
		match binding.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
				return "LEFT STICK"
			_:
				return "RIGHT STICK"
	return "?"


## The prompt label for `action` on the device the player is using now.
static func prompt(action: String, device := "") -> String:
	var using := device if not device.is_empty() else last_device
	if using == "gamepad":
		var pad: Array = GAMEPAD_DEFAULTS.get(action, [])
		if not pad.is_empty():
			return binding_label(pad[0])
	if action == "pause":
		return "ESC"
	var keys := keyboard_bindings(action)
	return binding_label(keys[0]) if not keys.is_empty() else "?"


## Track which device the player last used. Returns true when it changed.
static func note_event(event: InputEvent) -> bool:
	var device := ""
	if event is InputEventJoypadButton and event.pressed:
		device = "gamepad"
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.45:
		device = "gamepad"
	elif event is InputEventKey or (event is InputEventMouseButton and event.pressed):
		device = "keyboard"
	elif event is InputEventMouseMotion and event.relative.length_squared() > 16.0:
		device = "keyboard"
	if device.is_empty() or device == last_device:
		return false
	last_device = device
	return true
