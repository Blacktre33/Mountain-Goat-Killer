class_name GameMusic
extends Node
## Adaptive score, synthesised like the rest of the game's audio. Four layers
## of the same 16-second length play in lockstep and crossfade with what the
## warpack knows:
##
## - calm: a low D-minor drone and the herd-bell motif (D, F, A, C).
## - tension: a slow heartbeat under a dissonant high tremolo.
## - combat: drums and a driving bass ostinato.
## - boss: Orin's bell tolling over a low brass drone, for Varkas.
##
## The layers are built once per run on a worker thread and cached, so returning
## to the title neither stalls nor rebuilds them. Test and tool scripts never
## start synthesis (see GameSettings.persistent()).

const RATE := 11025
const LOOP_SECONDS := 16.0
const LAYERS := ["calm", "tension", "combat", "boss"]
## Mix level of each layer at full intensity, before the Music bus.
const LAYER_DB := -9.0
const FADE_IN_PER_SECOND := 0.7
const FADE_OUT_PER_SECOND := 0.25
## A calmer state waits this long before taking over, so a brief break in a
## fight does not drop the drums.
const RELAX_HOLD_SECONDS := 5.0
const RANK := {"silent": 0, "title": 1, "victory": 1, "calm": 1, "tension": 2, "combat": 3, "boss": 4}

## Lets a test exercise the real build-and-play lifecycle from a script run.
static var allow_in_scripts := false
static var bank: Dictionary = {}
static var building_task := -1
static var built_bytes: Dictionary = {}

var players: Dictionary = {}
var gains: Dictionary = {}
var state := "title"
var requested := "title"
var hold_left := 0.0
var playing := false


## Linear gain for every layer in a music state.
static func layer_targets(music_state: String) -> Dictionary:
	var targets := {"calm": 0.0, "tension": 0.0, "combat": 0.0, "boss": 0.0}
	match music_state:
		"title", "victory":
			targets.calm = 0.8
		"calm":
			targets.calm = 1.0
		"tension":
			targets.calm = 0.55
			targets.tension = 1.0
		"combat":
			targets.tension = 0.5
			targets.combat = 1.0
		"boss":
			targets.tension = 0.3
			targets.combat = 0.75
			targets.boss = 1.0
	return targets


## Escalations take over at once; a calmer request must persist for
## RELAX_HOLD_SECONDS. Returns [new_state, hold_left].
static func step_state(current: String, wanted: String, hold: float, delta: float) -> Array:
	if wanted == current:
		return [current, RELAX_HOLD_SECONDS]
	if RANK.get(wanted, 0) >= RANK.get(current, 0) or wanted in ["silent", "title", "victory"]:
		return [wanted, RELAX_HOLD_SECONDS]
	hold -= delta
	if hold <= 0.0:
		return [wanted, RELAX_HOLD_SECONDS]
	return [current, hold]


func _ready() -> void:
	for layer in LAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = &"Music"
		player.volume_db = -80.0
		add_child(player)
		players[layer] = player
		gains[layer] = 0.0
	if not GameSettings.persistent() and not allow_in_scripts:
		set_process(false)
		return
	if bank.is_empty() and building_task < 0:
		building_task = WorkerThreadPool.add_task(func() -> void: GameMusic._build_bank_bytes(), false, "Synthesise music")


func request(music_state: String) -> void:
	requested = music_state


func _process(delta: float) -> void:
	if not playing:
		if bank.is_empty():
			if building_task < 0 or not WorkerThreadPool.is_task_completed(building_task):
				return
			WorkerThreadPool.wait_for_task_completion(building_task)
			building_task = -1
			for layer in LAYERS:
				bank[layer] = _stream(built_bytes[layer])
			built_bytes.clear()
		_start()
	var next := step_state(state, requested, hold_left, delta)
	state = next[0]
	hold_left = next[1]
	var targets := layer_targets(state)
	for layer in LAYERS:
		var gain: float = gains[layer]
		var target: float = targets[layer]
		gain = move_toward(gain, target, delta * (FADE_IN_PER_SECOND if target > gain else FADE_OUT_PER_SECOND))
		gains[layer] = gain
		players[layer].volume_db = LAYER_DB + linear_to_db(maxf(gain, 0.0001))


func _start() -> void:
	# Start every layer on the same mix so they stay locked together.
	for layer in LAYERS:
		players[layer].stream = bank[layer]
		players[layer].play()
	playing = true


## Stop and release playback before a scene change or exit. The cached bank
## stays for the next scene; an unfinished build is waited for so the worker
## never outlives the tree.
func shutdown() -> void:
	set_process(false)
	for player in players.values():
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	playing = false


func _exit_tree() -> void:
	shutdown()


static func _build_bank_bytes() -> void:
	var result := {}
	for layer in LAYERS:
		result[layer] = _to_bytes(synthesize(layer, LOOP_SECONDS, RATE))
	built_bytes = result


