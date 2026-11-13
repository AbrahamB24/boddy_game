"""Phoenix line, measured from the turnaround sheet (every view).

Wing = leaf-shaped sail: an arm from the shoulder (up, out, back), a solid red field of covert rows,
and separate flame primaries rooted along the arm whose direction swings from straight down (at the body)
to the arm's own direction (at the tip). Tail = horizontal fan (stages 1-2) or seven hanging feathers (3).

    blender --background --python tool/blender/phoenix3.py -- --out docs/renders/monsters/phoenix3 [--stages 0,1,2] [--views q,front,side,back]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monsters_all as ma  # noqa: E402
import monsters_real as mr  # noqa: E402
import phoenix as ph  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

VIEWS = {'q': Vector((5.2, 4.0, 2.8)), 'front': Vector((6.0, 0.01, 1.8)), 'side': Vector((0.01, -6.0, 1.8)), 'back': Vector((-6.0, 0.01, 1.8))}
NY = Vector((0, 1, 0))


def sail_wing(b, sg, S, A, plen, D0, n_prim, cov_rows, cut=(.34, .62)):
    """A leaf-shaped wing. A = shoulder->apex for sg=+1 (x back, y out, z up)."""
    S = Vector(S)
    A = Vector((A[0], sg * A[1], A[2]))
    D0 = Vector((D0[0], sg * D0[1], D0[2])).normalized()
    Adir = A.normalized()
    tip = plen * .62                                          # the apex tongue continues the arm
    Lr = A.length - tip
    N = Adir.cross(D0).normalized()
    if N.dot(Vector((.4, sg * .8, .5))) < 0:
        N = -N
    b.chain([(S.x, S.y, S.z, .10), ((S + Adir * Lr * .55).x, (S + Adir * Lr * .55).y, (S + Adir * Lr * .55).z, .08),
             ((S + Adir * Lr).x, (S + Adir * Lr).y, (S + Adir * Lr).z, .05)], 'f1')

    def direction(u):
        t = u ** .85
        return (D0 * (1 - t) + Adir * t).normalized()

    def depth(u):                                             # feather length: long mid-wing, shorter at body and apex
        return plen * (.62 + .38 * math.sin(math.pi * (.06 + .88 * u)))

    for r in range(cov_rows):                                # solid red field, only the inner half of the depth
        cnt = n_prim * 2 - r * 2
        for i in range(cnt):
            u = (i + .5) / cnt
            root = S + Adir * (Lr * (.03 + .97 * u)) + N * (.016 * (r + 1))
            ln = depth(u) * (.50 - .13 * r)
            b.gfeather2(root, direction(u), ln, ln * .20, ('f1', 'f1b', 'f1b'), N, (.9, .95))
    n_prim = int(n_prim * 1.5)
    for i in range(n_prim):                                  # flame primaries, fully visible from both sides
        u = (i + .5) / n_prim
        root = S + Adir * (Lr * (.06 + .94 * u)) - N * .01
        ln = depth(u) * (1 + (.07 if i % 2 else 0))
        b.gfeather2(root, direction(u), ln, ln * .21, ('f1', 'f2', 'f3'), N, cut)
        if i % 2 == 0:
            b.gfeather2(root + N * .02, direction(min(1, u + .03)), ln * .78, ln * .20, ('f1', 'f2', 'f3'), N, cut)


def fan_tail(b, root, base, n, lat, length, width, N, drop=0.0):
    root = Vector(root)
    base = Vector(base).normalized()
    for i in range(n):
        u = (i - (n - 1) / 2) / ((n - 1) / 2 if n > 1 else 1)
        d = (base + Vector((0, u * lat, -abs(u) * drop))).normalized()
        ln = length * (1 - .22 * abs(u))
        b.gfeather2(root + Vector((0, u * .05, 0)), d, ln, width, ('f1', 'f2', 'f3'), N, (.30, .58))


def face(b, h, hr, k, brow):
    E = b.E
    ex, ez = h[0] + hr[0] * .80, h[2] - hr[2] * .02
    for sg in (-1, 1):
        E(ex, sg * hr[1] * .44, ez, .055 * k, .072 * k, .080 * k, 'dark')
        E(ex - .005, sg * hr[1] * .68, ez + .005, .040 * k, .062 * k, .070 * k, 'eyewhite')
        if brow:
            E(ex - .02, sg * hr[1] * .50, ez + .095 * k, .06 * k, .11 * k, .034 * k, 'brow', (sg * .25, 0, 0))
    bx = h[0] + hr[0] * .96
    b.L((bx - .05 * k, 0, ez - .02 * k), (bx + .15 * k, 0, ez - .12 * k), .105 * k, .03 * k, 'beak')
    b.E(bx + .02 * k, 0, ez - .08 * k, .10 * k, .105 * k, .075 * k, 'beak')


def phoenix(st):
    pal = dict(body=['#a72822', '#a62721', '#a02420'][st], body2=['#b43026', '#b83428', '#b43026'][st], head=['#ad2b24', '#ac2a23', '#a62722'][st],
               brow='#8a1c18', eyewhite='#f4ece0', beak='#d8a030', leg='#d09a28',
               f1='#a52620', f1b='#b4302a', f2='#ff7a1c', f3='#ffc83c',
               glow=('#ffc83c', '#ffb000', 1.0))

    def build(b):
        E, L = b.E, b.L
        if st == 0:                                              # stage 1 of the sheet
            k = 1.0
            c, rad, tilt = (0, 0, .60), (.28, .26, .46), .30
            h, hr = (.16, 0, .98), (.26, .25, .27)
            wing = dict(S=(-.02, .20, .82), A=(-.12, .83, .88), plen=.62, D0=(-.1, .35, -1), n=9, rows=2)
            crest = [(.10, .22), (.04, .30), (-.04, .36), (-.12, .32), (-.20, .24)]
            foot = (.15, .14)
        elif st == 1:                                            # stage 2 of the sheet
            k = 1.08
            c, rad, tilt = (0, 0, .62), (.29, .27, .44), .26
            h, hr = (.17, 0, 1.00), (.28, .26, .28)
            wing = dict(S=(-.02, .21, .82), A=(-.35, .90, .85), plen=.74, D0=(-.45, .25, -1), n=10, rows=2)
            crest = [(.12, .26), (.06, .34), (0, .42), (-.07, .38), (-.15, .30), (-.22, .24)]
            foot = (.16, .15)
        else:                                                    # stage 3 of the sheet
            k = 1.0
            c, rad, tilt = (0, 0, .84), (.25, .24, .52), .12
            h, hr = (.10, 0, 1.36), (.21, .20, .22)
            wing = dict(S=(-.02, .20, 1.08), A=(-.84, .84, .97), plen=.88, D0=(-.35, .15, -1), n=11, rows=3)
            crest = [(.06, .16), (0, .30), (-.06, .22)]
            foot = (.12, .10)
        E(*c, *rad, 'body', (0, tilt, 0))
        E(c[0] + .07, 0, c[2] - .02, rad[0] * .86, rad[1] * .86, rad[2] * .90, 'body2', (0, tilt, 0))
        E(*h, *hr, 'head')
        E(h[0] - .02, 0, h[2] + hr[2] * .15, hr[0] * .96, hr[1] * .96, hr[2] * .95, 'head')
        face(b, h, hr, k, True)
        # crest: a row of flame feathers along the midline, tallest at the back
        for i, (dx, ln) in enumerate(crest):
            b.gfeather2((h[0] + dx, 0, h[2] + hr[2] * .85), (-.30 - .25 * (i / len(crest)), 0, 1), ln, .062, ('f2', 'f2', 'f3'), NY, (.30, .60))
        if st == 2:
            for sg in (-1, 1):
                b.gfeather2((h[0] + .04, sg * .13, h[2] + hr[2] * .75), (-.2, sg * .3, 1), .20, .035, ('f2', 'f2', 'f3'), NY, (.25, .55))
        for (x, y, z) in ([(-.30, 0, h[2] + .50), (-.18, 0, h[2] + .60), (-.36, 0, h[2] + .36)] if st < 2 else [(-.30, 0, h[2] + .50), (-.2, 0, h[2] + .58), (-.34, 0, h[2] + .38)]):
            E(x, y, z, .028, .028, .028, 'f3')
        # wings
        for sg in (-1, 1):
            sail_wing(b, sg, (wing['S'][0], sg * wing['S'][1], wing['S'][2]), wing['A'], wing['plen'], wing['D0'], wing['n'], wing['rows'])
        # legs
        fz = .06 if st < 2 else .10
        for sg in (-1, 1):
            top = c[2] - .10                                   # the hip sits well inside the body, so the leg is attached
            E(.0, sg * foot[0], top, .11, .10, .14, 'body')    # feathered thigh
            L((.02, sg * foot[0], top), (.07, sg * foot[0], fz), .062, .05, 'leg')
            E(.07, sg * foot[0], fz, .07, .06, .05, 'leg')
            mr.bird_foot(b, (.07, sg * foot[0], fz), sg * foot[0], foot[1] + .08, 'leg')
        # tail
        if st < 2:
            fan_tail(b, (-.30, 0, .32), (-1, 0, -.10), 5 if st == 0 else 6, .55, .80 if st == 0 else .95, .085 if st == 0 else .09, NY, 0.03)
            if st == 1:
                for sg in (-1, 1):
                    b.gfeather2((-.10, sg * .18, .30), (-.2, sg * .6, -.8), .30, .05, ('f2', 'f2', 'f3'), NY, (.2, .5))
        else:
            fan_tail(b, (-.10, 0, .40), (-.36, 0, -1), 7, .36, 1.0, .095, NY, 0.05)
    return pal, build


def render_all(st, out, views, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    pal, build = phoenix(st)
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
        co.location = c + VIEWS[v]
        co.rotation_euler = (c - co.location).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.view_layer.update()
        inv = co.matrix_world.inverted()
        pts = [inv @ p for p in corners]
        w = max(p.x for p in pts) - min(p.x for p in pts)
        h = max(p.y for p in pts) - min(p.y for p in pts)
        cam.ortho_scale = ortho
        sc.camera = co
        K.render(os.path.join(out, 'phoenix_s%d_%s.png' % (st, v)))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--views', default='front,side,back,q')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--size', type=int, default=560)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    import traceback
    for st in [int(s) for s in a.stages.split(',')]:
        try:
            render_all(st, a.out, a.views.split(','), a.samples, a.size)
        except Exception:
            print('FAILED', st)
            traceback.print_exc()


if __name__ == '__main__':
    main()
