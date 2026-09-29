extends SceneTree
## The warpack's fight, on real physics in the real ravine: navigation across the
## map, telegraphed melee with a dodge window, rifle fire that cannot pass walls,
## attack tokens, death, and dead packmates raising the alarm.

var mission: Node3D
var player: GoatPlayer
var failures: Array[String] = []
var spawned: Array[WolverineEnemy] = []


func _init() -> void:
	call_deferred("run_test")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func ground(x: float, z: float, lift := 0.4) -> Vector3:
	return Vector3(x, WorldBuilder.height_at(x, z) + lift, z)


func spawn(role: String, at: Vector3, route: Array = []) -> WolverineEnemy:
	var enemy := WolverineEnemy.new()
	enemy.name = "TestWolverine_%d" % spawned.size()
	mission.add_child(enemy)
	enemy.configure(player, role, at, route if not route.is_empty() else [at], -1)
	spawned.append(enemy)
	return enemy


func clear_spawned() -> void:
	for enemy in spawned:
		if is_instance_valid(enemy):
			enemy.remove_from_group("enemies")
			enemy.remove_from_group("corpses")
			enemy.queue_free()
	spawned.clear()
	for round in mission.find_children("WarpackRound", "", false, false):
		round.queue_free()
	PackDirector.reset()


func steps(count: int) -> void:
	for _i in count:
		await physics_frame


func place_player(at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.health = 100


func run_test() -> void:
	seed(4242)
	mission = load("res://main.tscn").instantiate()
	root.add_child(mission)
	await process_frame
	mission._start_game()
	player = mission.player
	player.set_physics_process(false)
	for enemy in mission.enemies:
		enemy.set_physics_process(false)
		enemy.global_position = Vector3(500.0, 0.0, 500.0)
	Engine.time_scale = 4.0
	# Wait for the navigation mesh to bake.
	var first := spawn("stalker", ground(0.0, 30.0))
	var waited := 0
	while not EnemyNav.is_ready() and waited < 600:
		await physics_frame
		waited += 1
	check(EnemyNav.is_ready(), "Navigation mesh never baked")
	await steps(20)
	clear_spawned()

	await test_navigation()
	Engine.time_scale = 1.0
	await test_melee_telegraph()
	await test_dodge()
	await test_tokens()
	await test_brute_charge()
	await test_retreat_and_cover()
	await test_rifle()
	await test_death_and_bodies()

	Engine.time_scale = 1.0
	clear_spawned()
	mission.audio.shutdown()
	await create_timer(0.1).timeout
	if failures.is_empty():
		print("Enemy behaviour tests passed")
	quit(0 if failures.is_empty() else 1)


## Wolverines spread across the map hunt one goat around rocks, walls, the fold
## and pillars: every one of them must close to biting range.
func test_navigation() -> void:
	place_player(ground(0.0, -6.0, 0.95))
	var starts := [
		Vector2(-6.0, 28.0), Vector2(6.0, 18.0), Vector2(-9.0, 8.0), Vector2(8.0, -1.0),
		Vector2(-8.0, -14.0), Vector2(5.0, -22.0), Vector2(3.5, -35.0), Vector2(7.0, -40.0),
	]
	var closest := {}
	for start in starts:
		var enemy := spawn("stalker", ground(start.x, start.y))
		enemy.speed = 6.0
		closest[enemy] = 1e9
		enemy.alert_to(player.global_position)
	for tick in 42:
		await steps(30)
		place_player(ground(0.0, -6.0, 0.95))
		for enemy in closest:
			closest[enemy] = minf(closest[enemy], enemy.global_position.distance_to(player.global_position))
	var reached := 0
	for enemy in closest:
		if closest[enemy] < 5.0:
			reached += 1
		else:
			print("Stuck wolverine from ", enemy.home_position, " closest ", closest[enemy])
	check(reached == starts.size(), "Only %d of %d wolverines reached the goat across the map" % [reached, starts.size()])
	clear_spawned()


## A melee strike is announced: no damage may land during the wind-up, and it
## must land at the impact frame of the strike, not the moment the clip starts.
func test_melee_telegraph() -> void:
	place_player(ground(0.0, 12.0, 0.95))
	var enemy := spawn("stalker", ground(0.0, 8.0))
	enemy.alert_to(player.global_position)
	enemy.stagger = 0.0
	var windup_seen := false
	var damage_during_windup := false
	var hit_after_windup := false
	for tick in 1200:
		await physics_frame
		player.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, 12.0) + 0.95, 12.0)
		var before := player.health
		# The player stands still; the knockback should not push the test around.
		player.velocity = Vector3.ZERO
		if enemy.combat == WolverineEnemy.Combat.WINDUP:
			windup_seen = true
			if player.health < before:
				damage_during_windup = true
		if windup_seen and enemy.combat == WolverineEnemy.Combat.RECOVER and player.health < 100:
			hit_after_windup = true
			break
		if player.health < 100 and not windup_seen:
			damage_during_windup = true
			break
	check(windup_seen, "A stalker never wound up before striking")
	check(not damage_during_windup, "A stalker damaged the goat before or during its wind-up")
	check(hit_after_windup, "A stalker's strike never landed on a still goat")
	clear_spawned()


