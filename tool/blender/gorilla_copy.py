"""1:1 copy of one gorilla stage from the user's orthographic sheet (front / back / side / top).

    blender --background --python tool/blender/gorilla_copy.py -- <sheet.png> <out dir> <stage 0..2> [views] [samples] [size] [inflate]

1. the fitted primitive model of gorilla.py, slightly inflated, is voxelised (eyes kept apart)
2. its voxel occupancy is CUT with the visual hull of the four sheet silhouettes -> every view's outline matches the sheet
3. every visible voxel face is painted from the sheet view that sees it (gorilla_paint.paint)
4. the phoenix-recipe eyes are moved onto the face surface at the sheet's eye position and voxelised on the same grid
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gorilla as G  # noqa: E402
import gorilla_paint as P  # noqa: E402  (parses the same argv: sheet, out, stage, views, samples, size)
import phoenix3 as p3  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

args = sys.argv[sys.argv.index('--') + 1:]
sheet, out, stage = args[0], args[1], int(args[2])
views = (args[3] if len(args) > 3 else 'front,q,side,back').split(',')
samples = int(args[4]) if len(args) > 4 else 32
size = int(args[5]) if len(args) > 5 else 560
G.INFLATE = float(args[6]) if len(args) > 6 else 1.10
os.makedirs(out, exist_ok=True)
REF = P.REF


def occupancy(ob):
    """Voxel occupancy grid of a REMESH-blocks mesh: fill every (x, y) column between its bottom and top faces."""
    me = ob.data
    n = len(me.vertices)
    co = np.empty(n * 3, np.float32)
    me.vertices.foreach_get('co', co)
    co = co.reshape(n, 3)
    e = np.array([(me.vertices[ed.vertices[0]].co - me.vertices[ed.vertices[1]].co).length for ed in me.edges[:2000]])
    cs = float(np.median(e))
    o = co.min(axis=0)
    dims = np.round((co.max(axis=0) - o) / cs).astype(int)
    occ = np.zeros(dims, bool)
    events = {}
    for pl in me.polygons:
        nz = pl.normal.z
        if abs(nz) < .9:
            continue
        c = pl.center
        ix, iy = int((c.x - o[0]) / cs), int((c.y - o[1]) / cs)
        k = int(round((c.z - o[2]) / cs))
        events.setdefault((ix, iy), []).append((k, 1 if nz < 0 else -1))      # bottom face opens, top face closes
    for (ix, iy), ev in events.items():
        ev.sort()
        depth, start = 0, 0
        for k, t in ev:
            if t == 1:
                if depth == 0:
                    start = k
                depth += 1
            else:
                depth -= 1
                if depth == 0 and 0 <= ix < dims[0] and 0 <= iy < dims[1]:
                    occ[ix, iy, start:k] = True
    return occ, o, cs


def hull_cut(occ, o, cs):
    """Keep only cells that lie inside the sheet silhouette in all four views."""
    nx, ny, nz = occ.shape
    xs = o[0] + (np.arange(nx) + .5) * cs
    ys = o[1] + (np.arange(ny) + .5) * cs
    zs = o[2] + (np.arange(nz) + .5) * cs
    idx = np.argwhere(occ)
    z0, z1 = zs[idx[:, 2].min()] - cs / 2, zs[idx[:, 2].max()] + cs / 2
    x0, x1 = xs[idx[:, 0].min()] - cs / 2, xs[idx[:, 0].max()] + cs / 2
    y0, y1 = ys[idx[:, 1].min()] - cs / 2, ys[idx[:, 1].max()] + cs / 2
    xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
    s = (z1 - z0) / REF['front'][1].shape[0]

    def look(m, u, v):
        h, w = m.shape
        ui, vi = np.floor(u).astype(int), np.floor(v).astype(int)
        ok = (ui >= 0) & (ui < w) & (vi >= 0) & (vi < h)
        r = np.zeros(u.shape, bool)
        r[ok] = m[vi[ok], ui[ok]]
        return r
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing='ij')
    keep = occ.copy()
    m = REF['front'][1]; m = m | m[:, ::-1]                 # the model is symmetric: use the union of both halves of the silhouette
    keep &= look(m, m.shape[1] / 2 + (Y - yc) / s, m.shape[0] - (Z - z0) / s)
    m = REF['back'][1]; m = m | m[:, ::-1]
    keep &= look(m, m.shape[1] / 2 - (Y - yc) / s, m.shape[0] - (Z - z0) / s)
    m = REF['side'][1]
    keep &= look(m, m.shape[1] / 2 + (X - xc) / s, m.shape[0] - (Z - z0) / s)
    m = REF['top'][1]
    keep &= look(m, m.shape[1] / 2 + (Y - yc) / s, m.shape[0] / 2 + (X - xc) / s)
    print('cells', int(occ.sum()), '-> kept', int(keep.sum()))
    return keep, (s, z0, xc, yc)



def drop_thin(occ, n=2):
    """Remove one-voxel-thick walls/needles left by the hull cut: a cell survives only if it has a neighbour on at least one side
    in every axis (thickness >= 2 along x, y and z); repeated n times."""
    for _ in range(n):
        o = occ
        px = np.zeros_like(o); px[1:] = o[:-1]
        nx = np.zeros_like(o); nx[:-1] = o[1:]
        py = np.zeros_like(o); py[:, 1:] = o[:, :-1]
        ny = np.zeros_like(o); ny[:, :-1] = o[:, 1:]
        pz = np.zeros_like(o); pz[:, :, 1:] = o[:, :, :-1]
        nz_ = np.zeros_like(o); nz_[:, :, :-1] = o[:, :, 1:]
        occ = o & (px | nx) & (py | ny) & (pz | nz_)
    return occ

def mesh_from(occ, o, cs, mat):
    verts, faces = [], []
    nx, ny, nz = occ.shape
    pad = np.zeros((nx + 2, ny + 2, nz + 2), bool)
    pad[1:-1, 1:-1, 1:-1] = occ
    QUADS = {(1, 0, 0): [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)], (-1, 0, 0): [(0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1)],
             (0, 1, 0): [(1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)], (0, -1, 0): [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
             (0, 0, 1): [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)], (0, 0, -1): [(0, 1, 0), (1, 1, 0), (1, 0, 0), (0, 0, 0)]}
    for d, q in QUADS.items():
        nb = pad[1 + d[0]:nx + 1 + d[0], 1 + d[1]:ny + 1 + d[1], 1 + d[2]:nz + 1 + d[2]]
        cells = np.argwhere(occ & ~nb)
        base = len(verts)
        for qi, c in enumerate(q):
            pass
        corners = (cells[:, None, :] + np.array(q)[None, :, :]) * cs + o
        verts.extend(corners.reshape(-1, 3).tolist())
        k = np.arange(len(cells)) * 4 + base
        faces.extend(np.stack([k, k + 1, k + 2, k + 3], axis=1).tolist())
    me = bpy.data.meshes.new('gorilla')
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=cs * .01)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new('gorilla', me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ── build ──
bpy.ops.wm.read_factory_settings(use_empty=True)
tw.SMOOTH_MATS = True
tw.DEPTH = 8
G.HANDBULB = os.environ.get('GORILLA_PARTS', '0') != '1'  # experimental mode drops the hand bulbs
b = G.new_builder(stage)
G.STAGES[stage](b)
bpy.context.view_layer.update()
eye_objs = [o_ for o_ in b.objs if o_.material_slots and o_.material_slots[0].material and o_.material_slots[0].material.name.split('.')[0] in G.EYEMATS]
body_objs = [o_ for o_ in b.objs if o_ not in eye_objs]
body_objs_ref = [{'zc': o_.location.z, 'rz': o_.dimensions.z / 2} for o_ in body_objs]
PARTBVH, PARTOF = None, []
if True:                                                  # remember which primitive each surface triangle came from (part borders)
    dg = bpy.context.evaluated_depsgraph_get()
    pbm = bmesh.new()
    for oi, o_ in enumerate(body_objs):
        me_o = bpy.data.meshes.new_from_object(o_.evaluated_get(dg))
        me_o.transform(o_.matrix_world)
        t = bmesh.new()
        t.from_mesh(me_o)
        vm = {v: pbm.verts.new(v.co) for v in t.verts}
        mname = o_.material_slots[0].material.name.split('.')[0] if o_.material_slots and o_.material_slots[0].material else ''
        for f_ in t.faces:
            try:
                pbm.faces.new([vm[v] for v in f_.verts])
                PARTOF.append((oi, mname))
            except ValueError:
                pass
        t.free()
        bpy.data.meshes.remove(me_o)
    pbm.faces.ensure_lookup_table()
    PARTBVH = BVHTree.FromBMesh(pbm)
    pbm.free()
vox = tw.voxelise(body_objs)
occ, o, cs = occupancy(vox)
bpy.data.objects.remove(vox)
occ, (s, z0, xc, yc) = hull_cut(occ, o, cs)
occ = drop_thin(occ, int(os.environ.get('GORILLA_THIN', 2)))
body = mesh_from(occ, o, cs, b.M['fur'])
P.paint(body, stage)


def part_borders(ob):
    """Every face belongs to the outermost primitive at that spot. Fur parts get one even fur tone, stones/armour/mask keep
    the sheet colours (fur-dark pixels inside them are replaced by the part's own colour), and a dark seam marks every border
    where a non-fur part meets another part."""
    from mathutils.kdtree import KDTree
    me = ob.data
    npoly = len(me.polygons)
    attr = me.color_attributes['Col']
    nl = len(me.loops)
    cols = np.empty(nl * 4, np.float32)
    attr.data.foreach_get('color', cols)
    cols = cols.reshape(nl, 4)
    ls = np.empty(npoly, np.int64)
    me.polygons.foreach_get('loop_start', ls)
    cen = np.empty(npoly * 3, np.float32)
    me.polygons.foreach_get('center', cen)
    cen = cen.reshape(npoly, 3)
    nrm = np.empty(npoly * 3, np.float32)
    me.polygons.foreach_get('normal', nrm)
    nrm = nrm.reshape(npoly, 3)
    part = np.zeros(npoly, np.int64)
    kind = []
    FURM = ('fur', 'fur2', 'fur3')
    for i in range(npoly):
        hit = PARTBVH.find_nearest(Vector(cen[i] - nrm[i] * cs * .5))
        oi, mname = PARTOF[hit[2]] if hit[2] is not None else (-1, 'fur')
        part[i] = oi
        kind.append(1 if mname == 'stn' else 0)
    kind = np.array(kind)
    pc = cols[ls, :3] ** (1 / P.LIN)
    lum = pc @ np.array([.3, .59, .11])
    out = pc.copy()
    furf = kind == 0
    if False:                                                         # non-stone faces keep the (cleaned) sheet colours
        base = np.median(pc[furf & (lum < .35)], axis=0) if (furf & (lum < .35)).any() else np.median(pc[furf], axis=0)
        out[furf] = np.clip(base[None, :] * np.where(lum[furf] >= np.median(lum[furf]), 1.07, .92)[:, None], 0, 1)
    # stones coloured by their own geometry: height inside the stone -> top / middle / bottom colour measured from the sheet
    sat = pc.max(axis=1) - pc.min(axis=1)
    stone_ids = np.unique(part[~furf])
    rel = np.zeros(npoly)
    for oi in stone_ids:
        o_ = body_objs_ref[oi]
        sel = (part == oi) & ~furf
        rel[sel] = (cen[sel, 2] - o_['zc']) / max(o_['rz'], 1e-3)          # -1 bottom .. +1 top
    st_faces = ~furf
    blue = st_faces & (pc[:, 2] > pc[:, 0] + .06)
    orng = st_faces & (pc[:, 0] > pc[:, 2] + .06)
    TOP = np.median(pc[blue], axis=0) if blue.sum() > 20 else np.array([.38, .55, .78])
    BOT = np.median(pc[orng], axis=0) if orng.sum() > 20 else np.array([.78, .55, .32])
    MID = np.clip((TOP + BOT) / 2 * 1.25, 0, 1)
    t = np.clip((rel + 1) / 2, 0, 1)
    col_st = np.where((t > .55)[:, None], TOP[None, :] * (1 + .25 * (t[:, None] - .55)), np.where((t > .38)[:, None], MID[None, :], BOT[None, :]))
    out[st_faces] = np.clip(col_st[st_faces], 0, 1)
    hi = st_faces & (t > .82)
    out[hi] = np.clip(TOP * 1.5, 0, 1)                                   # glossy top highlight like the sheet's
    # colourful projection outside the stones = stone paint that landed on fur -> fur
    fur_tone = np.median(pc[furf & (sat < .08) & (lum < .3)], axis=0) if (furf & (sat < .08) & (lum < .3)).any() else np.array([.2, .17, .21])
    stray = furf & (sat > .10)
    out[stray] = fur_tone
    print('stone colours top', (TOP * 255).astype(int), 'bottom', (BOT * 255).astype(int), 'stray fixed', int(stray.sum()))
    kd = KDTree(npoly)
    for i in range(npoly):
        kd.insert(cen[i], i)
    kd.balance()
    seam = np.zeros(npoly, bool)
    for i in np.where(~furf)[0]:
        for (_, j, _) in kd.find_range(cen[i], cs * 1.1):
            if part[j] != part[i]:
                seam[i] = True
                break
    out[seam] *= .55
    print('parts', len(np.unique(part)), 'fur faces', int(furf.sum()), 'part faces', int((~furf).sum()), 'seam', int(seam.sum()))
    lt = np.empty(npoly, np.int64)
    me.polygons.foreach_get('loop_total', lt)
    for i in range(npoly):
        cols[ls[i]:ls[i] + lt[i], :3] = out[i] ** P.LIN
    attr.data.foreach_set('color', cols.reshape(-1))


if os.environ.get('GORILLA_PARTS', '0') == '1':   # experimental part borders (2026-11-14): worse, off by default
    part_borders(body)

# ── eyes: onto the face surface at the sheet's eye position ──
rgb, m = REF['front']
me_ = P.measure_eyes()
if me_ and eye_objs:
    cu, cv, h = me_
    ey, ez = cu * s, z0 + (h - cv) * s - .012
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bvh = BVHTree.FromBMesh(bm)
    bm.free()
    for sg in (-1, 1):
        side = [o_ for o_ in eye_objs if o_.location.y * sg > 0]
        darks = [o_ for o_ in side if o_.material_slots[0].material.name.split('.')[0] == 'dark']
        if not darks:
            continue
        d0 = darks[0].location.copy()
        hit = bvh.ray_cast(Vector((5, yc + sg * ey, ez)), Vector((-1, 0, 0)), 10)
        if hit[0] is None:
            continue
        tgt = Vector((hit[0].x + .004, yc + sg * ey, ez))
        for o_ in side:
            o_.location += tgt - d0
        print('eye', sg, 'surface x', round(hit[0].x, 3), 'y', round(tgt.y, 3), 'z', round(tgt.z, 3))
    bpy.context.view_layer.update()
    tw.voxelise(eye_objs)

# ── render ──
K.lighting(sky=0.9, sun=4.5)
K.rim_light(Vector((-0.6, 0.5, 0.7)))
sc = bpy.context.scene
corners = [body.matrix_world @ Vector(c) for c in body.bound_box]
c = sum(corners, Vector()) / 8
sc.render.resolution_x = sc.render.resolution_y = size
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'
sc.cycles.samples = samples
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.view_settings.view_transform = 'Standard'
ortho = 2.05 * max((q - c).length for q in corners)
for v in views:
    cam = bpy.data.cameras.new('cam_' + v)
    cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam_' + v, cam)
    sc.collection.objects.link(co)
    if v.startswith('o'):
        ctr = Vector((0, 0, .55))
        off = {'ofront': Vector((6, 0, 0)), 'oback': Vector((-6, 0, 0)), 'oside': Vector((0, -6, 0)), 'otop': Vector((0, 0, 6))}[v]
        co.location = ctr + off
        co.rotation_euler = (0, 0, math.pi / 2) if v == 'otop' else (ctr - co.location).to_track_quat('-Z', 'Y').to_euler()
        cam.ortho_scale = 1.5
    else:
        co.location = c + p3.VIEWS[v]
        co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
        cam.ortho_scale = ortho * .85
    sc.camera = co
    K.render(os.path.join(out, 'gorilla_s%d_%s.png' % (stage, v)))
