"""Tab tiles, smooth (NOT voxel) — a straight copy of the reference image
(user 2026-11-07: "den Stil 1:1 kopieren, egal welche Regeln ich vorher
gegeben habe"): dark slate tile, rounded chamfered corners, glossy gold rim,
smooth bevelled glyphs. Hammer / paw (instead of the people) / map with red X.

    blender --background --python tool/blender/make_ui10.py -- \
        tab_hammer tab_paw tab_map [--samples N --px N]
"""
import math
import os
import sys

import bmesh
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_ui as U  # noqa: E402
import icon_lib as L  # noqa: E402
from pro_kit import plain  # noqa: E402
from icon_lib import poly  # noqa: E402

_C = {}


def cm(name, col, rough=0.4, metal=0.0, bump=0.0):
    key = 't10_' + name
    m = _C.get(key)
    try:
        if m is not None:
            m.name
            return m
    except ReferenceError:
        pass
    m = plain(key, col, rough=rough, metal=metal, bump=bump, bump_scale=70, vary=0.0)
    _C[key] = m
    return m


def finish_obj(ob, mat, bevel, seg=5):
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    if bevel:
        b = ob.modifiers.new('bev', 'BEVEL')
        b.width = bevel
        b.segments = seg
        b.limit_method = 'ANGLE'
        b.angle_limit = math.radians(30)
    ob.modifiers.new('wn', 'WEIGHTED_NORMAL').keep_sharp = True
    return ob


def rounded(pts, r, steps=5):
    """Round every corner of a closed outline with radius r."""
    out = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2 = mathutils.Vector(pts[i - 1]), mathutils.Vector(pts[i]), mathutils.Vector(pts[(i + 1) % n])
        a = (p0 - p1)
        b = (p2 - p1)
        k = min(r, a.length * 0.45, b.length * 0.45)
        a = a.normalized() * k
        b = b.normalized() * k
        s, e = p1 + a, p1 + b
        for t in range(steps + 1):
            u = t / steps
            q = (1 - u) ** 2 * s + 2 * u * (1 - u) * p1 + u * u * e
            out.append((q.x, q.y))
    return out


def octo(h, c, steps=2):
    """A square whose corners are cut as a pixel staircase (reference tiles)."""
    if steps == 0:
        return [(h - c, h), (h, h - c), (h, -(h - c)), (h - c, -h), (-(h - c), -h), (-h, -(h - c)), (-h, h - c), (-(h - c), h)]
    k = c / steps
    tr = [(h - c, h)]
    for i in range(steps):
        tr.append((h - c + i * k, h - (i + 1) * k + 0.0))
        tr.append((h - c + (i + 1) * k, h - (i + 1) * k))
    tr = [(h - c, h)]
    for i in range(steps):
        tr.append((h - c, h - i * k - k)) if False else None
    # explicit staircase from the top edge down to the right edge
    tr = [(h - c, h)]
    x, z = h - c, h
    for i in range(steps):
        z -= k
        tr.append((x, z))
        x += k
        tr.append((x, z))
    pts = []
    for j in range(4):
        for (px, pz) in tr:
            for _ in range(j):
                px, pz = pz, -px
            pts.append((px, pz))
    return pts


def slab(outer, front, depth, mat, bevel=0.03, inner=None):
    """An outline (optionally with a hole) extruded back from y=front."""
    bm = bmesh.new()
    if inner is None:
        f = bm.faces.new([bm.verts.new((x, front, z)) for x, z in outer])
        geom = [f]
    else:
        vo = [bm.verts.new((x, front, z)) for x, z in outer]
        vi = [bm.verts.new((x, front, z)) for x, z in inner]
        n = len(outer)
        geom = [bm.faces.new((vo[i], vo[(i + 1) % n], vi[(i + 1) % n], vi[i])) for i in range(n)]
    r = bmesh.ops.extrude_face_region(bm, geom=geom)
    nv = [v for v in r['geom'] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, depth, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new('slab')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('slab', me)
    bpy.context.scene.collection.objects.link(ob)
    return finish_obj(ob, mat, bevel)


def ring_pts(h, c, r=0.14):
    return rounded(octo(h, c, 0), r, 8)


def tile():
    # exactly two bodies: one gold plate and one slate cap standing on it,
    # each made plastic by a generous bevel plus light and shadow only
    slab(ring_pts(1.0, 0.26, 0.2), -0.02, 0.30, cm('gold', '#eb9a1e', 0.26), 0.10)
    slab(ring_pts(0.82, 0.20, 0.16), -0.20, 0.30, cm('slate', '#1e3355', 0.5), 0.07)


GY = -0.30


def sph(x, z, rx, rz, ry, mat, rot=0, y=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(x, GY if y is None else y, z), segments=40, ring_count=20)
    ob = bpy.context.object
    ob.scale = (rx, ry, rz)
    ob.rotation_euler = (0, math.radians(rot), 0)
    return finish_obj(ob, mat, 0)


def rbox(x, z, sx, sz, sy, mat, rot=0, bevel=0.03, y=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, GY if y is None else y, z))
    ob = bpy.context.object
    ob.scale = (sx, sy, sz)
    ob.rotation_euler = (0, math.radians(rot), 0)
    bpy.ops.object.transform_apply(scale=True)
    return finish_obj(ob, mat, bevel)


