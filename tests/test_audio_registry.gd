extends SceneTree
## Sound bank, mixer, adaptive score and voice registry checks.
## Every effect clip is decoded and measured (no clipping, no silence, sane
## peak and RMS, sane duration); every registered name, bus, music state and
## voice line must resolve. Run: Godot --headless --path . --script res://tests/test_audio_registry.gd

## Names other systems call (existing and newly agreed) that must never go missing.
const REQUIRED := [
	"footstep", "bell_strike", "thud", "stone", "clank", "wood", "rock_hit", "shot", "hit", "headshot", "click", "reload",
	"hang", "sense", "chime", "converge", "volley", "bell", "howl", "growl", "huff", "yelp", "death", "bite", "hurt", "land",
	"snuff", "takedown", "gate", "sting",
	"heartbeat", "casing", "bolt", "mag_out", "mag_in", "impact_snow", "impact_flesh", "impact_wood", "hitmarker", "kill",
	"pickup", "ammo_pickup", "bell_pickup", "ui_click", "growl_windup", "rifle_crack", "wolf_footstep", "whoosh", "roar",
	"armor_break", "charge_rumble", "quake",
]
const WAV_PEAK_MAX := 0.90
const WAV_PEAK_MIN := 0.008
const TEST_SETTINGS := "user://test_audio_registry.cfg"

var failures: Array[String] = []


func _init() -> void:
	call_deferred("run_test")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func run_test() -> void:
	_test_bank_files()
	var audio := GoatAudio.new()
	audio.settings_path = TEST_SETTINGS
	root.add_child(audio)
	await process_frame
	_test_registry(audio)
	_test_buses(audio)
	_test_unknown_names(audio)
	_test_volume_api(audio)
	await _test_ducking(audio)
	await _test_music(audio)
	await _test_voice(audio)
	await _test_settings_persist()
	await _test_teardown(audio)
	if failures.is_empty():
		print("Audio registry test passed: %d effects, %d voice lines" % [AudioBank.SOUNDS.size(), AudioBank.VOICE.size()])
		quit()
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


## Decode every effect clip and measure it.
func _test_bank_files() -> void:
	var measured := 0
	for name in AudioBank.SOUNDS:
		var entry: Dictionary = AudioBank.SOUNDS[name]
		for file in entry.files:
			var path: String = GoatAudio.CLIP_DIR + file
			check(ResourceLoader.exists(path), "%s: missing %s" % [name, path])
			var stream := load(path) as AudioStream
			if stream == null:
				failures.append("%s: %s did not load" % [name, file])
				continue
			var seconds := stream.get_length()
			check(seconds > 0.03 and seconds < 60.0, "%s/%s: implausible length %.2f s" % [name, file, seconds])
			if stream is AudioStreamWAV:
				_measure_wav(name, file, stream)
				measured += 1
			else:
				check(stream is AudioStreamOggVorbis, "%s/%s: unexpected stream class" % [name, file])
	check(measured > 100, "Only %d WAV clips measured" % measured)
	# Long material must exist for each biome, phase and ending; stems of a group must share one loop length.
	for biome in ["widowpine", "carrion", "iron_crown"]:
		var lengths: Array[float] = []
		for kind in GoatMusic.KINDS:
			lengths.append((load(GoatAudio.CLIP_DIR + AudioBank.SOUNDS["music_%s_%s" % [biome, kind]].files[0]) as AudioStream).get_length())
		for length in lengths:
			check(absf(length - lengths[0]) < 0.05, "%s stems differ in loop length: %s" % [biome, lengths])
		check(AudioBank.SOUNDS.has("amb_" + ("carrion" if biome == "carrion" else biome)), "No ambience bed for " + biome)
	for phase in [1, 2, 3]:
		var base := (load(GoatAudio.CLIP_DIR + AudioBank.SOUNDS["music_boss%d_base" % phase].files[0]) as AudioStream).get_length()
		var perc := (load(GoatAudio.CLIP_DIR + AudioBank.SOUNDS["music_boss%d_perc" % phase].files[0]) as AudioStream).get_length()
		check(absf(base - perc) < 0.05, "Boss %d stems differ in length" % phase)
	check(AudioBank.SOUNDS.has("music_victory") and AudioBank.SOUNDS.has("music_death"), "Victory or death score missing")


