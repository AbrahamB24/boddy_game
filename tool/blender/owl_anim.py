"""Owl line (3 stages): jointed rig + ONE idle per stage, attack, hurt, walk. Same rig/bake pipeline as the duck and phoenix.

    blender --background --python tool/blender/owl_anim.py -- --stage 0 --out docs/renders/monsters/owl_anim/s0 \
        [--views front,map] [--headings se,ne] [--only idle,attack] [--samples 32] [--scale 1.0]
    ... --seams      every clip starts/ends in the rest pose (walk has in/out clips)
    ... --ground     nothing of the owl ever goes below the floor, in any frame
    ... --still x.png --pose idle:0.4 [--view front]

User decisions (2026-11-13):
  s0 (sheet stage 1, chick)  idle = looks around nervously left and right, then ONE hop with a wing flap
  s1 (sheet stage 2)         idle = the head turns 180 degrees and back THE SAME WAY, body stays calm
  s2 (sheet stage 3)         idle = wings open, ONE flap, wings fold
  combat, all stages         wings spread (small but visible on s0/s1, full on s2), 2-3 fast pecks; hurt = feathers puff,
                             body jerks back, wings open slightly
  walk                       waddle on s0/s1, long strides with slightly spread wings on s2
Rotations: rot y > 0 tips the top FORWARD (head nods down, a hanging wing's tip swings BACK); for a part hanging down on
the +y side rot x > 0 swings it OUT; rot z = yaw (turn left, towards +y). A wing's inner layer, outer layer and tip rotate
about the same shoulder pivot; the outer ones fan out with an extra rot y.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_bake as gb  # noqa: E402
import monster_rig as mrg  # noqa: E402
import owl as ow  # noqa: E402
import phoenix_anim as pa  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
from monster_rig import Pose, blink, breath, burst, osc, pulse, ramp  # noqa: E402

SG = {'p': 1, 'n': -1}
FLOOR = [0.0]                                      # lowest voxel of the rest pose (set when the rig is built)
DARKEN, SAT = .66, 1.35                            # the game's sprite light lifts colours towards pastel: darker and more
STAGE_TONE = {0: (1.5, .74), 1: (1.45, .72), 2: (1.12, .72)}      # saturated bases land on the intended colours (tuned on stills)
WING_OUT = {0: 30, 1: 32, 2: 80}                   # how far the wing swings out when "spread" (deg); s0/s1 only a little
FAN = {0: (0, 0), 1: (0, 0), 2: (34, 70)}          # extra fan of the outer layer / tip (deg, rot y), full wings only
CFG = {
    0: dict(shadow=(.46, .38, -.02), map_k=1.25, idle_frames=40),
    1: dict(shadow=(.46, .38, -.02), map_k=1.30, idle_frames=40),
    2: dict(shadow=(.50, .40, -.02), map_k=1.40, idle_frames=36),
}
# joint positions per stage: neck, shoulder, hip, tail, eye (+y eye), torso pivot
J = {
    0: dict(neck=(0, 0, .52), sh=(-.03, .28, .38), hip=(.04, .12, .10), tail=(-.25, 0, .13), eye=(.262, .125, .675), tor=(0, 0, .22)),
    1: dict(neck=(0, 0, .50), sh=(.0, .28, .58), hip=(.05, .12, .12), tail=(-.22, 0, .18), eye=(.245, .125, .67), tor=(0, 0, .22)),
    2: dict(neck=(.02, 0, .56), sh=(.0, .30, .60), hip=(.02, .10, .12), tail=(-.12, 0, .22), eye=(.245, .105, .675), tor=(0, 0, .22)),
}


def _dark(hexcol):
    import colorsys
    c = hexcol.lstrip('#')
    r, g, b = (int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    sat, dk_ = STAGE_TONE.get(_dark.stage, (SAT, DARKEN))
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, s * sat), v * dk_)
    return '#%02x%02x%02x' % (int(r * 255), int(g * 255), int(b * 255))


def build(st):
    _dark.stage = st
    pal = {k: (v if k in ('dark', 'white', 'eyewhite') else _dark(v)) for k, v in ow.pal_for(st).items()}
    b = pa.G(pal, 1.0)
    tw.DEPTH = 8
    ow.STAGES[st](b)
    groups = {}
    for o in b.objs:
        groups.setdefault(o['grp'], []).append(o)
    j = J[st]
    ex, ey, ez = j['eye']
    parts = {
        'torso': ('root', j['tor']),
        'body': ('torso', j['tor']),
        'head': ('torso', j['neck']),
        'tail': ('torso', j['tail']),
    }
    for s, sg in SG.items():
        parts['eye_' + s] = ('head', (ex, sg * ey, ez))
        parts['wing_' + s] = ('torso', (j['sh'][0], sg * j['sh'][1], j['sh'][2]))
        if st == 2:
            parts['wing_out_' + s] = ('wing_' + s, (j['sh'][0], sg * j['sh'][1], j['sh'][2]))
            parts['wing_tip_' + s] = ('wing_' + s, (j['sh'][0], sg * j['sh'][1], j['sh'][2]))
        parts['leg_' + s] = ('root', (j['hip'][0], sg * j['hip'][1], j['hip'][2]))
    rig = mrg.Rig(parts, groups)
    rig.reset()
    FLOOR[0] = mrg.lowest_z(rig)
    return rig


# ── poses ─────────────────────────────────────────────────────
def fin(r, P):
    """Apply a pose, then lift the whole owl just enough that nothing is below the floor (user rule: never below ground)."""
    r.apply(P)
    if hasattr(r, 'vox'):
        mrg.ground_clamp(r, FLOOR[0])


def base(P, t, k=2):
    """Real breathing: the body mesh swells, shoulders and wings follow, head and tail lag. Same at t=0 and t=1."""
    b, b1, b2, b3 = (breath(t, k, lag) for lag in (0.0, 0.08, 0.18, 0.30))
    P.grow('body', .030 * b, .022 * b, .030 * b)
    P.add('torso', rot=(0, -.8 * b, 0))
    P.add('head', d=(0, 0, .008 * b1), rot=(0, -.9 * b1, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * 1.4 * b3, 1.0 * b1, 0))
    P.add('tail', rot=(0, .9 * b2, 0))


def eyes(P, closed):
    s = max(.08, 1 - .92 * closed)
    P.set_scale('eye_p', (1, 1, s))
    P.set_scale('eye_n', (1, 1, s))


def wings(P, st, out, flap=0.0, fan=1.0):
    """Swing both wings out by `out` (0..1 of this stage's spread), `flap` adds degrees on top, `fan` opens the outer layers."""
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (WING_OUT[st] * out + flap), 0, 0))
        if st == 2:
            a, b2 = FAN[2]
            P.add('wing_out_' + s, rot=(0, a * out * fan, 0))
            P.add('wing_tip_' + s, rot=(0, b2 * out * fan, 0))


