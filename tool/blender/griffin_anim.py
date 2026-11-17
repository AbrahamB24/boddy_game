"""Griffin line (3 stages): jointed rig + ONE idle per stage, attack, hurt, walk (owl_anim.py pattern).

    blender --background --python tool/blender/griffin_anim.py -- --stage 0 --out docs/renders/monsters/griffin_anim/s0 \
        [--views front,map] [--headings se,ne] [--only idle,attack] [--samples 32] [--scale 1.0]
    ... --seams      every clip starts/ends in the rest pose (walk has in/out clips)
    ... --ground     nothing ever goes below the floor, in any frame
    ... --still x.png --pose idle:0.4 [--view front]

My choices (user gave no idle wishes for the griffin): s0 idle = looks around and pecks the ground; s1 idle = ruffles, quick wing
flutter; s2 idle = rears up and spreads the wings with ONE beat. Combat: wings open, 2-3 pecks / lunge, hurt = puff + jerk back.
Rotations as in owl_anim: rot y > 0 tips the top FORWARD; rot x on a wing: + raises outward-pointing feathers (sg * a).
Parts: torso/body/head/tail, eye_p/n, wing_p/n (+wing_out_), legf_p/n (front), legh_p/n (hind).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_bake as gb  # noqa: E402
import griffin as gr  # noqa: E402
import monster_rig as mrg  # noqa: E402
import phoenix_anim as pa  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
from monster_rig import Pose, blink, breath, burst, osc, pulse, ramp  # noqa: E402

SG = {'p': 1, 'n': -1}
FLOOR = [0.0]
DARKEN, SAT = .66, 1.35
STAGE_TONE = {0: (1.15, .70), 1: (1.15, .70), 2: (1.1, .68)}
WING_OUT = {0: 18, 1: 22, 2: 24}                   # how far the wings raise when "spread" (deg)
CFG = {
    0: dict(shadow=(.46, .38, -.02), map_k=1.25, idle_frames=40),
    1: dict(shadow=(.50, .38, -.02), map_k=1.35, idle_frames=36),
    2: dict(shadow=(.62, .42, -.10), map_k=1.60, idle_frames=36),
}
J = {   # joints for the 2026-11-14 model (griffin.py stage0..2: head centre, shoulder = first wing root, leg tops, tail base)
    0: dict(neck=(.12, 0, .56), sh=(-.02, .20, .56), lf=(.04, .15, .30), lh=(-.34, .15, .34), tail=(-.40, 0, .44), eye=(.348, .146, .765), tor=(0, 0, .30)),
    1: dict(neck=(.25, 0, .74), sh=(-.04, .27, .66), lf=(.06, .16, .30), lh=(-.52, .16, .38), tail=(-.64, 0, .62), eye=(.51, .162, .975), tor=(0, 0, .40)),
    2: dict(neck=(.40, 0, .98), sh=(.04, .36, .95), lf=(.32, .19, .45), lh=(-.50, .20, .50), tail=(-.62, 0, .74), eye=(.70, .162, 1.256), tor=(0, 0, .45)),
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
    pal = {k: (v if k in ('dark', 'white', 'eyewhite') else _dark(v)) for k, v in gr.pal_for(st).items()}
    b = pa.G(pal, 1.0)
    tw.DEPTH = 8
    gr.STAGES[st](b)
    groups = {}
    for o in b.objs:
        groups.setdefault(o['grp'], []).append(o)
    j = J[st]
    ex, ey, ez = j['eye']
    parts = {'torso': ('root', j['tor']), 'body': ('torso', j['tor']), 'head': ('torso', j['neck']), 'tail': ('torso', j['tail'])}
    for s, sg in SG.items():
        parts['eye_' + s] = ('head', (ex, sg * ey, ez))
        parts['wing_' + s] = ('torso', (j['sh'][0], sg * j['sh'][1], j['sh'][2]))
        if st > 0:
            parts['wing_out_' + s] = ('wing_' + s, (j['sh'][0], sg * j['sh'][1], j['sh'][2]))
        parts['legf_' + s] = ('torso', (j['lf'][0], sg * j['lf'][1], j['lf'][2]))
        parts['legh_' + s] = ('torso', (j['lh'][0], sg * j['lh'][1], j['lh'][2]))
    rig = mrg.Rig(parts, groups)
    rig.reset()
    FLOOR[0] = mrg.lowest_z(rig)
    return rig


def fin(r, P):
    r.apply(P)
    if hasattr(r, 'vox'):
        mrg.ground_clamp(r, FLOOR[0])


def base(P, t, k=2):
    """Real breathing: the body swells, shoulders and wings follow, head and tail lag. Same at t=0 and t=1."""
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


def wings(P, st, out, flap=0.0):
    """Raise both wings by `out` (0..1 of this stage's spread); `flap` adds degrees on top (+ = up)."""
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (WING_OUT[st] * out + flap), 0, 0))


