"""Prepare the warpack's generated wolverine head for the game.

The head was generated with Higgsfield (Hunyuan3D v3 image-to-3D, job
b2449030-3517-414a-8c1b-32649924e537) from a gpt_image_2_5 concept of a snarling,
scarred wolverine in a spiked iron collar. The raw result is ~500k triangles with
a 4096 px texture; this script decimates it to a game budget, downsizes the
texture, faces it down -Z (Godot forward), and pivots it at the base of the neck
so scripts/enemy.gd can mount it rigidly on the rig's Head bone.

The raw generation is not committed (33 MB). Save it as
art_source/characters/wolverine_head_higgsfield_raw.glb, or pass another path
after `--`, then run:
  Blender --background --python tools/blender/build_varkas_pack_head.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/characters/wolverine_head_higgsfield_raw.glb"
BLEND_PATH = ROOT / "art_source/characters/wolverine_head.blend"
GLB_PATH = ROOT / "assets/wolf/wolverine_head.glb"
TARGET_TRIANGLES = 28000
TEXTURE_SIZE = 2048


def main() -> None:
    source = SOURCE
    if "--" in sys.argv and len(sys.argv) > sys.argv.index("--") + 1:
        source = Path(sys.argv[sys.argv.index("--") + 1])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    head = meshes[0]
    for extra in meshes[1:]:
        bpy.data.objects.remove(extra, do_unlink=True)
    head.name = "WolverineHead"
    bpy.context.view_layer.objects.active = head
    head.select_set(True)

    # Face -Z in Godot (+Y in Blender); the generator faces -Y.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    head.data.transform(Matrix.Rotation(3.141592653589793, 4, "Z"))

    triangles = sum(len(polygon.vertices) - 2 for polygon in head.data.polygons)
    decimate = head.modifiers.new("Game budget", "DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = min(1.0, TARGET_TRIANGLES / max(1, triangles))
    decimate.use_collapse_triangulate = True
    decimate.delimit = {"UV"}
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    for polygon in head.data.polygons:
        polygon.use_smooth = True

    # Pivot: centred across, at the back of the skull, on the bottom of the head.
    corners = [Vector(corner) for corner in head.bound_box]
    low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    pivot = Vector(((low.x + high.x) * 0.5, low.y + (high.y - low.y) * 0.25, low.z + (high.z - low.z) * 0.3))
    head.data.transform(Matrix.Translation(-pivot))

    for image in bpy.data.images:
        if image.size[0] > TEXTURE_SIZE:
            image.scale(TEXTURE_SIZE, TEXTURE_SIZE)
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_image_format="JPEG",
        export_jpeg_quality=88,
        export_materials="EXPORT",
    )
    print(f"Head: {triangles:,} -> ~{TARGET_TRIANGLES:,} triangles, saved {GLB_PATH}")


if __name__ == "__main__":
    main()
