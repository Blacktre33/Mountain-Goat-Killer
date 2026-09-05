extends SceneTree


func _init() -> void:
	# Movement noise ladders up from still to sprint.
	assert(Stealth.movement_noise(false, true, false) == 0.0)
	assert(Stealth.movement_noise(true, false, true) < Stealth.movement_noise(true, false, false))
	assert(Stealth.movement_noise(true, false, false) < Stealth.movement_noise(true, true, false))
	assert(Stealth.noise_radius("hang") == 0.0, "hanging a Remembrance round is silent")
	assert(Stealth.noise_radius("shot") > Stealth.noise_radius("sprint"))

	# Scent only reaches a wolverine standing downwind of the goat.
	var wind := Vector3(1.0, 0.0, 0.0)
	var goat := Vector3.ZERO
	assert(Stealth.scent_strength(goat, Vector3(8.0, 0.0, 0.0), wind) > 0.4, "downwind wolverine smells the goat")
	assert(Stealth.scent_strength(goat, Vector3(-8.0, 0.0, 0.0), wind) == 0.0, "upwind wolverine smells nothing")
	assert(Stealth.scent_strength(goat, Vector3(0.0, 0.0, 8.0), wind) == 0.0, "crosswind carries nothing")
	assert(Stealth.scent_strength(goat, Vector3(Stealth.SCENT_RANGE + 1.0, 0.0, 0.0), wind) == 0.0)
	assert(Stealth.is_upwind(goat, Vector3(-8.0, 0.0, 0.0), wind))
	assert(not Stealth.is_upwind(goat, Vector3(8.0, 0.0, 0.0), wind))
	assert(is_equal_approx(Stealth.wind_at(3.0).length(), 1.0))

	# Sight needs line of sight, the view cone, and range; crouching and darkness help the goat.
	var facing := Vector3(0.0, 0.0, -1.0)
	assert(Stealth.sight_rate(facing, Vector3(0.0, 0.0, -10.0), false, false, 0.0) == 0.0, "no line of sight")
	assert(Stealth.sight_rate(facing, Vector3(0.0, 0.0, 10.0), true, false, 0.0) == 0.0, "behind the wolverine")
	assert(Stealth.sight_rate(facing, Vector3(0.0, 0.0, 1.5), true, false, 0.0) > 0.0, "point blank is noticed even behind")
	var standing := Stealth.sight_rate(facing, Vector3(0.0, 0.0, -10.0), true, false, 0.0)
	var crouched := Stealth.sight_rate(facing, Vector3(0.0, 0.0, -10.0), true, true, 0.0)
	var lit := Stealth.sight_rate(facing, Vector3(0.0, 0.0, -10.0), true, false, 1.0)
	assert(standing > 0.0 and crouched < standing and lit > standing)
	assert(Stealth.sight_rate(facing, Vector3(0.0, 0.0, -(Stealth.SIGHT_RANGE + 1.0)), true, false, 0.0) == 0.0, "dark: out of range")
	assert(Stealth.sight_rate(facing, Vector3(0.0, 0.0, -(Stealth.SIGHT_RANGE + 1.0)), true, false, 1.0) > 0.0, "lantern light: in range")

	# Hearing and the meter.
	assert(Stealth.hears(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), 9.0))
	assert(not Stealth.hears(Vector3.ZERO, Vector3(12.0, 0.0, 0.0), 9.0))
	var meter := 0.0
	for i in 10:
		meter = Stealth.step_detection(meter, 0.5, 0.1)
	assert(is_equal_approx(meter, 0.5) and Stealth.awareness_of(meter) == "suspicious")
	meter = Stealth.step_detection(meter, 5.0, 1.0)
	assert(meter == Stealth.ALERT and Stealth.awareness_of(meter) == "alert")
	meter = Stealth.step_detection(meter, 0.0, 1.0)
	assert(meter < Stealth.ALERT, "meter decays when nothing is sensed")
	assert(Stealth.awareness_of(0.1) == "unaware")

	# Takedowns need the goat behind an enemy that has not gone alert.
	assert(Stealth.can_takedown(facing, Vector3(0.0, 0.0, 1.5), 0.2), "behind and close")
	assert(not Stealth.can_takedown(facing, Vector3(0.0, 0.0, -1.5), 0.2), "in front")
	assert(not Stealth.can_takedown(facing, Vector3(0.0, 0.0, 1.5), Stealth.ALERT), "alert enemies cannot be taken down")
	assert(not Stealth.can_takedown(facing, Vector3(0.0, 0.0, 4.0), 0.2), "too far")
	assert(Stealth.ambush_multiplier(0.1) > 1.0 and Stealth.ambush_multiplier(0.9) == 1.0)

	# Story zones and objectives line up along the ravine.
	assert(Story.zone_for_z(30.0, false) == "trailhead")
	assert(Story.zone_for_z(0.0, false) == "homestead")
	assert(Story.zone_for_z(-30.0, false) == "shrine" and Story.zone_for_z(-30.0, true) == "shrine_rung")
	assert(Story.zone_for_z(-60.0, false) == "ascent" and Story.zone_for_z(-90.0, false) == "gate")
	assert(Story.chapter_for_zone("shrine_rung").title == Story.CHAPTERS.shrine.title)
	assert(Story.biome_for_z(20.0) == "whitewood")
	assert(Story.biome_for_zone("shrine") == "carrion_cut")
	assert(Story.biome_for_zone("gate") == "iron_crown")
	assert(not Story.can_ring_mother_bell(3) and Story.can_ring_mother_bell(4))
	assert(not Story.can_open_iron_gate(7, true) and not Story.can_open_iron_gate(8, false))
	assert(Story.can_open_iron_gate(8, true))
	assert(Story.objective_for("shrine", false, false, 3, false) == Story.OBJECTIVES.shrine_locked)
	assert(Story.objective_for("gate", false, false, 7, true) == Story.OBJECTIVES.gate_locked)
	assert(Story.objective_for("gate", false, false, 8, false) == Story.OBJECTIVES.gate_locked)
	assert(Story.objective_for("gate", true, false) == Story.OBJECTIVES.boss)
	assert(Story.objective_for("gate", true, true) == Story.OBJECTIVES.victory)
	assert(Story.BELL_NAMES.size() == 9 and Story.bell_name(99) == "ORIN")
	assert(Story.BELL_MEMORIES.size() == Story.BELL_NAMES.size())
	for index in Story.BELL_NAMES.size():
		assert(not Story.bell_memory(index).is_empty())

	print("Stealth tests passed")
	quit()
