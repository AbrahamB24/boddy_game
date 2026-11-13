"""Cinderchick -> Flamewing -> Solarphoenix, modelled on the reference photo (flame-feather fan wings).

    blender --background --python tool/blender/phoenix.py -- --out docs/renders/monsters/phoenix [--stages 0,1,2]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monsters_all as ma  # noqa: E402
import monsters_real as mr  # noqa: E402
import monsters_s0 as m0  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

FIRE = ma.FIRE


class P(m0.Q):
    def gfeather2(s, p, d, length, width, mats, norm, cut=(.30, .62)):
        """A pointed flame tongue shaded root -> orange -> yellow tip."""
        d = Vector(d).normalized()
        p = Vector(p)
        thick = max(.014, length * .035)
        eul = mr.basis_euler(d, norm)
        for k, (t0, t1, m) in enumerate(((0, cut[0] + .08, mats[0]), (cut[0], cut[1] + .08, mats[1]), (cut[1], 1.0, mats[2]))):
            tc, half = (t0 + t1) / 2, (t1 - t0) / 2
            wf = math.sqrt(max(.04, 1 - ((tc - .5) / .5) ** 2)) * (.5 if k == 2 else 1.0)
            c = p + d * length * tc
            s.E(c.x, c.y, c.z, length * half, width * wf, thick, m, eul)
    def eye_ring(s, c, r, er, az=44, el=8, hl=.017):
        for sg in (-1, 1):
            a, e = math.radians(az), math.radians(el)
            px = c[0] + r[0] * math.cos(e) * math.cos(a) * .95
            py = c[1] + sg * r[1] * math.cos(e) * math.sin(a) * .95
            pz = c[2] + r[2] * math.sin(e) * .95
            s.E(px - er * .2, py, pz, er * .85, er * 1.12, er * 1.2, 'eyering')
            s.E(px, py, pz, er * .85, er * .95, er * 1.02, 'dark')
            s.E(px + er * .74, py - sg * er * .2, pz + er * .6, hl, hl, hl, 'white')


def fan_wing(b, S, W, da, db, n, lmax, wr, mats_list):
    S, W = Vector(S), Vector(W)
    da, db = Vector(da).normalized(), Vector(db).normalized()
    N = da.cross(db).normalized()
    if N.dot(Vector((5.2, -4.0, 2.8))) < 0:
        N = -N
    b.chain([(S.x, S.y, S.z, .075), (W.x, W.y, W.z, .055)], 'f1')
    for r, mats in enumerate(mats_list):
        m = n - r * 2
        for i in range(m):
            u = (i + .5) / m
            d = (da * (1 - u) + db * u).normalized()
            pos = S + (W - S) * u + N * (.016 * r)
            ln = lmax * (.62 + .38 * math.sin(math.pi * (.12 + .76 * u))) * (1 - .30 * r)
            b.gfeather2(pos, d, ln, ln * wr, mats, N)


def phoenix(st):
    pal = dict(body=['#c42a1c', '#c02a1a', '#b02018'][st], body2=['#d8402a', '#e8602a', '#ffb62a'][st],
               head=['#cc3020', '#c82e1c', '#b8261a'][st], beak='#f4b434', beak2='#dc9a28', leg=['#f0a830', '#f0a830', '#f4bc3a'][st],
               f1='#c8281a', f2='#ff7a14', f3='#ffc83a', f4='#fff0a0', eyering='#f2dcc0', **FIRE)

    def build(b):
        E, L = b.E, b.L
        if st == 0:
            tl = (0, .55, 0)
            E(0, 0, .52, .27, .25, .37, 'body', tl); E(.11, 0, .46, .20, .20, .28, 'body2', tl)
            h, hr = (.32, 0, .80), (.28, .26, .25)
            E(*h, *hr, 'head'); b.eye_ring(h, hr, .075, 44, 8)
            L((.50, 0, .80), (.78, 0, .68), .10, .02, 'beak'); L((.50, 0, .72), (.68, 0, .66), .07, .016, 'beak2')
            for i, y in enumerate((-.09, 0, .09)):
                b.gfeather2((.22, y, 1.02), (-.35, y * 3, 1), .34 + .07 * (i == 1), .06, ('f1', 'f2', 'f3'), (0, 1, 0))
            fan_wing(b, (0, -.20, .70), (-.06, -.30, .84), (-.35, -.25, .9), (-.95, -.3, .2), 6, .66, .10, [('f1', 'f2', 'f3'), ('f1', 'f1', 'f2')])
            fan_wing(b, (0, .20, .68), (-.08, .32, .80), (-.3, .45, .85), (-.9, .5, -.1), 6, .66, .10, [('f1', 'f2', 'f3'), ('f1', 'f1', 'f2')])
            for sg in (-1, 1):
                E(.02, sg * .12, .26, .10, .09, .13, 'body')
                L((.04, sg * .11, .24), (.08, sg * .11, .07), .036, .03, 'leg')
                mr.bird_foot(b, (.08, sg * .11, .07), sg * .11, .17)
            for i in range(4):
                y = (i - 1.5) * .13
                b.gfeather2((-.18, 0, .24), (-.7, y, -.55), .34 - abs(i - 1.5) * .04, .065, ('f1', 'f2', 'f3'), (0, 1, 0))
            for (x, y, z) in ((-.5, .8, 1.3), (.1, -.7, 1.3), (.5, .6, 1.5), (-.3, .4, .5)):
                E(x, y, z, .035, .035, .035, 'glow')
        elif st == 1:
            tl = (0, .40, 0)
            E(0, 0, .64, .26, .24, .42, 'body', tl); E(.10, 0, .60, .19, .19, .33, 'body2', tl)
            b.chain([(.10, 0, 1.00, .14), (.15, 0, 1.12, .12)], 'body')
            h, hr = (.24, 0, 1.24), (.25, .22, .21)
            E(*h, *hr, 'head'); b.eye_ring(h, hr, .068, 46, 8)
            b.E2(.32, .13, 1.33, .08, .04, .03, 'head')
            b.chain([(.42, 0, 1.24, .08), (.56, 0, 1.22, .06), (.64, 0, 1.16, .045), (.67, 0, 1.08, .025)], 'beak')
            b.chain([(.42, 0, 1.18, .055), (.54, 0, 1.16, .04), (.60, 0, 1.14, .03)], 'beak2')
            for i, y in enumerate((-.12, -.04, .04, .12)):
                b.gfeather2((.14, y, 1.42), (-.45, y * 3, 1), .40 + .08 * (i in (1, 2)), .055, ('f1', 'f2', 'f3'), (0, 1, 0))
            fan_wing(b, (0, -.22, .90), (-.08, -.34, 1.02), (-.30, -.30, .95), (-.95, -.45, .05), 8, .90, .10, [('f1', 'f2', 'f3'), ('f1', 'f1', 'f2')])
            fan_wing(b, (0, .22, .88), (-.10, .36, .98), (-.25, .55, .9), (-.95, .55, -.1), 8, .90, .10, [('f1', 'f2', 'f3'), ('f1', 'f1', 'f2')])
            for sg in (-1, 1):
                E(.0, sg * .14, .46, .13, .11, .20, 'body')
                L((.02, sg * .13, .36), (.06, sg * .13, .08), .04, .032, 'leg')
                mr.bird_foot(b, (.06, sg * .13, .07), sg * .13, .19)
            for i in range(5):
                y = (i - 2) * .12
                b.gfeather2((-.20, 0, .40), (-.75, y, -.40), .62 - abs(i - 2) * .06, .075, ('f1', 'f2', 'f3'), (0, 1, 0))
            for (x, y, z) in ((-.6, .9, 1.5), (.1, -.9, 1.5), (.5, .7, 1.7), (-.3, .5, .6), (.2, -.6, .5)):
                E(x, y, z, .04, .04, .04, 'glow')
        else:
            tl = (0, .22, 0)
            E(0, 0, .80, .27, .25, .46, 'body', tl); E(.10, 0, .76, .21, .22, .38, 'body2', tl)
            E(.16, 0, .84, .10, .12, .14, 'glow')
            b.chain([(.08, 0, 1.12, .16), (.12, 0, 1.30, .13), (.16, 0, 1.46, .115)], 'body')
            h, hr = (.22, 0, 1.60), (.24, .21, .20)
            E(*h, *hr, 'head'); b.eye_ring(h, hr, .062, 46, 8)
            b.E2(.30, .13, 1.69, .09, .045, .03, 'head')
            b.chain([(.38, 0, 1.60, .08), (.52, 0, 1.58, .065), (.62, 0, 1.52, .048), (.65, 0, 1.43, .026)], 'beak')
            b.chain([(.38, 0, 1.54, .055), (.50, 0, 1.52, .042), (.58, 0, 1.50, .03)], 'beak2')
            for i in range(6):
                y = (i - 2.5) * .085
                b.gfeather2((.10, y, 1.76), (-.40 - abs(y) * 1.5, y * 4, 1), .55 - abs(i - 2.5) * .06, .06, ('f2', 'f3', 'f4'), (0, 1, 0))
            fan_wing(b, (0, -.24, 1.02), (-.10, -.40, 1.14), (-.15, -.60, .85), (-1.0, -.55, -.05), 10, 1.18, .09, [('f1', 'f2', 'f3'), ('f1', 'f1', 'f2')])
            fan_wing(b, (0, .24, 1.00), (-.12, .42, 1.10), (-.12, .65, .8), (-1.0, .6, -.1), 10, 1.18, .09, [('f1', 'f2', 'f3'), ('f1', 'f1', 'f2')])
            for sg in (-1, 1):
                E(.0, sg * .15, .50, .15, .12, .24, 'body')
                L((.02, sg * .14, .38), (.07, sg * .14, .09), .045, .033, 'leg')
                mr.bird_foot(b, (.07, sg * .14, .08), sg * .14, .21)
            for i in range(5):
                y = (i - 2) * .13
                b.gfeather2((-.22, 0, .56), (-.8, y, -.32), 1.25 - abs(i - 2) * .13, .10, ('f1', 'f2', 'f3'), (0, 1, 0))
            for (x, y, z) in ((.2, .9, 1.9), (-.5, -.9, 1.9), (.1, 1.3, 1.2), (-.6, .6, 2.1), (.6, -.8, 1.6), (-.9, 0, 1.4)):
                E(x, y, z, .045, .045, .045, 'glow')
    return pal, build


def build_stage(st):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    pal, build = phoenix(st)
    b = P(pal, 1.0)
    build(b)
    return tw.voxelise(b.objs)


def render(st, out, samples, size):
    ob = build_stage(st)
    K.lighting(sky=0.85, sun=5.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    c = sum(corners, Vector()) / 8
    co.location = c + ma.CAM_OFF
    co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.view_layer.update()
    inv = co.matrix_world.inverted()
    pts = [inv @ p for p in corners]
    w = max(p.x for p in pts) - min(p.x for p in pts)
    h = max(p.y for p in pts) - min(p.y for p in pts)
    cam.ortho_scale = max(w, h) * 1.12
    sc.camera = co
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = 0.3
    K.render(os.path.join(out, 'cinderchick_s%d.png' % st))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=40)
    ap.add_argument('--size', type=int, default=640)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    import traceback
    for st in [int(s) for s in a.stages.split(',')]:
        try:
            render(st, a.out, a.samples, a.size)
        except Exception:
            print('FAILED', st)
            traceback.print_exc()


if __name__ == '__main__':
    main()
