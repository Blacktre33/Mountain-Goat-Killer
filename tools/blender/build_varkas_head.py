"""Sculpt a joined wolverine face and short guard-fur silhouette for Godot.

Authored in the existing hero shell's coordinates; does not replace the rig.
Blender --background --python tools/blender/build_varkas_head.py
"""
from pathlib import Path
import math
import random

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
rng = random.Random(7083)

def point(x, y, z):
    return Vector((x, -z, y))

def material(name, color, roughness=0.94):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color, 1)
    principled.inputs["Roughness"].default_value = roughness
    return mat

def oval(name, at, size):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=point(*at))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return obj

def mask_region(p):
    x, z, y = p.x, -p.y, p.z
    # Broken pale cheek band outside the eyes, narrowing toward the muzzle.
    edge = 0.20 + max(0, y - 2.18) * 0.45 + .015 * math.sin(y * 71 + x * 32)
    return abs(x) > edge and 2.13 + x * .035 < y < 2.39 + x * .025 and z < -2.63

def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    shapes = [
        ("Cranium", (0, 2.30, -2.64), (.43, .29, .35)),
        ("Forehead", (0, 2.44, -2.72), (.35, .18, .26)),
        ("MuzzleBridge", (0, 2.23, -2.96), (.235, .145, .20)),
        ("LeftMuzzle", (-.095, 2.16, -3.025), (.15, .105, .155)),
        ("RightMuzzle", (.095, 2.17, -3.025), (.15, .105, .155)),
        ("Jaw", (0, 2.015, -2.94), (.235, .075, .20)),
    ]
    for side in [-1, 1]:
        shapes += [
            ("Cheek", (side * .29, 2.24, -2.72), (.165, .17, .21)),
            ("Brow", (side * .20, 2.39, -2.90), (.22, .085, .135)),
            ("Ear", (side * .37, 2.565, -2.57), (.115, .14, .10)),
        ]
    parts = [oval(*shape) for shape in shapes]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    head = bpy.context.object
    head.name = "VarkasSculptedHead"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    union = head.modifiers.new("Continuous facial anatomy", "REMESH")
    union.mode = "VOXEL"
    union.voxel_size = .018
    union.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=union.name)
    smooth = head.modifiers.new("Soften joined planes", "SMOOTH")
    smooth.factor = .72
    smooth.iterations = 3
    bpy.ops.object.modifier_apply(modifier=smooth.name)

    # Carve an actual mouth opening, leaving the cheeks joined at the rear.
    bpy.ops.mesh.primitive_cube_add(location=point(0, 2.09, -3.08))
    mouth = bpy.context.object
    mouth.scale = (.22, .15, .018)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.context.view_layer.objects.active = head
    cut = head.modifiers.new("Closed snarl", "BOOLEAN")
    cut.operation = "DIFFERENCE"
    cut.object = mouth
    bpy.ops.object.modifier_apply(modifier=cut.name)
    bpy.data.objects.remove(mouth, do_unlink=True)
    dark = material("VarkasHeadDark", (.075, .064, .050))
    pale = material("VarkasHeadCheek", (.15, .128, .085))
    head.data.materials.clear()
    head.data.materials.append(dark)
    head.data.materials.append(pale)
    for polygon in head.data.polygons:
        polygon.use_smooth = True
        polygon.material_index = 1 if mask_region(polygon.center) else 0
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Tapered, bent ribbons: short surface nap and longer broken cheek edges.
    vertices, faces, indices = [], [], []
    for vertex in head.data.vertices:
        if rng.random() > .40:
            continue
        at, normal = vertex.co.copy(), vertex.normal.normalized()
        scar_x = .23 + .14 * (2.47 - at.z) / .25
        if 2.22 < at.z < 2.47 and abs(at.x - scar_x) < .018 and -at.y < -2.65:
            continue
        if -at.y < -3.04 or normal.length < .5:
            continue  # nose and lips stay short-haired
        mask = mask_region(at)
        flow = Vector((at.x * .35, -.22, -.9))
        flow = (flow - normal * flow.dot(normal)).normalized()
        if flow.length < .1:
            continue
        length = rng.uniform(.022, .058) * (1.4 if mask else 1.0)
        across = flow.cross(normal).normalized() * rng.uniform(.0025, .005)
        base = at + normal * .003
        middle = base + flow * length * .5 + normal * length * .18
        tip = base + flow * length + normal * length * .12
        offset = len(vertices)
        vertices.extend([base - across, base + across, middle - across * .5,
                         middle + across * .5, tip])
        faces.extend([(offset, offset+1, offset+3, offset+2), (offset+2, offset+3, offset+4)])
        shade = rng.randrange(3) + (3 if mask else 0)
        indices.extend([shade, shade])
    mesh = bpy.data.meshes.new("Short guard-fur ribbons")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    fur = bpy.data.objects.new("VarkasGuardFur", mesh)
    bpy.context.collection.objects.link(fur)
    for i, color in enumerate([(.065,.056,.043),(.10,.086,.061),(.048,.042,.030),
                               (.19,.16,.11),(.25,.22,.15),(.14,.12,.079)]):
        mesh.materials.append(material(f"VarkasGuardHair{i}", color))
    for polygon, index in zip(mesh.polygons, indices):
        polygon.material_index = index
        polygon.use_smooth = True

    # A thin, irregular healed cut follows the sculpt's surface on one cheek.
    tree = BVHTree.FromObject(head, bpy.context.evaluated_depsgraph_get())
    scar_points = []
    for i in range(13):
        t = i / 12
        x, y = .23 + t * .14 + .004 * math.sin(t * 19), 2.47 - t * .25
        location, normal, _, _ = tree.ray_cast(point(x, y, -4), Vector((0, -1, 0)))
        if location is not None:
            scar_points.append(location + normal * .006)
    scar_curve = bpy.data.curves.new("Old healed cheek wound", "CURVE")
    scar_curve.dimensions = "3D"
    scar_curve.bevel_depth = .006
    scar_curve.bevel_resolution = 2
    scar_spline = scar_curve.splines.new("POLY")
    scar_spline.points.add(len(scar_points) - 1)
    for p, co in zip(scar_spline.points, scar_points):
        p.co = (*co, 1)
    scar = bpy.data.objects.new("VarkasHealedScar", scar_curve)
    bpy.context.collection.objects.link(scar)
    scar_curve.materials.append(material("VarkasOldScar", (.065, .027, .021)))
    out = ROOT / "assets/wolf/varkas_head.glb"
    source = ROOT / "art_source/characters/varkas_head.blend"
    source.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", use_selection=True,
                              export_animations=False, export_materials="EXPORT")
    print(f"Joined head: {len(head.data.vertices)} vertices; fur: {len(faces)} polygons")

if __name__ == "__main__":
    main()
