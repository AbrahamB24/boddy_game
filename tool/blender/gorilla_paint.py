"""Colour the voxel gorilla from the user's orthographic sheet (projection painting).

    blender --background --python tool/blender/gorilla_paint.py -- <sheet.png> <out dir> <stage 0..2> [views, default front,q,side,back] [samples] [size]

The shape is the fitted primitive model of gorilla.py (voxelised as usual). Every exposed voxel face that a sheet view really sees
(+x front, -x back, +-y side, +z top; checked by a ray cast) takes the colour of that view's pixel; hidden faces get the fur colour.
"""
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gorilla as G  # noqa: E402
import gorilla_ortho_masks as om  # noqa: E402

args = sys.argv[sys.argv.index('--') + 1:]
sheet, out, stage = args[0], args[1], int(args[2])
views = (args[3] if len(args) > 3 else 'front,q,side,back').split(',')
samples = int(args[4]) if len(args) > 4 else 32
size = int(args[5]) if len(args) > 5 else 560

px = om.load(sheet)
REF = {}
for name, (x0, y0, x1, y1) in zip(om.NAMES, om.PANELS[stage]):
    reg = px[y0:y1, x0:x1]
    m, bg = om.mask_of(reg, 24.0 if np.median(reg) > 60 else 11.0)
    ys, xs = np.where(m)
    REF[name] = (reg[ys.min():ys.max() + 1, xs.min():xs.max() + 1], m[ys.min():ys.max() + 1, xs.min():xs.max() + 1])



def _dil(a, n=1):
    for _ in range(n):
        b_ = a.copy()
        b_[1:, :] |= a[:-1, :]
        b_[:-1, :] |= a[1:, :]
        b_[:, 1:] |= a[:, :-1]
        b_[:, :-1] |= a[:, 1:]
        a = b_
    return a


def _ero(a, n=1):
    return ~_dil(~a, n)


def clean_ref(rgb, m):
    """Clear part borders in the sheet picture itself: FUR (dark, unsaturated) vs PARTS (stones, armour, crystals, mask, feet).
    Parts are closed (no holes), opened (no fringes); fur becomes one calm tone in two steps; a thin dark seam rings every part."""
    f = rgb / 255.0
    lum = f @ np.array([.3, .59, .11])
    sat = f.max(axis=2) - f.min(axis=2)
    part = m & ((sat > CLEAN_SAT) | (lum > CLEAN_LUM))
    part = _ero(_dil(part, 2), 2)                 # close
    part = _dil(_ero(part, 1), 1) & m             # open
    fur = m & ~part
    out = rgb.copy()
    if fur.any():
        base = np.median(rgb[fur], axis=0)
        k = lum.copy()
        for ax in (0, 1):
            for _ in range(3):
                k = (np.roll(k, 1, ax) + k + np.roll(k, -1, ax)) / 3
        tone = np.where(k >= np.median(k[fur]), 1.10, .88)
        out[fur] = np.clip(base[None, :] * tone[fur][:, None], 0, 255)
        ring = fur & _dil(part, 1)
        out[ring] = out[ring] * .6
    return out


CLEAN = os.environ.get('GORILLA_CLEAN', '0') == '1'      # experimental: cleaned sheet colours, fragmented stones -> off
CLEAN_SAT = float(os.environ.get('GORILLA_CSAT', .12))
CLEAN_LUM = float(os.environ.get('GORILLA_CLUM', .34))
REF_RAW = dict(REF)
if CLEAN:
    REF = {k: (clean_ref(v[0], v[1]), v[1]) for k, v in REF.items()}


def gold(lum):
    """Gold ramp (dark bronze -> bright gold) from a lightness 0..1."""
    t = np.clip((lum - .12) / .58, 0, 1)[..., None]
    lo, mid, hi = np.array([.26, .19, .08]), np.array([.66, .52, .24]), np.array([.92, .80, .52])
    return np.where(t < .55, lo + (mid - lo) * (t / .55), mid + (hi - mid) * ((t - .55) / .45))


