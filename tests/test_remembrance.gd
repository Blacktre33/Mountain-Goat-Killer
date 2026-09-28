extends SceneTree


func _init() -> void:
	var forward := Vector3(0.0, 0.0, -1.0)

	assert(Remembrance.can_hang(0, 5, false, false))
	assert(not Remembrance.can_hang(Remembrance.CAPACITY, 5, false, false))
	# Capacity starts at three and grows with each kindled cairn, never past six.
	assert(Remembrance.capacity_for(0) == Remembrance.BASE_CAPACITY and Remembrance.BASE_CAPACITY == 3)
	assert(Remembrance.capacity_for(2) == 5 and Remembrance.capacity_for(9) == Remembrance.CAPACITY)
	assert(not Remembrance.can_hang(3, 5, false, false, Remembrance.capacity_for(0)))
	assert(Remembrance.can_hang(3, 5, false, false, Remembrance.capacity_for(1)))
	assert(not Remembrance.can_hang(0, 0, false, false))
	assert(not Remembrance.can_hang(0, 5, true, false))
	assert(not Remembrance.can_hang(0, 5, false, true))

	var hung := Remembrance.HungRound.new(Vector3(0.0, 1.0, 0.0), forward)
	assert(is_zero_approx(Remembrance.beam_distance(hung, Vector3(0.0, 1.0, -10.0))))
	assert(is_equal_approx(Remembrance.beam_distance(hung, Vector3(2.0, 1.0, -10.0)), 2.0))
	assert(is_equal_approx(Remembrance.beam_distance(hung, Vector3(0.0, 1.0, 5.0)), 5.0))

	var on_line := {"id": 2, "position": Vector3(0.0, 1.0, -12.0), "boss": false}
	var nearly_ahead := {"id": 1, "position": Vector3(1.5, 1.0, -20.0), "boss": false}
	var off_cone := {"id": 3, "position": Vector3(12.0, 1.0, -12.0), "boss": false}
	var far_off_line := {"id": 5, "position": Vector3(3.2, 1.0, -30.0), "boss": false}
	var close_side := {"id": 6, "position": Vector3(1.2, 1.0, -6.0), "boss": false}
	assert(Remembrance.guide(hung, [nearly_ahead, off_cone, on_line]).target.id == 2)
	assert(Remembrance.guide(hung, [off_cone]).is_empty())
	assert(Remembrance.guide(hung, [far_off_line]).is_empty(), "guidance is assist, not auto-aim")
	assert(Remembrance.guide(hung, [close_side]).target.id == 6)
	var beyond := {"id": 4, "position": Vector3(0.0, 1.0, -(Remembrance.BEAM_LENGTH + 1.0)), "boss": false}
	assert(Remembrance.guide(hung, [beyond]).is_empty())

	var left := Remembrance.HungRound.new(Vector3(-4.0, 1.0, 0.0), Vector3(0.2, 0.0, -1.0))
	var right := Remembrance.HungRound.new(Vector3(4.0, 1.0, 0.0), Vector3(-0.2, 0.0, -1.0))
	var stray := Remembrance.HungRound.new(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0))
	var enemy := {"id": 7, "position": Vector3(0.0, 1.0, -20.0), "boss": false}
	var shots := Remembrance.plan_volley([left, right, stray], [enemy])
	assert(shots[0].target == 7 and shots[1].target == 7 and shots[2].target == -1)
	assert(shots[0].converged and shots[1].converged and not shots[2].converged)
	assert(shots[0].damage == roundi(Remembrance.BODY_DAMAGE * Remembrance.CONVERGENCE_MULTIPLIER))
	assert(shots[2].damage == 0)
	assert(is_equal_approx(shots[2].distance, Remembrance.BEAM_LENGTH))

	var single := Remembrance.plan_volley([left], [enemy])
	assert(not single[0].converged and single[0].damage == Remembrance.BODY_DAMAGE)
	var boss := {"id": 7, "position": Vector3(0.0, 1.0, -20.0), "boss": true}
	assert(Remembrance.plan_volley([left], [boss])[0].damage == Remembrance.BOSS_DAMAGE)

	var covered := Remembrance.plan_volley(
		[left, right],
		[enemy],
		func(round: Remembrance.HungRound, _direction: Vector3, _distance: float) -> bool: return round == right,
	)
	assert(covered[0].target == 7)
	assert(covered[1].target == -1, "a blocked shot lands nothing")
	assert(not covered[0].converged, "a blocked shot does not count toward convergence")

	var fresh := Remembrance.HungRound.new(Vector3.ZERO, forward)
	var old := Remembrance.HungRound.new(Vector3.ZERO, forward)
	old.age = Remembrance.LIFETIME_SECONDS - 0.5
	var aged := Remembrance.age_rounds([fresh, old], 1.0)
	assert(aged.size() == 1 and aged[0] == fresh and is_equal_approx(fresh.age, 1.0))

	print("Remembrance tests passed")
	quit()
