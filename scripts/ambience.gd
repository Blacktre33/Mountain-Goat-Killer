class_name GoatAmbience
extends Node
## Per-biome ambience: one seamless stereo bed per biome (crossfaded on a biome
## change) plus one-shots scattered around the listener (creaking pine, a far
## bell, embers, rope and cage creaks, chains, sliding snow, falling rock).
## The shared wind bed lives in GoatAudio because the game drives its level.

const BEDS := {"widowpine": "amb_widowpine", "carrion": "amb_carrion", "iron_crown": "amb_iron_crown"}
const BED_DB := -5.0
const SILENT := -80.0
const FADE_SECONDS := 6.0
## Scattered one-shots per biome: [sound, weight, min metres, max metres, dB].
const EVENTS := {
	"widowpine": [["amb_creak_pine", 3.0, 14.0, 42.0, 0.0], ["amb_snow", 1.0, 18.0, 46.0, 0.0], ["amb_bell_far", 0.6, 40.0, 70.0, 0.0]],
	"carrion": [["amb_bell_far", 2.0, 40.0, 75.0, 0.0], ["amb_rock", 1.0, 18.0, 50.0, 0.0], ["amb_creak_pine", 1.0, 12.0, 36.0, 0.0], ["amb_snow", 0.5, 18.0, 46.0, -3.0]],
	"iron_crown": [["amb_ember", 3.0, 5.0, 22.0, 0.0], ["amb_cage", 2.0, 8.0, 30.0, 0.0], ["amb_chain", 2.0, 8.0, 32.0, 0.0], ["amb_rope", 1.5, 8.0, 28.0, 0.0], ["amb_bell_far", 1.0, 45.0, 75.0, 0.0], ["amb_rock", 0.5, 20.0, 50.0, 0.0]],
}
const GAP_SECONDS := {"widowpine": [9.0, 22.0], "carrion": [7.0, 18.0], "iron_crown": [3.5, 10.0]}

var biome := "widowpine"
var beds := {}
var events_played := 0

var _countdown := 6.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bed(biome)


func _process(delta: float) -> void:
	for key in beds.keys():
		var player: AudioStreamPlayer = beds[key]
		var target := BED_DB if key == biome else SILENT
		player.volume_db = move_toward(player.volume_db, target, 60.0 / FADE_SECONDS * delta)
		if key != biome and player.volume_db <= SILENT + 1.0:
			player.stop()
			player.stream = null
			player.queue_free()
			beds.erase(key)
	if get_tree().paused:
		return
	_countdown -= delta
	if _countdown <= 0.0:
		var gap: Array = GAP_SECONDS[biome]
		_countdown = randf_range(gap[0], gap[1])
		_scatter()


func shutdown() -> void:
	set_process(false)
	for key in beds:
		beds[key].stop()
		beds[key].stream = null
	beds.clear()


func set_biome(name: String) -> void:
	var key: String = GoatMusic.BIOME_ALIASES.get(name, "")
	if key.is_empty() or key == biome:
		return
	biome = key
	_ensure_bed(key)


func _ensure_bed(key: String) -> void:
	if beds.has(key):
		return
	var player := AudioStreamPlayer.new()
	var stream := load(GoatAudio.CLIP_DIR + AudioBank.SOUNDS[BEDS[key]].files[0]) as AudioStreamOggVorbis
	stream.loop = true
	player.stream = stream
	player.bus = "Ambience"
	player.volume_db = SILENT
	add_child(player)
	player.play()
	beds[key] = player


## Drops one weighted-random event at a random bearing around the listener.
func _scatter() -> void:
	var audio := get_parent() as GoatAudio
	var camera := get_viewport().get_camera_3d()
	if audio == null or camera == null:
		return
	var table: Array = EVENTS[biome]
	var total := 0.0
	for entry in table:
		total += entry[1]
	var roll := randf() * total
	for entry in table:
		roll -= entry[1]
		if roll <= 0.0:
			var bearing := randf() * TAU
			var distance := randf_range(entry[2], entry[3])
			var at := camera.global_position + Vector3(cos(bearing) * distance, randf_range(-1.0, 4.0), sin(bearing) * distance)
			audio.play_at(entry[0], at, entry[4], randf_range(0.94, 1.06), entry[3] + 25.0)
			events_played += 1
			return
