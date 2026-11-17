"""Reconstruct one gorilla stage from the user's orthographic 2x2 sheet (front / back / side / top), colours from the pictures.

    blender --background --python tool/blender/gorilla_recon2.py -- <sheet.png> <out dir> <stage 0..2> [voxel height, default 96]

Visual hull = front AND back AND side AND top silhouette. Only voxel faces that a view really SEES get that view's colour
(+x front, -x back, +-y side, +z top); hidden faces get the nearest seen colour.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gorilla_ortho_masks as om  # noqa: E402

args = sys.argv[sys.argv.index('--') + 1:]
sheet, out, stage = args[0], args[1], int(args[2])
NZ = int(args[3]) if len(args) > 3 else 96
os.makedirs(out, exist_ok=True)

px = om.load(sheet)
views = {}
for name, (x0, y0, x1, y1) in zip(om.NAMES, om.PANELS[stage]):
    reg = px[y0:y1, x0:x1]
    m, bg = om.mask_of(reg, 24.0 if np.median(reg) > 60 else 11.0)
    ys, xs = np.where(m)
    # ignore thin stray rows/cols at the borders
    views[name] = (reg[ys.min():ys.max() + 1, xs.min():xs.max() + 1], m[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    print(name, views[name][1].shape)


def resample(rgb, m, h, w):
    hh, ww = m.shape
    yy = np.minimum(((np.arange(h) + .5) * hh / h).astype(int), hh - 1)
    xx = np.minimum(((np.arange(w) + .5) * ww / w).astype(int), ww - 1)
    return rgb[yy][:, xx], m[yy][:, xx]


fh, fw = views['front'][1].shape
sh, sw = views['side'][1].shape
ny = int(round(fw * NZ / fh))
nx = int(round(sw * NZ / sh))
Fc, Fm = resample(*views['front'], NZ, ny)
Bc, Bm = resample(*views['back'], NZ, ny)
Bc, Bm = Bc[:, ::-1], Bm[:, ::-1]                      # the back view is mirrored left-right
Sc, Sm = resample(*views['side'], NZ, nx)
Tc, Tm = resample(*views['top'], nx, ny)               # rows = x (face at the bottom = +x), cols = y
print('grid x,y,z', nx, ny, NZ)

hull = np.zeros((nx, ny, NZ), bool)
for iz in range(NZ):
    r = NZ - 1 - iz
    hull[:, :, iz] = Sm[r, :, None] & Fm[r, None, :] & Bm[r, None, :] & Tm
print('hull voxels', int(hull.sum()))

# visible surfaces
xs_idx = np.arange(nx)[:, None, None]
front_x = np.where(hull, xs_idx, -1).max(axis=0)           # [y, z] largest x
back_x = np.where(hull, xs_idx, nx + 1).min(axis=0)        # [y, z] smallest x
ys_idx = np.arange(ny)[None, :, None]
y_hi = np.where(hull, ys_idx, -1).max(axis=1)              # [x, z]
y_lo = np.where(hull, ys_idx, ny + 1).min(axis=1)
zs_idx = np.arange(NZ)[None, None, :]
top_z = np.where(hull, zs_idx, -1).max(axis=2)             # [x, y]

BR = 1.25


def c3(arr, r, c):
    return tuple(np.clip(arr[r, c] / 255.0 * BR, 0, 1))


FUR = (.16, .13, .17)
bpy.ops.wm.read_factory_settings(use_empty=True)
bm = bmesh.new()
cl = bm.loops.layers.color.new('Col')
FACES = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]), ((-1, 0, 0), [(0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1)]),
         ((0, 1, 0), [(1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)]), ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
         ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)])]
vs = 1.15 / NZ
for ix, iy, iz in zip(*np.nonzero(hull)):
    r = NZ - 1 - iz
    for nrm, quad in FACES:
        jx, jy, jz = ix + nrm[0], iy + nrm[1], iz + nrm[2]
        if 0 <= jx < nx and 0 <= jy < ny and 0 <= jz < NZ and hull[jx, jy, jz]:
            continue
        if nrm[0] == 1:
            c = c3(Fc, r, iy) if front_x[iy, iz] == ix else FUR
        elif nrm[0] == -1:
            c = c3(Bc, r, iy) if back_x[iy, iz] == ix else FUR
        elif nrm[1] == 1:
            c = c3(Sc, r, ix) if y_hi[ix, iz] == iy else FUR
        elif nrm[1] == -1:
            c = c3(Sc, r, ix) if y_lo[ix, iz] == iy else FUR
        else:
            c = c3(Tc, ix, iy) if top_z[ix, iy] == iz else FUR
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
sc_.render.resolution_x = sc_.render.resolution_y = 400
sc_.view_settings.view_transform = 'Standard'
w = bpy.data.worlds.new('w')
sc_.world = w
w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
sun = bpy.data.lights.new('sun', 'SUN')
sun.energy = 2.2
so = bpy.data.objects.new('sun', sun)
sc_.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(-35))
cen = Vector((0, 0, .55))
VIEWS = {'front': Vector((3, 0, .4)), 'q': Vector((2.4, -2.1, 1.2)), 'side': Vector((0, -3, .4)), 'back': Vector((-3, 0, .4)), 'top': Vector((0.01, 0, 3))}
for name, off in VIEWS.items():
    cam = bpy.data.cameras.new('c')
    cam.type = 'ORTHO'
    cam.ortho_scale = 1.5
    co = bpy.data.objects.new('c', cam)
    sc_.collection.objects.link(co)
    co.location = cen + off
    co.rotation_euler = (cen - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc_.camera = co
    sc_.render.filepath = os.path.join(out, 'rec2_s%d_%s.png' % (stage, name))
    bpy.ops.render.render(write_still=True)
