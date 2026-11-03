"""Union voxeliser: every mesh object rasterised on ONE world-aligned grid.

Replaces Blender's Remesh (BLOCKS) for the Fachwerk buildings. Remesh scan-
converts the whole joined scene by ray PARITY, so wherever two closed parts
overlap — a door leaf set into a wall, a beam bedded in plaster — the overlap
counts as "outside" and comes out as a hollow pocket just under the surface
(dark blotches around every door, 2026-11-03). Here each object is tested on
its own and the results are OR-ed, so an overlap is simply solid.

Per object, rays are cast along all three axes through the centres of the
grid cells its bounding box covers; a cell whose centre lies inside the
object (between an entry and an exit) is filled. An object thinner than one
cell along some axis — a sheet of washing, a line, a thin plank — would slip
between cell centres, so there the ray goes through the object's own middle
and the one cell it lies in is filled: everything thin still gets one block.

Each visible block face then takes the material of the nearest original
surface, as the Remesh path did.
"""
import math

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def _cells(lo, hi, V):
    """Cell indices whose CENTRE lies in [lo, hi]; or, when none does, the one
    cell holding the middle (and the coordinate to shoot the ray through)."""
    a = math.ceil(lo / V - 0.5)
    b = math.floor(hi / V - 0.5)
    if b >= a:
        return [(i, (i + 0.5) * V) for i in range(a, b + 1)]
    mid = (lo + hi) / 2
    return [(math.floor(mid / V), mid)]


def _spans(bvh, origin, axis, far):
    """All entry/exit coordinates along +axis from origin."""
    d = Vector((0, 0, 0))
    d[axis] = 1.0
    o = Vector(origin)
    ts = []
    left = far
    while left > 0:
        loc, _n, _i, dist = bvh.ray_cast(o, d, left)
        if loc is None:
            break
        ts.append(loc[axis])
        o = loc + d * 1e-6
        left -= dist + 1e-6
    if len(ts) % 2:
        ts.pop()
    return [(ts[i], ts[i + 1]) for i in range(0, len(ts), 2)]


def voxelize(V, name='voxels', skip=('blade',)):
    for o in [o for o in bpy.data.objects
              if o.type == 'MESH' and o.name.startswith(skip)]:
        bpy.data.objects.remove(o)
    objs = [o for o in bpy.data.objects if o.type == 'MESH']
    # matrix_world is evaluated lazily: without this every part placed by
    # location/rotation (beams, roof slabs) is read at the origin, unturned.
    bpy.context.view_layer.update()

    mats, mat_slot = [], {}
    g_verts, g_polys, g_pmat = [], [], []
    parts = []
    for o in objs:
        for md in list(o.modifiers):
            o.modifiers.remove(md)
        me = o.data
        if not me.polygons:
            continue
        mw = o.matrix_world
        vs = [mw @ v.co for v in me.vertices]
        polys = [tuple(p.vertices) for p in me.polygons]
        bvh = BVHTree.FromPolygons(vs, polys, all_triangles=False)
        arr = np.array([tuple(v) for v in vs])
        parts.append((bvh, arr.min(axis=0), arr.max(axis=0)))
        base = len(g_verts)
        g_verts.extend(vs)
        g_polys.extend(tuple(base + i for i in p) for p in polys)
        for p in me.polygons:
            mt = me.materials[p.material_index] if len(me.materials) else None
            key = mt.name if mt else '_none'
            if key not in mat_slot:
                mat_slot[key] = len(mats)
                mats.append(mt)
            g_pmat.append(mat_slot[key])

    lo = np.min([p[1] for p in parts], axis=0)
    hi = np.max([p[2] for p in parts], axis=0)
    i0 = np.floor(lo / V).astype(int) - 2
    i1 = np.ceil(hi / V).astype(int) + 2
    shape = tuple(int(x) for x in (i1 - i0))
    occ = np.zeros(shape, dtype=bool)
    print('VOXEL grid', shape, 'block', round(V, 5), 'parts', len(parts))

    for bvh, plo, phi in parts:
        for ax in range(3):
            b, c = [k for k in range(3) if k != ax]
            far = float(phi[ax] - plo[ax]) + 0.01
            for jb, yb in _cells(plo[b], phi[b], V):
                for jc, yc in _cells(plo[c], phi[c], V):
                    org = [0.0, 0.0, 0.0]
                    org[ax] = float(plo[ax]) - 0.005
                    org[b], org[c] = yb, yc
                    for s, e in _spans(bvh, org, ax, far):
                        ia = math.ceil(s / V - 0.5)
                        ie = math.floor(e / V - 0.5)
                        if ie < ia:
                            ia = ie = math.floor((s + e) / 2 / V)
                        idx = [0, 0, 0]
                        idx[b] = jb - i0[b]
                        idx[c] = jc - i0[c]
                        sl = [None, None, None]
                        sl[ax] = slice(ia - i0[ax], ie - i0[ax] + 1)
                        sl[b] = idx[b]
                        sl[c] = idx[c]
                        occ[tuple(sl)] = True

    # ── the block faces: a filled cell next to an empty one ──
    quads = []
    normals = []
    for ax in range(3):
        for sgn in (1, -1):
            nb = np.roll(occ, -sgn, axis=ax)
            mask = occ & ~nb
            idx = np.argwhere(mask)
            if not len(idx):
                continue
            ijk = idx + i0
            b, c = [k for k in range(3) if k != ax]
            if ax == 1:            # keep (b, c) right-handed with ax
                b, c = c, b
            base = ijk.astype(float) * V
            plane = base[:, ax] + (V if sgn > 0 else 0.0)
            corners = []
            for db, dc in ((0, 0), (1, 0), (1, 1), (0, 1)):
                p = base.copy()
                p[:, ax] = plane
                p[:, b] += db * V
                p[:, c] += dc * V
                corners.append(p)
            q = np.stack(corners, axis=1)          # (n, 4, 3)
            if sgn < 0:
                q = q[:, ::-1, :]
            quads.append(q)
            n = np.zeros((len(idx), 3))
            n[:, ax] = sgn
            normals.append(n)
    quads = np.concatenate(quads)
    normals = np.concatenate(normals)
    nf = len(quads)

    me = bpy.data.meshes.new(name)
    me.vertices.add(nf * 4)
    me.vertices.foreach_set('co', quads.reshape(-1).astype(np.float32))
    me.loops.add(nf * 4)
    me.loops.foreach_set('vertex_index', np.arange(nf * 4, dtype=np.int32))
    me.polygons.add(nf)
    me.polygons.foreach_set('loop_start', np.arange(0, nf * 4, 4, dtype=np.int32))
    me.update(calc_edges=True)

    # ── materials: nearest original surface, probed just inside the block ──
    big = BVHTree.FromPolygons(g_verts, g_polys, all_triangles=False)
    centers = quads.mean(axis=1) - normals * (0.25 * V)
    mi = np.zeros(nf, dtype=np.int32)
    for k in range(nf):
        hit = big.find_nearest(Vector(centers[k]))
        if hit[2] is not None:
            mi[k] = g_pmat[hit[2]]
    for mt in mats:
        me.materials.append(mt)
    me.polygons.foreach_set('material_index', mi)
    me.polygons.foreach_set('use_smooth', np.zeros(nf, dtype=bool))

    for o in objs:
        bpy.data.objects.remove(o)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    print('voxel faces', nf)
    return ob
