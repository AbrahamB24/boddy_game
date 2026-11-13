"""Stage 0, modelled by direct comparison with the reference photos (voxel size matched to the photos).

    blender --background --python tool/blender/monsters_s0.py -- --only cinderchick --out docs/renders/monsters/s0
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monsters_all as ma  # noqa: E402
import monsters_detail as md  # noqa: E402
import monsters_real as mr  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

FIRE, ICE = ma.FIRE, ma.ICE
blossom, antler, dots = md.blossom, md.antler, md.dots


class Q(mr.R):
    def gfeather(s, p, d, length, width, mats, norm=None, thick=None):
        """A feather that shades along its length (root colour, mid colour, tip colour)."""
        s.feather(p, d, length, width, mats[0], norm, thick)
        d = Vector(d).normalized()
        p = Vector(p)
        thick = thick or max(.012, length * .03)
        eul = mr.basis_euler(d, norm if norm is not None else Vector((0, 0, 1)))
        for t0, t1, m in ((.40, .72, mats[1]), (.66, 1.0, mats[2])):
            tc, half = (t0 + t1) / 2, (t1 - t0) / 2
            wf = math.sqrt(max(.05, 1 - ((tc - .46) / .46) ** 2)) if tc < .9 else .5
            c = p + d * length * tc
            s.E(c.x, c.y, c.z, length * half, width * wf * 1.03, thick * 1.2, m, eul)


def flame_wing(b, path, T, flen, n):
    P = [Vector(p) for p in path]
    T = Vector(T).normalized()
    A = P[3] - P[0]
    N = A.cross(T)
    if N.x < 0:
        N = -N
    Hd = (P[3] - P[2]).normalized()
    b.chain([(p.x, p.y, p.z, flen * .085) for p in P[:3]] + [(P[3].x, P[3].y, P[3].z, flen * .05)], 'body')
    for i, pos in enumerate(mr.samples(P[:3], max(4, n // 2))):
        b.gfeather(pos + N * .012, T, flen * .55, flen * .12, ('f1', 'f1', 'f2'), N)
    for i, pos in enumerate(mr.samples(P, n)):
        u = (i + .5) / n
        d = (T + Hd * .9 * u).normalized()
        ln = flen * (.62 + .5 * u)
        b.gfeather(pos - N * .01, d, ln, ln * .15, ('f1', 'f2', 'f3'), N)


def build_stage(name, st):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    pal, build = SPECIES[name]()
    b = Q(pal, 1.0)
    build(b)
    return tw.voxelise(b.objs)


# ───────────── Cinderchick: tilted songbird body, big beak, broad flame wings ─────────────
def flame_wing(b, path, T, flen, n):                       # redefined: broader, denser feathers
    P = [Vector(p) for p in path]
    T = Vector(T).normalized()
    A = P[3] - P[0]
    N = A.cross(T)
    if N.x < 0:
        N = -N
    Hd = (P[3] - P[2]).normalized()
    b.chain([(p.x, p.y, p.z, flen * .10) for p in P[:3]] + [(P[3].x, P[3].y, P[3].z, flen * .06)], 'f1')
    for pos in mr.samples(P[:3], n):
        b.gfeather(pos + N * .014, T, flen * .62, flen * .20, ('f1', 'f2', 'f2'), N)
    for i, pos in enumerate(mr.samples(P, n + 2)):
        u = (i + .5) / (n + 2)
        d = (T + Hd * .9 * u).normalized()
        ln = flen * (.70 + .45 * u)
        b.gfeather(pos - N * .01, d, ln, ln * .22, ('f1', 'f2', 'f3'), N)


def cinderchick():
    pal = dict(body='#cf3222', body2='#dc4128', head='#d63a26', beak='#f4b434', beak2='#dc9a28', leg='#f0a830',
               f1='#d83a1e', f2='#ff8a1c', f3='#ffd23a', **FIRE)

    def build(b):
        E, L = b.E, b.L
        tl = (0, .55, 0)
        E(0, 0, .52, .27, .25, .37, 'body', tl); E(.11, 0, .46, .20, .20, .28, 'body2', tl)
        h, hr = (.32, 0, .80), (.28, .26, .25)
        E(*h, *hr, 'head'); b.eyes2(h, hr, .09, 44, 8)
        L((.50, 0, .80), (.78, 0, .68), .10, .02, 'beak'); L((.50, 0, .72), (.68, 0, .66), .07, .016, 'beak2')
        for i, y in enumerate((-.09, 0, .09)):
            b.gfeather((.22, y, 1.02), (-.35, y * 3, 1), .34 + .07 * (i == 1), .06, ('f1', 'f2', 'f3'), (0, 1, 0))
        flame_wing(b, [(0, -.20, .68), (-.06, -.30, .86), (-.12, -.38, 1.04), (-.20, -.44, 1.22)], (-.95, 0, -.15), .50, 8)
        flame_wing(b, [(0, .20, .66), (-.10, .36, .74), (-.26, .52, .80), (-.44, .66, .84)], (.15, .25, .95), .50, 8)
        for sg in (-1, 1):
            E(.02, sg * .12, .26, .10, .09, .13, 'body')
            L((.04, sg * .11, .24), (.08, sg * .11, .07), .036, .03, 'leg')
            mr.bird_foot(b, (.08, sg * .11, .07), sg * .11, .17)
        for i in range(4):
            y = (i - 1.5) * .13
            b.gfeather((-.18, 0, .24), (-.7, y, -.55), .34 - abs(i - 1.5) * .04, .065, ('f1', 'f2', 'f3'), (0, 1, 0))
        for (x, y, z) in ((-.5, .8, 1.3), (.1, -.7, 1.3), (.5, .6, 1.5), (-.3, .4, .5)):
            E(x, y, z, .035, .035, .035, 'glow')
    return pal, build


# ───────────── Icepaw: low chunky cub, thick legs, big crystal beds at the front paws ─────────────
def icepaw():
    pal = dict(body='#b8703c', body2='#c27c46', belly='#c88a54', paw='#8c5430', muzzle='#dcae78', inner='#a8602e',
               plate='#8cc4ee', plate2='#cfe8fa', **ICE)

    def build(b):
        E, L = b.E, b.L
        z, r = .38, (.34, .30, .27)
        E(0, 0, z, *r, 'body'); E(.12, 0, z - .06, .24, .24, .22, 'belly')
        h, hr = (.33, 0, .66), (.37, .35, .32)
        E(*h, *hr, 'body')
        mz = h[2] - hr[2] * .26
        E(h[0] + hr[0] * .72, 0, mz, .18, .16, .13, 'muzzle'); E(h[0] + hr[0] * 1.0, 0, mz + .03, .045, .06, .04, 'nose')
        b.eyes2(h, hr, .088, 30, 14)
        for sg in (-1, 1):
            b.E(h[0] - .08, sg * hr[1] * .68, h[2] + hr[2] * .84, .09, .065, .09, 'body'); b.E(h[0] - .05, sg * hr[1] * .66, h[2] + hr[2] * .84, .05, .04, .05, 'inner')
            mr.bear_leg(b, (.20, .34), (.24, .18), (.22, .09), sg * .21, .12, 'body', 'paw', .10)
            mr.bear_leg(b, (-.20, .34), (-.26, .19), (-.24, .09), sg * .21, .125, 'body', 'paw', .10)
            b.cluster((.44, sg * .20, .03), (.45, sg * .15, 1), .40, .05, 8, 70 + sg, 'plate', 'plate2')
            b.cluster((.34, sg * .32, .03), (.2, sg * .8, 1), .26, .04, 5, 74 + sg, 'plate2', 'plate')
        E(-.35, 0, z, .09, .08, .09, 'body')
    return pal, build


# ───────────── Blossomfawn: compact fawn, short neck, round head, rich blossom antlers ─────────────
def blossomfawn():
    pal = dict(body='#c47a44', belly='#f0dcc0', limb='#a8683a', hoof='#3a2a20', dots='#fff0dc', wood='#5a3e2a', pink='#f4a0c0', pink2='#ffd0e0',
               leaf='#5fb04a', leaf2='#8ad060', nosec='#2a1c18', inner='#f4c4cc',
               glow=('#fff0a0', '#ffc840', 1.6), glow2=('#ffd6e4', '#ff9ac0', 1.4))

    def build(b):
        E, L = b.E, b.L
        zc, bl = .46, .32
        E(0, 0, zc, bl, .23, .22, 'body'); E(.16, 0, zc, .22, .22, .23, 'body'); E(-.16, 0, zc + .01, .22, .22, .22, 'body')
        E(.06, 0, zc - .08, bl * .8, .19, .15, 'belly')
        dots(b, (0, 0, zc), (bl, .23, .22), [(55, 40), (85, 50), (115, 40), (40, 62), (140, 52), (-55, 40), (-85, 50), (-115, 40), (-40, 62), (-140, 52),
                                             (70, 26), (100, 26), (-70, 26), (-100, 26)], .036, 'dots')
        for sg in (-1, 1):
            mr.deer_leg(b, bl * .62, sg * .14, .34, .20, .11, r=.056)
            mr.deer_leg(b, -bl * .62, sg * .14, .34, .17, .11, r=.06, hind=True)
        b.chain([(.24, 0, zc + .08, .15), (.32, 0, zc + .22, .125), (.36, 0, zc + .34, .11)], 'body')
        E(.28, 0, zc + .02, .13, .16, .22, 'belly')
        hx, hz = .42, zc + .46
        h, hr = (hx, 0, hz), (.23, .20, .20)
        E(*h, *hr, 'body')
        b.chain([(hx + .14, 0, hz - .05, .12), (hx + .24, 0, hz - .08, .10)], 'belly')
        E(hx + .31, 0, hz - .07, .05, .06, .045, 'nosec')
        b.eyes2(h, hr, .105, 40, 8)
        for sg in (-1, 1):
            b.E(hx - .06, sg * .21, hz + .12, .06, .12, .20, 'body', (.9 * sg, 0, 0)); b.E(hx - .05, sg * .20, hz + .12, .04, .09, .15, 'inner', (.9 * sg, 0, 0))
            bl_ = []
            antler(b, (hx - .02, sg * .07, hz + .17), (-.2, sg * .4, 1), .30, .042, 2, bl_, sg)
            for p in bl_:
                blossom(b, p, .062)
        for (x, y, z) in ((hx + .02, .14, hz + .26), (hx - .04, -.16, hz + .30), (hx + .08, 0, hz + .42), (hx - .12, .1, hz + .22)):
            blossom(b, (x, y, z), .05)
        E(-bl * .98, 0, zc + .10, .06, .055, .09, 'belly', (0, -.5, 0))
        for (x, y, z) in ((.3, .5, 1.5), (-.1, -.55, 1.3), (.7, -.4, 1.6), (.1, .45, 1.1), (.55, .5, 1.25), (-.3, .4, .95)):
            E(x, y, z, .04, .03, .02, 'pink', (.5, .3, .2))
        for (x, y, z) in ((.5, -.35, 1.35), (-.2, .45, 1.45), (.2, -.45, .9), (.35, .35, 1.7), (.0, -.3, 1.6)):
            b.feather((x, y, z), (.3, .5, .4), .12, .045, 'leaf' if x > .2 else 'leaf2', (0, 0, 1), .02)
    return pal, build


# ───────────── Duskhood: slim S-curve cobra, narrow banded hood, small head ─────────────
def duskhood():
    pal = dict(body='#403d54', belly='#aaa6c0', hood='#4c4964', band='#8a86a8', tongue='#e0405a',
               **md.PUR)

    def build(b):
        E, L = b.E, b.L
        r = .125
        n = 36
        pts = []
        for i in range(n):
            t = i / (n - 1)
            a = t * 1.3 * 2 * math.pi + 1.6
            R = .50 * (1 - t * .62)
            rad = r * (.3 + .7 * min(1, t * 1.7))
            pts.append((-.16 + math.cos(a) * R, math.sin(a) * R, rad + .01, rad))
        b.chain(pts, 'body')
        x0, y0 = pts[-1][0], pts[-1][1]
        neck = [(x0, y0, r, r), (-.22, 0, .32, r), (-.10, 0, .56, r * .95), (-.16, 0, .80, r * .9), (-.04, 0, 1.0, r * .82), (.06, 0, 1.10, r * .76)]
        b.chain(neck, 'body')
        for k in range(9):                                       # pale throat plates down the front
            t = k / 8
            E(.0 + t * .12, 0, .46 + t * .62, r * .45, r * .66, r * .36, 'belly')
        hx, hz = .26, 1.22
        wh = .30
        E(hx - .14, 0, hz - .16, .06, wh, wh * 1.2, 'hood')
        E(hx - .14, 0, hz - .44, .06, wh * .6, wh * .5, 'hood')
        for k in range(6):                                       # light cross bands on the hood
            zz = hz - .02 - k * .075
            wf = math.sqrt(max(.1, 1 - ((zz - (hz - .16)) / (wh * 1.2)) ** 2))
            E(hx - .08, 0, zz, .025, wh * wf * .85, .018, 'band')
        E(hx + .08, 0, hz, .20, .17, .14, 'body'); E(hx + .24, 0, hz - .05, .10, .11, .07, 'body')
        b.eyes2((hx + .08, 0, hz), (.20, .17, .14), .075, 42, 10)
        L((hx + .30, 0, hz - .09), (hx + .44, 0, hz - .16), .009, .007, 'tongue', 5)
        for sg in (-1, 1):
            L((hx + .44, 0, hz - .16), (hx + .53, sg * .04, hz - .22), .007, .004, 'tongue', 5)
    return pal, build


SPECIES = {'cinderchick': cinderchick, 'icepaw': icepaw, 'blossomfawn': blossomfawn, 'duskhood': duskhood}


def render(name, out, samples, size):
    ob = build_stage(name, 0)
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
    K.render(os.path.join(out, '%s_s0.png' % name))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=40)
    ap.add_argument('--size', type=int, default=640)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    import traceback
    for n in [n for n in a.only.split(',') if n] or list(SPECIES):
        try:
            render(n, a.out, a.samples, a.size)
        except Exception:
            print('FAILED', n)
            traceback.print_exc()


if __name__ == '__main__':
    main()
