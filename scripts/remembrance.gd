class_name Remembrance
extends RefCounted
## REMEMBRANCE: "the mountain remembers every shot".
##
## The player spends a live round to hang it in the air exactly where they
## stand and aim. Hung rounds stay behind as the player moves on, so several
## can be laid out across the ravine from different vantage points. The
## Herdkeeper starts able to hang three; each of Maren's cairns adds one, up to
## six. Holding the
## key releases every hung round at once, each firing from the spot it was left
## in: a crossfire assembled by one goat.
##
## Everything here is pure so it can be tested headless without a scene.

## The most rounds that can ever hang at once, and how many the climb starts with.
const CAPACITY := 6
const BASE_CAPACITY := 3
const RELEASE_HOLD_SECONDS := 0.38
const BEAM_LENGTH := 42.0
## Cosine of the cone (about 16 degrees) inside which a released round is guided.
const GUIDE_CONE_COS := 0.9611  # cos(0.28)
## Guidance also needs the target within this many metres of the aim line, so a
## round is nudged onto a nearby enemy but never snaps onto a distant one.
const GUIDE_RADIUS := 2.4
const LIFETIME_SECONDS := 40.0
## How close (metres) an enemy must pass to a beam for the round to sense it.
const SENSE_RADIUS := 1.35
const BODY_DAMAGE := 64
const BOSS_DAMAGE := 34
const CONVERGENCE_MULTIPLIER := 1.5
const CONVERGENCE_STAGGER := 1.2


class HungRound:
	var origin: Vector3
	var direction: Vector3
	var age := 0.0
	var reach := BEAM_LENGTH
	var sense := 0.0
	var sense_cooldown := 0.0
	var node: Node3D

	func _init(at: Vector3, aim: Vector3, beam_reach := BEAM_LENGTH) -> void:
		origin = at
		direction = aim.normalized()
		reach = beam_reach


static func can_hang(hung: int, ammo: int, reloading: bool, sprinting: bool, capacity := CAPACITY) -> bool:
	return hung < mini(capacity, CAPACITY) and ammo > 0 and not reloading and not sprinting


## How many rounds can hang once `cairns` of Maren's cairns are kindled.
static func capacity_for(cairns: int) -> int:
	return clampi(BASE_CAPACITY + cairns, BASE_CAPACITY, CAPACITY)


## Distance from a point to the finite beam a hung round projects ahead of itself.
static func beam_distance(round: HungRound, point: Vector3) -> float:
	var along := clampf((point - round.origin).dot(round.direction), 0.0, BEAM_LENGTH)
	return point.distance_to(round.origin + round.direction * along)


## Picks the target a released round is guided onto: the one best aligned with
## the aim line that sits inside the guide cone, within the lateral guide
## radius, and within beam reach. Targets are dictionaries with `id`,
## `position` and `boss`. Returns an empty dictionary when nothing qualifies.
static func guide(round: HungRound, targets: Array) -> Dictionary:
	var best := {}
	var best_alignment := -2.0
	for target in targets:
		var offset: Vector3 = target.position - round.origin
		var distance := offset.length()
		if distance == 0.0 or distance > BEAM_LENGTH:
			continue
		var direction := offset / distance
		var alignment := direction.dot(round.direction)
		if alignment < GUIDE_CONE_COS:
			continue
		var lateral := sqrt(maxf(0.0, 1.0 - alignment * alignment)) * distance
		if lateral > GUIDE_RADIUS:
			continue
		if alignment > best_alignment:
			best_alignment = alignment
			best = {"target": target, "direction": direction, "distance": distance}
	return best


## Resolves a whole volley into shot dictionaries: `round` (index), `target`
## (id or -1), `direction`, `distance`, `damage`, `converged`. `is_blocked`
## receives (round, direction, distance) and lets the caller veto a shot whose
## path is interrupted by cover; blocked shots still fly for the tracer but
## deal nothing and do not count toward convergence.
static func plan_volley(rounds: Array, targets: Array, is_blocked := Callable()) -> Array:
	var shots: Array = []
	var hits_per_target := {}
	for index in rounds.size():
		var round: HungRound = rounds[index]
		var guided := guide(round, targets)
		var shot := {
			"round": index,
			"target": -1,
			"direction": round.direction,
			"distance": BEAM_LENGTH,
			"damage": 0,
			"converged": false,
		}
		if not guided.is_empty():
			var blocked: bool = is_blocked.is_valid() and is_blocked.call(round, guided.direction, guided.distance)
			shot.direction = guided.direction
			shot.distance = guided.distance
			if not blocked:
				shot.target = guided.target.id
				shot.damage = BOSS_DAMAGE if guided.target.boss else BODY_DAMAGE
				hits_per_target[shot.target] = hits_per_target.get(shot.target, 0) + 1
		shots.append(shot)
	for shot in shots:
		if shot.target != -1 and hits_per_target.get(shot.target, 0) >= 2:
			shot.converged = true
			shot.damage = roundi(shot.damage * CONVERGENCE_MULTIPLIER)
	return shots


## Ages every hung round and returns the ones the mountain still remembers.
static func age_rounds(rounds: Array, delta: float) -> Array:
	var kept: Array = []
	for round in rounds:
		round.age += delta
		if round.age < LIFETIME_SECONDS:
			kept.append(round)
	return kept
