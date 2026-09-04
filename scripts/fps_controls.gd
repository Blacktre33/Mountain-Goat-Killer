class_name FPSControls
extends RefCounted

const MOUSE_SENSITIVITY := Vector2(0.00175, 0.00155)
const PITCH_MIN := -1.35
const PITCH_MAX := 1.25


static func apply_look(yaw: float, pitch: float, relative: Vector2) -> Vector2:
	return Vector2(
		yaw - relative.x * MOUSE_SENSITIVITY.x,
		clampf(pitch - relative.y * MOUSE_SENSITIVITY.y, PITCH_MIN, PITCH_MAX),
	)


static func planar_basis(yaw: float) -> Dictionary:
	var rotation_basis := Basis(Vector3.UP, yaw)
	return {
		"forward": rotation_basis * Vector3.FORWARD,
		"right": rotation_basis * Vector3.RIGHT,
	}


static func movement_vector(yaw: float, input_vector: Vector2) -> Vector3:
	var directions := planar_basis(yaw)
	var movement: Vector3 = (
		directions.forward * -input_vector.y + directions.right * input_vector.x
	)
	return movement.normalized() if movement.length_squared() > 0.0 else Vector3.ZERO
