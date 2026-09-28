extends Node3D
## Mission flow for THE LAST BELL: builds the ravine, spawns the warpack on
## their patrols, runs the story captions, the stealth HUD, checkpoints, the
## bell, the gate, and Varkas. Also owns the title and pause menus, the saved
## campaign, and the local playtest log.

const PLAYER_SCENE := preload("res://scripts/player.gd")
const ENEMY_SCENE := preload("res://scripts/enemy.gd")

const POUCH_AMMO := 14
const PICKUP_RADIUS := 2.2
const INTERACT_RADIUS := 2.4
const BELL_RADIUS := 6.0
const CHECKPOINTS := {
	"trailhead": Vector3(0.0, 0.0, 34.0),
	"homestead": Vector3(0.0, 0.0, 14.0),
	"shrine": Vector3(0.0, 0.0, -17.0),
	"shrine_rung": Vector3(0.0, 0.0, -17.0),
	"ascent": Vector3(0.0, 0.0, -41.0),
	"gate": Vector3(0.0, 0.0, -78.0),
}

var player: GoatPlayer
var audio: GoatAudio
var world: WorldBuilder.Built
var enemies: Array[WolverineEnemy] = []
var boss: WolverineEnemy
var kills := 0
var bells := 0
var total_enemies := 0
var started := false
var bell_rung := false
var gate_open := false
var boss_awake := false
var victory := false
var pouches: Array = []
var notice_until := 0.0
var zone := ""
var checkpoint := Vector3(0.0, 0.0, 34.0)
var seen_zones := {}
var current_biome := ""
var hud_tick := 0

var hud: CanvasLayer
var hud_ground_shade: TextureRect
var start_overlay: ColorRect
var pause_overlay: ColorRect
var objective_label: Label
var ammo_label: Label
var health_label: Label
var bells_label: Label
var remembrance_label: Label
var stealth_label: Label
var exposure_bar: ColorRect
var exposure_fill: ColorRect
var wind_label: Label
var center_message: Label
var prompt_label: Label
var crosshair: Label
var chapter_title: Label
var minimap: Minimap
var chapter_line: Label
var chapter_tween: Tween
var victory_veil: ColorRect
var ending_actions: HBoxContainer
var return_button: Button
var returning_to_title := false
var biome_label: Label
var boss_label: Label
var boss_bar: ColorRect
var boss_fill: ColorRect
var last_objective := ""
var snow: GPUParticles3D
var interact_target: Dictionary = {}

## Persistence, options, and playtest telemetry.
var playtest := PlaytestLog.new()
var save_data: Dictionary = {}
var continued := false
var run_time := 0.0
var deaths := 0
var dead_spawn_ids: Array[int] = []
var logged_difficulty := ""
var options_menu: OptionsMenu
var pause_input: PauseInput
var pause_panel: VBoxContainer
var resume_button: Button
var pause_options_button: Button
var deploy_button: Button
var continue_button: Button
var difficulty_button: Button
var field_note: Label
var controls_label: Label
var options_return_focus: Control


## Always-processing listener: tracks the active input device for prompts and
## resumes from the pause menu with Esc or Start, even while the tree is paused.
class PauseInput extends Node:
	var mission: Node

	func _input(event: InputEvent) -> void:
		mission._on_any_input(event)


func _ready() -> void:
	GameSettings.ensure_loaded()
	InputBindings.install()
	save_data = SaveGame.load_slot()
	audio = GoatAudio.new()
	audio.name = "Audio"
	add_child(audio)
	world = WorldBuilder.build(self)
	snow = world.root.get_node("Snowfall")
	_build_interface()
	_spawn_player()
	_spawn_enemies()
	_apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_input = PauseInput.new()
	pause_input.name = "PauseInput"
	pause_input.mission = self
	pause_input.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_input)
	(continue_button if continue_button.visible else deploy_button).call_deferred("grab_focus")
	if "--capture-iron-crown-live" in OS.get_cmdline_user_args():
		capture_iron_crown_after_render()
	elif "--capture-widowpine-live" in OS.get_cmdline_user_args():
		capture_widowpine_after_render()
	elif "--capture-carrion-live" in OS.get_cmdline_user_args():
		capture_carrion_after_render()
	elif "--capture-iron-crown-approach" in OS.get_cmdline_user_args():
		capture_iron_crown_approach()
	elif "--capture-varkas-phase1" in OS.get_cmdline_user_args():
		capture_varkas_phase(1)
	elif "--capture-varkas-phase3" in OS.get_cmdline_user_args():
		capture_varkas_phase(3)
	elif "--capture-varkas-execution" in OS.get_cmdline_user_args():
		capture_varkas_execution()


func capture_iron_crown_after_render() -> void:
	# Repeatable player-camera proof for environment review. This path runs only
	# when explicitly requested from the command line and never affects play.
	_start_game()
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, -43.0) + 1.2, -43.0)
	player.rotation.y = 0.0
	player.pitch = 0.19
	player.velocity = Vector3.ZERO
	WorldBuilder.set_biome(world, "iron_crown")
	current_biome = "iron_crown"
	biome_label.text = "THE IRON CROWN  //  ASH  //  SIEGE IRON  //  VARKAS"
	objective_label.text = "OBJECTIVE  //  THE IRON GATE OPENS ONLY WHEN EIGHT NAMES SPEAK"
	started = false
	for _frame in range(20):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://art_direction/iron_crown/iron-crown-live-game-v1.png")
	if error != OK:
		push_error("Could not save live Iron Crown frame: %s" % error_string(error))
		await _finish_capture(1)
		return
	print("Saved live in-game Iron Crown frame")
	await _finish_capture()


func capture_widowpine_after_render() -> void:
	_start_game()
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, 18.0) + 1.2, 18.0)
	player.rotation.y = 0.0
	player.pitch = 0.07
	player.velocity = Vector3.ZERO
	WorldBuilder.set_biome(world, "whitewood")
	current_biome = "whitewood"
	biome_label.text = "WIDOWPINE  //  FROST PINE  //  THE BROKEN FOLD"
	objective_label.text = "OBJECTIVE  //  FOLLOW THE BLOOD-TRACKS TO THE FAMILY FOLD"
	started = false
	for _frame in range(30):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://art_direction/widowpine/widowpine-live-game-v1.png")
	if error != OK:
		push_error("Could not save live Widowpine frame: %s" % error_string(error))
		await _finish_capture(1)
		return
	print("Saved live in-game Widowpine frame")
	await _finish_capture()


func capture_carrion_after_render() -> void:
	_start_game()
	# The shrine is carved into the west wall around the historic bell origin;
	# center the review camera on its actual processional lane.
	player.global_position = Vector3(-5.5, WorldBuilder.height_at(-5.5, -6.0) + 1.2, -6.0)
	player.rotation.y = 0.0
	player.pitch = 0.16
	player.velocity = Vector3.ZERO
	WorldBuilder.set_biome(world, "carrion_cut")
	current_biome = "carrion_cut"
	biome_label.text = "THE CARRION CUT  //  RED STONE  //  THE LAST SHRINE"
	objective_label.text = "OBJECTIVE  //  CARRY FOUR NAMES TO THE MOTHER BELL"
	started = false
	for _frame in range(30):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://art_direction/carrion_cut/carrion-cut-live-game-v1.png")
	if error != OK:
		push_error("Could not save live Carrion Cut frame: %s" % error_string(error))
		await _finish_capture(1)
		return
	print("Saved live in-game Carrion Cut frame")
	await _finish_capture()