def idle_s0(r, t):
    """Chick: looks nervously to the right, then left, blinks, then ONE hop with a wing flap."""
    P = Pose()
    base(P, t, 2)
    yaw = gb.curve(t, [(0, 0), (.10, 1), (.24, 1), (.32, -1), (.46, -1), (.56, 0), (1, 0)])
    hop = pulse(t, .66, .74, .78, .86)
    flap = pulse(t, .66, .72, .80, .88) * (.5 + .5 * math.sin(2 * math.pi * 3 * (t - .66) - 1.2))
    P.add('head', rot=(3 * abs(yaw), -2 * abs(yaw), 36 * yaw))
    P.add('torso', rot=(0, 0, 6 * yaw))
    P.add('root', d=(0, 0, .06 * hop))
    wings(P, 0, 0, flap=48 * flap + 6 * hop)
    for s, sg in SG.items():
        P.add('leg_' + s, rot=(0, -6 * hop, 0))
    P.add('tail', rot=(0, -8 * hop, 5 * yaw))
    eyes(P, blink(t, .38) + blink(t, .60))
    fin(r, P)


def idle_s1(r, t):
    """Owl: the head turns 180 degrees, holds, and turns back THE SAME WAY. The body stays calm."""
    P = Pose()
    base(P, t, 2)
    yaw = gb.curve(t, [(0, 0), (.16, 0), (.42, 1), (.62, 1), (.86, 0), (1, 0)])
    P.add('head', d=(0, 0, .012 * math.sin(math.pi * yaw)), rot=(0, 0, 180 * yaw))
    P.add('torso', rot=(0, 0, 4 * math.sin(math.pi * yaw)))
    P.add('tail', rot=(0, 0, 4 * math.sin(math.pi * yaw)))
    eyes(P, blink(t, .08) + blink(t, .84))
    fin(r, P)