func _measure_wav(name: String, file: String, stream: AudioStreamWAV) -> void:
	check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "%s: not 16-bit PCM" % file)
	check(stream.mix_rate == 44100, "%s: sample rate %d" % [file, stream.mix_rate])
	var data := stream.data
	var count := data.size() / 2
	check(count > 1000, "%s: only %d samples" % [file, count])
	var peak := 0
	var clipped := 0
	var sum := 0.0
	var energy := 0.0
	for i in count:
		var s := data.decode_s16(i * 2)
		var a := absi(s)
		peak = maxi(peak, a)
		if a >= 32767:
			clipped += 1
		sum += s
		energy += float(s) * float(s)
	var peak_lin := peak / 32768.0
	var rms := sqrt(energy / count) / 32768.0
	var dc := absf(sum / count) / 32768.0
	check(clipped == 0, "%s: %d clipped samples" % [file, clipped])
	check(peak_lin <= WAV_PEAK_MAX, "%s: peak %.3f is too hot" % [file, peak_lin])
	check(peak_lin >= WAV_PEAK_MIN, "%s: peak %.4f is effectively silent" % [file, peak_lin])
	check(rms > 0.0004, "%s: RMS %.5f is silent" % [file, rms])
	check(dc < 0.01, "%s: DC offset %.4f" % [file, dc])
	check(absi(data.decode_s16(0)) < 3000 and absi(data.decode_s16((count - 1) * 2)) < 800, "%s: clicks at its edges" % file)
	check(peak_lin / maxf(rms, 1e-6) < 400.0, "%s: crest factor absurd (spike in silence?)" % file)


func _test_registry(audio: GoatAudio) -> void:
	for name in REQUIRED:
		check(audio.has_sound(name), "Missing required sound '%s'" % name)
		check(not audio.bus_for(name).is_empty(), "Sound '%s' has no bus" % name)
	check(audio.streams.size() >= 70, "Sound bank suspiciously small: %d" % audio.streams.size())
	check(audio.sound_names().size() == audio.streams.size(), "sound_names() disagrees with the bank")
	for name in audio.sound_names():
		for stream in audio.streams[name]:
			check(stream is AudioStream, "%s holds a non-stream" % name)
		var bus := audio.bus_for(name)
		check(AudioServer.get_bus_index(bus) != -1, "%s routes to missing bus %s" % [name, bus])
	audio.play("shot")
	audio.play_at("howl", Vector3(3, 1, 4))
	audio.play("footstep", -10.0)
	check(audio.unknown_reported.is_empty(), "Valid names were reported unknown: %s" % audio.unknown_reported)


func _test_buses(audio: GoatAudio) -> void:
	for spec in GoatAudio.BUSES:
		var index := AudioServer.get_bus_index(spec[0])
		check(index != -1, "Bus %s missing" % spec[0])
		if index != -1:
			check(str(AudioServer.get_bus_send(index)) == spec[1], "Bus %s should send to %s, not %s" % [spec[0], spec[1], AudioServer.get_bus_send(index)])
	var master_effects: Array = []
	for i in AudioServer.get_bus_effect_count(0):
		master_effects.append(AudioServer.get_bus_effect(0, i))
	check(master_effects.any(func(e): return e is AudioEffectCompressor), "Master has no compressor")
	check(master_effects.any(func(e): return e is AudioEffectHardLimiter), "Master has no limiter")
	var canyon := AudioServer.get_bus_index("Canyon")
	var reverb: AudioEffectReverb = null
	for i in AudioServer.get_bus_effect_count(canyon):
		if AudioServer.get_bus_effect(canyon, i) is AudioEffectReverb:
			reverb = AudioServer.get_bus_effect(canyon, i)
	check(reverb != null and reverb.wet > 0.2 and reverb.room_size > 0.8, "Canyon bus lacks a large reverb")
	check(audio.bus_for("howl") == "Canyon" and audio.bus_for("shot") == "SFX" and audio.bus_for("hitmarker") == "UI", "Bus routing changed unexpectedly")
	# The layout shipped in default_bus_layout.tres must already carry the tree.
	var layout := load("res://default_bus_layout.tres") as AudioBusLayout
	check(layout != null, "default_bus_layout.tres does not load")


