class_name Story
extends RefCounted
## THE LAST BELL.
##
## Nine named neck-bells belonged to the Ironhorn herd. A tenth, the great
## mother bell, called the whole valley home. Varkas butchered the herd, gave
## eight bells to his warpack, and kept Orin's bell at his own throat. The
## mother bell survived at the shrine. So did one kid: the Herdkeeper.

const TITLE := "MOUNTAIN GOAT KILLER"
const SUBTITLE := "THE LAST BELL"

## Names cast into the nine stolen neck-bells, recovered one kill at a time.
## The great mother bell at the shrine is a separate, tenth bell.
const BELL_NAMES := ["ASHA", "ROWAN", "TEMBER", "LISSA", "HOLLIN", "BRAE", "SORREL", "MAREN", "ORIN"]
const MOTHER_BELL_REQUIRED := 4
const IRON_GATE_REQUIRED := 8

const INTRO := [
	"Nine neck-bells. Nine names. One great bell to call the herd home.",
	"Varkas came in the blue hour. By dawn the birthing pen was black-red, and our bells hung from his killers.",
	"Maren pushed me beneath the ice trough before his knife found her. Ten winters later, I have come back with her carbine.",
	"Cross three scars of this mountain. Take every name. Ring the mother bell. Put Varkas in the ground.",
]

## Five story beats carried through three visually distinct biomes.
const CHAPTERS := {
	"trailhead": {"title": "ACT I  //  WIDOWPINE", "line": "The pines kept the smell for ten winters: sap, cold iron, and the blood they could not bury."},
	"homestead": {"title": "WIDOWPINE  //  THE BROKEN FOLD", "line": "They sleep inside our fence. Four of our bells knock against their armour when they breathe."},
	"shrine": {"title": "ACT II  //  THE CARRION CUT", "line": "The snow thins here. Bone shows through the old red earth. Four names will wake the mother bell."},
	"ascent": {"title": "THE CARRION CUT  //  BLACK RAVINE", "line": "The bell has given the dead a voice. I carry it uphill, one shot at a time."},
	"gate": {"title": "ACT III  //  THE IRON CROWN", "line": "Eight names open the abbey our herd built. The ninth still knocks against Varkas' throat. Orin. My little brother."},
}

const BIOMES := {
	# Keep the original machine-facing key so save, test, and progression seams stay stable.
	"whitewood": {"title": "WIDOWPINE", "line": "FROST PINE  //  THE BROKEN FOLD"},
	"carrion_cut": {"title": "THE CARRION CUT", "line": "RED STONE  //  THE LAST SHRINE"},
	"iron_crown": {"title": "THE IRON CROWN", "line": "ASH  //  SIEGE IRON  //  VARKAS"},
}

const OBJECTIVES := {
	"trailhead": "FOLLOW THE BLOOD-TRACKS INTO WIDOWPINE",
	"homestead": "RECOVER FOUR NAMES FROM THE BROKEN FOLD",
	"shrine_locked": "FOUR NAMES MUST ANSWER BEFORE THE MOTHER BELL WILL RING",
	"shrine": "RING THE MOTHER BELL AND WAKE THE DEAD",
	"shrine_rung": "THE MOUNTAIN IS AWAKE. CLIMB THE CARRION CUT",
	"ascent": "RECOVER ALL EIGHT NAMES ON THE CARRION ROAD",
	"ascent_ready": "CLIMB TO THE IRON CROWN  //  EIGHT NAMES WILL OPEN THE GATE",
	"gate_locked": "THE IRON GATE OPENS ONLY WHEN EIGHT NAMES SPEAK",
	"gate": "ENTER THE IRON CROWN AND FACE VARKAS",
	"boss": "KILL VARKAS  //  TAKE BACK ORIN'S BELL",
	"victory": "NINE NAMES HAVE COME HOME",
}

const BELL_RUNG := "The mother bell tears the silence open. Every wolverine looks uphill. Every stolen bell answers."
const DEATH := "YOUR BLOOD STEAMS IN THE SNOW.\nPRESS R TO RETURN TO YOUR LAST REFUGE."

## Each recovered bell carries a person, not just one ninth of a counter.
## These memories are short enough to read while crossing the emptied camp.
const BELL_MEMORIES := [
	"Asha taught me to step where the needles were thick. Her killer wore her bell to warn the others when he fed.",
	"Rowan mended every broken strap in the fold. I have to cut his bell free. The leather has grown into the rust.",
	"Tember built the ice trough. He made it deep enough for a winter's water. Deep enough to hide one child.",
	"Lissa could name a missing goat by the silence in the herd. Four bells answer now. The mother bell will hear us.",
	"Hollin hauled the abbey's first stones. His bell is dented flat on one side. I turn that side into my palm.",
	"Brae stitched Maren's wounds after the rockfall. There was nobody left to stitch hers. I wipe the bell on my coat.",
	"Sorrel kept seed beneath the hearth through every lean winter. The hearth is cold. I keep the bell warm in my hand.",
	"Maren put her hand over my mouth beneath the trough. Stay quiet, she said. I carried her carbine here. I carry her name out.",
	"Orin was small enough to sleep against my ribs. Varkas wore his bell through ten winters. He will not wear it through another dawn.",
]
const VICTORY := [
	"Varkas dies beneath the bell he stole from Orin. I leave his iron in the mud.",
	"I do not wear the nine bells as trophies. I carry them down through ash, bone, and snow.",
	"At dawn the mother bell calls them home: Asha. Rowan. Tember. Lissa. Hollin. Brae. Sorrel. Maren. Orin.",
	"The mountain remembers. This time, it speaks our names instead of his.",
]

