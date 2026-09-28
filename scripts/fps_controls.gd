class_name FPSControls
extends RefCounted

const MOUSE_SENSITIVITY := Vector2(0.00175, 0.00155)
const PITCH_MIN := -1.35
const PITCH_MAX := 1.25
## Full-deflection right-stick turn rate, radians per second.
const STICK_LOOK_SPEED := Vector2(3.1, 2.2)
## Look slows to this fraction while the crosshair rests on a target (gamepad only).
const AIM_FRICTION := 0.42
const AIM_FRICTION_COS := 0.9962  # about 5 degrees either side of the aim line
const AIM_FRICTION_RANGE := 45.0


static func apply_look(yaw: float, pitch: float, relative: Vector2, sensitivity := 1.0, invert_y := false) -> Vector2:
	var vertical := -relative.y if invert_y else relative.y
	return Vector2(
		yaw - relative.x * MOUSE_SENSITIVITY.x * sensitivity,
		clampf(pitch - vertical * MOUSE_SENSITIVITY.y * sensitivity, PITCH_MIN, PITCH_MAX),
	)


## Right-stick look. A squared response curve keeps small deflections precise
## while full deflection still turns quickly.
static func apply_stick_look(yaw: float, pitch: float, stick: Vector2, delta: float, sensitivity := 1.0, invert_y := false, friction := 1.0) -> Vector2:
	var magnitude := minf(1.0, stick.length())
	if magnitude <= 0.0:
		return Vector2(yaw, pitch)
	var curved := stick.normalized() * magnitude * magnitude
	var vertical := -curved.y if invert_y else curved.y
	var scale := sensitivity * friction * delta
	return Vector2(
		yaw - curved.x * STICK_LOOK_SPEED.x * scale,
		clampf(pitch - vertical * STICK_LOOK_SPEED.y * scale, PITCH_MIN, PITCH_MAX),
	)


## 1.0, or AIM_FRICTION when any target sits close to the aim line.
static func aim_friction(origin: Vector3, aim: Vector3, targets: Array) -> float:
	for point in targets:
		var to_target: Vector3 = point - origin
		var distance := to_target.length()
		if distance < 0.5 or distance > AIM_FRICTION_RANGE:
			continue
		if aim.normalized().dot(to_target / distance) >= AIM_FRICTION_COS:
			return AIM_FRICTION
	return 1.0


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