func capture_iron_crown_approach() -> void:
	_start_game()
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, -64.0) + 1.2, -64.0)
	player.rotation.y = 0.0
	player.pitch = 0.19
	player.velocity = Vector3.ZERO
	WorldBuilder.set_biome(world, "iron_crown")
	current_biome = "iron_crown"
	biome_label.text = "THE IRON CROWN  //  THIRTY METRES TO THE IRON THROAT"
	objective_label.text = "OBJECTIVE  //  CARRY THE EIGHT NAMES TO THE GATE"
	started = false
	for _frame in range(25):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://art_direction/iron_crown/iron-crown-approach-v1.png")
	if error != OK:
		push_error("Could not save Iron Crown approach frame: %s" % error_string(error))
		await _finish_capture(1)
		return
	print("Saved live Iron Crown approach frame")
	await _finish_capture()


func capture_varkas_phase(phase_index: int) -> void:
	_start_game()
	# Stage the proof from inside the court, at the same intimate distance where
	# the Red Horn charge becomes dangerous. The slight angle keeps Orin's bell,
	# the broken armor profile, and Varkas' face readable at once.
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, -98.2) + 1.2, -98.2)
	var to_boss := boss.global_position - player.global_position
	player.rotation.y = atan2(-to_boss.x, -to_boss.z)
	player.pitch = 0.12
	player.velocity = Vector3.ZERO
	WorldBuilder.set_biome(world, "iron_crown")
	WorldBuilder.set_varkas_phase(world, phase_index)
	if phase_index >= 3:
		for fire in world.campfires:
			fire.light_color = Color("ff351f")
			fire.light_energy = 2.8
	current_biome = "iron_crown"
	bells = 8
	bells_label.text = "BELLS RECOVERED  //  8 / %d" % Story.BELL_NAMES.size()
	boss_awake = true
	boss.set_physics_process(false)
	boss.look_at(Vector3(player.global_position.x, boss.global_position.y, player.global_position.z), Vector3.UP)
	boss.preview_boss_phase(phase_index)
	var phase_title := boss.boss_phase_title()
	biome_label.text = "THE IRON CROWN  //  VARKAS  //  %s" % phase_title
	objective_label.text = "OBJECTIVE  //  %s" % ("BREAK VARKAS  //  TAKE BACK ORIN'S BELL" if phase_index >= 3 else "SHATTER VARKAS' IRON HIDE")
	boss_label.text = "VARKAS  //  %s" % phase_title
	boss_label.visible = true
	boss_bar.visible = true
	boss_fill.visible = true
	started = false
	for _frame in range(75):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var capture_path := "res://art_direction/iron_crown/iron-crown-varkas-phase%d-v1.png" % phase_index
	var error := image.save_png(capture_path)
	if error != OK:
		push_error("Could not save Varkas phase-%d frame: %s" % [phase_index, error_string(error)])
		await _finish_capture(1)
		return
	print("Saved live Varkas phase-%d frame" % phase_index)
	await _finish_capture()


func capture_varkas_execution() -> void:
	# This proof drives the real damage gates and final interaction handler. It
	# does not set `victory` directly, so a captured ending also verifies that the
	# boss death signal returns Orin's ninth bell and resolves the mission.
	_start_game()
	WorldBuilder.set_biome(world, "iron_crown")
	current_biome = "iron_crown"
	zone = "gate"
	seen_zones["gate"] = true
	biome_label.text = "THE IRON CROWN  //  VARKAS  //  THE LAST BELL"
	bells = Story.IRON_GATE_REQUIRED
	bells_label.text = "BELLS RECOVERED  //  %d / %d" % [bells, Story.BELL_NAMES.size()]
	boss_awake = true
	player.health = 999
	player.active = true
	boss.set_physics_process(false)
	boss.state = WolverineEnemy.State.DORMANT
	boss.take_damage(boss.max_health * 4)
	boss.boss_transition_lock = 0.0
	boss.take_damage(boss.max_health * 4)
	boss.boss_transition_lock = 0.0
	boss.take_damage(boss.max_health * 4)
	if not boss.execution_ready:
		push_error("Could not stage Varkas' execution beat")
		await _finish_capture(1)
		return
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy != boss:
			enemy.set_physics_process(false)
	player.global_position = boss.global_position + Vector3(0.0, 0.0, 2.65)
	player.velocity = Vector3.ZERO
	var to_boss := boss.global_position - player.global_position
	player.rotation.y = atan2(-to_boss.x, -to_boss.z)
	player.pitch = 0.08
	_update_prompt()
	if interact_target.get("kind", "") != "boss_finish":
		push_error("Varkas' final horn-strike prompt did not become available")
		await _finish_capture(1)
		return
	_on_interact()
	if not victory or bells != Story.BELL_NAMES.size():
		push_error("Varkas execution did not resolve the nine-bell ending")
		await _finish_capture(1)
		return
	for _frame in range(110):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://art_direction/iron_crown/iron-crown-varkas-execution-v1.png")
	if error != OK:
		push_error("Could not save Varkas execution frame: %s" % error_string(error))
		await _finish_capture(1)
		return
	print("Saved live Varkas execution and nine-bell victory frame")
	await _finish_capture()


func _finish_capture(exit_code := 0) -> void:
	# Generated audio streams hold native buffers for a short time after their
	# players stop. Draining them makes proof captures exit as cleanly as the
	# runtime smoke test instead of reporting misleading ObjectDB leaks.
	if is_instance_valid(audio):
		audio.shutdown()
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(exit_code)


func _process(delta: float) -> void:
	if not started or not is_instance_valid(player):
		return
	var now := Time.get_ticks_msec() * 0.001
	run_time += delta
	_update_zone()
	var objective := Story.objective_for(zone, boss_awake, victory, bells, bell_rung)
	if objective != last_objective:
		last_objective = objective
		objective_label.text = "OBJECTIVE  //  " + objective
	if not victory and notice_until > 0.0 and now > notice_until:
		notice_until = 0.0
		center_message.text = ""

	_update_lights(delta, now)
	_update_pouches(delta, now)
	_update_gate()
	_update_boss_hud()
	snow.position = Vector3(player.global_position.x, player.global_position.y + 12.0, player.global_position.z)
	audio.set_wind(0.35 + (0.45 if player.sprinting else 0.0) + (0.15 if player.global_position.z < -40.0 else 0.0))
	hud_tick += 1
	if hud_tick % 3 == 0:
		_update_stealth_hud(now)
		_update_prompt()
	if hud_tick % 2 == 0:
		minimap.queue_redraw()


# --- Spawning ------------------------------------------------------------------

func _spawn_player() -> void:
	player = PLAYER_SCENE.new()
	player.name = "Player"
	var start: Vector3 = CHECKPOINTS.trailhead
	player.position = Vector3(start.x, WorldBuilder.height_at(start.x, start.z) + 1.2, start.z)
	add_child(player)
	player.ammo_changed.connect(_on_ammo_changed)
	player.health_changed.connect(_on_health_changed)
	player.controls_changed.connect(_on_controls_changed)
	player.remembrance_changed.connect(_on_remembrance_changed)
	player.notice.connect(_notice)
	player.interact_pressed.connect(_on_interact)
	player.noise_made.connect(_on_noise)
	player.died.connect(_on_player_died)
	minimap.player = player
	_on_ammo_changed(player.ammo, player.reserve)
	_on_health_changed(player.health)
	_on_remembrance_changed(0, Remembrance.CAPACITY, false)


func _route(points: Array) -> Array:
	var route: Array = []
	for p in points:
		route.append(Vector3(p.x, WorldBuilder.height_at(p.x, p.y), p.y))
	return route


