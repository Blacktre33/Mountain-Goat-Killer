"""Build the animation-preserving Varkas hero mesh from the CC0 wolf source.

The ordinary warpack keeps the lightweight original. Varkas alone receives a
subdivided, smooth-shaded body so his three-metre silhouette can survive close
first-person framing without changing the proven skeleton or animation set.

Run with:
  Blender --background --python tools/blender/build_varkas_wolverine.py
"""

from __future__ import annotations

from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/wolf/wolf.glb"
BLEND_PATH = ROOT / "art_source/characters/varkas_wolverine.blend"
GLB_PATH = ROOT / "assets/wolf/varkas_wolverine.glb"


def deform_wolverine_silhouette(wolf: bpy.types.Object) -> None:
    """Push the inherited wolf toward a low, broad alpine wolverine.

    The deformation stays in the original skinned mesh, so every source action
    and bone weight survives. It is deliberately strongest at the shoulders,
    jowls, muzzle, and pointed ear tips—the shapes that read most clearly in a
    first-person front view.
    """

    model_to_world = wolf.matrix_world.copy()
    world_to_model = model_to_world.inverted()
    group_names = {group.index: group.name for group in wolf.vertex_groups}
    torso_groups = {"Body", "Back", "Torso", "Torso2", "Torso3"}
    neck_groups = {"Neck1", "Neck2", "Neck3"}
    shoulder_groups = {
        "FrontShoulder.L", "FrontShoulder.R", "BackShoulder.L", "BackShoulder.R",
        "FrontUpperLeg.L", "FrontUpperLeg.R", "BackUpperLeg.L", "BackUpperLeg.R",
    }

    for vertex in wolf.data.vertices:
        weights = {group_names[item.group]: item.weight for item in vertex.groups if item.group in group_names}
        head = weights.get("Head", 0.0)
        ear_weight = max((weight for name, weight in weights.items() if name.startswith("Ear")), default=0.0)
        ear = 1.0 if ear_weight > 0.01 else 0.0
        torso = max((weights.get(name, 0.0) for name in torso_groups), default=0.0)
        neck = max((weights.get(name, 0.0) for name in neck_groups), default=0.0)
        shoulder = max((weights.get(name, 0.0) for name in shoulder_groups), default=0.0)

        point = model_to_world @ vertex.co
        # Some of the source ear mantle is weighted to Head rather than the four
        # named ear bones. Catch that geometric tip region as well so no fox-like
        # triangle survives behind the replacement round ears.
        if head > 0.05 and point.z > 2.34 and abs(point.x) > 0.11 and point.y < -1.72:
            ear = 1.0
        # A wolverine's mass lives across its chest and neck, not in long legs.
        width = 1.0 + torso * 0.38 + neck * 0.34 + shoulder * 0.22
        point.x *= width
        point.z -= torso * 0.08 + neck * 0.12 + shoulder * 0.06

        if head > 0.0:
            # Wider cheek bones and a shorter muzzle remove the fox/wolf read.
            point.x *= 1.0 + head * 0.42
            muzzle = max(0.0, min(1.0, (-1.86 - point.y) / 0.66))
            shortened_y = -1.86 + (point.y + 1.86) * 0.46
            point.y += (shortened_y - point.y) * head * muzzle
            point.z -= head * 0.09

        if ear > 0.0:
            # Pull the tall triangular tips into the small rounded ears of a
            # wolverine while retaining enough motion from all four ear bones.
            rounded_z = 2.19 + (point.z - 2.19) * 0.05
            point.z += (rounded_z - point.z) * ear
            point.x *= 1.0 - ear * 0.24
            point.y += (-2.0 - point.y) * ear * 0.28

        vertex.co = world_to_model @ point


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.armatures,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def main() -> None:
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))

    # The source package carries a showcase camera, light, floor cube, and marker
    # sphere beside the actual rig. Keep only the rooted animated character.
    for obj in list(bpy.context.scene.objects):
        if obj.name in {"Cube", "Camera", "Light", "Icosphere"} and obj.parent is None:
            bpy.data.objects.remove(obj, do_unlink=True)

    wolf = bpy.data.objects.get("Wolf")
    if wolf is None or wolf.type != "MESH":
        raise RuntimeError("CC0 wolf mesh was not found after import")

    deform_wolverine_silhouette(wolf)

    # The glTF carries split vertices for its intentional low-poly hard edges.
    # Welding coincident positions first prevents Catmull-Clark from shrinking
    # every triangle into a disconnected scale while retaining per-loop UVs.
    bpy.context.view_layer.objects.active = wolf
    wolf.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.00001)
    bpy.ops.object.mode_set(mode="OBJECT")
    for polygon in wolf.data.polygons:
        polygon.use_smooth = True
    subdivision = wolf.modifiers.new("Varkas closeup subdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 1
    subdivision.render_levels = 1
    # Put subdivision before skinning so the interpolated weights remain usable
    # for every inherited walk, charge, hit, and death animation.
    while list(wolf.modifiers).index(subdivision) > 0:
        bpy.ops.object.modifier_move_up(modifier=subdivision.name)
    bpy.ops.object.modifier_apply(modifier=subdivision.name)
    # The original low-poly animal uses tiny palette UV islands. Repack the
    # hero after subdivision so actual guard-hair detail spans each surface
    # and follows the skin during all inherited animations.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.025)
    bpy.ops.object.mode_set(mode="OBJECT")
    wolf.select_set(False)

    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_skins=True,
        export_materials="EXPORT",
    )
    print(f"Varkas source vertices: 3,994 -> {len(wolf.data.vertices):,}")
    print(f"Saved Blender source: {BLEND_PATH}")
    print(f"Saved Godot GLB: {GLB_PATH}")


if __name__ == "__main__":
    main()
