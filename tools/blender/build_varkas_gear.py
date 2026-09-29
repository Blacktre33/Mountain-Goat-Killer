"""Build the warpack's dressing: harness rifle, forged pauldrons, spiked collar,
spine plates, and a cast neck-bell.

Every piece is an independent object with its pivot at its natural mount point
and its long axis along -Z (Godot forward), so scripts/enemy.gd can pick pieces
by name and parent them to bones. Materials are placeholders named Iron, Wood,
Brass, and Leather; the game replaces them with its own PBR sets.

Run with:
  Blender --background --python tools/blender/build_varkas_gear.py
"""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
BLEND_PATH = ROOT / "art_source/characters/varkas_gear.blend"
GLB_PATH = ROOT / "assets/wolf/varkas_gear.glb"


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name: str, color: tuple[float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    node = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = (*color, 1.0)
    return mat


MATERIALS: dict[str, bpy.types.Material] = {}


def mat(name: str) -> bpy.types.Material:
    if not MATERIALS:
        MATERIALS["Iron"] = material("Iron", (0.22, 0.23, 0.25))
        MATERIALS["Wood"] = material("Wood", (0.25, 0.15, 0.08))
        MATERIALS["Brass"] = material("Brass", (0.75, 0.55, 0.22))
        MATERIALS["Leather"] = material("Leather", (0.12, 0.08, 0.06))
    return MATERIALS[name]


class Piece:
    """Accumulates primitive parts into one mesh with per-part materials."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.bm = bmesh.new()
        self.slots: list[str] = []

    def _slot(self, material_name: str) -> int:
        if material_name not in self.slots:
            self.slots.append(material_name)
        return self.slots.index(material_name)

    def box(self, size, center, material_name="Iron", rotate=(0.0, 0.0, 0.0), bevel=0.0, taper=1.0) -> None:
        matrix = Matrix.Translation(center) @ Matrix.Rotation(rotate[2], 4, "Z") @ Matrix.Rotation(rotate[1], 4, "Y") @ Matrix.Rotation(rotate[0], 4, "X")
        geometry = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = geometry["verts"]
        for vert in verts:
            vert.co = Vector((vert.co.x * size[0], vert.co.y * size[1], vert.co.z * size[2]))
            if taper != 1.0 and vert.co.z < 0.0:
                vert.co.x *= taper
                vert.co.y *= taper
        bmesh.ops.transform(self.bm, matrix=matrix, verts=verts)
        slot = self._slot(material_name)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = slot
        if bevel > 0.0:
            edges = {e for v in verts for e in v.link_edges}
            bmesh.ops.bevel(self.bm, geom=list(edges) + verts, offset=bevel, segments=2, affect="EDGES")

    def cylinder(self, radius, depth, center, axis="Z", material_name="Iron", radius2=None, segments=14) -> None:
        radius2 = radius if radius2 is None else radius2
        geometry = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius2, depth=depth)
        verts = geometry["verts"]
        rotation = {
            "Z": Matrix.Identity(4),
            "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
            "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
        }[axis]
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(center) @ rotation, verts=verts)
        slot = self._slot(material_name)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = slot

    def spike(self, base, tip, radius, material_name="Iron") -> None:
        direction = Vector(tip) - Vector(base)
        geometry = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=6, radius1=radius, radius2=0.0, depth=direction.length)
        verts = geometry["verts"]
        rotation = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized()).to_matrix().to_4x4()
        center = (Vector(base) + Vector(tip)) * 0.5
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(center) @ rotation, verts=verts)
        slot = self._slot(material_name)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = slot

    def build(self) -> bpy.types.Object:
        # Parts are authored in Godot space (Y up, -Z forward); Blender is Z up
        # with +Y forward, and the glTF exporter converts back.
        to_blender = Matrix(((1.0, 0.0, 0.0, 0.0), (0.0, 0.0, -1.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)))
        bmesh.ops.transform(self.bm, matrix=to_blender, verts=self.bm.verts)
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        for slot in self.slots:
            mesh.materials.append(mat(slot))
        # Give each hard-surface part a UV so a tiling material reads plate-like.
        bpy.context.view_layer.update()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.cube_project(cube_size=0.5)
        bpy.ops.object.mode_set(mode="OBJECT")
        obj.select_set(False)
        return obj


def build_rifle() -> Piece:
    """A war-carbine on a harness: receiver at origin, muzzle at z = -0.98."""
    rifle = Piece("Rifle")
    # Stock and grip.
    rifle.box((0.075, 0.13, 0.36), (0.0, -0.035, 0.31), "Wood", bevel=0.012, taper=0.8)
    rifle.box((0.05, 0.11, 0.05), (0.0, -0.05, 0.13), "Wood", rotate=(0.5, 0.0, 0.0))
    rifle.box((0.082, 0.05, 0.08), (0.0, -0.11, 0.49), "Iron", bevel=0.01)
    # Receiver and bolt.
    rifle.box((0.075, 0.11, 0.30), (0.0, 0.0, 0.0), "Iron", bevel=0.01)
    rifle.cylinder(0.018, 0.10, (0.075, 0.02, 0.06), axis="X", material_name="Brass", segments=8)
    rifle.cylinder(0.014, 0.05, (0.13, 0.02, 0.06), axis="X", material_name="Iron", segments=8)
    # Magazine.
    rifle.box((0.05, 0.14, 0.09), (0.0, -0.12, -0.02), "Iron", rotate=(-0.12, 0.0, 0.0), bevel=0.008)
    # Wooden handguard and heavy barrel with a shroud.
    rifle.box((0.07, 0.085, 0.36), (0.0, -0.01, -0.33), "Wood", bevel=0.01)
    rifle.cylinder(0.024, 0.66, (0.0, 0.02, -0.65), axis="Z", material_name="Iron", segments=12)
    rifle.cylinder(0.034, 0.10, (0.0, 0.02, -0.90), axis="Z", material_name="Iron", segments=12)
    for step in range(3):
        rifle.cylinder(0.036, 0.012, (0.0, 0.02, -0.87 - step * 0.04), axis="Z", material_name="Iron", segments=12)
    # Sights and a scope tube riveted on top.
    rifle.box((0.012, 0.03, 0.012), (0.0, 0.075, -0.92), "Iron")
    rifle.cylinder(0.027, 0.28, (0.0, 0.095, -0.02), axis="Z", material_name="Iron", segments=12)
    rifle.cylinder(0.034, 0.03, (0.0, 0.095, -0.17), axis="Z", material_name="Iron", segments=12)
    rifle.cylinder(0.030, 0.03, (0.0, 0.095, 0.12), axis="Z", material_name="Iron", segments=12)
    rifle.box((0.02, 0.05, 0.02), (0.0, 0.055, -0.08), "Iron")
    rifle.box((0.02, 0.05, 0.02), (0.0, 0.055, 0.06), "Iron")
    # Sling: two leather loops.
    rifle.box((0.012, 0.09, 0.03), (0.0, -0.085, -0.25), "Leather")
    rifle.box((0.012, 0.09, 0.03), (0.0, -0.085, 0.44), "Leather")
    # Bayonet-like blade under the muzzle: these wolverines finish what they shoot.
    rifle.box((0.012, 0.03, 0.22), (0.0, -0.035, -0.86), "Iron", taper=0.5)
    return rifle


def build_pauldron(side: float) -> Piece:
    """A curved forged plate over the shoulder, spiked. Mounted at the shoulder joint."""
    name = "Pauldron_L" if side < 0 else "Pauldron_R"
    plate = Piece(name)
    for index in range(4):
        angle = -0.35 + index * 0.24
        plate.box(
            (0.34, 0.03, 0.15),
            (side * (0.02 + 0.12 * math.sin(angle * 1.4)), 0.16 - 0.06 * abs(angle) * 2.0, -0.14 + index * 0.115),
            "Iron",
            rotate=(0.0, 0.0, side * (0.35 + 0.18 * math.sin(angle * 2))),
            bevel=0.006,
        )
    plate.spike((side * 0.14, 0.17, -0.06), (side * 0.20, 0.42, -0.10), 0.032)
    plate.spike((side * 0.10, 0.19, 0.10), (side * 0.14, 0.40, 0.14), 0.028)
    plate.spike((side * 0.06, 0.19, 0.02), (side * 0.07, 0.48, 0.00), 0.03)
    plate.cylinder(0.012, 0.03, (side * 0.15, 0.14, 0.02), axis="Y", material_name="Brass", segments=8)
    return plate


def build_collar() -> Piece:
    """A heavy spiked neck-ring with a bell hoop; ring axis is Y."""
    collar = Piece("Collar")
    segments = 14
    for index in range(segments):
        angle = index / segments * math.tau
        x = math.cos(angle) * 0.26
        z = math.sin(angle) * 0.26
        collar.box((0.10, 0.09, 0.05), (x, 0.0, z), "Iron", rotate=(0.0, -angle + math.pi / 2, 0.0), bevel=0.008)
        if index % 2 == 0:
            collar.spike((x * 1.08, 0.0, z * 1.08), (x * 1.55, 0.06, z * 1.55), 0.022)
    collar.cylinder(0.02, 0.10, (0.0, -0.02, 0.26), axis="Y", material_name="Brass", segments=8)
    return collar


def build_spine_plate() -> Piece:
    """One overlapping back plate with a ridge spike; stacked three times on the spine."""
    plate = Piece("SpinePlate")
    plate.box((0.42, 0.04, 0.28), (0.0, 0.0, 0.0), "Iron", bevel=0.01)
    plate.box((0.36, 0.03, 0.22), (0.0, 0.03, 0.02), "Iron", rotate=(0.08, 0.0, 0.0), bevel=0.008)
    plate.spike((0.0, 0.04, 0.0), (0.0, 0.26, 0.04), 0.045)
    plate.cylinder(0.018, 0.03, (0.14, 0.05, 0.05), axis="Y", material_name="Brass", segments=8)
    plate.cylinder(0.018, 0.03, (-0.14, 0.05, 0.05), axis="Y", material_name="Brass", segments=8)
    return plate


def build_bell() -> Piece:
    """A neck-bell: lathe profile, open mouth down, hoop and clapper. Pivot at the hoop."""
    bell = Piece("Bell")
    profile = [(0.0, 0.0), (0.045, 0.0), (0.06, -0.04), (0.075, -0.10), (0.095, -0.16), (0.12, -0.21), (0.125, -0.225), (0.10, -0.225), (0.085, -0.20), (0.065, -0.14), (0.05, -0.09), (0.0, -0.06)]
    rings = 18
    vertices = []
    for ring in range(rings):
        angle = ring / rings * math.tau
        for radius, height in profile:
            vertices.append(bell.bm.verts.new((math.cos(angle) * radius, height, math.sin(angle) * radius)))
    count = len(profile)
    for ring in range(rings):
        next_ring = (ring + 1) % rings
        for index in range(count - 1):
            face = bell.bm.faces.new((
                vertices[ring * count + index],
                vertices[next_ring * count + index],
                vertices[next_ring * count + index + 1],
                vertices[ring * count + index + 1],
            ))
            face.material_index = bell._slot("Brass")
    bmesh.ops.recalc_face_normals(bell.bm, faces=bell.bm.faces)
    bell.cylinder(0.018, 0.03, (0.0, 0.03, 0.0), axis="Z", material_name="Iron", segments=8)
    bell.cylinder(0.014, 0.08, (0.0, -0.20, 0.0), axis="Y", material_name="Iron", segments=8)
    bell.spike((0.0, -0.17, 0.0), (0.0, -0.24, 0.0), 0.025)
    return bell


def main() -> None:
    reset_scene()
    objects = [
        build_rifle().build(),
        build_pauldron(-1.0).build(),
        build_pauldron(1.0).build(),
        build_collar().build(),
        build_spine_plate().build(),
        build_bell().build(),
    ]
    BLEND_PATH.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_materials="EXPORT",
        export_yup=True,
    )
    print(f"Exported {len(objects)} gear pieces to {GLB_PATH}")


if __name__ == "__main__":
    main()