func _spawn_enemies() -> void:
	var specs := [
		# Homestead: the camp. Bells 0..3.
		["stalker", [Vector2(-6.0, 6.0), Vector2(-3.0, -4.0), Vector2(-8.0, -9.0)], 0],
		["rifleman", [Vector2(6.0, 3.0), Vector2(7.5, -9.0), Vector2(2.0, -11.0)], 1],
		["brute", [Vector2(1.5, -2.0), Vector2(-2.0, 7.5)], 2],
		["stalker", [Vector2(9.0, 9.5), Vector2(-9.0, 9.5)], 3],
		# Shrine sentries. Bells 4..5.
		["rifleman", [Vector2(-1.0, -24.0), Vector2(4.0, -32.0)], 4],
		["stalker", [Vector2(2.5, -31.0), Vector2(3.5, -35.0), Vector2(2.0, -23.0)], 5],
		# The ascent. Bells 6..7.
		["rifleman", [Vector2(5.0, -50.0), Vector2(-4.0, -56.0)], 6],
		["brute", [Vector2(0.0, -58.0), Vector2(-5.0, -70.0), Vector2(5.0, -70.0)], 7],
		["stalker", [Vector2(6.0, -79.0), Vector2(-6.0, -80.0), Vector2(0.0, -86.0)], -1],
		# Varkas waits in the courtyard with Orin's stolen neck-bell. Bell 8.
		["boss", [Vector2(0.0, WorldBuilder.COURTYARD_Z - 4.5)], 8],
	]
	for spec in specs:
		var enemy: WolverineEnemy = ENEMY_SCENE.new()
		enemy.name = "Wolverine_%02d" % enemies.size()
		# A stable id per authored spawn, so a save can say who is already dead.
		enemy.set_meta("spawn_id", enemies.size())
		add_child(enemy)
		var route := _route(spec[1])
		enemy.configure(player, spec[0], route[0] + Vector3(0.0, 0.3, 0.0), route, spec[2])
		enemy.killed.connect(_on_enemy_killed)
		enemy.spotted.connect(_on_enemy_spotted)
		enemies.append(enemy)
		if enemy.boss:
			boss = enemy
			enemy.boss_phase_changed.connect(_on_boss_phase_changed)
			enemy.boss_attack.connect(_on_boss_attack)
	total_enemies = enemies.size()
	bells_label.text = "BELLS RECOVERED  //  0 / %d" % Story.BELL_NAMES.size()


# --- Per-frame systems ----------------------------------------------------------

func _update_zone() -> void:
	var next_zone := Story.zone_for_z(player.global_position.z, bell_rung)
	if next_zone == zone:
		return
	zone = next_zone
	checkpoint = CHECKPOINTS.get(zone, checkpoint)
	playtest.record("zone_enter", run_time, {"zone": zone, "bells": bells})
	var next_biome := Story.biome_for_zone(zone)
	if next_biome != current_biome:
		current_biome = next_biome
		WorldBuilder.set_biome(world, current_biome)
		var biome: Dictionary = Story.BIOMES.get(current_biome, {})
		biome_label.text = "%s  //  %s" % [biome.get("title", ""), biome.get("line", "")]
	var key := "shrine" if zone == "shrine_rung" else zone
	if not seen_zones.has(key):
		seen_zones[key] = true
		var chapter := Story.chapter_for_zone(zone)
		if not chapter.is_empty():
			_show_chapter(chapter.title, chapter.line)
	# After the chapter is marked seen, so Continue does not replay its card.
	_save_progress()


func _update_lights(delta: float, now: float) -> void:
	var exposure := 0.0
	var goat := player.global_position
	for lantern in world.lanterns:
		if not lantern.lit:
			continue
		var light: OmniLight3D = lantern.light
		if lantern.get("fire", false):
			light.light_energy = 4.2 + sin(now * 9.0 + light.position.x) * 0.8 + randf() * 0.5
		var distance: float = lantern.position.distance_to(goat)
		var reach: float = light.omni_range
		if distance < reach:
			exposure += pow(1.0 - distance / reach, 1.4)
	player.light_exposure = clampf(exposure, 0.0, 1.0)


func _update_gate() -> void:
	if not gate_open and Story.can_open_iron_gate(bells, bell_rung) and player.global_position.z < WorldBuilder.GATE_Z + 9.0:
		gate_open = true
		var tween := create_tween()
		tween.tween_property(world.gate, "position:y", world.gate.position.y + 7.5, 3.0).set_trans(Tween.TRANS_SINE)
		world.gate_block.queue_free()
		playtest.record("gate_open", run_time, {"bells": bells})
		audio.play_at("gate", world.gate.global_position + Vector3(0.0, 3.0, 0.0), 4.0)
		audio.play_at("clank", world.gate.global_position + Vector3(0.0, 3.0, 0.0), 0.0, 0.7)
		_notice("EIGHT NAMES SPEAK. THE IRON GATE ANSWERS.", 2.6)
	if gate_open and not boss_awake and player.global_position.z < WorldBuilder.GATE_Z - 1.0:
		boss_awake = true
		playtest.record("boss_engaged", run_time, {"health": player.health, "reserve": player.reserve})
		if is_instance_valid(boss):
			boss.wake()


func _on_noise(source: Vector3, radius: float) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.hear_noise(source, radius)


