"""Image-based reconstruction of one gorilla stage from the user's sheet (front + side + back silhouettes, colours from the pictures).

    blender --background --python tool/blender/gorilla_recon.py -- <sheet.jpg> <out dir> <stage 0..2> [voxel height, default 64]

Visual hull = front AND back AND side silhouette; every exposed voxel face takes its colour from the view that sees it
(+x front, -x back, +y/-y side, top from side). Experiment: compares against the hand-built gorilla.py.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
sheet, out, stage = args[0], args[1], int(args[2])
NZ = int(args[3]) if len(args) > 3 else 64
os.makedirs(out, exist_ok=True)

img = bpy.data.images.load(sheet)
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1, :, :3] * 255.0

ROWS = [(52, 245), (292, 500), (540, 766)]
COLS = {'front': (30, 280), 'side': (840, 1070), 'back': (1100, 1350)}


def fill_outside(m):
    """Mask without holes: everything not reachable from the border is inside."""
    out_ = np.zeros_like(m)
    out_[0, :] = ~m[0, :]
    out_[-1, :] = ~m[-1, :]
    out_[:, 0] = ~m[:, 0]
    out_[:, -1] = ~m[:, -1]
    for _ in range(400):
        n = out_.copy()
        n[1:, :] |= out_[:-1, :]
        n[:-1, :] |= out_[1:, :]
        n[:, 1:] |= out_[:, :-1]
        n[:, :-1] |= out_[:, 1:]
        n &= ~m
        if (n == out_).all():
            break
        out_ = n
    return ~out_


def cut(view):
    y0, y1 = ROWS[stage]
    x0, x1 = COLS[view]
    reg = px[y0:y1, x0:x1]
    bg = np.median(np.concatenate([reg[:6].reshape(-1, 3), reg[-6:].reshape(-1, 3)]), axis=0)
    d = np.sqrt(((reg - bg) ** 2).sum(axis=2))
    m = d > 14.0
    mm = m.astype(np.uint8)
    nb = sum(np.roll(np.roll(mm, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)) - mm
    m = m & (nb >= 3)
    m[:4, :] = False                                           # label / separator residue
    m = fill_outside(m)
    ys, xs = np.where(m)
    bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    return reg[by0:by1, bx0:bx1], m[by0:by1, bx0:bx1]


views = {v: cut(v) for v in COLS}
hf = views['front'][1].shape[0]
sc = NZ / hf                                                    # one pixel -> sc voxels (all views brought to the same height)


def resample(rgb, m, nz):
    h, w = m.shape
    nzv = nz
    nw = max(1, int(round(w * nz / h)))
    yy = np.minimum((np.arange(nzv) + .5) * h / nzv, h - 1).astype(int)
    xx = np.minimum((np.arange(nw) + .5) * w / nw, w - 1).astype(int)
    return rgb[yy][:, xx], m[yy][:, xx]


R = {}
for v, (rgb, m) in views.items():
    nz = NZ if v == 'front' else int(round(NZ * m.shape[0] / hf))      # keep the relative height of each view
    nz = max(8, nz)
    R[v] = resample(rgb, m, nz)
    print(v, 'voxels', R[v][1].shape)

Fm, Sm, Bm = R['front'][1], R['side'][1], R['back'][1]
nz = NZ
ny = max(Fm.shape[1], Bm.shape[1])
nx = Sm.shape[1]


def pad_to(m, rgb, h, w):
    """Place a view in an (h, w) frame, bottom aligned, horizontally centred."""
    mm = np.zeros((h, w), bool)
    cc = np.zeros((h, w, 3), np.float32)
    hh, ww = m.shape
    hh2 = min(hh, h)
    x0 = (w - ww) // 2
    mm[h - hh2:, x0:x0 + ww] = m[hh - hh2:]
    cc[h - hh2:, x0:x0 + ww] = rgb[hh - hh2:]
    return mm, cc


Fm, Fc = pad_to(R['front'][1], R['front'][0], nz, ny)
Bm, Bc = pad_to(R['back'][1], R['back'][0], nz, ny)
Bm, Bc = Bm[:, ::-1], Bc[:, ::-1]                                       # back view is mirrored
Sm, Sc = pad_to(R['side'][1], R['side'][0], nz, nx)

# voxel grid indexed [x, y, z]; image rows are top-down, so flip z
hull = np.zeros((nx, ny, nz), bool)
for ix in range(nx):
    for iy in range(ny):
        for iz in range(nz):
            r = nz - 1 - iz
            hull[ix, iy, iz] = Fm[r, iy] and Bm[r, iy] and Sm[r, ix]
print('hull voxels', int(hull.sum()), 'grid', hull.shape)


def col(arr, r, c):
    return tuple(np.clip(arr[r, c] / 255.0 * 1.35, 0, 1))


bpy.ops.wm.read_factory_settings(use_empty=True)
bm = bmesh.new()
cl = bm.loops.layers.color.new('Col')
FACES = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]), ((-1, 0, 0), [(0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1)]),
         ((0, 1, 0), [(1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)]), ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
         ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)])]
vs = 1.0 / nz * 1.15                                                  # world voxel size so the height is ~1.15
for ix, iy, iz in zip(*np.nonzero(hull)):
    r = nz - 1 - iz
    for nrm, quad in FACES:
        jx, jy, jz = ix + nrm[0], iy + nrm[1], iz + nrm[2]
        if 0 <= jx < nx and 0 <= jy < ny and 0 <= jz < nz and hull[jx, jy, jz]:
            continue
        if nrm[0] == 1:
            c = col(Fc, r, iy)
        elif nrm[0] == -1:
            c = col(Bc, r, iy)
        elif nrm[1] != 0:
            c = col(Sc, r, ix)
        else:
            c = col(Sc, max(r - 1, 0), ix)
        vv = [bm.verts.new(((ix + q[0] - nx / 2) * vs, (iy + q[1] - ny / 2) * vs, (iz + q[2]) * vs)) for q in quad]
        try:
            f = bm.faces.new(vv)
        except ValueError:
            continue
        for lp in f.loops:
            lp[cl] = (c[0], c[1], c[2], 1.0)
me = bpy.data.meshes.new('recon')
bm.to_mesh(me)
ob = bpy.data.objects.new('recon', me)
bpy.context.scene.collection.objects.link(ob)
mat = bpy.data.materials.new('vc')
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes['Principled BSDF']
att = nt.nodes.new('ShaderNodeVertexColor')
att.layer_name = 'Col'
nt.links.new(att.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 1.0
ob.data.materials.append(mat)

sc_ = bpy.context.scene
sc_.render.engine = 'CYCLES'
sc_.cycles.samples = 16
sc_.cycles.use_denoising = True
sc_.render.film_transparent = True
sc_.render.resolution_x = sc_.render.resolution_y = 360
sc_.view_settings.view_transform = 'Standard'
w = bpy.data.worlds.new('w')
sc_.world = w
w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.1
sun = bpy.data.lights.new('sun', 'SUN')
sun.energy = 2.5
so = bpy.data.objects.new('sun', sun)
sc_.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(-35))
cen = Vector((0, 0, .55))
VIEWS = {'front': Vector((3, 0, .9)), 'q': Vector((2.4, -2.1, 1.1)), 'side': Vector((0, -3, .8)), 'back': Vector((-3, 0, .9))}
for name, off in VIEWS.items():
    cam = bpy.data.cameras.new('c')
    cam.type = 'ORTHO'
    cam.ortho_scale = 1.45
    co = bpy.data.objects.new('c', cam)
    sc_.collection.objects.link(co)
    co.location = cen + off
    co.rotation_euler = (cen - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc_.camera = co
    sc_.render.filepath = os.path.join(out, 'rec_s%d_%s.png' % (stage, name))
    bpy.ops.render.render(write_still=True)
