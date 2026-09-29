class_name GoatAudio
extends Node
## Sound for the ravine: the mixer, the sound bank and the adaptive systems.
##
## Every effect is a 44.1 kHz clip rendered offline by tools/audio/render.py
## (deterministic numpy sound design, listed in AudioBank); Kenney's CC0 snow
## footsteps and impacts cover a few contact sounds. Music, ambience beds and
## voice lines live in their own nodes (GoatMusic, GoatAmbience, GoatVoice),
## which this node creates, mixes and ducks.
##
## Mix: Master (compressor + hard limiter) <- Music, SFX, Ambience, Voice, UI;
## SFX <- Room (small foley reverb) and Canyon (big cold reverb: gunfire, howls,
## bells, roars). Positional sounds are low-passed by distance (air absorption)
## and again when the listener has no line of sight to the source (occlusion).

const VOICES := 12
const SPATIAL_VOICES := 24
const CLIP_DIR := "res://assets/audio/generated/"
const SETTINGS_PATH := "user://audio.cfg"
const MIN_GAP_MSEC := 25
const PITCH_JITTER := 0.03
const OCCLUSION_MASK := 1

## Mixer buses in creation order: name, send, trim in dB applied on top of the
## player's volume setting.
const BUSES := [
	["Music", "Master", -3.0],
	["SFX", "Master", 0.0],
	["Room", "SFX", 0.0],
	["Canyon", "SFX", 0.0],
	["Ambience", "Master", -2.0],
	["Voice", "Master", 0.0],
	["UI", "Master", -2.0],
]
## Player-facing volume channels (lower-case keys of get/set_bus_volume).
const CHANNELS := ["master", "music", "sfx", "ambience", "voice", "ui"]
const DEFAULT_VOLUME := {"master": 1.0, "music": 0.8, "sfx": 1.0, "ambience": 0.9, "voice": 1.0, "ui": 1.0}
const BUS_OF := {"sfx": "SFX", "room": "Room", "canyon": "Canyon", "ui": "UI", "ambience": "Ambience", "music": "Music", "voice": "Voice"}

## Kenney Impact Sounds (CC0): name -> [files, bus].
const CLIPS := {
	"footstep": [["footstep_snow_000", "footstep_snow_001", "footstep_snow_002", "footstep_snow_003", "footstep_snow_004"], "room"],
	"bell_strike": [["impactBell_heavy_000", "impactBell_heavy_001"], "canyon"],
	"thud": [["impactPunch_heavy_000", "impactPunch_heavy_001"], "room"],
	"stone": [["impactSoft_medium_000", "impactSoft_medium_001"], "room"],
	"clank": [["impactMetal_heavy_000", "impactMetal_heavy_001"], "canyon"],
	"wood": [["impactWood_heavy_000", "impactPlank_medium_000"], "room"],
	"rock_hit": [["impactMining_000", "impactMining_001"], "room"],
	"footstep_rock": [["impactSoft_medium_000", "impactSoft_medium_001", "impactMining_000"], "room"],
	"footstep_wood": [["impactPlank_medium_000", "impactWood_heavy_000"], "room"],
	"jump": [["footstep_snow_001", "footstep_snow_003"], "room"],
}

## Positional reach: unit_size multiplier (how far a sound stays at full level).
const REACH := {
	"shot": 3.0, "rifle_crack": 3.0, "howl": 2.5, "roar": 3.0, "quake": 3.0, "bell": 5.0, "volley": 3.0,
	"armor_break": 2.0, "gate": 2.0, "bell_toll": 3.0, "charge_rumble": 2.0, "bell_strike": 3.0,
	"amb_bell_far": 3.0,
}
## A positional "shot" is somebody else's gun (the player's own carbine is
## played with `play`), so it uses the marksman's crack.
const POSITIONAL_ALIAS := {"shot": "rifle_crack"}
## Cues requested by gameplay code that share a recording with a close relative.
const ALIAS := {
	"equip": "bolt", "bolt_open": "bolt", "bolt_close": "bolt",
	"whiz": "whoosh", "aim_charge": "sense", "wall_slam": "thud",
}
## Sounds that push the score and the wind down: [music dB, ambience dB, hold seconds].
const DUCKS := {
	"shot": [-7.0, -5.0, 0.8], "rifle_crack": [-4.0, -3.0, 0.6], "volley": [-8.0, -6.0, 1.4], "roar": [-10.0, -8.0, 2.0],
	"quake": [-10.0, -8.0, 2.2], "bell": [-9.0, -6.0, 3.0], "armor_break": [-6.0, -4.0, 1.0], "howl": [-4.0, -2.0, 1.0],
	"takedown": [-3.0, -1.0, 0.5], "tinnitus": [-6.0, -10.0, 2.5], "bell_strike": [-4.0, -2.0, 1.0],
}
const VOICE_DUCK := [-5.0, -4.0]

