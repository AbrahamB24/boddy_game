"""Phoenix stage 0 (the round chick): jointed rig + idle behaviours, attack, hurt, walk.

    blender --background --python tool/blender/phoenix_anim.py -- --out docs/renders/monsters/phoenix_anim \
        [--views front,map] [--only idle,idle_peck] [--samples 24] [--scale 0.5]
    blender --background --python tool/blender/phoenix_anim.py -- --out x --still x.png --pose idle_peck:0.4

Rules (see feedback memory 'animation-principles'): real breathing in the body, varied natural idle
behaviours, correct combat and walk, the whole body takes part with lag (overlapping action).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_bake as gb  # noqa: E402
import monster_rig as mrg  # noqa: E402
import phoenix as ph  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
from monster_rig import Pose, blink, breath, burst, osc, pulse, ramp  # noqa: E402

NY = Vector((0, 1, 0))
SG = {'p': 1, 'n': -1}


class G(ph.P):
    """The phoenix builder, tagging every primitive with the part (b.grp) it belongs to."""
    grp = 'body'

    def E(s, *a, **k):
        n = len(s.objs)
        super().E(*a, **k)
        for o in s.objs[n:]:
            o['grp'] = s.grp

    def L(s, *a, **k):
        n = len(s.objs)
        super().L(*a, **k)
        for o in s.objs[n:]:
            o['grp'] = s.grp

    def clipped(s, x, y, z, rx, ry, rz, m, zcut, keep='above'):
        """An ellipsoid with everything below world height zcut cut away and the hole closed."""
        import bmesh
        ob = K.ellipsoid(x, y, z, rx, ry, rz, s.M[m], seg=24, rings=16)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, zcut - z), plane_no=(0, 0, 1),
                                     clear_inner=(keep == 'above'), clear_outer=(keep == 'below'))
        cut = [g for g in res['geom_cut'] if isinstance(g, bmesh.types.BMEdge)]
        bmesh.ops.triangle_fill(bm, use_beauty=True, edges=cut)
        bm.to_mesh(ob.data)
        bm.free()
        ob['grp'] = s.grp
        s.objs.append(ob)


# Two rules against flicker (user 2026-11-11, "es darf niemals irgendwo flackern"):
#  1. A colour boundary never runs between two parts that move against each other. The cream belly is PAINTED
#     onto the body mesh (one clean stepped line); it was a separate part, whose stair-steps crawled against the
#     body by sub-voxel amounts as the chest breathed.
#  2. Parts that overlap and move relative to each other share one colour (head, wing base, chest cap = body red),
#     so a nearly coplanar overlap cannot show up as flickering patches.
PAL = dict(brow='#8a2a1e', eyewhite='#f4ece0', body='#bd3f2c', head='#bd3f2c', belly='#e6c28c', wing='#a8332a', wing2='#982c24',
           beak='#f0b23c', leg='#e8a838', f1='#a8332a', f2='#ff8a20', f3='#ffd040')


def build_chick():
    b = G(dict(PAL), 1.0)
    E, L = b.E, b.L
    b.grp = 'body'
    E(0, 0, .36, .31, .29, .30, 'body')                  # ONE body mesh: no seams, no gaps, no overlapping surfaces
    tw.PAINT[:] = [('body', (.20, 0, .32), (.15, .17, .20), 'belly', 'body')]       # the cream belly, painted on that mesh
    h, hr = (.04, 0, .76), (.28, .27, .27)
    b.grp = 'head'
    E(*h, *hr, 'head')
    ex, ez = h[0] + hr[0] * .80, h[2] - hr[2] * .02
    for sg in (-1, 1):
        E(ex - .02, sg * hr[1] * .50, ez + .095, .06, .11, .034, 'brow', (sg * .25, 0, 0))
    eyes = {}
    for s, sg in SG.items():
        b.grp = 'eye_' + s
        E(ex, sg * hr[1] * .44, ez, .055, .072, .080, 'dark')
        E(ex - .005, sg * hr[1] * .68, ez + .005, .040, .062, .070, 'eyewhite')
        eyes[s] = (ex, sg * hr[1] * .44, ez)
    b.grp = 'beak_up'
    L((.28, 0, .715), (.44, 0, .69), .048, .012, 'beak'); E(.31, 0, .705, .058, .058, .032, 'beak')
    b.grp = 'beak_low'
    L((.28, 0, .672), (.41, 0, .662), .042, .010, 'beak'); E(.31, 0, .672, .052, .052, .028, 'beak')
    b.grp = 'crest'
    for dx, dy, ln, tilt in ((0, 0, .26, -.2), (-.06, -.07, .18, -.35), (-.06, .07, .18, -.35)):
        base = Vector((h[0] + dx, dy, h[2] + hr[2] * .86))
        tipv = base + Vector((tilt * ln, dy * ln, ln))
        L(base, base + (tipv - base) * .6, .06, .045, 'f2'); L(base + (tipv - base) * .6, tipv, .045, .01, 'f3')
    sparks = [(-.02, .10, 1.28), (.10, -.06, 1.36), (-.12, -.08, 1.20)]
    for i, (x, y, z) in enumerate(sparks):
        b.grp = 'spark%d' % i
        E(x, y, z, .025, .025, .025, 'f3')
    for s, sg in SG.items():
        b.grp = 'wing_' + s
        E(-.04, sg * .27, .46, .17, .07, .20, 'body', (sg * .25, .25, 0))
        for i, (dx, dz) in enumerate(((0, 0), (-.04, -.05), (-.08, -.10))):
            b.feather((.06 + dx, sg * .30, .56 + dz), (-.75, 0, -.65), .38 - i * .04, .075, 'wing2', (0, sg, 0))
    b.grp = 'tail'
    for y in (-.08, 0, .08):
        b.gfeather2((-.24, y * .6, .30), (-.85, y * 2, .22), .34 - abs(y) * .5, .06, ('f1', 'f2', 'f3'), NY, (.30, .58))
    import monsters_real as mr
    for s, sg in SG.items():
        b.grp = 'leg_' + s
        E(.02, sg * .12, .16, .09, .08, .12, 'body')
        L((.02, sg * .12, .14), (.06, sg * .12, .05), .035, .03, 'leg')
        b.grp = 'foot_' + s
        E(.06, sg * .12, .05, .04, .035, .03, 'leg')
        for ang in (-.45, 0, .45):
            tip = (.06 + math.cos(ang) * .12, sg * .12 + math.sin(ang) * .10, .03)
            L((.06, sg * .12, .045), tip, .026, .02, 'leg', seg=6)
    groups = {}
    for o in b.objs:
        groups.setdefault(o['grp'], []).append(o)
    parts = {
        'torso': ('root', (0, 0, .30)),                 # moves the whole upper body: body mesh, head, wings
        'body': ('torso', (0, 0, .30)),                 # the body mesh only: breathing scales THIS (no seam, no gap)
        'tail': ('root', (-.24, 0, .30)),
        'leg_p': ('root', (.02, .12, .18)), 'leg_n': ('root', (.02, -.12, .18)),
        'head': ('torso', (.02, 0, .60)),
        'wing_p': ('torso', (-.02, .26, .58)), 'wing_n': ('torso', (-.02, -.26, .58)),
        'beak_up': ('head', (.27, 0, .69)), 'beak_low': ('head', (.27, 0, .69)),
        'eye_p': ('head', eyes['p']), 'eye_n': ('head', eyes['n']),
        'crest': ('head', (.04, 0, .95)),
        'foot_p': ('leg_p', (.06, .12, .05)), 'foot_n': ('leg_n', (.06, -.12, .05)),
    }
    for i, p in enumerate(sparks):
        parts['spark%d' % i] = ('head', p)
    return mrg.Rig(parts, groups)


# ── shared layers ────────────────────────────────────────────
def base(P, t, k=2, amount=1.0):
    """What every idle has: real breathing (chest swells, belly gives, shoulders and wings lift, the
    head follows a beat later), slow weight sway, flickering crest, rising sparks."""
    b, b1, b2 = (breath(t, k, lag) * amount for lag in (0.0, 0.08, 0.18))
    P.grow('body', .040 * b, .025 * b, .032 * b)                  # the body mesh swells: forward, sideways, up
    P.add('torso', rot=(0, -1.0 * b, 0))
    P.add('head', d=(0, 0, .0096 * b1), rot=(0, -1.2 * b1, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, d=(0, sg * .0065 * b1, .009 * b1), rot=(sg * 1.6 * b1, 0, 0))
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


def tap(t, c, w=.022):
    return math.exp(-((t - c) / w) ** 2)


# ── idle behaviours ───────────────────────────────────────────
def idle(r, t):
    P = Pose()
    base(P, t, 2)
    P.add('head', rot=(2 * osc(t, 1), 1.5 * osc(t, 2), 4 * osc(t, 1)))     # every term is 0 at t=0 and t=1, so clips chain without a jump
    eyes(P, blink(t, .62))
    r.apply(P)


def idle_look(r, t):
    P = Pose()
    base(P, t, 2)
    Y = lambda u: 34 * pulse(u, .10, .24, .36, .50) - 38 * pulse(u, .52, .66, .76, .86)
    y = Y(t)
    P.add('head', rot=(-.2 * y, 0, y))
    P.add('torso', rot=(0, 0, .25 * Y(t - .03)))
    P.add('root', d=(0, .004 * y / 34, 0), rot=(0, 0, .10 * Y(t - .06)))
    P.add('tail', rot=(0, 0, -.12 * Y(t - .09)))
    eyes(P, blink(t, .56))
    r.apply(P)


def idle_peck(r, t):
    P = Pose()
    base(P, t, 2)
    D = pulse(t, .12, .30, .70, .90)
    T = sum(tap(t, c) for c in (.38, .50, .62))
    O = sum(pulse(t, c - .07, c - .04, c - .012, c) for c in (.38, .50, .62))
    chew = pulse(t, .76, .78, .86, .90) * (.5 - .5 * math.cos(2 * math.pi * 3 * (t - .76)))
    P.add('torso', rot=(0, 9 * D, 0))
    P.add('head', d=(.02 * D, 0, 0), rot=(0, 20 * D + 8 * T - 8 * pulse(t, .72, .78, .80, .86), 0))
    P.add('root', d=(.02 * D, 0, -.040 * D), rot=(0, 2 * D, 0))
    P.add('tail', rot=(0, 22 * D + 6 * T, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (6 * D + 2 * T), 0, 0))
        P.add('foot_' + s, rot=(0, -8 * D, 0))
    P.add('beak_low', rot=(0, 12 * O + 9 * chew, 0))
    P.add('beak_up', rot=(0, -3 * O - 2 * chew, 0))
    eyes(P, blink(t, .20) + blink(t, .84))
    r.apply(P)


def idle_scratch(r, t):
    P = Pose()
    base(P, t, 2)
    Lf = pulse(t, .10, .26, .78, .92)
    u = min(1.0, max(0.0, (t - .28) / .48)) * 3
    sc = (.5 - .5 * math.cos(2 * math.pi * u))
    # the scratching leg swings OUT to the side first, so the whole sweep happens outside the body and the foot
    # is never inside the belly (user 2026-11-11: the foot disappeared into the body)
    P.add('leg_p', d=(0, 0, .015 * Lf), rot=(62 * Lf, -22 * Lf + 30 * sc * Lf, 0))
    P.add('foot_p', rot=(0, -22 * Lf + 26 * sc * Lf, 0))
    P.add('leg_n', d=(0, 0, -.006 * Lf), rot=(0, 3 * Lf, 0))
    P.add('root', d=(-.010 * sc * Lf, -.012 * Lf, -.004 * Lf), rot=(4.5 * Lf, 3 * Lf + 2 * sc * Lf, -2.2 * sc * Lf))
    P.add('head', rot=(0, 16 * Lf - 4 * sc * Lf, 10 * Lf))
    P.add('torso', rot=(0, 0, 3 * Lf))
    P.add('tail', rot=(0, 5 * Lf, -6 * Lf - 8 * sc * Lf))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (4 * Lf + 3 * sc * Lf), 0, 0))
    eyes(P, blink(t, .12))
    r.apply(P)


def idle_shake(r, t):
    P = Pose()
    base(P, t, 2)
    fade = 1 - ramp(t, .74, .94)
    H = burst(t, .08, 3.5, 3.2, 34) * fade
    ruff = pulse(t, .10, .20, .52, .72)
    P.add('head', rot=(-.15 * H, 0, H))
    P.add('torso', rot=(0, 0, .35 * burst(t, .105, 3.5, 3.2, 34) * fade))
    P.add('root', rot=(0, 0, .15 * burst(t, .13, 3.5, 3.2, 34) * fade))
    P.add('tail', rot=(0, 0, -.7 * burst(t, .16, 3.5, 3.2, 34) * fade))
    P.add('crest', rot=(0, 10 * ruff, .5 * burst(t, .14, 3.5, 3.0, 34) * fade))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (12 * ruff + 3.5 * osc(t, 9) * ruff), 0, 0))
    P.add('beak_low', rot=(0, 6 * pulse(t, .08, .12, .20, .30), 0))
    eyes(P, .6 * pulse(t, .08, .12, .5, .7))
    r.apply(P)


def idle_roar(r, t):
    P = Pose()
    base(P, t, 2)
    inh = pulse(t, .06, .24, .26, .32)
    ro = pulse(t, .26, .33, .68, .78)
    trem = osc(t, 10) * ro
    P.add('head', d=(-.015 * inh + .02 * ro, 0, 0), rot=(0, 9 * inh - 30 * ro + .7 * trem, 0))
    P.add('beak_low', rot=(0, 4 * inh + 44 * ro, 0))
    P.add('beak_up', rot=(0, -10 * ro, 0))
    P.grow('body', (.030 * inh + .016 * ro) / .31, 0, (.020 * inh + .012 * ro) / .60)
    P.add('torso', rot=(0, -4 * inh - 8 * ro, 0))
    P.add('root', d=(-.012 * ro, 0, -.018 * ro - .010 * inh), rot=(0, -2 * inh - 7 * ro, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (9 * inh + 42 * ro + 2 * trem), -14 * ro, 0))
        P.add('foot_' + s, rot=(0, -6 * ro, 0))
    P.add('tail', rot=(0, -6 * inh + 20 * ro, 0))
    P.add('crest', rot=(0, -8 * inh - 25 * ro + 3 * trem, 0))
    eyes(P, .35 * ro + blink(t, .12))
    r.apply(P)


def idle_rear(r, t):
    P = Pose()
    base(P, t, 2)
    c = pulse(t, .05, .18, .19, .26)
    rear = ramp(t, .20, .40) * (1 - ramp(t, .70, .88)) + .12 * burst(t, .40, 2.5, 4.5) * (1 - ramp(t, .8, .95))
    beats = pulse(t, .42, .46, .68, .72) * math.sin(2 * math.pi * 2 * (t - .42))
    hop = pulse(t, .32, .42, .44, .56)
    P.add('root', d=(-.030 * rear, 0, -.040 * c + .055 * rear + .03 * hop), rot=(0, 9 * c - 24 * rear, 0))
    P.add('torso', rot=(0, -10 * rear, 0))
    P.add('head', rot=(0, 8 * c - 16 * rear, 0))
    for s, sg in SG.items():
        P.add('leg_' + s, rot=(0, -12 * rear, 0))
        P.add('foot_' + s, rot=(0, -20 * rear + 12 * c, 0))
        P.add('wing_' + s, rot=(sg * (8 * c + 58 * rear + 16 * beats), -12 * rear, 0))
    P.add('tail', rot=(0, -16 * rear + 8 * c, 0))
    P.add('beak_low', rot=(0, 14 * rear * pulse(t, .46, .50, .64, .68), 0))
    eyes(P, blink(t, .08))
    r.apply(P)


# ── combat and walk ───────────────────────────────────────────
def pose_attack(r, t):
    P = Pose()
    base(P, t, 1)
    wind = gb.curve(t, [(0, 0), (.30, 1), (.42, 0), (1, 0)])
    hit = gb.curve(t, [(0, 0), (.30, 0), (.48, 1), (.62, .8), (1, 0)])
    bite = gb.curve(t, [(0, 0), (.28, 0), (.38, 1), (.47, 1), (.52, 0), (1, 0)])
    hop = pulse(t, .34, .42, .50, .62)
    P.add('root', d=(-.05 * wind + .20 * hit, 0, -.035 * wind + .02 * hop), rot=(0, -8 * wind + 8 * hit, 0))
    P.add('torso', rot=(0, -4 * wind + 4 * hit, 0))
    P.add('head', d=(.06 * hit, 0, 0), rot=(0, -10 * wind + 18 * hit, 0))
    P.add('beak_low', rot=(0, 10 * wind + 24 * bite, 0))
    P.add('beak_up', rot=(0, -8 * bite, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (30 * wind + 12 * hit), 25 * hit, 0))
        P.add('leg_' + s, rot=(0, -30 * hit if s == 'p' else -10 * hit, 0))
        P.add('foot_' + s, rot=(0, 6 * hit, 0))
    P.add('tail', rot=(0, -14 * wind + 20 * hit, 0))
    P.add('crest', rot=(0, -20 * hit, 0))
    eyes(P, .5 * hit)
    r.apply(P)


def pose_hurt(r, t):
    P = Pose()
    base(P, t, 1)
    hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    P.add('root', d=(-.10 * hit, .01 * wob, 0), rot=(4 * wob, -10 * hit, 4 * wob))
    P.grow('body', .04 * hit, 0, 0)
    P.add('torso', rot=(0, -6 * hit, 0))
    P.add('head', rot=(0, -18 * hit, 10 * wob))
    P.add('beak_low', rot=(0, 12 * hit, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * 25 * hit, -10 * hit, 0))
        P.add('leg_' + s, rot=(0, (14 if s == 'p' else -10) * hit, 0))
    P.add('tail', rot=(0, 18 * hit, 25 * hit * math.cos(t * 6)))
    P.add('crest', rot=(0, -25 * hit, 0))
    eyes(P, .9 * hit)
    r.apply(P)
    r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))


def pose_walk(r, t):
    P = Pose()
    base(P, t, 1)
    s = 2 * math.pi * t
    for nm, sgn in (('p', 1), ('n', -1)):
        th = -34 * sgn * math.sin(s)
        lf = max(0.0, sgn * math.cos(s))                           # 0..1 while this leg swings forward
        P.add('leg_' + nm, d=(0, 0, .030 * lf), rot=(sgn * 30 * lf, th, 0))    # the lifted foot swings OUT, never up into the belly
        P.add('foot_' + nm, rot=(0, .6 * th * -1 + (-18 * max(0.0, sgn * math.cos(s))), 0))
        P.add('wing_' + nm, rot=(sgn * (3 * math.sin(2 * s) + 1.5), 0, 0))
    P.add('root', d=(0, 0, .014 * (1 - math.cos(2 * s)) / 2), rot=(-5 * math.sin(s), 3 + 2 * math.cos(2 * s), 3 * math.sin(s)))
    P.add('torso', d=(.008 * math.sin(s - 1.4), 0, 0), rot=(2.5 * math.sin(s), -1.5 * math.cos(2 * s), 0))
    P.add('head', d=(.02 * math.sin(s - 1.0), 0, 0), rot=(5 * math.sin(s), -2.5 * math.cos(2 * s), -4 * math.sin(s)))
    P.add('tail', rot=(0, 3 * math.cos(2 * s), 14 * math.sin(s + .6)))
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


def walk_in(r, t):
    """Standing -> first walk pose, so starting to walk never jumps."""
    r.apply(_cap(idle, 0.0).blend(_cap(pose_walk, 0.0), gbs(t)))


def walk_out(r, t):
    """Last walk pose -> standing, so stopping never jumps."""
    r.apply(_cap(pose_walk, 1.0).blend(_cap(idle, 0.0), gbs(t)))


gbs = gb.smooth

ANIMS = {
    # ONE idle per monster stage (user rule 2026-11-11): the chick pecks. The other behaviour functions above stay
    # as a menu for later species but are not baked.
    'idle': (28, 12, True, idle_peck),
    'attack': (16, 16, False, pose_attack),
    'hurt': (10, 14, False, pose_hurt),
    'walk': (8, 10, True, pose_walk),
    'walk_in': (6, 10, False, walk_in),
    'walk_out': (6, 10, False, walk_out),
}


class _Fake:
    """Captures a pose without a scene, to compare poses numerically."""
    def apply(self, P):
        self.P = P

    def flash(self, v):
        pass


def _vec(P):
    out = {}
    for n in set(P.d) | set(P.gro) | set(P.scale):
        out[n] = list(P.d.get(n, [0, 0, 0])) + list(P.rot.get(n, [0, 0, 0])) + list(P.gro.get(n, [0, 0, 0]))
        s = P.scale.get(n)
        out[n] += [x - 1 for x in s] if isinstance(s, tuple) else [(s - 1)] * 3 if s is not None else [0, 0, 0]
    return out


def check_seams():
    """Every clip must start AND end exactly in the idle rest pose, so clips chain with no jump (a 'cut')."""
    ref = _Fake()
    idle(ref, 0.0)
    rv = _vec(ref.P)

    def pose_at(fn, t):
        f = _Fake()
        fn(f, t)
        return _vec(f.P)
    w0, w1 = pose_at(pose_walk, 0.0), pose_at(pose_walk, 1.0)
    expect = {('walk', 'start'): w1, ('walk', 'end'): w0, ('walk_in', 'end'): w0, ('walk_out', 'start'): w1}   # all other ends: rest
    worst = 0.0
    for name, (n, fps, loop, fn) in ANIMS.items():
        for t, tag in ((0.0, 'start'), (1.0, 'end')):
            f = _Fake()
            fn(f, t)
            v = _vec(f.P)
            target = expect.get((name, tag), rv)
            dev, where = 0.0, ''
            for part in set(v) | set(target):
                a, b2 = v.get(part, [0] * 12), target.get(part, [0] * 12)
                for i, (x, y) in enumerate(zip(a, b2)):
                    scale = 1.0 if i in (3, 4, 5) else (100.0 if i < 3 else 100.0)     # degrees as is, offsets/scales x100
                    d = abs(x - y) * scale
                    if d > dev:
                        dev, where = d, '%s[%d]' % (part, i)
            worst = max(worst, dev)
            print('%-13s %-5s max deviation from rest = %.3f at %s%s' % (name, tag, dev, where, '' if dev < 0.05 else '   <-- JUMP'))
    print('WORST', round(worst, 3))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--views', default='front')
    ap.add_argument('--headings', default='se,ne,nw,sw')
    ap.add_argument('--only', default='')
    ap.add_argument('--samples', type=int, default=24)
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--still')
    ap.add_argument('--seams', action='store_true')
    ap.add_argument('--clearance', action='store_true')
    ap.add_argument('--pose')
    ap.add_argument('--view', default='front')
    a = ap.parse_args(argv)
    only = [x for x in a.only.split(',') if x] or None
    if a.seams:
        check_seams()
        return
    if a.clearance:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        rig = build_chick()
        bad = mrg.clearance(rig, ANIMS, watch=('foot_p', 'foot_n', 'wing_p', 'wing_n'))
        print('VIOLATIONS', len(bad), bad[:30])
        return
    if a.still:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        gb.FW, gb.FH = int(560 * a.scale), int(448 * a.scale)
        gb.ANIMS = {k: v for k, v in ANIMS.items() if k != 'walk'}
        rig = build_chick()
        gb.engine(a.samples)
        gb.shadow_catcher(5.0)
        sh = gb.contact_shadow(0)
        sh.scale = (.52, .40, 1)
        sh.location = (-.04, 0, .004)
        cam_loc = gb.battle_camera(rig, gb.VIEWS[a.view])
        gb.lights(cam_loc, Vector((0, 0, .5)), .25)
        name, tt = a.pose.split(':')
        rig.reset()
        ANIMS[name][3](rig, float(tt))
        bpy.context.view_layer.update()
        gb.render_frame(os.path.abspath(a.still))
        return
    mrg.bake(build_chick, ANIMS, a.out, a.views, a.samples, a.scale, 1.3, 'phoenix', 0, (.52, .40, -.04), only,
              map_anims=('walk', 'walk_in', 'walk_out', 'idle'), headings=a.headings.split(','))


if __name__ == '__main__':
    main()


