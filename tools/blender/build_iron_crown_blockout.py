"""Build the Iron Crown bell-abbey environment blockout in Blender.

Run with:
  Blender --background --python tools/blender/build_iron_crown_blockout.py

The generated .blend is the editable source. The GLB is a metric-scale Godot
import, and the PNG is the reveal-camera visual check.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector, noise


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "art_source/fortress/iron_crown_bell_abbey_blockout.blend"
GLB_PATH = ROOT / "assets/environment/iron_crown/iron_crown_bell_abbey_blockout.glb"
PREVIEW_PATH = ROOT / "art_direction/iron_crown/iron-crown-bell-abbey-blockout-v1.png"


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
    roughness: float = 0.75,
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


def add_pbr_textures(
    mat: bpy.types.Material,
    texture_set: str,
    *,
    use_diffuse: bool = True,
    uv_scale: float = 4.0,
    normal_strength: float = 0.45,
) -> None:
    """Attach a compact Poly Haven CC0 texture set in a glTF-friendly graph."""
    texture_dir = ROOT / "assets/materials/polyhaven" / texture_set
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    texcoord = nodes.new("ShaderNodeTexCoord")
    texcoord.name = f"{texture_set}_UV"
    mapping = nodes.new("ShaderNodeMapping")
    mapping.name = f"{texture_set}_Mapping"
    mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
    links.new(texcoord.outputs["UV"], mapping.inputs["Vector"])

    if use_diffuse:
        diffuse = nodes.new("ShaderNodeTexImage")
        diffuse.name = f"{texture_set}_Diffuse"
        diffuse.image = bpy.data.images.load(
            str(texture_dir / f"{texture_set}_Diffuse.jpg"), check_existing=True
        )
        links.new(mapping.outputs["Vector"], diffuse.inputs["Vector"])
        links.new(diffuse.outputs["Color"], bsdf.inputs["Base Color"])

    rough = nodes.new("ShaderNodeTexImage")
    rough.name = f"{texture_set}_Rough"
    rough.image = bpy.data.images.load(
        str(texture_dir / f"{texture_set}_Rough.jpg"), check_existing=True
    )
    rough.image.colorspace_settings.name = "Non-Color"
    links.new(mapping.outputs["Vector"], rough.inputs["Vector"])
    links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])

    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.name = f"{texture_set}_Normal"
    normal_tex.image = bpy.data.images.load(
        str(texture_dir / f"{texture_set}_nor_gl.jpg"), check_existing=True
    )
    normal_tex.image.colorspace_settings.name = "Non-Color"
    links.new(mapping.outputs["Vector"], normal_tex.inputs["Vector"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.name = f"{texture_set}_NormalMap"
    normal.space = "TANGENT"
    normal.inputs["Strength"].default_value = normal_strength
    links.new(normal_tex.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])


STONE = None
STONE_DARK = None
STONE_SHADOW = None
SNOW = None
IRON = None
TIMBER = None
RED = None
RED_DARK = None
WARM = None
BRONZE = None


def assign(obj: bpy.types.Object, mat: bpy.types.Material | None) -> None:
    if mat is not None and hasattr(obj.data, "materials"):
        obj.data.materials.append(mat)


def bevel(obj: bpy.types.Object, width: float = 0.12, segments: int = 2) -> None:
    modifier = obj.modifiers.new("Weathered edges", "BEVEL")
    modifier.width = width
    modifier.segments = segments


def cube(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material | None,
    *,
    bevel_width: float = 0.08,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (scale[0] / 2, scale[1] / 2, scale[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign(obj, mat)
    if bevel_width:
        bevel(obj, bevel_width)
    return obj


def snow_patch(
    name: str,
    location: tuple[float, float, float],
    size: tuple[float, float],
    mat: bpy.types.Material,
    rng: random.Random,
    *,
    points: int = 18,
) -> bpy.types.Object:
    """Create a patchy snow crust that exposes the occupied abbey's wet stone."""
    verts = [(0.0, 0.0, 0.0)]
    uvs = [(0.5, 0.5)]
    for index in range(points):
        angle = math.tau * index / points
        radial = rng.uniform(0.76, 1.15)
        x = math.cos(angle) * size[0] * 0.5 * radial
        y = math.sin(angle) * size[1] * 0.5 * radial
        verts.append((x, y, rng.uniform(-0.014, 0.02)))
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


def cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material | None,
    *,
    vertices: int = 8,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    assign(obj, mat)
    bevel(obj, 0.1, 2)
    return obj


