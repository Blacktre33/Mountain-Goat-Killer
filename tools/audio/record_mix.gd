extends SceneTree
## Records what Godot's own mixer produces (buses, reverbs, ducking, compressor
## and limiter included) for three scripted scenes, so the routing can be
## checked numerically without listening. Usage:
##   Godot --headless --path . --script res://tools/audio/record_mix.gd -- <out_dir>
## Then: python3 tools/audio/analyze.py --dir <out_dir> --files (see README in AUDIO.md)
## Each scene plays in real time (about 14 s) and is saved as <out_dir>/mix_<scene>.wav.

const SCENE_SECONDS := 14.0

var out_dir := "/tmp"
var audio: GoatAudio
var recorder: AudioEffectRecord


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	call_deferred("run")


func run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	audio = GoatAudio.new()
	audio.settings_path = "user://record_mix_unused.cfg"
	root.add_child(audio)
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, recorder)
	await process_frame
	await _scene("stealth", "stealth", _stealth)
	await _scene("firefight", "combat", _firefight)
	await _scene("boss", "boss3", _boss)
	audio.shutdown()
	await create_timer(0.3).timeout
	quit()


func _scene(name: String, state: String, script: Callable) -> void:
	audio.set_music_state(state)
	recorder.set_recording_active(true)
	var started := Time.get_ticks_msec()
	await script.call()
	var remaining := SCENE_SECONDS - (Time.get_ticks_msec() - started) * 0.001
	if remaining > 0.0:
		await create_timer(remaining).timeout
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	var path := "%s/mix_%s.wav" % [out_dir, name]
	var error := wav.save_to_wav(path)
	print("Recorded %s: %.1f s -> %s (%s)" % [name, wav.data.size() / 4.0 / wav.mix_rate, path, error_string(error)])
	recorder.set_recording_active(false)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _stealth() -> void:
	audio.set_wind(0.5)
	for i in 8:
		audio.play("footstep", -10.0)
		await _wait(0.6)
	audio.play_at("huff", Vector3(6, 0.8, -8), -4.0)
	await _wait(2.0)
	audio.say("memory_0")


func _firefight() -> void:
	audio.set_wind(0.8)
	audio.say("bark_contact", Vector3(-8, 1, -14))
	for i in 5:
		audio.play("shot")
		audio.play_at("rifle_crack", Vector3(10, 1, -25), -6.0)
		await _wait(0.5)
		audio.play("hit", -4.0)
		audio.play_at("growl", Vector3(-6, 0.8, -9), -6.0)
		await _wait(0.4)
		audio.play("casing", -4.0)
		await _wait(0.45)
	audio.play_at("howl", Vector3(20, 1, -40), -2.0)
	await _wait(1.0)
	audio.play_at("bite", Vector3(1, 0.8, -2))
	audio.play("hurt", -2.0)
	audio.stun(1.5)


func _boss() -> void:
	audio.play_at("roar", Vector3(0, 2, -12))
	await _wait(3.0)
	audio.say("varkas_phase_3", Vector3(0, 2, -12))
	audio.play_at("charge_rumble", Vector3(0, 0.5, -14))
	await _wait(4.0)
	audio.play("quake")
	await _wait(3.5)
	audio.play_at("armor_break", Vector3(2, 1.5, -10))
	audio.play_at("bell", Vector3(0, 6, -30), 5.0, 0.55, 120.0)
