class_name Difficulty
extends RefCounted
## Difficulty presets. HUNTER is the original tuning the campaign was balanced
## and verified against; every multiplier there is exactly 1.0.
##
## - `detection`: how fast a wolverine's awareness meter fills.
## - `damage_taken`: scales every hit on the Herdkeeper.
## - `accuracy`: scales rifleman hit chance.
## - `telegraph`: scales Varkas's warning windows before each attack lands.
## - `regen_cap`: the second-wind ceiling health recovers to.

const ORDER := ["story", "hunter", "varkas"]
const PRESETS := {
	"story": {
		"title": "STORY",
		"line": "Slower eyes, lighter wounds, longer warnings. For the names, not the fight.",
		"detection": 0.65,
		"damage_taken": 0.55,
		"accuracy": 0.7,
		"telegraph": 1.35,
		"regen_cap": 75,
	},
	"hunter": {
		"title": "HUNTER",
		"line": "The climb as it was built. Every mistake costs blood.",
		"detection": 1.0,
		"damage_taken": 1.0,
		"accuracy": 1.0,
		"telegraph": 1.0,
		"regen_cap": 55,
	},
	"varkas": {
		"title": "VARKAS",
		"line": "Sharper senses, deeper bites, shorter tells. The mountain does not forgive.",
		"detection": 1.3,
		"damage_taken": 1.35,
		"accuracy": 1.15,
		"telegraph": 0.85,
		"regen_cap": 40,
	},
}
## The accessibility option stretches boss warnings on top of any preset.
const LONG_TELEGRAPH_MULTIPLIER := 1.6


static func key() -> String:
	var value: String = GameSettings.get_value("difficulty")
	return value if PRESETS.has(value) else "hunter"


static func preset(name := "") -> Dictionary:
	return PRESETS.get(name if not name.is_empty() else key(), PRESETS.hunter)


static func title(name := "") -> String:
	return preset(name).title


static func detection_multiplier() -> float:
	return preset().detection


static func accuracy_multiplier() -> float:
	return preset().accuracy


static func regen_cap() -> int:
	return preset().regen_cap


static func telegraph_multiplier() -> float:
	var multiplier: float = preset().telegraph
	if GameSettings.get_value("long_telegraphs"):
		multiplier *= LONG_TELEGRAPH_MULTIPLIER
	return multiplier


## Damage after the preset; never rounds a real hit down to nothing.
static func scale_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	return maxi(1, roundi(amount * float(preset().damage_taken)))


static func next(name: String, step := 1) -> String:
	var index := ORDER.find(name)
	if index < 0:
		index = 1
	return ORDER[posmod(index + step, ORDER.size())]