var streams := {}
var voices: Array = []
var spatial: Array = []
var wind_player: AudioStreamPlayer
var wind_level := 0.5
var next_voice := 0
var next_spatial := 0
var settings_path := SETTINGS_PATH
var volumes := DEFAULT_VOLUME.duplicate()
var subtitles_enabled := true
var music: GoatMusic
var ambience: GoatAmbience
var voice: GoatVoice
var subtitles: GoatSubtitles
## Names already reported as unknown (debug builds warn once per name).
var unknown_reported := {}

var _bus_of_name := {}
var _last_msec := {}
var _last_variant := {}
var _duck_events: Array = []
var _duck_now := {"Music": 0.0, "Ambience": 0.0}
var _muffle := 0.0
var _paused_mix := 0.0
var _levels_dirty := true
var _watch := GoatWatch.new()
var _watch_clock := 0.0


func _ready() -> void:
	add_to_group("audio")
	process_mode = Node.PROCESS_MODE_ALWAYS
	configure_buses()
	_load_settings()
	_load_clips()
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		voices.append(player)
	for i in SPATIAL_VOICES:
		var player := AudioStreamPlayer3D.new()
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = 6.0
		player.max_distance = 60.0
		player.attenuation_filter_cutoff_hz = 6500.0
		player.attenuation_filter_db = -18.0
		add_child(player)
		spatial.append(player)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = _load_bed("wind")
	wind_player.bus = "Ambience"
	wind_player.volume_db = -14.0
	add_child(wind_player)
	wind_player.play()
	ambience = GoatAmbience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	music = GoatMusic.new()
	music.name = "Music"
	add_child(music)
	voice = GoatVoice.new()
	voice.name = "Voice"
	add_child(voice)
	subtitles = GoatSubtitles.new()
	subtitles.name = "Subtitles"
	add_child(subtitles)
	subtitles.bind(voice, self)
	subtitles.enabled = subtitles_enabled
	_apply_levels()


func _process(delta: float) -> void:
	var target := lerpf(-20.0, -6.0, wind_level)
	wind_player.volume_db = lerpf(wind_player.volume_db, target, minf(1.0, delta * 2.0))
	_update_ducking(delta)
	_update_muffle(delta)
	_watch_clock += delta
	if _watch_clock >= 0.25:
		_watch_clock = 0.0
		_watch.drive(self, get_parent())


## Release loaded clips deterministically on fast test exits and scene reloads.
## Stopping playback first prevents stream playbacks from retaining the streams
## after this node has left the tree.
func shutdown() -> void:
	set_process(false)
	for child in [music, ambience, voice, subtitles]:
		if is_instance_valid(child):
			child.shutdown()
	if is_instance_valid(wind_player):
		wind_player.stop()
		wind_player.stream = null
	for player in voices:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player in spatial:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	streams.clear()
	voices.clear()
	spatial.clear()
	wind_player = null


func _exit_tree() -> void:
	shutdown()


# --- Public API -------------------------------------------------------------------

## Sets how hard the wind blows in the player's ears, 0..1.
func set_wind(level: float) -> void:
	wind_level = clampf(level, 0.0, 1.0)


func has_sound(name: String) -> bool:
	return streams.has(ALIAS.get(name, name))


## Every registered effect name (alphabetical).
func sound_names() -> Array:
	var names := streams.keys()
	names.sort()
	return names


## Which mix bus a sound plays on ("" when unknown).
func bus_for(name: String) -> String:
	return _bus_of_name.get(name, "")


