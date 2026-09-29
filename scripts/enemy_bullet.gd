class_name EnemyBullet
extends Node3D
## A warpack rifle round. It flies on real physics steps so it can be dodged,
## can strike only what it actually reaches (walls stop it), and leaves a bright
## streak the goat can read.

const SPEED := 64.0
const MAX_AGE := 1.4
const WHIZ_RADIUS := 1.7

var velocity := Vector3.ZERO
var damage := 10
var shooter: Node3D
var target: GoatPlayer
var age := 0.0
var _whizzed := false
var _query: PhysicsRayQueryParameters3D


static func fire(parent: Node, from: Vector3, direction: Vector3, hit_damage: int, source: Node3D, victim: GoatPlayer) -> EnemyBullet:
	var bullet := EnemyBullet.new()
	bullet.name = "WarpackRound"
	bullet.damage = hit_damage
	bullet.shooter = source
	bullet.target = victim
	bullet.velocity = direction.normalized() * SPEED
	parent.add_child(bullet)
	bullet.global_position = from
	bullet.look_at(from + direction, Vector3.UP if absf(direction.normalized().y) < 0.99 else Vector3.RIGHT)
	bullet._build_visual()
	return bullet


func _build_visual() -> void:
	var streak := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.028, 0.028, 1.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.78, 0.42)
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = material
	streak.mesh = mesh
	streak.position.z = 0.75
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(streak)


func _physics_process(delta: float) -> void:
	age += delta
	if age > MAX_AGE:
		queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	if _query == null:
		_query = PhysicsRayQueryParameters3D.new()
		_query.collision_mask = 1
	_query.from = from
	_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if is_instance_valid(target) and not _whizzed and target.active:
		var closest := Geometry3D.get_closest_point_to_segment(target.chest_position(), from, to)
		if closest.distance_to(target.chest_position()) < WHIZ_RADIUS:
			_whizzed = true
			EnemyFx.sound(get_tree(), "whiz", closest, -2.0, randf_range(0.9, 1.15), "footstep")
	if hit:
		if hit.collider == target and is_instance_valid(target):
			target.damage(damage, from)
			target.knockback(from - velocity.normalized(), 1.6, 0.0)
			EnemyFx.sparks(get_parent(), hit.position, hit.normal, 6, 2.5, Color(0.6, 0.05, 0.03))
		else:
			EnemyFx.sparks(get_parent(), hit.position, hit.normal, 10, 4.5)
			EnemyFx.sound(get_tree(), "rock_hit", hit.position, -8.0, randf_range(1.1, 1.5))
		queue_free()
		return
	global_position = to
