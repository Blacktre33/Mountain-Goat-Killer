class_name PlaytestLog
extends RefCounted
## Local-only playtest telemetry. Each play session appends JSON lines to
## `user://playtests/session-<timestamp>.jsonl`: zone entries, detections,
## deaths and their causes, bells, boss phases and retries, and the ending.
## Nothing is uploaded. Testers send the folder back by hand, and
## `tools/summarize_playtests.py` turns many sessions into one report.
##
## Times are seconds of unpaused play since the session began.

const DIR := "user://playtests"
const FORMAT := 1

var events: Array = []
var path := ""
var file: FileAccess
var enabled := false


## Start recording. `to_disk` is false for tests and when the tester opts out;
## events are then kept in memory only.
func open(to_disk: bool, meta: Dictionary = {}) -> void:
	events.clear()
	enabled = true
	if to_disk:
		DirAccess.make_dir_recursive_absolute(DIR)
		var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
		path = "%s/session-%s.jsonl" % [DIR, stamp]
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_warning("Playtest log unavailable: " + error_string(FileAccess.get_open_error()))
	var start := meta.duplicate()
	start["format"] = FORMAT
	start["engine"] = Engine.get_version_info().string
	start["os"] = OS.get_name()
	start["started_at"] = Time.get_datetime_string_from_system(true)
	record("session_start", 0.0, start)


func record(kind: String, t: float, data: Dictionary = {}) -> void:
	if not enabled:
		return
	var entry := data.duplicate()
	entry["event"] = kind
	entry["t"] = snappedf(t, 0.01)
	events.append(entry)
	if file != null:
		file.store_line(JSON.stringify(entry))
		file.flush()


func close(t: float, reason: String, data: Dictionary = {}) -> void:
	if not enabled:
		return
	var summary := data.duplicate()
	summary["reason"] = reason
	record("session_end", t, summary)
	enabled = false
	if file != null:
		file.close()
		file = null


func count(kind: String) -> int:
	var total := 0
	for entry in events:
		if entry.event == kind:
			total += 1
	return total


func last(kind: String) -> Dictionary:
	for index in range(events.size() - 1, -1, -1):
		if events[index].event == kind:
			return events[index]
	return {}


static func folder() -> String:
	return ProjectSettings.globalize_path(DIR)
