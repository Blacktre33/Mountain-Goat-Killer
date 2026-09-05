"""Build the Widowpine fold and Carrion Cut mother-bell hero slices.

The two generated Blender files are editable source assets. Their GLBs are
metric-scale Godot imports; their PNGs are repeatable composition checks.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector, noise


ROOT = Path(__file__).resolve().parents[2]
TEXTURES = ROOT / "assets/materials/polyhaven"

WIDOW_BLEND = ROOT / "art_source/biomes/widowpine_broken_fold.blend"
WIDOW_GLB = ROOT / "assets/environment/widowpine/widowpine_broken_fold.glb"
WIDOW_PREVIEW = ROOT / "art_direction/widowpine/widowpine-broken-fold-blockout-v1.png"

CARRION_BLEND = ROOT / "art_source/biomes/carrion_cut_mother_bell.blend"
CARRION_GLB = ROOT / "assets/environment/carrion_cut/carrion_cut_mother_bell.glb"
CARRION_PREVIEW = ROOT / "art_direction/carrion_cut/carrion-cut-mother-bell-blockout-v1.png"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    roughness: float = 0.8,
    metallic: float = 0.0,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_pbr(
    mat: bpy.types.Material,
    texture_set: str,
    *,
    uv_scale: float,
    normal_strength: float,
    use_diffuse: bool = True,
) -> None:
    directory = TEXTURES / texture_set
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    diffuse = None
    if use_diffuse:
        diffuse = nodes.new("ShaderNodeTexImage")
        diffuse.image = bpy.data.images.load(str(directory / f"{texture_set}_Diffuse.jpg"), check_existing=True)
    rough = nodes.new("ShaderNodeTexImage")
    rough.image = bpy.data.images.load(str(directory / f"{texture_set}_Rough.jpg"), check_existing=True)
    rough.image.colorspace_settings.name = "Non-Color"
    normal_texture = nodes.new("ShaderNodeTexImage")
    normal_texture.image = bpy.data.images.load(str(directory / f"{texture_set}_nor_gl.jpg"), check_existing=True)
    normal_texture.image.colorspace_settings.name = "Non-Color"
    textures = [rough, normal_texture]
    if diffuse is not None:
        textures.append(diffuse)
    for node in textures:
        links.new(mapping.outputs["Vector"], node.inputs["Vector"])
    if diffuse is not None:
        links.new(diffuse.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = normal_strength
    links.new(normal_texture.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])


def assign(obj: bpy.types.Object, mat: bpy.types.Material | None) -> None:
    if mat is not None and hasattr(obj.data, "materials"):
        obj.data.materials.append(mat)


def bevel(obj: bpy.types.Object, width: float = 0.08, segments: int = 2) -> None:
    modifier = obj.modifiers.new("Worn edges", "BEVEL")
    modifier.width = width
    modifier.segments = segments


def cube(
    name: str,
    location: tuple[float, float, float],
    size: tuple[float, float, float],
    mat: bpy.types.Material | None,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    edge: float = 0.06,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = Vector(size) * 0.5
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    if edge:
        bevel(obj, edge)
    return obj


def snow_patch(
    name: str,
    location: tuple[float, float, float],
    size: tuple[float, float],
    mat: bpy.types.Material,
    rng: random.Random,
    *,
    points: int = 16,
) -> bpy.types.Object:
    """Make a thin, irregular snow scab instead of a rectangular game slab."""
    verts = [(0.0, 0.0, 0.0)]
    uvs = [(0.5, 0.5)]
    for index in range(points):
        angle = math.tau * index / points
        radial = rng.uniform(0.78, 1.14)
        x = math.cos(angle) * size[0] * 0.5 * radial
        y = math.sin(angle) * size[1] * 0.5 * radial
        verts.append((x, y, rng.uniform(-0.012, 0.018)))
        uvs.append((0.5 + x / size[0], 0.5 + y / size[1]))
    faces = [(0, index + 1, (index + 1) % points + 1) for index in range(points)]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    assign(obj, mat)
    return obj


def fractured_slab(
    name: str,
    location: tuple[float, float, float],
    size: tuple[float, float, float],
    mat: bpy.types.Material,
    rng: random.Random,
    *,
    rotation_z: float = 0.0,
    corners: int = 8,
) -> bpy.types.Object:
    """An uneven paving fragment with a real broken perimeter and worn rim."""
    width, depth, height = size
    verts: list[tuple[float, float, float]] = []
    perimeter: list[tuple[float, float]] = []
    for corner in range(corners):
        angle = math.tau * corner / corners
        radial = rng.uniform(0.82, 1.14)
        perimeter.append((math.cos(angle) * width * 0.5 * radial, math.sin(angle) * depth * 0.5 * radial))
    for z in (-height * 0.5, height * 0.5):
        for x, y in perimeter:
            verts.append((x, y, z + rng.uniform(-0.025, 0.025)))
    faces: list[tuple[int, ...]] = []
    faces.append(tuple(range(corners - 1, -1, -1)))
    faces.append(tuple(range(corners, corners * 2)))
    for corner in range(corners):
        following = (corner + 1) % corners
        faces.append((corner, following, corners + following, corners + corner))
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler.z = rotation_z
    assign(obj, mat)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(62.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    bevel(obj, min(0.055, height * 0.18), segments=2)
    return obj


def cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 12,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    bevel(obj, 0.045)
    return obj


def beam(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    radius: float,
    mat: bpy.types.Material,
    *,
    vertices: int = 8,
) -> bpy.types.Object:
    a, b = Vector(start), Vector(end)
    direction = b - a
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=direction.length,
        location=(a + b) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    assign(obj, mat)
    return obj


def rock(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    *,
    subdivisions: int = 1,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    bevel(obj, 0.04)
    if subdivisions > 1:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def leaf_blade(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """A narrow pointed bellthorn leaf, readable without a blob silhouette."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=4,
        radius1=0.5,
        radius2=0.025,
        depth=1.0,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    bevel(obj, 0.018, segments=1)
    return obj


