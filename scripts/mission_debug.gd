class_name MissionDebug
extends RefCounted
## Repeatable proof captures (run from the command line after `--`) and the
## number-key warps for visual QA in debug builds. None of this runs in normal
## play: captures need an explicit flag and warps need `OS.is_debug_build()`.

const CAPTURES := {
	"--capture-iron-crown-live": "iron_crown_live",
	"--capture-widowpine-live": "widowpine_live",
	"--capture-carrion-live": "carrion_live",
	"--capture-iron-crown-approach": "iron_crown_approach",
	"--capture-varkas-phase1": "varkas_phase1",
	"--capture-varkas-phase3": "varkas_phase3",
	"--capture-varkas-execution": "varkas_execution",
}


## Start the capture named on the command line, if any.
static func run_requested_capture(mission: Node) -> void:
	for flag in CAPTURES:
		if flag in OS.get_cmdline_user_args():
			match CAPTURES[flag]:
				"iron_crown_live":
					_capture_view(mission, Vector3(0.0, 0.0, -43.0), 0.19, "iron_crown", "THE IRON GATE OPENS ONLY WHEN EIGHT NAMES SPEAK", 20, "res://art_direction/iron_crown/iron-crown-live-game-v1.png")
				"widowpine_live":
					_capture_view(mission, Vector3(0.0, 0.0, 18.0), 0.07, "whitewood", "FOLLOW THE BLOOD-TRACKS TO THE FAMILY FOLD", 30, "res://art_direction/widowpine/widowpine-live-game-v1.png")
				"carrion_live":
					# The shrine is carved into the west wall around the historic bell
					# origin; centre the review camera on its processional lane.
					_capture_view(mission, Vector3(-5.5, 0.0, -6.0), 0.16, "carrion_cut", "CARRY FOUR NAMES TO THE MOTHER BELL", 30, "res://art_direction/carrion_cut/carrion-cut-live-game-v1.png")
				"iron_crown_approach":
					_capture_view(mission, Vector3(0.0, 0.0, -64.0), 0.19, "iron_crown", "CARRY THE EIGHT NAMES TO THE GATE", 25, "res://art_direction/iron_crown/iron-crown-approach-v1.png", "THE IRON CROWN  //  THIRTY METRES TO THE IRON THROAT")
				"varkas_phase1":
					capture_varkas_phase(mission, 1)
				"varkas_phase3":
					capture_varkas_phase(mission, 3)
				"varkas_execution":
					capture_varkas_execution(mission)
			return


## A player-camera frame of one biome for environment review.
static func _capture_view(mission: Node, at: Vector3, pitch: float, biome: String, objective: String, frames: int, path: String, biome_line := "") -> void:
	mission._start_game()
	var player: GoatPlayer = mission.player
	player.global_position = Vector3(at.x, WorldBuilder.height_at(at.x, at.z) + 1.2, at.z)
	player.rotation.y = 0.0
	player.pitch = pitch
	player.velocity = Vector3.ZERO
	WorldBuilder.set_biome(mission.world, biome)
	mission.current_biome = biome
	mission.hud.set_biome(biome)
	if not biome_line.is_empty():
		mission.hud.biome_label.text = biome_line
	mission.hud.set_objective(objective)
	mission.started = false
	await _save_after(mission, frames, path)


static func capture_varkas_phase(mission: Node, phase_index: int) -> void:
	mission._start_game()
	var player: GoatPlayer = mission.player
	var boss: WolverineEnemy = mission.boss
	# Stage the proof from inside the court, at the same intimate distance where
	# the Red Horn charge becomes dangerous. The slight angle keeps Orin's bell,
	# the broken armor profile, and Varkas' face readable at once.
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, -98.2) + 1.2, -98.2)
	var to_boss := boss.global_position - player.global_position
	player.rotation.y = atan2(-to_boss.x, -to_boss.z)
	player.pitch = 0.12
	player.velocity = Vector3.ZERO
	WorldBuilder.set_biome(mission.world, "iron_crown")
	WorldBuilder.set_varkas_phase(mission.world, phase_index)
	if phase_index >= 3:
		for fire in mission.world.campfires:
			fire.light_color = Color("ff351f")
			fire.light_energy = 2.8
	mission.current_biome = "iron_crown"
	mission.bells = 8
	mission.hud.set_bells(8)
	mission.boss_awake = true
	boss.set_physics_process(false)
	boss.look_at(Vector3(player.global_position.x, boss.global_position.y, player.global_position.z), Vector3.UP)
	boss.preview_boss_phase(phase_index)
	var phase_title := boss.boss_phase_title()
	mission.hud.biome_label.text = "THE IRON CROWN  //  VARKAS  //  %s" % phase_title
	mission.hud.set_objective("BREAK VARKAS  //  TAKE BACK ORIN'S BELL" if phase_index >= 3 else "SHATTER VARKAS' IRON HIDE")
	mission.hud.update_boss(boss, true)
	mission.started = false
	await _save_after(mission, 75, "res://art_direction/iron_crown/iron-crown-varkas-phase%d-v1.png" % phase_index)


