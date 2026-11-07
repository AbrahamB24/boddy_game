"""Shared machinery for the 3D icon set (tool/blender/make_icons.py).

User 2026-11-05: "mache alle Icons in diesem Stil. Versuche bei den Icons das
darzustellen, was am besten passt. Z.B. Timberframe soll auch ein Timberframe
sein". Every game icon becomes a small rendered model — wood, stone, brass, cloth —
photographed head-on by the same camera and light as the interface pieces.

An icon is a function registered with @icon('key'); it builds its parts with the
helpers below (everything upright: X right, Z up, the face towards -Y) and the
runner frames, lights and renders whatever it created.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import camp_kit  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
import make_ui as U  # noqa: E402
from pro_kit import plain  # noqa: E402

TAU = math.tau
REG = {}
ORDER = []


def icon(key):
    def deco(fn):
        REG[key] = fn
        ORDER.append(key)
        return fn
    return deco


# ── palette ─────────────────────────────────────────────────
_P = {}


def mat(name):
    """A material by name, made on first use."""
    if name in _P and _P[name] is not None:
        try:
            _P[name].name
            return _P[name]
        except ReferenceError:
            pass
    specs = {
        'gold': ('#f2b632', 0.28, 1.0, 0.05), 'gold_dk': ('#a87818', 0.4, 1.0, 0.08),
        'steel': ('#aeb4bb', 0.28, 1.0, 0.04), 'iron': ('#4a4e55', 0.42, 1.0, 0.3),
        'iron_dk': ('#25282d', 0.5, 1.0, 0.3), 'copper': ('#c98a4a', 0.38, 0.9, 0.1),
        'silver': ('#d4d8dc', 0.22, 1.0, 0.03), 'brass': ('#d9a441', 0.30, 1.0, 0.06),
        'red': ('#b3261e', 0.5, 0.0, 0.0), 'red_lt': ('#e0483c', 0.45, 0.0, 0.0),
        'green': ('#3f8a3a', 0.55, 0.0, 0.0), 'green_lt': ('#7bc043', 0.5, 0.0, 0.0),
        'green_dk': ('#27561f', 0.6, 0.0, 0.2),
        'blue': ('#3f7fe0', 0.45, 0.0, 0.0), 'blue_dk': ('#24457a', 0.5, 0.0, 0.0),
        'sky': ('#8cc6ee', 0.4, 0.0, 0.0),
        'yellow': ('#f0c93a', 0.5, 0.0, 0.0), 'orange': ('#e8801c', 0.5, 0.0, 0.0),
        'pink': ('#e982b4', 0.5, 0.0, 0.0), 'purple': ('#8a4fb4', 0.5, 0.0, 0.0),
        'white': ('#f4f1ea', 0.55, 0.0, 0.0), 'cream': ('#ecdcb4', 0.7, 0.0, 0.1),
        'black': ('#1c1a18', 0.5, 0.0, 0.0), 'grey': ('#8a8d91', 0.6, 0.0, 0.2),
        'brown': ('#8a5a2b', 0.7, 0.0, 0.3), 'brown_dk': ('#5a3a1a', 0.7, 0.0, 0.3),
        'leather': ('#8a5a32', 0.7, 0.0, 0.5), 'leather_dk': ('#5a3a22', 0.75, 0.0, 0.5),
        'clay': ('#b0653a', 0.9, 0.0, 0.5), 'clay_dk': ('#8a4a28', 0.9, 0.0, 0.5),
        'sand': ('#e2c47a', 0.95, 0.0, 0.5), 'lime': ('#f2eee4', 0.95, 0.0, 0.5),
        'coal': ('#232120', 0.55, 0.0, 0.7), 'salt': ('#f4f6f8', 0.25, 0.0, 0.1),
        'skin': ('#e8b48a', 0.65, 0.0, 0.0), 'fur': ('#c8793a', 0.9, 0.0, 0.4),
        'fur_lt': ('#f0dcc0', 0.9, 0.0, 0.3), 'wool': ('#efe8d8', 0.95, 0.0, 0.5),
        'water': ('#4a9fd8', 0.08, 0.0, 0.05), 'rock': ('#7a766f', 0.85, 0.0, 0.7),
        'rock_lt': ('#aaa69d', 0.8, 0.0, 0.6), 'ice': ('#bfe6f6', 0.12, 0.0, 0.05),
        'cloth': ('#c9322e', 0.9, 0.0, 0.3),
    }
    if name in specs:
        col, rough, metal, bump = specs[name]
        m = plain('ic_' + name, col, rough=rough, metal=metal, bump=bump, bump_scale=70, vary=0.04)
    elif name == 'glass':
        m = _glass('ic_glass', (0.8, 0.93, 1.0))
    elif name == 'glass_amber':
        m = _glass('ic_glass_amber', (1.0, 0.75, 0.35))
    elif name == 'glass_green':
        m = _glass('ic_glass_green', (0.35, 0.7, 0.4))
    elif name.startswith('glow_'):
        c = {'glow_fire': '#ff9a2e', 'glow_blue': '#4fa8ff', 'glow_cyan': '#4fe0ff', 'glow_gold': '#ffd24a',
             'glow_pink': '#ff6ad0', 'glow_green': '#6aff7a', 'glow_white': '#fff4d0', 'glow_red': '#ff4a3a'}[name]
        m = plain('ic_' + name, c, rough=0.3, bump=0, vary=0.0, emit=c, emit_strength=4.0)
    elif name in ('wood', 'planks', 'timber', 'stone', 'stone_dk', 'plaster', 'roof', 'roof2', 'hay', 'teal', 'mustard', 'pane_glow', 'lamp', 'linen', 'cobble'):
        m = camp_kit.mats()[name if name != 'wood' else 'timber']
    elif name == 'parchment':
        m = U.parch_mat('ic_parch', '#ecd9a8', '#c9a468')
    else:
        raise KeyError(name)
    _P[name] = m
    return m


def _glass(key, tint):
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    b = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(b.outputs['BSDF'], out.inputs['Surface'])
    b.inputs['Base Color'].default_value = (*tint, 1)
    b.inputs['Roughness'].default_value = 0.05
    for k in ('Transmission Weight', 'Transmission'):
        if k in b.inputs:
            b.inputs[k].default_value = 0.92
            break
    b.inputs['IOR'].default_value = 1.45
    return m


def reset_materials():
    _P.clear()


# ── primitives ──────────────────────────────────────────────
def _m(m):
    return mat(m) if isinstance(m, str) else m


def box(x, y, z, sx, sy, sz, m, rot=(0, 0, 0), bev=0.03):
    """A box centred on (x, y, z), sizes sx, sy, sz, rotation in DEGREES."""
    return U.block('b', (x, y, z), (sx, sy, sz), _m(m), rot=tuple(math.radians(r) for r in rot), bevel=min(bev, min(sx, sy, sz) * 0.45))


def ball(x, y, z, rx, ry=None, rz=None, m='white', seg=32, rot=(0, 0, 0)):
    ry = rx if ry is None else ry
    rz = rx if rz is None else rz
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(x, y, z), segments=seg, ring_count=seg // 2)
    ob = bpy.context.object
    ob.scale = (rx, ry, rz)
    ob.rotation_euler = tuple(math.radians(r) for r in rot)
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.append(_m(m))
    return ob


def cyl(x, y, z, r, h, m, axis='z', r2=None, seg=40, rot=(0, 0, 0), smooth=True):
    """A cylinder / cone centred on (x, y, z); `axis` is the way it points."""
    r2 = r if r2 is None else r2
    bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=h, location=(x, y, z), vertices=seg)
    ob = bpy.context.object
    base = {'z': (0, 0, 0), 'y': (math.pi / 2, 0, 0), 'x': (0, math.pi / 2, 0)}[axis]
    if rot == (0, 0, 0):
        ob.rotation_euler = base
    else:
        ob.rotation_euler = tuple(a + math.radians(b) for a, b in zip(base, rot))
    for p in ob.data.polygons:
        p.use_smooth = smooth
    ob.data.materials.append(_m(m))
    return ob


def ring(x, y, z, R, r, m, axis='y', rot=(0, 0, 0), seg=56):
    """A torus; axis 'y' = a ring facing the camera."""
    ob = U.torus('ring', R, r, _m(m), loc=(x, y, z), seg=seg)
    base = {'z': (0, 0, 0), 'y': (math.pi / 2, 0, 0), 'x': (0, math.pi / 2, 0)}[axis]
    ob.rotation_euler = tuple(a + math.radians(b) for a, b in zip(base, rot))
    return ob


def lathe(profile, m, x=0, y=0, z=0, steps=56, sub=1, rot=(0, 0, 0)):
    """Revolve a (radius, height) outline about the vertical axis."""
    ob = U.spin('lathe', profile, _m(m), steps=steps, subsurf=sub)
    ob.location = (x, y, z)
    ob.rotation_euler = tuple(math.radians(r) for r in rot)
    return ob


def poly(pts, depth, m, y=0.0, bev=0.025, rot=(0, 0, 0), loc=(0, 0, 0)):
    """An outline given as (x, z) points, extruded `depth` along Y and bevelled."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y - depth / 2, z)) for x, z in pts]
    f = bm.faces.new(vs)
    bmesh.ops.recalc_face_normals(bm, faces=[f])
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [v for v in r['geom'] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, depth, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new('poly')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('poly', me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(_m(m))
    ob.location = loc
    ob.rotation_euler = tuple(math.radians(r) for r in rot)
    if bev:
        b = ob.modifiers.new('bev', 'BEVEL')
        b.width = bev
        b.segments = 3
        b.limit_method = 'ANGLE'
        b.angle_limit = math.radians(35)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


# 2D point helpers
def circ(r, n=48, cx=0.0, cz=0.0, a0=0.0):
    return [(cx + r * math.cos(a0 + i * TAU / n), cz + r * math.sin(a0 + i * TAU / n)) for i in range(n)]


def starp(n, ro, ri, cx=0.0, cz=0.0, a0=math.pi / 2):
    return [(cx + (ro if i % 2 == 0 else ri) * math.cos(a0 + i * math.pi / n),
             cz + (ro if i % 2 == 0 else ri) * math.sin(a0 + i * math.pi / n)) for i in range(2 * n)]


def heartp(s=1.0, cx=0.0, cz=0.0, n=60):
    pts = []
    for i in range(n):
        t = i * TAU / n
        x = 16 * math.sin(t) ** 3
        z = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * s / 17.0, cz + z * s / 17.0))
    return pts


