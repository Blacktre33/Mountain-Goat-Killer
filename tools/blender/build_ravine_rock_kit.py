"""Build an original, PBR ravine-rock kit for the three playable biomes.

The meshes are intentionally compact enough for Godot MultiMesh scattering.
Their silhouettes, UVs, and collision-safe origins are authored here; the
surface maps are Poly Haven's CC0 Dark Rock texture set.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector, noise


ROOT = Path(__file__).resolve().parents[2]
TEXTURE_DIR = ROOT / "assets/materials/polyhaven/dark_rock"
EXPORT_DIR = ROOT / "assets/environment/rocks"
BLEND_PATH = ROOT / "art_source/rocks/ravine_rock_kit.blend"
PREVIEW_PATH = ROOT / "art_direction/shared/ravine-rock-kit-v1.png"


ROCKS = (
    ("ravine_boulder_a", 17, (1.18, 0.92, 0.74), 0.16, 0.06, 0.0),
    ("ravine_boulder_b", 31, (0.92, 1.15, 0.82), 0.20, 0.08, 0.0),
    ("ravine_boulder_c", 53, (1.34, 0.76, 0.62), 0.14, 0.05, 0.0),
    ("ravine_cliff_a", 79, (0.78, 1.06, 1.48), 0.18, 0.13, 0.03),
    ("ravine_cliff_b", 101, (1.02, 0.74, 1.72), 0.22, 0.16, -0.04),
    ("ravine_cliff_c", 137, (0.70, 1.24, 1.30), 0.17, 0.11, 0.05),
)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def load_image(name: str, *, non_color: bool = False) -> bpy.types.Image:
    image = bpy.data.images.load(str(TEXTURE_DIR / name), check_existing=True)
    if non_color:
        image.colorspace_settings.name = "Non-Color"
    return image


def dark_rock_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("Ravine dark rock")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.11, 0.13, 0.15, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.94

    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.55, 1.55, 1.55)
    links.new(uv.outputs["UV"], mapping.inputs["Vector"])

    diffuse = nodes.new("ShaderNodeTexImage")
    diffuse.image = load_image("dark_rock_Diffuse.jpg")
    roughness = nodes.new("ShaderNodeTexImage")
    roughness.image = load_image("dark_rock_Rough.jpg", non_color=True)
    normal_texture = nodes.new("ShaderNodeTexImage")
    normal_texture.image = load_image("dark_rock_nor_gl.jpg", non_color=True)
    for texture in (diffuse, roughness, normal_texture):
        links.new(mapping.outputs["Vector"], texture.inputs["Vector"])

    # Slight blue-black multiplication keeps the imported material inside the
    # ravine's night palette without destroying the scanned stone variation.
    tint = nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 0.34
    tint.inputs[2].default_value = (0.18, 0.24, 0.30, 1.0)
    links.new(diffuse.outputs["Color"], tint.inputs[1])
    links.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(roughness.outputs["Color"], bsdf.inputs["Roughness"])

    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.72
    links.new(normal_texture.outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_rock(
    name: str,
    seed: int,
    dimensions: tuple[float, float, float],
    fracture: float,
    strata: float,
    lean: float,
    mat: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0.0, 0.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.scale = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    offset = Vector((seed * 0.071, seed * -0.043, seed * 0.029))
    bottom = min(vertex.co.z for vertex in obj.data.vertices)
    top = max(vertex.co.z for vertex in obj.data.vertices)
    height = max(0.001, top - bottom)
    for vertex in obj.data.vertices:
        point = vertex.co.copy()
        direction = point.normalized()
        sample = point * 1.65 + offset
        coarse = noise.noise_vector(sample, noise_basis="PERLIN_NEW")
        fine = noise.noise_vector(sample * 2.8 + Vector((3.1, -1.7, 2.4)), noise_basis="PERLIN_NEW")
        layer = math.sin((point.z + seed * 0.013) * 13.0) * strata
        displacement = coarse.x * fracture + fine.y * fracture * 0.32 + layer
        vertex.co += direction * displacement
        normalized_height = (point.z - bottom) / height
        vertex.co.x += lean * (normalized_height - 0.35)
        # A broad foot makes the scatter sit in snow instead of balancing on a point.
        if normalized_height < 0.13:
            vertex.co.z = bottom + height * 0.055 + (normalized_height * height * 0.18)

    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(58.0), island_margin=0.025)
    bpy.ops.object.mode_set(mode="OBJECT")

    bevel = obj.modifiers.new("Weathered fracture edges", "BEVEL")
    bevel.width = 0.035
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(34.0)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.data.update()

    # Origins lie on the ground plane so Godot's terrain snapping and sinking
    # remain predictable for every random scale.
    lowest = min(vertex.co.z for vertex in obj.data.vertices)
    for vertex in obj.data.vertices:
        vertex.co.z -= lowest
    return obj


def export_object(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(EXPORT_DIR / f"{obj.name}.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )


def add_preview_stage(objects: list[bpy.types.Object]) -> None:
    positions = (
        (-4.6, 1.3, 0.0), (-1.5, 1.3, 0.0), (1.6, 1.3, 0.0),
        (-3.2, -1.4, 0.0), (0.0, -1.4, 0.0), (3.3, -1.4, 0.0),
    )
    for obj, (x, y, z) in zip(objects, positions):
        obj.location = (x, y, z)

    bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0.0, 0.0, -0.04))
    ground = bpy.context.object
    ground.name = "Preview ground"
    ground_mat = bpy.data.materials.new("Preview snow")
    ground_mat.diffuse_color = (0.08, 0.10, 0.13, 1.0)
    ground_mat.use_nodes = True
    ground_bsdf = ground_mat.node_tree.nodes.get("Principled BSDF")
    ground_bsdf.inputs["Base Color"].default_value = ground_mat.diffuse_color
    ground_bsdf.inputs["Roughness"].default_value = 0.86
    ground.data.materials.append(ground_mat)

    bpy.ops.object.light_add(type="AREA", location=(-4.0, -4.0, 8.5))
    key = bpy.context.object
    key.name = "Cold key"
    key.data.energy = 1200.0
    key.data.shape = "DISK"
    key.data.size = 7.0
    key.data.color = (0.50, 0.67, 0.88)
    key.rotation_euler = (math.radians(18.0), 0.0, math.radians(-32.0))

    bpy.ops.object.light_add(type="AREA", location=(5.0, 1.0, 4.0))
    rim = bpy.context.object
    rim.name = "Warm rim"
    rim.data.energy = 750.0
    rim.data.size = 5.0
    rim.data.color = (1.0, 0.31, 0.12)
    rim.rotation_euler = (math.radians(42.0), 0.0, math.radians(112.0))

    bpy.ops.object.camera_add(location=(8.8, -13.5, 7.3))
    camera = bpy.context.object
    camera.name = "Rock kit camera"
    camera.data.lens = 52.0
    direction = Vector((0.0, 0.0, 1.0)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.world.color = (0.008, 0.012, 0.021)
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)


def main() -> None:
    for directory in (EXPORT_DIR, BLEND_PATH.parent, PREVIEW_PATH.parent):
        directory.mkdir(parents=True, exist_ok=True)
    reset_scene()
    mat = dark_rock_material()
    rocks = [make_rock(name, seed, dimensions, fracture, strata, lean, mat) for name, seed, dimensions, fracture, strata, lean in ROCKS]
    for rock in rocks:
        export_object(rock)
    add_preview_stage(rocks)
    print(f"Wrote {len(rocks)} rock GLBs to {EXPORT_DIR}")
    print(f"Wrote {BLEND_PATH}")
    print(f"Wrote {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
