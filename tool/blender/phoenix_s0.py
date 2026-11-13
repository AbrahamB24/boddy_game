"""Phoenix stage 0 (round chick with a cream belly), from the new reference sheet.

    blender --background --python tool/blender/phoenix_s0.py -- --out docs/renders/monsters/phoenix3
Writes phoenix_s3_<view>.png style names as phoenix_s0_<view>.png (the old s0..s2 become s1..s3 on the sheet).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import phoenix as ph  # noqa: E402
import phoenix3 as p3  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

NY = Vector((0, 1, 0))


def build(b):
    E, L = b.E, b.L
    # snowman body: round body, round head, a visible waist between them
    E(0, 0, .36, .31, .29, .30, 'body'); E(.20, 0, .32, .15, .17, .20, 'belly')
    h, hr = (.04, 0, .76), (.28, .27, .27)
    E(*h, *hr, 'head')
    # eyes: same recipe as the phoenix stages 1 and 2 (face() in phoenix3.py):
    # dark eye, white patch on the outer side, darker brow ridge above
    ex, ez = h[0] + hr[0] * .80, h[2] - hr[2] * .02
    for sg in (-1, 1):
        E(ex, sg * hr[1] * .44, ez, .055, .072, .080, 'dark')
        E(ex - .005, sg * hr[1] * .68, ez + .005, .040, .062, .070, 'eyewhite')
        E(ex - .02, sg * hr[1] * .50, ez + .095, .06, .11, .034, 'brow', (sg * .25, 0, 0))
    # beak: small wedge
    L((h[0] + .24, 0, h[2] - .05), (h[0] + .40, 0, h[2] - .09), .06, .016, 'beak')
    E(h[0] + .27, 0, h[2] - .07, .06, .06, .04, 'beak')
    # crest: three flame prongs and sparks
    for dx, dy, ln, tilt in ((0, 0, .26, -.2), (-.06, -.07, .18, -.35), (-.06, .07, .18, -.35)):
        base = Vector((h[0] + dx, dy, h[2] + hr[2] * .86)); tipv = base + Vector((tilt * ln, dy * ln, ln))
        b.L(base, base + (tipv - base) * .6, .06, .045, 'f2'); b.L(base + (tipv - base) * .6, tipv, .045, .01, 'f3')
    for (x, y, z) in ((-.02, .10, 1.28), (.10, -.06, 1.36), (-.12, -.08, 1.20)):
        E(x, y, z, .025, .025, .025, 'f3')
    # folded wings with a darker feather tip
    for sg in (-1, 1):
        E(-.04, sg * .27, .46, .17, .07, .20, 'wing', (sg * .25, .25, 0))
        for i, (dx, dz) in enumerate(((0, 0), (-.04, -.05), (-.08, -.10))):
            b.feather((.06 + dx, sg * .30, .56 + dz), (-.75, 0, -.65), .38 - i * .04, .075, 'wing2', (0, sg, 0))
    # tail: short flame fan, red to yellow
    for i, y in enumerate((-.08, 0, .08)):
        b.gfeather2((-.24, y * .6, .30), (-.85, y * 2, .22), .34 - abs(y) * .5, .06, ('f1', 'f2', 'f3'), NY, (.30, .58))
    # feet
    for sg in (-1, 1):
        L((.02, sg * .12, .10), (.06, sg * .12, .05), .035, .03, 'leg')
        for ang in (-.45, 0, .45):
            tip = (.06 + math.cos(ang) * .12, sg * .12 + math.sin(ang) * .10, .03)
            L((.06, sg * .12, .045), tip, .026, .02, 'leg', seg=6)


def render_all(out, views, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    pal = dict(brow='#8a2a1e', eyewhite='#f4ece0', body='#bd3f2c', head='#c24430', belly='#e6c28c', wing='#a8332a', wing2='#982c24', beak='#f0b23c', leg='#e8a838',
               f1='#a8332a', f2='#ff8a20', f3='#ffd040')
    b = ph.P(pal, 1.0)
    build(b)
    ob = tw.voxelise(b.objs)
    K.lighting(sky=0.9, sun=4.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))
    sc = bpy.context.scene
    corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    c = sum(corners, Vector()) / 8
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.exposure = 0.0
    ortho = 2.05 * max((p - c).length for p in corners)
    for v in views:
        cam = bpy.data.cameras.new('cam_' + v)
        cam.type = 'ORTHO'
        co = bpy.data.objects.new('cam_' + v, cam)
        sc.collection.objects.link(co)
        co.location = c + p3.VIEWS[v]
        co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
        cam.ortho_scale = ortho * .80
        sc.camera = co
        K.render(os.path.join(out, 'phoenix_s0_%s.png' % v))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--views', default='front,side,back,q')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--size', type=int, default=560)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    render_all(a.out, a.views.split(','), a.samples, a.size)


if __name__ == '__main__':
    main()