def dropp(s=1.0, cx=0.0, cz=0.0, n=36):
    """A teardrop: a round belly with a point on top."""
    pts = []
    for i in range(n + 1):
        a = math.radians(145 + i * 250.0 / n)
        pts.append((cx + s * 0.58 * math.cos(a), cz - 0.28 * s + s * 0.58 * math.sin(a)))
    pts.append((cx, cz + 0.95 * s))
    return pts


def mirror_pts(pts):
    return [(-x, z) for x, z in reversed(pts)]


def rotp(pts, deg, cx=0.0, cz=0.0):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (z - cz) * s, cz + (x - cx) * s + (z - cz) * c) for x, z in pts]


# ── runner ──────────────────────────────────────────────────
def snapshot():
    return set(bpy.data.objects)


def new_since(before):
    return [o for o in bpy.data.objects if o not in before and o.type == 'MESH']


def fit_camera(objs, pitch=12.0, margin=1.14):
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    bpy.ops.object.camera_add()
    cam = bpy.context.object
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(90 - pitch), 0, 0)
    sc.camera = cam
    cam.data.clip_end = 500
    q = Euler(cam.rotation_euler).to_quaternion()
    right, up, back = q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0)), q @ Vector((0, 0, 1))
    xs, zs = [], []
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            xs.append(p.dot(right))
            zs.append(p.dot(up))
    cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
    size = max(max(xs) - min(xs), max(zs) - min(zs)) * margin
    cam.data.ortho_scale = size
    cam.location = right * cx + up * cz + back * 30
    return size