def gray_stones(rgb, m, st, view=''):
    """Recolour the sheet picture before projection (user 2026-11-14/15):
    - round STONES: silver gray, lighter and more neutral than the bluish skin gray, relief (lightness) kept
    - ARMOUR (tan / copper): gold-plated
    - CRYSTALS (stage 3): white
    Stage 0: all coloured pixels are stones. Stage 1: bulbs low on the body = stones, the tan armour up high = gold.
    Stage 2: armour tan = gold, blue = white crystals."""
    f = rgb / 255.0
    lum = f @ np.array([.3, .59, .11])
    sat = f.max(axis=2) - f.min(axis=2)
    h = m.shape[0]
    rows = np.arange(h)[:, None] * np.ones((1, m.shape[1]))
    blue = m & (f[..., 2] > f[..., 0] + .05) & (sat > .07)
    warm = m & (f[..., 0] > f[..., 2] + .05) & (sat > .07)
    out = f.copy()
    silver = np.clip(lum * STONE_GAIN, 0, 1)[..., None] * np.array([1.0, 1.0, 1.0])[None, None, :]
    if st == 0:
        stone = m & (sat > .08)                      # coloured bulbs only; the gray skin, mask and feet are low-saturation
        out[stone] = silver[stone]
    elif st == 1:
        low = rows > h * .45
        stone = m & low & ((sat > .07) | _dil(blue, 9) & (sat > .04))
        cols_ = np.arange(m.shape[1])[None, :] * np.ones((m.shape[0], 1))
        shoulder = m & (rows > h * .08) & (rows < h * .55) & (np.abs(cols_ - m.shape[1] / 2) > m.shape[1] * .2) & (lum > .22)   # pauldron zone: everything light on the sides up high
        if view == 'side':                                  # the sheet's side view paints stones where the front view shows the pauldron: treat the shoulder zone as armour
            cols2 = np.arange(m.shape[1])[None, :] * np.ones((m.shape[0], 1))
            shoulder = shoulder | (m & (rows > h * .27) & (rows < h * .55) & (cols2 > m.shape[1] * .38) & (cols2 < m.shape[1] * .68) & (lum > .22))
        armour = shoulder | (m & ~low & (f[..., 0] >= f[..., 2] - .02) & (lum > .30) & (sat > .05))
        out[stone] = silver[stone]
        g = gold(lum)
        out[armour] = g[armour]
    else:
        armour = m & (f[..., 0] >= f[..., 2] - .02) & (lum > .30) & (sat > .06)
        cryst = m & (sat > .14) & (f[..., 2] > f[..., 0] + .07) & (lum > .30) & ~armour    # strong blue only; bluish gray skin has low saturation
        g = gold(lum * 1.1)
        out[armour] = g[armour]
        wl = np.clip(lum * 1.5 + .12, 0, 1)[..., None] * np.array([.96, .98, 1.0])[None, None, :]
        out[cryst] = wl[cryst]
    if MERGE:
        cl = {'stone': stone, 'armour': armour} if st == 1 else ({'stone': stone} if st == 0 else {'armour': armour, 'crystal': cryst})
        out = merge_regions(out, m, cl, lum, st)
    print('recolour: stage', st)
    return np.clip(out * 255.0, 0, 255)




def _box(a, r):
    """Box sum (2r+1)^2 of a float array."""
    out = np.zeros_like(a)
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out += np.roll(np.roll(a, dy, 0), dx, 1)
    return out


