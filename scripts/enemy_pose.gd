class_name EnemyPose
extends SkeletonModifier3D
## Procedural layer over the wolf clips, run after the AnimationTree so it sits
## on the final pose: it bulks the forequarters and head into a wolverine's
## shape, turns the neck and head toward whatever the animal is suspicious of,
## and drops the forebody into a wind-up crouch.
##
## The rig bakes a 100x scale into its skeleton node, so every rotation here is
## composed on global bone bases (unit scale) and every scale is set against the
## bone's own rest scale. Bone +Y points along the bone, toward the muzzle.

const LOOK_CHAIN := ["Neck1", "Neck2", "Neck3", "Head"]
const LOOK_SHARE := [0.18, 0.24, 0.26, 0.32]
const MAX_YAW := 1.25
const MAX_PITCH := 0.6

## Bone name -> Vector3 scale multiplier, applied against the rest scale.
var bulk := {}
## World point the head should track, and how strongly (0..1).
var look_target := Vector3.ZERO
var look_weight := 0.0
## Crouch that drops the shoulders during a wind-up or aim, 0..1.
var crouch := 0.0

var _bone_ids := {}
var _look_ids: Array[int] = []
var _look_yaw := 0.0
var _look_pitch := 0.0
var _torso_ids: Array[int] = []


func setup(skeleton: Skeleton3D) -> void:
	for bone_name in bulk:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			_bone_ids[index] = bulk[bone_name]
	for bone_name in LOOK_CHAIN:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			_look_ids.append(index)
	for bone_name in ["Torso", "Torso2"]:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			_torso_ids.append(index)


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for index in _bone_ids:
		skeleton.set_bone_pose_scale(index, skeleton.get_bone_rest(index).basis.get_scale() * _bone_ids[index])
	var up := (skeleton.global_transform.affine_inverse().basis * Vector3.UP).normalized()
	if crouch > 0.01:
		_apply_torso(skeleton, up)
	if look_weight > 0.01 and _look_ids.size() == LOOK_CHAIN.size():
		_apply_look(skeleton, up)


## Pitch the forebody about the hips' lateral axis: the Torso chain carries the
## shoulders, neck and head, so rotating it drops the whole front into a crouch.
func _apply_torso(skeleton: Skeleton3D, up: Vector3) -> void:
	if _torso_ids.is_empty():
		return
	var pose: Transform3D = skeleton.get_bone_global_pose(_torso_ids[0])
	# Bone +Y is forward; a positive rotation about forward x up lifts the nose,
	# so a crouch is a negative pitch.
	var forward := pose.basis.y.normalized()
	var lateral := forward.cross(up).normalized()
	var angle := -crouch * 0.3
	var rotated := Basis(lateral, angle) * pose.basis
	skeleton.set_bone_global_pose(_torso_ids[0], Transform3D(rotated, pose.origin))


func _apply_look(skeleton: Skeleton3D, up: Vector3) -> void:
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var local_target := to_skeleton * look_target
	var head_pose: Transform3D = skeleton.get_bone_global_pose(_look_ids[_look_ids.size() - 1])
	var to_target := local_target - head_pose.origin
	to_target = to_target.normalized()
	# Head direction is bone +Y. Split both directions into yaw about `up` and pitch.
	var heading := head_pose.basis.y.normalized()
	var right := heading.cross(up).normalized()
	var flat_forward := (heading - up * heading.dot(up)).normalized()
	var flat_target := (to_target - up * to_target.dot(up))
	if flat_target.length() < 0.001 or flat_forward.length() < 0.001:
		return
	flat_target = flat_target.normalized()
	var yaw := flat_forward.signed_angle_to(flat_target, up)
	var pitch := asin(clampf(to_target.dot(up), -1.0, 1.0)) - asin(clampf(heading.dot(up), -1.0, 1.0))
	yaw = clampf(yaw, -MAX_YAW, MAX_YAW)
	pitch = clampf(pitch, -MAX_PITCH, MAX_PITCH)
	# Smooth per-frame so a snapping target never snaps the neck.
	var blend := 1.0 - exp(-12.0 * get_process_delta_time())
	_look_yaw = lerpf(_look_yaw, yaw * look_weight, blend)
	_look_pitch = lerpf(_look_pitch, pitch * look_weight, blend)
	for chain_index in _look_ids.size():
		var index := _look_ids[chain_index]
		var pose: Transform3D = skeleton.get_bone_global_pose(index)
		var share: float = LOOK_SHARE[chain_index]
		var pitch_axis := pose.basis.y.normalized().cross(up).normalized()
		var rotation := Basis(up, _look_yaw * share) * Basis(pitch_axis, _look_pitch * share)
		skeleton.set_bone_global_pose(index, Transform3D(rotation * pose.basis, pose.origin))
