class_name GameSettings
extends RefCounted
## Player options, persisted to `user://settings.cfg`.
##
## Values live in one static dictionary so the player, enemies and HUD can read
## them without an autoload. Test and tool scripts run under their own
## SceneTree subclass; they always see the defaults and never read or write
## the player's real settings, save, or playtest logs (see `persistent()`).

const PATH := "user://settings.cfg"
const VERSION := 1

const DEFAULTS := {
	"mouse_sensitivity": 1.0,
	"gamepad_sensitivity": 1.0,
	"invert_y": false,
	"fov": 68.0,
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"ambience_volume": 1.0,
	"brightness": 1.0,
	"camera_shake": 1.0,
	"difficulty": "hunter",
	"long_telegraphs": false,
	"aim_assist": true,
	"playtest_log": true,
}

## Inclusive [min, max] for every numeric option.
const RANGES := {
	"mouse_sensitivity": Vector2(0.2, 3.0),
	"gamepad_sensitivity": Vector2(0.2, 3.0),
	"fov": Vector2(60.0, 100.0),
	"master_volume": Vector2(0.0, 1.0),
	"sfx_volume": Vector2(0.0, 1.0),
	"ambience_volume": Vector2(0.0, 1.0),
	"brightness": Vector2(0.6, 1.6),
	"camera_shake": Vector2(0.0, 1.0),
}

## Audio buses and the option that drives each.
const BUSES := {"Master": "master_volume", "SFX": "sfx_volume", "Ambience": "ambience_volume"}

static var values: Dictionary = DEFAULTS.duplicate()
## Rebound keyboard/mouse controls: action -> serialized binding (see InputBindings).
static var bindings: Dictionary = {}
static var loaded := false


## False while a test or tool script owns the main loop. Only a real play
## session touches user files.
static func persistent() -> bool:
	var loop := Engine.get_main_loop()
	return loop != null and loop.get_script() == null


static func ensure_loaded() -> void:
	if loaded:
		return
	loaded = true
	if persistent():
		load_from(PATH)


static func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Unknown setting: " + key)
		return
	values[key] = _clean(key, value)


static func reset_defaults() -> void:
	values = DEFAULTS.duplicate()
	bindings = {}


static func save() -> void:
	if persistent():
		save_to(PATH)


## Keep known keys, restore missing ones, clamp numbers, reject bad types.
static func sanitize(raw: Dictionary) -> Dictionary:
	var clean := DEFAULTS.duplicate()
	for key in DEFAULTS:
		if raw.has(key):
			clean[key] = _clean(key, raw[key])
	return clean


static func _clean(key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	if fallback is bool:
		return value if value is bool else fallback
	if fallback is float:
		if not (value is float or value is int):
			return fallback
		var bounds: Vector2 = RANGES[key]
		return clampf(float(value), bounds.x, bounds.y)
	if key == "difficulty":
		return value if value is String and Difficulty.PRESETS.has(value) else fallback
	return value if typeof(value) == typeof(fallback) else fallback


static func save_to(path: String) -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	for key in values:
		config.set_value("options", key, values[key])
	for action in bindings:
		config.set_value("bindings", action, bindings[action])
	return config.save(path)


static func load_from(path: String) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		return error
	var raw := {}
	if config.has_section("options"):
		for key in config.get_section_keys("options"):
			raw[key] = config.get_value("options", key)
	values = sanitize(raw)
	bindings = {}
	if config.has_section("bindings"):
		for action in config.get_section_keys("bindings"):
			var binding: Variant = config.get_value("bindings", action)
			if InputBindings.is_valid_binding(action, binding):
				bindings[action] = binding
	return OK


## Push volume levels into the audio buses.
static func apply_audio() -> void:
	for bus_name in BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		var level: float = get_value(BUSES[bus_name])
		AudioServer.set_bus_mute(index, level <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.001)))


static func hip_fov() -> float:
	return get_value("fov")