def merge_regions(out, m, classes, lum, st):
    """Large coherent regions (user 2026-11-15: 'zu kleinteilig'): majority-filter the class map (stone / armour / crystal / fur) so every
    part is ONE surface without specks, then shade each class with only three flat tones from the smoothed lightness."""
    names = ['fur', 'stone', 'armour', 'crystal']
    cm = np.zeros(m.shape + (4,), np.float32)
    for k, name in enumerate(names):
        if name in classes:
            cm[..., k] = classes[name] & m
    cm[..., 0] = m & (cm[..., 1:].sum(axis=2) == 0) & (lum < .30)            # everything dark and unclassified is fur
    R = MERGE_R
    for _ in range(2):
        sm = np.stack([_box(cm[..., k], R) for k in range(4)], axis=-1)
        lab = sm.argmax(axis=2)
        keep = (sm.max(axis=2) > 0)
        cm = np.zeros_like(cm)
        for k in range(4):
            cm[..., k] = (lab == k) & keep & m
    ls = lum.copy()
    for _ in range(2):                                                      # smooth lightness so the tone steps follow big shapes
        ls = _box(ls, 2) / 25.0
    res = out.copy()
    for k, name in enumerate(names):
        sel = cm[..., k] > 0
        if not sel.any() or name not in classes and name != 'fur':
            continue
        l = ls[sel]
        q = np.quantile(l, [.34, .67])
        step = np.digitize(l, q)                                            # 0 dark, 1 mid, 2 light
        if name == 'fur':
            base = np.median(out[sel], axis=0)
            res[sel] = np.clip(base[None, :] * np.array([.86, 1.0, 1.14])[step][:, None], 0, 1)
        elif name == 'stone':
            res[sel] = np.array([[.36, .38, .41], [.55, .57, .60], [.75, .77, .80]])[step]
        elif name == 'armour':
            res[sel] = np.array([[.46, .34, .14], [.74, .58, .24], [.95, .82, .46]])[step]
        else:
            res[sel] = np.array([[.72, .75, .82], [.88, .90, .95], [.98, .99, 1.0]])[step]
    return res


MERGE_R = int(os.environ.get('GORILLA_MERGE', 4))
MERGE = os.environ.get('GORILLA_MERGEREGIONS', '1') == '1'
STONE_GAIN = float(os.environ.get('GORILLA_STONEGAIN', 1.30))
GRAY_STONES = os.environ.get('GORILLA_GRAYSTONES', '1') == '1'
GRAY_GAIN = float(os.environ.get('GORILLA_GRAYGAIN', 1.05))
if GRAY_STONES:
    REF = {k: (gray_stones(v[0], v[1], stage, k), v[1]) for k, v in REF.items()}
FUR = np.array([.17, .14, .18]) ** 2.2
BRIGHT = 1.0
LIN = 2.2                                                   # sheet colours are sRGB, the vertex colour attribute is linear
EMIT = float(os.environ.get('GORILLA_EMIT', 1.0))


def mt_name(me, i):
    m = me.materials[i]
    return m.name.split('.')[0] if m else ''




SEGMENT = os.environ.get('GORILLA_SEGMENT', '0') == '1'
FUR_LUM = float(os.environ.get('GORILLA_FURLUM', .27))
SEAM = float(os.environ.get('GORILLA_SEAM', .62))


def segment(me, cols, cen, kd):
    """Clear part borders. Every face is classed as FUR (dark), GRAY (mask, feet, gray stones) or COLOUR (stones, armour, crystals);
    the classes are majority-filtered over the neighbours (no specks, straight borders), fur becomes one even tone (two steps),
    and a non-fur part gets a dark seam where it meets fur."""
    npoly = len(me.polygons)
    ls = np.empty(npoly, np.int64)
    me.polygons.foreach_get('loop_start', ls)
    lt = np.empty(npoly, np.int64)
    me.polygons.foreach_get('loop_total', lt)
    pc = cols[ls, :3] ** (1 / LIN)
    lum = pc @ np.array([.3, .59, .11])
    sat = pc.max(axis=1) - pc.min(axis=1)
    lab = np.where((lum < FUR_LUM) & (sat < .14), 0, np.where(sat < .085, 1, 2))
    nb = [[j for (_, j, _) in kd.find_range(cen[i], .026)] for i in range(npoly)]
    for _ in range(2):
        new = lab.copy()
        for i in range(npoly):
            new[i] = np.bincount(lab[nb[i]], minlength=3).argmax()
        lab = new
    out = pc.copy()
    fur = lab == 0
    if fur.any():
        base = np.median(pc[fur], axis=0)
        out[fur] = np.clip(base[None, :] * np.where(lum[fur] >= np.median(lum[fur]), 1.08, .90)[:, None], 0, 1)
    near = [[j for (_, j, _) in kd.find_range(cen[i], .017)] for i in range(npoly)]
    seam = np.array([lab[i] != 0 and (lab[near[i]] == 0).any() for i in range(npoly)])
    out[seam] *= SEAM
    print('segment: fur', int(fur.sum()), 'gray', int((lab == 1).sum()), 'colour', int((lab == 2).sum()), 'seam', int(seam.sum()))
    for i in range(npoly):
        cols[ls[i]:ls[i] + lt[i], :3] = out[i] ** LIN