func _test_unknown_names(audio: GoatAudio) -> void:
	audio.play("definitely_not_a_sound")
	audio.play_at("also_not_a_sound", Vector3.ZERO)
	if OS.is_debug_build():
		check(audio.unknown_reported.has("definitely_not_a_sound") and audio.unknown_reported.has("also_not_a_sound"), "Unknown names were not reported")
	check(not audio.has_sound("definitely_not_a_sound"), "Unknown name appeared in the bank")


func _test_volume_api(audio: GoatAudio) -> void:
	audio.set_bus_volume("music", 0.25)
	var music_bus := AudioServer.get_bus_index("Music")
	var expected := linear_to_db(0.25) + GoatAudio.BUSES[0][2]
	check(absf(AudioServer.get_bus_volume_db(music_bus) - (expected + audio._duck_now.Music - 7.0 * audio._paused_mix)) < 0.2, "Music bus volume did not follow the slider")
	check(is_equal_approx(audio.get_bus_volume("Music"), 0.25), "get_bus_volume disagrees with set_bus_volume")
	audio.set_bus_volume("master", 0.0)
	check(AudioServer.get_bus_volume_db(0) <= -60.0, "Master at zero must mute")
	audio.set_bus_volume("master", 1.0)
	audio.set_bus_volume("nonsense", 0.5)
	check(not audio.volumes.has("nonsense"), "Unknown channel accepted")
	audio.set_subtitles_enabled(false)
	check(not audio.subtitles.enabled, "Subtitle switch did not propagate")
	audio.set_subtitles_enabled(true)


func _test_ducking(audio: GoatAudio) -> void:
	audio.play("shot")
	for i in 6:
		await process_frame
	check(audio._duck_now.Music < -2.0 and audio._duck_now.Ambience < -1.0, "A gunshot did not duck music and ambience: %s" % audio._duck_now)
	audio.stun(1.0)
	await process_frame
	check(audio._muffle > 0.0, "Stun did not muffle the mix")
	check(audio.has_sound("tinnitus"), "Stun needs the tinnitus clip")


func _test_music(audio: GoatAudio) -> void:
	var music := audio.music
	check(music.state == "title" and music.groups.has("biome:widowpine"), "Music should start on the title theme")
	for state in GoatMusic.STATES:
		music.set_state(state)
		check(music.state == state, "State %s not accepted" % state)
	music.set_state("not_a_state")
	check(music.state == "death", "Invalid state changed the score")
	music.set_state("stealth")
	check(music.stem_target_db("drone") == 0.0 and music.stem_target_db("combat") <= -70.0, "Stealth mix wrong")
	music.set_state("combat")
	check(music.stem_target_db("combat") == 0.0 and music.stem_target_db("motif") <= -70.0, "Combat mix wrong")
	music.set_state("suspicious")
	check(music.stem_target_db("tension") > -5.0 and music.stem_target_db("combat") <= -70.0, "Suspicious mix wrong")
	for name in ["whitewood", "carrion_cut", "iron_crown"]:
		music.set_biome(name)
	check(music.biome == "iron_crown" and music.groups.has("biome:carrion") and music.groups.has("biome:iron_crown"), "set_biome did not build stem groups")
	check(music.stem_target_db("drone", "widowpine") <= -70.0, "Old biome must fade out")
	music.set_state("boss2")
	check(music.groups.has("boss:2"), "Boss phase 2 stems were not created")
	for i in 40:
		music._process(0.25)
	check(music.groups["boss:2"].base.volume_db > -3.0 and music.groups["biome:iron_crown"].drone.volume_db < -70.0, "Boss crossfade did not complete")
	music.set_state("victory")
	check(music.oneshots.size() == 1, "Victory theme did not start")
	music.set_state("stealth")
	for i in 40:
		music._process(0.25)
	check(music.oneshots.is_empty(), "Victory theme should fade away when the state changes")
	music.set_biome("whitewood")
	music.set_state("title")