## Drives the real damage gates and final interaction handler. It does not set
## `victory` directly, so a captured ending also verifies that the boss death
## signal returns Orin's ninth bell and resolves the mission.
static func capture_varkas_execution(mission: Node) -> void:
	mission._start_game()
	var player: GoatPlayer = mission.player
	var boss: WolverineEnemy = mission.boss
	WorldBuilder.set_biome(mission.world, "iron_crown")
	mission.current_biome = "iron_crown"
	mission.zone = "gate"
	mission.seen_zones["gate"] = true
	mission.hud.biome_label.text = "THE IRON CROWN  //  VARKAS  //  THE LAST BELL"
	mission.bells = Story.IRON_GATE_REQUIRED
	mission.hud.set_bells(mission.bells)
	mission.boss_awake = true
	player.health = 999
	player.active = true
	boss.set_physics_process(false)
	boss.state = WolverineEnemy.State.DORMANT
	for attempt in 3:
		boss.take_damage(boss.max_health * 4)
		boss.boss_transition_lock = 0.0
	if not boss.execution_ready:
		push_error("Could not stage Varkas' execution beat")
		await mission._finish_capture(1)
		return
	for enemy in mission.enemies:
		if is_instance_valid(enemy) and enemy != boss:
			enemy.set_physics_process(false)
	player.global_position = boss.global_position + Vector3(0.0, 0.0, 2.65)
	player.velocity = Vector3.ZERO
	var to_boss := boss.global_position - player.global_position
	player.rotation.y = atan2(-to_boss.x, -to_boss.z)
	player.pitch = 0.08
	mission._update_prompt()
	if mission.interact_target.get("kind", "") != "boss_finish":
		push_error("Varkas' final horn-strike prompt did not become available")
		await mission._finish_capture(1)
		return
	mission._on_interact()
	if not mission.victory or mission.bells != Story.BELL_NAMES.size():
		push_error("Varkas execution did not resolve the nine-bell ending")
		await mission._finish_capture(1)
		return
	await _save_after(mission, 110, "res://art_direction/iron_crown/iron-crown-varkas-execution-v1.png")


static func _save_after(mission: Node, frames: int, path: String) -> void:
	for _frame in range(frames):
		await mission.get_tree().process_frame
	var image := mission.get_viewport().get_texture().get_image()
	var error := image.save_png(path) if image != null else ERR_UNAVAILABLE
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		await mission._finish_capture(1)
		return
	print("Saved proof frame " + path)
	await mission._finish_capture()


## Number keys warp through the authored beats for fast visual QA:
## 1 Widowpine, 2 Carrion Cut, 3 Iron Crown, 4 the Varkas arena, 5/6 advance
## his phases (6 again breaks him), 7 frames the final horn strike.
static func handle_key(mission: Node, keycode: int) -> void:
	var boss: WolverineEnemy = mission.boss
	var boss_active: bool = mission.boss_awake and is_instance_valid(boss) and not boss.dead
	match keycode:
		KEY_1:
			warp(mission, 30.0)
		KEY_2:
			warp(mission, -48.0)
		KEY_3:
			warp(mission, -82.0)
		KEY_4:
			prepare_varkas(mission)
		KEY_5, KEY_6:
			if boss_active:
				boss.take_damage(boss.max_health)
		KEY_7:
			if boss_active and boss.execution_ready:
				var player: GoatPlayer = mission.player
				player.global_position = boss.global_position + Vector3(0.0, 0.0, 2.8)
				player.velocity = Vector3.ZERO
				player.rotation.y = 0.0


static func warp(mission: Node, z: float) -> void:
	var player: GoatPlayer = mission.player
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, z) + 1.2, z)
	player.velocity = Vector3.ZERO
	mission.zone = ""


static func prepare_varkas(mission: Node) -> void:
	var player: GoatPlayer = mission.player
	if not player.active and not mission.victory:
		mission._respawn()
	mission.bells = Story.IRON_GATE_REQUIRED
	mission.bell_rung = true
	mission.hud.set_bells(mission.bells)
	player.health = 999
	mission.hud.set_health(player.health)
	player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, WorldBuilder.GATE_Z - 3.0) + 1.2, WorldBuilder.GATE_Z - 3.0)
	player.velocity = Vector3.ZERO
	mission.zone = ""
	mission._update_gate()