def scratch(t, t0=.04, t1=.36, reps=3):
    """Chick scratches the ground with its right foot: reach forward (lifted), then rake back with the foot on the ground.
    Returns (leg pitch deg, lift, envelope); everything is 0 outside [t0, t1] so the clip stays on the rest pose."""
    if not (t0 < t < t1):
        return 0.0, 0.0, 0.0
    x = (t - t0) / (t1 - t0)
    env = min(1.0, x * 6, (1 - x) * 6)
    u = (x * reps) % 1.0
    if u < .45:
        k = u / .45
        rot, lift = 14 - 56 * gb.smooth(k), math.sin(math.pi * k)
    else:
        k = (u - .45) / .55
        rot, lift = -42 + 56 * k, 0.0
    return rot * env, lift * env, env


def idle_s0(r, t):
    """Chick: first scratches the ground with a foot (user 2026-11-16), then looks left and right, blinks, pecks twice."""
    P = Pose()
    base(P, t, 2)
    sr, sl, se = scratch(t)
    P.add('legf_p', d=(0, 0, .07 * sl), rot=(0, sr, 0))
    yaw = gb.curve(t, [(0, 0), (.38, 0), (.46, 1), (.54, 1), (.62, -1), (.70, -1), (.76, 0), (1, 0)])
    peck = max(pulse(t, .80, .83, .85, .88), pulse(t, .89, .92, .94, .97))
    P.add('head', rot=(0, 2 * abs(yaw) + 34 * peck + 24 * se, 34 * yaw))
    P.add('torso', rot=(0, 5 * peck + 8 * se, 5 * yaw))
    P.add('tail', rot=(0, -6 * peck, 6 * yaw))
    wings(P, 0, 0, flap=4 * peck + 3 * se)
    eyes(P, blink(t, .40) + blink(t, .78))
    fin(r, P)


def idle_s1(r, t):
    """Juvenile: ruffles up, quick wing flutter, shakes the head."""
    P = Pose()
    base(P, t, 2)
    fl = pulse(t, .22, .30, .64, .72)
    flut = fl * (.5 + .5 * math.sin(2 * math.pi * 5 * (t - .22)))
    puff = pulse(t, .20, .34, .60, .74)
    P.grow('body', .09 * puff, .10 * puff, .05 * puff)
    wings(P, 1, .8 * fl, flap=46 * flut - 8 * fl)
    P.add('root', d=(0, 0, .035 * fl * max(0.0, math.sin(2 * math.pi * 5 * (t - .22)))))   # two or three little hops with the beats
    P.add('head', rot=(0, 0, 12 * burst(t, .74, 3.0, 4.0) * (1 - ramp(t, .88, 1.0))))
    P.add('torso', rot=(0, 0, 3 * burst(t, .74, 3.0, 4.0) * (1 - ramp(t, .88, 1.0)) + 3 * fl * math.sin(2 * math.pi * 6 * t)))
    P.add('tail', rot=(0, 3 * fl, 8 * fl * math.sin(2 * math.pi * 6 * t)))
    eyes(P, blink(t, .08) + blink(t, .84))
    fin(r, P)


