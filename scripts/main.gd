extends Node3D
## Mission flow for THE LAST BELL: builds the ravine, spawns the warpack on
## their patrols, and runs checkpoints, bells, the mother bell, the gate and
## Varkas. It owns the saved campaign and the local playtest log.
##
## The interface lives in MissionHud (`hud`); proof captures and debug warps
## live in MissionDebug.

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
var hud: MissionHud
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
var returning_to_title := false
var pouches: Array = []
var zone := ""
var checkpoint := Vector3(0.0, 0.0, 34.0)
var seen_zones := {}
var current_biome := ""
var last_objective := ""
var hud_tick := 0
var snow: GPUParticles3D
var interact_target: Dictionary = {}

## Persistence and playtest telemetry.
var playtest := PlaytestLog.new()
var save_data: Dictionary = {}
var continued := false
var run_time := 0.0
var deaths := 0
var dead_spawn_ids: Array[int] = []
var cairns_kindled: Array[int] = []
var logged_difficulty := ""
var pause_input: PauseInput


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
	hud = MissionHud.new()
	add_child(hud)
	hud.build(self, SaveGame.summary(save_data))
	hud.continue_requested.connect(_continue_game)
	hud.new_game_requested.connect(_new_game)
	hud.difficulty_cycle_requested.connect(_cycle_difficulty)
	hud.quit_requested.connect(_quit_game)
	hud.resume_requested.connect(_resume)
	hud.return_to_title_requested.connect(_return_to_title)
	hud.settings_changed.connect(_apply_settings)
	_spawn_player()
	_spawn_enemies()
	_apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_input = PauseInput.new()
	pause_input.name = "PauseInput"
	pause_input.mission = self
	pause_input.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_input)
	MissionDebug.run_requested_capture(self)


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
		hud.set_objective(objective)
	hud.tick(now)
	_update_lights(delta, now)
	_update_pouches(delta, now)
	_update_gate()
	_update_boss_hud()
	snow.position = Vector3(player.global_position.x, player.global_position.y + 12.0, player.global_position.z)
	audio.set_wind(0.35 + (0.45 if player.sprinting else 0.0) + (0.15 if player.global_position.z < -40.0 else 0.0))
	hud_tick += 1
	if hud_tick % 3 == 0:
		hud.update_stealth(enemies, player, now)
		_update_prompt()
	if hud_tick % 2 == 0:
		hud.minimap.queue_redraw()


# --- Spawning ------------------------------------------------------------------

func _spawn_player() -> void:
	player = PLAYER_SCENE.new()
	player.name = "Player"
	var start: Vector3 = CHECKPOINTS.trailhead
	player.position = Vector3(start.x, WorldBuilder.height_at(start.x, start.z) + 1.2, start.z)
	add_child(player)
	player.ammo_changed.connect(hud.set_ammo)
	player.health_changed.connect(hud.set_health)
	player.controls_changed.connect(_on_controls_changed)
	player.remembrance_changed.connect(hud.set_remembrance)
	player.notice.connect(_notice)
	player.interact_pressed.connect(_on_interact)
	player.noise_made.connect(_on_noise)
	player.died.connect(_on_player_died)
	hud.minimap.player = player
	hud.set_ammo(player.ammo, player.reserve)
	hud.set_health(player.health)
	hud.set_remembrance(0, player.remembrance_capacity, false)


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
		# Flank hunters, off the main road: a tracker on the shrine's east
		# shoulder, and the kill-site camp in the Black Ravine's west gully.
		["tracker", [Vector2(9.5, -20.0), Vector2(13.0, -29.0), Vector2(11.0, -38.0)], -1],
		["tracker", [Vector2(-14.0, -60.0), Vector2(-16.5, -68.5), Vector2(-12.0, -66.5)], -1],
		["stalker", [Vector2(-16.0, -62.5), Vector2(-17.8, -66.0)], -1],
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
		enemy.body_found.connect(_on_body_found)
		enemies.append(enemy)
		if enemy.boss:
			boss = enemy
			enemy.boss_phase_changed.connect(_on_boss_phase_changed)
			enemy.boss_attack.connect(_on_boss_attack)
	total_enemies = enemies.size()
	hud.set_bells(0)


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
		hud.set_biome(current_biome)
	var key := "shrine" if zone == "shrine_rung" else zone
	if not seen_zones.has(key):
		seen_zones[key] = true
		var chapter := Story.chapter_for_zone(zone)
		if not chapter.is_empty():
			_show_chapter(chapter.title, chapter.line)
	# After the chapter is marked seen, so Continue does not replay its card.
	_save_progress()


