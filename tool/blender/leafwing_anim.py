"""Leafwing line (3 stages): jointed rig + ONE idle per stage, attack, hurt, walk (griffin_anim.py pattern).

    blender --background --python tool/blender/leafwing_anim.py -- --stage 0 --out docs/renders/monsters/leafwing_anim/s0 \
        [--views front,map] [--headings se,ne] [--only idle,attack] [--samples 32] [--scale 1.0]
    ... --seams      every clip starts/ends in the rest pose (walk has in/out clips)
    ... --ground     nothing ever goes below the floor, in any frame
    ... --still x.png --pose idle:0.4 [--view front]

(Stage numbers here are the code's 0-2 = the user's Stufe 1-3.)
Stufe 1 (s0) hovering leaf-manta : idle = drifts like a leaf in the wind (wing edges ripple root to tip, body sways, tail trails)
                                   attack = pulls back, rams head first, wings sweep back; walk = glides, slow wing stroke
Stufe 2 (s1) baby dragon, tiny feet: idle = excited flutter hop (3-4 quick beats, lifts off, lands) then looks around
                                   attack = flutters up, horn thrust, one wing beat; walk = hop + flutter in turns
Stufe 3 (s2) upright dragon      : idle = rears up, spreads the wings with ONE slow beat; attack = crouch, leap, wings slam forward
                                   walk = real biped gait (alternating legs, planted feet, body roll, head counter-motion)
Wings are ONE rigid part per side (a membrane torn between two parts would open slits); they flap about the shoulder.
Rotations: rot y > 0 tips the top FORWARD; rot x on a wing: sg * a raises the outer edge; rot z on a wing: sg * a sweeps it back.
Parts: torso/body/head/tail/tailtip, eye_p/n, wing_p/n, leg_p/n (stage 2 only).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glimmergnaw_bake as gb  # noqa: E402
import leafwing as lw  # noqa: E402
import monster_rig as mrg  # noqa: E402
import phoenix_anim as pa  # noqa: E402
import pro_kit as K  # noqa: E402
import thunderwake_voxel as tw  # noqa: E402
from monster_rig import Pose, blink, breath, pulse, ramp  # noqa: E402

SG = {'p': 1, 'n': -1}
FLOOR = [0.0]
CFG = {
    0: dict(shadow=(.50, .42, -.04), map_k=1.25, idle_frames=40),
    1: dict(shadow=(.50, .46, -.08), map_k=1.5, idle_frames=40),
    2: dict(shadow=(.46, .40, -.04), map_k=2.3, pad=.44, idle_frames=40),
}
# joints in the model's own (pre-pose) coordinates; stage 2 is pitched/lifted by lw.pose() afterwards, see _pose_matrix()
J = {
    0: dict(tor=(-.06, 0, .20), neck=(.12, 0, .28), sh=(-.02, .22, .27), tail=(-.30, 0, .20), tip=(-.82, .229, .34), eye=(.468, .155, .308)),
    1: dict(tor=(-.10, 0, .24), neck=(.14, 0, .34), sh=(-.04, .26, .36), tail=(-.42, 0, .24), tip=(-1.16, .299, .60), eye=(.518, .155, .378)),
    2: dict(tor=(-.05, 0, .46), neck=(.08, 0, 1.18), sh=(-.04, .22, 1.02), tail=(-.20, 0, .22), tip=(-1.06, .282, .50), eye=(.388, .156, 1.419),
            hip=(.06, .17, .38)),
}


def _pose_matrix(st):
    if st != 2:
        return Matrix.Identity(4)
    p = Vector((0, 0, .6))
    return Matrix.Translation(Vector((0, 0, .55))) @ Matrix.Translation(p) @ Matrix.Rotation(math.radians(20), 4, 'Y') @ Matrix.Translation(-p)


def _dark(hexcol):
    """Same tone as the other baked monsters: the battle lighting washes the plain palette out."""
    import colorsys
    c = hexcol.lstrip("#")
    r, g, b = (int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, s * 1.15), v * .70)
    return "#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255))


def build(st):
    pal = {k: (v if k in ("dark", "white", "eyewhite") else _dark(v)) for k, v in lw.pal_for(st).items()}
    b = pa.G(pal, 1.0)
    tw.DEPTH = 8
    lw.STAGES[st](b)
    groups = {}
    for o in b.objs:
        groups.setdefault(o['grp'], []).append(o)
    M = _pose_matrix(st)
    j = {k: tuple(M @ Vector(v)) for k, v in J[st].items()}

    def mir(p, sg):
        return (p[0], sg * abs(p[1]), p[2])
    parts = {'torso': ('root', j['tor']), 'body': ('torso', j['tor']), 'head': ('torso', j['neck']), 'tail': ('torso', j['tail']),
             'tailtip': ('tail', j['tip'])}
    for s, sg in SG.items():
        parts['eye_' + s] = ('head', mir(j['eye'], sg))
        parts['wing_' + s] = ('torso', mir(j['sh'], sg))
        if st == 2:
            parts['leg_' + s] = ('torso', mir(j['hip'], sg))
    rig = mrg.Rig(parts, groups)
    rig.reset()
    FLOOR[0] = mrg.lowest_z(rig)
    return rig


def fin(r, P):
    r.apply(P)
    if hasattr(r, 'vox'):
        mrg.ground_clamp(r, FLOOR[0])


def wave(t, lag=0.0, k=1):
    """A travelling wave that is exactly 0 at t=0 and t=1 (so every clip meets the rest pose): sin envelope x sine."""
    return math.sin(math.pi * t) ** 1.5 * math.sin(2 * math.pi * (k * t - lag))


def base(P, t, k=2):
    """Real breathing: the body swells, shoulders and wings follow, head and tail lag. Same at t=0 and t=1."""
    b, b1, b2, b3 = (breath(t, k, lag) for lag in (0.0, 0.08, 0.18, 0.30))
    P.grow('body', .030 * b, .022 * b, .030 * b)
    P.add('torso', rot=(0, -.8 * b, 0))
    P.add('head', d=(0, 0, .008 * b1), rot=(0, -.9 * b1, 0))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * 1.6 * b3, 0, 0))
    P.add('tail', rot=(0, .9 * b2, 0))
    P.add('tailtip', rot=(0, 1.2 * b3, 0))


def eyes(P, closed):
    s = max(.08, 1 - .92 * closed)
    P.set_scale('eye_p', (1, 1, s))
    P.set_scale('eye_n', (1, 1, s))


def wings(P, flap=0.0, sweep=0.0, twist=0.0):
    """flap: + raises the outer edge (deg); sweep: + sweeps back; twist: pitches the leading edge."""
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * flap, twist, sg * sweep))


# ══════════ Stufe 1 (s0): hovering leaf-manta ══════════
def idle_s0(r, t):
    """Playful leaf-manta: drifts, then a gust makes it flutter fast (3 beats) and roll, it looks around curious, tail curls, double blink."""
    P = Pose()
    base(P, t, 2)
    up = math.sin(math.pi * t) ** 2
    gust = pulse(t, .22, .32, .52, .62)                  # the fast flutter
    beat = gust * math.sin(2 * math.pi * 3 * (t - .22))
    roll = pulse(t, .26, .36, .50, .60)
    look = gb.curve(t, [(0, 0), (.62, 0), (.70, 1), (.78, 1), (.86, -1), (.93, -1), (1, 0)])
    P.add('root', d=(.03 * wave(t, .0, 1), .04 * wave(t, .25, 1), .05 * up + .05 * gust), rot=(5 * wave(t, .1, 1) + 10 * roll * math.sin(2 * math.pi * 1.5 * (t - .26)), 3 * wave(t, .35, 1) + 8 * look, 5 * wave(t, .2, 1)))
    for s, sg in SG.items():
        P.add('wing_' + s, rot=(sg * (15 * wave(t, 0.0, 2) + 7 * up + 30 * beat + 8 * gust), 5 * wave(t, .15, 2), sg * (5 * wave(t, .3, 1) + 5 * gust)))
    P.add('head', rot=(0, 4 * wave(t, .3, 1) + 4 * abs(look), 7 * wave(t, .5, 1) + 28 * look))
    P.add('tail', rot=(0, 6 * wave(t, .3, 1), 16 * wave(t, .35, 1) + 14 * look))
    P.add('tailtip', rot=(0, 10 * wave(t, .5, 1), 24 * wave(t, .55, 1) - 12 * look))
    eyes(P, blink(t, .12) + blink(t, .18) + blink(t, .86))
    fin(r, P)

def attack_s0(r, t):
    """Pull back and up (wings rise), ram forward head first (wings sweep back), tail whips, glide back."""
    P = Pose()
    base(P, t, 1)
    wind = gb.curve(t, [(0, 0), (.30, 1), (.38, 1), (.46, 0), (1, 0)])
    strike = pulse(t, .36, .46, .58, .80)
    P.add('root', d=(-.07 * wind + .17 * strike, 0, .05 * wind + .02 * strike), rot=(0, -9 * wind + 12 * strike, 0))
    P.add('torso', rot=(0, -5 * wind + 6 * strike, 0))
    P.add('head', d=(.03 * strike, 0, 0), rot=(0, -10 * wind + 22 * strike, 0))
    wings(P, flap=26 * wind - 18 * strike, sweep=-8 * wind + 26 * strike, twist=0)
    P.add('tail', rot=(0, 6 * wind - 8 * strike, 22 * math.sin(2 * math.pi * ramp(t, .40, .85)) * pulse(t, .38, .5, .7, .9)))
    P.add('tailtip', rot=(0, 0, 34 * math.sin(2 * math.pi * (ramp(t, .40, .85) - .2)) * pulse(t, .38, .5, .7, .9)))
    eyes(P, .35 * strike)
    fin(r, P)


def hurt_s0(r, t):
    P = Pose()
    base(P, t, 1)
    hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    P.grow('body', .06 * hit, .06 * hit, .05 * hit)
    P.add('root', d=(-.09 * hit, .01 * wob, .03 * hit), rot=(4 * wob, -10 * hit, 5 * wob))
    P.add('head', rot=(0, -14 * hit, 8 * wob))
    wings(P, flap=38 * hit + 4 * math.cos(t * 10) * hit, sweep=8 * hit)           # the wings snap up and fold
    P.add('tail', rot=(0, 10 * hit, 18 * hit * math.cos(t * 6)))
    P.add('tailtip', rot=(0, 0, 26 * hit * math.cos(t * 6 - .8)))
    eyes(P, .9 * hit)
    fin(r, P)
    r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))


def walk_s0(r, t):
    """Glides: a slow wing stroke with the tip lagging, body trims into the motion, tail swings against it."""
    P = Pose()
    base(P, t, 1)
    s = 2 * math.pi * t
    P.add('root', d=(0, 0, .035 + .012 * math.sin(2 * s)), rot=(2.5 * math.sin(s), 1.2 * math.cos(2 * s) - 2.5, 0))
    for nm, sg in SG.items():
        P.add('wing_' + nm, rot=(sg * (16 * math.sin(s) + 6), 4 * math.sin(s - .9), sg * (-4 + 3 * math.sin(s - .5))))
    P.add('head', rot=(0, -3 * math.cos(2 * s), -4 * math.sin(s)))
    P.add('tail', rot=(0, 3 * math.cos(2 * s), 13 * math.sin(s + .6)))
    P.add('tailtip', rot=(0, 5 * math.sin(2 * s - .4), 20 * math.sin(s + .2)))
    fin(r, P)


# ══════════ Stufe 2 (s1): baby dragon ══════════
def idle_s1(r, t):
    """Excited baby: quick flutter hop, looks left and right, a happy tail wiggle with a little bounce, then a big wing stretch."""
    P = Pose()
    base(P, t, 2)
    fl = pulse(t, .05, .12, .30, .38)
    beat = fl * math.sin(2 * math.pi * 4 * (t - .05)) * 0.5 + fl * .5
    hop = pulse(t, .07, .17, .28, .38)
    look = gb.curve(t, [(0, 0), (.40, 0), (.47, 1), (.54, 1), (.60, -1), (.66, -1), (.71, 0), (1, 0)])
    wig = pulse(t, .44, .50, .76, .82) * math.sin(2 * math.pi * 3.5 * (t - .44))   # tail wiggle
    bob = pulse(t, .44, .50, .76, .82) * math.sin(2 * math.pi * 3.5 * (t - .44) + 1.2)
    stretch = pulse(t, .80, .86, .90, .96)                # wings spread wide at the end
    P.add('root', d=(0, 0, .11 * hop + .012 * fl + .02 * abs(bob)), rot=(0, -5 * hop - 3 * stretch, 3 * bob))
    P.grow('body', .02 * stretch, .0, -.03 * pulse(t, .36, .40, .42, .46) + .02 * stretch)
    wings(P, flap=-6 * fl + 48 * beat * fl + 6 * hop + 26 * stretch + 10 * abs(bob), sweep=-6 * stretch)
    P.add('head', rot=(0, -3 * hop + 2 * abs(look) - 6 * stretch, 30 * look + 5 * wig))
    P.add('torso', rot=(0, 2 * stretch, 5 * look))
    P.add('tail', rot=(0, 5 * hop, 10 * math.sin(2 * math.pi * 4 * t) * fl + 7 * look + 24 * wig))
    P.add('tailtip', rot=(0, 0, 18 * math.sin(2 * math.pi * 4 * (t - .06)) * fl - 8 * look + 36 * math.sin(2 * math.pi * 3.5 * (t - .44) - .6) * pulse(t, .44, .50, .76, .82)))
    eyes(P, blink(t, .05) + blink(t, .66) + blink(t, .86))
    fin(r, P)

def attack_s1(r, t):
    """Flutters up (wings rise), horn thrust forward with one strong beat, lands."""
    P = Pose()
    base(P, t, 1)
    wind = gb.curve(t, [(0, 0), (.28, 1), (.34, 1), (.40, 0), (1, 0)])
    strike = pulse(t, .32, .42, .56, .80)
    P.add('root', d=(-.05 * wind + .18 * strike, 0, .07 * wind + .04 * strike), rot=(0, -8 * wind + 14 * strike, 0))
    P.add('head', d=(.03 * strike, 0, 0), rot=(0, -12 * wind + 26 * strike, 0))
    wings(P, flap=40 * wind - 30 * strike, sweep=-6 * wind + 14 * strike)
    P.add('tail', rot=(0, 8 * wind - 10 * strike, 16 * math.sin(2 * math.pi * ramp(t, .40, .9)) * pulse(t, .4, .5, .75, .95)))
    P.add('tailtip', rot=(0, 0, 26 * math.sin(2 * math.pi * (ramp(t, .40, .9) - .2)) * pulse(t, .4, .5, .75, .95)))
    P.grow('body', 0, 0, -.04 * pulse(t, .78, .82, .84, .90))
    eyes(P, .35 * strike)
    fin(r, P)


def hurt_s1(r, t):
    P = Pose()
    base(P, t, 1)
    hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    P.grow('body', .07 * hit, .07 * hit, .05 * hit)
    P.add('root', d=(-.10 * hit, .01 * wob, .05 * hit), rot=(4 * wob, -10 * hit, 5 * wob))
    P.add('head', rot=(0, -14 * hit, 9 * wob))
    wings(P, flap=30 * hit + 18 * math.sin(t * 22) * hit * (1 - t), sweep=6 * hit)  # one wild flap to keep balance
    P.add('tail', rot=(0, 12 * hit, 18 * hit * math.cos(t * 6)))
    P.add('tailtip', rot=(0, 0, 28 * hit * math.cos(t * 6 - .8)))
    eyes(P, .9 * hit)
    fin(r, P)
    r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))


def walk_s1(r, t):
    """Hop and flutter in turns: two hops per cycle, quick beats on the way up, a springy landing."""
    P = Pose()
    base(P, t, 1)
    s = 2 * math.pi * t
    hop = abs(math.sin(s))                              # 0 on landing, 1 at the top of the hop
    land = (1 - hop) ** 6                               # 1 on landing, 0 in the air
    P.add('root', d=(0, 0, .07 * hop), rot=(0, -3 * math.sin(2 * s) - 2, 3 * math.sin(s)))
    P.grow('body', .02 * land, .02 * land, -.05 * land)
    wings(P, flap=8 + 34 * math.sin(2 * s) ** 2 - 10 * land, sweep=3 * math.sin(2 * s - .5))
    P.add('head', rot=(0, 3 * land - 2 * hop, -5 * math.sin(s)))
    P.add('tail', rot=(0, 5 * hop, 9 * math.sin(s + .6)))
    P.add('tailtip', rot=(0, 6 * math.sin(2 * s - .5), 16 * math.sin(s + .3)))
    fin(r, P)


# ══════════ Stufe 3 (s2): upright dragon ══════════
def idle_s2(r, t):
    """Rears up, spreads the wings with a strong beat, looks around proudly, a second smaller beat, tail lashes. Feet stay put."""
    P = Pose()
    base(P, t, 2)
    up = pulse(t, .10, .26, .74, .90)
    beat = math.sin(math.pi * ramp(t, .30, .48))
    beat2 = math.sin(math.pi * ramp(t, .62, .76)) * .6
    look = gb.curve(t, [(0, 0), (.48, 0), (.55, 1), (.62, 1), (.70, -1), (.78, -1), (.86, 0), (1, 0)])
    lash = pulse(t, .20, .30, .70, .80) * math.sin(2 * math.pi * 2 * (t - .20))
    P.add('torso', rot=(0, -17 * up - 4 * beat, 5 * look))
    P.add('head', rot=(0, 9 * up - 7 * beat + 3 * abs(look), 22 * look))
    for s in SG:
        P.add('leg_' + s, rot=(0, 13 * up, 0))
    wings(P, flap=16 * up - 34 * beat - 20 * beat2 + 8 * (beat ** 2 + beat2 ** 2), sweep=10 * up + 4 * beat)
    P.add('tail', rot=(0, 10 * up, 26 * lash + 6 * look))
    P.add('tailtip', rot=(0, 3 * up, 36 * math.sin(2 * math.pi * 2 * (t - .20) - .7) * pulse(t, .20, .30, .70, .80)))
    eyes(P, blink(t, .05) + blink(t, .86) + .3 * up * (1 - up))
    fin(r, P)

def attack_s2(r, t):
    """Crouch and draw the wings up, leap forward and slam both wings forward, tail swings through, recover."""
    P = Pose()
    base(P, t, 1)
    crouch = gb.curve(t, [(0, 0), (.26, 1), (.32, 1), (.38, 0), (1, 0)])
    leap = pulse(t, .30, .42, .56, .82)
    slam = pulse(t, .36, .46, .58, .78)
    P.add('root', d=(-.05 * crouch + .22 * leap, 0, .09 * math.sin(math.pi * ramp(t, .34, .62)) ), rot=(0, 5 * crouch + 3 * leap, 0))
    P.add('torso', rot=(0, 9 * crouch - 12 * leap + 8 * slam, 0))
    P.add('head', d=(.02 * slam, 0, 0), rot=(0, -8 * crouch + 22 * slam, 0))
    wings(P, flap=22 * crouch - 26 * slam, sweep=-14 * crouch - 18 * slam)
    for s, sg in SG.items():
        P.add('leg_' + s, rot=(0, -10 * crouch + (-12 if s == 'p' else 8) * leap, 0))
    P.add('tail', rot=(0, 8 * crouch - 10 * slam, 20 * math.sin(2 * math.pi * ramp(t, .38, .9)) * pulse(t, .36, .48, .75, .95)))
    P.add('tailtip', rot=(0, 0, 30 * math.sin(2 * math.pi * (ramp(t, .38, .9) - .2)) * pulse(t, .36, .48, .75, .95)))
    eyes(P, .4 * slam)
    fin(r, P)


def hurt_s2(r, t):
    P = Pose()
    base(P, t, 1)
    hit = gb.curve(t, [(0, 0), (.15, 1), (.40, .5), (.70, .12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    P.grow('body', .06 * hit, .06 * hit, .04 * hit)
    P.add('root', d=(-.10 * hit, .01 * wob, 0), rot=(3 * wob, -6 * hit, 4 * wob))
    P.add('torso', rot=(0, -9 * hit, 0))
    P.add('head', rot=(0, -16 * hit, 9 * wob))
    wings(P, flap=22 * hit + 4 * math.cos(t * 9) * hit, sweep=10 * hit)             # the wings fling open
    for s, sg in SG.items():
        P.add('leg_' + s, rot=(0, (8 if s == 'p' else -6) * hit, 0))
    P.add('tail', rot=(0, 12 * hit, 20 * hit * math.cos(t * 6)))
    P.add('tailtip', rot=(0, 0, 28 * hit * math.cos(t * 6 - .8)))
    eyes(P, .9 * hit)
    fin(r, P)
    r.flash(.9 if t < .12 else (.45 if t < .28 else 0.0))


def walk_s2(r, t):
    """Biped gait: legs alternate and plant, body bobs and rolls, head counter-moves, wings half folded and rippling, tail swings."""
    P = Pose()
    base(P, t, 1)
    s = 2 * math.pi * t
    for nm, sg in SG.items():
        a = s + (0 if sg > 0 else math.pi)
        lf = max(0.0, math.cos(a))
        P.add('leg_' + nm, d=(0, 0, .05 * lf), rot=(0, -26 * math.sin(a), 0))
    wings(P, flap=-6 + 2.5 * math.sin(2 * s), sweep=4 + 2 * math.sin(2 * s - .6))
    P.add('root', d=(0, 0, .016 * (1 - math.cos(2 * s)) / 2), rot=(2.5 * math.sin(s), 1 + 1.4 * math.cos(2 * s), 3 * math.sin(s)))
    P.add('torso', d=(.008 * math.sin(s - 1.4), 0, 0), rot=(0, -1.2 * math.cos(2 * s), 0))
    P.add('head', d=(.02 * math.sin(s - 1.0), 0, 0), rot=(0, -3 * math.cos(2 * s), -5 * math.sin(s)))
    P.add('tail', rot=(0, 3 * math.cos(2 * s), 12 * math.sin(s + .6)))
    P.add('tailtip', rot=(0, 4 * math.sin(2 * s - .4), 18 * math.sin(s + .2)))
    fin(r, P)


IDLE = (idle_s0, idle_s1, idle_s2)
ATTACK = (attack_s0, attack_s1, attack_s2)
HURT = (hurt_s0, hurt_s1, hurt_s2)
WALK = (walk_s0, walk_s1, walk_s2)


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
    idle, walk = IDLE[st], WALK[st]

    def walk_in(r, t):
        fin(r, _cap(idle, 0.0).blend(_cap(walk, 0.0), gb.smooth(t)))

    def walk_out(r, t):
        fin(r, _cap(walk, 1.0).blend(_cap(idle, 0.0), gb.smooth(t)))
    return {'idle': (CFG[st]['idle_frames'], 12, True, idle), 'attack': (20, 16, False, ATTACK[st]),
            'hurt': (10, 14, False, HURT[st]), 'walk': (8, 10, True, walk),
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
    ap.add_argument('--out', default='docs/renders/monsters/leafwing_anim/tmp')
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
        check_seams(table, WALK[st])
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
        for k, spec in enumerate(a.pose.split(",")):          # several poses: one rig, files <still>_<n>.png
            name, tt = spec.split(":")
            rig.reset()
            table[name][3](rig, float(tt))
            bpy.context.view_layer.update()
            gb.render_frame(os.path.abspath(a.still.replace(".png", "_%d.png" % k)))
        return
    gb.battle_camera.__defaults__ = (cfg.get('pad', 0.36),)           # extra room: strikes and wing beats must never touch the cell edge
    mrg.bake(lambda: build(st), table, a.out, a.views, a.samples, a.scale, cfg['map_k'], 'leafwing', st, cfg['shadow'], only,
             map_anims=('walk', 'walk_in', 'walk_out', 'idle'), headings=a.headings.split(','))


if __name__ == '__main__':
    main()
