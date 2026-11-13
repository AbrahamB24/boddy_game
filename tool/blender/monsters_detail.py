"""Detailed, stage-by-stage models (finer voxels, every stage modelled on its own).

    blender --background --python tool/blender/monsters_detail.py -- --only cinderchick --out docs/renders/monsters/detail

No ground, no base: just the creature. Each stage is fitted to its own frame.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monsters_all as ma  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

FIRE = ma.FIRE
ICE = ma.ICE
PUR = dict(glow=('#e0c4ff', '#a070ff', 2.0), glow2=('#b890ff', '#7040d0', 1.6))


class D(ma.S):
    def leg(s, top, ankle, r, m, paw_m=None):
        """A rounded limb: ball at the top, tapered shaft, ball at the ankle."""
        s.E(top[0], top[1], top[2], r * 1.25, r * 1.2, r * 1.35, m)
        s.L(top, ankle, r, r * .75, m)
        s.E(ankle[0], ankle[1], ankle[2], r * .8, r * .8, r * .8, m)

    def blade(s, p, d, length, width, m, thick=.02, curl=0.0):
        """A flat pointed leaf from p along d: feathers, flames, petals, ice blades."""
        d = Vector(d).normalized()
        c = Vector(p) + d * length * .5
        up = 'Y' if abs(d.z) > .95 else 'Z'
        eul = d.to_track_quat('X', up).to_euler()
        s.E(c.x, c.y, c.z, length * .5, width, thick, m, tuple(eul))

    def eyes2(s, c, r, er=.1, az=36, el=8, hl=.017, m='dark'):
        for sg in (-1, 1):
            a, e = math.radians(az), math.radians(el)
            px = c[0] + r[0] * math.cos(e) * math.cos(a) * .95
            py = c[1] + sg * r[1] * math.cos(e) * math.sin(a) * .95
            pz = c[2] + r[2] * math.sin(e) * .95
            s.E(px, py, pz, er * .85, er, er * 1.08, m)
            s.E(px + er * .74, py - sg * er * .2, pz + er * .6, hl, hl, hl, 'white')

    def toes(s, p, y, n, ln, rad, m, claw=True, spread=.06):
        for i in range(n):
            yy = y + (i - (n - 1) / 2) * spread
            s.L((p[0], yy, p[2] + .01), (p[0] + ln, yy + (i - (n - 1) / 2) * .015, p[2] - .01), rad, rad * .7, m, seg=6)
            if claw:
                s.L((p[0] + ln, yy, p[2] - .005), (p[0] + ln + .05, yy, p[2] - .04), rad * .7, .005, 'ivory', seg=5)


def fluff(b, c, r, n, ln, rad, m, seed, skip=None):
    rng = random.Random(seed)
    for _ in range(n):
        u = rng.uniform(-1, 1)
        a = rng.uniform(0, 2 * math.pi)
        s = math.sqrt(1 - u * u)
        d = (s * math.cos(a), s * math.sin(a), u)
        if skip and skip(d):
            continue
        p = Vector((c[0] + r[0] * d[0], c[1] + r[1] * d[1], c[2] + r[2] * d[2]))
        nrm = Vector((d[0] / r[0], d[1] / r[1], d[2] / r[2])).normalized()
        b.L(p - nrm * ln * .3, p + nrm * ln, rad * 1.5, rad * .8, m, seg=6)      # blunt tuft, not a thorn


def dots(b, c, r, pts, rad, m):
    """Spots painted onto an ellipsoid surface: pts are (azimuth, elevation) in degrees."""
    for az, el in pts:
        a, e = math.radians(az), math.radians(el)
        d = (math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))
        b.E(c[0] + r[0] * d[0] * .99, c[1] + r[1] * d[1] * .99, c[2] + r[2] * d[2] * .99, rad, rad, rad * .6, m,
            tuple(Vector((d[0] / r[0], d[1] / r[1], d[2] / r[2])).normalized().to_track_quat('Z', 'Y').to_euler()))


def wing_fan(b, sg, root, n, lmax, width, e0, e1, back, mats, spread=.9, tip_glow=False):
    for i in range(n):
        t = i / (n - 1)
        a = e0 + (e1 - e0) * t
        d = (-back * (1 - .4 * t), sg * math.cos(a) * spread, math.sin(a))
        ln = lmax * (.62 + .38 * math.sin(math.pi * (i + .5) / n))
        m = mats[min(len(mats) - 1, int(t * len(mats)))]
        b.blade(root, d, ln, width, m, .026)
        if tip_glow:
            dd = Vector(d).normalized()
            tip = Vector(root) + dd * ln
            b.L(tip, tip + dd * .08, width * .6, .01, 'glow', seg=5)


def blossom(b, p, r, m1='pink', m2='pink2', core='glow'):
    n = Vector((1, -.7, .4)).normalized()
    u = n.cross(Vector((0, 0, 1))).normalized()
    v = n.cross(u).normalized()
    for i in range(5):
        a = i / 5 * 2 * math.pi
        q = Vector(p) + (u * math.cos(a) + v * math.sin(a)) * r * .62
        b.E(q.x, q.y, q.z, r * .46, r * .46, r * .4, m1 if i % 2 == 0 else m2)
    b.E(p[0], p[1], p[2], r * .30, r * .30, r * .30, core)


def antler(b, p0, d, length, r, depth, blooms, sg, leaf=False):
    d = Vector(d).normalized()
    p0 = Vector(p0)
    p1 = p0 + d * length
    b.L(p0, p1, r, r * .66, 'wood', seg=8)
    if depth > 0:
        for k, ang in enumerate((.9, -.7)):
            q = Quaternion((0, 1, 0), ang * .8) @ d
            q = Quaternion((1, 0, 0), sg * ang * .6) @ q
            antler(b, p0 + d * length * (.55 + .12 * k), q, length * .58, r * .66, depth - 1, blooms, sg, leaf)
        nd = Quaternion((0, 1, 0), -.25) @ d
        antler(b, p1, nd, length * .72, r * .7, depth - 1, blooms, sg, leaf)
    else:
        blooms.append(p1)


def build_stage(name, st):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 9
    pal, build = SPECIES[name](st)
    b = D(pal, 1.0)
    build(b)
    return tw.voxelise(b.objs)


# ═══════════════════ CINDERCHICK → FLAMEWING → SOLARPHOENIX ═══════════════════
def cinderchick(st):
    pal = dict(body=['#e0452f', '#e2502a', '#c8321e'][st], head=['#e8553a', '#ea5e2c', '#d24020'][st], belly=['#f6b85a', '#f8c060', '#ffd878'][st],
               down='#f27a4a', beak='#f2a834', beak2='#c98a24', leg='#e8a030', gold='#ffc22e',
               f1='#d8352a', f2='#ff6a1c', f3='#ffb020', f4='#ffe27a', **FIRE)

    def build(b):
        E, L = b.E, b.L
        if st == 0:                                              # round fluffy chick, ember-tipped wing buds
            E(0, 0, .44, .34, .31, .36, 'body'); E(.14, 0, .38, .22, .22, .28, 'belly')
            fluff(b, (0, 0, .44), (.34, .31, .36), 60, .08, .035, 'down', 1, lambda d: d[2] > .7 or (d[0] > .6 and d[2] > .1))
            h, hr = (.14, 0, .84), (.37, .35, .32)
            E(*h, *hr, 'head'); fluff(b, h, hr, 36, .07, .03, 'down', 2, lambda d: d[0] > .35)
            b.eyes2(h, hr, .105, 36, 8)
            E(.52, 0, .80, .13, .075, .05, 'beak', (0, .15, 0)); E(.50, 0, .74, .10, .06, .035, 'beak2')
            E(.40, 0, .88, .03, .03, .02, 'beak2')
            b.E2(.40, .28, .74, .045, .03, .045, 'down')
            for i, (y, ln) in enumerate(((-.07, .20), (0, .30), (.07, .20))):
                b.blade((.08, y, 1.12), (-.25, y * 3, 1), ln, .05, 'f2' if i != 1 else 'f3')
            for sg in (-1, 1):
                E(-.02, sg * .35, .50, .10, .16, .14, 'body', (sg * .3, 0, 0))
                for i in range(3):
                    b.blade((-.04, sg * .42, .48 + i * .02), (-.55, sg * (.55 + i * .2), .3 + i * .25), .20, .045, ('f2', 'f3', 'f2')[i])
                L((.06, sg * .12, .24), (.08, sg * .12, .08), .04, .03, 'leg')
                b.toes((.08, 0, .06), sg * .12, 3, .12, .022, 'leg')
            for i, y in enumerate((-.18, 0, .18)):
                b.blade((-.30, y * .5, .36), (-1, y * 1.2, .5), .28, .05, ('f2', 'f3', 'f2')[i])
        elif st == 1:                                            # slimmer fledgling, real wings, long tail
            E(0, 0, .62, .30, .27, .44, 'body', (0, .2, 0)); E(.12, 0, .56, .20, .20, .34, 'belly', (0, .2, 0))
            fluff(b, (0, 0, .62), (.30, .27, .44), 50, .07, .03, 'down', 3, lambda d: d[2] > .75 or (d[0] > .6 and d[2] > .3))
            E(.12, 0, 1.0, .16, .15, .20, 'body', (0, .25, 0))
            h, hr = (.22, 0, 1.2), (.30, .27, .25)
            E(*h, *hr, 'head'); b.eyes2(h, hr, .09, 38, 8)
            E(.50, 0, 1.15, .14, .06, .04, 'beak', (0, .15, 0)); E(.48, 0, 1.09, .10, .05, .03, 'beak2')
            for i, (y, ln) in enumerate(((-.09, .28), (0, .40), (.09, .28))):
                b.blade((.14, y, 1.40), (-.5, y * 3, 1), ln, .045, ('f2', 'f4', 'f2')[i])
            for sg in (-1, 1):
                E(0, sg * .27, .84, .10, .13, .10, 'body')
                wing_fan(b, sg, (-.04, sg * .30, .84), 9, .62, .10, -.5, 1.0, .6, ['f1', 'f1', 'f2', 'f2', 'f3'], .9, True)
                wing_fan(b, sg, (-.02, sg * .28, .78), 7, .34, .09, -.3, .8, .5, ['body'], .9)
                E(-.12, sg * .2, .52, .13, .09, .22, 'body')
                L((-.02, sg * .13, .38), (.04, sg * .13, .24), .045, .035, 'leg'); L((.04, sg * .13, .24), (.08, sg * .13, .07), .03, .025, 'leg')
                b.toes((.08, 0, .05), sg * .13, 3, .16, .024, 'leg')
            for i in range(4):
                y = (i - 1.5) * .16
                b.blade((-.32, 0, .50), (-1, y, -.05 + i * .06), .58, .09, ('f1', 'f2', 'f2', 'f1')[i], .026)
        else:                                                    # solar phoenix: tall, long neck, wings spread, flame train
            E(0, 0, .72, .33, .29, .46, 'body', (0, .15, 0)); E(.15, 0, .70, .22, .24, .38, 'gold', (0, .15, 0))
            fluff(b, (0, 0, .72), (.33, .29, .46), 50, .08, .03, 'f3', 4, lambda d: d[2] > .8 or d[0] > .4)
            b.chain([(.10, 0, 1.06, .17), (.20, 0, 1.24, .13), (.26, 0, 1.40, .115)], 'body')
            h, hr = (.32, 0, 1.54), (.27, .24, .22)
            E(*h, *hr, 'head'); b.eyes2(h, hr, .085, 40, 6)
            E(.58, 0, 1.48, .17, .06, .045, 'beak', (0, .22, 0)); E(.54, 0, 1.42, .12, .05, .03, 'beak2')
            L((.66, 0, 1.46), (.72, 0, 1.38), .03, .008, 'beak', 5)
            for i in range(5):
                y = (i - 2) * .07
                b.blade((.22, y, 1.70), (-.45 - abs(y) * 2, y * 5, 1), .50 - abs(i - 2) * .06, .075, ('f2', 'f3', 'f4', 'f3', 'f2')[i], .026)
            for sg in (-1, 1):
                E(0, sg * .26, .94, .14, .16, .14, 'body')
                wing_fan(b, sg, (-.04, sg * .30, .94), 11, 1.05, .13, -.25, 1.15, .3, ['f1', 'f1', 'f2', 'f2', 'f3', 'f4'], .95, True)
                wing_fan(b, sg, (-.02, sg * .28, .88), 9, .55, .12, -.15, 1.0, .25, ['body', 'body', 'f2'], .95)
                E(-.02, sg * .13, .42, .09, .08, .14, 'body')
                L((-.02, sg * .13, .40), (.04, sg * .13, .24), .05, .035, 'gold'); L((.04, sg * .13, .24), (.08, sg * .13, .08), .035, .025, 'leg')
                b.toes((.08, 0, .05), sg * .13, 3, .18, .028, 'leg')
            for i in range(5):
                y = (i - 2) * .14
                b.blade((-.30, 0, .56), (-1, y, -.25 + i * .02), 1.0 - abs(i - 2) * .12, .11, ('f1', 'f2', 'f3', 'f2', 'f1')[i], .026)
            for (x, y, z) in ((.3, .9, 1.6), (-.4, -.9, 1.9), (.1, 1.2, 1.0), (-.5, .8, 2.0), (.4, -1.0, 1.4)):
                b.E(x, y, z, .035, .035, .035, 'glow')
    return pal, build


# ═══════════════════ BLOSSOMFAWN → BLOOMSTAG → BLOSSOMKING ═══════════════════
def blossomfawn(st):
    pal = dict(body=['#c8844c', '#b87240', '#a05f36'][st], belly=['#f6e6cc', '#f2dcc0', '#ecd0b0'][st], limb=['#a8703c', '#965e34', '#80502c'][st],
               hoof='#4a3828', dots='#fff3de', wood=['#8a6a44', '#7a5a38', '#6a4a30'][st], pink='#f6a6c4', pink2='#ffd6e4',
               leaf='#5fb04a', leaf2='#7fd05a', nosec='#2a2018',
               glow=('#fff0a0', '#ffc840', 1.6), glow2=('#ffd6e4', '#ff9ac0', 1.4))

    def build(b):
        E, L = b.E, b.L
        if st == 0:                                               # spotted fawn with antler buds
            E(0, 0, .46, .40, .26, .25, 'body'); E(.10, 0, .40, .30, .19, .18, 'belly')
            dots(b, (0, 0, .46), (.40, .26, .25), [(60, 40), (90, 55), (120, 40), (30, 60), (150, 55), (-60, 40), (-90, 55), (-120, 40), (-30, 60), (-150, 55), (100, 20), (-100, 20), (180, 50)], .045, 'dots')
            fluff(b, (0, 0, .46), (.40, .26, .25), 30, .05, .02, 'body', 5, lambda d: d[2] < 0)
            b.chain([(.30, 0, .58, .14), (.38, 0, .74, .12)], 'body')
            h, hr = (.44, 0, .90, ), (.27, .24, .22)
            E(*h, *hr, 'body'); E(.64, 0, .82, .13, .10, .09, 'belly'); E(.76, 0, .84, .035, .04, .03, 'nosec')
            b.eyes2(h, hr, .10, 36, 10)
            b.E2(.38, .22, 1.03, .06, .10, .17, 'body', (.7, 0, 0)); b.E2(.38, .21, 1.03, .03, .06, .12, 'belly', (.7, 0, 0))
            for sg in (-1, 1):
                L((.44, sg * .08, 1.08), (.40, sg * .10, 1.22), .035, .025, 'wood'); blossom(b, (.40, sg * .10, 1.26), .08)
            for x in (.26, -.28):
                for sg in (-1, 1):
                    if x > 0:
                        L((x, sg * .15, .40), (x + .02, sg * .15, .20), .05, .035, 'limb'); L((x + .02, sg * .15, .20), (x + .03, sg * .15, .07), .032, .028, 'limb')
                    else:
                        L((x, sg * .15, .40), (x - .06, sg * .15, .24), .06, .04, 'limb'); L((x - .06, sg * .15, .24), (x - .02, sg * .15, .07), .034, .028, 'limb')
                    E(x + .03, sg * .15, .045, .06, .045, .045, 'hoof')
            E(-.42, 0, .54, .07, .07, .10, 'belly', (0, -.4, 0))
        elif st == 1:                                             # buck: taller, branched antlers, flower collar
            E(0, 0, .66, .44, .27, .26, 'body'); E(.12, 0, .60, .32, .20, .19, 'belly')
            dots(b, (0, 0, .66), (.44, .27, .26), [(70, 45), (110, 45), (-70, 45), (-110, 45), (150, 50), (-150, 50)], .04, 'dots')
            fluff(b, (0, 0, .66), (.44, .27, .26), 36, .05, .02, 'body', 6, lambda d: d[2] < 0)
            b.chain([(.34, 0, .80, .15), (.44, 0, 1.00, .13), (.50, 0, 1.18, .12)], 'body')
            E(.58, 0, 1.0, .12, .12, .22, 'belly', (0, .3, 0)); fluff(b, (.50, 0, .96), (.14, .14, .24), 18, .08, .03, 'belly', 7, lambda d: d[0] < .1)
            h, hr = (.56, 0, 1.30), (.26, .22, .21)
            E(*h, *hr, 'body'); E(.76, 0, 1.22, .13, .10, .09, 'belly'); E(.88, 0, 1.24, .035, .04, .03, 'nosec')
            b.eyes2(h, hr, .09, 36, 10)
            b.E2(.50, .22, 1.44, .055, .10, .17, 'body', (.7, 0, 0))
            for sg in (-1, 1):
                bl = []
                antler(b, (.52, sg * .08, 1.46), (-.2, sg * .25, 1), .26, .035, 1, bl, sg)
                for p in bl:
                    blossom(b, p, .07)
            for i in range(6):
                a = i / 6 * 2 * math.pi
                blossom(b, (.46 + math.cos(a) * .15, math.sin(a) * .15, 1.0 + (i % 2) * .05), .05)
            for x in (.30, -.32):
                for sg in (-1, 1):
                    if x > 0:
                        L((x, sg * .16, .60), (x + .02, sg * .16, .32), .055, .04, 'limb'); L((x + .02, sg * .16, .32), (x + .03, sg * .16, .08), .035, .03, 'limb')
                    else:
                        L((x, sg * .16, .60), (x - .08, sg * .16, .36), .068, .045, 'limb'); L((x - .08, sg * .16, .36), (x - .03, sg * .16, .09), .036, .03, 'limb')
                    E(x + .04, sg * .16, .05, .065, .048, .05, 'hoof')
            E(-.46, 0, .74, .08, .08, .12, 'belly', (0, -.5, 0))
            for (x, y, z) in ((.1, .26, .88), (-.2, -.25, .86)):
                blossom(b, (x, y, z), .06)
        else:                                                     # blossom king: tall, antler tree, petal cape
            E(0, 0, .84, .46, .28, .28, 'body'); E(.14, 0, .76, .34, .22, .21, 'belly')
            fluff(b, (0, 0, .84), (.46, .28, .28), 50, .06, .022, 'body', 8, lambda d: d[2] < 0)
            b.chain([(.36, 0, 1.0, .17), (.48, 0, 1.24, .14), (.56, 0, 1.46, .12)], 'body')
            E(.62, 0, 1.24, .15, .15, .30, 'belly', (0, .3, 0)); fluff(b, (.56, 0, 1.2), (.17, .17, .32), 30, .1, .03, 'belly', 9, lambda d: d[0] < .1)
            h, hr = (.64, 0, 1.62), (.25, .21, .20)
            E(*h, *hr, 'body'); E(.83, 0, 1.54, .12, .09, .085, 'belly'); E(.94, 0, 1.56, .035, .04, .03, 'nosec')
            b.eyes2(h, hr, .085, 36, 10)
            b.E2(.58, .22, 1.76, .055, .10, .17, 'body', (.7, 0, 0))
            for sg in (-1, 1):
                bl = []
                antler(b, (.60, sg * .08, 1.78), (-.15, sg * .3, 1), .36, .042, 2, bl, sg)
                for p in bl:
                    blossom(b, p, .075)
            for i in range(9):
                t = i / 8
                blossom(b, (.5 - t * .9, 0, 1.14 - t * .02 + math.sin(t * 6) * .02), .055)
            for sg in (-1, 1):
                for i in range(5):
                    b.blade((.10 - i * .14, sg * .24, 1.08 - i * .02), (-.3, sg * .7, -.6), .24, .06, 'leaf' if i % 2 == 0 else 'leaf2')
            for x in (.34, -.36):
                for sg in (-1, 1):
                    if x > 0:
                        L((x, sg * .17, .84), (x + .02, sg * .17, .44), .062, .042, 'limb'); L((x + .02, sg * .17, .44), (x + .03, sg * .17, .09), .038, .03, 'limb')
                    else:
                        L((x, sg * .17, .84), (x - .10, sg * .17, .50), .075, .05, 'limb'); L((x - .10, sg * .17, .50), (x - .04, sg * .17, .10), .04, .03, 'limb')
                    E(x + .04, sg * .17, .055, .07, .05, .055, 'hoof')
            E(-.50, 0, .96, .10, .09, .16, 'belly', (0, -.5, 0))
            for (x, y, z) in ((.3, .6, 1.8), (-.2, -.7, 1.6), (.6, -.5, 2.0), (-.4, .6, 1.9), (.1, .5, 2.2), (.7, .4, 1.4)):
                b.E(x, y, z, .04, .03, .02, 'pink', (.5, .3, .2))
    return pal, build


# ═══════════════════ ICEPAW → FROSTBEAR → GLACIERBEAR ═══════════════════
def icepaw(st):
    pal = dict(body=['#a8724a', '#9a6642', '#8a5a3c'][st], belly='#e8cdb0', paw='#7a5236', muzzle='#e8cdb0', inner='#e8b49a',
               plate='#bfe6ff', plate2='#e4f6ff', frost='#eef8ff', **ICE)

    def build(b):
        E, L = b.E, b.L
        nose = 'nose'
        if st == 0:                                               # round cub with crystal-tipped paws
            E(0, 0, .42, .36, .31, .34, 'body'); E(.14, 0, .36, .24, .22, .26, 'belly')
            fluff(b, (0, 0, .42), (.36, .31, .34), 40, .06, .025, 'body', 11, lambda d: d[2] > .75)
            h, hr = (.28, 0, .80), (.36, .34, .31)
            E(*h, *hr, 'body'); fluff(b, h, hr, 40, .06, .025, 'body', 12, lambda d: d[0] > .45)
            E(.58, 0, .72, .16, .13, .11, 'muzzle'); E(.72, 0, .74, .045, .06, .04, 'nose')
            L((.70, 0, .66), (.70, 0, .62), .01, .008, 'nose', 5)
            b.eyes2(h, hr, .10, 36, 10)
            b.E2(.20, .27, 1.04, .10, .07, .10, 'body'); b.E2(.22, .26, 1.04, .06, .04, .06, 'inner')
            b.E2(.50, .15, .60, .05, .04, .03, 'inner')
            for sg in (-1, 1):
                b.leg((.12, sg * .26, .44), (.22, sg * .20, .12), .10, 'body'); E(.30, sg * .20, .07, .15, .105, .07, 'paw')
                for k in (-1, 0, 1):
                    b.spike(.42, sg * .20 + k * .05, .09, .13, .035, 1.35, 0, 'glow' if k == 0 else 'glow2')
                b.leg((-.20, sg * .24, .42), (-.22, sg * .22, .12), .115, 'body'); E(-.14, sg * .22, .07, .17, .11, .07, 'paw')
                b.toes((-.04, 0, .06), sg * .22, 3, .09, .022, 'paw', True)
            E(-.38, 0, .30, .09, .09, .09, 'body')
            for (x, y, z) in ((.1, .2, .74), (-.1, -.2, .72), (-.25, .1, .70)):
                E(x, y, z, .04, .035, .02, 'frost')
        elif st == 1:                                             # frost bear: shoulder crystals, ice ruff, ice-coated paws
            E(0, 0, .62, .42, .34, .36, 'body'); E(.16, 0, .54, .28, .24, .27, 'belly')
            E(.10, 0, .84, .30, .30, .20, 'body')                  # shoulder hump
            fluff(b, (0, 0, .62), (.42, .34, .36), 40, .07, .028, 'body', 13, lambda d: d[2] > .8)
            h, hr = (.40, 0, .92), (.33, .30, .28)
            E(*h, *hr, 'body'); fluff(b, h, hr, 36, .06, .025, 'body', 14, lambda d: d[0] > .45)
            E(.68, 0, .84, .17, .13, .11, 'muzzle'); E(.83, 0, .86, .045, .06, .04, 'nose')
            b.eyes2(h, hr, .09, 36, 10)
            b.E2(.30, .25, 1.14, .09, .06, .09, 'body'); b.E2(.32, .24, 1.14, .05, .04, .05, 'inner')
            for i in range(9):                                      # ice ruff around the neck
                a = (i - 4) / 9 * math.pi * 1.1
                b.spike(.20, math.sin(a) * .34, .86 + math.cos(a) * .22 - .12, .14, .05, math.cos(a) * .7 + .3, math.sin(a) * 1.0, 'glow' if i % 2 else 'plate')
            for sg in (-1, 1):
                for k in range(3):
                    b.spike(.0 - k * .10, sg * (.32 + k * .02), .94 - k * .06, .24 - k * .03, .065, .1, sg * .8, 'plate' if k % 2 == 0 else 'glow')
                b.leg((.18, sg * .30, .56), (.30, sg * .24, .16), .12, 'body'); E(.38, sg * .22, .09, .19, .13, .09, 'plate')
                for k in (-1, 0, 1):
                    L((.50, sg * .22 + k * .06, .10), (.62, sg * .22 + k * .06, .05), .03, .008, 'plate2', 5)
                b.leg((-.22, sg * .26, .56), (-.24, sg * .24, .16), .135, 'body'); E(-.14, sg * .24, .08, .20, .13, .08, 'paw')
                b.toes((.0, 0, .07), sg * .24, 3, .10, .026, 'paw', True)
            for i in range(5):
                b.spike(.0 - i * .12, 0, .92 - i * .02, .22 + .04 * (i % 2), .06, .15, 0, 'plate' if i % 2 else 'glow')
            E(-.46, 0, .42, .10, .10, .10, 'body'); b.spike(-.52, 0, .42, .14, .05, 1.2, 0, 'glow')
        else:                                                     # glacier bear: massive, ice armour plates, crystal crown
            E(0, 0, .80, .50, .40, .42, 'body'); E(.18, 0, .70, .34, .30, .32, 'belly')
            E(.14, 0, 1.08, .36, .36, .24, 'body')
            fluff(b, (0, 0, .80), (.50, .40, .42), 45, .08, .03, 'body', 15, lambda d: d[2] > .8)
            h, hr = (.48, 0, 1.18), (.34, .31, .29)
            E(*h, *hr, 'body'); fluff(b, h, hr, 30, .06, .025, 'body', 16, lambda d: d[0] > .45)
            E(.78, 0, 1.08, .18, .14, .12, 'muzzle'); E(.94, 0, 1.10, .05, .065, .045, 'nose')
            b.eyes2(h, hr, .088, 36, 10)
            E(.62, 0, .92, .08, .10, .08, 'glow')                   # frost breath gathering at the jaw
            b.E2(.38, .27, 1.40, .09, .06, .09, 'body')
            for i, (y, ln) in enumerate(((-.12, .30), (0, .46), (.12, .30), (-.22, .20), (.22, .20))):
                b.spike(.40, y, 1.40, ln, .065, .15 + abs(y), y * 1.2, 'plate' if i % 2 else 'glow')
            for i in range(7):                                      # overlapping ice plates down the back
                b.blade((.28 - i * .14, 0, 1.2 - i * .035), (-.4, 0, 1), .44 - i * .02, .15, 'plate' if i % 2 == 0 else 'plate2', .035)
            for sg in (-1, 1):
                for k in range(4):
                    b.spike(.12 - k * .08, sg * (.38 + k * .02), 1.14 - k * .05, .36 - k * .04, .08, .2, sg * 1.0, 'plate' if k % 2 == 0 else 'glow')
                b.leg((.22, sg * .34, .74), (.34, sg * .28, .22), .15, 'body'); E(.42, sg * .26, .11, .23, .15, .10, 'plate')
                for k in (-1, 0, 1):
                    L((.58, sg * .26 + k * .07, .12), (.74, sg * .26 + k * .07, .05), .035, .008, 'plate2', 5)
                b.leg((-.26, sg * .30, .74), (-.28, sg * .28, .22), .165, 'body'); E(-.18, sg * .28, .10, .24, .15, .09, 'paw')
                b.toes((.02, 0, .08), sg * .28, 3, .12, .03, 'paw', True)
            E(.40, 0, .90, .14, .20, .16, 'glow')                   # glowing chest crystal
            b.spike(.50, 0, .84, .22, .08, 1.0, 0, 'glow')
            E(-.52, 0, .54, .12, .12, .12, 'body')
            for i in range(3):
                b.spike(-.58, 0, .54 + i * .02, .2 + i * .06, .05, 1.1 + i * .15, (i - 1) * .4, 'plate')
    return pal, build


# ═══════════════════ DUSKHOOD → NIGHTCOBRA → ECLIPSECOBRA ═══════════════════
def duskhood(st):
    pal = dict(body=['#46445e', '#3a3852', '#2c2a44'][st], belly='#a8a4c8', hood=['#54526e', '#48466c', '#363458'][st], band='#6a68a0',
               eye='#ffe070', ring='#1a1830', **PUR)

    def build(b):
        E, L = b.E, b.L
        r = [.15, .18, .22][st]
        turns = [1.6, 2.1, 2.5][st]
        n = int(26 + turns * 8)
        pts = []
        for i in range(n):
            t = i / (n - 1)
            a = t * turns * 2 * math.pi + 1.2
            R = (.62 + .1 * st) * (1 - t * .78)
            rad = r * (.28 + .72 * min(1, t * 1.6))
            pts.append((-.22 + math.cos(a) * R, math.sin(a) * R, rad + .01 + t * .06, rad))
        b.chain(pts, 'body')
        for i in range(2, n, 3):                                  # dorsal scale bands
            x, y, z, rad = pts[i]
            E(x, y, z + rad * .72, rad * .42, rad * .42, rad * .34, 'band')
        neck_r = r
        lift = [.70, .92, 1.14][st]
        neck = [(pts[-1][0], pts[-1][1], r, neck_r), (-.2, 0, lift * .35, neck_r), (-.14, 0, lift * .62, neck_r * .94),
                (-.02, 0, lift * .82, neck_r * .86), (.10, 0, lift * .96, neck_r * .8)]
        b.chain(neck, 'body')
        hx, hz = .26, lift + .14
        for k in range(8):                                        # pale throat plates down the front of the neck
            t = k / 7
            E(.0 + t * .22 + .06, 0, lift * (.35 + t * .6) + .02, neck_r * .5, neck_r * .7, neck_r * .42, 'belly')
        wh = [.30, .38, .50][st]
        E(hx - .12, 0, hz - .12, .06, wh, wh * .95, 'hood')                          # flared hood
        for sg in (-1, 1):
            E(hx - .10, sg * wh * .86, hz - .20, .06, wh * .35, wh * .5, 'hood')
        E(hx + .10, 0, hz, .24, .20, .17, 'body')
        E(hx + .30, 0, hz - .06, .12, .13, .08, 'body')
        b.eyes2((hx + .10, 0, hz), (.24, .20, .17), .085, 40, 10)
        for sg in (-1, 1):
            L((hx + .34, sg * .04, hz - .10), (hx + .35, sg * .05, hz - .20 - .03 * st), .018, .004, 'ivory', 5)
        L((hx + .38, 0, hz - .10), (hx + .50, 0, hz - .12), .008, .006, 'glow', 5)
        for sg in (-1, 1):
            L((hx + .50, 0, hz - .12), (hx + .58, sg * .04, hz - .13), .006, .004, 'glow', 5)
        if st >= 1:
            for sg in (-1, 1):                                      # chevrons on the hood
                for k in range(3):
                    E(hx - .05, sg * (wh * (.35 + k * .22)), hz - .08 - k * .05, .015, .05, .015, 'glow', (0, 0, sg * .8))
        if st == 2:
            cx, cz = hx - .04, hz - .14
            for k in range(14):                                     # eclipse ring on the hood
                a = k / 14 * 2 * math.pi
                E(cx - .02, math.sin(a) * wh * .82, cz + math.cos(a) * wh * .82, .04, .04, .04, 'glow2')
            E(cx - .04, 0, cz, .03, wh * .72, wh * .72, 'ring')
            for k in range(4):
                b.spike(hx + .10 - k * .05, 0, hz + .15, .2 - k * .03, .045, .3 + k * .25, 0, 'glow')
            for k in range(6):
                t = (k + 1) / 7
                b.spike(-.2 + t * .25, 0, lift * (.2 + t * .7), .16, .04, .4, 0, 'glow2')
            for (x, y, z) in ((.5, .6, 1.2), (-.6, -.5, 1.5), (.2, -.7, 1.7)):
                E(x, y, z, .07, .07, .04, 'glow')
        if st == 0:
            E(pts[0][0], pts[0][1], pts[0][2] + .08, .05, .05, .05, 'glow')
    return pal, build


SPECIES = {'cinderchick': cinderchick, 'blossomfawn': blossomfawn, 'icepaw': icepaw, 'duskhood': duskhood}


def render_stage(name, st, out, samples, size):
    ob = build_stage(name, st)
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
    K.render(os.path.join(out, '%s_s%d.png' % (name, st)))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--stages', default='0,1,2')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=48)
    ap.add_argument('--size', type=int, default=720)
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    import traceback
    for n in [n for n in a.only.split(',') if n] or list(SPECIES):
        for st in [int(s) for s in a.stages.split(',')]:
            try:
                render_stage(n, st, a.out, a.samples, a.size)
            except Exception:
                print('FAILED', n, st)
                traceback.print_exc()


if __name__ == '__main__':
    main()