## Stepping out of the locked lunge line during the wind-up beats the strike.
func test_dodge() -> void:
	var dodged := 0
	var trials := 3
	for trial in trials:
		place_player(ground(0.0, 12.0, 0.95))
		var enemy := spawn("stalker", ground(0.0, 8.0))
		enemy.feinting = false
		enemy.alert_to(player.global_position)
		var missed := [false]
		enemy.attack_dodged.connect(func(_who: WolverineEnemy) -> void: missed[0] = true)
		var lateral := 0.0
		var health_at_start := player.health
		for tick in 900:
			await physics_frame
			player.velocity = Vector3.ZERO
			if enemy.combat == WolverineEnemy.Combat.WINDUP and enemy.combat_time > enemy.windup_total * 0.55:
				# Sidestep: the locked lunge goes where the goat was.
				lateral = minf(lateral + 0.08, 3.0)
			player.global_position = Vector3(lateral, WorldBuilder.height_at(lateral, 12.0) + 0.95, 12.0)
			if enemy.combat == WolverineEnemy.Combat.RECOVER:
				break
		if player.health == health_at_start and missed[0]:
			dodged += 1
		clear_spawned()
	check(dodged >= 2, "A sidestep during the wind-up did not beat the strike (%d of %d dodged)" % [dodged, trials])


## Four hunters may not all strike at once: at most two melee tokens exist.
func test_tokens() -> void:
	place_player(ground(0.0, -6.0, 0.95))
	for index in 4:
		var enemy := spawn("stalker", ground(-6.0 + index * 4.0, -12.0))
		enemy.alert_to(player.global_position)
	var most := 0
	for tick in 900:
		await physics_frame
		player.health = 100
		player.velocity = Vector3.ZERO
		player.global_position = ground(0.0, -6.0, 0.95)
		var attacking := 0
		for enemy in spawned:
			if enemy.combat == WolverineEnemy.Combat.WINDUP or enemy.combat == WolverineEnemy.Combat.STRIKE:
				attacking += 1
		most = maxi(most, attacking)
	check(most <= PackDirector.MELEE_TOKENS, "%d wolverines attacked at once (limit %d)" % [most, PackDirector.MELEE_TOKENS])
	check(most >= 1, "The pack never attacked")
	var roles := {}
	for enemy in spawned:
		roles[enemy.pack_role] = true
	check(roles.has("rusher") and roles.has("flanker"), "Alert did not assign rusher and flanker roles: %s" % [roles.keys()])
	clear_spawned()


## A rifleman aims with a visible beam and fires real rounds, and a wall
## between it and the goat stops every one of them.
func test_rifle() -> void:
	var rifleman_at := ground(0.0, 20.0)
	place_player(ground(0.0, 6.0, 0.95))
	var enemy := spawn("rifleman", rifleman_at)
	enemy.alert_to(player.global_position)
	var saw_beam := false
	var saw_round := false
	for tick in 900:
		await physics_frame
		player.velocity = Vector3.ZERO
		player.global_position = ground(0.0, 6.0, 0.95)
		if enemy.laser != null and enemy.laser.visible:
			saw_beam = true
		if mission.find_children("WarpackRound", "", false, false).size() > 0:
			saw_round = true
		if saw_beam and saw_round:
			break
	check(saw_beam, "A rifleman fired without a visible aiming beam")
	check(saw_round, "A rifleman never fired a real round")
	check(enemy.rounds < 4 or player.health < 100, "A rifleman never spent ammunition")
	clear_spawned()

	# A solid wall between the shooter and the goat: nothing gets through.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	mission.add_child(wall)
	var wall_y := WorldBuilder.height_at(0.0, 13.0)
	wall.global_position = Vector3(0.0, wall_y + 3.0, 13.0)
	place_player(ground(0.0, 6.0, 0.95))
	var shooter := spawn("rifleman", ground(0.0, 20.0))
	shooter.alert_to(player.global_position)
	var damaged := false
	for tick in 600:
		await physics_frame
		player.velocity = Vector3.ZERO
		player.global_position = ground(0.0, 6.0, 0.95)
		if player.health < 100:
			damaged = true
			print("wall breach: shooter at ", shooter.global_position, " combat=", shooter.combat, " state=", shooter.state, " rounds=", shooter.rounds, " health=", player.health)
			break
	check(not damaged, "A rifleman shot the goat through a wall")
	check(shooter.rounds == 4 or shooter.combat != WolverineEnemy.Combat.AIM, "A rifleman kept aiming through solid stone")
	wall.queue_free()
	clear_spawned()