## Non-positional: the goat's own actions and interface cues.
func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	name = ALIAS.get(name, name)
	var stream := _stream_for(name)
	if stream == null or not _gap_ok(name):
		return
	var player: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % VOICES
	player.bus = _bus_of_name[name]
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * _jitter(name)
	player.play()
	_on_played(name, 1.0)


## Positional: the warpack, the world. Sources beyond hearing are skipped, and
## a source with no line of sight to the listener is muffled and softened.
func play_at(name: String, at: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 60.0) -> void:
	name = POSITIONAL_ALIAS.get(name, ALIAS.get(name, name))
	var stream := _stream_for(name)
	if stream == null or not _gap_ok(name):
		return
	var listener := listener_position()
	var distance := 0.0
	var occlusion := 0.0
	if listener != Vector3.INF:
		distance = listener.distance_to(at)
		if distance > max_distance * 1.15:
			return
		occlusion = _occlusion(listener, at, distance)
	var player: AudioStreamPlayer3D = spatial[next_spatial]
	next_spatial = (next_spatial + 1) % SPATIAL_VOICES
	player.global_position = at
	player.bus = _bus_of_name[name]
	player.stream = stream
	player.volume_db = volume_db - 6.0 * occlusion
	player.pitch_scale = pitch * _jitter(name)
	player.max_distance = max_distance
	player.unit_size = 6.0 * REACH.get(name, 1.0)
	player.attenuation_filter_cutoff_hz = lerpf(6500.0, 1100.0, occlusion)
	player.play()
	_on_played(name, clampf(1.0 - distance / 90.0, 0.25, 1.0))


## Speak a voice line or group (see GoatVoice). `at` makes it positional.
func say(id: String, at := Vector3.INF) -> bool:
	return is_instance_valid(voice) and voice.say(id, at)


## Biome key from Story ("whitewood", "carrion_cut", "iron_crown") for the
## score and the ambience bed.
func set_biome(biome: String) -> void:
	if is_instance_valid(music):
		music.set_biome(biome)
	if is_instance_valid(ambience):
		ambience.set_biome(biome)


## Adaptive score state: title, stealth, suspicious, combat, boss1..3, victory, death.
func set_music_state(state: String) -> void:
	if is_instance_valid(music):
		music.set_state(state)


## Ringing ears: muffle everything but the ringing itself for a few seconds.
func stun(seconds := 3.0) -> void:
	play("tinnitus")
	_muffle = clampf(seconds / 3.0, 0.0, 1.5)


func get_bus_volume(channel: String) -> float:
	return volumes.get(channel.to_lower(), 1.0)


func set_bus_volume(channel: String, linear: float, save := true) -> void:
	var key := channel.to_lower()
	if not CHANNELS.has(key):
		return
	volumes[key] = clampf(linear, 0.0, 1.0)
	_levels_dirty = true
	_apply_levels()
	if save:
		save_settings()


func set_subtitles_enabled(enabled: bool, save := true) -> void:
	subtitles_enabled = enabled
	if is_instance_valid(subtitles):
		subtitles.enabled = enabled
	if save:
		save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in CHANNELS:
		cfg.set_value("volume", key, volumes[key])
	cfg.set_value("accessibility", "subtitles", subtitles_enabled)
	cfg.save(settings_path)


# --- Mixer --------------------------------------------------------------------------

## Creates the bus tree and its effects when AudioServer does not already carry
## them (default_bus_layout.tres is built from this same function).
static func configure_buses() -> void:
	for spec in BUSES:
		if AudioServer.get_bus_index(spec[0]) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, spec[0])
		AudioServer.set_bus_send(index, spec[1])
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -14.0
		compressor.ratio = 3.0
		compressor.attack_us = 15000.0
		compressor.release_ms = 240.0
		compressor.gain = 4.0
		AudioServer.add_bus_effect(master, compressor)
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.pre_gain_db = 0.0
		limiter.release = 0.08
		AudioServer.add_bus_effect(master, limiter)
	_ensure_effect("Canyon", AudioEffectReverb, _canyon_reverb)
	_ensure_effect("Room", AudioEffectReverb, _room_reverb)
	_ensure_effect("Voice", AudioEffectReverb, _voice_reverb)
	for bus in ["Music", "SFX", "Ambience"]:
		_ensure_effect(bus, AudioEffectLowPassFilter, _idle_lowpass, false)


