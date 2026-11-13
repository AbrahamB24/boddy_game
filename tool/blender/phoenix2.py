"""Phoenix line from the turnaround sheet: wings are thin sheets (front/back wide, side narrow) of
flame feathers fanned from the shoulder; slim tilted body, small round head, long tail streamers.

    blender --background --python tool/blender/phoenix2.py -- --out docs/renders/monsters/phoenix2 [--stages 0,1,2] [--views q,front,side,back]
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

FIRE = ma.FIRE
NX = Vector((1, 0, 0))
VIEWS = {'q': Vector((5.2, -4.0, 2.8)), 'front': Vector((6.0, 0.01, 1.8)), 'side': Vector((0.01, -6.0, 1.8)), 'back': Vector((-6.0, 0.01, 1.8))}


def plane_wing(b, sg, S, n, lmax, wr, rows=2, span=(22, 86), tilt=-.10, jag=0.0):
    S = Vector(S)
    b.chain([(S.x, S.y, S.z, .07), (S.x, S.y + sg * .26, S.z + .13, .05)], 'f1')
    for r in range(rows):
        m = n - 2 * r
        for i in range(m):
            u = (i + .5) / m
            phi = math.radians(span[0] + (span[1] - span[0]) * u)
            d = Vector((tilt, sg * math.sin(phi), math.cos(phi))).normalized()
            root = S + Vector((.016 * r, sg * .26 * u, .13 * u))
            ln = lmax * (.52 + .48 * math.sin(math.pi * (.06 + .84 * u))) * (1 - .34 * r) * (1 + jag * (i % 2))
            mats = ('f1', 'f2', 'f3') if r == 0 else ('f1', 'f1', 'f2')
            b.gfeather2(root, d, ln, ln * wr, mats, NX, (.30, .62))


def streamer(b, root, d, length, width, mats=('f1', 'f2', 'f3')):
    b.gfeather2(root, d, length, width, mats, Vector((0, 1, 0)), (.45, .75))


def phoenix(st):
    pal = dict(body=['#b8281e', '#b4261c', '#aa2018'][st], body2=['#c43224', '#c83626', '#c03020'][st], head=['#be2c20', '#ba2a1e', '#b0241a'][st],
               beak='#c89030', beak2='#a87424', leg='#d9a82a', f1=['#b02a22', '#ac2820', '#a82020'][st], f2='#ff5a06', f3='#ffa800',
               glow=('#ffd36b', '#ff7a14', 2.6), glow2=('#ff7a2e', '#e83c08', 2.2))

    def build(b):
        E, L = b.E, b.L
        tl = (0, [.75, .65, .55][st], 0)
        k = [1.0, 1.12, 1.25][st]
        E(0, 0, .52 * k, .25 * k, .22 * k, .38 * k, 'body', tl); E(.08 * k, 0, .48 * k, .19 * k, .18 * k, .30 * k, 'body2', tl)
        h, hr = (.27 * k, 0, .88 * k), (.25 * k, .23 * k, .23 * k)
        E(*h, *hr, 'head'); b.eyes2(h, hr, .052 * k, 42, 8, .015)
        L((.40 * k, 0, .84 * k), (.54 * k, 0, .79 * k), .05 * k, .014, 'beak'); L((.40 * k, 0, .79 * k), (.50 * k, 0, .77 * k), .036 * k, .01, 'beak2')
        # crest
        b.gfeather2((.16 * k, 0, 1.0 * k), (-.2, 0, 1), [.26, .34, .42][st], .04, ('f1', 'f2', 'f3'), Vector((0, 1, 0)), (.4, .7))
        if st >= 1:
            for i, y in enumerate((-.06, .06)):
                b.gfeather2((.14 * k, y, .98 * k), (-.45, y * 4, 1), .22 + .08 * st, .04, ('f2', 'f3', 'f3'), Vector((0, 1, 0)), (.2, .5))
        if st == 2:
            for i, y in enumerate((-.12, 0, .12)):
                b.gfeather2((.10 * k, y, .98 * k), (-.7, y * 3, .9), .34 - abs(y) * .6, .045, ('f2', 'f3', 'f3'), Vector((0, 1, 0)), (.2, .5))
        # wings: thin sheets fanned from the shoulder
        S = (0, .14 * k, .74 * k)
        for sg in (-1, 1):
            plane_wing(b, sg, (S[0], sg * S[1], S[2]), [8, 9, 11][st], [.90, 1.15, 1.50][st], [.12, .12, .105][st], 2 if st < 2 else 3,
                       (10, 80) if st < 2 else (8, 84), -.10, 0 if st < 2 else .10)
        # legs
        for sg in (-1, 1):
            E(.0, sg * .09 * k, .30 * k, .07, .06, .10, 'body')
            L((.02, sg * .09 * k, .26 * k), (.05, sg * .09 * k, .06), .026, .022, 'leg')
            mr.bird_foot(b, (.05, sg * .09 * k, .06), sg * .09 * k, .12 * k, 'leg')
        # tail
        if st == 0:
            streamer(b, (-.14, 0, .30), (-.9, 0, -.4), .7, .05)
            for y in (-.07, .07):
                streamer(b, (-.14, y, .28), (-.5, y * 3, -.8), .24, .045, ('f2', 'f2', 'f3'))
        elif st == 1:
            streamer(b, (-.16, 0, .32 * k), (-.9, 0, -.4), .95, .06)
            for y in (-.10, .10):
                streamer(b, (-.16, y, .30 * k), (-.7, y * 3, -.6), .55, .055, ('f1', 'f2', 'f3'))
            for y in (-.05, .05):
                streamer(b, (-.16, y, .28 * k), (-.3, y * 3, -.9), .26, .045, ('f2', 'f3', 'f3'))
        else:
            for i in range(7):
                y = (i - 3) * .075
                streamer(b, (-.18, y * .5, .38 * k), (-.35, y * 1.4, -1), 1.45 - abs(i - 3) * .14, .09)
            for y in (-.12, .12):
                streamer(b, (-.2, y, .40 * k), (-.9, y * 2, -.5), .75, .06, ('f1', 'f2', 'f3'))
    return pal, build


def render_all(st, out, views, samples, size):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    pal, build = phoenix(st)
    b = ph.P(pal, 1.0)
    build(b)
    ob = tw.voxelise(b.objs)
    K.lighting(sky=0.85, sun=5.5)
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
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = 0.3
    ortho = None
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
        cam.ortho_scale = max(w, h) * 1.12 if ortho is None else ortho
        ortho = cam.ortho_scale if ortho is None else ortho
        sc.camera = co
        K.render(os.path.join(out, 'phoenix_s%d_%s.png' % (st, v)))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--views', default='q,front,side,back')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=36)
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
