class_name GoatWatch
extends RefCounted
## Lets the sound layer follow the campaign without edits scattered through
## main.gd. GoatAudio calls `drive` four times a second with the game scene; it
## reads main's public state (duck-typed with `get`, so a renamed field only
## silences one cue) and turns it into music states, narration, Varkas' taunts,
## pack barks and the low-health heartbeat. Explicit calls elsewhere
## (`audio.say(...)`, `audio.set_music_state(...)`) work alongside it; repeats
## are ignored by the voice layer.

const COMBAT_HOLD := 7.0
const SUSPICIOUS_HOLD := 3.0
const BARK_RANGE := 50.0
const LOW_HEALTH := 35
const CHAPTER_IDS := ["trailhead", "homestead", "shrine", "ascent", "gate"]

var started := false
var dead := false
var victory := false
var bell_rung := false
var boss_awake := false
var boss_phase := 0
var bells := 0
var zone := ""
var narrated := {}

var _enemy_state := {}
var _enemy_dead := {}
var _combat_until := 0.0
var _suspicious_until := 0.0
var _last_contact := -10.0
var _boss_health_mark := 1.0
var _next_taunt := 0.0


func drive(audio: GoatAudio, main: Node) -> void:
	if main == null or main == audio or not is_instance_valid(audio.voice):
		return
	var player := main.get("player") as GoatPlayer
	if player == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	var biome := str(main.get("current_biome"))
	audio.set_biome(biome if not biome.is_empty() else "whitewood")
	if main.get("started") != true:
		started = false
		audio.set_music_state("title")
		return
	if not started:
		started = true
		audio.voice.say_intro()
	var boss := main.get("boss") as WolverineEnemy
	victory = _watch_victory(audio, main, boss)
	dead = _watch_death(audio, main, player, boss)
	_watch_story(audio, main)
	_watch_boss(audio, main, boss, now)
	var state := _pack_state(audio, main, player, now)
	if victory:
		state = "victory"
	elif dead:
		state = "death"
	elif boss_awake:
		state = "boss%d" % clampi(maxi(boss_phase, 1), 1, 3)
	audio.set_music_state(state)
	_watch_heartbeat(audio, player, now)


func _watch_victory(audio: GoatAudio, main: Node, boss: WolverineEnemy) -> bool:
	var now_victory: bool = main.get("victory") == true
	if now_victory and not victory:
		audio.voice.stop_narration()
		audio.say("varkas_final", _chest(boss))
		for i in Story.VICTORY.size():
			audio.voice.say_later("victory_%d" % i, 6.5)
	return now_victory


func _watch_death(audio: GoatAudio, main: Node, player: GoatPlayer, boss: WolverineEnemy) -> bool:
	var now_dead := player.health <= 0 and not victory
	if now_dead and not dead:
		audio.voice.stop_narration()
		if main.get("boss_awake") == true and boss != null:
			audio.say("varkas_kill", _chest(boss))
	return now_dead


func _watch_story(audio: GoatAudio, main: Node) -> void:
	var next_zone := str(main.get("zone"))
	if next_zone != zone:
		zone = next_zone
		var key := "shrine" if zone == "shrine_rung" else zone
		if CHAPTER_IDS.has(key) and not narrated.has(key):
			narrated[key] = true
			audio.say("chapter_" + key)
	var rung: bool = main.get("bell_rung") == true
	if rung and not bell_rung:
		audio.say("bell_rung")
	bell_rung = rung
	var count := int(main.get("bells")) if main.get("bells") != null else 0
	if count > bells:
		_narrate_memory(audio, main)
	bells = count


## The recovered bell's name heads the chapter title ("ROWAN  //  A NAME RETURNED").
func _narrate_memory(audio: GoatAudio, main: Node) -> void:
	var title := main.get("chapter_title") as Label
	if title == null:
		return
	for i in Story.BELL_NAMES.size():
		if title.text.begins_with(Story.BELL_NAMES[i]):
			audio.say("memory_%d" % i)
			return