def cylx(x, z, r, depth, mat, y=None, axis='z'):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=(x, GY if y is None else y, z), vertices=32)
    ob = bpy.context.object
    if axis == 'x':
        ob.rotation_euler = (0, math.radians(90), 0)
    return finish_obj(ob, mat, 0.01, 2)


def blob(cx, cz, rx, rz, seed, front, depth, mat, n=14, wob=0.2, bevel=0.01):
    pts = []
    for i in range(n):
        a = i * math.tau / n
        k = 1 + wob * math.sin(3 * a + seed) * math.cos(2 * a + seed * 1.7)
        pts.append((cx + rx * k * math.cos(a), cz + rz * k * math.sin(a)))
    return slab(rounded(pts, 0.05, 2), front, depth, mat, bevel)


def glyph_hammer():
    wood = cm('wood', '#c25a1c', 0.45)
    woodd = cm('woodd', '#8e3d10', 0.5)
    grey = cm('grey', '#9a9c9f', 0.32, 0.25)
    greyl = cm('greyl', '#d4d6d8', 0.25, 0.2)
    greyd = cm('greyd', '#4b4d52', 0.4, 0.3)
    gold = cm('hgold', '#f0a01c', 0.28)
    goldd = cm('hgoldd', '#b06c0c', 0.35)
    before = L.snapshot()
    bpy.ops.mesh.primitive_cylinder_add(radius=0.085, depth=1.5, location=(0, GY, -0.20), vertices=32)
    finish_obj(bpy.context.object, wood, 0)
    for z in (-0.82, -0.68, -0.54, -0.40, -0.26):           # leather-wrap grooves
        cylx(0, z, 0.092, 0.035, woodd)
    rbox(0, 0.52, 0.92, 0.40, 0.40, grey, bevel=0.06)
    rbox(0, 0.62, 0.84, 0.07, 0.06, greyl, bevel=0.02, y=GY - 0.19)   # top glint
    rbox(0, 0.40, 0.84, 0.03, 0.04, greyd, bevel=0.01, y=GY - 0.20)   # lower shade line
    for sx in (-1, 1):
        rbox(0.50 * sx, 0.52, 0.16, 0.46, 0.44, greyd, bevel=0.05)
        rbox(0.50 * sx, 0.64, 0.12, 0.06, 0.05, grey, bevel=0.015, y=GY - 0.22)
    rbox(0, 0.52, 0.17, 0.44, 0.46, gold, bevel=0.04)
    for z in (0.34, 0.70):                                   # band rivets
        sph(0, z, 0.035, 0.035, 0.03, goldd, y=GY - 0.235)
    rbox(0, 0.52, 0.015, 0.44, 0.04, goldd, bevel=0.005, y=GY - 0.235)
    rbox(0, -0.96, 0.20, 0.14, 0.20, gold, bevel=0.04)       # pommel cap
    rbox(0, -0.92, 0.22, 0.02, 0.22, goldd, bevel=0.005)
    turn(L.new_since(before), 40)


def glyph_paw():
    gold = cm('pgold', '#f2a31c', 0.3)
    goldl = cm('pgoldl', '#ffd45a', 0.2)
    goldd = cm('pgoldd', '#c0780c', 0.4)
    claw = cm('claw', '#fff0c0', 0.3)
    parts = [(0, -0.18, 0.46, 0.38, 0), (-0.58, 0.20, 0.16, 0.23, 28), (-0.22, 0.58, 0.16, 0.25, 10),
             (0.22, 0.58, 0.16, 0.25, -10), (0.58, 0.20, 0.16, 0.23, -28)]
    for x, z, rx, rz, a in parts:
        sph(x, z, rx * 1.07, rz * 1.07, 0.15, goldd, rot=a, y=GY + 0.03)        # darker under-rim
        sph(x, z, rx, rz, 0.16 if x == 0 and z < 0 else 0.14, gold, rot=a)
        sph(x - rx * 0.25, z + rz * 0.30, rx * 0.5, rz * 0.4, 0.05, goldl, rot=a, y=GY - 0.12)  # gloss
    # cream claw tips over the four toes
    for x, z, a in ((-0.66, 0.46, 28), (-0.26, 0.86, 10), (0.26, 0.86, -10), (0.66, 0.46, -28)):
        sph(x, z, 0.05, 0.065, 0.05, claw, rot=a, y=GY - 0.02)


