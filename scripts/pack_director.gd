class_name PackDirector
extends RefCounted
## Coordinates the warpack so a fight reads as a hunt instead of a dogpile:
## attack tokens cap how many wolverines strike (or shoot) at once, and an alert
## assigns each one a role. Token holders expire on their own, so a wolverine
## that dies mid-attack never starves the pack.

const MELEE_TOKENS := 2
const RANGED_TOKENS := 2
const TOKEN_LIFETIME_MSEC := 4200

static var _held := {"melee": {}, "ranged": {}}


static func now() -> int:
	return Time.get_ticks_msec()


static func capacity(kind: String, boss_phase := 1) -> int:
	if kind == "melee":
		return MELEE_TOKENS + (1 if boss_phase >= 3 else 0)
	return RANGED_TOKENS


## Asks for an attack token. Holding one already just renews it.
static func request(kind: String, enemy: Object, boss_phase := 1) -> bool:
	_purge(kind)
	var pool: Dictionary = _held[kind]
	var id := enemy.get_instance_id()
	if pool.has(id) or pool.size() < capacity(kind, boss_phase):
		pool[id] = now() + TOKEN_LIFETIME_MSEC
		return true
	return false


static func release(kind: String, enemy: Object) -> void:
	_held[kind].erase(enemy.get_instance_id())


static func release_all(enemy: Object) -> void:
	release("melee", enemy)
	release("ranged", enemy)


static func holders(kind: String) -> int:
	_purge(kind)
	return _held[kind].size()


static func reset() -> void:
	_held = {"melee": {}, "ranged": {}}


static func _purge(kind: String) -> void:
	var pool: Dictionary = _held[kind]
	var stale: Array = []
	var t := now()
	for id in pool:
		if pool[id] < t or not is_instance_id_valid(id):
			stale.append(id)
	for id in stale:
		pool.erase(id)


## Assigns `pack_role` on every living, alerted member: the nearest melee
## fighter rushes, the rest flank from alternating sides, riflemen suppress.
## `player_position` orders the melee fighters by how soon they can arrive.
static func assign_roles(members: Array, player_position: Vector3) -> void:
	var melee: Array = []
	var shooters: Array = []
	for member in members:
		if member.boss or member.dead:
			continue
		if member.role == "rifleman":
			shooters.append(member)
		else:
			melee.append(member)
	melee.sort_custom(func(a, b) -> bool:
		return a.global_position.distance_squared_to(player_position) < b.global_position.distance_squared_to(player_position))
	var side := 1.0
	for index in melee.size():
		var member = melee[index]
		if index == 0:
			member.pack_role = "rusher"
			member.flank_side = 0.0
		else:
			member.pack_role = "flanker"
			member.flank_side = side
			side = -side
	for shooter in shooters:
		shooter.pack_role = "suppressor" if shooters.size() > 1 or not melee.is_empty() else "marksman"
