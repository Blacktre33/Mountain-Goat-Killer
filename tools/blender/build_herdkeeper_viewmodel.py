"""Prepare the Herdkeeper carbine and the gloved forearm for the first-person rig.

Inputs are two Higgsfield image-to-3D results (see assets/LICENSES.md):
  carbine: meshy_v7_image_to_3d (PBR) from art_source/weapon/carbine_ref_b.png
  glove:   hunyuan3d_v3_image_to_3d from art_source/weapon/glove_ref_b.png
Both raw GLBs are too heavy to commit, so pass their paths after "--":
  Blender --background --python tools/blender/build_herdkeeper_viewmodel.py -- carbine.glb glove.glb

The carbine is rotated so the muzzle points down -Z (Godot forward), scaled to a
1.06 m carbine, and split into the parts the viewmodel animates: Bolt (handle and
knob, pivoting on the bore axis), Bell (the charm, pivoting where it hangs) and
Body. A detachable box magazine is modelled here because the generated carbine has
none. Empties mark the muzzle, ejection port and sights. The glove is decimated
and its 4K texture halved.
"""
from pathlib import Path
import math
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "weapon"
CARBINE_LENGTH = 1.06
GLOVE_SCALE = 0.37
SLEEVE_STRETCH = 2.0
BOLT_DROP = 0.024
SLEEVE_SLIM = 0.6


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_mesh(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    assert len(meshes) == 1, meshes
    obj = meshes[0]
    world = obj.matrix_world.copy()
    obj.parent = None
    # Bake any node rotation the importer left on the mesh into its vertices.
    obj.data.transform(world)
    obj.matrix_world = Matrix.Identity(4)
    for o in list(bpy.data.objects):
        if o not in before and o != obj:
            bpy.data.objects.remove(o)
    return obj


def close_hole(bm):
    """Cap the opening a removed part leaves, borrowing UVs from the rim so the cap
    samples the same metal or wood as its surroundings."""
    boundary = [e for e in bm.edges if e.is_boundary]
    if not boundary:
        return
    uv_layer = bm.loops.layers.uv.active
    made = bmesh.ops.holes_fill(bm, edges=boundary, sides=12)["faces"]
    for face in made:
        rim_uvs = []
        for edge in face.edges:
            for other in edge.link_faces:
                if other in made:
                    continue
                for loop in other.loops:
                    rim_uvs.append(loop[uv_layer].uv.copy())
        if not rim_uvs:
            continue
        centre = sum(rim_uvs, rim_uvs[0] * 0.0) / len(rim_uvs)
        for loop in face.loops:
            loop[uv_layer].uv = centre
    bmesh.ops.triangulate(bm, faces=made)


def split_faces(obj, predicate, name):
    """Move faces whose centroid satisfies predicate into a new object."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    picked = [f for f in bm.faces if predicate(f.calc_center_median())]
    part_bm = bmesh.new()
    # Rebuild the picked faces in a fresh mesh that shares UVs and the material.
    uv_layer = bm.loops.layers.uv.active
    part_uv = part_bm.loops.layers.uv.new(uv_layer.name)
    vert_map = {}
    for face in picked:
        verts = []
        for v in face.verts:
            if v.index not in vert_map:
                vert_map[v.index] = part_bm.verts.new(v.co)
            verts.append(vert_map[v.index])
        new_face = part_bm.faces.new(verts)
        new_face.material_index = face.material_index
        for loop, src in zip(new_face.loops, face.loops):
            loop[part_uv].uv = src[uv_layer].uv
    bmesh.ops.delete(bm, geom=picked, context="FACES")
    close_hole(bm)
    bm.to_mesh(obj.data)
    bm.free()
    part_mesh = bpy.data.meshes.new(name)
    part_bm.to_mesh(part_mesh)
    part_bm.free()
    for mat in obj.data.materials:
        part_mesh.materials.append(mat)
    part = bpy.data.objects.new(name, part_mesh)
    bpy.context.scene.collection.objects.link(part)
    print(name, "faces", len(part_mesh.polygons))
    return part


def steel_material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def box(name, center, size, material, bevel=0.004):
    bpy.ops.mesh.primitive_cube_add(location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 2
    bpy.ops.object.modifier_apply(modifier="bevel")
    obj.data.materials.append(material)
    return obj


def set_pivot(obj, pivot):
    """Move the object origin to `pivot` (world space) without moving geometry."""
    obj.data.transform(Matrix.Translation(-Vector(pivot)))
    obj.location = Vector(pivot)


def build_carbine(path):
    body = import_mesh(path)
    body.name = "Body"
    # The generated bolt handle sits on the left; Maren's carbine is right-handed.
    body.data.transform(Matrix.Diagonal((1.0, -1.0, 1.0, 1.0)))
    body.data.flip_normals()
    # Coordinates below are the generated model's own frame: muzzle toward -X,
    # up +Z, bolt handle on the -Y side. Sight line sits at z ~= 0.197.
    bolt = split_faces(body, lambda c: c.z > 0.165 and 0.27 < c.x < 0.38, "Bolt")
    bell = split_faces(body, lambda c: c.z < -0.06 and 0.27 < c.x < 0.38, "Bell")
    # The generated handle stands as tall as the sights and would sit in the middle of
    # the sight picture; drop it so the knob just clears the receiver bridge.
    for vertex in bolt.data.vertices:
        vertex.co.z -= BOLT_DROP

    sights = [v.co for v in body.data.vertices if v.co.z > 0.19 and v.co.x < -0.85]
    sight_y = sum(v.y for v in sights) / len(sights)
    scale = CARBINE_LENGTH / 1.903
    # Origin: rear sight top (x=-0.05), on the sight line. Rotate -90 about Z so the
    # muzzle points to +Y in Blender, which the glTF exporter maps to -Z.
    origin = Vector((-0.05, sight_y, 0.195))
    matrix = Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Scale(scale, 4) @ Matrix.Translation(-origin)

    def to_final(p):
        return matrix @ Vector(p)

    steel = steel_material("MagSteel", (0.045, 0.05, 0.058), 0.7, 0.5)
    brass = steel_material("MagBrass", (0.22, 0.15, 0.06), 0.8, 0.5)
    mag = box("Magazine", (0.145, sight_y, -0.035), (0.095, 0.036, 0.155), steel, 0.005)
    mag.rotation_euler = (0.0, math.radians(-8.0), 0.0)
    bpy.context.view_layer.objects.active = mag
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    plate = box("MagPlate", (0.135, sight_y, -0.112), (0.10, 0.040, 0.014), brass, 0.003)
    plate.rotation_euler = (0.0, math.radians(-8.0), 0.0)
    bpy.context.view_layer.objects.active = plate
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    bpy.ops.object.select_all(action="DESELECT")
    plate.select_set(True)
    mag.select_set(True)
    bpy.context.view_layer.objects.active = mag
    bpy.ops.object.join()
    mag.name = "Magazine"

    for obj in (body, bolt, bell, mag):
        obj.data.transform(matrix)
        obj.location = Vector((0, 0, 0))
    bore_z = 0.135
    set_pivot(bolt, to_final((0.31, sight_y, bore_z)))
    set_pivot(bell, to_final((0.315, sight_y, -0.055)))
    set_pivot(mag, to_final((0.145, sight_y, 0.03)))

    def empty(name, at):
        obj = bpy.data.objects.new(name, None)
        obj.empty_display_type = "PLAIN_AXES"
        obj.location = to_final(at)
        bpy.context.scene.collection.objects.link(obj)
        return obj

    empty("Muzzle", (-0.99, sight_y, bore_z))
    empty("EjectPort", (0.16, sight_y - 0.03, 0.15))
    empty("SightRear", (-0.05, sight_y, 0.195))
    empty("SightFront", (-0.9, sight_y, 0.199))
    return [body, bolt, bell, mag]


def build_glove(path):
    glove = import_mesh(path)
    glove.name = "Glove"
    mod = glove.modifiers.new("decimate", "DECIMATE")
    mod.ratio = 0.055
    bpy.context.view_layer.objects.active = glove
    bpy.ops.object.modifier_apply(modifier="decimate")
    print("glove faces", len(glove.data.polygons))
    for image in bpy.data.images:
        if image.size[0] > 2048:
            image.scale(2048, 2048)
    for mat in glove.data.materials:
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Roughness"].default_value = 0.82
        bsdf.inputs["Metallic"].default_value = 0.0
    # The jacket sleeve is cut short at the image edge: stretch it past the cuff so
    # the forearm stays off-screen through the reload and throw gestures.
    cuff = [v.co for v in glove.data.vertices if -0.19 < v.co.x < -0.15]
    axis_y = sum(v.y for v in cuff) / len(cuff)
    axis_z = sum(v.z for v in cuff) / len(cuff)
    for vertex in glove.data.vertices:
        if vertex.co.x > -0.15:
            # Slim the puffy sleeve toward the shoulder as well as lengthening it.
            slim = 1.0 - SLEEVE_SLIM * min(1.0, (vertex.co.x + 0.15) / 0.2)
            vertex.co.y = axis_y + (vertex.co.y - axis_y) * slim
            vertex.co.z = axis_z + (vertex.co.z - axis_z) * slim
            vertex.co.x = -0.15 + (vertex.co.x + 0.15) * SLEEVE_STRETCH
    # The fist centre becomes the origin; fingertip points to -Z in Godot.
    fist = [v.co for v in glove.data.vertices if -0.45 < v.co.x < -0.2]
    centre = sum(fist, Vector()) / len(fist)
    matrix = Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Scale(GLOVE_SCALE, 4) @ Matrix.Translation(-centre)
    glove.data.transform(matrix)
    return glove


def export(objects, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        obj.select_set(obj in objects or obj.type == "EMPTY")
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / filename),
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_image_format="JPEG",
        export_jpeg_quality=90,
        export_apply=True,
    )


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    carbine_path, glove_path = Path(args[0]), Path(args[1])
    clear_scene()
    parts = build_carbine(carbine_path)
    export(parts, "herdkeeper.glb")
    clear_scene()
    glove = build_glove(glove_path)
    export([glove], "glove.glb")


main()
