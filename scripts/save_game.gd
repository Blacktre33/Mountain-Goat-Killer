class_name SaveGame
extends RefCounted
## Campaign progress, saved to `user://campaign.save` as JSON.
##
## A save mirrors what an in-session death already keeps: the last refuge,
## recovered bells, the mother bell, which of the warpack are dead, their
## uncollected drops, kindled cairns, and reserve ammunition. Continuing
## resumes at that refuge exactly as a respawn would. Varkas's fight is never saved mid-way;
## it restarts from Iron Hide, as a failed attempt already does.

const PATH := "user://campaign.save"
const VERSION := 1
const ZONES := ["trailhead", "homestead", "shrine", "shrine_rung", "ascent", "gate"]
const ZONE_TITLES := {
	"trailhead": "WIDOWPINE",
	"homestead": "THE BROKEN FOLD",
	"shrine": "THE CARRION CUT",
	"shrine_rung": "THE CARRION CUT",
	"ascent": "THE BLACK RAVINE",
	"gate": "THE IRON CROWN",
}


## Validate and normalise loaded data. Returns {} when it cannot be trusted.
static func sanitize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	if int(data.get("version", -1)) != VERSION:
		return {}
	var zone: Variant = data.get("zone", "")
	if not (zone is String) or not zone in ZONES:
		return {}
	var bells := clampi(int(data.get("bells", 0)), 0, Story.IRON_GATE_REQUIRED)
	var bell_rung: bool = data.get("bell_rung", false) == true
	if bell_rung and bells < Story.MOTHER_BELL_REQUIRED:
		return {}
	var dead: Array[int] = []
	for id in data.get("dead", []):
		if (id is int or id is float) and int(id) >= 0 and not int(id) in dead:
			dead.append(int(id))
	var drops: Array = []
	for drop in data.get("drops", []):
		if drop is Dictionary and drop.has_all(["x", "y", "z", "bell"]):
			drops.append({
				"x": float(drop.x), "y": float(drop.y), "z": float(drop.z),
				"bell": clampi(int(drop.bell), -1, Story.BELL_NAMES.size() - 1),
			})
	var cairns: Array[int] = []
	for index in data.get("cairns", []):
		if (index is int or index is float) and int(index) >= 0 and int(index) < WorldBuilder.CAIRNS.size() and not int(index) in cairns:
			cairns.append(int(index))
	var seen: Array[String] = []
	for key in data.get("seen", []):
		if key is String and not key in seen:
			seen.append(key)
	return {
		"version": VERSION,
		"zone": "shrine_rung" if bell_rung and zone == "shrine" else zone,
		"bells": bells,
		"bell_rung": bell_rung,
		"dead": dead,
		"drops": drops,
		"reserve": clampi(int(data.get("reserve", 96)), 0, GoatPlayer.RESERVE_CAP),
		"seen": seen,
		"cairns": cairns,
		"playtime": maxf(0.0, float(data.get("playtime", 0.0))),
		"deaths": maxi(0, int(data.get("deaths", 0))),
	}


## One line for the title screen's continue button.
static func summary(data: Dictionary) -> String:
	if data.is_empty():
		return ""
	return "%s  //  %d / %d BELLS" % [ZONE_TITLES.get(data.zone, "THE CLIMB"), data.bells, Story.BELL_NAMES.size()]


static func write_to(path: String, data: Dictionary) -> Error:
	var clean := sanitize(data)
	if clean.is_empty():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(clean, "\t"))
	file.close()
	return OK


static func read_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	# A corrupt or hand-edited save simply offers no Continue.
	return sanitize(json.data) if error == OK else {}


static func erase_at(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The real save slot. Test and tool scripts never touch it.
static func store(data: Dictionary) -> void:
	if GameSettings.persistent():
		write_to(PATH, data)


static func load_slot() -> Dictionary:
	return read_from(PATH) if GameSettings.persistent() else {}


static func clear() -> void:
	if GameSettings.persistent():
		erase_at(PATH)
