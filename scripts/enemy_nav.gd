class_name EnemyNav
extends RefCounted
## Runtime navigation for the warpack. The ravine is a height field studded with
## rocks, walls, pillars and the fold, so a NavigationMesh is baked once from the
## world's static colliders and every wolverine follows real paths on it. Until
## the bake completes (or when a goal is unreachable) callers fall back to
## whisker steering, so nothing ever stands still.

const CELL_SIZE := 0.25
const AGENT_RADIUS := 0.5

static var region: NavigationRegion3D
static var baked := false
static var _baking := false


static func is_ready() -> bool:
	return baked and is_instance_valid(region) and region.is_inside_tree()


## Bakes the mesh for the tree `host` lives in, once. Safe to call every frame.
static func ensure(host: Node) -> void:
	if _baking or is_ready():
		return
	if is_instance_valid(region) and region.is_inside_tree():
		return
	var parent := host.get_parent()
	if parent == null:
		return
	baked = false
	_baking = true
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL_SIZE
	mesh.cell_height = 0.25
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = 1.25
	mesh.agent_max_climb = 0.5
	mesh.agent_max_slope = 42.0
	mesh.region_min_size = 4.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, parent)
	if not source.has_data():
		_baking = false
		return
	var node := NavigationRegion3D.new()
	node.name = "WarpackNavigation"
	parent.add_child(node)
	region = node
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, func() -> void:
		_baking = false
		if is_instance_valid(node):
			node.navigation_mesh = mesh
			baked = true)


## Waypoints from `from` to `to` on the mesh, or an empty array when the mesh is
## not ready or the goal cannot be reached (the last waypoint is >3 m from it).
static func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_ready():
		return PackedVector3Array()
	var map := region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array()
	var waypoints := NavigationServer3D.map_get_path(map, from, to, true)
	if waypoints.size() < 2:
		return PackedVector3Array()
	var end := waypoints[waypoints.size() - 1]
	if Vector2(end.x - to.x, end.z - to.z).length() > 3.0:
		return PackedVector3Array()
	return waypoints


## Nearest walkable point to `point` within the mesh, or `point` itself.
static func snap(point: Vector3) -> Vector3:
	if not is_ready():
		return point
	return NavigationServer3D.map_get_closest_point(region.get_navigation_map(), point)


## True if `point` lies on (or within `tolerance` of) the mesh.
static func walkable(point: Vector3, tolerance := 0.6) -> bool:
	if not is_ready():
		return true
	return Vector2(snap(point).x - point.x, snap(point).z - point.z).length() < tolerance
