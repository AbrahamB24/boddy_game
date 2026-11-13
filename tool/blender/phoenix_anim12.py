"""Phoenix stages 1 (Flamewing) and 2 (Solarphoenix): jointed rig + ONE idle each, attack, hurt, walk.

    blender --background --python tool/blender/phoenix_anim12.py -- --stage 1 --out docs/renders/monsters/phoenix_anim/s1 \
        [--views front,map] [--headings se,ne] [--only idle,attack] [--samples 32] [--scale 1.0]
    ... --seams      every clip starts/ends in the rest pose (walk has in/out clips)
    ... --clearance  feet and wings never sink into the body, in any frame
    ... --still x.png --pose idle:0.4

Rules (memory 'animation-principles'): one idle per stage, all stages different (s1 = ruffle and shake, s2 = rear up
with wing beats and a roar); real breathing; the body is ONE mesh that breathing scales; a wing is an inner and an outer
part, the outer one lying one layer above the inner one so no two surfaces coincide; nothing may flicker, cut or sink.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_bake as gb  # noqa: E402
import monster_rig as mrg  # noqa: E402
import monsters_real as mr  # noqa: E402
import phoenix3 as p3  # noqa: E402
import phoenix_anim as pa  # noqa: E402
import pro_kit as K  # noqa: E402
from monster_rig import Pose, blink, breath, burst, osc, pulse, ramp  # noqa: E402

NY = Vector((0, 1, 0))
SG = {'p': 1, 'n': -1}

CFG = {
    1: dict(k=1.08, c=(0, 0, .62), rad=(.29, .27, .44), tilt=.26, h=(.17, 0, 1.00), hr=(.28, .26, .28),
            wing=dict(S=(-.02, .21, .82), A=(-.35, .90, .85), plen=.74, D0=(-.45, .25, -1), n=10, rows=2),
            crest=[(.12, .26), (.06, .34), (0, .42), (-.07, .38), (-.15, .30), (-.22, .24)], foot=(.16, .15), fz=.06,
            sparks=[(-.30, 0, 1.50), (-.18, 0, 1.60), (-.36, 0, 1.36)], tail=(-.30, 0, .32), shadow=(.60, .46, -.08), map_k=1.6),
    2: dict(k=1.0, c=(0, 0, .84), rad=(.25, .24, .52), tilt=.12, h=(.10, 0, 1.36), hr=(.21, .20, .22),
            wing=dict(S=(-.02, .20, 1.08), A=(-.84, .84, .97), plen=.88, D0=(-.35, .15, -1), n=11, rows=3),
            crest=[(.06, .16), (0, .30), (-.06, .22)], foot=(.12, .10), fz=.10,
            sparks=[(-.30, 0, 1.86), (-.20, 0, 1.94), (-.34, 0, 1.74)], tail=(-.10, 0, .40), shadow=(.72, .56, -.12), map_k=1.95),
}


def sail_wing_rig(b, sg, S, A, plen, D0, n_prim, cov_rows, cut=(.34, .62), split=.55):
    """p3.sail_wing, with every feather assigned to the inner wing (arm side) or the outer wing (beyond the wrist). The outer
    wing is lifted one layer (3 cm) along the wing normal, so where the two overlap they never share a surface."""
    S = Vector(S)
    A = Vector((A[0], sg * A[1], A[2]))
    D0 = Vector((D0[0], sg * D0[1], D0[2])).normalized()
    Adir = A.normalized()
    tip = plen * .62
    Lr = A.length - tip
    N = Adir.cross(D0).normalized()
    if N.dot(Vector((.4, sg * .8, .5))) < 0:
        N = -N
    gin, gout = 'wing_in_' + ('p' if sg > 0 else 'n'), 'wing_out_' + ('p' if sg > 0 else 'n')
    P0, P1, P2 = S, S + Adir * Lr * split, S + Adir * Lr
    b.grp = gin
    b.chain([(P0.x, P0.y, P0.z, .10), (P1.x, P1.y, P1.z, .08)], 'f1')
    b.grp = gout
    b.chain([(P1.x, P1.y, P1.z, .08), (P2.x, P2.y, P2.z, .05)], 'f1')

    def direction(u):
        t = u ** .85
        return (D0 * (1 - t) + Adir * t).normalized()

    def depth(u):
        return plen * (.62 + .38 * math.sin(math.pi * (.06 + .88 * u)))

    def place(root, d, ln, wr, cols, cut_, off):
        a = (root - S).dot(Adir) / Lr
        outer = a >= split
        b.grp = gout if outer else gin
        b.gfeather2(root + (N * .03 if outer else Vector((0, 0, 0))), d, ln, ln * wr, cols, N, cut_)

    for r in range(cov_rows):
        cnt = n_prim * 2 - r * 2
        for i in range(cnt):
            u = (i + .5) / cnt
            root = S + Adir * (Lr * (.03 + .97 * u)) + N * (.016 * (r + 1))
            place(root, direction(u), depth(u) * (.50 - .13 * r), .20, ('f1', 'f1b', 'f1b'), (.9, .95), 0)
    n2 = int(n_prim * 1.5)
    for i in range(n2):
        u = (i + .5) / n2
        root = S + Adir * (Lr * (.06 + .94 * u)) - N * .01
        ln = depth(u) * (1 + (.07 if i % 2 else 0))
        place(root, direction(u), ln, .21, ('f1', 'f2', 'f3'), cut, 0)
        if i % 2 == 0:
            place(root + N * .02, direction(min(1, u + .03)), ln * .78, .20, ('f1', 'f2', 'f3'), cut, 0)
    return S + Adir * Lr * split


def build(st):
    cfg = CFG[st]
    pal = dict(p3.phoenix(st)[0])
    # The game's sprite light (AgX, self-light 0.30, sun + fill) lifts everything towards pastel: a base red of #a72822 came out
    # salmon and the flame yellow beige. Darker, more saturated bases land on the intended colours.
    pal.update(body='#7c1610', body2='#8c1c14', head='#7c1610', brow='#4e0c08', f1='#6e120e', f1b='#7e1812',
               f2='#e83a00', f3='#f08a00', beak='#b87812', leg='#b07414')
    b = pa.G(dict(pal), 1.0)
    E, L = b.E, b.L
    k, c, rad, tilt, h, hr = cfg['k'], cfg['c'], cfg['rad'], cfg['tilt'], cfg['h'], cfg['hr']
    b.grp = 'body'
    E(*c, *rad, 'body', (0, tilt, 0))
    E(c[0] + .07, 0, c[2] - .02, rad[0] * .86, rad[1] * .86, rad[2] * .90, 'body2', (0, tilt, 0))
    b.grp = 'head'
    E(*h, *hr, 'head')
    E(h[0] - .02, 0, h[2] + hr[2] * .15, hr[0] * .96, hr[1] * .96, hr[2] * .95, 'head')
    ex, ez = h[0] + hr[0] * .80, h[2] - hr[2] * .02
    for sg in (-1, 1):
        E(ex - .02, sg * hr[1] * .50, ez + .095 * k, .06 * k, .11 * k, .034 * k, 'brow', (sg * .25, 0, 0))
    eyes = {}
    for s, sg in SG.items():
        b.grp = 'eye_' + s
        E(ex, sg * hr[1] * .44, ez, .055 * k, .072 * k, .080 * k, 'dark')
        E(ex - .005, sg * hr[1] * .68, ez + .005, .040 * k, .062 * k, .070 * k, 'eyewhite')
        eyes[s] = (ex, sg * hr[1] * .44, ez)
    bx = h[0] + hr[0] * .96
    b.grp = 'beak_up'
    L((bx - .04 * k, 0, ez + .0), (bx + .16 * k, 0, ez - .10 * k), .09 * k, .025 * k, 'beak'); E(bx + .0 * k, 0, ez - .03 * k, .09 * k, .095 * k, .06 * k, 'beak')
    b.grp = 'beak_low'
    L((bx - .03 * k, 0, ez - .075 * k), (bx + .10 * k, 0, ez - .115 * k), .065 * k, .02 * k, 'beak'); E(bx - .01 * k, 0, ez - .085 * k, .07 * k, .08 * k, .04 * k, 'beak')
    beak_hinge = (bx - .03 * k, 0, ez - .05 * k)
    b.grp = 'crest'
    for i, (dx, ln) in enumerate(cfg['crest']):
        b.gfeather2((h[0] + dx, 0, h[2] + hr[2] * .85), (-.30 - .25 * (i / len(cfg['crest'])), 0, 1), ln, .062, ('f2', 'f2', 'f3'), NY, (.30, .60))
    if st == 2:
        for sg in (-1, 1):
            b.gfeather2((h[0] + .04, sg * .13, h[2] + hr[2] * .75), (-.2, sg * .3, 1), .20, .035, ('f2', 'f2', 'f3'), NY, (.25, .55))
    for i, (x, y, z) in enumerate(cfg['sparks']):
        b.grp = 'spark%d' % i
        E(x, y, z, .028, .028, .028, 'f3')
    wr = {}
    wcfg = cfg['wing']
    for s, sg in SG.items():
        wr[s] = sail_wing_rig(b, sg, (wcfg['S'][0], sg * wcfg['S'][1], wcfg['S'][2]), wcfg['A'], wcfg['plen'], wcfg['D0'], wcfg['n'], wcfg['rows'])
    top = c[2] - .10
    foot = cfg['foot']
    fz = cfg['fz']
    for s, sg in SG.items():
        b.grp = 'leg_' + s
        E(.0, sg * foot[0], top, .11, .10, .14, 'body')
        L((.02, sg * foot[0], top), (.07, sg * foot[0], fz), .062, .05, 'leg')
        b.grp = 'foot_' + s
        E(.07, sg * foot[0], fz, .07, .06, .05, 'leg')
        mr.bird_foot(b, (.07, sg * foot[0], fz), sg * foot[0], foot[1] + .08, 'leg')
    b.grp = 'tail'
    if st == 1:
        p3.fan_tail(b, (-.30, 0, .32), (-1, 0, -.10), 6, .55, .95, .09, NY, 0.03)
        for sg in (-1, 1):
            b.gfeather2((-.10, sg * .18, .30), (-.2, sg * .6, -.8), .30, .05, ('f2', 'f2', 'f3'), NY, (.2, .5))
    else:
        p3.fan_tail(b, (-.10, 0, .40), (-.36, 0, -1), 7, .36, 1.0, .095, NY, 0.05)
    groups = {}
    for o in b.objs:
        groups.setdefault(o['grp'], []).append(o)
    hip = c[2] - .10
    parts = {
        'torso': ('root', (0, 0, hip - .10)),
        'body': ('torso', (0, 0, hip - .10)),
        'tail': ('root', cfg['tail']),
        'leg_p': ('root', (.0, foot[0], hip)), 'leg_n': ('root', (.0, -foot[0], hip)),
        'head': ('torso', (h[0] - .06, 0, h[2] - .20)),
        'beak_up': ('head', beak_hinge), 'beak_low': ('head', beak_hinge),
        'eye_p': ('head', eyes['p']), 'eye_n': ('head', eyes['n']),
        'crest': ('head', (h[0], 0, h[2] + hr[2] * .8)),
        'foot_p': ('leg_p', (.07, foot[0], fz)), 'foot_n': ('leg_n', (.07, -foot[0], fz)),
    }
    for s, sg in SG.items():
        parts['wing_in_' + s] = ('torso', (wcfg['S'][0], sg * wcfg['S'][1], wcfg['S'][2]))
        parts['wing_out_' + s] = ('wing_in_' + s, tuple(wr[s]))
    for i, p in enumerate(cfg['sparks']):
        parts['spark%d' % i] = ('head', p)
    return mrg.Rig(parts, groups)


# ── poses ─────────────────────────────────────────────────────
def base2(P, t, k=2):
    """Real breathing (the single body mesh swells; shoulders lift, the wing tips follow later, head and tail lag),
    slow weight sway, flickering crest, rising sparks. Identical at t=0 and t=1 in every clip."""
    b, b1, b2, b3 = (breath(t, k, lag) for lag in (0.0, 0.08, 0.18, 0.30))
    P.grow('body', .035 * b, .022 * b, .030 * b)
    P.add('torso', rot=(0, -1.0 * b, 0))
    P.add('head', d=(0, 0, .010 * b1), rot=(0, -1.2 * b1, 0))
    for s, sg in SG.items():
        P.add('wing_in_' + s, d=(0, sg * .006 * b1, .010 * b1), rot=(sg * 1.8 * b1, 0, 0))
        P.add('wing_out_' + s, rot=(sg * 2.2 * b3, 0, 0))
    P.add('tail', rot=(0, .9 * b2, 0))
    P.add('crest', rot=(2.5 * osc(t, 3), 3 * osc(t, 4, .2), 2 * osc(t, 2, .5)))
    P.add('root', rot=(.7 * osc(t, 1), 0, .5 * osc(t, 1, .25)))
    for i in range(3):
        ph_ = (t + i / 3) % 1.0
        P.add('spark%d' % i, d=(0, 0, .12 * ph_))
        P.set_scale('spark%d' % i, max(.01, min(1, ph_ * 6) * min(1, (1 - ph_) * 3)))


def eyes(P, closed):
    s = max(.08, 1 - .92 * closed)
    P.set_scale('eye_p', (1, 1, s))
    P.set_scale('eye_n', (1, 1, s))


def idle_s1(r, t):
    """Flamewing: it shakes its head and ruffles its feathers: a damped head shake, the body shivers after it, wings lift
    and flutter with the tips lagging, crest whips, tail swings the other way."""
    P = Pose()
    base2(P, t, 2)
    fade = 1 - ramp(t, .74, .94)
    H = burst(t, .08, 3.5, 3.2, 30) * fade
    ruff = pulse(t, .10, .20, .52, .72)
    P.add('head', rot=(-.15 * H, 0, H))
    P.add('torso', rot=(0, 0, .30 * burst(t, .105, 3.5, 3.2, 30) * fade))
    P.add('root', rot=(0, 0, .12 * burst(t, .13, 3.5, 3.2, 30) * fade))
    P.add('tail', rot=(0, 0, -.6 * burst(t, .16, 3.5, 3.2, 30) * fade))
    P.add('crest', rot=(0, 10 * ruff, .5 * burst(t, .14, 3.5, 3.0, 30) * fade))
    for s, sg in SG.items():
        P.add('wing_in_' + s, rot=(sg * (7 * ruff + 2.5 * osc(t, 9) * ruff), 0, 0))
        P.add('wing_out_' + s, rot=(sg * 6 * osc(t, 9, .25) * ruff, 0, 0))
    P.add('beak_low', rot=(0, 6 * pulse(t, .08, .12, .20, .30), 0))
    eyes(P, .6 * pulse(t, .08, .12, .5, .7))
    r.apply(P)


def idle_s2(r, t):
    """Solarphoenix: it crouches, rears up and beats its great wings twice, roaring at the top, then settles."""
    P = Pose()
    base2(P, t, 2)
    c = pulse(t, .05, .18, .19, .26)
    rear = ramp(t, .20, .40) * (1 - ramp(t, .70, .88)) + .10 * burst(t, .40, 2.5, 4.5) * (1 - ramp(t, .8, .95))
    beat = pulse(t, .40, .46, .70, .76)
    ph1 = 2 * math.pi * 2.0 * (t - .40)
    roar = pulse(t, .46, .52, .66, .72)
    hop = pulse(t, .32, .42, .44, .56)
    P.add('root', d=(-.025 * rear, 0, -.035 * c + .045 * rear + .04 * hop), rot=(0, 7 * c - 14 * rear, 0))
    P.add('torso', rot=(0, -9 * rear, 0))
    P.add('head', rot=(0, 6 * c - 12 * rear - 10 * roar, 0))
    P.add('beak_low', rot=(0, 34 * roar, 0))
    P.add('beak_up', rot=(0, -9 * roar, 0))
    for s, sg in SG.items():
        P.add('wing_in_' + s, rot=(sg * (8 * rear + 6 * c + 22 * beat * math.sin(ph1)), -6 * rear, 0))
        P.add('wing_out_' + s, rot=(sg * (4 * rear + 16 * beat * math.sin(ph1 - .9)), 0, 0))
        P.add('leg_' + s, rot=(0, -8 * rear, 0))
        P.add('foot_' + s, rot=(0, -12 * rear + 8 * c, 0))
    P.add('tail', rot=(0, -12 * rear + 6 * c, 6 * beat * math.sin(ph1 - 1.2)))
    P.add('crest', rot=(0, -20 * roar - 6 * rear, 0))
    eyes(P, .3 * roar + blink(t, .10))
    r.apply(P)


def make_attack(A):
    def attack(r, t):
        P = Pose()
        base2(P, t, 1)
        wind = gb.curve(t, [(0, 0), (.30, 1), (.42, 0), (1, 0)])
        hit = gb.curve(t, [(0, 0), (.30, 0), (.48, 1), (.62, .8), (1, 0)])
        bite = gb.curve(t, [(0, 0), (.28, 0), (.38, 1), (.47, 1), (.52, 0), (1, 0)])
        hop = pulse(t, .34, .44, .52, .64)
        P.add('root', d=(-.05 * wind + .20 * A * hit, 0, -.030 * wind + .025 * hop), rot=(0, -8 * wind + 8 * hit, 0))
        P.add('torso', rot=(0, -5 * wind + 5 * hit, 0))
        P.add('head', d=(.05 * hit, 0, 0), rot=(0, -9 * wind + 20 * hit, 0))
        P.add('beak_low', rot=(0, 10 * wind + 28 * bite, 0))
        P.add('beak_up', rot=(0, -8 * bite, 0))
        for s, sg in SG.items():
            P.add('wing_in_' + s, rot=(sg * (20 * wind - 26 * hit), 0, 0))
            P.add('wing_out_' + s, rot=(sg * (10 * wind - 16 * hit + 6 * math.sin(2 * math.pi * 2 * t) * (1 - wind)), 0, 0))
            P.add('leg_' + s, rot=(0, -36 * hit if s == 'p' else -14 * hit, 0))
            P.add('foot_' + s, rot=(0, 8 * hit, 0))
        P.add('tail', rot=(0, -12 * wind + 18 * hit, 0))
        P.add('crest', rot=(0, -20 * hit, 0))
        eyes(P, .4 * hit)
        r.apply(P)
    return attack


def pose_hurt(r, t):
    P = Pose()
    base2(P, t, 1)
    hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    P.add('root', d=(-.10 * hit, .01 * wob, 0), rot=(3 * wob, -9 * hit, 4 * wob))
    P.add('torso', rot=(0, -6 * hit, 0))
    P.add('head', rot=(0, -16 * hit, 10 * wob))
    P.add('beak_low', rot=(0, 12 * hit, 0))
    for s, sg in SG.items():
        P.add('wing_in_' + s, rot=(sg * 16 * hit, 0, 0))
        P.add('wing_out_' + s, rot=(sg * 10 * hit * math.cos(t * 9), 0, 0))
        P.add('leg_' + s, rot=(0, (12 if s == 'p' else -8) * hit, 0))
    P.add('tail', rot=(0, 16 * hit, 22 * hit * math.cos(t * 6)))
    P.add('crest', rot=(0, -22 * hit, 0))
    eyes(P, .9 * hit)
    r.apply(P)
    r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))


def pose_walk(r, t):
    P = Pose()
    base2(P, t, 1)
    s = 2 * math.pi * t
    for nm, sgn in (('p', 1), ('n', -1)):
        th = -28 * sgn * math.sin(s)
        lf = max(0.0, sgn * math.cos(s))
        P.add('leg_' + nm, d=(0, 0, .040 * lf), rot=(sgn * 14 * lf, th, 0))
        P.add('foot_' + nm, rot=(0, -.5 * th - 16 * lf, 0))
        P.add('wing_in_' + nm, rot=(sgn * (3 * math.sin(2 * s) + 1.0), 0, 0))
        P.add('wing_out_' + nm, rot=(sgn * 4 * math.sin(2 * s - .8), 0, 0))
    P.add('root', d=(0, 0, .016 * (1 - math.cos(2 * s)) / 2), rot=(-4 * math.sin(s), 3 + 2 * math.cos(2 * s), 3 * math.sin(s)))
    P.add('torso', d=(.008 * math.sin(s - 1.4), 0, 0), rot=(2.0 * math.sin(s), -1.5 * math.cos(2 * s), 0))
    P.add('head', d=(.025 * math.sin(s - 1.0), 0, 0), rot=(4 * math.sin(s), -2.5 * math.cos(2 * s), -4 * math.sin(s)))
    P.add('tail', rot=(0, 3 * math.cos(2 * s), 12 * math.sin(s + .6)))
    r.apply(P)


class _Cap:
    def apply(self, P):
        self.P = P

    def flash(self, v):
        pass


def _cap(fn, t):
    c = _Cap()
    fn(c, t)
    return c.P


def anims(st):
    idle = idle_s1 if st == 1 else idle_s2

    def walk_in(r, t):
        r.apply(_cap(idle, 0.0).blend(_cap(pose_walk, 0.0), gb.smooth(t)))

    def walk_out(r, t):
        r.apply(_cap(pose_walk, 1.0).blend(_cap(idle, 0.0), gb.smooth(t)))
    return {'idle': (30, 12, True, idle), 'attack': (16, 16, False, make_attack(1.0 if st == 1 else 1.2)),
            'hurt': (10, 14, False, pose_hurt), 'walk': (8, 10, True, pose_walk),
            'walk_in': (6, 10, False, walk_in), 'walk_out': (6, 10, False, walk_out)}


def _vec(P):
    out = {}
    for n in set(P.d) | set(P.gro) | set(P.scale):
        out[n] = list(P.d.get(n, [0, 0, 0])) + list(P.rot.get(n, [0, 0, 0])) + list(P.gro.get(n, [0, 0, 0]))
        s = P.scale.get(n)
        out[n] += [x - 1 for x in s] if isinstance(s, tuple) else [(s - 1)] * 3 if s is not None else [0, 0, 0]
    return out


def check_seams(table):
    ref = _cap(table['idle'][3], 0.0)
    rv = _vec(ref)
    w0, w1 = _vec(_cap(pose_walk, 0.0)), _vec(_cap(pose_walk, 1.0))
    expect = {('walk', 'start'): w1, ('walk', 'end'): w0, ('walk_in', 'end'): w0, ('walk_out', 'start'): w1}
    worst = 0.0
    for name, (n, fps, loop, fn) in table.items():
        for t, tag in ((0.0, 'start'), (1.0, 'end')):
            v = _vec(_cap(fn, t))
            target = expect.get((name, tag), rv)
            dev, where = 0.0, ''
            for part in set(v) | set(target):
                a, b2 = v.get(part, [0] * 12), target.get(part, [0] * 12)
                for i, (x, y) in enumerate(zip(a, b2)):
                    d = abs(x - y) * (1.0 if i in (3, 4, 5) else 100.0)
                    if d > dev:
                        dev, where = d, '%s[%d]' % (part, i)
            worst = max(worst, dev)
            print('%-9s %-5s max deviation = %.3f %s%s' % (name, tag, dev, where, '' if dev < 0.05 else '   <-- JUMP'))
    print('WORST', round(worst, 3))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int, required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--views', default='front')
    ap.add_argument('--headings', default='se,ne,nw,sw')
    ap.add_argument('--only', default='')
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--seams', action='store_true')
    ap.add_argument('--clearance', action='store_true')
    ap.add_argument('--still')
    ap.add_argument('--pose')
    ap.add_argument('--view', default='front')
    a = ap.parse_args(argv)
    st = a.stage
    cfg = CFG[st]
    table = anims(st)
    only = [x for x in a.only.split(',') if x] or None
    if a.seams:
        check_seams(table)
        return
    if a.clearance:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        rig = build(st)
        bad = mrg.clearance(rig, table, ellipsoid=(cfg['c'], cfg['rad']), tilt=cfg['tilt'],
                            watch=('foot_p', 'foot_n', 'wing_in_p', 'wing_in_n', 'wing_out_p', 'wing_out_n'))
        print('VIOLATIONS', len(bad), bad[:30])
        return
    if a.still:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        gb.FW, gb.FH = int(560 * a.scale), int(448 * a.scale)
        gb.ANIMS = {k: v for k, v in table.items() if k not in ('walk', 'walk_in', 'walk_out')}
        rig = build(st)
        gb.engine(a.samples)
        gb.shadow_catcher(5.0)
        sh = gb.contact_shadow(0)
        sh.scale = (cfg['shadow'][0], cfg['shadow'][1], 1)
        sh.location = (cfg['shadow'][2], 0, .004)
        cam_loc = gb.battle_camera(rig, gb.VIEWS[a.view])
        gb.lights(cam_loc, Vector((0, 0, .5)), .25)
        name, tt = a.pose.split(':')
        rig.reset()
        table[name][3](rig, float(tt))
        bpy.context.view_layer.update()
        gb.render_frame(os.path.abspath(a.still))
        return
    mrg.bake(lambda: build(st), table, a.out, a.views, a.samples, a.scale, cfg['map_k'], 'phoenix', st, cfg['shadow'], only,
             map_anims=('walk', 'walk_in', 'walk_out', 'idle'), headings=a.headings.split(','))


if __name__ == '__main__':
    main()
