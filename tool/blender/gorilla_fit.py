"""Fit the main dimensions of one gorilla stage to the user's orthographic sheet (front/back/side/top silhouettes).

    blender --background --python tool/blender/gorilla_fit.py -- <sheet.png> <out dir> <stage 0..2> [passes]

Coordinate descent on gorilla.PARAMS[stage]: for every parameter try +-step, keep what raises the mean silhouette IoU of the four views.
Silhouettes come from a fast Workbench render of the raw primitives (no voxelising).
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gorilla as G  # noqa: E402
import gorilla_ortho_masks as om  # noqa: E402

args = sys.argv[sys.argv.index('--') + 1:]
sheet, outdir, stage = args[0], args[1], int(args[2])
outjson = os.path.join(outdir, 'fit_s%d.json' % stage)
os.makedirs(outdir, exist_ok=True)
PASSES = int(args[3]) if len(args) > 3 else 3
SIZE = 320
TMP = os.path.join(os.environ.get('TEMP', '.'), 'gorilla_fit_tmp_s%s.png' % args[2])

# name -> (default, lo, hi); defaults must equal the ones in the stage function
SPECS = {
    0: {'tx': (.04, -.1, .2), 'tz': (.49, .38, .62), 'trx': (.27, .15, .4), 'try': (.25, .15, .4), 'trz': (.24, .15, .35),
        'hx': (.13, -.05, .3), 'hz': (.58, .45, .75), 'hrx': (.19, .08, .3), 'hry': (.27, .12, .4), 'hrz': (.13, .06, .25),
        'px': (-.12, -.3, .05), 'pz': (.34, .22, .5), 'prx': (.15, .08, .25), 'pry': (.20, .1, .35), 'prz': (.17, .08, .28),
        'dx': (.33, .15, .5), 'dz': (.55, .4, .7), 'dt': (.85, .7, 1.0), 'dr': (.27, .15, .35), 'dd': (.20, .08, .3), 'fz': (.68, .5, .85),
        'sx': (.19, .0, .35), 'sy': (.26, .15, .4), 'sz': (.54, .4, .7), 'ex': (.26, .05, .45), 'ey': (.33, .2, .5), 'ez': (.31, .15, .45),
        'ax': (.38, .15, .55), 'ay': (.31, .18, .45), 'ar1': (.16, .08, .24), 'ar2': (.14, .07, .22),
        'lx': (-.15, -.3, .05), 'ly': (.25, .15, .4), 'fx': (-.05, -.2, .15), 'lr1': (.15, .08, .24), 'lr2': (.11, .06, .2), 'ys': (.90, .7, 1.1), 'bxo': (0.0, -.2, .2), 'fk': (1.3, .9, 1.5)},
    1: {'tx': (-.03, -.2, .15), 'tz': (.48, .38, .6), 'trx': (.30, .15, .42), 'try': (.34, .2, .45), 'trz': (.28, .18, .38),
        'px': (-.22, -.35, .0), 'pz': (.35, .22, .5), 'prx': (.17, .08, .28), 'pry': (.24, .12, .35), 'prz': (.19, .08, .3),
        'rx': (.0, -.15, .2), 'rz': (.72, .6, .85), 'dx': (.24, .1, .45), 'dz': (.58, .45, .7), 'dt': (.9, .75, 1.0), 'dr': (.29, .18, .36),
        'dd': (.205, .08, .3), 'fz': (.745, .55, .9), 'fk': (1.32, .9, 1.5), 'qx': (.08, -.05, .25), 'qy': (.50, .3, .65), 'qz': (.60, .45, .75),
        'qrx': (.18, .08, .28), 'qry': (.17, .08, .26), 'qrz': (.155, .08, .24), 'sx': (.10, -.05, .3), 'sy': (.38, .2, .5), 'sz': (.50, .35, .65),
        'ex': (.19, .0, .4), 'ey': (.43, .25, .55), 'ez': (.28, .15, .45), 'ax': (.30, .1, .5), 'ay': (.41, .25, .55), 'ar1': (.16, .08, .24),
        'ar2': (.145, .08, .22), 'lx': (-.22, -.35, .0), 'ly': (.28, .15, .4), 'fx': (-.08, -.25, .15), 'lr1': (.16, .08, .24), 'lr2': (.12, .06, .2),
        'ys': (.96, .7, 1.1)},
    2: {'tx': (-.08, -.25, .1), 'tz': (.44, .3, .6), 'trx': (.34, .2, .45), 'try': (.30, .15, .4), 'trz': (.28, .18, .38),
        'shx': (.02, -.15, .2), 'shz': (.62, .5, .75), 'shrx': (.22, .1, .32), 'shry': (.42, .25, .55), 'shrz': (.19, .1, .28),
        'px': (-.30, -.45, -.1), 'pz': (.30, .2, .45), 'prx': (.22, .1, .32), 'pry': (.27, .15, .38), 'prz': (.22, .1, .3),
        'dx': (.20, .05, .4), 'dz': (.62, .5, .8), 'dt': (.90, .75, 1.0), 'dr': (.265, .15, .33), 'dd': (.19, .08, .28), 'fz': (.805, .6, .95),
        'fk': (1.3, .9, 1.5), 'sx': (.04, -.1, .25), 'sy': (.46, .25, .6), 'sz': (.60, .45, .75), 'ex': (.11, -.1, .35), 'ey': (.52, .3, .65),
        'ez': (.34, .2, .5), 'ax': (.16, -.05, .4), 'ay': (.46, .25, .6), 'ar1': (.14, .08, .22), 'ar2': (.17, .08, .26), 'ar3': (.165, .08, .26),
        'lx': (-.28, -.45, -.05), 'ly': (.23, .12, .38), 'fx': (-.17, -.35, .1), 'bxo': (0.0, -.2, .2), 'ys': (.76, .55, 1.05),
        'pw': (1.0, .6, 2.2), 'ph': (1.0, .5, 2.0), 'cl': (.40, .15, .7), 'cr': (.08, .04, .14), 'cdy': (.62, .2, 1.2), 'cdz': (.55, .15, 1.2), 'br': (.19, .12, .27)},
}
specs = SPECS[stage]

# reference masks (cropped to their bbox)
px = om.load(sheet)
REF = {}
for name, (x0, y0, x1, y1) in zip(om.NAMES, om.PANELS[stage]):
    reg = px[y0:y1, x0:x1]
    m, bg = om.mask_of(reg, 24.0 if np.median(reg) > 60 else 11.0)
    ys, xs = np.where(m)
    REF[name] = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = SIZE
sc.display.shading.light = 'FLAT'
sc.display.shading.color_type = 'SINGLE'
sc.display.shading.single_color = (1, 1, 1)
sc.view_settings.view_transform = 'Standard'
ctr = Vector((0, 0, .55))
CAMS = {}
for v, off in {'front': Vector((6, 0, 0)), 'back': Vector((-6, 0, 0)), 'side': Vector((0, -6, 0)), 'top': Vector((0, 0, 6))}.items():
    cam = bpy.data.cameras.new('c_' + v)
    cam.type = 'ORTHO'
    cam.ortho_scale = 1.5
    co = bpy.data.objects.new('c_' + v, cam)
    sc.collection.objects.link(co)
    co.location = ctr + off
    co.rotation_euler = (0, 0, math.pi / 2) if v == 'top' else (ctr - co.location).to_track_quat('-Z', 'Y').to_euler()
    CAMS[v] = co


def clear_model():
    for o in [o for o in bpy.data.objects if not o.name.startswith('c_')]:
        bpy.data.objects.remove(o)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)


def bbox(m):
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def resize_mask(a, s):
    h, w = a.shape
    nh, nw = max(1, int(round(h * s))), max(1, int(round(w * s)))
    yy = np.minimum(((np.arange(nh) + .5) / s).astype(int), h - 1)
    xx = np.minimum(((np.arange(nw) + .5) / s).astype(int), w - 1)
    return a[yy][:, xx]


def silhouettes():
    out = {}
    for v, co in CAMS.items():
        sc.camera = co
        sc.render.filepath = TMP
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(TMP, check_existing=False)
        a = np.array(img.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)[::-1, :, 3] > .5
        bpy.data.images.remove(img)
        out[v] = a
    return out


def evaluate(params, detail=False):
    clear_model()
    G.PARAMS[stage] = params
    b = G.new_builder(stage)
    G.STAGES[stage](b)
    mine = silhouettes()
    mb = bbox(mine['front'])
    s = (mb[3] - mb[1]) / REF['front'].shape[0]
    ious = {}
    for v in ('front', 'back', 'side', 'top'):
        m_r = resize_mask(REF[v].astype(np.uint8), s).astype(bool)
        mm = mine[v]
        b2 = bbox(mm)
        h, w = m_r.shape
        canvas = np.zeros((SIZE, SIZE), bool)
        cx = (b2[0] + b2[2]) // 2
        x0 = int(np.clip(cx - w // 2, 0, max(SIZE - w, 0)))
        y1 = b2[3] if v != 'top' else (b2[1] + b2[3]) // 2 + h // 2
        y0 = y1 - h
        ys0 = max(y0, 0)
        sh = min(h - (ys0 - y0), SIZE - ys0)
        sw = min(w, SIZE - x0)
        canvas[ys0:ys0 + sh, x0:x0 + sw] = m_r[ys0 - y0:ys0 - y0 + sh, :sw]
        ious[v] = float((canvas & mm).sum() / max((canvas | mm).sum(), 1))
    score = sum(ious.values()) / 4.0
    return (score, ious) if detail else score


cur = {k: G.PARAMS[stage].get(k, v[0]) for k, v in specs.items()}        # start from the stored fit if there is one
best, ious = evaluate(cur, True)
print('start', round(best, 4), {k: round(v, 3) for k, v in ious.items()}, flush=True)
steps = [.04, .02, .01][:PASSES]
for st_ in steps:
    for k, (d, lo, hi) in specs.items():
        stp = st_ * (3.0 if k == 'ys' else 1.0) * (1.0 if k != 'ys' else .5)
        for sgn in (1, -1):
            trial = dict(cur)
            trial[k] = float(np.clip(cur[k] + sgn * stp, lo, hi))
            if trial[k] == cur[k]:
                continue
            sc_ = evaluate(trial)
            if sc_ > best + 1e-4:
                best, cur = sc_, trial
                break
    print('step', st_, 'score', round(best, 4), flush=True)
    with open(outjson, 'w') as fh:
        json.dump(cur, fh, indent=1)
best, ious = evaluate(cur, True)
print('final', round(best, 4), {k: round(v, 3) for k, v in ious.items()}, flush=True)
print(json.dumps(cur))