func _update_stealth_hud(now: float) -> void:
	var highest := 0.0
	var nearest: WolverineEnemy = null
	var nearest_distance := INF
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.state == WolverineEnemy.State.DORMANT:
			continue
		highest = maxf(highest, enemy.detection)
		var distance := enemy.global_position.distance_to(player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	exposure_fill.size.x = 180.0 * highest
	var state_text := "HIDDEN"
	var color := Color("8fd0c8")
	if highest >= Stealth.ALERT:
		state_text = "HUNTED"
		color = Color("ff5a3c")
	elif highest >= Stealth.SUSPICIOUS:
		state_text = "SUSPICION"
		color = Color("ffb03a")
	exposure_fill.color = color
	var posture := "CROUCHED" if player.crouched else ("SPRINTING" if player.sprinting else "STANDING")
	var lit := "IN LIGHT" if player.light_exposure > 0.25 else "IN DARK"
	stealth_label.text = "%s  //  %s  //  %s" % [state_text, posture, lit]
	stealth_label.modulate = color
	var wind := Stealth.wind_at(now)
	var relative := wind.rotated(Vector3.UP, -player.rotation.y)
	var arrow := "AHEAD" if relative.z < -0.5 else ("BEHIND" if relative.z > 0.5 else ("RIGHT" if relative.x > 0.0 else "LEFT"))
	var scent := ""
	if nearest:
		scent = "  //  SCENT CARRIED AWAY" if Stealth.is_upwind(player.global_position, nearest.global_position, wind) else "  //  SCENT CARRIED TO THEM"
	wind_label.text = "WIND BLOWS %s%s" % [arrow, scent]


func _update_prompt() -> void:
	interact_target = {}
	var prompt := ""
	var goat := player.global_position
	if boss_awake and is_instance_valid(boss) and boss.execution_ready and goat.distance_to(boss.global_position) < 3.8:
		interact_target = {"kind": "boss_finish"}
		prompt = "%s   HORN STRIKE  //  END VARKAS" % InputBindings.prompt("interact")
	elif not bell_rung and goat.distance_to(_bell_position()) < BELL_RADIUS:
		interact_target = {"kind": "bell"}
		if Story.can_ring_mother_bell(bells):
			prompt = "%s   RING THE MOTHER BELL  (WAKES THE WHOLE RAVINE)" % InputBindings.prompt("interact")
		else:
			prompt = "%s   THE BELL NEEDS %d MORE NAMES" % [InputBindings.prompt("interact"), Story.MOTHER_BELL_REQUIRED - bells]
	else:
		var best_distance := INTERACT_RADIUS
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy.dead or enemy.boss:
				continue
			var distance := enemy.global_position.distance_to(goat)
			if distance < best_distance and Stealth.can_takedown(enemy.facing(), goat - enemy.global_position, enemy.detection):
				best_distance = distance
				interact_target = {"kind": "takedown", "enemy": enemy}
				prompt = "%s   HORN STRIKE  (SILENT)" % InputBindings.prompt("interact")
		if interact_target.is_empty():
			for lantern in world.lanterns:
				if lantern.lit and lantern.glass != null and lantern.position.distance_to(goat) < INTERACT_RADIUS:
					interact_target = {"kind": "lantern", "lantern": lantern}
					prompt = "%s   SNUFF THE LANTERN" % InputBindings.prompt("interact")
					break
	if prompt.is_empty():
		if player.hang_held_for >= 0.0 and not player.volley_released and not player.hung.is_empty():
			prompt = "THE MOUNTAIN REMEMBERS  %d%%" % int(minf(1.0, player.hang_held_for / Remembrance.RELEASE_HOLD_SECONDS) * 100.0)
	if prompt != prompt_label.text:
		prompt_label.text = prompt


## Where the current objective is, for the minimap. INF when there is none.
func objective_position() -> Vector3:
	if victory:
		return Vector3.INF
	if boss_awake and is_instance_valid(boss) and not boss.dead:
		return boss.global_position
	if (zone == "shrine" and bells < Story.MOTHER_BELL_REQUIRED) or (bell_rung and bells < Story.IRON_GATE_REQUIRED):
		var stolen := _nearest_stolen_bell()
		if stolen != Vector3.INF:
			return stolen
	match zone:
		"trailhead":
			return Vector3(0.0, 0.0, 6.0)
		"homestead":
			return Vector3(0.0, 0.0, -17.0)
		"shrine":
			return WorldBuilder.BELL_ORIGIN
		_:
			return Vector3(0.0, 0.0, WorldBuilder.GATE_Z)


func _nearest_stolen_bell() -> Vector3:
	var nearest := Vector3.INF
	var distance := INF
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.boss or enemy.bell_index < 0:
			continue
		var next_distance := enemy.global_position.distance_squared_to(player.global_position)
		if next_distance < distance:
			distance = next_distance
			nearest = enemy.global_position
	return nearest


func _bell_position() -> Vector3:
	var origin := WorldBuilder.BELL_ORIGIN
	return Vector3(origin.x, WorldBuilder.height_at(origin.x, origin.z) + 3.0, origin.z)


func _on_interact() -> void:
	_update_prompt()
	match interact_target.get("kind", ""):
		"bell":
			_ring_bell()
		"boss_finish":
			if is_instance_valid(boss) and boss.execution_ready:
				player.gunshot_feedback()
				audio.play("takedown", 2.0, 0.72)
				boss.execute_boss()
		"takedown":
			var enemy: WolverineEnemy = interact_target.enemy
			if is_instance_valid(enemy) and not enemy.dead:
				player.perform_takedown(enemy)
		"lantern":
			var lantern: Dictionary = interact_target.lantern
			lantern.lit = false
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(lantern.light, "light_energy", 0.0, 0.5)
			tween.tween_property(lantern.glass, "emission_energy_multiplier", 0.0, 0.5)
			player.noise_made.emit(player.global_position, Stealth.noise_radius("snuff"))
			audio.play("snuff", -6.0)
			_notice("THE DARK IS YOURS", 0.9)


func _ring_bell() -> void:
	if not Story.can_ring_mother_bell(bells):
		_notice("THE BELL IS MUTE. BRING BACK FOUR NAMES.", 2.0)
		return
	bell_rung = true
	audio.play_at("bell_strike", _bell_position(), 2.0, 0.6)
	audio.play_at("bell", _bell_position(), 6.0, 1.0, 200.0)
	world.bell_material.emission_energy_multiplier = 5.0
	var tween := create_tween()
	tween.tween_property(world.bell_material, "emission_energy_multiplier", 0.7, 3.0)
	player.release_volley("bell")
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.alert_to(player.global_position)
	_show_chapter("THE MOTHER BELL", Story.BELL_RUNG)
	playtest.record("mother_bell_rung", run_time, {"bells": bells})
	zone = ""


# --- Pouches & bells -------------------------------------------------------------

func _drop_pouch(at: Vector3, bell_index: int) -> void:
	# Authored stairs and terraces rise above the height field. Rest the drop
	# on their collision surface and retain that height through its idle bob.
	var ground_y := WorldBuilder.height_at(at.x, at.z)
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, maxf(at.y, ground_y) + 3.0, at.z),
		Vector3(at.x, ground_y - 2.0, at.z), 1, [player.get_rid()])
	var surface := get_world_3d().direct_space_state.intersect_ray(query)
	if not surface.is_empty() and surface.normal.y > 0.55:
		ground_y = surface.position.y
	var node := MeshInstance3D.new()
	var mesh: Mesh
	if bell_index >= 0:
		var bell_mesh := CylinderMesh.new()
		bell_mesh.top_radius = 0.12
		bell_mesh.bottom_radius = 0.22
		bell_mesh.height = 0.34
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color("d09a3c")
		brass.metallic = 0.9
		brass.roughness = 0.25
		brass.emission_enabled = true
		brass.emission = Color("8a4a12")
		brass.emission_energy_multiplier = 1.2
		bell_mesh.material = brass
		mesh = bell_mesh
	else:
		var pouch_mesh := PrismMesh.new()
		pouch_mesh.size = Vector3(0.42, 0.42, 0.42)
		var leather := StandardMaterial3D.new()
		leather.albedo_color = Color("c9a25a")
		leather.emission_enabled = true
		leather.emission = Color("8a5a14")
		leather.emission_energy_multiplier = 0.9
		pouch_mesh.material = leather
		mesh = pouch_mesh
	node.mesh = mesh
	node.position = Vector3(at.x, ground_y + 0.35, at.z)
	add_child(node)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb35c")
	light.light_energy = 1.2
	light.omni_range = 3.0
	light.position.y = 0.4
	node.add_child(light)
	pouches.append({"node": node, "phase": randf() * TAU, "bell": bell_index, "ground_y": ground_y, "at": at})


func _update_pouches(delta: float, now: float) -> void:
	for i in range(pouches.size() - 1, -1, -1):
		var pouch: Dictionary = pouches[i]
		var node: MeshInstance3D = pouch.node
		if player.active and node.global_position.distance_to(player.global_position) < PICKUP_RADIUS:
			pouches.remove_at(i)
			node.queue_free()
			player.add_reserve(POUCH_AMMO)
			audio.play("chime", -8.0 if pouch.bell >= 0 else -16.0, 1.0 if pouch.bell >= 0 else 1.5)
			if pouch.bell >= 0:
				bells += 1
				bells_label.text = "BELLS RECOVERED  //  %d / %d" % [bells, Story.BELL_NAMES.size()]
				center_message.text = ""
				notice_until = 0.0
				_show_chapter(Story.bell_name(pouch.bell) + "  //  A NAME RETURNED", Story.bell_memory(pouch.bell))
				playtest.record("bell_recovered", run_time, {"name": Story.bell_name(pouch.bell), "bells": bells, "zone": zone})
			else:
				_notice("+%d ROUNDS" % POUCH_AMMO, 0.9)
			_save_progress()
			continue
		node.position.y = pouch.ground_y + 0.35 + sin(now * 3.0 + pouch.phase) * 0.08
		node.rotation.y += delta * 1.5


