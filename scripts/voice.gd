class_name GoatVoice
extends Node
## Spoken lines: the Herdkeeper's quiet inner narration, Varkas' taunts and the
## warpack's barks. Speech was generated with Higgsfield seed_audio and
## processed by tools/audio/voice_process.py; subtitle text comes from Story.
##
##   voice.say("memory_3")               narration (queued behind the current line)
##   voice.say("varkas_alert")           a group id picks a random variant
##   voice.say("bark_contact", position) barks are positional and rate-limited
##
## `line_started` / `line_finished` drive the subtitle label and the music duck.

signal line_started(id: String, speaker: String, text: String, seconds: float, at: Vector3)
signal line_finished(id: String)

const VOICE_DIR := "res://assets/audio/voice/"
const VOICE_BUS := "Voice"
const BARK_PLAYERS := 4
const QUEUE_LIMIT := 4
const BARK_GROUP_GAP := 3.5
const BARK_ANY_GAP := 1.0
const REPEAT_GAP := 8.0
## Narration priority by id prefix; higher speaks first and lower expires sooner.
const PRIORITY := {"intro": 5, "victory": 5, "boss_phase": 4, "bell_rung": 3, "memory": 3, "chapter": 1}
const EXPIRES := {"chapter": 18.0, "memory": 40.0, "bell_rung": 30.0, "boss_phase": 45.0}

## id -> {"speaker", "text", "path"}
var lines := {}
var current_id := ""
var queue: Array = []
var last_said: Array = []

var _narrator: AudioStreamPlayer
var _varkas: AudioStreamPlayer3D
var _varkas_id := ""
var _barks: Array = []
var _bark_ids: Array = []
var _next_bark := 0
var _group_ready := {}
var _any_bark_ready := 0.0
var _pending: Array = []
var _last_variant := {}
var _said_at := {}
var _clock := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in AudioBank.VOICE:
		lines[id] = {"speaker": AudioBank.VOICE[id], "text": Story.voice_text(id), "path": VOICE_DIR + id + ".ogg"}
	_narrator = AudioStreamPlayer.new()
	_narrator.bus = VOICE_BUS
	_narrator.finished.connect(_on_narrator_finished)
	add_child(_narrator)
	_varkas = AudioStreamPlayer3D.new()
	_varkas.bus = VOICE_BUS
	_varkas.unit_size = 18.0
	_varkas.max_distance = 120.0
	_varkas.attenuation_filter_cutoff_hz = 9000.0
	_varkas.finished.connect(_on_varkas_finished)
	add_child(_varkas)
	for i in BARK_PLAYERS:
		var bark := AudioStreamPlayer3D.new()
		bark.bus = VOICE_BUS
		bark.unit_size = 8.0
		bark.max_distance = 70.0
		bark.attenuation_filter_cutoff_hz = 5500.0
		bark.finished.connect(_on_bark_finished.bind(i))
		add_child(bark)
		_barks.append(bark)
		_bark_ids.append("")


func _process(delta: float) -> void:
	_clock += delta
	for i in range(_pending.size() - 1, -1, -1):
		if _clock >= _pending[i][1]:
			var id: String = _pending[i][0]
			_pending.remove_at(i)
			say(id)
	if current_id.is_empty() and not queue.is_empty():
		_play_next()


func shutdown() -> void:
	set_process(false)
	queue.clear()
	_pending.clear()
	for player in [_narrator, _varkas] + _barks:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	current_id = ""


func has_line(id: String) -> bool:
	return lines.has(id) or Story.VOICE_GROUPS.has(id)


func line_ids() -> Array:
	return lines.keys()


## True while the Herdkeeper or Varkas is speaking (barks do not duck the mix).
func is_speaking() -> bool:
	return not current_id.is_empty() or not _varkas_id.is_empty()


## Speaks `id` (or a random variant when it names a group). Returns false when
## the line is unknown, on cooldown or dropped.
func say(id: String, at := Vector3.INF) -> bool:
	var real := _resolve(id)
	if real.is_empty():
		if OS.is_debug_build():
			push_warning("GoatVoice: unknown voice line '%s'" % id)
		return false
	match lines[real].speaker:
		"keeper":
			return _say_keeper(real)
		"varkas":
			return _say_varkas(real, at)
	return _say_bark(real, id, at)


## Speaks `id` after a delay (seconds), e.g. the ending narration after Varkas' last words.
func say_later(id: String, seconds: float) -> void:
	_pending.append([id, _clock + seconds])