static func _ensure_effect(bus: String, effect_class: Variant, build: Callable, enabled := true) -> void:
	var index := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(index):
		if is_instance_of(AudioServer.get_bus_effect(index, i), effect_class):
			return
	AudioServer.add_bus_effect(index, build.call())
	AudioServer.set_bus_effect_enabled(index, AudioServer.get_bus_effect_count(index) - 1, enabled)


static func _canyon_reverb() -> AudioEffectReverb:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.93
	reverb.damping = 0.62
	reverb.spread = 1.0
	reverb.predelay_msec = 45.0
	reverb.predelay_feedback = 0.25
	reverb.hipass = 0.08
	reverb.dry = 1.0
	reverb.wet = 0.30
	return reverb


static func _room_reverb() -> AudioEffectReverb:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.4
	reverb.damping = 0.55
	reverb.predelay_msec = 12.0
	reverb.dry = 1.0
	reverb.wet = 0.08
	return reverb


static func _voice_reverb() -> AudioEffectReverb:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.55
	reverb.damping = 0.7
	reverb.predelay_msec = 20.0
	reverb.dry = 1.0
	reverb.wet = 0.10
	return reverb


static func _idle_lowpass() -> AudioEffectLowPassFilter:
	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = 20500.0
	filter.resonance = 0.6
	return filter


static func _lowpass_of(bus: String) -> int:
	var index := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(index):
		if AudioServer.get_bus_effect(index, i) is AudioEffectLowPassFilter:
			return i
	return -1


static func _set_lowpass(bus: String, cutoff_hz: float) -> void:
	var slot := _lowpass_of(bus)
	if slot < 0:
		return
	var index := AudioServer.get_bus_index(bus)
	var filter := AudioServer.get_bus_effect(index, slot) as AudioEffectLowPassFilter
	var active := cutoff_hz < 20000.0
	filter.cutoff_hz = cutoff_hz
	if AudioServer.is_bus_effect_enabled(index, slot) != active:
		AudioServer.set_bus_effect_enabled(index, slot, active)


func _apply_levels() -> void:
	for spec in BUSES:
		var index := AudioServer.get_bus_index(spec[0])
		if index == -1:
			continue
		var channel: String = spec[0].to_lower()
		# Room and Canyon have no slider: they follow SFX through their send.
		var linear: float = volumes.get(channel, 1.0) if CHANNELS.has(channel) else 1.0
		var db: float = _linear_db(linear) + float(spec[2])
		db += float(_duck_now.get(spec[0], 0.0))
		if spec[0] == "Music":
			db -= 7.0 * _paused_mix
		AudioServer.set_bus_volume_db(index, db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), _linear_db(volumes.master))
	_levels_dirty = false


static func _linear_db(linear: float) -> float:
	return -80.0 if linear <= 0.0001 else linear_to_db(linear)


func _on_played(name: String, scale: float) -> void:
	if name == "tinnitus":
		_muffle = maxf(_muffle, 1.0)
	var duck: Array = DUCKS.get(name, [])
	if not duck.is_empty():
		_duck_events.append([duck[0] * scale, duck[1] * scale, Time.get_ticks_msec() * 0.001 + duck[2]])