## Death is physical and lingers, and a patrol that sees a dead packmate
## raises the alarm.
func test_death_and_bodies() -> void:
	place_player(ground(20.0, -6.0, 0.95))
	var victim := spawn("stalker", ground(0.0, 0.0))
	var witness := spawn("rifleman", ground(-1.0, 8.0))
	witness.rotation.y = PI
	witness.state = WolverineEnemy.State.PATROL
	var start := victim.global_position
	victim.hit_direction = Vector3(0.0, 0.0, -1.0)
	victim.take_damage(999, 0.5, true)
	check(victim.dead and victim.is_in_group("corpses") and not victim.is_in_group("enemies"), "A killed wolverine is not a corpse")
	await steps(90)
	check(is_instance_valid(victim) and victim.is_inside_tree(), "A corpse vanished within a second of dying")
	check(victim.global_position.distance_to(start) > 0.4, "A corpse did not carry its knockback")
	check(victim.collision_layer == 0, "A corpse still blocks movement")
	# The witness turns to face the body and finds it.
	witness.rotation.y = 0.0
	witness.detection = 0.0
	await steps(240)
	check(witness.found_body, "A patrol that faced a dead packmate never found the body")
	check(witness.state == WolverineEnemy.State.SEARCH or witness.state == WolverineEnemy.State.ALERT, "Finding a body did not raise the alarm")
	clear_spawned()


## A brute telegraphs a shoulder-charge, and a goat who sidesteps it leaves it
## to run into stone and stagger.
func test_brute_charge() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 8.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	mission.add_child(wall)
	wall.global_position = Vector3(0.0, WorldBuilder.height_at(0.0, 5.0) + 3.0, 5.0)
	place_player(ground(0.0, 8.0, 0.95))
	var brute := spawn("brute", ground(0.0, 20.0))
	brute.alert_to(player.global_position)
	var dodged := [false]
	brute.attack_dodged.connect(func(_who: WolverineEnemy) -> void: dodged[0] = true)
	var charged := false
	var staggered := false
	var windup_seen := false
	var lateral := 0.0
	for tick in 1500:
		await physics_frame
		player.velocity = Vector3.ZERO
		player.health = 100
		if brute.combat == WolverineEnemy.Combat.WINDUP:
			windup_seen = true
			if brute.strike_kind == "charge" and brute.combat_time > brute.windup_total * 0.6:
				lateral = minf(lateral + 0.1, 3.5)
		if brute.combat == WolverineEnemy.Combat.CHARGE:
			charged = true
		player.global_position = Vector3(lateral, WorldBuilder.height_at(lateral, 8.0) + 0.95, 8.0)
		if brute.combat == WolverineEnemy.Combat.STAGGERED:
			staggered = true
			break
	check(windup_seen, "A brute charged without a wind-up")
	check(charged, "A brute never shoulder-charged across open ground")
	check(staggered, "A brute that missed its charge did not stagger against the wall")
	check(dodged[0], "A dodged charge was not reported as dodged")
	wall.queue_free()
	clear_spawned()


## Wounded wolverines break off, and a rifleman with stone nearby uses it.
func test_retreat_and_cover() -> void:
	place_player(ground(0.0, 6.0, 0.95))
	var hurt := spawn("stalker", ground(0.0, 14.0))
	hurt.alert_to(player.global_position)
	hurt.health = int(hurt.max_health * 0.2)
	await steps(30)
	hurt.take_damage(1, 0.1)
	var retreated := false
	var start_distance := hurt.global_position.distance_to(player.global_position)
	for tick in 240:
		await physics_frame
		player.velocity = Vector3.ZERO
		player.global_position = ground(0.0, 6.0, 0.95)
		if hurt.combat == WolverineEnemy.Combat.RETREAT:
			retreated = true
	check(retreated, "A badly wounded wolverine never fell back")
	clear_spawned()

	# Cover: a boulder-sized block between a rifleman and the goat gives it a place to hide.
	var rock := StaticBody3D.new()
	rock.collision_layer = 1
	var rock_shape := CollisionShape3D.new()
	var rock_box := BoxShape3D.new()
	rock_box.size = Vector3(5.0, 3.0, 2.0)
	rock_shape.shape = rock_box
	rock.add_child(rock_shape)
	mission.add_child(rock)
	rock.global_position = Vector3(3.0, WorldBuilder.height_at(3.0, 18.0) + 1.5, 18.0)
	place_player(ground(0.0, 3.0, 0.95))
	var shooter := spawn("rifleman", ground(1.0, 22.0))
	shooter.alert_to(player.global_position)
	shooter.rounds = 4
	var used_cover := false
	for tick in 1200:
		await physics_frame
		player.velocity = Vector3.ZERO
		player.health = 100
		player.global_position = ground(0.0, 3.0, 0.95)
		if shooter.combat == WolverineEnemy.Combat.COVER or shooter.combat == WolverineEnemy.Combat.PEEK:
			used_cover = true
			break
	check(used_cover, "A rifleman with stone nearby never took cover")
	rock.queue_free()
	clear_spawned()
