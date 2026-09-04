class_name Stealth
extends RefCounted
## Perception math for the warpack. Wolverines hunt with three senses:
## sight (needs line of sight, a view cone, and light on the goat), hearing
## (noise radii from movement, gunfire, and decoys), and scent, which the wind
## carries downwind. Everything here is pure so it can be tested headless.

## Awareness thresholds on the 0..1 detection meter.
const SUSPICIOUS := 0.35
const ALERT := 1.0
const DECAY_PER_SECOND := 0.22

## Base sight range in the dark, in metres. Lantern light stretches it.
const SIGHT_RANGE := 19.0
const SIGHT_FOV_COS := 0.34  # about 140 degrees of total view cone
const SIGHT_RATE := 0.9
const CROUCH_SIGHT_MULTIPLIER := 0.55
const LIGHT_SIGHT_MULTIPLIER := 1.7

## Noise radii in metres for what the goat does.
const NOISE := {
	"still": 0.0,
	"crouch": 3.5,
	"walk": 9.0,
	"sprint": 18.0,
	"land": 7.0,
	"shot": 60.0,
	"volley": 48.0,
	"hang": 0.0,
	"decoy": 15.0,
	"snuff": 2.5,
	"takedown": 4.0,
}

## Scent carries up to this far when the wind blows straight from goat to wolverine.
const SCENT_RANGE := 24.0
const SCENT_RATE := 0.35

## Wind drifts slowly around the compass so the safe side of a camp changes.
const WIND_PERIOD_SECONDS := 150.0


static func noise_radius(action: String) -> float:
	return NOISE.get(action, 0.0)


## Movement noise from what the goat is doing this frame.
static func movement_noise(moving: bool, sprinting: bool, crouched: bool) -> float:
	if not moving:
		return NOISE.still
	if sprinting:
		return NOISE.sprint
	if crouched:
		return NOISE.crouch
	return NOISE.walk


## Unit wind direction (where the air is blowing toward) at a given time.
static func wind_at(seconds: float) -> Vector3:
	var angle := 0.7 + seconds * TAU / WIND_PERIOD_SECONDS + sin(seconds * 0.11) * 0.6
	return Vector3(cos(angle), 0.0, sin(angle))


## How strongly a wolverine at `sniffer` smells a goat at `goat`, 0..1. Scent
## only travels with the wind: the wolverine must be downwind of the goat.
static func scent_strength(goat: Vector3, sniffer: Vector3, wind: Vector3) -> float:
	var carried := sniffer - goat
	carried.y = 0.0
	var distance := carried.length()
	if distance < 0.001 or distance > SCENT_RANGE:
		return 0.0
	var downwind := carried.normalized().dot(Vector3(wind.x, 0.0, wind.z).normalized())
	if downwind <= 0.2:
		return 0.0
	var reach := 1.0 - distance / SCENT_RANGE
	return clampf(((downwind - 0.2) / 0.8) * reach, 0.0, 1.0)


## True when the goat is upwind of the wolverine, i.e. its scent is carried away from it.
static func is_upwind(goat: Vector3, sniffer: Vector3, wind: Vector3) -> bool:
	return scent_strength(goat, sniffer, wind) <= 0.0


## Detection rate per second from sight. `light` is the goat's lantern
## exposure 0..1, `facing` the wolverine's forward vector, `to_goat` the
## vector from its eyes to the goat.
static func sight_rate(facing: Vector3, to_goat: Vector3, has_line_of_sight: bool, crouched: bool, light: float) -> float:
	if not has_line_of_sight:
		return 0.0
	var distance := to_goat.length()
	if distance < 0.001:
		return SIGHT_RATE * 4.0
	var range := SIGHT_RANGE * (1.0 + light * (LIGHT_SIGHT_MULTIPLIER - 1.0))
	if distance > range:
		return 0.0
	var flat_facing := Vector3(facing.x, 0.0, facing.z).normalized()
	var flat_to_goat := Vector3(to_goat.x, 0.0, to_goat.z).normalized()
	var alignment := flat_facing.dot(flat_to_goat)
	# Anything closer than arm's reach is noticed regardless of the cone.
	if alignment < SIGHT_FOV_COS and distance > 2.2:
		return 0.0
	var closeness := 1.0 - distance / range
	var rate := SIGHT_RATE * (0.35 + closeness * 1.4)
	if crouched:
		rate *= CROUCH_SIGHT_MULTIPLIER
	return rate


## Hearing: a noise of `radius` metres at `source` is heard at `listener` when inside it.
static func hears(source: Vector3, listener: Vector3, radius: float) -> bool:
	return radius > 0.0 and source.distance_to(listener) <= radius


## Advances a detection meter: rises with the summed sense rates, decays when nothing is sensed.
static func step_detection(current: float, rate: float, delta: float) -> float:
	if rate > 0.0:
		return minf(ALERT, current + rate * delta)
	return maxf(0.0, current - DECAY_PER_SECOND * delta)


static func awareness_of(detection: float) -> String:
	if detection >= ALERT:
		return "alert"
	if detection >= SUSPICIOUS:
		return "suspicious"
	return "unaware"


## A stealth takedown needs the goat behind an enemy that has not gone alert.
static func can_takedown(enemy_facing: Vector3, enemy_to_goat: Vector3, detection: float) -> bool:
	if detection >= ALERT:
		return false
	var flat_distance := Vector2(enemy_to_goat.x, enemy_to_goat.z).length()
	if flat_distance > 2.3:
		return false
	var facing := Vector3(enemy_facing.x, 0.0, enemy_facing.z).normalized()
	var toward := Vector3(enemy_to_goat.x, 0.0, enemy_to_goat.z).normalized()
	return facing.dot(toward) < -0.15


## Damage multiplier for a carbine round into an enemy that never saw it coming.
static func ambush_multiplier(detection: float) -> float:
	return 1.6 if detection < SUSPICIOUS else 1.0
