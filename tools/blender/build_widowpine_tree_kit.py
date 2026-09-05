"""Build a compact original pine/dead-tree kit for Widowpine and Carrion Cut."""

from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
TEXTURE_DIR = ROOT / "assets/materials/polyhaven/pine_tree_01"
ORIGINAL_TEXTURE_DIR = ROOT / "assets/materials/original"
EXPORT_DIR = ROOT / "assets/environment/vegetation"
BLEND_PATH = ROOT / "art_source/vegetation/widowpine_tree_kit.blend"
PREVIEW_PATH = ROOT / "art_direction/widowpine/widowpine-tree-kit-v1.png"


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def load_image(name: str, non_color: bool = False, directory: Path = TEXTURE_DIR) -> bpy.types.Image:
    image = bpy.data.images.load(str(directory / name), check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    return image


def bark_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("Widowpine bark")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.92
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (2.5, 2.5, 2.5)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])
    diffuse = nodes.new("ShaderNodeTexImage")
    diffuse.image = load_image("bark_diff_1k.jpg")
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.image = load_image("bark_nor_gl_1k.jpg", True)
    rough = nodes.new("ShaderNodeTexImage")
    rough.image = load_image("bark_rough_1k.jpg", True)
    for tex in (diffuse, normal_tex, rough):
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    links.new(diffuse.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.5
    links.new(normal_tex.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def needle_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("Widowpine needles")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.88
    branch = nodes.new("ShaderNodeTexImage")
    branch.image = load_image(
        "widowpine_branch_rgba.png",
        directory=ORIGINAL_TEXTURE_DIR,
    )
    links.new(branch.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(branch.outputs["Alpha"], bsdf.inputs["Alpha"])
    try:
        mat.surface_render_method = "DITHERED"
    except Exception:
        try:
            mat.blend_method = "HASHED"
        except Exception:
            pass
    mat.diffuse_color = (0.11, 0.18, 0.16, 1.0)
    return mat


def snow_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("Pine branch snow")
    mat.diffuse_color = (0.48, 0.58, 0.72, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = mat.diffuse_color
    bsdf.inputs["Roughness"].default_value = 0.7
    return mat


def tapered_beam(
    name: str,
    start: Vector,
    end: Vector,
    radius_start: float,
    radius_end: float,
    mat: bpy.types.Material,
    vertices: int = 8,
) -> bpy.types.Object:
    direction = end - start
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_start,
        radius2=radius_end,
        depth=direction.length,
        location=(start + end) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    obj.data.materials.append(mat)
    return obj


def foliage_mesh(
    name: str,
    cards: list[tuple[Vector, Vector, float]],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    # The project texture is a single transparent horizontal branch. Crop only
    # its empty vertical padding, then cant two cards around every bough. The
    # older second card lay almost horizontal and collapsed into long bright
    # streaks at player eye height; both new planes retain a vertical component.
    atlas_uv = ((0.0, 0.18), (1.0, 0.18), (1.0, 0.82), (0.0, 0.82))
    uv_values: list[tuple[float, float]] = []
    for start, end, half_height in cards:
        branch = end - start
        vertical = Vector((0.0, 0.0, half_height * 0.82))
        horizontal = Vector((-branch.y, branch.x, 0.0)).normalized() * half_height * 0.42
        for width_axis in (vertical + horizontal, vertical - horizontal):
            index = len(verts)
            verts.extend(
                (
                    tuple(start - width_axis),
                    tuple(end - width_axis),
                    tuple(end + width_axis),
                    tuple(start + width_axis),
                )
            )
            faces.append((index, index + 1, index + 2, index + 3))
            uv_values.extend(atlas_uv)
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            uv_layer.data[loop_index].uv = uv_values[vertex_index]
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def snow_cards(
    name: str,
    cards: list[tuple[Vector, Vector, float]],
    mat: bpy.types.Material,
) -> bpy.types.Object:
    verts = []
    faces = []
    for index, (start, end, half_height) in enumerate(cards[::4]):
        lift = Vector((0.0, 0.0, half_height * 0.8))
        width = Vector((-(end - start).y, (end - start).x, 0.0)).normalized() * 0.09
        a = start.lerp(end, 0.35) + lift
        b = start.lerp(end, 0.92) + lift
        offset = len(verts)
        verts.extend((tuple(a - width), tuple(b - width), tuple(b + width), tuple(a + width)))
        faces.append((offset, offset + 1, offset + 2, offset + 3))
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def join_objects(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    tree = bpy.context.object
    tree.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return tree


def build_tree(
    name: str,
    *,
    seed: int,
    height: float,
    crown_width: float,
    foliage: float,
    lean: float,
    bark: bpy.types.Material,
    needles: bpy.types.Material,
    snow: bpy.types.Material,
) -> bpy.types.Object:
    rng = random.Random(seed)
    bark_parts: list[bpy.types.Object] = []
    points = [Vector((0.0, 0.0, 0.0))]
    for segment in range(1, 6):
        t = segment / 5
        points.append(
            Vector(
                (
                    lean * t + math.sin(segment * 1.7 + seed) * 0.12,
                    math.cos(segment * 1.3 + seed) * 0.1,
                    height * t,
                )
            )
        )
    for segment in range(5):
        bark_parts.append(
            tapered_beam(
                f"{name}_trunk_{segment}",
                points[segment],
                points[segment + 1],
                0.52 * (1.0 - segment * 0.13),
                0.42 * (1.0 - segment * 0.16),
                bark,
                10,
            )
        )

    # Low polygon root flares connect the trunk to snow and rock. They matter
    # most on the two closest scatter rows, where a cylinder planted directly
    # into the terrain immediately gives away the procedural kit.
    for root_index in range(6):
        angle = math.tau * root_index / 6.0 + rng.uniform(-0.16, 0.16)
        reach = rng.uniform(0.78, 1.25)
        bark_parts.append(
            tapered_beam(
                f"{name}_root_{root_index}",
                Vector((0.0, 0.0, 0.34)),
                Vector((math.cos(angle) * reach, math.sin(angle) * reach, 0.05)),
                0.16,
                0.025,
                bark,
                7,
            )
        )

    cards: list[tuple[Vector, Vector, float]] = []
    levels = 18 if foliage > 0 else 12
    windward = rng.uniform(0.0, math.tau)
    for level in range(levels):
        t = 0.16 + level / max(1, levels - 1) * 0.78 + rng.uniform(-0.014, 0.014)
        z = height * t
        trunk = points[0].lerp(points[-1], t)
        branches = rng.randint(4, 7) if foliage > 0 else rng.randint(2, 4)
        ring_phase = rng.random() * math.tau
        for side in range(branches):
            angle = ring_phase + side * math.tau / branches + rng.uniform(-0.18, 0.18)
            wind = max(0.0, math.cos(angle - windward))
            # A broken windward side and irregular branch whorls avoid stacked
            # umbrella silhouettes. Upper growth tapers into a narrow crown.
            if foliage > 0 and rng.random() < wind * 0.22:
                continue
            length = crown_width * pow(1.0 - t, 0.65) * rng.uniform(0.76, 1.18)
            length *= 1.0 - wind * 0.20
            if foliage <= 0:
                length *= rng.uniform(0.45, 0.95)
            branch_drop = rng.uniform(-0.2, -0.035) + max(0.0, t - 0.72) * 0.34
            direction = Vector((math.cos(angle), math.sin(angle), branch_drop)).normalized()
            start = Vector((trunk.x, trunk.y, z))
            end = start + direction * length
            bark_parts.append(
                tapered_beam(
                    f"{name}_branch_{level}_{side}",
                    start,
                    end,
                    max(0.035, 0.11 * (1.0 - t * 0.45)),
                    0.018,
                    bark,
                    6,
                )
            )
            if foliage > 0 and rng.random() <= foliage:
                # Short branching sprays have readable gaps and depth; a
                # single stretched atlas card along a whole bough read flat.
                cards.append((start.lerp(end, 0.56), end, 0.20 + length * 0.028))
                tangent = Vector((-direction.y, direction.x, 0.0))
                for twig_index, along in enumerate((0.32, 0.57, 0.74)):
                    side_sign = -1.0 if twig_index % 2 == 0 else 1.0
                    twig_start = start.lerp(end, along)
                    twig_length = length * rng.uniform(0.26, 0.40)
                    twig_direction = (direction * 0.58 + tangent * side_sign * 0.62 + Vector((0, 0, -.10))).normalized()
                    twig_end = twig_start + twig_direction * twig_length
                    bark_parts.append(tapered_beam(f"{name}_spray_{level}_{side}_{twig_index}",
                                                  twig_start, twig_end, .025, .006, bark, 5))
                    cards.append((twig_start, twig_end, rng.uniform(.18, .30)))
            elif foliage <= 0 and length > 0.7:
                tangent = Vector((-direction.y, direction.x, 0.0))
                for fork in range(rng.randint(1, 3)):
                    fork_start = start.lerp(end, rng.uniform(.42, .78))
                    fork_end = fork_start + (direction * .42 + tangent * rng.choice((-1, 1)) * .52 + Vector((0, 0, rng.uniform(.1,.4)))) * length * rng.uniform(.24,.46)
                    bark_parts.append(tapered_beam(f"{name}_broken_fork_{level}_{side}_{fork}",
                                                  fork_start, fork_end, .035, .006, bark, 5))

    if foliage <= 0:
        # Broken spear-like crown differentiates Carrion Cut at distance.
        broken_top = points[-1] + Vector((0.14, -0.08, -height * 0.08))
        bark_parts.append(tapered_beam(f"{name}_broken_top", points[-2], broken_top, 0.2, 0.035, bark, 7))

    objects = list(bark_parts)
    if cards:
        objects.append(foliage_mesh(f"{name}_needles", cards, needles))
        # The original branch atlas already contains granular snow. A second
        # opaque ribbon on every fourth branch read as fluorescent stripes in
        # the live Godot camera, so snow stays inside the alpha foliage surface.
    return join_objects(name, objects)


def export_tree(tree: bpy.types.Object, filename: str) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    tree.select_set(True)
    bpy.context.view_layer.objects.active = tree
    bpy.ops.export_scene.gltf(
        filepath=str(EXPORT_DIR / filename),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
    )


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    reset_scene()
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    bark, needles, snow = bark_material(), needle_material(), snow_material()
    specs = (
        ("WidowpineTreeA", 11, 22.0, 4.55, 0.96, -0.45, "widowpine_tree_a.glb"),
        ("WidowpineTreeB", 23, 18.0, 4.0, 0.88, 0.75, "widowpine_tree_b.glb"),
        ("WidowpineTreeC", 47, 25.0, 4.85, 0.92, 0.2, "widowpine_tree_c.glb"),
        ("CarrionDeadPine", 79, 18.0, 4.8, 0.0, -0.55, "carrion_dead_pine.glb"),
    )
    trees = []
    for name, seed, height, width, foliage, lean, filename in specs:
        tree = build_tree(
            name,
            seed=seed,
            height=height,
            crown_width=width,
            foliage=foliage,
            lean=lean,
            bark=bark,
            needles=needles,
            snow=snow,
        )
        export_tree(tree, filename)
        trees.append(tree)

    for tree, x in zip(trees, (-18.0, -6.0, 7.0, 20.0)):
        tree.location.x = x
    ground = bpy.data.meshes.new("Ground_mesh")
    ground.from_pydata([(-30, -5, 0), (30, -5, 0), (30, 5, 0), (-30, 5, 0)], [], [(0, 1, 2, 3)])
    ground_obj = bpy.data.objects.new("SnowGround", ground)
    bpy.context.collection.objects.link(ground_obj)
    ground_obj.data.materials.append(snow)

    world = bpy.data.worlds.new("Widowpine preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.008, 0.018, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    bpy.context.scene.world = world
    area_data = bpy.data.lights.new("Moon", "AREA")
    area_data.energy = 3800
    area_data.color = (0.32, 0.5, 0.8)
    area_data.shape = "DISK"
    area_data.size = 12
    area = bpy.data.objects.new("Moon", area_data)
    bpy.context.collection.objects.link(area)
    area.location = (-18, -16, 30)
    point_at(area, Vector((0, 0, 10)))
    fill_data = bpy.data.lights.new("Cold front fill", "AREA")
    fill_data.energy = 1600
    fill_data.color = (0.18, 0.3, 0.55)
    fill_data.shape = "RECTANGLE"
    fill_data.size = 20
    fill = bpy.data.objects.new("Cold front fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (5, -20, 13)
    point_at(fill, Vector((0, 0, 9)))
    camera_data = bpy.data.cameras.new("Camera")
    camera = bpy.data.objects.new("Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (0, -34, 8)
    camera_data.lens = 38
    point_at(camera, Vector((0, 0, 10)))
    bpy.context.scene.camera = camera
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)
    print(f"Saved tree source: {BLEND_PATH}")
    print(f"Saved tree preview: {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