## Wait for a pending build (used at exit so no worker outlives the engine).
static func finish_pending_build() -> void:
	if building_task >= 0:
		WorkerThreadPool.wait_for_task_completion(building_task)
		building_task = -1


## Drop the cached layers when the game is really leaving, not just returning
## to the title, so no generated stream outlives the engine.
static func release_bank() -> void:
	finish_pending_build()
	bank.clear()
	built_bytes.clear()


static func _to_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return bytes


static func _stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = bytes.size() / 2
	return stream


# --- Synthesis ----------------------------------------------------------------

const D2 := 73.42
const A2 := 110.0
const D3 := 146.83
const MOTIF := [293.66, 349.23, 220.0, 261.63]  # D4 F4 A3 C4, one every four seconds
const OSTINATO := [73.42, 73.42, 87.31, 73.42, 98.0, 73.42, 87.31, 82.41]  # D D F D G D F E


## One loopable layer. The tail is generated past the loop point and
## crossfaded into the head; every layer's rhythm repeats within the loop, so
## the seam lands on matching material.
static func synthesize(layer: String, seconds: float, rate: int) -> PackedFloat32Array:
	var fade := 0.5
	var total := int((seconds + fade) * rate)
	var raw := PackedFloat32Array()
	raw.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layer)
	var lp := 0.0
	var phase_a := 0.0
	var phase_b := 0.0
	for i in total:
		var t := float(i) / rate
		var loop_t := fmod(t, seconds)
		var v := 0.0
		match layer:
			"calm":
				var swell := 0.6 + 0.4 * sin(TAU * t / seconds)
				v = (sin(TAU * D2 * t) * 0.22 + sin(TAU * A2 * t) * 0.14 + sin(TAU * D3 * t) * 0.07) * swell
				var note := int(loop_t / 4.0) % MOTIF.size()
				var since := fmod(loop_t, 4.0)
				v += _bell_tone(MOTIF[note], since, 1.1) * 0.22
			"tension":
				var beat := fmod(t, 1.0)
				v = _thump(beat, 46.0) * 0.5 + _thump(beat - 0.26, 42.0) * 0.32
				var trem := 0.5 + 0.5 * sin(TAU * 7.0 * t)
				var swell := 0.5 + 0.5 * sin(TAU * t / (seconds * 0.5))
				v += (sin(TAU * 311.13 * t) + sin(TAU * 293.66 * t)) * 0.035 * trem * swell
			"combat":
				var step_len := 0.25
				var step := int(t / step_len)
				var in_step := fmod(t, step_len)
				var freq: float = OSTINATO[step % OSTINATO.size()]
				phase_a += TAU * freq / rate
				var saw := 2.0 * fmod(phase_a / TAU, 1.0) - 1.0
				lp += (saw - lp) * 0.08
				v = lp * exp(-in_step * 9.0) * 0.45
				var beat := fmod(t, 1.0)
				v += _thump(beat, 55.0) * 0.6
				v += _thump(fmod(t + 0.5, 2.0), 90.0) * 0.28
				var snare_t := fmod(t + 1.0, 2.0)
				if snare_t < 0.2:
					v += (rng.randf() * 2.0 - 1.0) * exp(-snare_t * 24.0) * 0.22
			"boss":
				var since := fmod(loop_t, 4.0)
				v = _bell_tone(D3, since, 0.55) * 0.34
				phase_a += TAU * 36.71 / rate
				phase_b += TAU * 55.0 / rate
				var brass := (2.0 * fmod(phase_a / TAU, 1.0) - 1.0) + (2.0 * fmod(phase_b / TAU, 1.0) - 1.0) * 0.6
				lp += (brass - lp) * 0.035
				v += lp * (0.55 + 0.45 * sin(TAU * t / seconds)) * 0.3
		raw[i] = v
	var out := PackedFloat32Array()
	out.resize(int(seconds * rate))
	var fade_samples := total - out.size()
	for i in out.size():
		if i < fade_samples:
			var w := float(i) / fade_samples
			out[i] = raw[i] * w + raw[out.size() + i] * (1.0 - w)
		else:
			out[i] = raw[i]
	return out


## A struck bell: slightly inharmonic partials with a soft strike.
static func _bell_tone(frequency: float, since: float, decay: float) -> float:
	if since < 0.0:
		return 0.0
	var v := 0.0
	var ratios := [1.0, 2.0, 2.4, 3.0]
	var amps := [1.0, 0.5, 0.35, 0.2]
	for k in ratios.size():
		v += sin(TAU * frequency * ratios[k] * since) * amps[k] * exp(-since * decay * (1.0 + k * 0.5))
	return v * minf(1.0, since * 120.0)


## A low drum hit starting at `since` = 0.
static func _thump(since: float, frequency: float) -> float:
	if since < 0.0 or since > 0.6:
		return 0.0
	return sin(TAU * frequency * (1.0 + 1.5 * exp(-since * 30.0)) * since) * exp(-since * 11.0)
