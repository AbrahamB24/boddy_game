"""Detect the stones (glossy bumps) in the user's orthographic sheet and place a real ellipsoid for each on the fitted gorilla.

    blender --background --python tool/blender/gorilla_stones.py -- <sheet.png> <out dir> <stage 0..2>

For every view (front, back, side, top): bright blobs inside the silhouette that are separated by dark seams are candidates
(area / shape filter keeps stone-sized, roundish ones; face, chest and feet are too big or too low). Each blob is projected onto the
stone-free voxel model with a ray along the view axis; the hit point is the stone's surface point, the blob size gives its radii.
Result: tool/blender/gorilla_stones_s<stage>.json = list of [x, y, z, rx, ry, rz] (world units, +y side; mirrored in gorilla.py).
"""
import json
import os
import sys
from collections import deque

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gorilla as G  # noqa: E402
import gorilla_ortho_masks as om  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

args = sys.argv[sys.argv.index('--') + 1:]
sheet, out, stage = args[0], args[1], int(args[2])
os.makedirs(out, exist_ok=True)

px = om.load(sheet)
REF = {}
for name, (x0, y0, x1, y1) in zip(om.NAMES, om.PANELS[stage]):
    reg = px[y0:y1, x0:x1]
    m, bg = om.mask_of(reg, 24.0 if np.median(reg) > 60 else 11.0)
    ys, xs = np.where(m)
    REF[name] = (reg[ys.min():ys.max() + 1, xs.min():xs.max() + 1], m[ys.min():ys.max() + 1, xs.min():xs.max() + 1])

# stone-free model
G.NOBULB = True
bpy.ops.wm.read_factory_settings(use_empty=True)
tw.SMOOTH_MATS = True
tw.DEPTH = 8
b = G.new_builder(stage)
G.STAGES[stage](b)
ob = tw.voxelise(b.objs)
me = ob.data
n = len(me.vertices)
co = np.empty(n * 3, np.float32)
me.vertices.foreach_get('co', co)
co = co.reshape(n, 3)
x0, y0, z0 = co.min(axis=0)
x1, y1, z1 = co.max(axis=0)
xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
s = (z1 - z0) / REF['front'][1].shape[0]
bm = bmesh.new()
bm.from_mesh(me)
bvh = BVHTree.FromBMesh(bm)
bm.free()
print('model bbox', round(x0, 2), round(x1, 2), round(y0, 2), round(y1, 2), round(z0, 2), round(z1, 2), 'scale', round(s, 5))

V_THR = .36                       # luminance of a stone surface; fur is ~.25
A_MIN, A_MAX = 40, 2600           # blob area in reference pixels
FILL_MIN = .55


def blobs(rgb, m):
    v = rgb.max(axis=2) / 255.0
    bright = (v > V_THR) & m
    er = bright.copy()                                           # erode 1px to cut thin bridges between stones
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        er &= np.roll(np.roll(bright, dy, 0), dx, 1)
    h, w = er.shape
    seen = np.zeros_like(er)
    res = []
    for y in range(h):
        for x in range(w):
            if er[y, x] and not seen[y, x]:
                comp = []
                dq = deque([(y, x)])
                seen[y, x] = True
                while dq:
                    cy, cx = dq.popleft()
                    comp.append((cy, cx))
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and er[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            dq.append((ny, nx))
                a = np.array(comp)
                u0, u1 = a[:, 1].min(), a[:, 1].max() + 1
                v0, v1 = a[:, 0].min(), a[:, 0].max() + 1
                area = len(comp) + 2 * (u1 - u0 + v1 - v0)         # add back the eroded rim
                bw, bh = u1 - u0 + 2, v1 - v0 + 2
                if A_MIN <= area <= A_MAX and area / (bw * bh) >= FILL_MIN and .35 < bw / bh < 2.8:
                    res.append(((u0 + u1) / 2.0, (v0 + v1) / 2.0, bw / 2.0, bh / 2.0))
    return res


stones = []
for view, rgbm in REF.items():
    rgb, m = rgbm
    h, w = m.shape
    for (cu, cv, ru, rv) in blobs(rgb, m):
        if view in ('front', 'back'):
            wy = yc + ((cu - w / 2) if view == 'front' else -(cu - w / 2)) * s
            wz = z0 + (h - cv) * s
            if wz < z0 + .10:                                    # feet
                continue
            org, dr = (Vector((6, wy, wz)), Vector((-1, 0, 0))) if view == 'front' else (Vector((-6, wy, wz)), Vector((1, 0, 0)))
            radii = (None, ru * s, rv * s)                        # (depth, y, z)
        elif view == 'side':
            wx = xc + (cu - w / 2) * s
            wz = z0 + (h - cv) * s
            if wz < z0 + .10:
                continue
            org, dr = Vector((wx, -6, wz)), Vector((0, 1, 0))
            radii = (ru * s, None, rv * s)
        else:
            wy = yc + (cu - w / 2) * s
            wx = xc + (cv - h / 2) * s
            org, dr = Vector((wx, wy, 6)), Vector((0, 0, -1))
            radii = (rv * s, ru * s, None)
        hit = bvh.ray_cast(org, dr, 12.0)
        if hit[0] is None:
            continue
        p = hit[0]
        inpl = [r for r in radii if r is not None]
        depth_r = .75 * min(inpl)
        rr = [depth_r if r is None else r for r in radii]
        # centre pushed inwards so only ~0.45 of the depth radius protrudes
        p = p + dr * (.55 * depth_r)
        if view == 'side':
            stones.append([p.x, p.y, p.z, rr[0], rr[1], rr[2]])           # -y side as seen; the mirror is added below
        else:
            stones.append([p.x, p.y, p.z, rr[0], rr[1], rr[2]])
    print(view, 'stones so far', len(stones))

# fold everything onto +y (the model is symmetric), then merge duplicates seen from several views
folded = [[x, abs(y), z, rx, ry, rz] for x, y, z, rx, ry, rz in stones]
merged = []
for st in sorted(folded, key=lambda t: -(t[3] * t[4] * t[5])):
    for mg in merged:
        d = np.hypot(np.hypot(st[0] - mg[0], st[1] - mg[1]), st[2] - mg[2])
        if d < .6 * (max(st[3:]) + max(mg[3:])) * .75:
            break
    else:
        merged.append(st)
print('stones after merge', len(merged))
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gorilla_stones_s%d.json' % stage)
json.dump([[round(float(v), 4) for v in st] for st in merged], open(dst, 'w'))
print('wrote', dst)