## Ducking has a fast attack and a slow release, like a sidechain compressor.
func _update_ducking(delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var music_target := 0.0
	var ambience_target := 0.0
	for i in range(_duck_events.size() - 1, -1, -1):
		var event: Array = _duck_events[i]
		if now > event[2]:
			_duck_events.remove_at(i)
		else:
			music_target = minf(music_target, event[0])
			ambience_target = minf(ambience_target, event[1])
	if is_instance_valid(voice) and voice.is_speaking():
		music_target = minf(music_target, VOICE_DUCK[0])
		ambience_target = minf(ambience_target, VOICE_DUCK[1])
	var paused := get_tree().paused
	_paused_mix = move_toward(_paused_mix, 1.0 if paused else 0.0, delta * 4.0)
	var changed := false
	for entry in [["Music", music_target], ["Ambience", ambience_target]]:
		var current: float = _duck_now[entry[0]]
		var speed := 90.0 if entry[1] < current else 14.0
		var next := move_toward(current, entry[1], speed * delta)
		if not is_equal_approx(next, current):
			_duck_now[entry[0]] = next
			changed = true
	if changed or _levels_dirty or paused or (_paused_mix > 0.0 and _paused_mix < 1.0):
		_apply_levels()
	_set_lowpass("Music", lerpf(20500.0, 650.0, _paused_mix))


func _update_muffle(delta: float) -> void:
	_muffle = move_toward(_muffle, 0.0, delta / 3.0)
	var amount := smoothstep(0.0, 0.6, _muffle)
	var cutoff := lerpf(20500.0, 700.0, amount)
	_set_lowpass("SFX", cutoff)
	_set_lowpass("Ambience", lerpf(20500.0, 1400.0, amount))


# --- Settings -------------------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for key in CHANNELS:
		volumes[key] = clampf(float(cfg.get_value("volume", key, volumes[key])), 0.0, 1.0)
	subtitles_enabled = bool(cfg.get_value("accessibility", "subtitles", true))


# --- Sound bank --------------------------------------------------------------------------

func _load_clips() -> void:
	for name in CLIPS:
		var variants: Array = []
		for file in CLIPS[name][0]:
			var path := "res://assets/audio/%s.ogg" % file
			if ResourceLoader.exists(path):
				variants.append(load(path))
		if not variants.is_empty():
			streams[name] = variants
			_bus_of_name[name] = BUS_OF[CLIPS[name][1]]
	for name in AudioBank.SOUNDS:
		var entry: Dictionary = AudioBank.SOUNDS[name]
		if entry.bus in ["music", "ambience"]:
			continue
		var variants: Array = []
		for file in entry.files:
			variants.append(load(CLIP_DIR + file))
		streams[name] = variants
		_bus_of_name[name] = BUS_OF[entry.bus]


static func _load_bed(name: String) -> AudioStream:
	var stream := load(CLIP_DIR + AudioBank.SOUNDS[name].files[0]) as AudioStreamOggVorbis
	stream.loop = true
	return stream


func _stream_for(name: String) -> AudioStream:
	var entry: Variant = streams.get(name)
	if entry == null:
		# After shutdown() the bank is empty on purpose; only a live bank can have typos.
		if OS.is_debug_build() and not streams.is_empty() and not unknown_reported.has(name):
			unknown_reported[name] = true
			push_warning("GoatAudio: unknown sound name '%s' (see AudioBank.SOUNDS and GoatAudio.CLIPS)" % name)
		return null
	var variants: Array = entry
	var pick := 0
	if variants.size() > 1:
		pick = randi() % variants.size()
		if pick == _last_variant.get(name, -1):
			pick = (pick + 1) % variants.size()
		_last_variant[name] = pick
	return variants[pick]


func _gap_ok(name: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_msec.get(name, -1000)) < MIN_GAP_MSEC:
		return false
	_last_msec[name] = now
	return true


func last_played_msec(name: String) -> int:
	return int(_last_msec.get(name, -1000000))


func _jitter(name: String) -> float:
	var bus: String = _bus_of_name.get(name, "")
	return 1.0 if bus == "UI" else 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)


# --- Spatial helpers -----------------------------------------------------------------------

func listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera else Vector3.INF


## 0 = clear line of sight, 1 = fully blocked (two rays: chest and head height).
func _occlusion(listener: Vector3, at: Vector3, distance: float) -> float:
	if distance < 3.0:
		return 0.0
	var space := get_viewport().world_3d.direct_space_state
	var blocked := 0.0
	for lift in [0.0, 1.2]:
		# End the ray just short of the source so a sound sitting in a wall or on
		# the ground does not occlude itself.
		var end := (at + Vector3(0.0, lift, 0.0)).move_toward(listener, 0.7)
		var query := PhysicsRayQueryParameters3D.create(listener, end, OCCLUSION_MASK)
		if not space.intersect_ray(query).is_empty():
			blocked += 0.5
	return blocked