func _on_enemy_killed(enemy: WolverineEnemy) -> void:
	enemies.erase(enemy)
	kills += 1
	if enemy.has_meta("spawn_id"):
		dead_spawn_ids.append(enemy.get_meta("spawn_id"))
	playtest.record("enemy_killed", run_time, {"role": enemy.role, "aware": enemy.detection >= Stealth.ALERT, "zone": zone})
	if enemy.boss:
		if enemy.bell_index >= 0:
			bells += 1
			bells_label.text = "BELLS RECOVERED  //  %d / %d" % [bells, Story.BELL_NAMES.size()]
		WorldBuilder.set_varkas_phase(world, 4)
		victory = true
		_set_hud_visible(false)
		boss_label.visible = false
		boss_bar.visible = false
		boss_fill.visible = false
		victory_veil.visible = true
		ending_actions.visible = true
		victory_veil.color.a = 0.0
		var ending_fade := create_tween()
		ending_fade.tween_property(victory_veil, "color:a", 0.72, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		chapter_title.add_theme_font_size_override("font_size", 34)
		chapter_line.add_theme_font_size_override("font_size", 17)
		chapter_line.add_theme_color_override("font_color", Color("e1d2b4"))
		chapter_line.offset_left = -520.0
		chapter_line.offset_right = 520.0
		chapter_line.offset_top = 142.0
		chapter_line.offset_bottom = 292.0
		_show_chapter("THE MOUNTAIN REMEMBERS.", "\n".join(Story.VICTORY))
		center_message.text = ""
		player.active = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return_button.call_deferred("grab_focus")
		SaveGame.clear()
		playtest.record("victory", run_time, _run_stats())
		playtest.close(run_time, "victory", _run_stats())
		return
	_drop_pouch(enemy.global_position, enemy.bell_index)
	_save_progress()


func _on_enemy_spotted(enemy: WolverineEnemy) -> void:
	if not victory:
		_notice("THEY HAVE YOUR SCENT", 1.1)
		playtest.record("detected", run_time, {"role": enemy.role, "reason": enemy.alert_reason, "zone": zone, "crouched": player.crouched, "lit": player.light_exposure > 0.25})


func _on_boss_phase_changed(_enemy: WolverineEnemy, phase_index: int, _phase_title: String) -> void:
	playtest.record("boss_phase", run_time, {"phase": phase_index})
	var beat: Dictionary = Story.BOSS_PHASES.get(phase_index, {})
	_show_chapter("VARKAS  //  " + beat.get("title", ""), beat.get("line", ""))
	audio.play_at("bell", boss.global_position, 5.0, 0.52 + phase_index * 0.05, 120.0)
	player.add_camera_trauma(0.58 if phase_index == 2 else 0.82)
	WorldBuilder.set_varkas_phase(world, phase_index)
	if phase_index == 2:
		_spawn_reinforcement(Vector2(-8.0, WorldBuilder.COURTYARD_Z + 1.0))
		_spawn_reinforcement(Vector2(8.0, WorldBuilder.COURTYARD_Z + 1.0))
		for fire in world.campfires:
			fire.light_energy = 6.0
	elif phase_index == 3:
		_notice("CONVERGING REMEMBRANCE ROUNDS CAN BREAK HIS CHARGE.", 2.8)
		for fire in world.campfires:
			fire.light_color = Color("ff351f")
			fire.light_energy = 2.8


func _on_boss_attack(_enemy: WolverineEnemy, attack_name: String) -> void:
	if attack_name == "bellquake":
		_notice("BELLQUAKE  //  JUMP THE PULSE OR LEAVE THE RING", 1.2)
	elif attack_name == "charge":
		_notice("RED HORN  //  STEP OFF THE RED LINE", 1.1)
	elif attack_name == "charge_release":
		player.add_camera_trauma(0.16)
	elif attack_name == "swipe":
		_notice("IRON JAW  //  BACK AWAY", 0.85)
	elif attack_name == "exposed":
		_notice("HE IS OPEN  //  RELEASE REMEMBRANCE", 1.4)
	elif attack_name == "convergence_break":
		_notice("CONVERGENCE  //  THE CHARGE IS BROKEN", 1.5)
	elif attack_name == "broken":
		player.add_camera_trauma(0.92)
		_show_chapter("THE LAST BELL", "Varkas folds into the ash. Orin's bell is still around his throat. Finish it horn to horn.")
		_notice("CLOSE IN  //  HORN STRIKE", 4.0)


func _spawn_reinforcement(point: Vector2) -> void:
	var enemy: WolverineEnemy = ENEMY_SCENE.new()
	enemy.name = "Varkas_Reinforcement_%02d" % enemies.size()
	add_child(enemy)
	var route := _route([point, Vector2(point.x * 0.45, point.y - 5.0)])
	enemy.configure(player, "stalker", route[0] + Vector3(0.0, 0.3, 0.0), route, -1)
	enemy.killed.connect(_on_enemy_killed)
	enemy.spotted.connect(_on_enemy_spotted)
	enemies.append(enemy)
	enemy.alert_to(player.global_position)


func _update_boss_hud() -> void:
	var show := started and boss_awake and is_instance_valid(boss) and not boss.dead and not victory
	boss_label.visible = show
	boss_bar.visible = show
	boss_fill.visible = show
	if not show:
		return
	var ratio := clampf(float(boss.health) / boss.max_health, 0.0, 1.0)
	boss_fill.size.x = 440.0 * ratio
	boss_label.text = "VARKAS  //  HORN STRIKE" if boss.execution_ready else "VARKAS  //  %s" % boss.boss_phase_title()
	boss_fill.color = Color("d23b28") if boss.boss_phase >= 3 else (Color("df7837") if boss.boss_phase == 2 else Color("c4a46b"))


# --- Player -------------------------------------------------------------------------

func _on_ammo_changed(current: int, reserve: int) -> void:
	ammo_label.text = "%02d  /  %02d" % [current, reserve]


func _on_health_changed(current: int) -> void:
	health_label.text = "WILL  //  %03d" % current
	health_label.modulate = Color("ff6845") if current < 32 else Color.WHITE


func _on_remembrance_changed(hung: int, capacity: int, sensing: bool) -> void:
	var slots := ""
	for i in capacity:
		slots += "|" if i < hung else "."
	remembrance_label.text = "REMEMBRANCE  //  [%s]  %s" % [slots, "CONTACT" if sensing else "F"]
	remembrance_label.modulate = Color("fff0c0") if sensing else Color.WHITE


func _on_controls_changed(captured: bool) -> void:
	pause_overlay.visible = started and not captured and player.active
	crosshair.visible = started and captured and player.active and not victory
	get_tree().paused = pause_overlay.visible
	if pause_overlay.visible:
		playtest.record("pause", run_time)
		resume_button.grab_focus()


func _resume() -> void:
	if not get_tree().paused or not pause_overlay.visible:
		return
	options_menu.close()
	get_tree().paused = false
	player.begin()


## Every input event, even while paused (see PauseInput).
func _on_any_input(event: InputEvent) -> void:
	if InputBindings.note_event(event):
		_refresh_control_text()
		if started:
			playtest.record("input_device", run_time, {"device": InputBindings.last_device})
	if options_menu.visible:
		return
	if get_tree().paused and pause_overlay.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_resume()


func _on_pause_input(event: InputEvent) -> void:
	var resume_click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var resume_key: bool = event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo
	if get_tree().paused and (resume_click or resume_key):
		pause_overlay.accept_event()
		_resume()


func _return_to_title() -> void:
	if returning_to_title:
		return
	returning_to_title = true
	return_button.disabled = true
	player.active = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	audio.shutdown()
	await get_tree().create_timer(0.2).timeout
	var result := get_tree().change_scene_to_file("res://main.tscn")
	if result != OK:
		returning_to_title = false
		return_button.disabled = false
		push_error("Could not return to the title: " + error_string(result))


func _on_player_died() -> void:
	audio.play("sting", -4.0, 0.5)
	center_message.text = Story.DEATH % InputBindings.prompt("reload")
	notice_until = 0.0
	pause_overlay.visible = false
	deaths += 1
	var at := player.global_position
	playtest.record("death", run_time, {
		"zone": zone, "cause": player.last_damage_source, "x": snappedf(at.x, 0.1), "z": snappedf(at.z, 0.1),
		"bells": bells, "boss_phase": boss.boss_phase if boss_awake and is_instance_valid(boss) else 0,
	})


func _unhandled_input(event: InputEvent) -> void:
	if returning_to_title:
		return
	if started and not player.active and event.is_action_pressed("reload"):
		if victory:
			_return_to_title()
		else:
			_respawn()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if OS.is_debug_build() and started:
		match event.keycode:
			KEY_1:
				_debug_warp(30.0)
			KEY_2:
				_debug_warp(-48.0)
			KEY_3:
				_debug_warp(-82.0)
			KEY_4:
				_debug_prepare_varkas()
			KEY_5:
				if boss_awake and is_instance_valid(boss) and not boss.dead:
					boss.take_damage(boss.max_health)
			KEY_6:
				if boss_awake and is_instance_valid(boss) and not boss.dead:
					boss.take_damage(boss.max_health)
			KEY_7:
				if boss_awake and is_instance_valid(boss) and boss.execution_ready:
					player.global_position = boss.global_position + Vector3(0.0, 0.0, 2.8)
					player.velocity = Vector3.ZERO
					player.rotation.y = 0.0


func _debug_warp(z: float) -> void:
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, z) + 1.2, z)
	player.velocity = Vector3.ZERO
	zone = ""


