class_name GoatMusic
extends Node
## Adaptive score. Each biome owns four synchronised stems (drone, motif,
## tension, combat); each of Varkas' three phases owns a base and a perc stem;
## victory and death are one-shots. `set_state` and `set_biome` only change fade
## targets, so every transition is a crossfade and every stem keeps its place in
## the loop. All stems are rendered by tools/audio/music.py.

signal state_changed(state: String)

const STATES := ["title", "stealth", "suspicious", "combat", "boss1", "boss2", "boss3", "victory", "death"]
const KINDS := ["drone", "motif", "tension", "combat"]
const BIOME_ALIASES := {
	"whitewood": "widowpine", "widowpine": "widowpine",
	"carrion_cut": "carrion", "carrion": "carrion",
	"iron_crown": "iron_crown",
}
const SILENT := -80.0
const MUSIC_BUS := "Music"
## Stem gain in dB per state. Anything not listed for a state is silent.
const MATRIX := {
	"title": {"drone": 0.0, "motif": -3.0},
	"stealth": {"drone": 0.0, "motif": -1.0},
	"suspicious": {"drone": -2.0, "motif": -14.0, "tension": -1.0},
	"combat": {"drone": -9.0, "tension": -6.0, "combat": 0.0},
}
## Seconds a stem takes to travel 60 dB toward louder / quieter targets.
const FADE_IN := {"title": 4.0, "stealth": 5.0, "suspicious": 3.0, "combat": 1.2, "boss1": 2.0, "boss2": 1.5, "boss3": 1.2, "victory": 2.0, "death": 0.5}
const FADE_OUT := {"title": 4.0, "stealth": 6.0, "suspicious": 5.0, "combat": 6.0, "boss1": 3.0, "boss2": 2.5, "boss3": 2.5, "victory": 3.0, "death": 0.8}
const RETIRE_SECONDS := 12.0

var state := "title"
var biome := "widowpine"
## Stem groups by key ("biome:widowpine", "boss:2"): {kind: AudioStreamPlayer}.
var groups := {}
## One-shot players (victory, death): {"player", "state"}.
var oneshots: Array = []

var _silent_for := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_group("biome:" + biome)


func _process(delta: float) -> void:
	var retire: Array = []
	for key in groups:
		var quiet := true
		for kind in groups[key]:
			var player: AudioStreamPlayer = groups[key][kind]
			var target := _target_db(key, kind)
			var seconds: float = (FADE_IN if target > player.volume_db else FADE_OUT).get(state, 4.0)
			player.volume_db = move_toward(player.volume_db, target, 60.0 / maxf(seconds, 0.05) * delta)
			if player.volume_db > SILENT + 1.0:
				quiet = false
		if quiet:
			_silent_for[key] = _silent_for.get(key, 0.0) + delta
			if _silent_for[key] > RETIRE_SECONDS and key != "biome:" + biome:
				retire.append(key)
		else:
			_silent_for[key] = 0.0
	for key in retire:
		_free_group(key)
	for i in range(oneshots.size() - 1, -1, -1):
		var shot: Dictionary = oneshots[i]
		var player: AudioStreamPlayer = shot.player
		var wanted: bool = shot.state == state
		player.volume_db = move_toward(player.volume_db, 0.0 if wanted else SILENT, 60.0 / (FADE_IN[state] if wanted else FADE_OUT[state]) * delta)
		if not player.playing or (not wanted and player.volume_db <= SILENT + 1.0):
			player.stop()
			player.stream = null
			player.queue_free()
			oneshots.remove_at(i)


func shutdown() -> void:
	set_process(false)
	for key in groups.keys():
		_free_group(key)
	for shot in oneshots:
		shot.player.stop()
		shot.player.stream = null
		shot.player.queue_free()
	oneshots.clear()


## Switch the score: title, stealth, suspicious, combat, boss1, boss2, boss3, victory, death.
func set_state(next: String) -> void:
	if not STATES.has(next):
		if OS.is_debug_build():
			push_warning("GoatMusic: unknown state '%s' (expected one of %s)" % [next, STATES])
		return
	if next == state:
		return
	state = next
	if next.begins_with("boss"):
		_ensure_group("boss:" + next.trim_prefix("boss"))
	elif next == "victory" or next == "death":
		_start_oneshot(next)
	state_changed.emit(state)


## Switch the biome colour. Accepts Story keys ("whitewood", "carrion_cut",
## "iron_crown") or the stem names ("widowpine", "carrion").
func set_biome(name: String) -> void:
	var key: String = BIOME_ALIASES.get(name, "")
	if key.is_empty():
		if OS.is_debug_build():
			push_warning("GoatMusic: unknown biome '%s'" % name)
		return
	if key == biome:
		return
	biome = key
	_ensure_group("biome:" + biome)


## Current gain target in dB of a stem, for tests and debugging.
func stem_target_db(kind: String, group_biome := "") -> float:
	return _target_db("biome:" + (group_biome if not group_biome.is_empty() else biome), kind)


func _target_db(key: String, kind: String) -> float:
	if key.begins_with("boss:"):
		return 0.0 if state == "boss" + key.trim_prefix("boss:") else SILENT
	if key != "biome:" + biome:
		return SILENT
	return MATRIX.get(state, {}).get(kind, SILENT)


func _ensure_group(key: String) -> void:
	if groups.has(key):
		return
	var stems := {}
	if key.begins_with("boss:"):
		var phase := key.trim_prefix("boss:")
		for kind in ["base", "perc"]:
			stems[kind] = _make_stem("music_boss%s_%s" % [phase, kind])
	else:
		var name := key.trim_prefix("biome:")
		for kind in KINDS:
			stems[kind] = _make_stem("music_%s_%s" % [name, kind])
	# Start together so the stems share one beat grid.
	for kind in stems:
		stems[kind].play()
	groups[key] = stems


func _make_stem(bank_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var stream := load(GoatAudio.CLIP_DIR + AudioBank.SOUNDS[bank_name].files[0]) as AudioStreamOggVorbis
	stream.loop = true
	player.stream = stream
	player.bus = MUSIC_BUS
	player.volume_db = SILENT
	add_child(player)
	return player


func _free_group(key: String) -> void:
	for kind in groups.get(key, {}):
		var player: AudioStreamPlayer = groups[key][kind]
		player.stop()
		player.stream = null
		player.queue_free()
	groups.erase(key)
	_silent_for.erase(key)


func _start_oneshot(name: String) -> void:
	var player := AudioStreamPlayer.new()
	var stream := load(GoatAudio.CLIP_DIR + AudioBank.SOUNDS["music_" + name].files[0]) as AudioStreamOggVorbis
	stream.loop = false
	player.stream = stream
	player.bus = MUSIC_BUS
	player.volume_db = SILENT
	add_child(player)
	player.play()
	oneshots.append({"player": player, "state": name})
