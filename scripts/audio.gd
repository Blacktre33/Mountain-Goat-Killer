class_name GoatAudio
extends Node
## Sound for the ravine. Kenney's CC0 snow footsteps and impact clips cover
## contact sounds; everything else (the carbine, hits, howls, growls, the
## mother bell, wind, the gate, chapter stings) is synthesised into
## AudioStreamWAV buffers once at startup, so the game ships no other audio.

const RATE := 22050
const VOICES := 8
const SPATIAL_VOICES := 12
const CLIPS := {
	"footstep": ["footstep_snow_000", "footstep_snow_001", "footstep_snow_002", "footstep_snow_003", "footstep_snow_004"],
	"bell_strike": ["impactBell_heavy_000", "impactBell_heavy_001"],
	"thud": ["impactPunch_heavy_000", "impactPunch_heavy_001"],
	"stone": ["impactSoft_medium_000", "impactSoft_medium_001"],
	"clank": ["impactMetal_heavy_000", "impactMetal_heavy_001"],
	"wood": ["impactWood_heavy_000", "impactPlank_medium_000"],
	"rock_hit": ["impactMining_000", "impactMining_001"],
}

var streams := {}
var voices: Array = []
var spatial: Array = []
var wind_player: AudioStreamPlayer
var wind_level := 0.5
var next_voice := 0
var next_spatial := 0


func _ready() -> void:
	add_to_group("audio")
	_load_clips()
	_synthesise()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	for i in SPATIAL_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.unit_size = 6.0
		voice.max_distance = 60.0
		add_child(voice)
		spatial.append(voice)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = streams.wind
	wind_player.volume_db = -14.0
	add_child(wind_player)
	wind_player.play()


func _process(delta: float) -> void:
	var target := lerpf(-20.0, -6.0, wind_level)
	wind_player.volume_db = lerpf(wind_player.volume_db, target, minf(1.0, delta * 2.0))


## Sets how hard the wind blows in the player's ears, 0..1.
func set_wind(level: float) -> void:
	wind_level = clampf(level, 0.0, 1.0)


func has_sound(name: String) -> bool:
	return streams.has(name)


func _stream_for(name: String) -> AudioStream:
	var entry = streams.get(name)
	if entry is Array:
		return entry[randi() % entry.size()]
	return entry


## Non-positional: the goat's own actions and interface cues.
func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _stream_for(name)
	if stream == null:
		return
	var voice: AudioStreamPlayer = voices[next_voice]
	next_voice = (next_voice + 1) % VOICES
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()


## Positional: the warpack, the world.
func play_at(name: String, at: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 60.0) -> void:
	var stream := _stream_for(name)
	if stream == null:
		return
	var voice: AudioStreamPlayer3D = spatial[next_spatial]
	next_spatial = (next_spatial + 1) % SPATIAL_VOICES
	voice.global_position = at
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.max_distance = max_distance
	voice.play()


func _load_clips() -> void:
	for name in CLIPS:
		var variants: Array = []
		for file in CLIPS[name]:
			var path := "res://assets/audio/%s.ogg" % file
			if ResourceLoader.exists(path):
				variants.append(load(path))
		if not variants.is_empty():
			streams[name] = variants


# --- Synthesis -----------------------------------------------------------------

static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


static func _buffer(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(seconds * RATE))
	return samples


func _synthesise() -> void:
	streams.shot = _wav(_shot())
	streams.hit = _wav(_hit(720.0))
	streams.headshot = _wav(_hit(1180.0))
	streams.click = _wav(_click())
	streams.reload = _wav(_reload())
	streams.hang = _wav(_chime([880.0, 1760.0], [1.0, 0.35], 0.7, 4.0))
	streams.sense = _wav(_chime([1480.0], [0.6], 0.12, 30.0))
	streams.chime = _wav(_chime([1200.0, 1800.0, 2400.0], [1.0, 0.5, 0.25], 0.8, 5.0))
	streams.converge = _wav(_sweep(330.0, 660.0, 0.5, 3.0, 0.5))
	streams.volley = _wav(_volley())
	streams.bell = _wav(_bell())
	streams.howl = _wav(_howl())
	streams.growl = _wav(_growl())
	streams.huff = _wav(_huff())
	streams.yelp = _wav(_sweep(900.0, 480.0, 0.45, 7.0, 0.45))
	streams.death = _wav(_death())
	streams.bite = _wav(_bite())
	streams.hurt = _wav(_hurt())
	streams.land = _wav(_noise_burst(0.22, 0.2, 25.0, 0.6))
	streams.snuff = _wav(_snuff())
	streams.takedown = _wav(_takedown())
	streams.gate = _wav(_gate())
	streams.sting = _wav(_sting())
	streams.wind = _wav(_wind(), true)