func _update_lights(_delta: float, now: float) -> void:
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


func _update_boss_hud() -> void:
	# Varkas is freed a few seconds after the ending; never hand the HUD a dead node.
	var show := started and boss_awake and is_instance_valid(boss) and not boss.dead and not victory
	hud.update_boss(boss if show else null, show)


func _on_noise(source: Vector3, radius: float) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.hear_noise(source, radius)


func _update_prompt() -> void:
	interact_target = {}
	var prompt := ""
	var goat := player.global_position
	var key := InputBindings.prompt("interact")
	if boss_awake and is_instance_valid(boss) and boss.execution_ready and goat.distance_to(boss.global_position) < 3.8:
		interact_target = {"kind": "boss_finish"}
		prompt = "%s   HORN STRIKE  //  END VARKAS" % key
	elif not bell_rung and goat.distance_to(_bell_position()) < BELL_RADIUS:
		interact_target = {"kind": "bell"}
		if Story.can_ring_mother_bell(bells):
			prompt = "%s   RING THE MOTHER BELL  (WAKES THE WHOLE RAVINE)" % key
		else:
			prompt = "%s   THE BELL NEEDS %d MORE NAMES" % [key, Story.MOTHER_BELL_REQUIRED - bells]
	else:
		var best_distance := INTERACT_RADIUS
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy.dead or enemy.boss:
				continue
			var distance := enemy.global_position.distance_to(goat)
			if distance < best_distance and Stealth.can_takedown(enemy.facing(), goat - enemy.global_position, enemy.detection):
				best_distance = distance
				interact_target = {"kind": "takedown", "enemy": enemy}
				prompt = "%s   HORN STRIKE  (SILENT)" % key
		if interact_target.is_empty():
			for cairn in world.cairns:
				if not cairn.kindled and Vector2(cairn.position.x - goat.x, cairn.position.z - goat.z).length() < INTERACT_RADIUS + 0.4:
					interact_target = {"kind": "cairn", "cairn": cairn}
					prompt = "%s   KINDLE MAREN'S CAIRN" % key
					break
		if interact_target.is_empty():
			for lantern in world.lanterns:
				if lantern.lit and lantern.glass != null and lantern.position.distance_to(goat) < INTERACT_RADIUS:
					interact_target = {"kind": "lantern", "lantern": lantern}
					prompt = "%s   SNUFF THE LANTERN" % key
					break
	if prompt.is_empty():
		if player.hang_held_for >= 0.0 and not player.volley_released and not player.hung.is_empty():
			prompt = "THE MOUNTAIN REMEMBERS  %d%%" % int(minf(1.0, player.hang_held_for / Remembrance.RELEASE_HOLD_SECONDS) * 100.0)
	hud.set_prompt(prompt)


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
		"cairn":
			_kindle_cairn(interact_target.cairn)
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