func _test_voice(audio: GoatAudio) -> void:
	var voice := audio.voice
	check(voice.lines.size() == AudioBank.VOICE.size(), "Voice registry incomplete")
	var manifest := JSON.parse_string(FileAccess.get_file_as_string("res://tools/audio/voice_manifest.json")) as Dictionary
	var spoken := {}
	for entry in manifest.lines:
		spoken[entry.id] = entry.text
	for id in AudioBank.VOICE:
		check(ResourceLoader.exists(GoatVoice.VOICE_DIR + id + ".ogg"), "Voice file missing for %s" % id)
		var text := Story.voice_text(id)
		check(not text.is_empty(), "Voice line %s has no subtitle text" % id)
		check(spoken.get(id, "") == text, "Recorded speech for %s no longer matches the story text" % id)
		var length := (load(GoatVoice.VOICE_DIR + id + ".ogg") as AudioStream).get_length()
		check(length > 0.8 and length < 20.0, "Voice line %s is %.1f s" % [id, length])
	for i in Story.BELL_NAMES.size():
		check(voice.has_line("memory_%d" % i), "No voice for bell memory %d" % i)
	for i in Story.INTRO.size():
		check(voice.has_line("intro_%d" % i), "No voice for intro line %d" % i)
	for group in Story.VOICE_GROUPS:
		for id in Story.VOICE_GROUPS[group]:
			check(voice.lines.has(id), "Group %s names unknown line %s" % [group, id])
	var heard: Array = []
	voice.line_started.connect(func(id: String, speaker: String, text: String, seconds: float, _at: Vector3) -> void:
		heard.append([id, speaker, text, seconds]))
	check(voice.say("memory_3"), "Narration was refused")
	await process_frame
	check(heard.size() == 1 and heard[0][2] == Story.bell_memory(3) and heard[0][3] > 2.0, "Narration did not emit its subtitle: %s" % [heard])
	check(audio.subtitles.label.text == Story.bell_memory(3) and audio.subtitles.panel.visible, "Subtitle label did not show the line")
	check(voice.is_speaking(), "is_speaking should be true during narration")
	check(not voice.say("memory_3"), "A repeated request must be ignored")
	check(voice.say("varkas_alert"), "Varkas group line refused")
	check(heard[-1][1] == "varkas" and Story.VARKAS_LINES.values().has(heard[-1][2]), "Varkas line text wrong")
	check(voice.say("bark_contact", Vector3(4, 1, 4)), "Bark refused")
	check(not voice.say("bark_contact", Vector3(4, 1, 4)), "Bark cooldown not applied")
	check(not voice.say("no_such_line"), "Unknown voice line accepted")
	voice.stop_narration()
	check(voice.queue.is_empty() and voice.current_id.is_empty(), "stop_narration left the narrator busy")
	# Priority queue: the intro outranks a chapter line and both are spoken in turn.
	voice.say("chapter_gate")
	voice.say("intro_0")
	check(voice.queue.size() >= 1 or not voice.current_id.is_empty(), "Queued narration vanished")
	voice.stop_narration()


func _test_settings_persist() -> void:
	var again := GoatAudio.new()
	again.settings_path = TEST_SETTINGS
	root.add_child(again)
	await process_frame
	check(is_equal_approx(again.get_bus_volume("music"), 0.25), "Volume was not restored from audio.cfg")
	check(again.subtitles_enabled, "Subtitle setting not restored")
	again.shutdown()
	again.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))


## Same leak hygiene as the other suites: nothing may retain streams or playbacks after shutdown.
func _test_teardown(audio: GoatAudio) -> void:
	audio.play("shot")
	audio.play_at("howl", Vector3(2, 1, 2))
	await create_timer(maxf(0.02, AudioServer.get_time_to_next_mix() + 0.02)).timeout
	var refs: Array = []
	for name in audio.streams:
		for stream in audio.streams[name]:
			refs.append(weakref(stream))
	for player in audio.voices + audio.spatial + [audio.wind_player]:
		if player.has_stream_playback():
			refs.append(weakref(player.get_stream_playback()))
	audio.shutdown()
	await create_timer(0.2).timeout
	audio.queue_free()
	await process_frame
	await process_frame
	var retained := 0
	for attempt in 50:
		retained = 0
		for reference in refs:
			if reference.get_ref() != null:
				retained += 1
		if retained == 0:
			break
		await create_timer(0.02).timeout
	check(retained == 0, "Audio backend retained %d streams or playbacks after teardown" % retained)