def glyph_map():
    paper = cm('paper', '#efd9a6', 0.75)
    paper2 = cm('paper2', '#e2c68a', 0.75)
    edge = cm('pedge', '#a9763a', 0.7)
    red = cm('red', '#d92a1c', 0.45)
    ink = cm('ink', '#7a4c22', 0.7)
    sea = cm('sea', '#58a9c4', 0.6)
    land = cm('land', '#78a850', 0.7)
    mtn = cm('mtn', '#9a7448', 0.7)
    before = L.snapshot()
    ragged = []
    n = 30
    for i in range(n):                                       # torn rectangle
        t = i / n * 4
        side, u = int(t), t - int(t)
        w, h = 0.78, 0.60
        base = [(-w + 2 * w * u, h), (w, h - 2 * h * u), (w - 2 * w * u, -h), (-w, -h + 2 * h * u)][side]
        j = 0.035 * math.sin(i * 2.3) + 0.02 * math.cos(i * 4.1)
        ragged.append((base[0] + j * (1 if base[0] > 0 else -1), base[1] + j * (1 if base[1] > 0 else -1)))
    slab(rounded(ragged, 0.03, 2), -0.31, 0.06, edge, 0.012)
    pp = [(x * 0.95, z * 0.94) for x, z in ragged]
    slab(rounded(pp, 0.03, 2), -0.345, 0.06, paper, 0.012)
    blob(-0.50, 0.28, 0.24, 0.20, 1.0, -0.37, 0.04, sea)
    blob(-0.38, -0.28, 0.26, 0.18, 3.0, -0.37, 0.04, land)
    blob(0.0, -0.05, 0.22, 0.28, 5.0, -0.37, 0.04, land)
    for x, z in ((-0.12, 0.28), (0.02, 0.36), (-0.04, 0.2)):  # little mountains
        poly([(x - 0.07, z - 0.05), (x, z + 0.07), (x + 0.07, z - 0.05)], 0.03, mtn, y=GY - 0.075, bev=0.005)
    for x, z in ((-0.52, 0.02), (-0.36, 0.0), (-0.18, 0.12), (0.0, 0.24), (0.2, 0.28)):   # dotted trail
        sph(x, z, 0.04, 0.04, 0.02, ink, y=GY - 0.09)
    for a in (45, -45):
        rbox(0.42, 0.26, 0.36, 0.1, 0.04, red, rot=a, bevel=0.025, y=GY - 0.095 - (0.012 if a < 0 else 0))
    cx, cz = 0.42, -0.30                                     # compass rose
    cylx(cx, cz, 0.10, 0.02, ink, y=GY - 0.085).rotation_euler = (math.radians(90), 0, 0)
    for rot in (0, 90):
        rbox(cx, cz, 0.05, 0.26, 0.02, edge, rot=rot, bevel=0.005, y=GY - 0.10)
    rbox(0.0, 0.58, 1.5, 0.07, 0.06, edge, bevel=0.02, y=GY - 0.04)    # rolled ends
    rbox(0.0, -0.58, 1.5, 0.07, 0.06, edge, bevel=0.02, y=GY - 0.04)
    turn(L.new_since(before), 7)


def turn(objs, deg):
    bpy.context.view_layer.update()
    r = mathutils.Matrix.Translation((0, GY, 0)) @ mathutils.Matrix.Rotation(math.radians(deg), 4, 'Y') \
        @ mathutils.Matrix.Translation((0, -GY, 0))
    for o in objs:
        o.matrix_world = r @ o.matrix_world
    bpy.context.view_layer.update()


def make(glyph):
    def piece(M):
        _C.clear()
        L.reset_materials()
        tile()
        before = L.snapshot()
        glyph()
        pv = mathutils.Vector((0, GY, 0))
        sc = mathutils.Matrix.Translation(pv) @ mathutils.Matrix.Scale(0.9, 4) @ mathutils.Matrix.Translation(-pv)
        bpy.context.view_layer.update()
        for o in L.new_since(before):
            o.matrix_world = sc @ o.matrix_world
        return [], 2.2
    return piece


for _n, _g in (('tab_hammer', glyph_hammer), ('tab_paw', glyph_paw), ('tab_map', glyph_map)):
    U.PIECES[_n] = (make(_g), False, 0.0)

_cycles = U.cycles


def _vivid(samples):
    _cycles(samples)
    vs = bpy.context.scene.view_settings
    vs.view_transform = 'Standard'
    vs.look = 'None'
    vs.exposure = 0.0


U.cycles = _vivid

if __name__ == '__main__':
    U.main()