## Each of Maren's cairns lets one more Remembrance round hang.
func _kindle_cairn(cairn: Dictionary, announce := true) -> void:
	if cairn.kindled:
		return
	WorldBuilder.kindle_cairn(cairn)
	cairns_kindled.append(cairn.index)
	player.set_remembrance_capacity(Remembrance.capacity_for(cairns_kindled.size()))
	if not announce:
		return
	audio.play_at("bell_strike", cairn.position, -10.0, 1.6)
	audio.play("chime", -6.0, 0.8)
	_show_chapter("MAREN'S CAIRN  //  REMEMBRANCE DEEPENS", Story.cairn_memory(cairn.index))
	_notice("%d ROUNDS CAN HANG" % player.remembrance_capacity, 2.2)
	playtest.record("cairn_kindled", run_time, {"index": cairn.index, "zone": zone, "capacity": player.remembrance_capacity})
	_save_progress()


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
				hud.set_bells(bells)
				hud.clear_center()
				_show_chapter(Story.bell_name(pouch.bell) + "  //  A NAME RETURNED", Story.bell_memory(pouch.bell))
				playtest.record("bell_recovered", run_time, {"name": Story.bell_name(pouch.bell), "bells": bells, "zone": zone})
			else:
				_notice("+%d ROUNDS" % POUCH_AMMO, 0.9)
			_save_progress()
			continue
		node.position.y = pouch.ground_y + 0.35 + sin(now * 3.0 + pouch.phase) * 0.08
		node.rotation.y += delta * 1.5


# --- Warpack and Varkas ------------------------------------------------------------

func _on_enemy_killed(enemy: WolverineEnemy) -> void:
	enemies.erase(enemy)
	kills += 1
	if enemy.has_meta("spawn_id"):
		dead_spawn_ids.append(enemy.get_meta("spawn_id"))
	playtest.record("enemy_killed", run_time, {"role": enemy.role, "aware": enemy.detection >= Stealth.ALERT, "zone": zone})
	if enemy.boss:
		_finish_victory(enemy)
		return
	_drop_pouch(enemy.global_position, enemy.bell_index)
	_save_progress()


func _finish_victory(varkas: WolverineEnemy) -> void:
	if varkas.bell_index >= 0:
		bells += 1
		hud.set_bells(bells)
	WorldBuilder.set_varkas_phase(world, 4)
	victory = true
	hud.show_ending()
	audio.play("sting", -6.0)
	player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveGame.clear()
	playtest.record("victory", run_time, _run_stats())
	playtest.close(run_time, "victory", _run_stats())


func _on_enemy_spotted(enemy: WolverineEnemy) -> void:
	if not victory:
		_notice("THEY HAVE YOUR SCENT", 1.1)
		playtest.record("detected", run_time, {"role": enemy.role, "reason": enemy.alert_reason, "zone": zone, "crouched": player.crouched, "lit": player.light_exposure > 0.25})


func _on_body_found(enemy: WolverineEnemy, at: Vector3) -> void:
	if victory:
		return
	_notice("THEY FOUND A BODY  //  THE PACK IS UNEASY", 1.8)
	playtest.record("body_found", run_time, {"role": enemy.role, "zone": zone, "distance": snappedf(at.distance_to(player.global_position), 0.1)})


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
	match attack_name:
		"bellquake":
			_notice("BELLQUAKE  //  JUMP THE PULSE OR LEAVE THE RING", 1.2)
		"charge":
			_notice("RED HORN  //  STEP OFF THE RED LINE", 1.1)
		"charge_release":
			player.add_camera_trauma(0.16)
		"swipe":
			_notice("IRON JAW  //  BACK AWAY", 0.85)
		"exposed":
			_notice("HE IS OPEN  //  RELEASE REMEMBRANCE", 1.4)
		"convergence_break":
			_notice("CONVERGENCE  //  THE CHARGE IS BROKEN", 1.5)
		"broken":
			player.add_camera_trauma(0.92)
			_show_chapter("THE LAST BELL", "Varkas folds into the ash. Orin's bell is still around his throat. Finish it horn to horn.")
			_notice("CLOSE IN  //  HORN STRIKE", 4.0)


func _spawn_reinforcement(point: Vector2) -> void:
	var enemy: WolverineEnemy = ENEMY_SCENE.new()
	enemy.name = "Varkas_Reinforcement_%02d" % enemies.size()
	add_child(enemy)
	var route := _route([point, Vector2(point.x * 0.45, point.y - 5.0)])
	enemy.configure(player, "stalker", route[0] + Vector3(0.0, 0.3, 0.0), route, -1)
	# Summoned mid-fight; retries clear them, so they leave no bodies behind.
	enemy.leaves_body = false
	enemy.killed.connect(_on_enemy_killed)
	enemy.spotted.connect(_on_enemy_spotted)
	enemies.append(enemy)
	enemy.alert_to(player.global_position)


