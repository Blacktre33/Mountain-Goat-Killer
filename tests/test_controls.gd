extends SceneTree


func _init() -> void:
	for yaw in [-PI, -PI * 0.5, -0.35, 0.0, 0.7, PI * 0.5]:
		var directions := FPSControls.planar_basis(yaw)
		assert(is_equal_approx(directions.forward.length(), 1.0))
		assert(is_zero_approx(directions.forward.dot(directions.right)))

	var turned := FPSControls.apply_look(0.0, 0.0, Vector2(100.0, 0.0))
	assert(turned.x < 0.0)
	assert(FPSControls.planar_basis(turned.x).forward.x > 0.0)
	assert(is_equal_approx(FPSControls.apply_look(0.0, 0.0, Vector2(0.0, -100000.0)).y, FPSControls.PITCH_MAX))
	assert(is_equal_approx(FPSControls.apply_look(0.0, 0.0, Vector2(0.0, 100000.0)).y, FPSControls.PITCH_MIN))

	print("FPS control tests passed")
	quit()