const BOSS_PHASES := {
	1: {"title": "I  //  THE IRON HIDE", "line": "Varkas lowers his plated head. Orin's bell knocks once against his throat."},
	2: {"title": "II  //  CALL THE WARPACK", "line": "His hide splits under the iron. Four memorial lamps spit red; he howls, and the last of the pack comes running."},
	3: {"title": "III  //  RED HORN", "line": "The plates tear free. Eight names burn around him. He lowers the red horn; I remember Maren's hand. Be still. Let him commit. Then move."},
}


## Spoken-only lines: Varkas' taunts and the warpack's short barks. Everything
## else the game speaks is the story text above, read aloud by the Herdkeeper.
## Voice file ids match assets/audio/voice/<id>.ogg.
const VARKAS_LINES := {
	"varkas_alert_0": "Another goat, climbing my mountain.",
	"varkas_alert_1": "The bells told me you were coming.",
	"varkas_phase_1": "I wear their names. Take one, if you can.",
	"varkas_phase_2": "Pack! Tear it down!",
	"varkas_phase_3": "Come, then. Meet the horn.",
	"varkas_hurt": "Is that all the herd left?",
	"varkas_kill_0": "The mountain keeps the goat.",
	"varkas_kill_1": "Down you go, with the rest.",
	"varkas_final": "Ring it, then. I hear them anyway.",
}
const PACK_BARKS := {
	"bark_contact_a": "Contact! Contact!",
	"bark_contact_b": "There he is!",
	"bark_lost_a": "Lost him.",
	"bark_lost_b": "Where did he go?",
	"bark_flank_a": "Flank him!",
	"bark_flank_b": "Go around!",
	"bark_body_a": "Body! Someone's here!",
	"bark_body_b": "Someone killed him. Find them.",
}
## Group name -> variant ids. `voice.say("bark_contact")` picks one at random.
const VOICE_GROUPS := {
	"varkas_alert": ["varkas_alert_0", "varkas_alert_1"],
	"varkas_kill": ["varkas_kill_0", "varkas_kill_1"],
	"bark_contact": ["bark_contact_a", "bark_contact_b"],
	"bark_lost": ["bark_lost_a", "bark_lost_b"],
	"bark_flank": ["bark_flank_a", "bark_flank_b"],
	"bark_body": ["bark_body_a", "bark_body_b"],
}


## Subtitle text for a voice line id ("" when the id is unknown). Narration ids
## point at the story constants above so text and speech cannot drift apart.
static func voice_text(id: String) -> String:
	if VARKAS_LINES.has(id):
		return VARKAS_LINES[id]
	if PACK_BARKS.has(id):
		return PACK_BARKS[id]
	var parts := id.rsplit("_", true, 1)
	if id.begins_with("intro_"):
		return INTRO[clampi(int(parts[1]), 0, INTRO.size() - 1)]
	if id.begins_with("memory_"):
		return bell_memory(int(parts[1]))
	if id.begins_with("victory_"):
		return VICTORY[clampi(int(parts[1]), 0, VICTORY.size() - 1)]
	if id.begins_with("boss_phase_"):
		return BOSS_PHASES.get(int(parts[1]), {}).get("line", "")
	if id.begins_with("chapter_"):
		return CHAPTERS.get(id.trim_prefix("chapter_"), {}).get("line", "")
	if id == "bell_rung":
		return BELL_RUNG
	return ""


## The zone the player is standing in, from south-to-north z ranges.
static func zone_for_z(z: float, bell_rung: bool) -> String:
	if z > 12.0:
		return "trailhead"
	if z > -16.0:
		return "homestead"
	if z > -40.0:
		return "shrine_rung" if bell_rung else "shrine"
	if z > -76.0:
		return "ascent"
	return "gate"


static func chapter_for_zone(zone: String) -> Dictionary:
	var key := "shrine" if zone == "shrine_rung" else zone
	return CHAPTERS.get(key, {})


static func biome_for_zone(zone: String) -> String:
	if zone in ["trailhead", "homestead"]:
		return "whitewood"
	if zone in ["shrine", "shrine_rung", "ascent"]:
		return "carrion_cut"
	return "iron_crown"


static func biome_for_z(z: float) -> String:
	if z > -16.0:
		return "whitewood"
	if z > -76.0:
		return "carrion_cut"
	return "iron_crown"


static func can_ring_mother_bell(recovered_bells: int) -> bool:
	return recovered_bells >= MOTHER_BELL_REQUIRED


static func can_open_iron_gate(recovered_bells: int, mother_bell_rung: bool) -> bool:
	return mother_bell_rung and recovered_bells >= IRON_GATE_REQUIRED


static func objective_for(zone: String, boss_awake: bool, victory: bool, recovered_bells := 0, mother_bell_rung := false) -> String:
	if victory:
		return OBJECTIVES.victory
	if boss_awake:
		return OBJECTIVES.boss
	if zone == "shrine" and not can_ring_mother_bell(recovered_bells):
		return OBJECTIVES.shrine_locked
	if zone == "gate" and not can_open_iron_gate(recovered_bells, mother_bell_rung):
		return OBJECTIVES.gate_locked
	if zone in ["shrine_rung", "ascent", "gate"] and mother_bell_rung and recovered_bells < IRON_GATE_REQUIRED:
		return OBJECTIVES.gate_locked if zone == "gate" else OBJECTIVES.ascent
	if zone == "ascent" and can_open_iron_gate(recovered_bells, mother_bell_rung):
		return OBJECTIVES.ascent_ready
	return OBJECTIVES.get(zone, OBJECTIVES.trailhead)


static func bell_name(index: int) -> String:
	return BELL_NAMES[clampi(index, 0, BELL_NAMES.size() - 1)]


static func bell_memory(index: int) -> String:
	return BELL_MEMORIES[clampi(index, 0, BELL_MEMORIES.size() - 1)]