func _shot() -> PackedFloat32Array:
	var s := _buffer(0.4)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.55
		var crack := lp * exp(-t * 26.0) * 1.1
		var thump := sin(TAU * (70.0 + 40.0 * exp(-t * 12.0)) * t) * exp(-t * 9.0) * 0.8
		s[i] = crack + thump
	return s


func _hit(frequency: float) -> PackedFloat32Array:
	var s := _buffer(0.12)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * frequency * (1.0 - t * 1.6) * t) * exp(-t * 38.0) * 0.55 + (randf() * 2.0 - 1.0) * exp(-t * 70.0) * 0.3
	return s


func _click() -> PackedFloat32Array:
	var s := _buffer(0.05)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (randf() * 2.0 - 1.0) * exp(-t * 120.0) * 0.5
	return s


func _reload() -> PackedFloat32Array:
	var s := _buffer(0.9)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for start in [0.0, 0.42, 0.72]:
			if t >= start:
				v += (randf() * 2.0 - 1.0) * exp(-(t - start) * 90.0) * 0.45
				v += sin(TAU * 620.0 * (t - start)) * exp(-(t - start) * 60.0) * 0.2
		s[i] = v
	return s


func _chime(frequencies: Array, amplitudes: Array, seconds: float, decay: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in frequencies.size():
			v += sin(TAU * frequencies[k] * t) * amplitudes[k] * exp(-t * decay * (1.0 + k * 0.4))
		s[i] = v * 0.35
	return s


func _sweep(from_hz: float, to_hz: float, seconds: float, decay: float, gain: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := lerpf(from_hz, to_hz, t / seconds)
		phase += TAU * f / RATE
		var wave := sin(phase) + 0.3 * sin(phase * 2.0)
		s[i] = wave * exp(-t * decay) * minf(1.0, t * 40.0) * gain
	return s


func _volley() -> PackedFloat32Array:
	var s := _buffer(0.9)
	var phases := [0.0, 0.0, 0.0]
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.5
		var v := lp * exp(-t * 8.0) * 0.7 + sin(TAU * 58.0 * t) * exp(-t * 5.0) * 0.5
		for k in 3:
			var start := k * 0.06
			if t >= start:
				var f := lerpf(240.0 + k * 40.0, 90.0, minf(1.0, (t - start) / 0.35))
				phases[k] += TAU * f / RATE
				v += (2.0 * fmod(phases[k] / TAU, 1.0) - 1.0) * exp(-(t - start) * 7.0) * 0.22
		s[i] = v
	return s


func _bell() -> PackedFloat32Array:
	var s := _buffer(5.0)
	var ratios := [1.0, 2.0, 2.4, 3.0, 4.2, 5.4]
	var amps := [1.0, 0.6, 0.45, 0.35, 0.2, 0.1]
	var decays := [0.9, 1.3, 1.8, 2.3, 3.2, 4.4]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in ratios.size():
			v += sin(TAU * 196.0 * ratios[k] * t) * amps[k] * exp(-t * decays[k])
		var strike := (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.5
		s[i] = (v * 0.3 + strike) * minf(1.0, t * 200.0)
	return s


func _howl() -> PackedFloat32Array:
	var s := _buffer(1.9)
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var rise := minf(1.0, t / 0.55)
		var f := 340.0 + 300.0 * sin(rise * PI * 0.5) - maxf(0.0, t - 1.1) * 140.0
		f *= 1.0 + 0.03 * sin(TAU * 5.5 * t)
		phase += TAU * f / RATE
		var wave := sin(phase) + 0.35 * sin(phase * 2.0) + 0.18 * sin(phase * 3.0) + 0.08 * sin(phase * 4.0)
		var env := minf(1.0, t * 6.0) * exp(-maxf(0.0, t - 1.15) * 2.8)
		s[i] = wave * env * 0.32
	return s


func _growl() -> PackedFloat32Array:
	var s := _buffer(0.95)
	var phase := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 72.0 + 14.0 * sin(TAU * 1.7 * t)
		phase += TAU * f / RATE
		var saw := 2.0 * fmod(phase / TAU, 1.0) - 1.0
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.12
		var am := 0.6 + 0.4 * sin(TAU * 23.0 * t)
		var env := minf(1.0, t * 20.0) * exp(-maxf(0.0, t - 0.55) * 6.0)
		s[i] = (saw * 0.55 + lp * 0.45) * am * env * 0.5
	return s


func _huff() -> PackedFloat32Array:
	var s := _buffer(0.35)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.15
		s[i] = (lp * 0.7 + sin(TAU * 180.0 * t) * 0.2) * minf(1.0, t * 60.0) * exp(-t * 11.0) * 0.6
	return s


func _death() -> PackedFloat32Array:
	var s := _buffer(1.0)
	var phase := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := lerpf(720.0, 210.0, minf(1.0, t / 0.85)) * (1.0 + 0.04 * sin(TAU * 7.0 * t))
		phase += TAU * f / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.2
		var env := minf(1.0, t * 30.0) * exp(-t * 3.2)
		s[i] = (sin(phase) * 0.5 + 0.2 * sin(phase * 2.0) + lp * 0.25) * env * 0.5
	return s


func _bite() -> PackedFloat32Array:
	var s := _buffer(0.2)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (randf() * 2.0 - 1.0) * exp(-t * 30.0) * 0.7 + sin(TAU * 140.0 * t) * exp(-t * 20.0) * 0.4
	return s


func _hurt() -> PackedFloat32Array:
	var s := _buffer(0.45)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.25
		s[i] = sin(TAU * 90.0 * t) * exp(-t * 8.0) * 0.6 + lp * exp(-t * 10.0) * 0.35
	return s


func _noise_burst(seconds: float, cutoff: float, decay: float, gain: float) -> PackedFloat32Array:
	var s := _buffer(seconds)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * cutoff
		s[i] = lp * exp(-t * decay) * gain
	return s


func _snuff() -> PackedFloat32Array:
	var s := _buffer(0.5)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.08
		var env := minf(1.0, t / 0.08) * exp(-maxf(0.0, t - 0.08) * 8.0)
		s[i] = lp * env * 0.7
	return s


func _takedown() -> PackedFloat32Array:
	var s := _buffer(0.45)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 60.0 * t) * exp(-t * 10.0) * 0.7 + (randf() * 2.0 - 1.0) * exp(-t * 35.0) * 0.5
	return s


func _gate() -> PackedFloat32Array:
	var s := _buffer(3.2)
	var phase := 0.0
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := lerpf(58.0, 36.0, t / 3.2)
		phase += TAU * f / RATE
		var saw := 2.0 * fmod(phase / TAU, 1.0) - 1.0
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.06
		var ring := sin(TAU * 880.0 * t) * exp(-t * 2.0) * 0.12 * (0.5 + 0.5 * sin(TAU * 0.9 * t))
		var env := minf(1.0, t * 4.0) * (1.0 - smoothstep(2.3, 3.2, t))
		s[i] = (saw * 0.35 + lp * 0.5 + ring) * env * 0.6
	return s


func _sting() -> PackedFloat32Array:
	var s := _buffer(2.8)
	for i in s.size():
		var t := float(i) / RATE
		var pad := sin(TAU * 110.0 * t) + sin(TAU * 165.0 * t) * 0.7 + sin(TAU * 220.0 * t) * 0.4
		var bell := sin(TAU * 392.0 * t) * exp(-t * 1.6) * 0.3
		var env := minf(1.0, t / 0.6) * (1.0 - smoothstep(1.5, 2.8, t))
		s[i] = (pad * 0.18 + bell) * env
	return s


func _wind() -> PackedFloat32Array:
	var length := 6.0
	var fade := 0.6
	var raw := _buffer(length + fade)
	var lp := 0.0
	var lp2 := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.045
		lp2 += (lp - lp2) * 0.02
		var gust := 0.55 + 0.45 * sin(TAU * 0.17 * t + 1.3) * sin(TAU * 0.07 * t)
		raw[i] = lp2 * 6.0 * gust
	# Crossfade the tail into the head so the loop point is seamless.
	var out := _buffer(length)
	var fade_samples := int(fade * RATE)
	for i in out.size():
		if i < fade_samples:
			var w := float(i) / fade_samples
			out[i] = raw[i] * w + raw[out.size() + i] * (1.0 - w)
		else:
			out[i] = raw[i]
	return out