func _watch_boss(audio: GoatAudio, main: Node, boss: WolverineEnemy, now: float) -> void:
	var awake: bool = main.get("boss_awake") == true
	if boss == null:
		boss_awake = false
		return
	if awake and not boss_awake:
		boss_phase = 0
		_boss_health_mark = 1.0
		_next_taunt = now + 20.0
		audio.say("varkas_alert", _chest(boss))
	boss_awake = awake
	if not awake or boss.dead:
		return
	if boss.boss_phase > boss_phase:
		boss_phase = boss.boss_phase
		_boss_health_mark = 1.0
		if boss_phase <= 3:
			audio.say("varkas_phase_%d" % boss_phase, _chest(boss))
			audio.voice.say_later("boss_phase_%d" % boss_phase, 4.6)
	var fraction := float(boss.health) / maxf(1.0, float(boss.max_health))
	if now > _next_taunt and _boss_health_mark - fraction >= 0.2:
		_boss_health_mark = fraction
		_next_taunt = now + 25.0
		audio.say("varkas_hurt", _chest(boss))


func _pack_state(audio: GoatAudio, main: Node, player: GoatPlayer, now: float) -> String:
	var enemies := main.get("enemies") as Array
	var seen := {}
	var alerted := 0
	var uneasy := 0
	if enemies != null:
		for entry in enemies:
			var enemy := entry as WolverineEnemy
			if enemy == null or enemy.boss:
				continue
			var id := enemy.get_instance_id()
			seen[id] = true
			var before: int = _enemy_state.get(id, WolverineEnemy.State.PATROL)
			var at := _chest(enemy)
			var near := player.global_position.distance_to(at) < BARK_RANGE
			if enemy.dead:
				if not _enemy_dead.get(id, false) and near:
					_bark_body(audio, enemies, enemy)
				_enemy_dead[id] = true
				continue
			if enemy.state == WolverineEnemy.State.ALERT:
				alerted += 1
				if before != WolverineEnemy.State.ALERT and near:
					audio.say("bark_flank" if now - _last_contact < 1.5 else "bark_contact", at)
					_last_contact = now
			elif enemy.state == WolverineEnemy.State.SUSPICIOUS or enemy.state == WolverineEnemy.State.SEARCH:
				uneasy += 1
				if before == WolverineEnemy.State.ALERT and enemy.state == WolverineEnemy.State.SEARCH and near:
					audio.say("bark_lost", at)
			_enemy_state[id] = enemy.state
	for id in _enemy_state.keys():
		if not seen.has(id):
			_enemy_state.erase(id)
			_enemy_dead.erase(id)
	if alerted > 0:
		_combat_until = now + COMBAT_HOLD
	elif uneasy > 0:
		_suspicious_until = now + SUSPICIOUS_HOLD
	if now < _combat_until:
		return "combat"
	if now < _suspicious_until:
		return "suspicious"
	return "stealth"


## A packmate that finds a body calls it out.
func _bark_body(audio: GoatAudio, enemies: Array, corpse: WolverineEnemy) -> void:
	for entry in enemies:
		var other := entry as WolverineEnemy
		if other == null or other == corpse or other.dead or other.boss:
			continue
		if other.global_position.distance_to(corpse.global_position) < 22.0 and other.state != WolverineEnemy.State.ALERT:
			audio.say("bark_body", _chest(other))
			return


func _watch_heartbeat(audio: GoatAudio, player: GoatPlayer, now: float) -> void:
	if dead or victory or audio.get_tree().paused:
		return
	if player.health <= 0 or player.health >= LOW_HEALTH:
		return
	var weak := float(player.health) / LOW_HEALTH
	var interval := lerpf(0.55, 0.95, weak)
	if now - audio.last_played_msec("heartbeat") * 0.001 > interval * 1.6:
		audio.play("heartbeat", -3.0 + 4.0 * (1.0 - weak))


static func _chest(enemy: WolverineEnemy) -> Vector3:
	return enemy.global_position + Vector3(0.0, 0.9, 0.0) if enemy != null else Vector3.INF
