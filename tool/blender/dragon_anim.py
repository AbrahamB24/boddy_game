"""Dragon line (3 stages): jointed rig + idle, attack, hurt, walk, baked to the sprite sheets the game reads.

    blender --background --python tool/blender/dragon_anim.py -- --stage 1 --out docs/renders/monsters/dragon_anim \
        [--views front,back,map] [--only idle,attack] [--samples 24] [--scale 0.5] [--seams] [--still x.png --pose idle:0.4]

The model is tool/blender/dragon.py (groups tagged there). Parts: body (breathes), head (+ brow, horns), eyes, wings (one rigid
piece per side, flap about the shoulder), front legs / arms, hind legs, tail. Rules: feedback 'animation-principles'.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dragon as dr  # noqa: E402
import glimmergnaw_bake as gb  # noqa: E402
import monster_rig as mrg  # noqa: E402
import phoenix_anim as pa  # noqa: E402
import pro_kit as K  # noqa: E402
from monster_rig import Pose, blink, breath, burst, osc, pulse, ramp  # noqa: E402

SG = {'p': 1, 'n': -1}
PX = {0: 0.0, 1: -.30, 2: -.40}      # x of the planted hind feet: pitching moves turn about THIS point, never the world origin
FLOOR = [0.0]
GUARD = [True]


def rp(P, st, deg, d=(0, 0, 0)):
    """Pitch the whole creature by deg (rot y) about its planted hind feet, plus an extra offset d."""
    a = math.radians(deg)
    px = PX[st]
    P.add('root', d=(px - px * math.cos(a) + d[0], d[1], px * math.sin(a) + d[2]), rot=(0, deg, 0))


CFG = {
    0: dict(shadow=(.50, .42, -.02), map_k=1.35, hip=(0, 0, .22)),
    1: dict(shadow=(.80, .46, -.14), map_k=1.85, hip=(-.05, 0, .30)),
    2: dict(shadow=(1.00, .50, -.26), map_k=2.25, hip=(-.10, 0, .32)),
}


def build(st):
    pal = dr.pal_for(st)
    # The game's sprite light lifts everything towards pastel (see phoenix_anim12): darker, more saturated bases land right.
    for k, v in list(pal.items()):
        if k in ('dark', 'eyewhite', 'white', 'nostril', 'brow'):
            continue
        r, g, b_ = (int(v[i:i + 2], 16) / 255 for i in (1, 3, 5))
        m = (r + g + b_) / 3
        r, g, b_ = (max(0, min(1, (c - m) * 1.12 + m)) * .74 for c in (r, g, b_))
        pal[k] = '#%02x%02x%02x' % (int(r * 255), int(g * 255), int(b_ * 255))
    b = pa.G(pal, 1.0)
    dr.build(b, st)
    p = dr.P[st]
    h, hr = p['head']
    k = p['k']
    ex, ez = h[0] + hr[0] * .80, h[2] - hr[2] * .02
    groups = {}
    for o in b.objs:
        groups.setdefault(o['grp'], []).append(o)
    w = p['wing']
    hx, hz = CFG[st]['hip'][0], CFG[st]['hip'][2]
    parts = {'torso': ('root', (hx, 0, hz)), 'body': ('torso', (hx, 0, hz))}
    head_piv = (h[0] - .06, 0, h[2] - .17) if st else (.02, 0, .56)
    parts['head'] = ('torso', head_piv)
    for s, sg in SG.items():
        parts['eye_' + s] = ('head', (ex, sg * hr[1] * .44, ez))
        parts['wing_' + s] = ('torso', (w['S'][0], sg * w['S'][1], w['S'][2]))
        if st == 0:
            a0 = p['arm'][0][0]
            parts['fleg_' + s] = ('torso', (a0[0], sg * a0[1], a0[2]))
            t = p['legs']['thigh'][0]
            parts['hleg_' + s] = ('root', (t[0], sg * p['legs']['y'], t[2] + .02))
        else:
            tx, tz = p['front']['top']
            parts['fleg_' + s] = ('root', (tx, sg * p['front']['y'], tz + .06))
            parts['hleg_' + s] = ('root', (p['hind']['x'], sg * p['hind']['y'], p['hind']['top'] + .06))
    tl = p['tail'][0]
    parts['tail'] = ('torso', (tl[0] + .06, 0, tl[2]))
    rig = mrg.Rig(parts, groups)
    FLOOR[0] = mrg.lowest_z(rig)
    return rig


# ── poses ─────────────────────────────────────────────────────
def base(P, t, st, k=2):
    """Real breathing (the body swells, head and tail lag), slow weight sway, wings settle with the breath."""
    b0, b1, b2 = (breath(t, k, lag) for lag in (0.0, 0.10, 0.25))
    P.grow('body', .030 * b0, .020 * b0, .028 * b0)
    P.add('torso', rot=(0, -.8 * b0, 0))
    P.add('head', d=(0, 0, .008 * b1), rot=(0, -1.2 * b1, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (1.6 * b1), 0, 0))
    P.add('tail', rot=(0, .9 * b2, 1.2 * osc(t, 1, .2)))
    P.add('root', rot=(.6 * osc(t, 1), 0, .4 * osc(t, 1, .25)))


def eyes(P, closed):
    s = max(.08, 1 - .92 * closed)
    P.set_scale('eye_p', (1, 1, s))
    P.set_scale('eye_n', (1, 1, s))


def idle0(r, t):
    """Hatchling: sits up, looks left and right, wiggles its wings and tail, stomps once."""
    P = Pose()
    base(P, t, 0, 2)
    look = pulse(t, .08, .16, .30, .38) - pulse(t, .46, .54, .66, .74)
    flut = pulse(t, .78, .82, .92, .96)
    P.add('head', rot=(0, -3 * abs(look), 16 * look))
    P.add('torso', rot=(0, 0, 4 * look))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (10 * flut * (.6 + .4 * math.sin(2 * math.pi * 7 * t)) + 3 * abs(look)), 0, 0))
        P.add('fleg_' + s, rot=(sg * 5 * flut, 0, 0))
    P.add('tail', rot=(0, 0, 14 * pulse(t, .50, .56, .66, .74) * math.sin(2 * math.pi * 3 * t) - 8 * look))
    eyes(P, blink(t, .60))
    r.apply(P)


def idle1(r, t):
    """Young dragon: stretches, spreads both wings wide and shakes them out, tail sweeps, then settles."""
    P = Pose()
    base(P, t, 1, 2)
    spread = pulse(t, .12, .30, .58, .76)
    shake = spread * math.sin(2 * math.pi * 3 * (t - .30))
    rp(P, 1, -3 * spread, (0, 0, .012 * spread))
    P.add('head', rot=(0, -12 * spread, 3 * math.sin(2 * math.pi * 2 * t) * spread))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (30 * spread + 5 * shake), -8 * spread, sg * -4 * spread))
    P.add('tail', rot=(0, -6 * spread, 12 * spread * math.sin(2 * math.pi * 1 * (t - .2))))
    eyes(P, .35 * spread + blink(t, .08))
    r.apply(P)


def idle2(r, t):
    """Great dragon: crouches, rears up, beats its wings twice and roars at the top, then settles."""
    P = Pose()
    base(P, t, 2, 2)
    c = pulse(t, .05, .18, .19, .26)
    rear = ramp(t, .20, .40) * (1 - ramp(t, .70, .88))
    beat = pulse(t, .40, .46, .70, .76)
    ph1 = 2 * math.pi * 2.0 * (t - .40)
    roar = pulse(t, .46, .52, .66, .72)
    rp(P, 2, -13 * rear, (-.03 * rear, 0, 0))
    P.add('torso', d=(0, 0, -.035 * c), rot=(0, 4 * c, 0))      # crouch: the body sinks between the planted legs, no pitch
    P.add('torso', rot=(0, -5 * rear, 0))
    P.add('head', rot=(0, 5 * c - 12 * rear - 14 * roar, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (10 * rear + 5 * c + 12 * beat * (1 + math.sin(ph1))), 0, 0))
        P.add('fleg_' + s, rot=(0, 10 * rear, 0))
        P.add('hleg_' + s, rot=(0, 5 * rear, 0))
    P.add('tail', rot=(0, 20 * rear + 4 * c, 7 * beat * math.sin(ph1 - 1.2)))
    eyes(P, .3 * roar + blink(t, .10))
    r.apply(P)


def make_attack(st):
    A = (.14, .20, .28)[st]

    def attack(r, t):
        P = Pose()
        base(P, t, st, 1)
        wind = gb.curve(t, [(0, 0), (.30, 1), (.42, 0), (1, 0)])
        hit = gb.curve(t, [(0, 0), (.30, 0), (.48, 1), (.62, .8), (1, 0)])
        rp(P, st, -6 * wind + 7 * hit, (-.05 * wind + A * hit, 0, -.02 * wind))
        P.add('torso', rot=(0, -4 * wind + 4 * hit, 0))
        P.add('head', d=(.05 * hit, 0, 0), rot=(0, -12 * wind + 26 * hit, 0))
        for s, sg in SG.items():
            P.add('wing_' + s, rot=(sg * (24 * wind - 6 * hit), 0, 0))
            P.add('fleg_' + s, rot=(0, -30 * hit if s == 'p' else -12 * hit, 0))
            P.add('hleg_' + s, rot=(0, 6 * hit, 0))
        P.add('tail', rot=(0, 8 * wind + 14 * hit, 0))
        eyes(P, .4 * hit)
        r.apply(P)
    return attack


def pose_hurt(r, t, st=1):
    P = Pose()
    base(P, t, st, 1)
    hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    rp(P, st, -8 * hit, (-.09 * hit, .01 * wob, 0)); P.add('root', rot=(3 * wob, 0, 4 * wob))
    P.add('torso', rot=(0, -5 * hit, 0))
    P.add('head', rot=(0, -16 * hit, 10 * wob))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * 18 * hit, 0, 0))
        P.add('fleg_' + s, rot=(0, (10 if s == 'p' else -6) * hit, 0))
    P.add('tail', rot=(0, 14 * hit, 20 * hit * math.cos(t * 6)))
    eyes(P, .9 * hit)
    r.apply(P)
    r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))


def make_walk(st):
    def walk(r, t):
        P = Pose()
        base(P, t, st, 1)
        s = 2 * math.pi * t
        amp = 22 if st else 26
        for nm, sgn in (('p', 1), ('n', -1)):
            # diagonal gait: front p with hind n
            f, hnd = sgn * math.sin(s), -sgn * math.sin(s)
            lf, lh = max(0.0, sgn * math.cos(s)), max(0.0, -sgn * math.cos(s))
            P.add('fleg_' + nm, d=(0, 0, .035 * lf), rot=(sgn * 6 * lf, -amp * f * (0 if st == 0 else 1) - (14 * f if st == 0 else 0), 0))
            P.add('hleg_' + nm, d=(0, 0, .035 * lh), rot=(-sgn * 6 * lh, -amp * hnd, 0))
            P.add('wing_' + nm, rot=(sgn * (2.5 * math.sin(2 * s) + 1.0), 0, 0))
        P.add('root', d=(0, 0, .014 * (1 - math.cos(2 * s)) / 2), rot=(-3 * math.sin(s), 2 + 1.5 * math.cos(2 * s), 3 * math.sin(s)))
        P.add('torso', rot=(2.0 * math.sin(s), -1.2 * math.cos(2 * s), 2 * math.sin(s - .5)))
        P.add('head', d=(.02 * math.sin(s - 1.0), 0, 0), rot=(3 * math.sin(s), -2 * math.cos(2 * s), -4 * math.sin(s)))
        P.add('tail', rot=(0, 3 * math.cos(2 * s), 14 * math.sin(s + .6)))
        r.apply(P)
    return walk


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
    idle = (idle0, idle1, idle2)[st]
    walk = make_walk(st)

    def walk_in(r, t):
        r.apply(_cap(idle, 0.0).blend(_cap(walk, 0.0), gb.smooth(t)))

    def walk_out(r, t):
        r.apply(_cap(walk, 1.0).blend(_cap(idle, 0.0), gb.smooth(t)))
    def guard(fn):
        def g(r, t):
            fn(r, t)
            if GUARD[0]:
                mrg.ground_clamp(r, FLOOR[0])
        return g
    tbl = {'idle': (30, 12, True, idle), 'attack': (16, 16, False, make_attack(st)),
            'hurt': (10, 14, False, lambda r, t: pose_hurt(r, t, st)), 'walk': (8, 10, True, walk),
            'walk_in': (6, 10, False, walk_in), 'walk_out': (6, 10, False, walk_out)}
    return {k: (n, f, lp, guard(fn)) for k, (n, f, lp, fn) in tbl.items()}


def _vec(P):
    out = {}
    for n in set(P.d) | set(P.gro) | set(P.scale):
        out[n] = list(P.d.get(n, [0, 0, 0])) + list(P.rot.get(n, [0, 0, 0])) + list(P.gro.get(n, [0, 0, 0]))
        s = P.scale.get(n)
        out[n] += [x - 1 for x in s] if isinstance(s, tuple) else [(s - 1)] * 3 if s is not None else [0, 0, 0]
    return out


def check_seams(table, st):
    rv = _vec(_cap(table['idle'][3], 0.0))
    walk = table['walk'][3]
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
    ap.add_argument('--out', required=True)
    ap.add_argument('--views', default='front')
    ap.add_argument('--headings', default='se,ne,nw,sw')
    ap.add_argument('--only', default='')
    ap.add_argument('--samples', type=int, default=32)
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--seams', action='store_true')
    ap.add_argument('--raw', action='store_true', help='with --ground: check the poses without the clamp')
    ap.add_argument('--ground', action='store_true', help='report every frame that reaches below the floor (guard off)')
    ap.add_argument('--still')
    ap.add_argument('--pose')
    ap.add_argument('--view', default='front')
    a = ap.parse_args(argv)
    st = a.stage
    cfg = CFG[st]
    table = anims(st)
    only = [x for x in a.only.split(',') if x] or None
    if a.ground:
        GUARD[0] = not a.raw
        bpy.ops.wm.read_factory_settings(use_empty=True)
        K._mats.clear()
        rig = build(st)
        bad = mrg.ground_report(rig, anims(st))
        print('BELOW GROUND', len(bad), bad[:20])
        return
    if a.seams:
        check_seams(table, st)
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
    mrg.bake(lambda: build(st), table, a.out, a.views, a.samples, a.scale, cfg['map_k'], 'dragon', st, cfg['shadow'], only,
             map_anims=('walk', 'walk_in', 'walk_out', 'idle'), headings=a.headings.split(','))


if __name__ == '__main__':
    main()
