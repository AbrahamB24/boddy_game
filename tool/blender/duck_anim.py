"""Duck line (3 stages): jointed rig + ONE idle per stage, attack, hurt, walk. Same rig/bake pipeline as the phoenix.

    blender --background --python tool/blender/duck_anim.py -- --stage 0 --out docs/renders/monsters/duck_anim/s0 \
        [--views front,map] [--headings se,ne] [--only idle,attack] [--samples 32] [--scale 1.0]
    ... --seams      every clip starts/ends in the rest pose (walk has in/out clips)
    ... --clearance  feet and wings never sink into the body, in any frame
    ... --still x.png --pose idle:0.4 [--view front]

Rules (memory 'animation-principles'): ONE idle per stage and all three different
  s0 = looks around with a head tilt and a wing flutter, s1 = ruffles: quick wing flaps, tail leaf whips, a hop,
  s2 = stretches its neck up, quacks twice with half-spread wings.
Real breathing (the single body mesh swells), nothing may flicker, cut or sink.
Rotations: rot y > 0 tips the top FORWARD (head nods down), a wing that points back lifts with rot y > 0 and spreads
outwards with rot z = -side * angle.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import duck as dk  # noqa: E402
import glimmergnaw_bake as gb  # noqa: E402
import monster_rig as mrg  # noqa: E402
import phoenix_anim as pa  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
from monster_rig import Pose, blink, breath, burst, osc, pulse, ramp  # noqa: E402

SG = {'p': 1, 'n': -1}
DARKEN = .66                                       # the game's sprite light lifts colours towards pastel (see phoenix_anim12):
SAT = 1.35                                         # darker AND more saturated bases land on the intended colours
STAGE_TONE = {0: (2.4, .80), 1: (1.55, .80), 2: (1.35, .66)}     # (saturation x, value x) per stage, tuned on stills
CFG = {
    0: dict(shadow=(.40, .32, -.04), map_k=1.25, amp=1.0, idle_frames=28),
    1: dict(shadow=(.46, .36, -.04), map_k=1.35, amp=1.0, idle_frames=30),
    2: dict(shadow=(.52, .34, -.06), map_k=1.45, amp=1.0, idle_frames=30),
}
INFO = {}


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
    pal = {k: (v if k in ('dark', 'white', 'eyewhite') else _dark(v)) for k, v in dk.pal_for(st).items()}
    b = pa.G(pal, 1.0)
    tw.DEPTH = 8
    info = dk.build(b, st)
    INFO[st] = info
    groups = {}
    for o in b.objs:
        groups.setdefault(o['grp'], []).append(o)
    sh, hp, an = info['shoulder'], info['hip'], info['ankle']
    ex, ey, ez = info['eye']
    parts = {
        'torso': ('root', info['torso']),
        'body': ('torso', info['torso']),
        'head': ('torso', info['neck']),
        'bill': ('head', info['hinge']),
        'tail': ('torso', info['tail']),
    }
    for s, sg in SG.items():
        parts['eye_' + s] = ('head', (ex, sg * ey, ez))
        parts['wing_' + s] = ('torso', (sh[0], sg * sh[1], sh[2]))
        parts['leg_' + s] = ('root', (hp[0], sg * hp[1], hp[2]))
        parts['foot_' + s] = ('leg_' + s, (an[0], sg * an[1], an[2]))
    return mrg.Rig(parts, groups)


# ── poses ─────────────────────────────────────────────────────
def base(P, t, k=2):
    """Real breathing: the body mesh swells, shoulders and wings follow, head and tail lag. Same at t=0 and t=1."""
    b, b1, b2, b3 = (breath(t, k, lag) for lag in (0.0, 0.08, 0.18, 0.30))
    P.grow('body', .032 * b, .022 * b, .030 * b)
    P.add('torso', rot=(0, -.9 * b, 0))
    P.add('head', d=(0, 0, .008 * b1), rot=(0, -1.0 * b1, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(0, 1.2 * b1, -sg * 1.4 * b3))
    P.add('tail', rot=(0, .9 * b2, 0))
    P.add('root', rot=(.6 * osc(t, 1), 0, .4 * osc(t, 1, .25)))


def eyes(P, closed):
    s = max(.08, 1 - .92 * closed)
    P.set_scale('eye_p', (1, 1, s))
    P.set_scale('eye_n', (1, 1, s))


def idle_s0(r, t):
    """Duckling: looks to the right, then left, with a cute head tilt, a quick wing flutter and a little hop."""
    P = Pose()
    base(P, t, 2)
    yaw = gb.curve(t, [(0, 0), (.14, 1), (.32, 1), (.46, -1), (.66, -1), (.80, 0), (1, 0)])
    tilt = gb.curve(t, [(0, 0), (.14, 1), (.32, 1), (.46, -1), (.66, -1), (.80, 0), (1, 0)])
    flut = pulse(t, .70, .74, .88, .92)
    hop = pulse(t, .80, .86, .88, .94)
    P.add('head', rot=(8 * tilt, -2 * abs(yaw), 30 * yaw))
    P.add('torso', rot=(0, 0, 8 * yaw))
    P.add('root', d=(0, 0, .035 * hop))
    P.add('bill', rot=(0, 5 * pulse(t, .10, .13, .22, .26), 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(0, 10 * flut * (.5 + .5 * math.sin(2 * math.pi * 7 * t)) + 4 * hop, -sg * (14 * flut * math.sin(2 * math.pi * 7 * t + .3) + 6 * hop)))
        P.add('foot_' + s, rot=(0, -3 * hop, 0))
    P.add('tail', rot=(0, 0, 14 * burst(t, .70, 5, 3.5) + 5 * math.sin(2 * math.pi * t)))
    eyes(P, blink(t, .50))
    r.apply(P)


def idle_s1(r, t):
    """Yellow duck: ruffles up: head shake, quick triple wing flap, the tail leaf whips back, a small hop."""
    P = Pose()
    base(P, t, 2)
    fade = 1 - ramp(t, .74, .94)
    H = burst(t, .08, 3.5, 3.2, 26) * fade
    flap = pulse(t, .22, .28, .56, .62)
    ph = 2 * math.pi * 3 * (t - .22)
    hop = pulse(t, .26, .34, .38, .46)
    P.add('head', rot=(0, -.15 * H, H))
    P.add('torso', rot=(0, 0, .26 * burst(t, .105, 3.5, 3.2, 26) * fade))
    P.add('root', d=(0, 0, .05 * hop), rot=(0, 0, .10 * burst(t, .13, 3.5, 3.2, 26) * fade))
    P.add('tail', rot=(0, -10 * flap + 3 * burst(t, .16, 3.5, 3.2, 20) * fade, 12 * burst(t, .16, 3.5, 3.2, 26) * fade))
    P.add('bill', rot=(0, 7 * pulse(t, .08, .12, .20, .30), 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(0, 34 * flap * (.5 + .5 * math.sin(ph)) + 3 * hop, -sg * (22 * flap * (.5 + .5 * math.sin(ph)))))
        P.add('foot_' + s, rot=(0, -6 * hop, 0))
        P.add('leg_' + s, rot=(0, -4 * hop, 0))
    eyes(P, .6 * pulse(t, .08, .12, .5, .7))
    r.apply(P)


def idle_s2(r, t):
    """Blue duck: stretches its neck up, half-spreads its wings and quacks twice, then settles."""
    P = Pose()
    base(P, t, 2)
    up = pulse(t, .08, .26, .74, .90)
    q1 = pulse(t, .30, .34, .38, .42)
    q2 = pulse(t, .46, .50, .54, .58)
    quack = q1 + q2
    spread = pulse(t, .24, .38, .56, .74)
    P.add('torso', rot=(0, -5 * up, 0))
    P.add('root', d=(-.01 * up, 0, .02 * up), rot=(0, -3 * up, 0))
    P.add('head', d=(0, 0, .03 * up), rot=(0, -10 * up - 6 * quack, 0))
    P.add('bill', rot=(0, 26 * quack, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(0, 10 * spread + 4 * quack, -sg * (16 * spread + 3 * quack)))
        P.add('foot_' + s, rot=(0, 3 * up, 0))
    P.add('tail', rot=(0, -8 * up + 4 * quack, 8 * math.sin(2 * math.pi * 2 * t) * spread))
    eyes(P, blink(t, .08) + .25 * quack)
    r.apply(P)


def make_attack(A, st):
    def attack(r, t):
        P = Pose()
        base(P, t, 1)
        wind = gb.curve(t, [(0, 0), (.30, 1), (.42, 0), (1, 0)])
        hit = gb.curve(t, [(0, 0), (.30, 0), (.48, 1), (.62, .8), (1, 0)])
        bite = gb.curve(t, [(0, 0), (.28, 0), (.38, 1), (.47, 1), (.52, 0), (1, 0)])
        hop = pulse(t, .34, .44, .52, .64)
        P.add('root', d=(-.05 * wind + .20 * A * hit, 0, -.025 * wind + .03 * hop), rot=(0, -6 * wind + 8 * hit, 0))
        P.add('torso', rot=(0, -4 * wind + 8 * hit, 0))
        P.add('head', d=(.04 * hit, 0, 0), rot=(0, -12 * wind + 26 * hit, 0))
        P.add('bill', rot=(0, 8 * wind + 24 * bite, 0))
        for s, sg in SG.items():
            P.add('wing_' + s, rot=(0, 14 * wind - 4 * hit, -sg * (16 * wind + 10 * hit)))
            P.add('leg_' + s, rot=(0, -30 * hit if s == 'p' else -12 * hit, 0))
            P.add('foot_' + s, rot=(0, 8 * hit, 0))
        P.add('tail', rot=(0, -10 * wind + 14 * hit, 0))
        eyes(P, .4 * hit)
        r.apply(P)
    return attack


def pose_hurt(r, t):
    P = Pose()
    base(P, t, 1)
    hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    P.add('root', d=(-.09 * hit, .01 * wob, 0), rot=(3 * wob, -8 * hit, 4 * wob))
    P.add('torso', rot=(0, -6 * hit, 0))
    P.add('head', rot=(0, -16 * hit, 10 * wob))
    P.add('bill', rot=(0, 14 * hit, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(0, 14 * hit, -sg * (20 * hit + 8 * hit * math.cos(t * 9))))
        P.add('leg_' + s, rot=(0, (12 if s == 'p' else -8) * hit, 0))
    P.add('tail', rot=(0, 14 * hit, 20 * hit * math.cos(t * 6)))
    eyes(P, .9 * hit)
    r.apply(P)
    r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))


def pose_walk(r, t):
    """A duck's waddle: the body rolls over the planted leg, legs swing alternately, head bobs, tail wags."""
    P = Pose()
    base(P, t, 1)
    s = 2 * math.pi * t
    for nm, sgn in (('p', 1), ('n', -1)):
        th = -28 * sgn * math.sin(s)
        lf = max(0.0, sgn * math.cos(s))
        P.add('leg_' + nm, d=(0, 0, .035 * lf), rot=(sgn * 12 * lf, th, 0))
        P.add('foot_' + nm, rot=(0, -.5 * th - 16 * lf, 0))
        P.add('wing_' + nm, rot=(0, 2 * math.sin(2 * s) + 1.0, -sgn * (2.5 + 2 * math.sin(2 * s - .8))))
    P.add('root', d=(0, 0, .016 * (1 - math.cos(2 * s)) / 2), rot=(-6 * math.sin(s), 3 + 2 * math.cos(2 * s), 4 * math.sin(s)))
    P.add('torso', d=(.008 * math.sin(s - 1.4), 0, 0), rot=(2.5 * math.sin(s), -1.5 * math.cos(2 * s), 0))
    P.add('head', d=(.025 * math.sin(s - 1.0), 0, 0), rot=(4 * math.sin(s), -3 * math.cos(2 * s), -4 * math.sin(s)))
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


