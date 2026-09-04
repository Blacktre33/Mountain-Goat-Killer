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
	"Varkas came in the blue hour. By dawn the lambing pen was black-red, and our bells hung from his killers.",
	"Maren pushed me beneath the ice trough before his knife found her. Ten winters later, I have come back with her carbine.",
	"Cross three scars of this mountain. Take every name. Ring the mother bell. Put Varkas in the ground.",
]

## Five story beats carried through three visually distinct biomes.
const CHAPTERS := {
	"trailhead": {"title": "ACT I  //  WHITEWOOD", "line": "The pines kept the smell for ten winters: sap, cold iron, and the blood they could not bury."},
	"homestead": {"title": "WHITEWOOD  //  THE BROKEN FOLD", "line": "They sleep inside our fence. Four of our bells knock against their armour when they breathe."},
	"shrine": {"title": "ACT II  //  THE CARRION CUT", "line": "The snow thins here. Bone shows through the old red earth. Four names will wake the mother bell."},
	"ascent": {"title": "THE CARRION CUT  //  BLACK RAVINE", "line": "The bell has given the dead a voice. I carry it uphill, one shot at a time."},
	"gate": {"title": "ACT III  //  THE IRON CROWN", "line": "Varkas built a throne above our grave. I brought every stolen name to tear it down."},
}

const BIOMES := {
	"whitewood": {"title": "WHITEWOOD", "line": "FROST PINE  //  THE BROKEN FOLD"},
	"carrion_cut": {"title": "THE CARRION CUT", "line": "RED STONE  //  THE LAST SHRINE"},
	"iron_crown": {"title": "THE IRON CROWN", "line": "ASH  //  SIEGE IRON  //  VARKAS"},
}

const OBJECTIVES := {
	"trailhead": "FOLLOW THE BLOOD-TRACKS INTO WHITEWOOD",
	"homestead": "RECOVER FOUR NAMES FROM THE BROKEN FOLD",
	"shrine_locked": "FOUR NAMES MUST ANSWER BEFORE THE MOTHER BELL WILL RING",
	"shrine": "RING THE MOTHER BELL AND WAKE THE DEAD",
	"shrine_rung": "THE MOUNTAIN IS AWAKE. CLIMB THE CARRION CUT",
	"ascent": "RECOVER ALL EIGHT NAMES ON THE CARRION ROAD",
	"gate_locked": "THE IRON GATE OPENS ONLY WHEN EIGHT NAMES SPEAK",
	"gate": "ENTER THE IRON CROWN AND FACE VARKAS",
	"boss": "KILL VARKAS  //  TAKE BACK ORIN'S BELL",
	"victory": "NINE NAMES HAVE COME HOME",
}

const BELL_RUNG := "The mother bell tears the silence open. Every wolverine looks uphill. Every stolen bell answers."
const DEATH := "YOUR BLOOD STEAMS IN THE SNOW.\nPRESS R TO RETURN TO THE LAST NAME YOU RECOVERED."
const VICTORY := [
	"Varkas dies beneath the bell he stole from Orin. I leave his iron in the mud.",
	"I do not wear the nine bells as trophies. I carry them down through ash, bone, and snow.",
	"At dawn the mother bell calls them home: Asha. Rowan. Tember. Lissa. Hollin. Brae. Sorrel. Maren. Orin.",
	"The mountain remembers. This time, it speaks our names instead of his.",
]

const BOSS_PHASES := {
	1: {"title": "I  //  THE IRON HIDE", "line": "Varkas lowers his plated head. Orin's bell knocks once against his throat."},
	2: {"title": "II  //  CALL THE WARPACK", "line": "His hide splits under the iron. He howls, and the last of the pack comes running."},
	3: {"title": "III  //  RED HORN", "line": "The plates tear free. Blood darkens his muzzle. Now there is only the charge."},
}


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
	return OBJECTIVES.get(zone, OBJECTIVES.trailhead)


static func bell_name(index: int) -> String:
	return BELL_NAMES[clampi(index, 0, BELL_NAMES.size() - 1)]