def idle_s2(r, t):
    """Great owl: wings open, ONE flap, wings fold."""
    P = Pose()
    base(P, t, 2)
    op = pulse(t, .14, .36, .66, .86)
    stroke = math.sin(math.pi * ramp(t, .40, .58))                  # one down-and-up beat
    P.add('root', d=(0, 0, .018 * stroke))
    P.add('head', rot=(0, -4 * op + 4 * stroke, 0))
    P.add('torso', rot=(0, -3 * op + 3 * stroke, 0))
    wings(P, 2, op, flap=-26 * stroke + 10 * stroke ** 2, fan=1.0 - .25 * stroke)
    P.add('tail', rot=(0, -6 * op, 0))
    eyes(P, blink(t, .10) + .3 * op * (1 - op))
    fin(r, P)


def make_attack(st):
    npeck = (2, 3, 3)[st]
    A = (.9, 1.0, 1.15)[st]

    def attack(r, t):
        P = Pose()
        base(P, t, 1)
        open_ = pulse(t, .02, .26, .80, .98)
        wind = gb.curve(t, [(0, 0), (.24, 1), (.30, 1), (.36, 0), (1, 0)])
        peck = 0.0
        t0 = .30
        width = .50 / npeck
        for i in range(npeck):
            a = t0 + i * width
            peck = max(peck, pulse(t, a, a + .035, a + .06, a + .10 + .02))
        lunge = pulse(t, .30, .40, .70, .86)
        P.add('root', d=(.05 * A * lunge, 0, 0), rot=(0, -3 * wind + 4 * lunge, 0))
        P.add('torso', rot=(0, -6 * wind + 10 * peck, 0))
        P.add('head', d=(.03 * peck, 0, 0), rot=(0, -12 * wind + (28, 36, 38)[st] * peck, 0))
        wings(P, st, open_, flap=-2 * peck)
        for s, sg in SG.items():
            P.add('leg_' + s, rot=(0, -4 * wind + 2 * lunge, 0))
        P.add('tail', rot=(0, -8 * wind + 12 * peck, 0))
        eyes(P, .35 * peck)
        fin(r, P)
    return attack


def make_hurt(st):
    def pose_hurt(r, t):
        P = Pose()
        base(P, t, 1)
        hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
        wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
        P.grow('body', .07 * hit, .07 * hit, .05 * hit)                      # feathers puff up
        P.add('root', d=(-.08 * hit, .01 * wob, 0), rot=(3 * wob, -8 * hit, 4 * wob))
        P.add('torso', rot=(0, -6 * hit, 0))
        P.add('head', rot=(0, -14 * hit, 8 * wob))
        wings(P, st, .45 * hit, flap=3 * math.cos(t * 9) * hit)
        for s, sg in SG.items():
            P.add('leg_' + s, rot=(0, (10 if s == 'p' else -6) * hit, 0))
        P.add('tail', rot=(0, 12 * hit, 18 * hit * math.cos(t * 6)))
        eyes(P, .9 * hit)
        fin(r, P)
        r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))
    return pose_hurt


