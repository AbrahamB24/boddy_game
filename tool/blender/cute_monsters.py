"""Stage-0 proposals for the 28 monsters that have no asset yet, as voxels (Glimmergnaw recipe).

    blender --background --python tool/blender/cute_monsters.py -- \
        --only embit,flickle --out docs/renders/monsters/proposals [--samples 48]

One function per monster, all built from the same kit: chibi proportions, big eyes with one
glint voxel, one glowing accent that later stages grow. Facing +x, z up, same camera as the game.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

BASE = {'dark': ('#141830',), 'ivory': ('#fff6dc',), 'white': ('#ffffff', '#ffffff', 1.0),
        'nose': ('#2a1f2c',)}


class B:
    def __init__(s, pal):
        s.objs = []
        s.M = {}
        for k, v in list(BASE.items()) + list(pal.items()):
            v = v if isinstance(v, tuple) else (v,)
            if len(v) == 3 and k.startswith('glow'):       # saturated base = the emit colour,
                v = (v[1], v[1], v[2] * 0.45)               # or AgX washes the glow out to cream
            s.M[k] = tw.flat(k, *v)

    # ── primitives ──
    def E(s, x, y, z, rx, ry, rz, m, tilt=None):
        s.objs.append(K.ellipsoid(x, y, z, rx, ry, rz, s.M[m], seg=24, rings=16, tilt=tilt))

    def E2(s, x, y, z, rx, ry, rz, m, tilt=None):
        for sg in (-1, 1):
            t = None if tilt is None else (tilt[0] * sg, tilt[1], tilt[2] * sg)
            s.E(x, y * sg, z, rx, ry, rz, m, t)

    def L(s, p0, p1, r0, r1, m, seg=12):
        a, b = Vector(p0), Vector(p1)
        d = b - a
        c = K.cyl(0, 0, 0, r0, r1, d.length, s.M[m], seg=seg, smooth=True)
        c.location = a
        c.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        s.objs.append(c)

    def L2(s, p0, p1, r0, r1, m, seg=12):
        for sg in (-1, 1):
            s.L((p0[0], p0[1] * sg, p0[2]), (p1[0], p1[1] * sg, p1[2]), r0, r1, m, seg)

    def spike(s, x, y, z, length, r, lean=0.0, side=0.0, m='glow'):
        s.L((x, y, z), (x - math.sin(lean) * length, y + side * length, z + math.cos(lean) * length),
            r, 0.016, m, seg=6)

    def chain(s, pts, m):
        """Smooth tube of spheres through (x, y, z, r) points: tails, trunks, horns, vines."""
        for (x0, y0, z0, r0), (x1, y1, z1, r1) in zip(pts, pts[1:]):
            n = max(2, int(Vector((x1 - x0, y1 - y0, z1 - z0)).length / (min(r0, r1) * 0.55)))
            for i in range(n + 1):
                t = i / n
                r = r0 + (r1 - r0) * t
                s.E(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t, r, r, r, m)

    # ── the family face ──
    def eyes(s, c, r, er=0.085, az=34, el=8, m='dark'):
        for sg in (-1, 1):
            a, e = math.radians(az), math.radians(el)
            px = c[0] + r[0] * math.cos(e) * math.cos(a) * 0.95
            py = c[1] + sg * r[1] * math.cos(e) * math.sin(a) * 0.95
            pz = c[2] + r[2] * math.sin(e) * 0.95
            s.E(px, py, pz, er * 0.85, er, er * 1.08, m)
            s.E(px + er * 0.78 * 0.85, py - sg * er * 0.2, pz + er * 0.58 * 1.08,
                max(0.028, er * 0.30), max(0.028, er * 0.30), max(0.028, er * 0.30), 'white')

    def nose(s, c, r, size=0.045, el=-12, m='nose'):
        e = math.radians(el)
        s.E(c[0] + r[0] * math.cos(e) * 0.97, c[1], c[2] + r[2] * math.sin(e) * 0.97,
            size, size * 1.3, size * 0.85, m)

    def legs4(s, xf, xb, y, top, r, m, foot, fr=0.11):
        for x in (xf, xb):
            s.L2((x, y, top), (x + 0.03, y, 0.07), r, r * 0.9, m)
            s.E2(x + 0.07, y, 0.06, fr, fr * 0.78, 0.06, foot)

    def tooth(s, x, z, h=0.05):
        s.E2(x, 0.032, z, 0.02, 0.022, h, 'ivory')


# ═══════════ FIRE ═══════════
def embit(b):
    """Fox kitten, tail tip burns like a candle wick."""
    b.E(-0.02, 0, .40, .40, .28, .27, 'body'); b.E(.12, 0, .34, .30, .22, .20, 'belly')
    b.legs4(.28, -.26, .17, .30, .085, 'body', 'paw')
    h, r = (.44, 0, .70), (.36, .34, .31)
    b.E(*h, *r, 'body'); b.E(.74, 0, .62, .14, .13, .10, 'belly')
    b.nose((.74, 0, .62), (.14, .13, .10), .04, 8)
    b.eyes(h, r, .09)
    b.L2((.38, .20, .92), (.28, .30, 1.24), .12, .015, 'body')
    b.L2((.39, .19, .93), (.31, .27, 1.16), .065, .015, 'paw')
    b.chain([(-.36, 0, .36, .12), (-.58, 0, .48, .15), (-.66, 0, .72, .16), (-.58, 0, .94, .13)], 'body')
    b.spike(-.58, 0, .98, .34, .10, 0.15, 0, 'glow'); b.spike(-.56, .06, .98, .22, .06, .4, .2, 'glow2')
    b.spike(.42, 0, .98, .22, .06, 0.1, 0, 'glow')


def flickle(b):
    """Salamander, gill tufts are little flames."""
    b.E(-0.05, 0, .30, .50, .30, .24, 'body'); b.E(.05, 0, .24, .38, .24, .16, 'belly')
    for x in (.28, -.30):
        b.L2((x, .22, .26), (x + .06, .40, .08), .09, .08, 'body'); b.E2(x + .12, .42, .06, .11, .09, .05, 'paw')
    h, r = (.46, 0, .46), (.34, .38, .26)
    b.E(*h, *r, 'body'); b.eyes(h, r, .09, 40, 14)
    b.E(.72, 0, .38, .10, .17, .07, 'belly')
    for k in (0, 1, 2):
        b.spike(.30 - k * .04, .30, .52 + k * .10, .26, .045, .5, .5, 'glow' if k != 1 else 'glow2')
        b.spike(.30 - k * .04, -.30, .52 + k * .10, .26, .045, .5, -.5, 'glow' if k != 1 else 'glow2')
    b.chain([(-.46, 0, .26, .17), (-.74, .10, .20, .13), (-.96, .22, .20, .09), (-1.08, .34, .26, .06)], 'body')
    b.spike(-1.08, .34, .28, .26, .075, 0, 0, 'glow')
    for x in (.10, -.12, -.30):
        b.E(x, 0, .52, .045, .045, .03, 'spot')


def ashpip(b):
    """Falcon chick, a fluffy ball with ember-tipped crest."""
    b.E(0, 0, .46, .40, .36, .40, 'body'); b.E(.18, 0, .38, .26, .26, .30, 'belly')
    h, r = (.14, 0, .78), (.40, .38, .34)
    b.E(*h, *r, 'head'); b.eyes(h, r, .095, 36, 6)
    b.L((.46, 0, .74), (.66, 0, .66), .075, .03, 'beak'); b.L((.46, 0, .70), (.62, 0, .64), .05, .02, 'beak2')
    for k in (0, 1, 2):
        b.spike(.12 - k * .07, 0, 1.08 - k * .02, .26 - k * .03, .07, .4 + k * .2, 0, 'glow' if k != 1 else 'glow2')
    b.E2(0, .38, .50, .14, .10, .24, 'wing', (0.3, 0, 0))
    b.E2(0, .40, .34, .09, .06, .14, 'glow2', (0.3, 0, 0))
    b.E2(.08, .15, .06, .13, .08, .05, 'beak'); b.E2(.00, .15, .16, .035, .035, .12, 'beak')
    b.chain([(-.34, 0, .34, .10), (-.52, 0, .28, .09)], 'wing')


def coalcub(b):
    """Bear cub with ember claws."""
    b.E(0, 0, .42, .36, .33, .38, 'body'); b.E(.14, 0, .38, .24, .24, .30, 'belly')
    h, r = (.22, 0, .92), (.42, .40, .36)
    b.E(*h, *r, 'body'); b.E(.56, 0, .84, .15, .15, .11, 'muzzle'); b.nose((.56, 0, .84), (.15, .15, .11), .05, 10)
    b.eyes(h, r, .09, 38, 10)
    b.E2(.14, .32, 1.20, .11, .09, .11, 'body'); b.E2(.16, .32, 1.20, .06, .05, .07, 'muzzle')
    for sg in (-1, 1):
        b.L((.02, sg * .30, .60), (.30, sg * .22, .50), .10, .09, 'body')
        b.E(.34, sg * .20, .48, .12, .10, .10, 'body')
        for k in (-1, 0, 1):
            b.spike(.44, sg * .20 + k * .045, .46, .10, .03, 1.5, 0, 'glow2')
        b.E(.16, sg * .17, .07, .21, .12, .08, 'body')
    b.spike(-.14, 0, .72, .30, .09, .5, 0, 'glow'); b.spike(-.18, .10, .66, .22, .06, .6, .3, 'glow2')
    b.E(-.34, 0, .26, .10, .10, .10, 'body')


# ═══════════ WATER ═══════════
def dribblet(b):
    """Seal/frog pup of living water."""
    b.E(0, 0, .40, .38, .36, .38, 'body'); b.E(.14, 0, .34, .28, .26, .30, 'belly')
    h, r = (.18, 0, .88), (.42, .42, .36)
    b.E(*h, *r, 'body'); b.E(.50, 0, .78, .17, .20, .12, 'belly'); b.nose((.50, 0, .78), (.17, .20, .12), .05, 12)
    b.eyes(h, r, .10, 38, 14)
    b.chain([(.28, 0, 1.22, .08), (.26, 0, 1.36, .06), (.38, 0, 1.46, .05)], 'glow')
    b.E(.28, 0, 1.18, .12, .10, .08, 'glow')
    b.E2(.04, .40, .30, .20, .07, .10, 'body', (0.5, 0, 0)); b.E2(.14, .18, .06, .20, .12, .06, 'body')
    b.E(-.40, 0, .22, .26, .10, .08, 'glow2', (0, -.3, 0))
    b.E2(.52, .09, .70, .02, .02, .06, 'ivory')


def ripplefin(b):
    """Baby shark waddling upright."""
    b.E(0, 0, .44, .34, .30, .40, 'body'); b.E(.14, 0, .38, .24, .22, .32, 'belly')
    h, r = (.18, 0, .90), (.44, .40, .34)
    b.E(*h, *r, 'body'); b.E(.40, 0, .80, .20, .24, .14, 'belly')
    b.eyes(h, r, .10, 36, 14); b.E(.58, 0, .86, .06, .08, .045, 'nose')
    b.tooth(.56, .72, .05)
    b.E(-.05, 0, .96, .10, .04, .30, 'body', (0, -.5, 0)); b.spike(-.06, 0, 1.12, .28, .10, .6, 0, 'glow')
    b.E2(.02, .32, .50, .20, .06, .10, 'body', (0.6, 0, 0)); b.E2(.14, .16, .06, .22, .12, .06, 'fin')
    b.chain([(-.28, 0, .26, .14), (-.52, 0, .34, .12)], 'body'); b.E(-.62, 0, .52, .06, .22, .20, 'fin')
    for sg in (-1, 1):
        for k in (0, 1, 2):
            b.E(.30, sg * (.30 + k * .0), .82 - k * .05, .02, .05, .02, 'dark')


def shellotter(b):
    """Sea otter pup holding a pearl shell."""
    b.E(0, 0, .40, .34, .30, .38, 'body'); b.E(.14, 0, .38, .24, .24, .32, 'belly')
    h, r = (.18, 0, .90), (.40, .38, .34)
    b.E(*h, *r, 'body'); b.E(.46, 0, .80, .20, .22, .14, 'face'); b.nose((.46, 0, .80), (.20, .22, .14), .055, 12)
    b.eyes(h, r, .095, 36, 12)
    b.E2(.12, .28, 1.20, .07, .06, .07, 'body'); b.E2(.50, .12, .72, .04, .04, .04, 'glow')
    for sg in (-1, 1):
        b.L((.02, sg * .28, .62), (.34, sg * .14, .50), .09, .085, 'body')
    b.E(.40, 0, .46, .15, .20, .12, 'shell', (0, 0.4, 0)); b.E(.40, 0, .50, .05, .12, .09, 'shell2', (0, 0.4, 0))
    b.E2(.12, .16, .07, .18, .11, .07, 'body')
    b.chain([(-.30, 0, .24, .13), (-.56, 0, .18, .12), (-.76, 0, .14, .09)], 'body')


# ═══════════ PLANT ═══════════
def seedling(b):
    """Sloth with a sprout on its head."""
    b.E(0, 0, .42, .36, .34, .38, 'body'); b.E(.14, 0, .38, .24, .24, .30, 'belly')
    h, r = (.18, 0, .88), (.42, .40, .34)
    b.E(*h, *r, 'head')
    for sg in (-1, 1):
        b.E(.34, sg * .20, .90, .16, .12, .13, 'mask', (0.4 * sg, 0, 0))
    b.eyes(h, r, .085, 34, 6, 'dark'); b.nose(h, r, .045, -14)
    b.chain([(.20, 0, 1.18, .035), (.18, 0, 1.38, .035)], 'leaf')
    b.E(.20, .13, 1.46, .16, .06, .07, 'leaf', (0.3, 0.2, 0)); b.E(.18, -.13, 1.46, .16, .06, .07, 'leaf', (-0.3, -0.2, 0))
    b.E(.19, 0, 1.46, .06, .06, .08, 'glow')
    for sg in (-1, 1):
        b.L((.0, sg * .34, .70), (.22, sg * .40, .30), .09, .08, 'limb'); b.E(.26, sg * .40, .24, .09, .08, .08, 'limb')
        for k in (-1, 0, 1):
            b.L((.30, sg * .40 + k * .04, .22), (.38, sg * .40 + k * .04, .14), .025, 0, 'ivory', 6)
        b.E(.12, sg * .20, .07, .18, .11, .07, 'limb')


def budfawn(b):
    """Fawn with two budding antlers."""
    b.E(0, 0, .46, .40, .28, .28, 'body'); b.E(.12, 0, .38, .28, .20, .20, 'belly')
    for x in (.26, -.26):
        b.L2((x, .15, .40), (x + .03, .16, .08), .07, .055, 'limb'); b.E2(x + .05, .16, .05, .08, .065, .045, 'hoof')
    h, r = (.44, 0, .84), (.34, .31, .30)
    b.E(*h, *r, 'body'); b.E(.70, 0, .74, .13, .12, .10, 'belly'); b.nose((.70, 0, .74), (.13, .12, .10), .05, 8)
    b.eyes(h, r, .095, 36, 8)
    b.E2(.34, .30, 1.04, .08, .05, .16, 'body', (0.9, 0, 0)); b.E2(.35, .29, 1.03, .04, .03, .11, 'belly', (0.9, 0, 0))
    for sg in (-1, 1):
        b.L((.36, sg * .10, 1.08), (.30, sg * .16, 1.30), .045, .035, 'wood')
        b.spike(.30, sg * .16, 1.28, .14, .06, 0, 0, 'glow')
    for (x, y, z) in ((.10, .20, .68), (-.10, .18, .72), (.0, -.20, .70), (-.22, -.12, .66), (.18, -.12, .74)):
        b.E(x, y, z, .05, .05, .03, 'dots')
    b.E(-.40, 0, .56, .09, .08, .09, 'belly')


def vinelet(b):
    """Weasel with leaf ears and a curling vine tail."""
    b.E(-0.04, 0, .34, .56, .24, .22, 'body'); b.E(.06, 0, .28, .44, .18, .16, 'belly')
    b.legs4(.30, -.34, .15, .26, .07, 'body', 'limb', .09)
    h, r = (.52, 0, .64), (.32, .30, .28)
    b.E(*h, *r, 'body'); b.E(.78, 0, .56, .12, .11, .09, 'belly'); b.nose((.78, 0, .56), (.12, .11, .09), .045, 10)
    b.eyes(h, r, .09, 38, 10)
    b.E2(.44, .24, .88, .07, .13, .15, 'leaf', (0.5, 0, 0.3))
    b.chain([(-.54, 0, .32, .09), (-.82, 0, .38, .08), (-.98, 0, .56, .07), (-.92, 0, .76, .06), (-.76, 0, .82, .05)], 'vine')
    b.E(-.74, 0, .86, .08, .08, .08, 'glow'); b.E(-.98, .0, .64, .10, .04, .06, 'leaf')
    for x in (.10, -.14, -.36):
        b.E(x, 0, .55, .06, .06, .04, 'leaf')


def mosspup(b):
    """Wolf pup with a moss coat and a tiny mushroom."""
    b.E(0, 0, .40, .42, .29, .28, 'body'); b.E(.12, 0, .33, .30, .22, .20, 'belly')
    b.legs4(.28, -.26, .17, .30, .085, 'body', 'limb')
    h, r = (.44, 0, .70), (.35, .33, .31)
    b.E(*h, *r, 'body'); b.E(.72, 0, .62, .15, .13, .10, 'belly'); b.nose((.72, 0, .62), (.15, .13, .10), .05, 8)
    b.eyes(h, r, .09, 36, 10); b.tooth(.74, .52, .045)
    b.E2(.38, .22, .96, .09, .07, .17, 'body', (0.2, 0, .2)); b.E2(.38, .22, .95, .05, .04, .11, 'belly')
    for (x, y, z, rr) in ((-.04, 0, .66, .17), (-.22, .08, .62, .13), (-.20, -.10, .60, .12), (.10, -.08, .66, .11), (-.36, 0, .50, .10)):
        b.E(x, y, z, rr, rr * .9, rr * .55, 'moss')
    b.L((-.02, .10, .72), (-.02, .10, .88), .03, .03, 'ivory'); b.E(-.02, .10, .92, .10, .10, .05, 'cap'); b.E(.0, .12, .96, .03, .03, .02, 'ivory')
    b.chain([(-.40, 0, .34, .09), (-.58, 0, .44, .10), (-.64, 0, .58, .09)], 'moss')


# ═══════════ ICE ═══════════
def flakepaw(b):
    """Husky pup with an ice crystal on its brow."""
    b.E(0, 0, .40, .42, .29, .28, 'body'); b.E(.12, 0, .33, .30, .22, .20, 'belly')
    b.legs4(.28, -.26, .17, .30, .085, 'body', 'ice')
    h, r = (.44, 0, .70), (.36, .34, .32)
    b.E(*h, *r, 'body'); b.E(.40, 0, .78, .22, .22, .12, 'mask', (0, .2, 0))
    b.E(.72, 0, .62, .15, .14, .10, 'belly'); b.nose((.72, 0, .62), (.15, .14, .10), .05, 8)
    b.eyes(h, r, .09, 36, 10)
    b.L2((.38, .18, .94), (.34, .28, 1.22), .11, .02, 'body'); b.L2((.38, .18, .95), (.35, .26, 1.14), .06, .02, 'belly')
    b.spike(.52, 0, .96, .26, .07, 0.1, 0, 'glow'); b.spike(.48, .06, .96, .16, .05, .5, .3, 'glow2')
    b.chain([(-.38, 0, .38, .10), (-.56, 0, .52, .12), (-.52, 0, .70, .11), (-.38, 0, .74, .09)], 'tailw')
    b.E(-.50, 0, .80, .05, .05, .05, 'glow')


def flurry(b):
    """Snow hare with moth feelers."""
    b.E(0, 0, .40, .36, .32, .38, 'body'); b.E(.14, 0, .34, .26, .24, .30, 'belly')
    h, r = (.18, 0, .86), (.40, .38, .34)
    b.E(*h, *r, 'body'); b.eyes(h, r, .10, 36, 8); b.nose(h, r, .04, -14, 'pink')
    for sg in (-1, 1):
        b.L((.08, sg * .16, 1.10), (-.02, sg * .24, 1.62), .10, .06, 'body')
        b.L((.09, sg * .16, 1.12), (.0, sg * .23, 1.54), .06, .04, 'pink')
        b.spike(.34, sg * .10, 1.14, .24, .035, .6, sg * .4, 'glow')
        b.E(.34 - .14, sg * .10 + sg * .10, 1.30, .04, .04, .04, 'glow')
    b.E2(.10, .16, .07, .20, .11, .07, 'body'); b.E(-.38, 0, .34, .16, .16, .16, 'belly')
    b.E2(.16, .30, .86, .05, .02, .05, 'pink')


def icicrown(b):
    """Penguin chick with an ice crown."""
    b.E(0, 0, .48, .40, .36, .44, 'body'); b.E(.16, 0, .44, .28, .28, .36, 'belly')
    h, r = (.12, 0, .96), (.38, .36, .32)
    b.E(*h, *r, 'body'); b.E(.22, 0, .90, .22, .26, .22, 'belly', (0, .2, 0))
    b.eyes(h, r, .095, 34, 8); b.L((.44, 0, .90), (.64, 0, .84), .075, .03, 'beak')
    for k, (y, ln) in enumerate(((-.12, .20), (0, .30), (.12, .20))):
        b.spike(.12, y, 1.24, ln, .06, .1, y * 1.5, 'glow' if k != 1 else 'glow2')
    b.E2(.0, .40, .50, .12, .06, .26, 'body', (0.4, 0, 0)); b.E2(.14, .15, .05, .17, .10, .05, 'beak')
    b.E(-.40, 0, .22, .10, .08, .06, 'body')


def frostfluff(b):
    """Baby mammoth, shaggy and round."""
    b.E(0, 0, .44, .44, .36, .36, 'body'); b.E(.10, 0, .36, .34, .28, .26, 'belly')
    b.legs4(.26, -.26, .22, .30, .12, 'body', 'ice', .14)
    h, r = (.44, 0, .76), (.38, .38, .34)
    b.E(*h, *r, 'body'); b.eyes(h, r, .095, 40, 12)
    b.E(.30, 0, 1.08, .26, .22, .12, 'tuft')
    b.chain([(.78, 0, .72, .09), (.88, 0, .52, .08), (.86, 0, .34, .065), (.78, 0, .28, .06)], 'body')
    b.E2(.34, .36, .80, .10, .12, .22, 'body', (-0.3, 0, 0)); b.E2(.34, .38, .78, .05, .06, .15, 'tuft')
    for sg in (-1, 1):
        b.L((.66, sg * .18, .60), (.78, sg * .24, .40), .045, .02, 'ivory'); b.spike(.78, sg * .24, .40, .12, .025, 1.2, 0, 'glow')
    b.E(-.44, 0, .34, .10, .10, .12, 'tuft')
    for (x, y, z) in ((.0, .30, .70), (-.18, -.28, .64), (-.30, .20, .52)):
        b.E(x, y, z, .12, .08, .10, 'tuft')
    b.spike(-.08, 0, .76, .24, .07, .3, 0, 'glow')


# ═══════════ LIGHTNING ═══════════
def zipnut(b):
    """Squirrel that holds a charged nut."""
    b.E(0, 0, .40, .34, .30, .38, 'body'); b.E(.14, 0, .34, .24, .24, .30, 'belly')
    h, r = (.18, 0, .88), (.40, .38, .34)
    b.E(*h, *r, 'body'); b.E(.50, 0, .78, .15, .15, .11, 'belly'); b.nose((.50, 0, .78), (.15, .15, .11), .045, 8)
    b.eyes(h, r, .095, 36, 10); b.tooth(.52, .68, .04)
    b.L2((.10, .26, 1.14), (.02, .34, 1.36), .09, .015, 'body'); b.spike(.02, .34, 1.36, .14, .035, 0, 0, 'glow')
    b.L2((.10, -.26, 1.14), (.02, -.34, 1.36), .09, .015, 'body'); b.spike(.02, -.34, 1.36, .14, .035, 0, 0, 'glow')
    b.chain([(-.30, 0, .30, .16), (-.62, 0, .40, .20), (-.74, 0, .72, .22), (-.62, 0, 1.04, .20), (-.40, 0, 1.18, .16)], 'body')
    b.E(-.74, .16, .72, .06, .06, .20, 'glow', (0, 0, .3)); b.E(-.62, .17, 1.02, .05, .05, .14, 'glow', (0, 0, -.3))
    b.E(.34, 0, .44, .13, .13, .13, 'nut'); b.E(.34, 0, .50, .07, .07, .08, 'glow')
    for sg in (-1, 1):
        b.L((.02, sg * .28, .60), (.30, sg * .12, .50), .08, .075, 'body')
    b.E2(.12, .16, .07, .18, .11, .07, 'body')


def crackpaw(b):
    """Terrier pup with a permanent static hairdo."""
    b.E(0, 0, .40, .40, .29, .28, 'body'); b.E(.12, 0, .33, .28, .22, .20, 'belly')
    b.legs4(.26, -.26, .17, .30, .085, 'body', 'paw')
    h, r = (.42, 0, .70), (.36, .34, .32)
    b.E(*h, *r, 'body'); b.E(.70, 0, .62, .15, .13, .10, 'belly'); b.nose((.70, 0, .62), (.15, .13, .10), .05, 8)
    b.eyes(h, r, .095, 36, 10)
    b.E2(.30, .32, .86, .10, .08, .18, 'body', (0.9, 0, 0))
    for k, (x, y, ln, ln2) in enumerate(((.40, 0, .30, 0.0), (.32, .10, .24, .4), (.32, -.10, .24, -.4), (.18, .06, .22, .3), (.18, -.06, .22, -.3))):
        b.spike(x, y, .98, ln, .05, ln2 * .8, y, 'glow' if k % 2 == 0 else 'fur')
    for k in range(3):
        b.spike(-.08 - k * .12, 0, .66, .22, .05, .9, 0, 'glow' if k % 2 == 0 else 'fur')
    b.chain([(-.36, 0, .36, .07), (-.50, 0, .48, .07), (-.40, 0, .60, .06), (-.52, 0, .74, .06)], 'glow')


def zigzag(b):
    """Flying squirrel with zig-zag membranes."""
    b.E(0, 0, .40, .32, .28, .36, 'body'); b.E(.14, 0, .34, .22, .22, .28, 'belly')
    h, r = (.16, 0, .86), (.40, .38, .34)
    b.E(*h, *r, 'body'); b.E(.46, 0, .76, .14, .14, .10, 'belly'); b.nose((.46, 0, .76), (.14, .14, .10), .045, 8)
    b.eyes(h, r, .11, 36, 10)
    b.E2(.10, .22, 1.14, .09, .07, .10, 'body'); b.E2(.10, .22, 1.14, .05, .04, .06, 'belly')
    for sg in (-1, 1):
        b.L((.0, sg * .26, .62), (.0, sg * .66, .44), .07, .06, 'body')
        b.E(.0, sg * .50, .38, .20, .30, .05, 'wing', (0.25 * sg, 0, 0))
        for k, y in enumerate((.36, .50, .66)):
            b.E(.0, sg * y, .22 - (k % 2) * .05, .05, .05, .03, 'glow')
        b.E(.0, sg * .66, .46, .07, .07, .07, 'body')
    b.E2(.10, .15, .07, .16, .10, .07, 'body')
    b.chain([(-.28, 0, .26, .12), (-.52, 0, .30, .14), (-.74, 0, .44, .14)], 'body')
    b.E(-.74, 0, .44, .08, .10, .10, 'glow')


def rumblehorn(b):
    """Rhino calf, small horn crackling."""
    b.E(0, 0, .42, .46, .34, .34, 'body'); b.E(.12, 0, .34, .34, .26, .24, 'belly')
    b.legs4(.28, -.28, .22, .32, .12, 'body', 'hoof', .14)
    h, r = (.50, 0, .70), (.38, .34, .30)
    b.E(*h, *r, 'body'); b.E(.78, 0, .62, .17, .20, .13, 'belly'); b.nose((.78, 0, .62), (.17, .20, .13), .05, 20)
    b.eyes(h, r, .095, 40, 12)
    b.E2(.42, .28, .96, .08, .06, .09, 'body')
    b.spike(.86, 0, .72, .28, .10, 1.0, 0, 'glow'); b.spike(.64, 0, .86, .16, .06, .5, 0, 'glow2')
    b.E(.0, .30, .52, .10, .035, .08, 'glow', (0, 0, .5)); b.E(.10, .31, .44, .08, .03, .06, 'glow', (0, 0, -.5))
    b.E(-.40, 0, .44, .06, .06, .06, 'body')


# ═══════════ STONE ═══════════
def pebbly(b):
    """Hedgehog-turtle: face peeks out of a pebble shell."""
    b.E(-.06, 0, .38, .46, .38, .34, 'shell')
    for (x, y, z, rr) in ((-.04, 0, .66, .20), (-.28, .14, .58, .16), (-.28, -.14, .58, .16), (.14, .20, .58, .13), (.14, -.20, .58, .13), (-.46, 0, .44, .14), (-.08, .30, .42, .12), (-.08, -.30, .42, .12)):
        b.E(x, y, z, rr, rr, rr * .75, 'rock')
    b.E(-.08, 0, .84, .08, .08, .05, 'moss'); b.E(-.14, .05, .82, .06, .06, .04, 'moss')
    h, r = (.38, 0, .48), (.30, .30, .26)
    b.E(*h, *r, 'face'); b.eyes(h, r, .09, 38, 12); b.nose(h, r, .04, -14)
    b.E2(.10, .26, .08, .17, .11, .07, 'face'); b.E2(-.30, .26, .08, .17, .11, .07, 'face')
    b.spike(-.10, 0, .90, .14, .05, 0, 0, 'glow')


def digglet(b):
    """Mole with shovel paws and crystals sprouting from its back."""
    b.E(0, 0, .40, .38, .32, .36, 'body'); b.E(.14, 0, .34, .26, .24, .28, 'belly')
    h, r = (.18, 0, .86), (.38, .36, .32)
    b.E(*h, *r, 'body'); b.E(.50, 0, .74, .17, .17, .12, 'belly'); b.E(.64, 0, .76, .07, .08, .06, 'pink')
    b.eyes(h, r, .085, 34, 10)
    for sg in (-1, 1):
        b.L((.0, sg * .30, .56), (.28, sg * .34, .34), .10, .09, 'body')
        b.E(.34, sg * .36, .30, .08, .16, .16, 'palm', (0, 0, 0));
        for k in (-1, 0, 1):
            b.L((.40, sg * .36 + k * .08, .30), (.52, sg * .36 + k * .09, .22), .04, 0.0, 'ivory', 6)
        b.E(.10, sg * .16, .07, .18, .11, .07, 'palm')
    b.E2(.16, .26, 1.14, .06, .05, .06, 'body')
    b.spike(-.10, .0, .72, .30, .09, .5, 0, 'glow'); b.spike(-.14, .10, .68, .22, .06, .6, .3, 'glow2'); b.spike(-.14, -.10, .68, .20, .06, .6, -.3, 'glow2')
    b.E(-.38, 0, .22, .09, .09, .09, 'palm')


def runestone(b):
    """Owl-shaped standing stone, runes glowing faintly."""
    b.E(0, 0, .50, .40, .36, .46, 'stone'); b.E(.18, 0, .46, .26, .28, .36, 'stone2')
    h, r = (.12, 0, .98), (.40, .40, .34)
    b.E(*h, *r, 'stone'); b.eyes(h, r, .125, 34, 6)
    b.L((.46, 0, .90), (.60, 0, .84), .06, .02, 'ivory')
    b.L2((.06, .24, 1.22), (-.02, .30, 1.44), .11, .02, 'stone')
    for k, z in enumerate((.64, .50, .36)):
        b.E(.40, 0, z, .02, .10 - k * .02, .035, 'glow')
    b.E(.40, 0, .72, .02, .035, .08, 'glow')
    b.E2(.0, .38, .52, .12, .07, .26, 'stone', (0.3, 0, 0)); b.E2(.10, .16, .06, .15, .10, .05, 'rock')
    b.spike(-.12, 0, 1.28, .18, .06, .3, 0, 'glow')


def cragkid(b):
    """Ibex kid with moss cape and crystal crown."""
    b.E(0, 0, .46, .40, .28, .28, 'body'); b.E(.12, 0, .38, .28, .20, .20, 'belly')
    for x in (.26, -.26):
        b.L2((x, .15, .40), (x + .03, .16, .08), .07, .055, 'limb'); b.E2(x + .05, .16, .05, .08, .065, .045, 'hoof')
    h, r = (.44, 0, .84), (.34, .31, .30)
    b.E(*h, *r, 'body'); b.E(.70, 0, .74, .13, .12, .10, 'belly'); b.nose((.70, 0, .74), (.13, .12, .10), .05, 8)
    b.eyes(h, r, .095, 36, 8)
    for sg in (-1, 1):
        b.chain([(.36, sg * .12, 1.06, .055), (.26, sg * .18, 1.24, .05), (.10, sg * .22, 1.30, .045), (-.02, sg * .24, 1.20, .035)], 'horn')
    b.E2(.34, .30, 1.02, .08, .05, .13, 'body', (0.9, 0, 0))
    b.E(.0, 0, .70, .26, .26, .14, 'moss'); b.E(-.12, .14, .66, .14, .10, .08, 'moss'); b.E(-.12, -.14, .66, .14, .10, .08, 'moss')
    b.spike(.44, 0, 1.10, .20, .06, 0, 0, 'glow')
    b.E(.58, 0, .56, .05, .05, .08, 'belly'); b.E(-.40, 0, .54, .08, .07, .08, 'belly')


# ═══════════ LIGHT ═══════════
def prismling(b):
    """Lynx kitten with prism ear tufts."""
    b.E(0, 0, .40, .38, .28, .28, 'body'); b.E(.12, 0, .33, .27, .21, .20, 'belly')
    b.legs4(.26, -.26, .17, .30, .08, 'body', 'paw')
    h, r = (.42, 0, .70), (.36, .36, .31)
    b.E(*h, *r, 'body'); b.E(.70, 0, .62, .13, .12, .09, 'belly'); b.nose((.70, 0, .62), (.13, .12, .09), .045, 8)
    b.eyes(h, r, .10, 36, 10)
    b.E2(.30, .30, .70, .08, .10, .12, 'belly', (0.3, 0, 0))
    b.L2((.36, .20, .92), (.28, .30, 1.22), .12, .015, 'body')
    b.spike(.28, .30, 1.20, .22, .05, 0, .0, 'glow'); b.spike(.28, -.30, 1.20, .22, .05, 0, 0, 'glow3')
    b.spike(.46, 0, .98, .22, .06, .1, 0, 'glow2')
    for (x, y, z) in ((.0, .22, .54), (-.16, .20, .50), (-.20, -.18, .52), (.06, -.22, .56)):
        b.E(x, y, z, .05, .05, .035, 'dots')
    b.chain([(-.36, 0, .40, .09), (-.50, 0, .50, .09)], 'body'); b.E(-.52, 0, .52, .06, .06, .06, 'glow')


def sunmane(b):
    """Lion cub with a ring of sunlight for a mane."""
    b.E(0, 0, .40, .38, .30, .30, 'body'); b.E(.12, 0, .33, .27, .22, .22, 'belly')
    b.legs4(.26, -.26, .17, .30, .085, 'body', 'paw')
    h, r = (.42, 0, .70), (.34, .33, .31)
    for k in range(10):
        a = k / 10 * 2 * math.pi
        b.spike(.28, math.sin(a) * .30, .70 + math.cos(a) * .30, .20, .07,
                math.cos(a) * .5, math.sin(a) * .5, 'glow' if k % 2 == 0 else 'glow2')
    b.E(.30, 0, .70, .30, .36, .34, 'mane')
    b.E(*h, *r, 'body'); b.E(.68, 0, .62, .14, .13, .10, 'belly'); b.nose((.68, 0, .62), (.14, .13, .10), .05, 8)
    b.eyes(h, r, .10, 36, 10)
    b.E2(.34, .26, .94, .09, .07, .09, 'body')
    b.spike(.44, 0, .96, .12, .05, 0.2, 0, 'glow')
    b.chain([(-.36, 0, .34, .07), (-.58, 0, .42, .07), (-.66, 0, .58, .07)], 'body'); b.E(-.66, 0, .66, .12, .10, .14, 'mane')


# ═══════════ SHADOW ═══════════
def moonear(b):
    """Bat pup with big ears and a moon on its chest."""
    b.E(0, 0, .44, .34, .30, .38, 'body'); b.E(.14, 0, .40, .24, .24, .32, 'belly')
    b.E(.30, 0, .52, .10, .10, .10, 'glow'); b.E(.33, 0, .55, .09, .09, .09, 'belly')
    h, r = (.16, 0, .90), (.40, .38, .34)
    b.E(*h, *r, 'body'); b.E(.44, 0, .80, .13, .14, .10, 'belly'); b.nose((.44, 0, .80), (.13, .14, .10), .04, 8)
    b.eyes(h, r, .105, 36, 10); b.tooth(.50, .72, .04)
    b.L2((.10, .18, 1.12), (-.02, .30, 1.62), .14, .02, 'body')
    b.L2((.11, .18, 1.12), (.0, .28, 1.50), .08, .02, 'inner')
    for sg in (-1, 1):
        b.L((.0, sg * .30, .62), (.0, sg * .62, .48), .07, .05, 'body')
        b.E(.0, sg * .50, .38, .16, .22, .04, 'wing', (0.3 * sg, 0, 0)); b.E(.0, sg * .64, .46, .06, .06, .06, 'ivory')
    b.E2(.10, .14, .07, .15, .09, .06, 'body')
    b.spike(-.20, 0, .78, .16, .05, .5, 0, 'glow2')


def dusklet(b):
    """Mouse with huge ears and a wisp of shadow."""
    b.E(0, 0, .38, .32, .28, .34, 'body'); b.E(.14, 0, .32, .22, .22, .26, 'belly')
    h, r = (.16, 0, .82), (.38, .36, .32)
    b.E(*h, *r, 'body'); b.E(.46, 0, .74, .13, .12, .09, 'belly'); b.nose((.46, 0, .74), (.13, .12, .09), .045, 8, 'pink')
    b.eyes(h, r, .105, 36, 10)
    b.E2(.04, .28, 1.12, .06, .22, .22, 'body', (0.6, 0, 0)); b.E2(.05, .28, 1.12, .03, .15, .15, 'inner', (0.6, 0, 0))
    b.E2(.12, .14, .07, .15, .09, .06, 'body')
    for sg in (-1, 1):
        b.L((.0, sg * .26, .56), (.28, sg * .12, .46), .07, .065, 'body')
    b.chain([(-.28, 0, .26, .06), (-.54, 0, .20, .055), (-.76, .12, .22, .045), (-.92, .28, .34, .04)], 'tailm')
    b.E(-.96, .30, .52, .10, .10, .12, 'glow'); b.E(-.90, .36, .72, .06, .06, .08, 'glow2')
    b.E(.46, .0, .90, .04, .04, .04, 'glow2')


def starfluff(b):
    """Raven chick, a navy fluff ball dotted with stars."""
    b.E(0, 0, .46, .40, .36, .40, 'body'); b.E(.18, 0, .38, .26, .26, .30, 'belly')
    h, r = (.14, 0, .80), (.40, .38, .34)
    b.E(*h, *r, 'body'); b.eyes(h, r, .10, 36, 6)
    b.L((.46, 0, .76), (.68, 0, .68), .08, .03, 'beak'); b.L((.46, 0, .72), (.64, 0, .66), .05, .02, 'beak2')
    for k in range(3):
        b.spike(.10 - k * .08, 0, 1.10 - k * .01, .20, .06, .5 + k * .3, 0, 'body')
    b.spike(.04, 0, 1.12, .16, .04, .4, 0, 'glow')
    b.E2(0, .38, .50, .14, .10, .24, 'wing', (0.3, 0, 0))
    for (x, y, z) in ((.0, .46, .56), (.0, -.46, .50), (-.26, .24, .70), (-.30, -.20, .60), (.0, .30, .36)):
        b.E(x, y, z, .04, .04, .04, 'glow')
    b.E2(.08, .15, .06, .13, .08, .05, 'beak'); b.chain([(-.34, 0, .34, .10), (-.52, 0, .26, .09)], 'wing')


# id: (builder, palette)
G = ('#ffd36b', '#ffb02e', 0.9)        # warm glow
SPECIES = {
    'embit': (embit, dict(body='#f2a35e', head='#f2a35e', belly='#fff0d6', paw='#b8512c',
                          glow=('#ffd36b', '#ff9a1f', 1.3), glow2=('#ff7a2e', '#ff5a0f', 1.1))),
    'flickle': (flickle, dict(body='#e8683c', belly='#ffe3b0', paw='#a63b24', spot='#ffd36b',
                              glow=('#ffd36b', '#ff9a1f', 1.3), glow2=('#ff7a2e', '#ff5a0f', 1.1))),
    'ashpip': (ashpip, dict(body='#b99a7e', head='#cfb396', belly='#f6ead8', wing='#8e6e56', beak='#f0b34a',
                            beak2='#c98a2c', glow=('#ffd36b', '#ff9a1f', 1.3), glow2=('#ff7a2e', '#ff5a0f', 1.1))),
    'coalcub': (coalcub, dict(body='#54443f', belly='#6c5a52', muzzle='#e8cdb0',
                              glow=('#ffd36b', '#ff9a1f', 1.3), glow2=('#ff7a2e', '#ff5a0f', 1.1))),
    'dribblet': (dribblet, dict(body='#7fc6ee', belly='#e9f7ff', fin='#5aa8de',
                                glow=('#bff0ff', '#4fd0ff', 0.9), glow2=('#9ad8ff', '#3fb0ff', .7))),
    'ripplefin': (ripplefin, dict(body='#7e97b8', belly='#eef3f8', fin='#5c76a0',
                                  glow=('#bff0ff', '#4fd0ff', 0.9))),
    'shellotter': (shellotter, dict(body='#8c6a4c', belly='#b28d68', face='#f1dfc4', shell='#ffd9e4', shell2='#f5aac0',
                                    glow=('#bff0ff', '#4fd0ff', 0.9))),
    'seedling': (seedling, dict(body='#c9d8a6', head='#dce6bd', belly='#f3f0d2', limb='#a8b87e', mask='#7d8f5e',
                                leaf='#6fc05a', glow=('#d6ff8a', '#8ae83a', 1.0))),
    'budfawn': (budfawn, dict(body='#d3a06b', belly='#f6e6cc', limb='#b4814f', hoof='#5c4632', dots='#fff3de',
                              wood='#8c6a45', glow=('#d6ff8a', '#8ae83a', 1.0))),
    'vinelet': (vinelet, dict(body='#c98b4e', belly='#fbebc9', limb='#a66d36', leaf='#6fc05a', vine='#4ea44a',
                              glow=('#d6ff8a', '#8ae83a', 1.0))),
    'mosspup': (mosspup, dict(body='#a39583', belly='#ece3d0', limb='#7f735f', moss='#6aa84f', cap='#e0584a',
                              glow=('#d6ff8a', '#8ae83a', 1.0))),
    'flakepaw': (flakepaw, dict(body='#aecbe6', belly='#f4fbff', mask='#7f9cc0', ice='#d9f0ff', tailw='#e9f6ff',
                                glow=('#bff0ff', '#4fd0ff', 1.0), glow2=('#9ad8ff', '#3fb0ff', .8))),
    'flurry': (flurry, dict(body='#f2f7fb', belly='#ffffff', pink='#f5b5c6',
                            glow=('#bff0ff', '#4fd0ff', 1.0))),
    'icicrown': (icicrown, dict(body='#6f87a8', belly='#f4f8fc', beak='#f3a43b',
                                glow=('#bff0ff', '#4fd0ff', 1.0), glow2=('#9ad8ff', '#3fb0ff', .8))),
    'frostfluff': (frostfluff, dict(body='#bcd6ec', belly='#e6f1fa', tuft='#eef6fc', ice='#9fc4e4',
                                    glow=('#bff0ff', '#4fd0ff', 1.0))),
    'zipnut': (zipnut, dict(body='#e6b84a', belly='#fff2c9', nut='#8a6a3a',
                            glow=('#fff29a', '#ffe030', 1.5))),
    'crackpaw': (crackpaw, dict(body='#efd9a4', belly='#fff8e6', paw='#cdb07a', fur='#f7ee9a',
                                glow=('#fff29a', '#ffe030', 1.5))),
    'zigzag': (zigzag, dict(body='#b7ad9f', belly='#f2ecdf', wing='#d8cdb4',
                            glow=('#fff29a', '#ffe030', 1.5))),
    'rumblehorn': (rumblehorn, dict(body='#7f8fa8', belly='#c7d0de', hoof='#4e5a70',
                                    glow=('#fff29a', '#ffe030', 1.5), glow2=('#ffd23a', '#ffb800', 1.2))),
    'pebbly': (pebbly, dict(shell='#a39a8b', rock='#bdb4a3', face='#e3d2b6', moss='#6aa84f',
                            glow=('#9ff0ff', '#3fd0ff', 1.0))),
    'digglet': (digglet, dict(body='#8c7a68', belly='#c3b29c', pink='#f0a7b4', palm='#6f5f50',
                              glow=('#7affc8', '#20e8a0', 1.1), glow2=('#5fd8ff', '#20b0ff', 1.0))),
    'runestone': (runestone, dict(stone='#a8a090', stone2='#cfc8b6', rock='#8c8576',
                                  glow=('#9ff0ff', '#3fd0ff', 1.4))),
    'cragkid': (cragkid, dict(body='#b5a58e', belly='#efe5d2', limb='#8f8068', hoof='#4a3e32', horn='#8a8478',
                              moss='#6aa84f', glow=('#9ff0ff', '#3fd0ff', 1.1))),
    'prismling': (prismling, dict(body='#f6efe6', belly='#ffffff', paw='#e5d8c6', dots='#c9b9d8',
                                  glow=('#ff9ad8', '#ff5ac0', 1.2), glow2=('#9ad8ff', '#3fb0ff', 1.2),
                                  glow3=('#fff29a', '#ffe030', 1.2))),
    'sunmane': (sunmane, dict(body='#f0c46a', belly='#fff0d0', paw='#d49a3e', mane='#e8993a',
                              glow=('#ffe08a', '#ffc21a', 1.4), glow2=('#ffb040', '#ff8a10', 1.2))),
    'moonear': (moonear, dict(body='#5b4a86', belly='#9a8bc4', inner='#e898c8', wing='#47396e',
                              glow=('#fff2b0', '#ffe070', 1.4), glow2=('#c8a0ff', '#a070ff', 1.2))),
    'dusklet': (dusklet, dict(body='#6c6684', belly='#b7b0cc', inner='#d09ac0', pink='#d09ac0', tailm='#8f88a8',
                              glow=('#c8a0ff', '#a070ff', 1.2), glow2=('#9a70e8', '#7040d0', 1.0))),
    'starfluff': (starfluff, dict(body='#3a3f78', belly='#5b62a6', wing='#2c3060', beak='#e0b04a', beak2='#b08a30',
                                  glow=('#fff29a', '#ffe030', 1.5))),
}


def render_one(name, out, samples, size):
    fn, pal = SPECIES[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 8
    b = B(pal)
    fn(b)
    ob = tw.voxelise(b.objs)
    K.lighting(sky=0.85, sun=5.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))
    sc = bpy.context.scene
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    ctr = sum(corners, Vector()) / 8
    off = Vector((5.2, -4.0, 2.8))
    co.location = ctr + off
    co.rotation_euler = (ctr - co.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.view_layer.update()
    inv = co.matrix_world.inverted()
    pts = [inv @ c for c in corners]
    w = max(p.x for p in pts) - min(p.x for p in pts)
    h = max(p.y for p in pts) - min(p.y for p in pts)
    cam.ortho_scale = max(w, h) * 1.16
    sc.camera = co
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.exposure = 0.3
    K.render(os.path.join(out, name + '.png'))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=48)
    ap.add_argument('--size', type=int, default=640)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    names = [n for n in a.only.split(',') if n] or list(SPECIES)
    for n in names:
        render_one(n, a.out, a.samples, a.size)


if __name__ == '__main__':
    main()