func _debug_prepare_varkas() -> void:
	if not player.active and not victory:
		_respawn()
	bells = Story.IRON_GATE_REQUIRED
	bell_rung = true
	bells_label.text = "BELLS RECOVERED  //  %d / %d" % [bells, Story.BELL_NAMES.size()]
	player.health = 999
	_on_health_changed(player.health)
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, WorldBuilder.GATE_Z - 3.0) + 1.2, WorldBuilder.GATE_Z - 3.0)
	player.velocity = Vector3.ZERO
	zone = ""
	_update_gate()


func _respawn() -> void:
	var at := Vector3(checkpoint.x, WorldBuilder.height_at(checkpoint.x, checkpoint.z) + 1.2, checkpoint.z)
	player.respawn(at)
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		if enemy.name.begins_with("Varkas_Reinforcement_"):
			enemies.erase(enemy)
			enemy.remove_from_group("enemies")
			enemy.queue_free()
		elif enemy.boss and boss_awake:
			enemy.reset_boss_encounter()
		else:
			enemy.calm()
	playtest.record("respawn", run_time, {"zone": zone, "boss_retry": boss_awake and is_instance_valid(boss) and not boss.dead})
	if boss_awake and is_instance_valid(boss) and not boss.dead:
		boss_awake = false
		WorldBuilder.set_varkas_phase(world, 0)
		for fire in world.campfires:
			fire.light_color = Color("ff7a2a")
			fire.light_energy = 5.0
		boss_label.visible = false
		boss_bar.visible = false
		boss_fill.visible = false
	center_message.text = ""
	_notice("THE MOUNTAIN LETS YOU TRY AGAIN", 1.6)


# --- Interface -------------------------------------------------------------------------

func _notice(text: String, seconds: float) -> void:
	if victory:
		return
	center_message.text = text
	notice_until = Time.get_ticks_msec() * 0.001 + seconds


func _show_chapter(title: String, line: String) -> void:
	if chapter_tween and chapter_tween.is_valid():
		chapter_tween.kill()
	audio.play("sting", -6.0)
	chapter_title.text = title
	chapter_line.text = line
	chapter_title.modulate.a = 0.0
	chapter_line.modulate.a = 0.0
	chapter_tween = create_tween()
	chapter_tween.set_parallel(true)
	chapter_tween.tween_property(chapter_title, "modulate:a", 1.0, 0.8)
	chapter_tween.tween_property(chapter_line, "modulate:a", 1.0, 1.4).set_delay(0.4)
	chapter_tween.chain().tween_interval(6.5 if not victory else 40.0)
	chapter_tween.chain().tween_property(chapter_title, "modulate:a", 0.0, 1.2)
	chapter_tween.parallel().tween_property(chapter_line, "modulate:a", 0.0, 1.2)


