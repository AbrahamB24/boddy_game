"""Anatomically plausible versions: real wings (arm bones + layered feathers), plantigrade bears,
deer with proper joints, ice as hexagonal crystals. Fantasy only in colour, glow and small extras.

    blender --background --python tool/blender/monsters_real.py -- --only cinderchick --out docs/renders/monsters/real
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monsters_all as ma  # noqa: E402
import monsters_detail as md  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402

FIRE = ma.FIRE
ICE = ma.ICE


def basis_euler(d, n):
    x = Vector(d).normalized()
    n = Vector(n)
    z = (n - x * n.dot(x))
    if z.length < 1e-4:
        z = Vector((0, 0, 1)) if abs(x.z) < .9 else Vector((0, 1, 0))
        z = z - x * z.dot(x)
    z.normalize()
    y = z.cross(x)
    return tuple(Matrix((x, y, z)).transposed().to_euler())


def samples(P, n):
    segs = [(P[i + 1] - P[i]).length for i in range(len(P) - 1)]
    tot = sum(segs)
    out = []
    for k in range(n):
        s = (k + .5) / n * tot
        i = 0
        while i < len(segs) - 1 and s > segs[i]:
            s -= segs[i]
            i += 1
        out.append(P[i] + (P[i + 1] - P[i]) * (s / segs[i]))
    return out


class R(md.D):
    def feather(s, p, d, length, width, m, norm=None, thick=None):
        """One feather: long vane, rounded tip. norm = the direction the flat face looks."""
        d = Vector(d).normalized()
        p = Vector(p)
        thick = thick or max(.012, length * .03)
        eul = basis_euler(d, norm if norm is not None else Vector((0, 0, 1)))
        c = p + d * length * .46
        s.E(c.x, c.y, c.z, length * .46, width, thick, m, eul)
        c2 = p + d * length * .86
        s.E(c2.x, c2.y, c2.z, length * .14, width * .82, thick, m, eul)

    def crystal(s, p, d, length, r, m):
        """Hexagonal prism with a pointed termination, like real quartz or ice."""
        d = Vector(d).normalized()
        p = Vector(p)
        a = p + d * length * .72
        s.L(p, a, r, r * .95, m, seg=6)
        s.L(a, p + d * length, r * .95, .004, m, seg=6)

    def cluster(s, p, d, length, r, n, seed, m1, m2):
        rng = random.Random(seed)
        d = Vector(d).normalized()
        s.crystal(p, d, length, r, m1)
        for i in range(n - 1):
            q = (d + Vector((rng.uniform(-.7, .7), rng.uniform(-.7, .7), rng.uniform(-.2, .5)))).normalized()
            s.crystal(Vector(p) + Vector((rng.uniform(-.03, .03), rng.uniform(-.03, .03), 0)), q,
                      length * rng.uniform(.45, .8), r * rng.uniform(.6, .85), m2 if i % 2 == 0 else m1)


def plumage(b, c, r, rows, size, mats, seed, skip=None, flow=(-1, 0, -.35), width=.36):
    """Contour feathers laid like roof tiles over an ellipsoid, flowing head to tail."""
    rng = random.Random(seed)
    k = 0
    for ri in range(rows):
        lat = -75 + 150 * (ri + .5) / rows
        la = math.radians(lat)
        cnt = max(4, int(rows * 1.7 * math.cos(la) * 2))
        for ci in range(cnt):
            az = (ci + (.5 if ri % 2 else 0)) / cnt * 2 * math.pi
            d = (math.cos(la) * math.cos(az), math.cos(la) * math.sin(az), math.sin(la))
            if skip and skip(d):
                continue
            p = Vector((c[0] + r[0] * d[0], c[1] + r[1] * d[1], c[2] + r[2] * d[2]))
            nrm = Vector((d[0] / r[0], d[1] / r[1], d[2] / r[2])).normalized()
            fv = Vector(flow)
            t = fv - nrm * fv.dot(nrm)
            if t.length < .15:
                continue
            sz = size * rng.uniform(.85, 1.15)
            b.feather(p - nrm * sz * .05 - t.normalized() * sz * .15, t, sz, sz * width, mats[k % len(mats)], nrm, sz * .1)
            k += 1


def wing(b, path, T, N, flen, mats, covers=3, fan=.9, wmul=.085):
    """A bird wing: arm skeleton (shoulder, elbow, wrist, hand tip), secondaries along the forearm,
    primaries fanned along the hand, and rows of coverts overlapping their bases."""
    P = [Vector(p) for p in path]
    T = Vector(T).normalized()
    N = Vector(N).normalized()
    seg = [(P[i + 1] - P[i]).length for i in range(3)]
    Hd = (P[3] - P[2]).normalized()
    b.chain([(p.x, p.y, p.z, flen * .075) for p in P[:3]] + [(P[3].x, P[3].y, P[3].z, flen * .04)], mats[0])
    for pos in samples(P[:3], max(5, int((seg[0] + seg[1]) / (flen * .16)))):
        b.feather(pos - N * .012, T, flen * .74, flen * wmul, mats[0], N)
    npri = max(5, int(seg[2] / (flen * .15)))
    for i, pos in enumerate(samples(P[2:], npri)):
        u = (i + .5) / npri
        d = (T + Hd * fan * u).normalized()
        ln = flen * (.95 + .3 * math.sin(math.pi * (.1 + .8 * u)))
        mi = 1 + min(len(mats) - 2, int(u * (len(mats) - 1)))
        b.feather(pos - N * .014, d, ln, flen * wmul, mats[mi], N)
    for r in range(covers):
        f = flen * (.50 - .13 * r)
        for i, pos in enumerate(samples(P, max(5, int(sum(seg) / (f * .30))))):
            b.feather(pos + N * (.012 * (r + 1)) - T * flen * .05 * r, T, f, f * .21, mats[0] if r else mats[1], N)


def tail(b, root, base, n, spread, length, mats, N=(0, 0, 1), glow_tip=False):
    base = Vector(base).normalized()
    for i in range(n):
        u = (i - (n - 1) / 2) / max(1, (n - 1) / 2)
        d = (base + Vector((0, u * spread, -abs(u) * .05))).normalized()
        ln = length * (1 - .18 * abs(u))
        b.feather(root, d, ln, length * .075, mats[min(len(mats) - 1, int(abs(u) * len(mats)))], N)
        if glow_tip:
            tip = Vector(root) + d * ln * .93
            b.E(tip.x, tip.y, tip.z, .035, .03, .02, 'glow')


def bird_foot(b, ankle, y, size, m='leg', claw='ivory'):
    for ang in (-.5, 0, .5):
        tip = (ankle[0] + math.cos(ang) * size, y + math.sin(ang) * size * .9, .035)
        b.L(ankle, tip, .026, .02, m, seg=6)
        b.L(tip, (tip[0] + .05, tip[1] + math.sin(ang) * .02, .0), .018, .004, claw, seg=5)
    b.L(ankle, (ankle[0] - size * .55, y, .035), .024, .018, m, seg=6)
    b.L((ankle[0] - size * .55, y, .035), (ankle[0] - size * .55 - .04, y, .0), .016, .004, claw, seg=5)


def build_stage(name, st):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tw.SMOOTH_MATS = True
    tw.DEPTH = 9
    pal, build = SPECIES[name](st)
    b = R(pal, 1.0)
    build(b)
    return tw.voxelise(b.objs)


# ═══════════════════ CINDERCHICK → FLAMEWING → SOLARPHOENIX ═══════════════════
def cinderchick(st):
    pal = dict(body=['#d8402c', '#cc3624', '#bc2a1e'][st], head=['#e2503a', '#d84426', '#c83420'][st], belly=['#f4b45a', '#f6bc5c', '#ffd070'][st],
               beak='#f0a834', beak2='#c98a24', leg='#e8a030', gold='#ffc22e', cere='#f6d060', down='#ee6a48',
               f1='#c02a22', f2='#ee6a1c', f3='#ffb02a', f4='#ffe88a', **FIRE)

    def build(b):
        E, L = b.E, b.L
        if st == 0:                                              # plump chick
            c, r = (0, 0, .46), (.34, .31, .37)
            E(*c, *r, 'body'); E(.14, 0, .40, .22, .22, .29, 'belly')
            plumage(b, c, r, 9, .15, ['body', 'down'], 1, lambda d: d[2] > .78 or (d[0] > .55 and d[2] > .0), width=.4)
            h, hr = (.14, 0, .85), (.36, .34, .32)
            E(*h, *hr, 'head'); plumage(b, h, hr, 7, .11, ['head', 'down'], 2, lambda d: d[0] > .3, width=.4)
            b.eyes2(h, hr, .10, 40, 6)
            L((.45, 0, .82), (.64, 0, .77), .07, .012, 'beak'); L((.45, 0, .76), (.59, 0, .74), .05, .012, 'beak2')
            E(.42, 0, .84, .04, .04, .02, 'cere')
            for i, y in enumerate((-.07, 0, .07)):
                b.feather((.06, y, 1.12), (-.35, y * 3, 1), .22 + .08 * (i == 1), .045, ('f2', 'f3', 'f2')[i], (0, 1, 0))
            for sg in (-1, 1):
                path = [(0, sg * .31, .60), (-.12, sg * .34, .50), (.02, sg * .35, .52), (-.20, sg * .34, .42)]
                wing(b, path, (-1, 0, -.35), (0, sg, 0), .24, ['f1', 'f2', 'f3', 'f4'], 2, .8)
                E(0, sg * .12, .24, .09, .08, .12, 'body')
                L((.02, sg * .12, .22), (.05, sg * .12, .07), .034, .028, 'leg')
                bird_foot(b, (.05, sg * .12, .06), sg * .12, .13)
            tail(b, (-.30, 0, .38), (-1, 0, .25), 5, .5, .30, ['f1', 'f2', 'f3'], (0, 1, 0))
        elif st == 1:                                            # juvenile raptor-phoenix
            c, r = (0, 0, .74), (.29, .27, .43)
            E(*c, *r, 'body'); E(.11, 0, .70, .21, .22, .34, 'belly')
            plumage(b, c, r, 11, .17, ['body', 'f1'], 3, lambda d: d[2] > .8 or (d[0] > .45 and d[2] > .35), width=.4)
            b.chain([(.06, 0, 1.02, .15), (.11, 0, 1.15, .13)], 'body')
            h, hr = (.17, 0, 1.28), (.25, .22, .21)
            E(*h, *hr, 'head'); plumage(b, h, hr, 6, .10, ['head', 'body'], 4, lambda d: d[0] > .45, width=.4)
            b.eyes2(h, hr, .085, 46, 6)
            b.E2(.26, .14, 1.36, .09, .045, .03, 'head')                          # brow ridge
            b.chain([(.34, 0, 1.27, .07), (.46, 0, 1.25, .06), (.54, 0, 1.19, .045), (.57, 0, 1.11, .025)], 'beak')
            b.chain([(.34, 0, 1.21, .05), (.44, 0, 1.19, .04), (.50, 0, 1.17, .03)], 'beak2')
            E(.34, 0, 1.28, .05, .06, .03, 'cere')
            for i, y in enumerate((-.08, 0, .08)):
                b.feather((.08, y, 1.45), (-.45, y * 2.5, 1), .28 + .08 * (i == 1), .05, ('f2', 'f3', 'f2')[i], (0, 1, 0))
            for sg in (-1, 1):
                path = [(0, sg * .27, 1.0), (-.20, sg * .31, .84), (.06, sg * .31, .88), (-.26, sg * .29, .62)]
                wing(b, path, (-1, 0, -.42), (0, sg, 0), .52, ['f1', 'f1', 'f2', 'f3', 'f4'], 3, .9)
                E(.0, sg * .16, .46, .14, .11, .22, 'f1')                         # feathered thigh
                L((.02, sg * .14, .34), (.06, sg * .14, .08), .04, .03, 'leg')
                bird_foot(b, (.06, sg * .14, .07), sg * .14, .17)
            tail(b, (-.26, 0, .50), (-1, 0, -.32), 7, .55, .76, ['f1', 'f2', 'f3'], (0, 1, 0), True)
        else:                                                    # solar phoenix, wings raised
            c, r = (0, 0, .80), (.31, .28, .46)
            E(*c, *r, 'body'); E(.13, 0, .78, .22, .24, .38, 'gold')
            plumage(b, c, r, 12, .19, ['body', 'f1', 'f2'], 5, lambda d: d[2] > .8 or (d[0] > .45 and d[2] > .35), width=.4)
            b.chain([(.08, 0, 1.12, .17), (.14, 0, 1.30, .14), (.18, 0, 1.46, .12)], 'body')
            h, hr = (.24, 0, 1.60), (.25, .22, .21)
            E(*h, *hr, 'head'); plumage(b, h, hr, 6, .10, ['head', 'gold'], 6, lambda d: d[0] > .45, width=.4)
            b.eyes2(h, hr, .08, 46, 6)
            b.E2(.34, .14, 1.68, .09, .045, .03, 'head')
            b.chain([(.42, 0, 1.60, .075), (.55, 0, 1.58, .065), (.64, 0, 1.51, .048), (.67, 0, 1.42, .026)], 'beak')
            b.chain([(.42, 0, 1.54, .052), (.53, 0, 1.52, .042), (.60, 0, 1.50, .03)], 'beak2')
            E(.42, 0, 1.61, .05, .06, .03, 'cere')
            for i in range(5):
                y = (i - 2) * .075
                b.feather((.14, y, 1.76), (-.30 - abs(y) * 1.5, y * 3, 1), .50 - abs(i - 2) * .07, .055, ('f2', 'f3', 'f4', 'f3', 'f2')[i], (0, 1, 0))
            for sg in (-1, 1):
                path = [(0, sg * .28, 1.08), (-.06, sg * .62, 1.22), (-.20, sg * .98, 1.40), (-.40, sg * 1.30, 1.56)]
                wing(b, path, (-1, 0, -.18), (0, 0, 1), .88, ['f1', 'f1', 'f2', 'f3', 'f4'], 3, .9)
                E(.0, sg * .15, .50, .15, .12, .24, 'f1')
                L((.02, sg * .14, .38), (.07, sg * .14, .09), .045, .032, 'gold')
                bird_foot(b, (.07, sg * .14, .08), sg * .14, .20, 'gold')
            tail(b, (-.28, 0, .60), (-1, 0, -.26), 5, .38, 1.15, ['f1', 'f2', 'f3'], (0, 1, 0), True)
            for (x, y, z) in ((.2, .9, 1.9), (-.5, -.9, 1.9), (.1, 1.3, 1.2), (-.6, .6, 2.1)):
                E(x, y, z, .03, .03, .03, 'glow')
    return pal, build


# ═══════════════════ ICEPAW → FROSTBEAR → GLACIERBEAR ═══════════════════
def bear_leg(b, top, elbow, wrist, y, r, m, paw_m, toe_len, front=True, ice=None):
    E, L = b.E, b.L
    E(top[0], y, top[1], r * 1.4, r * 1.3, r * 1.5, m)
    L((top[0], y, top[1]), (elbow[0], y, elbow[1]), r * 1.1, r * .9, m)
    E(elbow[0], y, elbow[1], r * .95, r * .9, r * .95, m)
    L((elbow[0], y, elbow[1]), (wrist[0], y, wrist[1]), r * .9, r * .68, m)
    E(wrist[0], y, wrist[1], r * .72, r * .7, r * .72, m)
    px = wrist[0] + toe_len * .5
    E(px, y, .06, toe_len * .62, r * .95, .06, paw_m)
    for i in range(5):
        yy = y + (i - 2) * r * .36
        E(px + toe_len * .5, yy, .045, .028, .028, .026, paw_m)
        L((px + toe_len * .5, yy, .04), (px + toe_len * .5 + .06, yy, .015), .014, .004, 'ivory', seg=5)


def icepaw(st):
    pal = dict(body=['#a8724a', '#9a6642', '#8a5a3c'][st], body2=['#b8825a', '#aa7650', '#9a6a48'][st], belly='#e0c4a4', paw='#7a5236',
               muzzle='#e4cbae', inner='#e8b49a', plate='#b8e2fa', plate2='#dff3ff', frost='#f0f9ff', **ICE)

    def build(b):
        E, L = b.E, b.L
        S = [dict(z=.40, r=(.38, .30, .30), hx=.34, hz=.70, hr=(.34, .32, .30), top=.40, lr=.085, el=.20, toe=.10),
             dict(z=.56, r=(.44, .32, .34), hx=.42, hz=.92, hr=(.32, .29, .27), top=.56, lr=.10, el=.30, toe=.12),
             dict(z=.74, r=(.50, .36, .38), hx=.52, hz=1.18, hr=(.31, .28, .26), top=.74, lr=.125, el=.40, toe=.15)][st]
        z, r = S['z'], S['r']
        E(0, 0, z, *r, 'body')
        E(.14, 0, z - .07, r[0] * .66, r[1] * .78, r[2] * .74, 'belly')
        if st:
            E(r[0] * .32, 0, z + r[2] * .62, r[0] * .62, r[1] * .86, r[2] * .55, 'body')        # shoulder hump
        plumage(b, (0, 0, z), r, 9 + st * 2, .13 + .02 * st, ['body', 'body2'], 11, lambda d: d[2] < -.2, (-1, 0, -.2), .5)
        h, hr = (S['hx'], 0, S['hz']), S['hr']
        E(*h, *hr, 'body'); plumage(b, h, hr, 6, .09, ['body', 'body2'], 12, lambda d: d[0] > .35, (-1, 0, -.2), .5)
        mz = h[2] - hr[2] * .3
        E(h[0] + hr[0] * .66, 0, mz, hr[0] * .50, hr[1] * .50, hr[2] * .42, 'muzzle')
        E(h[0] + hr[0] * 1.04, 0, mz + .02, .045, .06, .04, 'nose')
        b.eyes2(h, hr, .085 - .008 * st, 40, 12)
        b.E2(h[0] - .08, hr[1] * .7, h[2] + hr[2] * .85, .085, .06, .085, 'body'); b.E2(h[0] - .06, hr[1] * .66, h[2] + hr[2] * .85, .05, .04, .05, 'inner')
        zt = S['top']
        for sg in (-1, 1):
            bear_leg(b, (r[0] * .55, zt), (r[0] * .55 + .04, S['el']), (r[0] * .55 + .02, .09), sg * r[1] * .72, S['lr'], 'body', 'paw', S['toe'])
            bear_leg(b, (-r[0] * .6, zt), (-r[0] * .6 - .08, S['el'] + .03), (-r[0] * .6 - .02, .09), sg * r[1] * .72, S['lr'] * 1.1, 'body', 'paw', S['toe'] * 1.15)
        E(-r[0] * .98, 0, z + .02, .10 + .02 * st, .09, .10, 'body')
        pk = r[0] * .55 + .02
        if st == 0:                                                 # small crystals on the front paws
            for sg in (-1, 1):
                b.cluster((pk + .06, sg * r[1] * .72, .10), (1, 0, .35), .15, .03, 3, 21 + sg, 'plate', 'glow')
            for (x, y) in ((.1, .18), (-.12, -.16), (-.22, .12)):
                E(x, y, z + r[2] * .92, .05, .04, .02, 'frost')
        elif st == 1:                                               # crystals growing from shoulders, spine and forearms
            for sg in (-1, 1):
                b.cluster((r[0] * .35, sg * r[1] * .6, z + r[2] * .95), (0, sg * .55, 1), .30, .045, 4, 31 + sg, 'plate', 'plate2')
                b.cluster((pk + .02, sg * r[1] * .72, S['el'] + .06), (.4, sg * .8, .6), .16, .03, 3, 33 + sg, 'plate2', 'glow')
                b.cluster((pk + .08, sg * r[1] * .72, .10), (1, 0, .3), .20, .035, 3, 35 + sg, 'plate', 'glow')
            for i in range(3):
                b.cluster((.0 - i * .16, 0, z + r[2] * (1.0 - .1 * i)), (-.1, 0, 1), .26 - .03 * i, .04, 3, 40 + i, 'plate', 'plate2')
        else:                                                       # adult: large formations, brow crystals, ice claws
            for sg in (-1, 1):
                b.cluster((r[0] * .35, sg * r[1] * .6, z + r[2] * 1.15), (0, sg * .5, 1), .52, .07, 5, 51 + sg, 'plate', 'plate2')
                b.cluster((pk + .02, sg * r[1] * .72, S['el'] + .08), (.4, sg * .8, .6), .26, .05, 4, 53 + sg, 'plate2', 'glow')
                b.cluster((pk + .10, sg * r[1] * .72, .12), (1, 0, .3), .28, .05, 3, 55 + sg, 'plate', 'glow')
                b.cluster((h[0] - .04, sg * hr[1] * .55, h[2] + hr[2] * .85), (-.2, sg * .6, 1), .30, .045, 3, 57 + sg, 'plate', 'plate2')
            for i in range(4):
                b.cluster((.10 - i * .17, 0, z + r[2] * (1.15 - .1 * i)), (-.15, 0, 1), .42 - .05 * i, .06, 4, 60 + i, 'plate', 'plate2')
            b.cluster((h[0] + .02, 0, h[2] + hr[2] * .92), (-.1, 0, 1), .34, .05, 3, 66, 'plate', 'glow')
            E(.30, 0, z - .02, .10, .16, .13, 'glow')
    return pal, build


# ═══════════════════ BLOSSOMFAWN → BLOOMSTAG → BLOSSOMKING ═══════════════════
def deer_leg(b, x, y, top, hock, fet, m='limb', r=.05, hind=False):
    E, L = b.E, b.L
    E(x, y, top, r * 1.5, r * 1.3, r * 1.9, m)
    if hind:
        L((x, y, top), (x - .09, y, hock), r * 1.15, r * .8, m)
        L((x - .09, y, hock), (x - .04, y, fet), r * .8, r * .55, m)
        E(x - .09, y, hock, r * .8, r * .7, r * .8, m)
    else:
        L((x, y, top), (x + .02, y, hock), r * 1.05, r * .62, m)
        E(x + .02, y, hock, r * .65, r * .6, r * .65, m)
        L((x + .02, y, hock), (x + .02, y, fet), r * .6, r * .5, m)
    xf = x - .04 if hind else x + .02
    E(xf, y, fet, r * .55, r * .5, r * .55, m)
    E(xf + .02, y, .05, .06, .042, .05, 'hoof')
    E(xf + .06, y, .035, .035, .038, .035, 'hoof')


def blossomfawn(st):
    pal = dict(body=['#c8844c', '#b87240', '#a05f36'][st], belly=['#f6e6cc', '#f2dcc0', '#ecd0b0'][st], limb=['#a8703c', '#965e34', '#80502c'][st],
               hoof='#3a2c20', dots='#fff3de', wood=['#8a6a44', '#7a5a38', '#6a4a30'][st], pink='#f6a6c4', pink2='#ffd6e4',
               leaf='#5fb04a', leaf2='#7fd05a', nosec='#2a2018',
               glow=('#fff0a0', '#ffc840', 1.6), glow2=('#ffd6e4', '#ff9ac0', 1.4))

    def build(b):
        E, L = b.E, b.L
        P = [dict(zc=.52, bl=.40, leg=(.40, .22, .11), hz=.92, nk=.30), dict(zc=.70, bl=.44, leg=(.58, .34, .13), hz=1.34, nk=.40),
             dict(zc=.86, bl=.46, leg=(.74, .44, .14), hz=1.62, nk=.46)][st]
        zc, bl = P['zc'], P['bl']
        E(0, 0, zc, bl, .26 + .01 * st, .25 + .01 * st, 'body')
        E(.20, 0, zc - .01, bl * .6, .24, .26, 'body'); E(-.2, 0, zc + .02, bl * .6, .24, .25, 'body')
        E(.08, 0, zc - .07, bl * .8, .20, .18, 'belly')
        plumage(b, (0, 0, zc), (bl, .26, .25), 8, .10, ['body'], 7, lambda d: d[2] < -.1, (-1, 0, -.2), .5)
        if st == 0:
            dots(b, (0, 0, zc), (bl, .26, .25), [(60, 40), (90, 55), (120, 40), (30, 62), (150, 55), (-60, 40), (-90, 55), (-120, 40), (-30, 62), (-150, 55), (100, 22), (-100, 22), (180, 52), (80, 70), (-80, 70)], .045, 'dots')
        elif st == 1:
            dots(b, (0, 0, zc), (bl, .26, .25), [(70, 50), (110, 50), (-70, 50), (-110, 50), (150, 55), (-150, 55)], .036, 'dots')
        top, hock, fet = P['leg']
        for sg in (-1, 1):
            deer_leg(b, bl * .62, sg * .15, top, hock, fet, r=.05 + .004 * st)
            deer_leg(b, -bl * .62, sg * .15, top, hock * .82, fet, r=.055 + .004 * st, hind=True)
        nk = P['nk']
        b.chain([(bl * .8, 0, zc + .06, .15), (bl * .8 + nk * .55, 0, zc + nk * .8, .12), (bl * .8 + nk * .85, 0, zc + nk * 1.4, .095)], 'body')
        if st:
            E(bl * .82, 0, zc - .02, .15, .17, .26, 'belly'); plumage(b, (bl * .84, 0, zc), (.17, .18, .27), 7, .10, ['belly'], 8, lambda d: d[0] < .2, (-1, 0, -.4), .5)
        hx, hz = bl * .8 + nk * .85 + .05, P['hz']
        h, hr = (hx, 0, hz), (.20, .16, .16)
        E(*h, *hr, 'body')
        b.chain([(hx + .10, 0, hz - .03, .12), (hx + .26, 0, hz - .08, .095), (hx + .38, 0, hz - .11, .075)], 'body')
        E(hx + .42, 0, hz - .10, .05, .06, .045, 'nosec'); E(hx + .30, 0, hz - .15, .08, .06, .03, 'belly')
        b.eyes2(h, hr, .075 if st else .09, 58, 14)
        b.E2(hx - .06, .16, hz + .12, .05, .10, .17, 'body', (.9, 0, 0)); b.E2(hx - .05, .155, hz + .12, .03, .07, .12, 'belly', (.9, 0, 0))
        if st == 0:
            for sg in (-1, 1):
                L((hx - .02, sg * .07, hz + .13), (hx - .05, sg * .09, hz + .24), .03, .022, 'wood'); blossom(b, (hx - .05, sg * .09, hz + .28), .075)
        else:
            for sg in (-1, 1):
                bl_ = []
                antler(b, (hx - .02, sg * .07, hz + .14), (-.25, sg * .3, 1), .30 + .08 * st, .035 + .006 * st, st, bl_, sg)
                for p in bl_:
                    blossom(b, p, .065 + .008 * st)
            n = 6 + 3 * st
            for i in range(n):
                t = i / (n - 1)
                a = t * math.pi
                blossom(b, (hx - .16 + math.cos(a) * 0.0, math.sin(a - math.pi / 2) * .22, hz - .20 + math.cos(a) * 0.0), .04) if False else None
            for i in range(5 + 3 * st):
                t = i / (4 + 3 * st)
                blossom(b, (bl * .5 - t * bl * 1.0, 0, zc + .26 + math.sin(t * 5) * .02), .05)
            if st == 2:
                for sg in (-1, 1):
                    for i in range(4):
                        b.feather((bl * .4 - i * .22, sg * .20, zc + .20), (-.2, sg * .9, -.7), .20, .05, 'leaf' if i % 2 == 0 else 'leaf2', (sg * .7, 0, .7), .02)
        E(-bl * .98, 0, zc + .10, .07, .06, .10, 'belly', (0, -.5, 0))
        if st == 2:
            for (x, y, z_) in ((.3, .6, 2.0), (-.2, -.7, 1.7), (.7, -.5, 2.1), (-.4, .6, 1.9), (.1, .5, 2.3), (.8, .4, 1.5)):
                E(x, y, z_, .04, .03, .02, 'pink', (.5, .3, .2))
    return pal, build


blossom = md.blossom
antler = md.antler
dots = md.dots

SPECIES = {'cinderchick': cinderchick, 'icepaw': icepaw, 'blossomfawn': blossomfawn, 'duskhood': md.duskhood}


def render_stage(name, st, out, samples_, size):
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
    sc.cycles.samples = samples_
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
    ap.add_argument('--samples', type=int, default=40)
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
