"""Build, voxelise, render and ship the map's scenery in the BUILDINGS' own
pipeline (user 2026-11-05: "es soll so wirken, als gäbe es keinen Unterschied
zwischen Karte und Gebäude"): smooth model from the same kits, the union
voxeliser at fw_kit.VOX, the same sun, sky, AgX and render scale, then shipped
at the same density (make_building's SHIP_DENSITY). So a tree, a bush or a
flower patch on the map IS the one next to a house.

    blender --background --python tool/blender/make_prop.py -- <name|all> \
        [--samples 96] [--out DIR]

Each sprite is cropped to what it covers and centred on its FOOT (the
origin), because terrain_layer.dart anchors a prop's picture bottom-centre on
its grid point. Writes assets/images/terrain/prop_<name>.webp, unless --out.

The app draws a prop picture at  image width / PROP_PX  canvas pixels
(terrain_layer.dart `_kPropPx` — the same number as here), never rescaled:
every instance of a sprite has the same block size as the buildings.
"""
import argparse
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import camp_kit as C  # noqa: E402
import fw_kit as F  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
from pro_kit import G, cyl, ellipsoid, plain  # noqa: E402

RENDER_SCALE = 5
SHIP_DENSITY = 960 / 1227
PROP_PX = RENDER_SCALE * SHIP_DENSITY         # image px per canvas px (3.912)
OUT_DIR = os.path.join(ROOT, 'assets', 'images', 'terrain')


# ── the models (authored in tiles, yard at z = G) ───────────
def _stone(M, seed, parts, mat='rock'):
    """A rock: overlapping flattened ellipsoids, each tipped a little."""
    r = random.Random(seed)
    for (x, y, rx, ry, rz) in parts:
        ellipsoid(x, y, G + rz * 0.55, rx, ry, rz, M[mat], seg=12, rings=9,
                  tilt=Euler((r.uniform(-.25, .25), r.uniform(-.25, .25),
                              r.uniform(0, 3)), 'XYZ'))


def stone_a(M): _stone(M, 1, [(0, 0, .15, .12, .10)])
def stone_b(M): _stone(M, 2, [(0, 0, .26, .20, .17), (.2, .06, .12, .1, .09)])
def stone_c(M): _stone(M, 3, [(0, 0, .40, .30, .21), (.28, .16, .14, .11, .1)])
def stone_d(M): _stone(M, 4, [(0, 0, .30, .27, .30), (-.22, .1, .15, .13, .13)])
def stone_e(M): _stone(M, 5, [(0, 0, .55, .42, .34), (.38, .12, .24, .2, .16),
                              (-.3, .22, .18, .15, .12)])
def stone_f(M): _stone(M, 6, [(-.12, 0, .1, .08, .06), (.05, .08, .08, .07, .05),
                              (.14, -.05, .09, .08, .06), (0, -.1, .07, .06, .05)])


def conifer_s(M): C.fir(M, 0, 0, 2.2, 'pine')
def conifer_m(M): C.fir(M, 0, 0, 3.0, 'pine2')
def conifer_l(M): C.fir(M, 0, 0, 3.8, 'pine')
def broadleaf_s(M): C.leafy(M, 0, 0, 1.8, 11)
def broadleaf_m(M): C.leafy(M, 0, 0, 2.4, 12)
def broadleaf_l(M): C.leafy(M, 0, 0, 3.0, 13)


def bush_a(M): F.bush(M, 0, 0, 0.17, 1)
def bush_b(M): F.bush(M, 0, 0, 0.24, 2, ['fl_white'])
def bush_c(M): F.bush(M, 0, 0, 0.21, 3, ['fl_pink', 'fl_white'])
def bush_d(M): F.bush(M, 0, 0, 0.3, 4, ['fl_yel'])


def flowers_a(M): F.flower_patch(M, 0, 0, 9, ['fl_yel', 'fl_red'], 1, .2, .14)
def flowers_b(M): F.flower_patch(M, 0, 0, 11, ['fl_white', 'fl_pink'], 2, .24, .16)
def flowers_c(M): F.flower_patch(M, 0, 0, 9, ['fl_blue', 'fl_white'], 3, .2, .15)
def flowers_d(M): F.flower_patch(M, 0, 0, 14, ['fl_red', 'fl_yel', 'fl_pink',
                                                'fl_blue', 'fl_white'], 4, .3, .2)


def _drift(M, x, y, length, r, yaw, seed):
    rnd = random.Random(seed)
    p0 = Vector((x - math.cos(yaw) * length / 2, y - math.sin(yaw) * length / 2,
                 G + r))
    p1 = Vector((x + math.cos(yaw) * length / 2, y + math.sin(yaw) * length / 2,
                 G + r + rnd.uniform(0, .02)))
    C.log(M, p0, p1, r, 'drift')


def driftwood_a(M):
    _drift(M, 0, 0, .55, .028, .3, 1)
    _drift(M, .1, .08, .26, .018, 1.2, 2)


def driftwood_b(M):
    _drift(M, 0, 0, .8, .035, -.2, 3)


def shell_a(M):
    ellipsoid(0, 0, G + .012, .028, .022, .014, M['shell'], seg=10, rings=7)
    ellipsoid(.05, .03, G + .01, .02, .016, .01, M['shell2'], seg=10, rings=7)


def shell_b(M):
    ellipsoid(0, 0, G + .014, .034, .026, .016, M['shell2'], seg=10, rings=7)