def paint(ob, st):
    me = ob.data
    n = len(me.vertices)
    co = np.empty(n * 3, np.float32)
    me.vertices.foreach_get('co', co)
    co = co.reshape(n, 3)
    x0, y0, z0 = co.min(axis=0)
    x1, y1, z1 = co.max(axis=0)
    xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
    fh = REF['front'][1].shape[0]
    s = (z1 - z0) / fh                                     # world units per reference pixel (front height = model height)
    bm = bmesh.new()
    bm.from_mesh(me)
    bvh = BVHTree.FromBMesh(bm)
    bm.free()
    attr = me.color_attributes.new('Col', 'FLOAT_COLOR', 'CORNER')
    stats = {'seen': 0, 'hidden': 0}
    # face and eyes keep MY materials (the phoenix eye recipe is a user rule; painting would also double the sheet's eyes)
    KEEP = {'dark', 'white', 'eyewhite', 'brow'}
    head_top = G.prm(st, 'dt', {0: .85, 1: .90, 2: .90}[st]) + G.prm(st, 'dd', {0: .20, 1: .205, 2: .19}[st]) - .03
    head_z0 = G.prm(st, 'dz', {0: .55, 1: .58, 2: .62}[st]) - .06
    own = {}
    for i, mt in enumerate(me.materials):
        if mt is not None and mt.name.split('.')[0] in KEEP and mt.use_nodes:
            own[i] = np.array(mt.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value[:3])
    cols = np.zeros((len(me.loops), 4), np.float32)
    cols[:, 3] = 1.0
    # smoothed normals: a voxel staircase on a curved surface must take ONE view's colour, not alternate per step
    from mathutils.kdtree import KDTree
    npoly = len(me.polygons)
    cen = np.empty(npoly * 3, np.float32)
    me.polygons.foreach_get('center', cen)
    cen = cen.reshape(npoly, 3)
    nrms = np.empty(npoly * 3, np.float32)
    me.polygons.foreach_get('normal', nrms)
    nrms = nrms.reshape(npoly, 3)
    kd = KDTree(npoly)
    for i in range(npoly):
        kd.insert(cen[i], i)
    kd.balance()
    SR = float(os.environ.get('GORILLA_SMOOTH', .045))
    snrm = np.zeros_like(nrms)
    for i in range(npoly):
        ids = [j for (_, j, _) in kd.find_range(cen[i], SR)]
        v = nrms[ids].sum(axis=0)
        snrm[i] = v / max(np.linalg.norm(v), 1e-6)
    for poly in me.polygons:
        nrm = poly.normal
        c = poly.center
        if poly.material_index in own and head_z0 < c.z < head_top:
            for li in poly.loop_indices:
                cols[li, :3] = own[poly.material_index]
            continue
        sn = snrm[poly.index]
        ax = int(np.argmax(np.abs(sn)))
        sgn = 1 if sn[ax] > 0 else -1
        dvec = Vector([float(sgn) if i == ax else 0.0 for i in range(3)])
        if ax == 2 and sgn < 0:                              # underside
            col = FUR
        else:
            hit = bvh.ray_cast(c + nrm * .004 + dvec * .004, dvec, 6.0)
            if hit[0] is not None:
                col = FUR
                stats['hidden'] += 1
            else:
                stats['seen'] += 1
                if ax == 0:
                    view = 'front' if sgn > 0 else 'back'
                elif ax == 1:
                    view = 'side'
                else:
                    view = 'top'
                rgb, m = REF[view]
                h, w = m.shape
                if view == 'front':
                    u, v = w / 2 + (c.y - yc) / s, h - (c.z - z0) / s
                elif view == 'back':
                    u, v = w / 2 - (c.y - yc) / s, h - (c.z - z0) / s
                elif view == 'side':
                    u, v = w / 2 + (c.x - xc) / s, h - (c.z - z0) / s
                else:
                    u, v = w / 2 + (c.y - yc) / s, h / 2 + (c.x - xc) / s
                ui, vi = int(np.clip(u, 0, w - 1)), int(np.clip(v, 0, h - 1))
                if not m[vi, ui]:                            # outside the sheet silhouette: take the nearest inside pixel
                    ys, xs = np.where(m[max(vi - 6, 0):vi + 7, max(ui - 6, 0):ui + 7])
                    if len(xs):
                        k = np.argmin((ys - min(6, vi)) ** 2 + (xs - min(6, ui)) ** 2)
                        vi, ui = max(vi - 6, 0) + ys[k], max(ui - 6, 0) + xs[k]
                col = np.clip(rgb[vi, ui] / 255.0 * BRIGHT, 0, 1) ** LIN
        for li in poly.loop_indices:
            cols[li, :3] = col
    if SEGMENT:
        segment(me, cols, cen, kd)
    attr.data.foreach_set('color', cols.reshape(-1))
    print('painted faces: seen', stats['seen'], 'hidden', stats['hidden'])
    mat = bpy.data.materials.new('sheetpaint')
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes['Principled BSDF']
    node = nt.nodes.new('ShaderNodeVertexColor')
    node.layer_name = 'Col'
    # the sheet colours already contain their shading: let them shine as they are (emission), plus a little diffuse for the voxel edges
    bsdf.inputs['Base Color'].default_value = (0, 0, 0, 1)
    nt.links.new(node.outputs['Color'], bsdf.inputs['Emission Color'])
    bsdf.inputs['Emission Strength'].default_value = EMIT
    bsdf.inputs['Roughness'].default_value = 1.0
    me.materials.clear()
    me.materials.append(mat)
    for poly in me.polygons:
        poly.material_index = 0