def idle_s2(r, t):
    """Griffin: rears up on the hind legs, wings spread, ONE beat, settles down."""
    P = Pose()
    base(P, t, 2)
    up = pulse(t, .12, .36, .70, .90)
    beat = math.sin(math.pi * ramp(t, .42, .62))
    P.add('torso', rot=(0, -26 * up, 0))
    P.add('head', rot=(0, 6 * up - 3 * beat, 0))
    for s, sg in SG.items():
        P.add('legf_' + s, rot=(0, 34 * up, 0))   # fold back under the chest instead of reaching forward
        P.add('legh_' + s, rot=(0, 24 * up, 0))
    wings(P, 2, 1.5 * up, flap=-55 * beat + 14 * up)
    P.add('tail', rot=(0, 10 * up, 0))
    eyes(P, blink(t, .08) + .25 * up * (1 - up))
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
        width = .50 / npeck
        for i in range(npeck):
            a = .30 + i * width
            peck = max(peck, pulse(t, a, a + .035, a + .06, a + .12))
        lunge = pulse(t, .30, .40, .70, .86)
        P.add('root', d=(.05 * A * lunge, 0, 0), rot=(0, -3 * wind + 4 * lunge, 0))
        P.add('torso', rot=(0, -6 * wind + 9 * peck, 0))
        P.add('head', d=(.03 * peck, 0, 0), rot=(0, -12 * wind + (28, 34, 36)[st] * peck, 0))
        wings(P, st, open_, flap=-3 * peck)
        for s, sg in SG.items():
            P.add('legf_' + s, rot=(0, -4 * wind + (-16 if s == 'p' else 0) * peck, 0))
            P.add('legh_' + s, rot=(0, 3 * wind, 0))
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
        P.grow('body', .07 * hit, .07 * hit, .05 * hit)
        P.add('root', d=(-.08 * hit, .01 * wob, 0), rot=(3 * wob, -8 * hit, 4 * wob))
        P.add('torso', rot=(0, -6 * hit, 0))
        P.add('head', rot=(0, -14 * hit, 8 * wob))
        wings(P, st, .6 * hit, flap=3 * math.cos(t * 9) * hit)
        for s, sg in SG.items():
            P.add('legf_' + s, rot=(0, (10 if s == 'p' else -6) * hit, 0))
        P.add('tail', rot=(0, 12 * hit, 18 * hit * math.cos(t * 6)))
        eyes(P, .9 * hit)
        fin(r, P)
        r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))
    return pose_hurt


def make_walk(st):
    big = st == 2

    def pose_walk(r, t):
        """Diagonal gait: front-right + hind-left together, then the other pair; body bob, head counter-motion, wings slightly raised."""
        P = Pose()
        base(P, t, 1)
        s = 2 * math.pi * t
        amp = 28 if big else 24
        for nm, sg in (('p', 1), ('n', -1)):
            for pre, ph_ in (('legf_', 0.0), ('legh_', math.pi)):
                a = s + ph_ + (0 if sg > 0 else math.pi)
                lf = max(0.0, math.cos(a))
                P.add(pre + nm, d=(0, 0, (.05 if big else .035) * lf), rot=(0, -amp * math.sin(a), 0))
        wings(P, st, .15 if big else 0.0, flap=2 * math.sin(2 * s) + 1.0)
        P.add('root', d=(0, 0, .014 * (1 - math.cos(2 * s)) / 2), rot=(-3 * math.sin(s), 1 + 1.5 * math.cos(2 * s), 3 * math.sin(s)))
        P.add('torso', d=(.008 * math.sin(s - 1.4), 0, 0), rot=(1.5 * math.sin(s), -1.2 * math.cos(2 * s), 0))
        P.add('head', d=(.02 * math.sin(s - 1.0), 0, 0), rot=(0, -3 * math.cos(2 * s), -4 * math.sin(s)))
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
    ap.add_argument('--out', default='docs/renders/monsters/griffin_anim/tmp')
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
    mrg.bake(lambda: build(st), table, a.out, a.views, a.samples, a.scale, cfg['map_k'], 'griffin', st, cfg['shadow'], only,
             map_anims=('walk', 'walk_in', 'walk_out', 'idle'), headings=a.headings.split(','))


if __name__ == '__main__':
    main()