def tuft(M):
    """Tall grass: a fan of leaning blades."""
    r = random.Random(5)
    for i in range(16):
        a = r.uniform(0, 6.28)
        d = r.uniform(0, .05)
        h = r.uniform(.07, .16)
        lean = r.uniform(.2, .6)
        x, y = math.cos(a) * d, math.sin(a) * d
        b = cyl(x, y, G, .008, .0015, h, M['blade2' if i % 2 else 'blade'],
                seg=4, smooth=False)
        b.rotation_euler = (math.sin(a) * lean, -math.cos(a) * lean, 0)
        b.location = (x, y, G)


def fern(M):
    r = random.Random(6)
    for i in range(9):
        a = i * 0.7 + r.uniform(-.2, .2)
        L = r.uniform(.1, .17)
        for k in range(3):
            ellipsoid(math.cos(a) * (.03 + k * L / 3.2),
                      math.sin(a) * (.03 + k * L / 3.2),
                      G + .02 + k * .018 - (k * k) * .003, .02, .012, .004,
                      M['leaf'], seg=8, rings=5)


def stump(M): C.stump(M, 0, 0, .075, .09)


def log_a(M):
    C.log(M, Vector((-.22, 0, G + .05)), Vector((.22, .04, G + .05)), .05, 'bark')


def reeds(M):
    r = random.Random(7)
    for i in range(11):
        x, y = r.uniform(-.08, .08), r.uniform(-.06, .06)
        h = r.uniform(.2, .34)
        cyl(x, y, G, .006, .003, h, M['stem'], seg=5, smooth=False)
        if i % 3 == 0:
            cyl(x, y, G + h - .045, .011, .011, .045, M['cattail'], seg=6)


PROPS = {n: f for n, f in list(globals().items())
         if callable(f) and n.split('_')[0] in (
             'stone', 'conifer', 'broadleaf', 'bush', 'flowers', 'driftwood',
             'shell', 'tuft', 'fern', 'stump', 'log', 'reeds')
         and getattr(f, '__module__', '') == __name__}


def materials():
    M = C.mats()
    M['drift'] = plain('drift', '#b3a487', rough=0.9, bump=0.5, bump_scale=70,
                       vary=0.12, speck='#8e8068')
    M['shell'] = plain('shell', '#f0dcc6', rough=0.5, bump=0.1)
    M['shell2'] = plain('shell2', '#e2b99c', rough=0.5, bump=0.1)
    M['cattail'] = plain('cattail', '#5a3a22', rough=0.8, bump=0.2)
    return M


# ── the pipeline ────────────────────────────────────────────
def render_one(name, samples, out_dir, funcs=None, prefix='prop', mats=None):
    import voxelizer
    rb.clear()
    K._mats.clear()
    F.reset_anims()
    M = (mats or materials)()
    (funcs or PROPS)[name](M)
    for o in list(bpy.data.objects):
        if o.parent is None:
            o.location.z -= G
    voxelizer.voxelize(F.VOX, name + '_voxel',
                       objs=[o for o in bpy.data.objects if o.type == 'MESH'])
    K.lighting()
    K.setup_render(samples, RENDER_SCALE, 0.1, 0.1, headroom=0.3)
    raw = os.path.join(HERE, '_out', f'{prefix}_{name}.png')
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    K.render(raw)

    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    u, v, _ = world_to_camera_view(sc, sc.camera, Vector((0, 0, 0)))
    iw, ih = sc.render.resolution_x, sc.render.resolution_y
    foot_x = u * iw

    img = bpy.data.images.load(raw)
    img.colorspace_settings.name = 'Non-Color'
    img.alpha_mode = 'STRAIGHT'
    a = np.array(img.pixels[:], dtype=np.float32).reshape(ih, iw, 4)
    ys, xs = np.where(a[..., 3] > 0.02)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    half = int(math.ceil(max(foot_x - x0, x1 - foot_x))) + 1
    cx = int(round(foot_x))
    w = 2 * half
    crop = np.zeros((y1 - y0, w, 4), dtype=np.float32)
    lo = cx - half
    sx0, sx1 = max(lo, 0), min(lo + w, iw)
    crop[:, sx0 - lo:sx1 - lo] = a[y0:y1, sx0:sx1]
    tmp = bpy.data.images.new('crop', w, y1 - y0, alpha=True)
    tmp.colorspace_settings.name = 'Non-Color'
    tmp.alpha_mode = 'STRAIGHT'
    tmp.pixels = crop.ravel().tolist()
    nw = max(2, round(w * SHIP_DENSITY))
    nw += nw % 2
    tmp.scale(nw, max(1, round((y1 - y0) * nw / w)))
    st = sc.render.image_settings
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    st.file_format = 'WEBP'
    st.color_mode = 'RGBA'
    st.quality = 90
    dst = os.path.join(out_dir, f'{prefix}_{name}.webp')
    os.makedirs(out_dir, exist_ok=True)
    tmp.save_render(dst, scene=sc)
    print('PROP', name, f'{tmp.size[0]}x{tmp.size[1]}', os.path.getsize(dst))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('what')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--out', default=OUT_DIR)
    args = ap.parse_args(argv)
    names = list(PROPS) if args.what == 'all' else args.what.split(',')
    for n in names:
        render_one(n, args.samples, args.out)


if __name__ == '__main__':
    main()