def natural_rock(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    *,
    seed: int,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    offset = Vector((seed * 0.067, seed * -0.041, seed * 0.025))
    for vertex in obj.data.vertices:
        point = vertex.co.copy()
        direction = point.normalized()
        coarse = noise.noise_vector(point * 0.46 + offset, noise_basis="PERLIN_NEW")
        detail = noise.noise_vector(point * 1.15 - offset, noise_basis="PERLIN_NEW")
        strata = math.sin((point.z + seed * 0.07) * 2.2) * 0.11
        vertex.co += direction * (coarse.x * 0.42 + detail.y * 0.14 + strata)
    assign(obj, mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(58.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    bevel_modifier = obj.modifiers.new("Strata fracture edges", "BEVEL")
    bevel_modifier.width = 0.055
    bevel_modifier.segments = 2
    bevel_modifier.limit_method = "ANGLE"
    bevel_modifier.angle_limit = math.radians(36.0)
    bpy.ops.object.modifier_apply(modifier=bevel_modifier.name)
    return obj


def collision_box(name: str, location: tuple[float, float, float], size: tuple[float, float, float]) -> None:
    proxy = cube(f"{name}-colonly", location, size, None, edge=0.0)
    proxy.hide_render = True
    proxy.display_type = "WIRE"


def collision_wall(
    name: str,
    start: tuple[float, float],
    end: tuple[float, float],
    height: float,
    *,
    base_z: tuple[float, float] = (0.0, 0.0),
    thickness: float = 1.0,
) -> None:
    a, b = Vector((*start, 0.0)), Vector((*end, 0.0))
    direction = b - a
    middle = a.lerp(b, 0.5)
    proxy = cube(
        f"{name}-colonly",
        (middle.x, middle.y, (base_z[0] + base_z[1]) * 0.5 + height * 0.5),
        (direction.length, thickness, height),
        None,
        rotation=(0.0, 0.0, math.atan2(direction.y, direction.x)),
        edge=0.0,
    )
    proxy.hide_render = True
    proxy.display_type = "WIRE"


def low_wall(
    prefix: str,
    start: tuple[float, float],
    end: tuple[float, float],
    height: float,
    stone: bpy.types.Material,
    snow: bpy.types.Material,
    rng: random.Random,
    *,
    gap: tuple[float, float] | None = None,
    base_z: tuple[float, float] = (0.0, 0.0),
) -> None:
    a, b = Vector((*start, 0.0)), Vector((*end, 0.0))
    direction = b - a
    length = direction.length
    heading = math.atan2(direction.y, direction.x)
    unit = direction.normalized()
    courses = max(2, int(height / 0.52))
    for course in range(courses):
        cursor = -0.35 if course % 2 else 0.0
        block_index = 0
        while cursor < length:
            width = rng.uniform(0.82, 1.45)
            middle = min(length, cursor + width * 0.5)
            ratio = middle / length
            if gap is None or not (gap[0] <= ratio <= gap[1]):
                pos = a + unit * middle
                floor_z = base_z[0] + (base_z[1] - base_z[0]) * ratio
                z = floor_z + 0.28 + course * 0.5 + rng.uniform(-0.035, 0.035)
                cube(
                    f"{prefix}_stone_{course}_{block_index:02d}",
                    (pos.x, pos.y, z),
                    (width - 0.035, rng.uniform(0.66, 0.82), 0.5),
                    stone,
                    rotation=(0.0, 0.0, heading + rng.uniform(-0.035, 0.035)),
                    edge=0.045,
                )
            cursor += width
            block_index += 1
    for i in range(max(2, int(length / 2.4))):
        ratio = (i + 0.5) / max(1, int(length / 2.4))
        if gap is not None and gap[0] <= ratio <= gap[1]:
            continue
        pos = a.lerp(b, ratio)
        floor_z = base_z[0] + (base_z[1] - base_z[0]) * ratio
        crust = snow_patch(
            f"{prefix}_snow_{i:02d}",
            (pos.x, pos.y, floor_z + courses * 0.5 + 0.08),
            (rng.uniform(1.4, 2.25), rng.uniform(0.42, 0.7)),
            snow,
            rng,
            points=10,
        )
        crust.rotation_euler.z = heading + rng.uniform(-0.05, 0.05)


def lantern(prefix: str, at: tuple[float, float, float], timber: bpy.types.Material, iron: bpy.types.Material, warm: bpy.types.Material) -> None:
    x, y, z = at
    beam(f"{prefix}_post", (x, y, z), (x, y, z + 2.7), 0.11, timber)
    beam(f"{prefix}_crook", (x, y, z + 2.55), (x + 0.55, y, z + 2.8), 0.08, iron)
    cube(f"{prefix}_cage", (x + 0.58, y, z + 2.25), (0.42, 0.42, 0.62), iron, edge=0.025)
    cube(f"{prefix}_ember", (x + 0.58, y - 0.22, z + 2.25), (0.23, 0.035, 0.32), warm, edge=0.015)


def setup_render(path: Path, camera_at: tuple[float, float, float], target: tuple[float, float, float], *, warm_fill: bool = False) -> None:
    world = bpy.data.worlds.new("Moonlit ravine")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.009, 0.02, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    bpy.context.scene.world = world

    moon_data = bpy.data.lights.new("Moon", "SUN")
    moon_data.energy = 3.0
    moon_data.color = (0.3, 0.46, 0.75)
    moon_data.angle = math.radians(10)
    moon = bpy.data.objects.new("Moon", moon_data)
    bpy.context.collection.objects.link(moon)
    moon.rotation_euler = (math.radians(38), math.radians(-28), math.radians(-24))

    fill_data = bpy.data.lights.new("Cold fill", "AREA")
    fill_data.energy = 1800
    fill_data.shape = "DISK"
    fill_data.size = 18
    fill_data.color = (0.24, 0.34, 0.62) if not warm_fill else (0.55, 0.2, 0.12)
    fill = bpy.data.objects.new("Cold fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (-11, -5, 18)
    point_at(fill, target)

    camera_data = bpy.data.cameras.new("PlayerRevealCamera")
    camera_data.lens = 27
    camera_data.sensor_width = 36
    camera = bpy.data.objects.new("PlayerRevealCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = camera_at
    point_at(camera, target)
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1536
    scene.render.resolution_y = 864
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    scene.view_settings.look = "AgX - Medium High Contrast"


def point_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def create_shared_materials() -> dict[str, bpy.types.Material]:
    stone = material("Widowpine dark fieldstone", (0.11, 0.13, 0.15, 1), roughness=0.94)
    timber = material("Black weathered timber", (0.055, 0.034, 0.024, 1), roughness=0.95)
    iron = material("Old black iron", (0.018, 0.022, 0.026, 1), roughness=0.62, metallic=0.78)
    add_pbr(stone, "dark_rock", uv_scale=1.85, normal_strength=0.68)
    add_pbr(timber, "weathered_planks", uv_scale=2.2, normal_strength=0.42)
    snow = material("Blue crusted snow", (0.27, 0.34, 0.42, 1), roughness=0.84)
    add_pbr(snow, "snow_04", uv_scale=2.8, normal_strength=0.34)
    shadow = material("Deep ravine shadow", (0.006, 0.01, 0.017, 1), roughness=0.96)
    old_red = material("Dried bellthorn red", (0.18, 0.003, 0.007, 1), roughness=0.94)
    blood = material("Old iron-dark blood", (0.075, 0.001, 0.001, 1), roughness=0.98)
    warm = material(
        "Lantern ember",
        (0.52, 0.08, 0.006, 1),
        roughness=0.32,
        emission=(1.0, 0.22, 0.02, 1),
        emission_strength=7.0,
    )
    bell = material("Mother Bell bronze", (0.16, 0.075, 0.025, 1), roughness=0.34, metallic=0.9)
    return {
        "stone": stone,
        "timber": timber,
        "iron": iron,
        "snow": snow,
        "shadow": shadow,
        "old_red": old_red,
        "blood": blood,
        "warm": warm,
        "bell": bell,
    }


def build_widowpine() -> None:
    rng = random.Random(3107)
    mats = create_shared_materials()
    stone, timber, iron, snow = mats["stone"], mats["timber"], mats["iron"], mats["snow"]
    root_wood = material("Wet exposed pine roots", (0.035, 0.021, 0.015, 1), roughness=0.98)
    add_pbr(root_wood, "weathered_planks", uv_scale=1.8, normal_strength=0.56)
    hide = material("Warpack smoke-black hide", (0.045, 0.018, 0.014, 1), roughness=0.96)
    old_ice = material("Trough black ice", (0.018, 0.055, 0.085, 1), roughness=0.18, metallic=0.08)

    def ground(local_y: float) -> float:
        """Measured fit to WorldBuilder around the fold root at world z=11."""
        return 0.15 + min(1.0, max(0.0, (local_y - 3.0) / 19.0)) * 1.07

    # The fold follows the forest contour in ten short, broken runs. This
    # replaces the rectangular pen with an enclosure that could have grown by
    # hand over generations while preserving a broad central infiltration lane.
    wall_specs = (
        ("FoldMouthWest", (-11.2, 3.2), (-5.25, 3.55), 1.15),
        ("FoldMouthEast", (5.1, 3.55), (11.0, 3.15), 1.05),
        ("FoldWestFront", (-11.2, 3.2), (-10.55, 9.4), 1.25),
        ("FoldWestMiddle", (-10.55, 9.4), (-9.15, 15.35), 1.62),
        ("FoldWestRear", (-9.15, 15.35), (-6.75, 20.75), 1.82),
        ("FoldEastFront", (11.0, 3.15), (10.25, 8.7), 1.12),
        ("FoldEastBroken", (10.25, 8.7), (9.55, 11.9), 1.45),
        ("FoldEastRear", (9.15, 14.45), (7.15, 20.65), 1.7),
        ("FoldBackWest", (-6.75, 20.75), (-2.35, 22.0), 1.9),
        ("FoldBackEast", (2.7, 22.0), (7.15, 20.65), 1.72),
    )
    for prefix, start, end, height in wall_specs:
        base = (ground(start[1]), ground(end[1]))
        low_wall(prefix, start, end, height, stone, snow, rng, base_z=base)
        collision_wall(prefix, start, end, height, base_z=base, thickness=0.95)

    # The playable wet trail is generated against the exact Godot height field.
    # Keeping it out of the GLB prevents coplanar highlights from turning the
    # intended black slush into a row of pale stepping stones.
    for index in range(14):
        side = -1 if index % 2 == 0 else 1
        y = -1.0 + index * 1.45
        x = side * rng.uniform(3.4, 7.4)
        z = ground(y) + 0.09
        beam(
            f"FoldTwig_{index:02d}",
            (x - 0.28, y - 0.12, z),
            (x + 0.34, y + 0.18, z + 0.05),
            0.022,
            root_wood,
            vertices=6,
        )

    # A broken timber throat survives at the mouth, small enough to feel human-
    # made and wide enough to avoid reading as a generic game gate.
    entry_y = 4.15
    entry_z = ground(entry_y)
    beam("FoldEntry_left", (-4.85, entry_y, entry_z), (-4.68, entry_y, entry_z + 2.48), 0.19, root_wood)
    beam("FoldEntry_right", (4.8, entry_y, entry_z), (4.62, entry_y, entry_z + 2.18), 0.19, root_wood)
    beam("FoldEntry_split_timber", (-4.7, entry_y, entry_z + 2.4), (-3.15, entry_y + 0.18, entry_z + 1.35), 0.15, root_wood)
    beam("FoldEntry_fallen_lintel", (1.55, entry_y + 0.2, entry_z + 0.14), (4.45, entry_y + 1.0, entry_z + 0.23), 0.16, root_wood)
    for post_x in (-4.85, 4.8):
        natural_rock(f"FoldEntryFoot_{post_x}", (post_x, entry_y, entry_z + 0.2), (0.62, 0.55, 0.42), stone, seed=500 + int(post_x * 10))

    # Nine empty chains are the first story object the player reads. Raising the
    # rack by the measured rear terrain height keeps every missing name visible.
    rack_y = 19.35
    rack_z = ground(rack_y)
    beam("NameRack_left", (-4.45, rack_y, rack_z), (-4.15, rack_y, rack_z + 5.0), 0.22, root_wood)
    beam("NameRack_right", (4.35, rack_y, rack_z), (4.05, rack_y, rack_z + 4.82), 0.22, root_wood)
    beam("NameRack_cross_left", (-4.2, rack_y, rack_z + 4.62), (0.15, rack_y, rack_z + 4.82), 0.18, root_wood)
    beam("NameRack_cross_right", (0.15, rack_y, rack_z + 4.82), (4.08, rack_y, rack_z + 4.48), 0.18, root_wood)
    beam("NameRack_iron_spine", (-3.95, rack_y - 0.07, rack_z + 4.28), (3.85, rack_y - 0.07, rack_z + 4.22), 0.055, iron, vertices=8)
    for i in range(9):
        x = -3.55 + i * 0.88
        chain_top = rack_z + 4.25 + math.sin(i * 1.7) * 0.04
        chain_bottom = rack_z + 3.05 + 0.14 * (i % 3)
        beam(f"EmptyNameChain_{i:02d}", (x, rack_y - 0.08, chain_top), (x, rack_y - 0.08, chain_bottom), 0.026, iron, vertices=6)
        cylinder(f"EmptyNameClasp_{i:02d}", (x, rack_y - 0.08, chain_bottom - 0.08), 0.13, 0.2, iron, vertices=10)
    cube("NameRack_torn_memorial", (0.25, rack_y - 0.13, rack_z + 2.7), (0.7, 0.045, 1.35), hide, rotation=(0.0, 0.0, 0.08), edge=0.018)

    # A stone trough assembled from separate worn blocks keeps the water line
    # and wall thickness legible instead of reading as one rectangular box.
    trough_x, trough_y = -5.7, 9.2
    trough_z = ground(trough_y)
    for side in (-1, 1):
        cube(
            f"IceTrough_side_{side}",
            (trough_x, trough_y + side * 0.78, trough_z + 0.46),
            (5.0, 0.34, 0.88),
            stone,
            rotation=(0.0, 0.0, side * 0.018),
            edge=0.13,
        )
    for side in (-1, 1):
        cube(f"IceTrough_end_{side}", (trough_x + side * 2.35, trough_y, trough_z + 0.52), (0.42, 1.8, 1.05), stone, rotation=(0.0, 0.0, side * 0.025), edge=0.12)
    cube("IceTrough_black_ice", (trough_x, trough_y, trough_z + 0.5), (4.45, 1.28, 0.08), old_ice, edge=0.025)
    snow_patch("IceTrough_snow", (trough_x - 0.7, trough_y + 0.78, trough_z + 0.93), (2.8, 0.42), snow, rng, points=11)
    collision_box("IceTrough", (trough_x, trough_y, trough_z + 0.55), (5.1, 2.0, 1.1))

    # Varkas' only shelter is a low, collapsed addition leaning against the
    # east wall. Smoke-black hide dominates; two old red seams imply its use.
    shelter_front_y, shelter_back_y = 10.2, 15.45
    front_z, back_z = ground(shelter_front_y), ground(shelter_back_y)
    for x in (5.15, 8.55):
        beam("OccupationShelter_front", (x, shelter_front_y, front_z), (x, shelter_front_y, front_z + 2.68), 0.13, root_wood)
        beam("OccupationShelter_back", (x, shelter_back_y, back_z), (x, shelter_back_y, back_z + 1.82), 0.13, root_wood)
    beam("OccupationShelter_ridge", (6.85, shelter_front_y, front_z + 2.88), (6.85, shelter_back_y, back_z + 2.08), 0.14, root_wood)
    for rafter in range(5):
        x = 5.15 + rafter * 0.85
        beam(f"OccupationShelter_rafter_{rafter}", (x, shelter_front_y, front_z + 2.52), (x + rng.uniform(-0.15, 0.15), shelter_back_y, back_z + 1.75), 0.075, root_wood)
    for panel in range(5):
        cube(
            f"OccupationShelter_hide_{panel:02d}",
            (5.15 + panel * 0.82, 12.82, front_z + 2.3 - panel * 0.035),
            (0.78, 5.45, 0.065),
            hide,
            rotation=(-0.11, rng.uniform(-0.02, 0.02), -0.045 + panel * 0.018),
            edge=0.016,
        )
    beam("OccupationShelter_collapse", (8.65, 11.0, front_z + 2.28), (5.4, 15.2, back_z + 0.35), 0.12, root_wood)
    for seam, x in enumerate((5.92, 8.28)):
        beam(
            f"OccupationShelter_old_seam_{seam}",
            (x, shelter_front_y + 0.35, front_z + 2.35),
            (x - 0.08, shelter_back_y - 0.45, back_z + 1.72),
            0.018,
            mats["blood"],
            vertices=6,
        )

    # The inactive fire, narrow drag evidence, and a handful of bones remain
    # story clues rather than a decorative gore carpet.
    fire_y = 11.4
    fire_z = ground(fire_y)
    for i in range(11):
        angle = math.tau * i / 11
        natural_rock(
            f"FireRing_{i:02d}",
            (math.cos(angle) * 1.05, fire_y + math.sin(angle) * 0.72, fire_z + 0.16),
            (0.26, 0.21, 0.18),
            stone,
            seed=800 + i * 19,
        )
    snow_patch("ColdAsh", (0.0, fire_y, fire_z + 0.08), (1.55, 1.0), mats["shadow"], rng, points=13)
    for i in range(4):
        y = 5.55 + i * 1.38
        snow_patch(
            f"OldDragMark_{i:02d}",
            (-0.52 + math.sin(i * 1.3) * 0.22, y, ground(y) + 0.045),
            (0.48, 1.72),
            mats["blood"],
            rng,
            points=10,
        )
    for i in range(6):
        y = 8.65 + math.sin(i * 1.7) * 0.48
        z = ground(y) + 0.13
        beam(
            f"OldBone_{i:02d}",
            (-1.7 + i * 0.42, y, z),
            (-1.4 + i * 0.42, y + 0.18, z + 0.1),
            0.034,
            snow,
            vertices=6,
        )

    # One fallen pine binds the masonry to the forest and creates meaningful
    # left-flank cover. Its roots reach over, rather than through, the lane.
    beam("FallenPine_trunk", (-9.6, 7.1, ground(7.1) + 0.72), (-6.4, 15.9, ground(15.9) + 1.2), 0.42, root_wood, vertices=12)
    for branch, end in enumerate(((-4.9, 13.4, 2.15), (-8.7, 17.0, 2.55), (-5.8, 10.2, 2.4), (-10.2, 12.9, 2.7))):
        start_y = 10.1 + branch * 1.15
        beam(f"FallenPine_branch_{branch}", (-8.45 + branch * 0.42, start_y, ground(start_y) + 1.05), end, 0.095, root_wood, vertices=8)
    for root_index, end in enumerate(((-11.2, 6.5, 0.35), (-10.8, 8.1, 0.3), (-8.9, 5.8, 0.28))):
        beam(f"FallenPine_root_{root_index}", (-9.55, 7.1, ground(7.1) + 0.65), end, 0.1, root_wood, vertices=8)

    # Two close, fully modelled snags give the fold real trunk and root mass in
    # the player camera. The distant vegetation cards can now supply canopy and
    # parallax without having to carry every foreground silhouette.
    snag_specs = ((-10.7, -1.8, 10.8, -0.42), (10.4, -0.7, 8.7, 0.35))
    for snag, (x, y, height, lean) in enumerate(snag_specs):
        z = ground(y)
        crown = (x + lean, y + 0.18, z + height)
        beam(f"ForegroundSnag_{snag}_trunk", (x, y, z - 0.12), crown, 0.48 if snag == 0 else 0.42, root_wood, vertices=12)
        for root_index in range(5):
            angle = math.tau * root_index / 5.0 + snag * 0.4
            reach = 1.25 + rng.uniform(-0.18, 0.3)
            end = (x + math.cos(angle) * reach, y + math.sin(angle) * reach, ground(y + math.sin(angle) * reach) + 0.05)
            beam(f"ForegroundSnag_{snag}_root_{root_index}", (x, y, z + 0.32), end, 0.085, root_wood, vertices=8)
        for branch_index, direction in enumerate((-1.0, 1.0, -1.0)):
            branch_z = z + height * (0.56 + branch_index * 0.12)
            start = (x + lean * (branch_z - z) / height, y + 0.18, branch_z)
            end = (start[0] + direction * (1.2 - branch_index * 0.18), y + 0.3 + branch_index * 0.22, branch_z + 0.52)
            beam(f"ForegroundSnag_{snag}_branch_{branch_index}", start, end, 0.08, root_wood, vertices=8)

    # Dormant bellthorn stays rare and low in this first biome.
    for group, (x, y, direction) in enumerate(((-8.2, 17.2, -1.0), (8.45, 7.25, 1.0))):
        z = ground(y) + 0.08
        beam(f"DormantBellthornRoot_{group}", (x, y, z), (x + direction * 0.65, y + 0.9, z + 0.42), 0.045, mats["old_red"], vertices=7)
        for leaf in range(3):
            leaf_blade(
                f"DormantBellthornLeaf_{group}_{leaf}",
                (x + direction * (0.18 + leaf * 0.18), y + 0.35 + leaf * 0.2, z + 0.22 + leaf * 0.16),
                (0.18, 0.08, 0.38),
                mats["old_red"],
                rotation=(rng.uniform(-0.3, 0.3), direction * rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4)),
            )

    for i, (x, y) in enumerate(((-7.8, 5.3), (7.8, 6.0), (-7.75, 18.0))):
        lantern(f"FoldLantern_{i}", (x, y, ground(y)), timber, iron, mats["warm"])
    boundary_specs = ((-12.7, 6.8, 1.25), (12.65, 12.6, 1.18), (-12.35, 20.7, 1.12), (12.4, 20.0, 1.22), (-10.8, 23.0, 0.9))
    for i, (x, y, scale) in enumerate(boundary_specs):
        natural_rock(
            f"FoldBoundaryCrag_{i}",
            (x, y, ground(y) + 0.78 * scale),
            (1.55 * scale, 1.15 * scale, 1.45 * scale),
            stone,
            seed=1000 + i * 43,
        )

    setup_render(WIDOW_PREVIEW, (0.0, -10.5, 2.25), (0.0, 15.0, 2.75))
    bpy.context.scene["production_target"] = "art_direction/widowpine/widowpine-target-v1.png"
    bpy.context.scene["design_intent"] = "The Ironhorn family fold after Varkas' first raid"
    save_render_export(WIDOW_BLEND, WIDOW_GLB, WIDOW_PREVIEW)


def build_carrion() -> None:
    rng = random.Random(771)
    mats = create_shared_materials()
    stone, timber, iron, snow = mats["stone"], mats["timber"], mats["iron"], mats["snow"]
    red_rock = material("Carrion ironstone", (0.12, 0.025, 0.02, 1), roughness=0.92)
    add_pbr(red_rock, "dark_rock", uv_scale=1.55, normal_strength=0.68, use_diffuse=False)
    ancient = material("Mother shrine pale limestone", (0.24, 0.25, 0.26, 1), roughness=0.96)
    add_pbr(ancient, "stone_wall_05", uv_scale=3.8, normal_strength=0.62, use_diffuse=True)
    ancient_dark = material("Mother shrine rain-dark limestone", (0.12, 0.13, 0.15, 1), roughness=0.98)
    add_pbr(ancient_dark, "stone_wall_05", uv_scale=4.1, normal_strength=0.7, use_diffuse=False)
    cut = material("Rain-black shrine cuts", (0.018, 0.017, 0.016, 1), roughness=0.99)

    # The procession is a repaired sacred road, not a stack of game slabs.
    # Broad invisible collision keeps the climb forgiving; fractured visible
    # tread stones and small snow scabs carry the silhouette.
    for segment in range(7):
        y = -8.45 - segment * 1.28
        local_ground = -1.22 - segment * 0.082
        lanes = 2 if segment in (1, 5) else 3
        spacing = 3.2 if lanes == 2 else 2.35
        for lane in range(lanes):
            x = (lane - (lanes - 1) * 0.5) * spacing + rng.uniform(-0.48, 0.48)
            fractured_slab(
                f"ProcessionalRoad_{segment:02d}_{lane}",
                (x, y + rng.uniform(-0.18, 0.18), local_ground + 0.08),
                (rng.uniform(1.75, 2.75), rng.uniform(1.05, 1.62), rng.uniform(0.15, 0.24)),
                red_rock if (segment + lane) % 3 else ancient_dark,
                rng,
                rotation_z=rng.uniform(-0.16, 0.16),
                corners=rng.choice((7, 8, 9)),
            )
        if segment in (1, 3, 6):
            snow_patch(
                f"ProcessionalRoadSnow_{segment:02d}",
                (rng.uniform(-1.8, 1.8), y - 0.08, local_ground + 0.22),
                (rng.uniform(1.5, 2.5), rng.uniform(0.62, 0.9)),
                snow,
                rng,
                points=11,
            )
    for i in range(8):
        y = -7.0 + i * 0.86
        # Measured against WorldBuilder.height_at(): the ravine is 1.13 m lower
        # at the foot of the shrine than at its origin.
        z = -1.28 + i * 0.31
        width = 6.8 + i * 0.32
        cube(f"MotherBellStep_{i:02d}-colonly", (0.0, y, z), (width + 0.7, 1.02, 0.34 + i * 0.12), None, edge=0.0)
        shards = 4 if i not in (1, 6) else 3
        cursor = -width * 0.5
        for shard in range(shards):
            remaining = width * 0.5 - cursor
            shard_width = remaining if shard == shards - 1 else min(remaining, width / shards * rng.uniform(0.78, 1.18))
            gap = rng.uniform(0.045, 0.12)
            visual_width = max(0.72, shard_width - gap)
            x = cursor + shard_width * 0.5
            fractured_slab(
                f"ProcessionalTread_{i:02d}_{shard}",
                (x, y + rng.uniform(-0.055, 0.055), z + 0.045),
                (visual_width, 0.92, 0.38 + i * 0.12),
                red_rock if (i + shard) % 4 else ancient,
                rng,
                rotation_z=rng.uniform(-0.045, 0.045),
                corners=rng.choice((7, 8, 9)),
            )
            cursor += shard_width
        for patch in range(2):
            patch_width = width * rng.uniform(0.18, 0.34)
            snow_x = rng.uniform(-width * 0.32, width * 0.32)
            snow_patch(
                f"MotherBellStepSnow_{i:02d}_{patch}",
                (snow_x, y - 0.12 + rng.uniform(-0.05, 0.05), z + 0.255 + i * 0.06),
                (patch_width, rng.uniform(0.28, 0.48)),
                snow,
                rng,
                points=10,
            )

    cube("MotherBellDais-colonly", (0.0, 2.25, 0.72), (12.0, 8.0, 1.45), None, edge=0.0)
    # Large irregular plates break the dais edge and keep its center open.
    for row in range(3):
        y = -0.05 + row * 2.2
        for lane in range(4):
            x = -4.35 + lane * 2.9 + rng.uniform(-0.18, 0.18)
            cube(
                f"DaisPlate_{row}_{lane}",
                (x, y, 1.28 + rng.uniform(-0.08, 0.05)),
                (rng.uniform(2.55, 3.15), rng.uniform(2.0, 2.35), rng.uniform(0.52, 0.72)),
                ancient_dark if (row + lane) % 5 == 0 else (ancient if (row + lane) % 3 else red_rock),
                rotation=(rng.uniform(-0.018, 0.018), rng.uniform(-0.025, 0.025), rng.uniform(-0.035, 0.035)),
                edge=0.1,
            )
    for patch_index, (x, y, width, depth) in enumerate(((-3.8, 0.2, 2.8, 1.1), (3.15, 2.5, 3.2, 1.25), (-0.8, 4.45, 2.1, 0.9))):
        snow_patch(f"MotherBellDaisSnow_{patch_index}", (x, y, 1.67), (width, depth), snow, rng)

    # An old apse widens behind the bell. Its broken wings make the monument
    # feel excavated from the ravine instead of dropped onto a platform.
    low_wall("ShrineApseWest", (-4.6, 4.25), (-9.0, 7.6), 2.15, ancient, snow, rng)
    low_wall("ShrineApseEast", (4.6, 4.25), (8.2, 6.8), 1.55, ancient, snow, rng, gap=(0.54, 0.78))
    collision_box("ShrineApseWest", (-6.8, 5.9, 1.05), (6.1, 1.4, 2.2))
    collision_box("ShrineApseEast", (6.4, 5.45, 0.78), (4.9, 1.25, 1.6))

    # Tapered, scarred piers and a segmented processional arch replace the old
    # symmetrical towers-and-lintel blockout. The right crown is deliberately
    # broken, leaving one surviving horn against the sky.
    for side in (-1, 1):
        x = side * 3.55
        courses = 11 if side < 0 else 10
        for course in range(courses):
            lanes = 3 if course < 5 else 2
            course_width = 2.85 - course * 0.075
            block_width = course_width / lanes
            for lane in range(lanes):
                offset = -course_width * 0.5 + block_width * (lane + 0.5)
                stagger = (0.13 if course % 2 else -0.08) * side
                cube(
                    f"BellPier_{'L' if side < 0 else 'R'}_{course:02d}_{lane}",
                    (x + offset + stagger, 2.15 + rng.uniform(-0.11, 0.11), 1.82 + course * 0.55),
                    (block_width - 0.045, rng.uniform(1.65, 1.92), 0.58),
                    ancient_dark if (course + lane + (1 if side > 0 else 0)) % 7 == 0 else ancient,
                    rotation=(rng.uniform(-0.012, 0.012), rng.uniform(-0.018, 0.018), rng.uniform(-0.034, 0.034)),
                    edge=0.065,
                )
        # Low outer buttresses make the frame feel load-bearing.
        for buttress in range(4):
            cube(
                f"BellButtress_{side}_{buttress}",
                (side * (4.65 + buttress * 0.18), 2.3, 1.25 + buttress * 0.5),
                (1.25, 2.35, 1.9),
                ancient,
                rotation=(0.0, side * rng.uniform(-0.03, 0.03), side * math.radians(5.0)),
                edge=0.09,
            )
        collision_box(f"BellPier_{side}", (x, 2.1, 4.55), (3.0, 2.15, 7.0))

    arch_center_z = 6.12
    arch_radius = 3.5
    for segment in range(12):
        angle = math.radians(20.0 + segment * 12.7)
        x = math.cos(angle) * arch_radius
        z = arch_center_z + math.sin(angle) * arch_radius
        cube(
            f"ProcessionalArch_{segment:02d}",
            (x, 2.05 + rng.uniform(-0.035, 0.035), z),
            (0.84, 2.05, 0.96),
            ancient_dark if segment in (2, 8) else ancient,
            rotation=(0.0, angle - math.pi * 0.5, rng.uniform(-0.012, 0.012)),
            edge=0.085,
        )
    # Split cap courses visually bind the arch while retaining a broken crown.
    for segment, (x, width, tilt) in enumerate(((-3.25, 2.35, -0.025), (-1.02, 2.1, 0.018), (1.02, 2.0, -0.012), (3.12, 1.82, 0.075))):
        cube(
            f"ArchCapCourse_{segment}",
            (x, 2.08, 9.82 + abs(tilt) * 1.4),
            (width, 2.18, 0.66),
            ancient_dark if segment == 2 else ancient,
            rotation=(0.0, 0.0, tilt),
            edge=0.09,
        )
    for segment, (x, width, tilt) in enumerate(((-2.72, 2.8, 0.018), (0.08, 2.65, -0.025), (2.55, 2.05, 0.052))):
        cube(
            f"ArchCoping_{segment}",
            (x, 2.08, 10.34 + abs(tilt)),
            (width, 1.92, 0.48),
            ancient_dark if segment == 1 else ancient,
            rotation=(0.0, 0.0, tilt),
            edge=0.075,
        )
    beam("SurvivingShrineHorn", (-4.45, 2.1, 8.0), (-5.7, 2.1, 10.15), 0.19, ancient)
    for side in (-1, 1):
        beam("BellYoke", (side * 2.95, 2.0, 7.58), (side * 0.88, 2.0, 7.58), 0.22, timber)

    # Eight rain-black name niches connect this shrine to the bells already
    # recovered by the player without resorting to glowing fantasy runes.
    for index in range(8):
        side = -1 if index < 4 else 1
        row = index if index < 4 else index - 4
        x = side * (3.48 + (0.04 if row % 2 else -0.03))
        z = 2.55 + row * 0.92
        cube(f"MotherNameNiche_{index:02d}", (x, 1.16, z), (0.48, 0.055, 0.58), cut, edge=0.025)
        beam(f"MotherNameSlash_{index:02d}", (x - 0.12, 1.12, z - 0.13), (x + 0.12, 1.12, z + 0.15), 0.026, iron, vertices=6)

    # A layered bronze bell, clapper, name-band, and repaired yoke. MotherBell
    # remains a separate named mesh so the Godot interaction never moves.
    bpy.ops.mesh.primitive_cone_add(vertices=64, radius1=1.5, radius2=0.72, depth=2.05, location=(0.0, 2.0, 5.65))
    bell = bpy.context.object
    bell.name = "MotherBell"
    assign(bell, mats["bell"])
    bevel(bell, 0.065)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.38, minor_radius=0.15, major_segments=64, minor_segments=12, location=(0.0, 2.0, 4.68))
    rim = bpy.context.object
    rim.name = "MotherBell_Rim"
    assign(rim, mats["bell"])
    bpy.ops.mesh.primitive_torus_add(major_radius=1.05, minor_radius=0.055, major_segments=48, minor_segments=8, location=(0.0, 2.0, 5.34))
    assign(bpy.context.object, iron)
    cylinder("MotherBell_Crown", (0.0, 2.0, 6.72), 0.28, 0.5, mats["bell"], vertices=24)
    beam("MotherBell_Clapper", (0.0, 2.0, 5.5), (0.0, 2.0, 4.15), 0.1, iron)
    rock("MotherBell_ClapperHead", (0.0, 2.0, 4.0), (0.24, 0.24, 0.28), iron)

    # Varkas' occupation is deliberately lopsided and visibly younger: one
    # brutal watch shelf, one lower prisoner rail, two hanging cages, and torn
    # hide bolted into the sacred stone.
    for post_x in (-8.35, -6.0):
        beam("OccupationWatch_post", (post_x, 4.15, 0.0), (post_x + 0.12, 4.15, 4.75), 0.15, timber)
    cube("OccupationWatch_deck", (-7.15, 4.15, 3.0), (3.25, 3.2, 0.2), timber, rotation=(0.0, 0.0, -0.035), edge=0.025)
    beam("OccupationWatch_brace", (-8.25, 4.15, 0.2), (-6.15, 4.15, 4.4), 0.105, timber)
    beam("OccupationWatch_rail", (-8.4, 3.0, 4.05), (-5.85, 3.0, 4.05), 0.075, iron, vertices=6)
    for slat in range(5):
        cube(
            f"OccupationHide_{slat}",
            (-8.15 + slat * 0.48, 2.95, 4.42 - 0.12 * (slat % 2)),
            (0.42, 0.055, 1.15 + 0.13 * (slat % 3)),
            mats["blood"] if slat in (1, 4) else mats["old_red"],
            rotation=(0.0, 0.0, rng.uniform(-0.08, 0.08)),
            edge=0.018,
        )
    for cage_index, (cage_x, cage_y, top) in enumerate(((-7.65, 0.15, 6.5), (7.0, 3.8, 5.7))):
        for bar in range(6):
            angle = math.tau * bar / 6
            beam(
                f"HangingCage_{cage_index}_bar",
                (cage_x + math.cos(angle) * 0.62, cage_y + math.sin(angle) * 0.62, 1.2),
                (cage_x + math.cos(angle) * 0.62, cage_y + math.sin(angle) * 0.62, 3.35),
                0.045,
                iron,
                vertices=6,
            )
        cylinder(f"HangingCage_{cage_index}_floor", (cage_x, cage_y, 1.15), 0.72, 0.1, iron, vertices=12)
        beam(f"HangingCage_{cage_index}_chain", (cage_x, cage_y, 3.35), (cage_x, cage_y, top), 0.035, iron, vertices=6)

    # Layered ironstone shelves replace the oversized paired boulders. Their
    # flatter profiles frame the route without reading as two rows of potatoes.
    strata_layout = (
        (-9.2, -5.6, 1.0, 1.0), (-10.1, -2.2, 1.3, 0.86), (-9.4, 1.2, 1.45, 1.08), (-10.4, 4.5, 1.8, 0.82),
        (9.0, -4.7, 1.05, 0.9), (10.2, -0.8, 1.25, 1.02), (9.25, 2.8, 1.55, 0.84), (9.7, 6.0, 1.7, 0.95),
    )
    for i, (x, y, z, scale) in enumerate(strata_layout):
        # The east side sits on the valley floor while the west side climbs the
        # shoulder. Fit those two terrain bands instead of mirroring altitude.
        fitted_z = z + y * 0.05 + (-1.35 if x > 0 else 0.0)
        for layer in range(3):
            cube(
                f"CarrionShelf_{i:02d}_stratum_{layer}",
                (x + rng.uniform(-0.18, 0.18), y + rng.uniform(-0.12, 0.12), fitted_z - 0.48 * scale + layer * 0.42 * scale),
                (rng.uniform(3.25, 4.25) * scale, rng.uniform(1.0, 1.35) * scale, rng.uniform(0.42, 0.62) * scale),
                red_rock,
                rotation=(rng.uniform(-0.035, 0.035), rng.uniform(-0.045, 0.045), rng.uniform(-0.11, 0.11)),
                edge=0.16,
            )
        shelf = natural_rock(
            f"CarrionShelf_{i:02d}_fracture",
            (x - math.copysign(0.42 * scale, x), y + 0.12, fitted_z - 0.05),
            (1.05 * scale, 0.78 * scale, 0.72 * scale),
            red_rock,
            seed=410 + i * 37,
        )
        shelf.rotation_euler.z = rng.uniform(-0.18, 0.18)
        snow_patch(
            f"CarrionShelfSnow_{i:02d}",
            (x - math.copysign(0.12, x), y - 0.06, fitted_z + 1.02 * scale),
            (2.1 * scale, 0.62 * scale),
            snow,
            rng,
            points=11,
        )

    # Memorials are gathered into two small processional groups rather than
    # scattered as identical waist-high cover blocks.
    memorials = ((-5.55, -2.9, 1.3), (-6.25, -1.9, 0.92), (-5.35, 5.35, 1.08), (5.75, 5.8, 1.18), (6.4, 4.8, 0.86))
    for i, (x, y, scale) in enumerate(memorials):
        fitted_z = -0.62 if x > 0 else 0.0
        cube(
            f"NameStone_{i:02d}",
            (x, y, fitted_z + 1.05 * scale),
            (0.88 * scale, 0.5, 1.9 * scale),
            ancient,
            rotation=(0.0, rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08)),
            edge=0.07,
        )
        cube(f"NameStoneCut_{i:02d}", (x, y - 0.265, fitted_z + 1.15 * scale), (0.38 * scale, 0.04, 0.68 * scale), cut, edge=0.012)

    # A dry, iron-dark drainage rill leads toward the bell. It is old evidence,
    # not a fresh gore trail, and occupies only a narrow strip of the route.
    for i in range(6):
        y = -15.5 + i * 1.42
        local_ground = -1.68 + i * 0.086
        snow_patch(
            f"OldDrainageRill_{i:02d}",
            (-0.3 + math.sin(i * 1.4) * 0.28, y, local_ground + 0.13),
            (0.38 + i * 0.025, 1.75),
            mats["blood"],
            rng,
            points=10,
        )
    for i in range(5):
        x = -0.45 + math.sin(i * 1.7) * 0.32
        y = -6.55 + i * 1.55
        snow_patch(f"OldSacrificeRill_{i:02d}", (x, y, -1.03 + i * 0.57), (0.42 + i * 0.04, 1.85), mats["blood"], rng, points=10)
    for i in range(5):
        beam(
            f"CarrionOldBone_{i:02d}",
            (-5.85 + i * 0.18, -2.5 + math.sin(i) * 0.34, 0.22),
            (-5.55 + i * 0.18, -2.35 + math.sin(i) * 0.34, 0.31),
            0.035,
            snow,
            vertices=6,
        )

    # Bellthorn now grows as roots and pointed leaves, not red sphere clusters.
    bellthorn_groups = ((-4.9, -4.7, 1.0, -1.0), (4.75, -3.7, 0.82, 1.0), (-5.3, 4.9, 1.08, -1.0), (5.9, 5.15, 1.12, 1.0))
    for i, (x, y, scale, direction) in enumerate(bellthorn_groups):
        root_z = 0.18 if y < 0 else 1.55
        beam(f"BellthornRoot_{i}_main", (x, y, root_z), (x + direction * 0.72, y + 1.15, root_z + 1.25 * scale), 0.075, mats["old_red"], vertices=7)
        beam(f"BellthornRoot_{i}_branch", (x + direction * 0.26, y + 0.4, root_z + 0.42), (x - direction * 0.5, y + 0.82, root_z + 0.84 * scale), 0.048, mats["old_red"], vertices=7)
        for leaf in range(5):
            leaf_blade(
                f"BellthornLeaf_{i}_{leaf}",
                (x + direction * (-0.48 + leaf * 0.25) * scale, y + 0.55 + leaf * 0.18, root_z + 0.58 + leaf * 0.28 * scale),
                (0.42 * scale, 0.18, 0.82 * scale),
                mats["old_red"],
                rotation=(rng.uniform(-0.28, 0.28), direction * rng.uniform(-0.42, 0.42), rng.uniform(-0.35, 0.35)),
            )
    for i, at in enumerate(((-5.7, -5.8, 0.0), (5.8, -4.8, 0.0), (-6.2, 6.7, 1.5), (6.3, 7.0, 1.5))):
        lantern(f"CarrionLantern_{i}", at, timber, iron, mats["warm"])

    setup_render(CARRION_PREVIEW, (0.8, -14.8, 2.8), (-0.35, 2.45, 4.7), warm_fill=True)
    bpy.context.scene["production_target"] = "art_direction/carrion_cut/carrion-cut-target-v1.png"
    bpy.context.scene["design_intent"] = "The Ironhorn mother bell caged inside the Carrion Cut"
    save_render_export(CARRION_BLEND, CARRION_GLB, CARRION_PREVIEW)


def save_render_export(blend_path: Path, glb_path: Path, preview_path: Path) -> None:
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    bpy.ops.render.render(write_still=True)
    batch_visuals_for_export()
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )
    print(f"Saved Blender source: {blend_path}")
    print(f"Saved Godot GLB: {glb_path}")
    print(f"Saved preview: {preview_path}")


def batch_visuals_for_export() -> None:
    """Collapse static art into one mesh while preserving editable .blend parts.

    The source file is saved before this runs. Collision proxies stay separate so
    Godot can still turn each `-col` mesh into a correctly placed static body.
    """
    visuals = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and not obj.hide_render
        and "-col" not in obj.name.lower()
        and obj.name != "MotherBell"
    ]
    for obj in visuals:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in visuals:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = visuals[0]
    bpy.ops.object.join()
    visuals[0].name = "EnvironmentVisuals"
    print(f"Batched {len(visuals)} visual objects into one export mesh")


def main() -> None:
    reset_scene()
    build_widowpine()
    reset_scene()
    build_carrion()


if __name__ == "__main__":
    main()