# --- Player, pause and death ---------------------------------------------------------

func _on_controls_changed(captured: bool) -> void:
	var open := started and not captured and player.active
	hud.show_pause(open)
	hud.set_crosshair(started and captured and player.active and not victory)
	get_tree().paused = open
	if open:
		playtest.record("pause", run_time)


func _resume() -> void:
	if not get_tree().paused or not hud.is_pause_open():
		return
	hud.show_pause(false)
	get_tree().paused = false
	player.begin()


## Every input event, even while paused (see PauseInput).
func _on_any_input(event: InputEvent) -> void:
	if InputBindings.note_event(event):
		hud.refresh_control_text(_awaiting_retry())
		if started:
			playtest.record("input_device", run_time, {"device": InputBindings.last_device})
	if hud.options_menu.visible:
		return
	if get_tree().paused and hud.is_pause_open() and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_resume()


func _return_to_title() -> void:
	if returning_to_title:
		return
	returning_to_title = true
	hud.return_button.disabled = true
	player.active = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	audio.shutdown()
	await get_tree().create_timer(0.2).timeout
	var result := get_tree().change_scene_to_file("res://main.tscn")
	if result != OK:
		returning_to_title = false
		hud.return_button.disabled = false
		push_error("Could not return to the title: " + error_string(result))


func _on_player_died() -> void:
	audio.play("sting", -4.0, 0.5)
	hud.show_death()
	deaths += 1
	var at := player.global_position
	playtest.record("death", run_time, {
		"zone": zone, "cause": player.last_damage_source, "x": snappedf(at.x, 0.1), "z": snappedf(at.z, 0.1),
		"bells": bells, "boss_phase": boss.boss_phase if boss_awake and is_instance_valid(boss) else 0,
	})


func _awaiting_retry() -> bool:
	return started and not player.active and not victory


func _unhandled_input(event: InputEvent) -> void:
	if returning_to_title:
		return
	if started and not player.active and event.is_action_pressed("reload"):
		if victory:
			_return_to_title()
		else:
			_respawn()
		return
	if OS.is_debug_build() and started and event is InputEventKey and event.pressed and not event.echo:
		MissionDebug.handle_key(self, event.keycode)


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
		hud.update_boss(boss, false)
	hud.clear_center()
	_notice("THE MOUNTAIN LETS YOU TRY AGAIN", 1.6)


func _notice(text: String, seconds: float) -> void:
	hud.notice(text, seconds)


func _show_chapter(title: String, line: String) -> void:
	audio.play("sting", -6.0)
	hud.show_chapter(title, line)


# --- Starting, saving and settings ------------------------------------------------

func _start_game() -> void:
	started = true
	hud.hide_title()
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
	hud.set_bells(bells)
	if clean.bell_rung:
		bell_rung = true
		world.bell_material.emission_energy_multiplier = 0.7
	for drop in clean.drops:
		_drop_pouch(Vector3(drop.x, drop.y, drop.z), drop.bell)
	for key in clean.seen:
		seen_zones[key] = true
	for index in clean.cairns:
		if index < world.cairns.size():
			_kindle_cairn(world.cairns[index], false)
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
		"cairns": cairns_kindled.duplicate(),
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
		"cairns": cairns_kindled.size(),
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


func _apply_settings() -> void:
	GameSettings.apply_audio()
	var brightness: float = GameSettings.get_value("brightness")
	world.environment.adjustment_enabled = not is_equal_approx(brightness, 1.0)
	world.environment.adjustment_brightness = brightness
	hud.refresh_control_text(_awaiting_retry())
	if started and Difficulty.key() != logged_difficulty:
		logged_difficulty = Difficulty.key()
		playtest.record("difficulty_changed", run_time, {"difficulty": logged_difficulty})