def ico(
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
    bevel(obj, 0.06)
    if subdivisions > 1:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def organic_rock(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    *,
    seed: int,
) -> bpy.types.Object:
    """A weathered many-sided mass, used instead of visible low-poly icospheres."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    offset = Vector((seed * 0.091, seed * -0.057, seed * 0.034))
    for vertex in obj.data.vertices:
        point = vertex.co.copy()
        direction = point.normalized()
        coarse = noise.noise_vector(point * 0.24 + offset, noise_basis="PERLIN_NEW")
        detail = noise.noise_vector(point * 0.72 - offset, noise_basis="PERLIN_NEW")
        strata = math.sin((point.z + seed * 0.11) * 0.72) * 0.18
        vertex.co += direction * (coarse.x * 0.8 + detail.z * 0.24 + strata)
    assign(obj, mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(58.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    bevel_modifier = obj.modifiers.new("Weathered fracture edges", "BEVEL")
    bevel_modifier.width = 0.08
    bevel_modifier.segments = 2
    bevel_modifier.limit_method = "ANGLE"
    bevel_modifier.angle_limit = math.radians(36.0)
    bpy.ops.object.modifier_apply(modifier=bevel_modifier.name)
    return obj


def beam_between(
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
    midpoint = (a + b) / 2
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=direction.length, location=midpoint
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    assign(obj, mat)
    return obj


def rect_beam_between(
    name: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    width: float,
    depth: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    """A square-cut stone or timber rib aligned between two points."""
    a, b = Vector(start), Vector(end)
    direction = b - a
    midpoint = (a + b) * 0.5
    obj = cube(name, tuple(midpoint), (width, depth, direction.length), mat, bevel_width=0.055)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def arch_ring(
    name: str,
    center: tuple[float, float, float],
    outer_radius: float,
    inner_radius: float,
    leg_height: float,
    depth: float,
    mat: bpy.types.Material,
    *,
    segments: int = 18,
) -> bpy.types.Object:
    """Create a Roman arch ring with straight lower legs and a deep opening."""
    cx, cy, cz = center
    outline: list[tuple[float, float]] = []
    outline.append((-outer_radius, 0.0))
    outline.append((-outer_radius, leg_height))
    for i in range(segments + 1):
        angle = math.pi - (math.pi * i / segments)
        outline.append((outer_radius * math.cos(angle), leg_height + outer_radius * math.sin(angle)))
    outline.append((outer_radius, 0.0))
    outline.append((inner_radius, 0.0))
    outline.append((inner_radius, leg_height))
    for i in range(segments + 1):
        angle = math.pi * i / segments
        outline.append((inner_radius * math.cos(angle), leg_height + inner_radius * math.sin(angle)))
    outline.append((-inner_radius, 0.0))

    verts = []
    for y in (-depth / 2, depth / 2):
        verts.extend([(cx + x, cy + y, cz + z) for x, z in outline])
    count = len(outline)
    faces = []
    faces.append(tuple(range(count)))
    faces.append(tuple(range(count, count * 2))[::-1])
    for i in range(count):
        j = (i + 1) % count
        faces.append((i, j, count + j, count + i))
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    assign(obj, mat)
    bevel(obj, 0.09, 2)
    return obj


def battlements(
    prefix: str,
    center: tuple[float, float, float],
    length: float,
    axis: str,
    mat: bpy.types.Material,
    *,
    count: int,
) -> None:
    cx, cy, cz = center
    for i in range(count):
        offset = -length / 2 + (i + 0.5) * length / count
        loc = (cx + offset, cy, cz) if axis == "X" else (cx, cy + offset, cz)
        cube(f"{prefix}_merlon_{i:02d}", loc, (1.0, 1.2, 1.5), mat, bevel_width=0.05)


def masonry_face(
    prefix: str,
    center_x: float,
    front_y: float,
    bottom_z: float,
    width: float,
    height: float,
    *,
    seed: int,
) -> None:
    """Dress a monolithic traversal support with readable, irregular stone courses."""
    rng = random.Random(seed)
    row_height = 0.82
    rows = max(1, int(height / row_height))
    for row in range(rows):
        cursor = -width / 2 - (0.65 if row % 2 else 0.0)
        block_index = 0
        while cursor < width / 2:
            block_width = rng.uniform(1.35, 2.35)
            center = min(width / 2, cursor + block_width * 0.5)
            visible_width = min(block_width - 0.045, width / 2 - cursor)
            if visible_width > 0.18:
                cube(
                    f"{prefix}_course_{row:02d}_{block_index:02d}",
                    (
                        center_x + center,
                        front_y + rng.uniform(-0.045, 0.045),
                        bottom_z + row_height * (row + 0.5) + rng.uniform(-0.025, 0.025),
                    ),
                    (visible_width, 0.42, row_height - 0.055),
                    STONE_DARK,
                    bevel_width=0.055,
                    rotation=(0.0, 0.0, rng.uniform(-0.012, 0.012)),
                )
            cursor += block_width
            block_index += 1


def arch_voussoirs(prefix: str, x: float, y: float, spring_z: float, radius: float) -> None:
    """Individual wedge-like arch stones add scale and catch the moonlight."""
    count = 17
    arc_width = math.pi * radius / count * 1.12
    for i in range(count):
        angle = math.pi - math.pi * i / (count - 1)
        bx = x + math.cos(angle) * radius
        bz = spring_z + math.sin(angle) * radius
        cube(
            f"{prefix}_{i:02d}",
            (bx, y, bz),
            (arc_width, 0.78, 0.82),
            STONE,
            bevel_width=0.055,
            rotation=(0.0, -angle + math.pi * 0.5, 0.0),
        )


def triangular_gable(
    name: str,
    center_x: float,
    center_y: float,
    base_z: float,
    width: float,
    height: float,
    depth: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    """A deep abbey gable that breaks the fortress-box silhouette."""
    half_width = width * 0.5
    half_depth = depth * 0.5
    profile = [
        (-half_width, base_z),
        (half_width, base_z),
        (0.0, base_z + height),
    ]
    verts = []
    for y in (center_y - half_depth, center_y + half_depth):
        verts.extend([(center_x + x, y, z) for x, z in profile])
    faces = [
        (0, 1, 2),
        (5, 4, 3),
        (0, 3, 4, 1),
        (1, 4, 5, 2),
        (2, 5, 3, 0),
    ]
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    assign(obj, mat)
    bevel(obj, 0.13, 3)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(58.0), island_margin=0.025)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    return obj


def hanging_bell(
    prefix: str,
    location: tuple[float, float, float],
    radius: float,
    height: float,
    *,
    heroic: bool = False,
) -> None:
    """Build a readable bronze bell silhouette with rim, crown, and clapper."""
    x, y, z = location
    bpy.ops.mesh.primitive_cone_add(
        vertices=32 if heroic else 20,
        radius1=radius,
        radius2=radius * 0.47,
        depth=height,
        location=(x, y, z),
    )
    body = bpy.context.object
    body.name = f"{prefix}_body"
    assign(body, BRONZE)
    bevel(body, 0.055 if heroic else 0.025, 2)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=radius * 0.88,
        minor_radius=radius * 0.13,
        major_segments=32 if heroic else 20,
        minor_segments=8,
        location=(x, y, z - height * 0.49),
    )
    rim = bpy.context.object
    rim.name = f"{prefix}_rim"
    assign(rim, BRONZE)
    cylinder(
        f"{prefix}_crown",
        (x, y, z + height * 0.57),
        radius * 0.16,
        height * 0.22,
        IRON,
        vertices=12,
    )
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=2,
        radius=radius * 0.18,
        location=(x, y, z - height * 0.69),
    )
    clapper = bpy.context.object
    clapper.name = f"{prefix}_clapper"
    assign(clapper, IRON)


def stairs(
    prefix: str,
    start: tuple[float, float, float],
    end: tuple[float, float, float],
    width: float,
    steps: int,
) -> None:
    start_v, end_v = Vector(start), Vector(end)
    delta = end_v - start_v
    run = math.hypot(delta.x, delta.y)
    angle = math.atan2(delta.y, delta.x)
    step_run = run / steps
    step_rise = delta.z / steps
    snow_rng = random.Random(sum(ord(char) for char in prefix) * 101 + steps)
    for i in range(steps):
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        pos = start_v + direction * (step_run * (i + 0.5))
        z = start_v.z + step_rise * i
        cube(
            f"{prefix}_step_{i:02d}-col",
            (pos.x, pos.y, z + step_rise / 2),
            (step_run + 0.04, width, max(step_rise, 0.18)),
            STONE_DARK,
            bevel_width=0.025,
            rotation=(0, 0, angle),
        )
        crust = snow_patch(
            f"{prefix}_snow_{i:02d}",
            (pos.x, pos.y, z + step_rise + 0.038),
            (step_run * snow_rng.uniform(0.62, 0.96), width * snow_rng.uniform(0.45, 0.9)),
            SNOW,
            snow_rng,
            points=12,
        )
        crust.rotation_euler.z = angle


def lancet_window(
    prefix: str,
    location: tuple[float, float, float],
    width: float,
    height: float,
    *,
    facing: str = "FRONT",
) -> None:
    x, y, z = location
    if facing == "FRONT":
        cube(f"{prefix}_recess", (x, y, z), (width, 0.16, height), STONE_SHADOW, bevel_width=0.03)
        cube(f"{prefix}_sill", (x, y - 0.04, z - height / 2), (width + 0.35, 0.3, 0.22), STONE)
    else:
        cube(f"{prefix}_recess", (x, y, z), (0.16, width, height), STONE_SHADOW, bevel_width=0.03)
        cube(f"{prefix}_sill", (x - 0.04, y, z - height / 2), (0.3, width + 0.35, 0.22), STONE)


def make_octagonal_tower(
    prefix: str,
    location: tuple[float, float, float],
    radius: float,
    height: float,
    *,
    broken: bool = False,
) -> None:
    x, y, base_z = location
    cylinder(f"{prefix}_body", (x, y, base_z + height / 2), radius, height, STONE, vertices=8)
    cylinder(f"{prefix}_base", (x, y, base_z + 0.75), radius + 0.7, 1.5, STONE_DARK, vertices=8)
    cylinder(f"{prefix}_cornice", (x, y, base_z + height - 1.2), radius + 0.35, 0.6, STONE, vertices=8)
    for band_index, fraction in enumerate((0.28, 0.54, 0.78)):
        cylinder(
            f"{prefix}_stringcourse_{band_index}",
            (x, y, base_z + height * fraction),
            radius + 0.14,
            0.34,
            STONE_DARK,
            vertices=8,
        )
    for rib_index in range(8):
        angle = math.tau * rib_index / 8 + math.pi / 8
        cube(
            f"{prefix}_rib_{rib_index:02d}",
            (
                x + math.cos(angle) * (radius + 0.03),
                y + math.sin(angle) * (radius + 0.03),
                base_z + height * 0.51,
            ),
            (0.48, 0.48, height * 0.88),
            STONE_DARK,
            bevel_width=0.06,
            rotation=(0.0, 0.0, angle),
        )
    window_zs = (base_z + height * 0.48, base_z + height * 0.73)
    for level, wz in enumerate(window_zs):
        for side, angle in enumerate((0, math.pi / 2, math.pi, 3 * math.pi / 2)):
            wx = x + math.sin(angle) * (radius + 0.025)
            wy = y - math.cos(angle) * (radius + 0.025)
            facing = "FRONT" if side in (0, 2) else "SIDE"
            lancet_window(f"{prefix}_window_{level}_{side}", (wx, wy, wz), 1.15, 3.4, facing=facing)
    # A deep front lancet and stone hood remain legible from the approach camera.
    front_y = y - radius - 0.10
    for level, wz in enumerate(window_zs):
        arch_ring(
            f"{prefix}_front_hood_{level}",
            (x, front_y, wz - 1.7),
            1.15,
            0.78,
            1.6,
            0.52,
            STONE_DARK,
            segments=12,
        )
    battlement_z = base_z + height + 0.8
    for i in range(8):
        if broken and i in (1, 2, 3):
            continue
        angle = math.tau * i / 8
        cube(
            f"{prefix}_crown_{i:02d}",
            (x + math.cos(angle) * (radius - 0.25), y + math.sin(angle) * (radius - 0.25), battlement_z),
            (1.15, 1.15, 1.7),
            STONE,
            bevel_width=0.06,
            rotation=(0, 0, angle),
        )


def timber_scaffold(prefix: str, x: float, y: float, z: float, width: float, height: float) -> None:
    for side in (-1, 1):
        for depth in (-0.9, 0.9):
            beam_between(
                f"{prefix}_post_{side}_{depth}",
                (x + side * width / 2, y + depth, z),
                (x + side * width / 2, y + depth, z + height),
                0.16,
                TIMBER,
            )
    for level in range(1, 4):
        lz = z + height * level / 4
        beam_between(f"{prefix}_rail_{level}", (x - width / 2, y - 1, lz), (x + width / 2, y - 1, lz), 0.13, TIMBER)
        cube(f"{prefix}_deck_{level}", (x, y, lz - 0.1), (width + 0.8, 2.4, 0.22), TIMBER, bevel_width=0.02)
    beam_between(f"{prefix}_brace_a", (x - width / 2, y - 1.05, z), (x + width / 2, y - 1.05, z + height), 0.1, TIMBER)
    beam_between(f"{prefix}_brace_b", (x + width / 2, y - 0.95, z), (x - width / 2, y - 0.95, z + height), 0.1, TIMBER)


def banner(prefix: str, location: tuple[float, float, float], width: float, height: float) -> None:
    x, y, z = location
    cube(f"{prefix}_cloth", (x, y, z - height / 2), (width, 0.08, height), RED_DARK, bevel_width=0.015)
    beam_between(f"{prefix}_spar", (x - width * 0.65, y, z), (x + width * 0.65, y, z), 0.09, IRON)


def portcullis(x: float, y: float, z: float, width: float, height: float) -> None:
    for i in range(9):
        bx = x - width / 2 + width * i / 8
        beam_between(f"IronThroat_vertical_{i:02d}", (bx, y, z), (bx, y, z + height), 0.10, IRON, vertices=6)
    for i in range(5):
        bz = z + height * i / 4
        beam_between(f"IronThroat_horizontal_{i:02d}", (x - width / 2, y, bz), (x + width / 2, y, bz), 0.10, IRON, vertices=6)
    for i in range(9):
        bx = x - width / 2 + width * i / 8
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.2, radius2=0.0, depth=0.8, location=(bx, y, z - 0.38))
        spike = bpy.context.object
        spike.name = f"IronThroat_spike_{i:02d}"
        assign(spike, IRON)


def crane(prefix: str, x: float, y: float, z: float, height: float, arm: float) -> None:
    beam_between(f"{prefix}_post", (x, y, z), (x, y, z + height), 0.24, TIMBER)
    beam_between(f"{prefix}_arm", (x - 0.8, y, z + height), (x + arm, y, z + height), 0.20, TIMBER)
    beam_between(f"{prefix}_brace", (x, y, z + height * 0.55), (x + arm * 0.7, y, z + height), 0.14, TIMBER)
    beam_between(f"{prefix}_chain", (x + arm * 0.8, y, z + height), (x + arm * 0.8, y, z + height - 3.4), 0.055, IRON, vertices=6)
    cylinder(f"{prefix}_bell", (x + arm * 0.8, y, z + height - 3.8), 0.55, 0.9, IRON, vertices=12)


def lantern(prefix: str, x: float, y: float, z: float) -> None:
    cube(f"{prefix}_housing", (x, y, z), (0.55, 0.55, 0.75), IRON, bevel_width=0.04)
    cube(f"{prefix}_light", (x, y - 0.29, z), (0.28, 0.05, 0.42), WARM, bevel_width=0.015)
    light_data = bpy.data.lights.new(f"{prefix}_point", "POINT")
    light_data.energy = 160
    light_data.color = (1.0, 0.35, 0.08)
    light_data.shadow_soft_size = 1.0
    light = bpy.data.objects.new(f"{prefix}_point", light_data)
    bpy.context.collection.objects.link(light)
    light.location = (x, y - 0.5, z)


def bellthorn(prefix: str, x: float, y: float, z: float, scale: float) -> None:
    beam_between(f"{prefix}_trunk", (x, y, z), (x, y, z + 4.5 * scale), 0.32 * scale, STONE_SHADOW)
    for i, (dx, dy, dz) in enumerate(((-2.0, 0.2, 5.4), (1.7, -0.2, 5.8), (-0.4, 0.5, 7.0), (1.0, 0.2, 7.6))):
        beam_between(
            f"{prefix}_branch_{i}",
            (x, y, z + 3.0 * scale),
            (x + dx * scale, y + dy * scale, z + dz * scale),
            0.16 * scale,
            STONE_SHADOW,
        )
        tip = Vector((x + dx * scale, y + dy * scale, z + dz * scale))
        for leaf_index in range(5):
            angle = (leaf_index / 5.0) * math.tau + i * 0.61
            leaf = tip + Vector(
                (
                    math.cos(angle) * (0.72 + 0.12 * (leaf_index % 2)) * scale,
                    math.sin(angle) * 0.38 * scale,
                    (leaf_index - 2) * 0.22 * scale,
                )
            )
            ico(
                f"{prefix}_leaves_{i}_{leaf_index}",
                tuple(leaf),
                (0.54 * scale, 0.24 * scale, 0.34 * scale),
                RED,
                subdivisions=2,
            )


def create_terraced_ascent() -> None:
    # Broad traversal planes: each platform supports a combat beat.
    platforms = (
        ("LowerReveal", (0, 0, 0.0), (15, 13, 0.8)),
        ("TerraceOne", (-6.0, 13.5, 2.1), (21, 9, 1.0)),
        ("TerraceTwo", (5.5, 25.5, 4.8), (24, 10, 1.2)),
        ("TerraceThree", (-1.0, 38.0, 7.9), (28, 10, 1.4)),
    )
    rng = random.Random(2718)
    for platform_index, (name, loc, dims) in enumerate(platforms):
        cube(name, loc, dims, STONE_DARK, bevel_width=0.14)
        top = loc[2] + dims[2] / 2 + 0.066
        for patch_index in range(3):
            patch_width = dims[0] * rng.uniform(0.28, 0.45)
            patch_depth = dims[1] * rng.uniform(0.3, 0.52)
            patch_x = loc[0] + dims[0] * (-0.27 + patch_index * 0.27) + rng.uniform(-0.8, 0.8)
            patch_y = loc[1] + rng.uniform(-dims[1] * 0.24, dims[1] * 0.2)
            snow_patch(f"{name}_snow_{patch_index}", (patch_x, patch_y, top), (patch_width, patch_depth), SNOW, rng)

    # Retaining masses make the terraces feel carved from the mountain instead
    # of suspended as game-platform shelves.
    for index, (name, loc, dims) in enumerate(platforms[1:], start=1):
        support_height = loc[2] + dims[2] / 2
        cube(
            f"{name}_mountain_support",
            (loc[0], loc[1] + 0.8, support_height / 2),
            (dims[0] + 3.0, dims[1] + 4.0, support_height),
            STONE_DARK,
            bevel_width=0.35,
            rotation=(0.0, 0.0, (index - 2) * 0.025),
        )
        masonry_face(
            name,
            loc[0],
            loc[1] - dims[1] * 0.5 - 0.24,
            0.0,
            dims[0] + 1.4,
            support_height,
            seed=81 + index * 17,
        )
        for buttress_index, x_offset in enumerate((-dims[0] * 0.38, 0.0, dims[0] * 0.38)):
            cube(
                f"{name}_buttress_{buttress_index}",
                (loc[0] + x_offset, loc[1] - dims[1] * 0.5 - 0.55, support_height * 0.48),
                (0.82, 1.15, support_height * 0.96),
                STONE,
                bevel_width=0.07,
            )

    stairs("StairsLower", (2.0, 6.2, 0.45), (-7.0, 10.0, 1.65), 5.5, 9)
    stairs("StairsMiddle", (-2.5, 17.8, 2.65), (6.5, 20.5, 4.2), 6.2, 10)
    stairs("StairsUpper", (7.0, 30.3, 5.45), (-2.0, 33.2, 7.25), 6.5, 11)
    stairs("StairsGate", (-1.5, 42.7, 8.65), (0.0, 48.5, 11.2), 7.4, 13)

    # Low cover establishes tactical scale and breaks the ceremonial route.
    cover = (
        (-11.5, 12.2, 3.0, 2.8, 1.5, 1.9),
        (0.8, 14.8, 3.1, 3.4, 1.4, 2.1),
        (12.6, 24.0, 6.2, 3.2, 1.7, 2.2),
        (-6.4, 27.7, 6.0, 4.2, 1.5, 1.8),
        (-13.2, 38.8, 9.7, 3.0, 1.8, 2.1),
        (8.8, 39.4, 9.7, 3.8, 1.8, 2.0),
    )
    for i, values in enumerate(cover):
        x, y, z, sx, sy, sz = values
        cube(f"RuinedCover_{i:02d}", (x, y, z), (sx, sy, sz), STONE, bevel_width=0.18, rotation=(0, 0, (i % 3 - 1) * 0.12))

    # Collision proxies are deliberately simple and use Godot's import suffix.
    for name, loc, dims in platforms:
        obj = cube(f"{name}-colonly", loc, dims, None, bevel_width=0)
        obj.display_type = "WIRE"
        obj.hide_render = True


def create_sanctuary() -> None:
    # Mountain-cut foundation and gate wall.
    cube("AbbeyFoundationWest", (-17.0, 54.0, 9.5), (17, 18, 8), STONE_DARK, bevel_width=0.28)
    cube("AbbeyFoundationEast", (18.0, 54.0, 9.5), (15, 18, 8), STONE_DARK, bevel_width=0.28)
    cube("GateLeftMass", (-9.2, 52.5, 18.0), (13, 5.5, 18), STONE, bevel_width=0.16)
    cube("GateRightMass", (10.5, 52.5, 17.0), (15, 5.5, 16), STONE, bevel_width=0.16)
    cube("GateShadow", (0.0, 52.1, 17.2), (8.2, 0.4, 12.5), STONE_SHADOW, bevel_width=0.0)
    arch_ring("IronThroat_Arch", (0.0, 51.7, 11.0), 6.6, 4.2, 5.7, 1.2, STONE)
    arch_voussoirs("IronThroat_Voussoir", 0.0, 49.42, 16.7, 5.55)
    portcullis(0.0, 51.35, 11.2, 7.6, 10.0)
    battlements("GateLeft", (-9.2, 49.8, 27.7), 12.0, "X", STONE, count=7)
    battlements("GateRight", (10.5, 49.8, 25.7), 14.0, "X", STONE, count=8)

    # The Iron Crown is an occupied bell abbey, not a generic keep. A steep
    # central gable and its scarred founding bell dominate the approach, while
    # the smaller name bells make the nine-bell story physically legible.
    triangular_gable("NinefoldBellGable", 0.0, 52.25, 24.5, 12.0, 14.5, 5.2, STONE)
    rect_beam_between("NinefoldGableRibLeft", (-6.0, 49.48, 24.55), (0.0, 49.48, 39.0), 0.55, 0.56, STONE_DARK)
    rect_beam_between("NinefoldGableRibRight", (6.0, 49.48, 24.55), (0.0, 49.48, 39.0), 0.55, 0.56, STONE_DARK)
    for course_index, course_z in enumerate((25.4, 27.5, 29.6, 33.7, 35.8)):
        course_width = max(1.4, 12.0 * (1.0 - (course_z - 24.5) / 14.5))
        cube(
            f"NinefoldGableCourse_{course_index}",
            (0.0, 49.43, course_z),
            (course_width, 0.62, 0.24),
            STONE_DARK,
            bevel_width=0.045,
        )
    cylinder(
        "NinefoldRoseVoid",
        (0.0, 49.56, 31.15),
        2.7,
        0.24,
        STONE_SHADOW,
        vertices=32,
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    bpy.ops.mesh.primitive_torus_add(
        major_radius=2.72,
        minor_radius=0.28,
        major_segments=32,
        minor_segments=10,
        location=(0.0, 49.38, 31.15),
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    rose_ring = bpy.context.object
    rose_ring.name = "NinefoldRoseStoneRing"
    assign(rose_ring, STONE_DARK)
    beam_between("FoundingBellChain", (0.0, 49.08, 36.9), (0.0, 49.08, 32.65), 0.09, IRON, vertices=8)
    hanging_bell("FoundingBell", (0.0, 49.0, 30.8), 1.58, 2.7, heroic=True)
    # The crack is a separate soot-black inlay on the bell face.
    beam_between("FoundingBellCrackA", (-0.18, 48.12, 32.0), (0.22, 48.12, 31.15), 0.065, STONE_SHADOW, vertices=7)
    beam_between("FoundingBellCrackB", (0.22, 48.12, 31.15), (-0.12, 48.12, 30.35), 0.065, STONE_SHADOW, vertices=7)
    for bell_index, x in enumerate((-11.7, -8.4, -5.1, -1.7, 1.7, 5.1, 8.4, 11.7)):
        chain_top = 24.7 + (bell_index % 2) * 0.65
        beam_between(
            f"NameBellChain_{bell_index + 1:02d}",
            (x, 49.08, chain_top),
            (x, 49.08, chain_top - 1.25),
            0.035,
            IRON,
            vertices=6,
        )
        hanging_bell(
            f"NameBell_{bell_index + 1:02d}",
            (x, 49.0, chain_top - 1.55),
            0.34,
            0.58,
        )

    # Deep piers, string courses, and scarred blind niches make the gate read
    # as a former abbey rather than a pair of plain fortress boxes.
    for x in (-14.4, -10.0, -5.2, 5.3, 10.3, 15.2):
        height = 16.0 if x > 0 else 18.0
        cube(
            f"GateFacadePier_{x:+05.1f}",
            (x, 49.55, 9.0 + height * 0.5),
            (0.75, 1.0, height),
            STONE_DARK,
            bevel_width=0.07,
        )
    for course, z in enumerate((14.2, 20.1, 25.4)):
        cube(f"GateLeftCourse_{course}", (-9.2, 49.45, z), (13.2, 0.8, 0.52), STONE_DARK, bevel_width=0.06)
        if course < 2:
            cube(f"GateRightCourse_{course}", (10.5, 49.45, z), (15.2, 0.8, 0.52), STONE_DARK, bevel_width=0.06)
    for niche_index, x in enumerate((-11.8, -7.1, 7.5, 12.5)):
        cube(f"GateBlindNiche_{niche_index}", (x, 49.32, 18.6), (1.65, 0.16, 4.9), STONE_SHADOW, bevel_width=0.04)
        arch_ring(
            f"GateBlindNicheHood_{niche_index}",
            (x, 49.17, 16.15),
            1.35,
            0.94,
            2.2,
            0.44,
            STONE,
            segments=12,
        )

    # Main asymmetrical Ninefold tower and companion structures.
    # Keep the Ninefold tower visually dominant without letting its six-metre
    # radius choke Varkas' central charge lane. Its old x=8.5 footprint reached
    # to within 2.5 m of the centre line and read as a wall in first person.
    make_octagonal_tower("NinefoldTower", (13.0, 62.0, 13.0), 6.0, 30.0)
    make_octagonal_tower("EastMemorialTower", (21.0, 61.5, 13.0), 4.6, 23.0)
    make_octagonal_tower("BrokenBellTower", (-18.0, 59.0, 13.0), 5.2, 20.0, broken=True)

    # Varkas' court terminates in the abbey's scarred memorial apse. Three deep
    # arches give the phase-three arena a readable backdrop and keep the boss
    # silhouette off the distant placeholder mountains.
    cube("VarkasCourtApse", (0.0, 71.0, 19.0), (29.0, 5.0, 16.0), STONE_DARK, bevel_width=0.24)
    for i, x in enumerate((-8.2, 0.0, 8.2)):
        cube(f"CourtArchVoid_{i}", (x, 68.35, 17.0), (4.5, 0.24, 9.8), STONE_SHADOW, bevel_width=0.04)
        arch_ring(f"CourtMemorialArch_{i}", (x, 68.1, 11.0), 3.6, 2.35, 4.5, 1.1, STONE)
    for i, x in enumerate((-12.0, -6.0, 1.0, 7.0, 12.0)):
        cube(
            f"CourtBrokenCrown_{i}",
            (x, 68.4, 27.0 + (i % 2) * 0.9),
            (4.2, 2.0, 2.0 + (i % 3) * 0.5),
            STONE,
            bevel_width=0.12,
            rotation=(0.0, 0.0, (i - 2) * 0.025),
        )
    banner("CourtBannerLeft", (-5.0, 67.45, 25.2), 1.6, 6.4)
    banner("CourtBannerRight", (6.0, 67.45, 24.0), 1.4, 5.2)

    # Broken nave is lower and broad, preventing a castle-like twin-tower read.
    cube("BrokenNave_Back", (-15.0, 65.0, 20.0), (18, 8, 16), STONE, bevel_width=0.18)
    for i, x in enumerate((-19.0, -13.0, -7.0)):
        arch_ring(f"NaveArch_{i}", (x, 60.8, 14.0), 3.2, 2.2, 4.0, 1.0, STONE)
        cube(f"NaveVoid_{i}", (x, 60.2, 18.0), (4.2, 0.3, 8.0), STONE_SHADOW, bevel_width=0.02)
    cube("NaveBrokenRoofA", (-17.0, 64.5, 29.0), (8.0, 7.0, 1.2), STONE_DARK, bevel_width=0.15, rotation=(0.0, 0.18, 0.05))
    cube("NaveBrokenRoofB", (-10.0, 65.0, 27.2), (6.0, 7.0, 1.0), STONE_DARK, bevel_width=0.15, rotation=(0.0, -0.25, -0.08))

    # Memorial arcade and an incomplete curtain wall.
    for i in range(4):
        x = -24 + i * 6.0
        cube(f"MemorialPier_{i}", (x, 55.5, 16.0), (1.4, 3.0, 9.0), STONE, bevel_width=0.10)
        if i < 3:
            arch_ring(f"MemorialArch_{i}", (x + 3.0, 53.9, 11.6), 2.8, 2.0, 2.2, 1.0, STONE)

    # Varkas' visually younger occupation layer.
    timber_scaffold("GateScaffold", 10.5, 49.0, 10.5, 12.0, 15.0)
    timber_scaffold("NaveScaffold", -11.0, 59.0, 15.0, 12.0, 14.0)
    crane("WestBellCrane", -25.0, 49.0, 10.5, 10.0, 5.2)
    crane("EastCageCrane", 25.0, 50.0, 11.0, 12.0, 5.5)
    banner("GateBannerLeft", (-6.8, 49.55, 25.5), 2.1, 7.5)
    banner("NinefoldBanner", (13.0, 55.6, 40.0), 2.5, 9.0)
    banner("EastBanner", (21.0, 57.3, 31.5), 1.8, 6.2)

    # Sparse route lamps.
    for i, (x, y, z) in enumerate(((-5.5, 7.0, 1.6), (-12.0, 16.0, 4.4), (11.0, 28.0, 7.2), (-9.0, 40.0, 10.9), (7.0, 48.5, 13.4))):
        lantern(f"RouteLantern_{i}", x, y, z)


def create_cliffs_and_bellthorn() -> None:
    # Weathered PBR rock masses frame the reveal while leaving the center readable.
    for side in (-1, 1):
        for i in range(8):
            x = side * (22.5 + (i % 3) * 3.7)
            y = -2.0 + i * 9.0
            z = 4.0 + i * 1.8
            organic_rock(
                f"Cliff_{'L' if side < 0 else 'R'}_{i:02d}",
                (x, y, z),
                (6.0 + i * 0.42, 5.4, 8.5 + i * 0.9),
                STONE_DARK,
                seed=311 + i * 19 + (0 if side < 0 else 151),
            )
    organic_rock("RearMountainLeft", (-27, 70, 30), (22, 18, 34), STONE_DARK, seed=701)
    organic_rock("RearMountainRight", (30, 72, 35), (24, 18, 40), STONE_DARK, seed=809)

    bellthorn("BellthornLower", -12.5, 5.0, 0.5, 0.8)
    bellthorn("BellthornTerrace", 14.0, 34.0, 8.8, 0.9)
    bellthorn("BellthornAbbey", -20.5, 48.5, 11.0, 1.2)
    bellthorn("BellthornGateScar", 17.4, 52.0, 13.0, 0.92)
    for i, (x, y, z, sx, sy) in enumerate(
        ((-3, 2, 0.6, 6, 3), (-8, 15, 2.7, 5, 2), (8, 25, 5.5, 7, 2.2), (-5, 39, 8.8, 7, 2.0))
    ):
        cube(f"BellthornLeafDrift_{i}", (x, y, z), (sx, sy, 0.08), RED_DARK, bevel_width=0.04, rotation=(0, 0, 0.1 * (i - 1)))


def add_camera_and_lighting() -> None:
    world = bpy.data.worlds.new("Iron Crown Storm")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.01, 0.018, 0.04, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35

    sun_data = bpy.data.lights.new("Moon", "SUN")
    sun_data.energy = 4.0
    sun_data.color = (0.34, 0.48, 0.8)
    sun_data.angle = math.radians(12)
    sun = bpy.data.objects.new("Moon", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(42), math.radians(-24), math.radians(-28))

    area_data = bpy.data.lights.new("Cold sky fill", "AREA")
    area_data.energy = 2300
    area_data.shape = "DISK"
    area_data.size = 25
    area_data.color = (0.22, 0.32, 0.6)
    area = bpy.data.objects.new("Cold sky fill", area_data)
    bpy.context.collection.objects.link(area)
    area.location = (-20, 15, 45)
    point_at(area, (0, 45, 14))

    front_data = bpy.data.lights.new("Cold reveal bounce", "AREA")
    front_data.energy = 900
    front_data.shape = "RECTANGLE"
    front_data.size = 18
    front_data.color = (0.16, 0.25, 0.5)
    front = bpy.data.objects.new("Cold reveal bounce", front_data)
    bpy.context.collection.objects.link(front)
    front.location = (3, -8, 18)
    point_at(front, (0, 49, 17))

    camera_data = bpy.data.cameras.new("RevealCamera")
    camera = bpy.data.objects.new("RevealCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0.0, -10.0, 3.8)
    camera_data.lens = 28
    camera_data.sensor_width = 36
    point_at(camera, (0.0, 48.0, 18.0))
    bpy.context.scene.camera = camera


def point_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure_render() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1536
    scene.render.resolution_y = 864
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_percentage = 100


def batch_visuals_for_export() -> None:
    """Batch static art after saving the modular source, retaining collision proxies."""
    landmark_names = {
        "NinefoldTower_body",
        "NinefoldBellGable",
        "FoundingBell_body",
        "IronThroat_Arch",
        "IronThroat_vertical_04",
        "BrokenNave_Back",
        "GateScaffold_deck_2",
        "BellthornAbbey_trunk",
        "TerraceThree",
    }
    visuals = [
        obj
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and not obj.hide_render
        and "-col" not in obj.name.lower()
        and obj.name not in landmark_names
        and not obj.name.startswith("IronThroat_vertical_")
        and not obj.name.startswith("IronThroat_horizontal_")
        and not obj.name.startswith("IronThroat_spike_")
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


def create_materials() -> None:
    global STONE, STONE_DARK, STONE_SHADOW, SNOW, IRON, TIMBER, RED, RED_DARK, WARM, BRONZE
    # The abbey must remain pale enough to read through the Iron Crown's blue
    # hour haze. The PBR scans darken these values substantially in-engine, so
    # the material swatches are intentionally lifted while the occupation iron
    # below stays near-black.
    STONE = material("Ancient pale limestone", (0.43, 0.47, 0.51, 1), roughness=0.82)
    STONE_DARK = material("Black granite", (0.045, 0.055, 0.075, 1), roughness=0.75)
    STONE_SHADOW = material("Deep recess", (0.006, 0.009, 0.015, 1), roughness=0.95)
    SNOW = material("Dirty moonlit snow", (0.36, 0.42, 0.5, 1), roughness=0.84)
    IRON = material("Varkas black iron", (0.018, 0.022, 0.028, 1), roughness=0.5, metallic=0.78)
    TIMBER = material("Sooted timber", (0.075, 0.035, 0.018, 1), roughness=0.92)
    RED = material("Living bellthorn crimson", (0.53, 0.006, 0.016, 1), roughness=0.83)
    RED_DARK = material("Dried bellthorn and banners", (0.19, 0.004, 0.01, 1), roughness=0.9)
    WARM = material(
        "Warm route light",
        (0.45, 0.08, 0.008, 1),
        roughness=0.3,
        emission=(1.0, 0.18, 0.015, 1),
        emission_strength=8.0,
    )
    BRONZE = material("Ninefold weathered bronze", (0.24, 0.11, 0.025, 1), roughness=0.42, metallic=0.82)
    add_pbr_textures(STONE, "stone_wall_05", uv_scale=3.2, normal_strength=0.52)
    add_pbr_textures(STONE_DARK, "dark_rock", uv_scale=1.8, normal_strength=0.62)
    add_pbr_textures(TIMBER, "weathered_planks", uv_scale=2.4, normal_strength=0.42)
    # Keep the occupation iron black; use the rust set only for pitting and
    # broken highlights instead of turning every bar orange.
    add_pbr_textures(
        IRON,
        "rust_coarse_01",
        use_diffuse=False,
        uv_scale=2.0,
        normal_strength=0.36,
    )


def main() -> None:
    reset_scene()
    create_materials()
    create_terraced_ascent()
    create_sanctuary()
    create_cliffs_and_bellthorn()
    add_camera_and_lighting()
    configure_render()

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["production_target"] = "art_direction/iron_crown/iron-crown-bell-abbey-target-v2.png"
    scene["design_intent"] = "Ancient Ironhorn bell sanctuary mutilated by Varkas"

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)
    batch_visuals_for_export()
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )
    print(f"Saved Blender source: {BLEND_PATH}")
    print(f"Saved Godot GLB: {GLB_PATH}")
    print(f"Saved preview: {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