def anims(st):
    idle = (idle_s0, idle_s1, idle_s2)[st]

    def walk_in(r, t):
        r.apply(_cap(idle, 0.0).blend(_cap(pose_walk, 0.0), gb.smooth(t)))

    def walk_out(r, t):
        r.apply(_cap(pose_walk, 1.0).blend(_cap(idle, 0.0), gb.smooth(t)))
    A = (.9, 1.0, 1.15)[st]
    return {'idle': (CFG[st]['idle_frames'], 12, True, idle), 'attack': (16, 16, False, make_attack(A, st)),
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
    rv = _vec(_cap(table['idle'][3], 0.0))
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
    ap.add_argument('--out', default='docs/renders/monsters/duck_anim/tmp')
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
        i = INFO[st]
        bad = mrg.clearance(rig, table, ellipsoid=(i['body_c'], i['body_r']), tilt=i['tilt'],
                            watch=('foot_p', 'foot_n', 'wing_p', 'wing_n'))
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
    mrg.bake(lambda: build(st), table, a.out, a.views, a.samples, a.scale, cfg['map_k'], 'duck', st, cfg['shadow'], only,
             map_anims=('walk', 'walk_in', 'walk_out', 'idle'), headings=a.headings.split(','))


if __name__ == '__main__':
    main()