VOXELS = {'n': 0}   # >0: voxelise every icon, this many blocks across its longest side


def render_icon(key, out_png, samples=48, px=320, pitch=12.0):
    rb.clear()
    K._mats.clear()
    reset_materials()
    before = snapshot()
    REG[key]()
    objs = new_since(before)
    if not objs:
        raise RuntimeError('icon %s built nothing' % key)
    if VOXELS['n']:
        # The buildings' own union voxeliser (user 2026-11-05: icons in the new look).
        import voxelizer
        bpy.context.view_layer.update()
        lo = [1e9] * 3
        hi = [-1e9] * 3
        for o in objs:
            for c in o.bound_box:
                p = o.matrix_world @ Vector(c)
                for i in range(3):
                    lo[i], hi[i] = min(lo[i], p[i]), max(hi[i], p[i])
        v = max(hi[i] - lo[i] for i in range(3)) / VOXELS['n']
        objs = [voxelizer.voxelize(v, 'icon_voxel', objs=objs)]
    K.lighting(azimuth=0, elev=52, swing=-28)
    fit_camera(objs, pitch)
    sc = bpy.context.scene
    sc.render.resolution_x = sc.render.resolution_y = px
    U.cycles(samples)
    K.render(out_png)


def strip_poly(pts, w):
    """A thick polyline as one outline: its left and right edges, joined."""
    left, right = [], []
    n = len(pts)
    for i, (x, z) in enumerate(pts):
        x0, z0 = pts[max(i - 1, 0)]
        x1, z1 = pts[min(i + 1, n - 1)]
        dx, dz = x1 - x0, z1 - z0
        d = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / d, dx / d
        left.append((x + nx * w / 2, z + nz * w / 2))
        right.append((x - nx * w / 2, z - nz * w / 2))
    return left + right[::-1]


def rotate_since(before, deg, pivot=(0, 0, 0)):
    """Turn everything made since `before` about Y (the view axis' sideways swing)."""
    objs = new_since(before)
    e = bpy.data.objects.new('pivot', None)
    bpy.context.scene.collection.objects.link(e)
    e.location = pivot
    bpy.context.view_layer.update()
    for o in objs:
        if o.parent is None:
            o.parent = e
            o.matrix_parent_inverse = e.matrix_world.inverted()
    e.rotation_euler = (0, math.radians(deg), 0)
    bpy.context.view_layer.update()
    return objs