func _build_interface() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	# Snow and exposed stone can be much brighter than the old empty backdrop.
	# A soft lower veil keeps status and ammunition legible across every biome.
	var shade_gradient := Gradient.new()
	shade_gradient.colors = PackedColorArray([Color(0.005, 0.01, 0.018, 0.0), Color(0.005, 0.01, 0.018, 0.78)])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = shade_gradient
	shade_texture.fill_from = Vector2(0.0, 0.0)
	shade_texture.fill_to = Vector2(0.0, 1.0)
	hud_ground_shade = TextureRect.new()
	hud_ground_shade.name = "GroundReadabilityShade"
	hud_ground_shade.texture = shade_texture
	hud_ground_shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hud_ground_shade.offset_top = -260.0
	hud_ground_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_ground_shade)

	objective_label = _make_label("OBJECTIVE  //  " + Story.OBJECTIVES.trailhead, 17, Color("e6d8c1"))
	objective_label.position = Vector2(46.0, 40.0)
	hud.add_child(objective_label)
	biome_label = _make_label("WIDOWPINE  //  FROST PINE  //  THE BROKEN FOLD", 12, Color("8fa1a8"))
	biome_label.position = Vector2(46.0, 68.0)
	hud.add_child(biome_label)

	bells_label = _make_label("BELLS RECOVERED  //  0 / 9", 15, Color("e8c578"))
	bells_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bells_label.position = Vector2(-340.0, 42.0)
	bells_label.size = Vector2(295.0, 30.0)
	bells_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(bells_label)

	ammo_label = _make_label("24  /  96", 34, Color("f2e8d4"))
	ammo_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ammo_label.position = Vector2(-230.0, 620.0)
	ammo_label.size = Vector2(190.0, 50.0)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(ammo_label)

	minimap = Minimap.new()
	minimap.mission = self
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-266.0, 80.0)
	minimap.size = Vector2(220.0, 220.0)
	hud.add_child(minimap)

	stealth_label = _make_label("HIDDEN  //  STANDING  //  IN DARK", 14, Color("8fd0c8"))
	stealth_label.position = Vector2(46.0, 548.0)
	hud.add_child(stealth_label)
	exposure_bar = ColorRect.new()
	exposure_bar.color = Color(1.0, 1.0, 1.0, 0.12)
	exposure_bar.position = Vector2(46.0, 574.0)
	exposure_bar.size = Vector2(180.0, 4.0)
	hud.add_child(exposure_bar)
	exposure_fill = ColorRect.new()
	exposure_fill.color = Color("8fd0c8")
	exposure_fill.position = Vector2(46.0, 574.0)
	exposure_fill.size = Vector2(0.0, 4.0)
	hud.add_child(exposure_fill)
	wind_label = _make_label("WIND", 13, Color("aebdc2"))
	wind_label.position = Vector2(46.0, 586.0)
	hud.add_child(wind_label)

	remembrance_label = _make_label("", 15, Color("e8c578"))
	remembrance_label.position = Vector2(46.0, 616.0)
	hud.add_child(remembrance_label)

	health_label = _make_label("WILL  //  100", 16, Color("d5e4e8"))
	health_label.position = Vector2(46.0, 650.0)
	hud.add_child(health_label)

	crosshair = _make_label("+", 28, Color("e8c578"))
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-14.0, -18.0)
	crosshair.size = Vector2(28.0, 36.0)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(crosshair)

	center_message = _make_label("", 24, Color("e8c578"))
	center_message.set_anchors_preset(Control.PRESET_CENTER)
	center_message.position = Vector2(-400.0, -170.0)
	center_message.size = Vector2(800.0, 100.0)
	center_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(center_message)

	boss_label = _make_label("VARKAS", 16, Color("f0e0cb"))
	boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_label.position = Vector2(-280.0, 28.0)
	boss_label.size = Vector2(560.0, 28.0)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.visible = false
	hud.add_child(boss_label)
	boss_bar = ColorRect.new()
	boss_bar.color = Color(0.04, 0.025, 0.025, 0.9)
	boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_bar.position = Vector2(-220.0, 58.0)
	boss_bar.size = Vector2(440.0, 7.0)
	boss_bar.visible = false
	hud.add_child(boss_bar)
	boss_fill = ColorRect.new()
	boss_fill.color = Color("c4a46b")
	boss_fill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_fill.position = Vector2(-220.0, 58.0)
	boss_fill.size = Vector2(440.0, 7.0)
	boss_fill.visible = false
	hud.add_child(boss_fill)

	victory_veil = ColorRect.new()
	victory_veil.name = "VictoryVeil"
	victory_veil.color = Color(0.008, 0.012, 0.022, 0.0)
	victory_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_veil.z_index = 5
	victory_veil.visible = false
	hud.add_child(victory_veil)

	chapter_title = _make_label("", 30, Color("f0e7d7"))
	chapter_title.z_index = 6
	chapter_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	chapter_title.position = Vector2(-420.0, 96.0)
	chapter_title.size = Vector2(840.0, 44.0)
	chapter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapter_title.modulate.a = 0.0
	hud.add_child(chapter_title)
	chapter_line = _make_label("", 16, Color("cbb98f"))
	chapter_line.z_index = 6
	chapter_line.set_anchors_preset(Control.PRESET_CENTER_TOP)
	chapter_line.position = Vector2(-360.0, 142.0)
	chapter_line.size = Vector2(720.0, 120.0)
	chapter_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapter_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chapter_line.modulate.a = 0.0
	hud.add_child(chapter_line)

	prompt_label = _make_label("", 16, Color("dfc186"))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.position = Vector2(-400.0, 120.0)
	prompt_label.size = Vector2(800.0, 40.0)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt_label)

	start_overlay = ColorRect.new()
	start_overlay.color = Color(0.01, 0.02, 0.028, 0.94)
	start_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(start_overlay)
	var start_stack := VBoxContainer.new()
	# The stack now carries the menu too, so it uses nearly the full height.
	_center(start_stack, Rect2(-420.0, -350.0, 840.0, 700.0))
	start_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	start_stack.add_theme_constant_override("separation", 8)
	start_overlay.add_child(start_stack)
	var eyebrow := _make_label("MISSION 01  //  " + Story.SUBTITLE, 15, Color("db6c2f"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_stack.add_child(eyebrow)
	var title := _make_label("MOUNTAIN\nGOAT KILLER", 52, Color("f0e7d7"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_stack.add_child(title)
	for line in Story.INTRO:
		var story := _make_label(line, 16, Color("aebdc2"))
		story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.custom_minimum_size = Vector2(760.0, 0.0)
		start_stack.add_child(story)
	field_note = _make_label("", 13, Color("e8c578"))
	field_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field_note.custom_minimum_size = Vector2(760.0, 0.0)
	start_stack.add_child(field_note)
	controls_label = _make_label("", 12, Color("8fa1a8"))
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label.custom_minimum_size = Vector2(760.0, 0.0)
	start_stack.add_child(controls_label)
	continue_button = _menu_button("CONTINUE  //  " + SaveGame.summary(save_data), _continue_game, 52.0)
	continue_button.visible = not save_data.is_empty()
	start_stack.add_child(continue_button)
	deploy_button = _menu_button("DEPLOY  //  ENTER THE RAVINE" if save_data.is_empty() else "NEW CLIMB  //  FORGET THE SAVED ASCENT", _on_new_game_pressed, 52.0 if save_data.is_empty() else 42.0)
	start_stack.add_child(deploy_button)
	var menu_row := HBoxContainer.new()
	menu_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_row.add_theme_constant_override("separation", 14)
	start_stack.add_child(menu_row)
	difficulty_button = _menu_button("", _cycle_difficulty, 40.0)
	difficulty_button.custom_minimum_size.x = 300.0
	menu_row.add_child(difficulty_button)
	var title_options := _menu_button("OPTIONS", Callable(), 40.0)
	title_options.custom_minimum_size.x = 180.0
	title_options.pressed.connect(func() -> void: _open_options(title_options))
	menu_row.add_child(title_options)
	var title_quit := _menu_button("LEAVE", _quit_game, 40.0)
	title_quit.custom_minimum_size.x = 140.0
	menu_row.add_child(title_quit)

	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.0, 0.0, 0.0, 0.58)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Only this modal receives input while the rest of the scene is paused.
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.z_index = 10
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.focus_mode = Control.FOCUS_ALL
	pause_overlay.gui_input.connect(_on_pause_input)
	pause_overlay.visible = false
	hud.add_child(pause_overlay)
	var pause_text := _make_label("FIELD PAUSED", 26, Color("e8c578"))
	_center(pause_text, Rect2(-230.0, -110.0, 460.0, 50.0))
	pause_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_overlay.add_child(pause_text)
	# RESUME sits exactly at screen centre, where the old click-anywhere
	# overlay was most often clicked.
	pause_panel = VBoxContainer.new()
	_center(pause_panel, Rect2(-170.0, -26.0, 340.0, 190.0))
	pause_panel.add_theme_constant_override("separation", 12)
	pause_overlay.add_child(pause_panel)
	resume_button = _menu_button("RESUME", _resume, 52.0)
	# Resume on press, not release. The held button is then suppressed as fire
	# until it is let go, so re-entering the field never fires a shot.
	resume_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	pause_panel.add_child(resume_button)
	pause_options_button = _menu_button("OPTIONS", func() -> void: _open_options(pause_options_button), 44.0)
	pause_panel.add_child(pause_options_button)
	pause_panel.add_child(_menu_button("RETURN TO TITLE  //  PROGRESS KEPT", _return_to_title, 44.0))

	ending_actions = HBoxContainer.new()
	ending_actions.z_index = 6
	ending_actions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ending_actions.position = Vector2(-244.0, -105.0)
	ending_actions.size = Vector2(488.0, 50.0)
	ending_actions.add_theme_constant_override("separation", 18)
	ending_actions.visible = false
	hud.add_child(ending_actions)
	return_button = Button.new()
	return_button.text = "RETURN TO TITLE  [R]"
	return_button.custom_minimum_size = Vector2(260.0, 50.0)
	return_button.pressed.connect(_return_to_title)
	ending_actions.add_child(return_button)
	var quit_button := Button.new()
	quit_button.text = "LEAVE THE MOUNTAIN"
	quit_button.custom_minimum_size = Vector2(210.0, 50.0)
	quit_button.pressed.connect(_quit_game)
	ending_actions.add_child(quit_button)

	options_menu = OptionsMenu.new()
	hud.add_child(options_menu)
	options_menu.settings_changed.connect(_apply_settings)
	options_menu.closed.connect(_on_options_closed)

	_set_hud_visible(false)


func _start_game() -> void:
	started = true
	start_overlay.visible = false
	options_menu.close()
	_set_hud_visible(true)
	logged_difficulty = Difficulty.key()
	playtest.open(GameSettings.persistent() and GameSettings.get_value("playtest_log"), {
		"difficulty": logged_difficulty,
		"long_telegraphs": GameSettings.get_value("long_telegraphs"),
		"aim_assist": GameSettings.get_value("aim_assist"),
		"device": InputBindings.last_device,
		"continued": continued,
		"bells": bells,
		"checkpoint": CHECKPOINTS.find_key(checkpoint) if CHECKPOINTS.values().has(checkpoint) else "trailhead",
	})
	player.begin()


## With a save on disk, the first press only asks; the second erases it.
func _on_new_game_pressed() -> void:
	if not save_data.is_empty() and deploy_button.text != "PRESS AGAIN TO ERASE THE SAVED ASCENT":
		deploy_button.text = "PRESS AGAIN TO ERASE THE SAVED ASCENT"
		return
	_new_game()


func _new_game() -> void:
	SaveGame.clear()
	save_data = {}
	_start_game()


func _continue_game() -> void:
	if continue_from(save_data):
		_start_game()
	else:
		_new_game()


## Restore a saved ascent onto this freshly built mission, as a respawn at the
## saved refuge would find it. Returns false if the data is unusable.
func continue_from(data: Dictionary) -> bool:
	var clean := SaveGame.sanitize(data)
	if clean.is_empty() or started:
		return false
	for enemy in enemies.duplicate():
		if enemy.boss or not enemy.has_meta("spawn_id") or not int(enemy.get_meta("spawn_id")) in clean.dead:
			continue
		enemies.erase(enemy)
		enemy.remove_from_group("enemies")
		enemy.queue_free()
		dead_spawn_ids.append(enemy.get_meta("spawn_id"))
	kills = dead_spawn_ids.size()
	bells = clean.bells
	bells_label.text = "BELLS RECOVERED  //  %d / %d" % [bells, Story.BELL_NAMES.size()]
	if clean.bell_rung:
		bell_rung = true
		world.bell_material.emission_energy_multiplier = 0.7
	for drop in clean.drops:
		_drop_pouch(Vector3(drop.x, drop.y, drop.z), drop.bell)
	for key in clean.seen:
		seen_zones[key] = true
	checkpoint = CHECKPOINTS[clean.zone]
	player.global_position = Vector3(checkpoint.x, WorldBuilder.height_at(checkpoint.x, checkpoint.z) + 1.2, checkpoint.z)
	player.velocity = Vector3.ZERO
	player.reserve = clean.reserve
	player.ammo_changed.emit(player.ammo, player.reserve)
	run_time = clean.playtime
	deaths = clean.deaths
	continued = true
	return true


## The save as it stands: the same state a death at this moment would keep.
func progress_snapshot() -> Dictionary:
	var drops: Array = []
	for pouch in pouches:
		var at: Vector3 = pouch.at
		drops.append({"x": at.x, "y": at.y, "z": at.z, "bell": pouch.bell})
	var refuge: Variant = zone if CHECKPOINTS.has(zone) else CHECKPOINTS.find_key(checkpoint)
	return {
		"version": SaveGame.VERSION,
		"zone": refuge if refuge != null else "trailhead",
		"bells": bells,
		"bell_rung": bell_rung,
		"dead": dead_spawn_ids.duplicate(),
		"drops": drops,
		"reserve": player.reserve,
		"seen": seen_zones.keys(),
		"playtime": run_time,
		"deaths": deaths,
	}


func _save_progress() -> void:
	# Varkas's fight restarts from Iron Hide, so the gate refuge is the last save.
	if not started or victory or boss_awake or not player.active:
		return
	SaveGame.store(progress_snapshot())


func _run_stats() -> Dictionary:
	return {
		"time": snappedf(run_time, 0.1),
		"deaths": deaths,
		"bells": bells,
		"kills": kills,
		"shots": player.shots_fired if is_instance_valid(player) else 0,
		"hits": player.shots_hit if is_instance_valid(player) else 0,
		"difficulty": Difficulty.key(),
	}


func _quit_game() -> void:
	playtest.close(run_time, "quit", _run_stats())
	_finish_capture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		playtest.close(run_time, "window_closed", _run_stats())


func _exit_tree() -> void:
	playtest.close(run_time, "title" if returning_to_title else "exit", _run_stats())


func _cycle_difficulty() -> void:
	GameSettings.set_value("difficulty", Difficulty.next(Difficulty.key()))
	GameSettings.save()
	_apply_settings()


func _open_options(return_focus: Control) -> void:
	options_return_focus = return_focus
	options_menu.open()


func _on_options_closed() -> void:
	_apply_settings()
	if is_instance_valid(options_return_focus) and options_return_focus.is_visible_in_tree():
		options_return_focus.grab_focus()


func _apply_settings() -> void:
	GameSettings.apply_audio()
	var brightness: float = GameSettings.get_value("brightness")
	world.environment.adjustment_enabled = not is_equal_approx(brightness, 1.0)
	world.environment.adjustment_brightness = brightness
	_refresh_control_text()
	if started and Difficulty.key() != logged_difficulty:
		logged_difficulty = Difficulty.key()
		playtest.record("difficulty_changed", run_time, {"difficulty": logged_difficulty})


## Keep every on-screen key hint true to the current bindings and device.
func _refresh_control_text() -> void:
	field_note.text = "STEALTH  //  Crouch (%s) to move quietly and stay small. Keep the wind in your face: wolverines smell what it carries. Snuff lanterns (%s), throw stones (%s) to pull them away, and strike from behind (%s) for a silent kill.\nREMEMBRANCE  //  Tap %s to hang a live round where you stand. Hold %s and the mountain fires them all at once." % [
		_key("crouch"), _key("interact"), _key("throw_stone"), _key("interact"), _key("remembrance"), _key("remembrance")]
	controls_label.text = _controls_text()
	difficulty_button.text = "DIFFICULTY  //  " + Difficulty.title()
	difficulty_button.tooltip_text = Difficulty.preset().line
	if started and not player.active and not victory:
		center_message.text = Story.DEATH % InputBindings.prompt("reload")


func _controls_text() -> String:
	var move := "LEFT STICK"
	var look := "RIGHT STICK"
	if InputBindings.last_device != "gamepad":
		var keys: Array[String] = []
		for action in ["move_forward", "move_left", "move_back", "move_right"]:
			keys.append(_key(action))
		move = "".join(keys) if keys.all(func(k: String) -> bool: return k.length() == 1) else "/".join(keys)
		look = "MOUSE"
	return "%s MOVE   %s AIM   %s FIRE   %s FOCUS   %s SPRINT   %s JUMP   %s CROUCH   %s STONE   %s INTERACT   %s REMEMBER   %s RELOAD   %s PAUSE" % [
		move, look, _key("fire"), _key("aim"), _key("sprint"), _key("jump"), _key("crouch"),
		_key("throw_stone"), _key("interact"), _key("remembrance"), _key("reload"), _key("pause")]


func _key(action: String) -> String:
	return InputBindings.prompt(action)


func _menu_button(text_value: String, action: Callable, height := 46.0) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, height)
	button.add_theme_font_size_override("font_size", 18 if height >= 50.0 else 15)
	if action.is_valid():
		button.pressed.connect(action)
	return button


## Anchor a control to its parent's centre with an explicit rectangle.
func _center(control: Control, rect: Rect2) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _set_hud_visible(visible_state: bool) -> void:
	for node in [hud_ground_shade, objective_label, biome_label, ammo_label, health_label, bells_label, remembrance_label, stealth_label, exposure_bar, exposure_fill, wind_label, center_message, prompt_label, minimap, crosshair]:
		node.visible = visible_state


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