def make_walk(st):
    big = st == 2

    def pose_walk(r, t):
        """s0/s1: a waddle, the body rolls over the planted leg. s2: long strides, wings slightly spread."""
        P = Pose()
        base(P, t, 1)
        s = 2 * math.pi * t
        amp = 34 if big else 26
        for nm, sgn in (('p', 1), ('n', -1)):
            th = -amp * sgn * math.sin(s)
            lf = max(0.0, sgn * math.cos(s))
            P.add('leg_' + nm, d=(0, 0, (.05 if big else .035) * lf), rot=(sgn * 10 * lf, th, 0))
        wings(P, st, .22 if big else 0.0, flap=3 * math.sin(2 * s) + 1.0)
        P.add('root', d=(0, 0, .016 * (1 - math.cos(2 * s)) / 2), rot=(-(5 if big else 7) * math.sin(s), 3 + 2 * math.cos(2 * s), 4 * math.sin(s)))
        P.add('torso', d=(.008 * math.sin(s - 1.4), 0, 0), rot=(2.5 * math.sin(s), -1.5 * math.cos(2 * s), 0))
        P.add('head', d=(.02 * math.sin(s - 1.0), 0, 0), rot=(4 * math.sin(s), -3 * math.cos(2 * s), -4 * math.sin(s)))
        P.add('tail', rot=(0, 3 * math.cos(2 * s), 10 * math.sin(s + .6)))
        fin(r, P)
    return pose_walk


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
    idle = (idle_s0, idle_s1, idle_s2)[st]
    walk = make_walk(st)

    def walk_in(r, t):
        fin(r, _cap(idle, 0.0).blend(_cap(walk, 0.0), gb.smooth(t)))

    def walk_out(r, t):
        fin(r, _cap(walk, 1.0).blend(_cap(idle, 0.0), gb.smooth(t)))
    return {'idle': (CFG[st]['idle_frames'], 12, True, idle), 'attack': (20, 16, False, make_attack(st)),
            'hurt': (10, 14, False, make_hurt(st)), 'walk': (8, 10, True, walk),
            'walk_in': (6, 10, False, walk_in), 'walk_out': (6, 10, False, walk_out)}


def _vec(P):
    out = {}
    for n in set(P.d) | set(P.gro) | set(P.scale):
        out[n] = list(P.d.get(n, [0, 0, 0])) + list(P.rot.get(n, [0, 0, 0])) + list(P.gro.get(n, [0, 0, 0]))
        s = P.scale.get(n)
        out[n] += [x - 1 for x in s] if isinstance(s, tuple) else [(s - 1)] * 3 if s is not None else [0, 0, 0]
    return out


def check_seams(table, walk):
    rv = _vec(_cap(table['idle'][3], 0.0))
    w0, w1 = _vec(_cap(walk, 0.0)), _vec(_cap(walk, 1.0))
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
    ap.add_argument('--out', default='docs/renders/monsters/owl_anim/tmp')
    ap.add_argument('--views', default='front')
    ap.add_argument('--headings', default='se,ne,nw,sw')
    ap.add_argument('--only', default='')
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--seams', action='store_true')
    ap.add_argument('--ground', action='store_true')
    ap.add_argument('--still')
    ap.add_argument('--pose')
    ap.add_argument('--view', default='front')
    a = ap.parse_args(argv)
    st = a.stage
    cfg = CFG[st]
    table = anims(st)
    only = [x for x in a.only.split(',') if x] or None
    if a.seams:
        check_seams(table, make_walk(st))
        return
    if a.ground:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        rig = build(st)
        bad = mrg.ground_report(rig, table)
        print('BELOW GROUND', len(bad), bad[:20])
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
    mrg.bake(lambda: build(st), table, a.out, a.views, a.samples, a.scale, cfg['map_k'], 'owl', st, cfg['shadow'], only,
             map_anims=('walk', 'walk_in', 'walk_out', 'idle'), headings=a.headings.split(','))


if __name__ == '__main__':
    main()
