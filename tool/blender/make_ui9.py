"""Tab tiles, 1:1 after the reference image (user 2026-11-07): a dark steel-blue
tile with chamfered corners and a double gold rim, the glyph standing on it —
hammer (Build), PAW (Monsters, in place of the reference's people) and a
parchment map with a red X.

    blender --background --python tool/blender/make_ui9.py -- \
        tile_hammer tile_paw tile_map [--samples N --px N]

Built with make_ui4's voxelizer + material kit, vivid grade like make_ui6.
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_ui4  # noqa: E402
import make_ui as U  # noqa: E402
import icon_lib as L  # noqa: E402
from make_ui4 import vox, finish, turn_y  # noqa: E402
from icon_lib import box, ball, poly  # noqa: E402
from pro_kit import plain  # noqa: E402

_C = {}


def cm(name, col, rough=0.5, metal=0.0, bump=0.0):
    key = 'tl_' + name
    m = _C.get(key)
    try:
        if m is not None:
            m.name
            return m
    except ReferenceError:
        pass
    m = plain(key, col, rough=rough, metal=metal, bump=bump, bump_scale=70, vary=0.02)
    _C[key] = m
    return m


def octo(h, c, step=0.0):
    """A square of half-size h with its corners cut by c (45 deg)."""
    pts = []
    for sx, sz in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
        # walk each corner: along x edge, cut, along z edge
        pts.append((sx * (h - c), sz * h))
        pts.append((sx * h, sz * (h - c)))
    # order counter-clockwise starting at the top right
    pts = [(h - c, h), (-(h - c), h), (-h, h - c), (-h, -(h - c)),
           (-(h - c), -h), (h - c, -h), (h, -(h - c)), (h, h - c)]
    return pts


def ring_poly(outer, inner, front, depth, m):
    """A flat frame between two matching outlines, its front face at y=front."""
    import bmesh
    bm = bmesh.new()
    vo = [bm.verts.new((x, front, z)) for x, z in outer]
    vi = [bm.verts.new((x, front, z)) for x, z in inner]
    n = len(outer)
    fs = [bm.faces.new((vo[i], vo[(i + 1) % n], vi[(i + 1) % n], vi[i])) for i in range(n)]
    r = bmesh.ops.extrude_face_region(bm, geom=fs)
    nv = [v for v in r['geom'] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, depth, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new('ring_poly')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('ring_poly', me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(m)
    return ob


def solid(pts, front, depth, m):
    return poly(pts, depth, m, y=front + depth / 2, bev=0.0)


def tile():
    _C.clear()
    L.reset_materials()
    solid(octo(1.00, 0.25), -0.02, 0.30, cm('rim_dk', '#7a4a10', 0.45, 0.4))
    ring_poly(octo(0.96, 0.23), octo(0.86, 0.19), -0.12, 0.30, cm('rim', '#f2a52c', 0.30, 0.8))
    ring_poly(octo(0.86, 0.19), octo(0.82, 0.17), -0.04, 0.30, cm('gap', '#121923', 0.6))
    ring_poly(octo(0.82, 0.17), octo(0.76, 0.15), -0.07, 0.30, cm('edge', '#3d5879', 0.55))
    solid(octo(0.76, 0.15), -0.05, 0.30, cm('panel', '#1c2d48', 0.6))


GY = -0.20  # glyph depth: just in front of the panel


def glyph_hammer():
    wood = cm('wood', '#c8641e', 0.55)
    grey = cm('grey', '#8d8f92', 0.4, 0.3)
    greyd = cm('greyd', '#3b3d41', 0.5, 0.3)
    gold = cm('gold', '#f7a921', 0.3, 0.9)
    before = L.snapshot()
    box(0, GY, -0.12, 0.16, 0.16, 1.30, wood, bev=0.0)
    box(0, GY, -0.78, 0.22, 0.20, 0.14, gold, bev=0.0)
    box(0, GY, 0.52, 0.98, 0.42, 0.40, grey, bev=0.0)
    box(0.52, GY, 0.52, 0.12, 0.44, 0.46, greyd, bev=0.0)
    box(-0.52, GY, 0.52, 0.12, 0.44, 0.46, greyd, bev=0.0)
    box(0.0, GY, 0.52, 0.15, 0.46, 0.44, gold, bev=0.0)
    turn_y(L.new_since(before), -42)


def glyph_paw():
    gold = cm('pgold', '#f7b52a', 0.3, 0.9)
    goldd = cm('pgoldd', '#c98a10', 0.4, 0.9)
    ball(0, GY, -0.20, 0.42, 0.14, 0.34, gold, seg=24)
    for x, z, rx, rz, a in ((-0.52, 0.18, 0.15, 0.21, 28), (-0.20, 0.52, 0.15, 0.22, 10),
                            (0.20, 0.52, 0.15, 0.22, -10), (0.52, 0.18, 0.15, 0.21, -28)):
        ball(x, GY, z, rx, 0.13, rz, gold, seg=18, rot=(0, a, 0))


def glyph_map():
    paper = cm('paper', '#ecd9a4', 0.8)
    paperd = cm('paperd', '#c89a52', 0.8)
    red = cm('red', '#d8281e', 0.5)
    ink = cm('ink', '#7a5424', 0.8)
    before = L.snapshot()
    for x, c in ((-0.42, '#e6cf98'), (0.0, '#f1e0b0'), (0.42, '#e6cf98')):
        box(x, GY, 0, 0.46, 0.07, 1.05, cm('leaf' + c, c, 0.8), bev=0.0)
    box(0, GY, 0.55, 1.34, 0.06, 0.07, paperd, bev=0.0)
    box(0, GY, -0.55, 1.34, 0.06, 0.07, paperd, bev=0.0)
    for x, z in ((-0.42, 0.22), (-0.28, 0.06), (-0.12, -0.04), (0.04, -0.16), (0.2, -0.3)):
        box(x, GY - 0.05, z, 0.07, 0.03, 0.07, ink, bev=0.0)
    for a in (45, -45):
        box(0.36, GY - 0.06, 0.2, 0.34, 0.04, 0.09, red, rot=(0, a, 0), bev=0.0)
    box(-0.5, GY - 0.05, -0.28, 0.26, 0.03, 0.18, cm('mapg', '#8aa856', 0.7), bev=0.0)
    turn_y(L.new_since(before), 8)


def make(glyph):
    def piece(M):
        vox(0.016)
        tile()
        import mathutils
        before = L.snapshot()
        glyph()
        pv = mathutils.Vector((0, GY, 0))
        sc = (mathutils.Matrix.Translation(pv) @ mathutils.Matrix.Scale(0.88, 4) @ mathutils.Matrix.Translation(-pv))
        bpy.context.view_layer.update()
        for o in L.new_since(before):
            o.matrix_world = sc @ o.matrix_world
        finish()
        return [], 2.2
    return piece


U.PIECES['tile_hammer'] = (make(glyph_hammer), False, 0.0)
U.PIECES['tile_paw'] = (make(glyph_paw), False, 0.0)
U.PIECES['tile_map'] = (make(glyph_map), False, 0.0)

_cycles = U.cycles


def _vivid(samples):
    _cycles(samples)
    vs = bpy.context.scene.view_settings
    vs.view_transform = 'Standard'
    vs.look = 'None'
    vs.exposure = 0.25


U.cycles = _vivid

if __name__ == '__main__':
    U.main()