def measure_eyes():
    """Eye position from the sheet: the two bright highlight dots in the upper part of the front view; needs the model's height/centre."""
    rgb, m = REF_RAW['front']
    h, w = m.shape
    bright = (rgb.min(axis=2) > 190) & m
    dark = rgb.max(axis=2) < 55
    near = np.zeros_like(dark)
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            near |= np.roll(np.roll(dark, dy, 0), dx, 1)
    ys, xs = np.where(bright & near)            # eye highlight = bright dot right next to the black pupil
    lo, hi = {0: (.08, .40), 1: (.08, .40), 2: (.20, .42)}[stage]
    sel = (ys > h * lo) & (ys < h * hi) & (abs(xs - w / 2) < w * .17)
    ys, xs = ys[sel], xs[sel]
    left, right = xs < w / 2, xs >= w / 2
    if left.sum() < 2 or right.sum() < 2:
        return None
    cu = (xs[right].mean() - xs[left].mean()) / 2 / 1.0
    cv = np.concatenate([ys[left], ys[right]]).mean()
    return cu, cv, h


if __name__ == '__main__':
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import thunderwake_voxel as _tw
    _tw.SMOOTH_MATS = True
    _tw.DEPTH = 8
    _b = G.new_builder(stage)
    G.STAGES[stage](_b)
    _ob = _tw.voxelise(_b.objs)
    _c = np.empty(len(_ob.data.vertices) * 3, np.float32)
    _ob.data.vertices.foreach_get('co', _c)
    _c = _c.reshape(-1, 3)
    _z0, _z1 = _c[:, 2].min(), _c[:, 2].max()
    _me = measure_eyes()
    if _me:
        _s = (_z1 - _z0) / _me[2]
        G.EYE = (_me[0] * _s * .92, _z0 + (_me[2] - _me[1]) * _s - .012)         # highlight dot sits a bit above the eye centre
        print('eye y,z', G.EYE)
    G.POST = paint
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(out, exist_ok=True)
    G.render_all(stage, out, views, samples, size)