## The four intro lines back to back.
func say_intro() -> void:
	for i in Story.INTRO.size():
		say("intro_%d" % i)


## Cut the narrator and clear what is waiting (death, returning to the title).
func stop_narration() -> void:
	queue.clear()
	_pending.clear()
	if not current_id.is_empty():
		_narrator.stop()
		_on_narrator_finished()


func _resolve(id: String) -> String:
	if lines.has(id):
		return id
	var group: Array = Story.VOICE_GROUPS.get(id, [])
	if group.is_empty():
		return ""
	var pick := randi() % group.size()
	if group.size() > 1 and pick == _last_variant.get(id, -1):
		pick = (pick + 1) % group.size()
	_last_variant[id] = pick
	return group[pick]


func _priority_of(id: String) -> int:
	for prefix in PRIORITY:
		if id.begins_with(prefix):
			return PRIORITY[prefix]
	return 2


func _say_keeper(id: String) -> bool:
	# The same line requested twice in a row (an explicit call plus the game
	# watcher) is spoken once.
	if _clock - _said_at.get(id, -100.0) < REPEAT_GAP:
		return false
	_said_at[id] = _clock
	if current_id.is_empty() and queue.is_empty():
		_start_keeper(id)
		return true
	if current_id == id or queue.any(func(item): return item.id == id):
		return false
	var expires := _clock + 999.0
	for prefix in EXPIRES:
		if id.begins_with(prefix):
			expires = _clock + EXPIRES[prefix]
	queue.append({"id": id, "priority": _priority_of(id), "expires": expires})
	if queue.size() > QUEUE_LIMIT:
		var lowest := 0
		for i in queue.size():
			if queue[i].priority < queue[lowest].priority:
				lowest = i
		queue.remove_at(lowest)
	return true


func _play_next() -> void:
	queue = queue.filter(func(item): return item.expires > _clock)
	if queue.is_empty():
		return
	var best := 0
	for i in queue.size():
		if queue[i].priority > queue[best].priority:
			best = i
	var item: Dictionary = queue[best]
	queue.remove_at(best)
	_start_keeper(item.id)


func _start_keeper(id: String) -> void:
	var stream := load(lines[id].path) as AudioStream
	if stream == null:
		return
	current_id = id
	_narrator.stream = stream
	_narrator.play()
	_remember(id)
	line_started.emit(id, "keeper", lines[id].text, stream.get_length(), Vector3.INF)


func _on_narrator_finished() -> void:
	var id := current_id
	current_id = ""
	if not id.is_empty():
		line_finished.emit(id)


func _say_varkas(id: String, at: Vector3) -> bool:
	var stream := load(lines[id].path) as AudioStream
	if stream == null:
		return false
	_varkas_id = id
	_varkas.stream = stream
	_varkas.volume_db = 3.0
	if at != Vector3.INF:
		_varkas.global_position = at
	_varkas.play()
	_remember(id)
	line_started.emit(id, "varkas", lines[id].text, stream.get_length(), at)
	return true


func _on_varkas_finished() -> void:
	var id := _varkas_id
	_varkas_id = ""
	if not id.is_empty():
		line_finished.emit(id)


func _say_bark(id: String, requested: String, at: Vector3) -> bool:
	var group := requested if Story.VOICE_GROUPS.has(requested) else id.rsplit("_", true, 1)[0]
	if _clock < _group_ready.get(group, 0.0) or _clock < _any_bark_ready:
		return false
	var stream := load(lines[id].path) as AudioStream
	if stream == null:
		return false
	_group_ready[group] = _clock + BARK_GROUP_GAP
	_any_bark_ready = _clock + BARK_ANY_GAP
	var slot := _next_bark
	_next_bark = (_next_bark + 1) % BARK_PLAYERS
	var bark: AudioStreamPlayer3D = _barks[slot]
	bark.stream = stream
	bark.volume_db = 0.0
	if at != Vector3.INF:
		bark.global_position = at
	bark.play()
	_bark_ids[slot] = id
	_remember(id)
	line_started.emit(id, lines[id].speaker, lines[id].text, stream.get_length(), at)
	return true


func _on_bark_finished(slot: int) -> void:
	var id: String = _bark_ids[slot]
	_bark_ids[slot] = ""
	if not id.is_empty():
		line_finished.emit(id)


func _remember(id: String) -> void:
	last_said.append(id)
	if last_said.size() > 12:
		last_said.pop_front()
