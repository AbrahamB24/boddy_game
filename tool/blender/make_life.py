"""The map's LIFE (user 2026-11-05: "Tiere, welche sich auf der Karte bewegen
und zusätzlich einige Ruinen, gestrandetes Boot etc."): animals and
landmarks, built and shipped in exactly the pipeline of the buildings and the
scenery (make_prop.render_one — same voxeliser, sun, render scale, density).

    blender --background --python tool/blender/make_life.py -- <name,..|all> \
        [--samples 96] [--out DIR]

Writes assets/images/terrain/life_<name>.webp, each cropped and centred on its
FOOT (the origin), like the props.

Animals face +x in the model. An animal is rendered in the two directions an
isometric picture needs — `_se` (walking down-right on screen) and `_ne`
(walking up-right); the app mirrors them for the left-hand directions. Models
are built a little larger than life: a real sheep would be four voxels long.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import camp_kit as C  # noqa: E402
import fw_kit as F  # noqa: E402
import make_prop as P  # noqa: E402
from pro_kit import G, beam, cyl, ellipsoid, plain, rbox  # noqa: E402

YAW = {'se': 0.0, 'ne': math.pi / 2}
K_ANIMAL = 1.7                 # animals are drawn larger than life


def materials():
    M = P.materials()
    pl = plain
    M['wool'] = pl('wool', '#efe8da', rough=0.95, bump=0.7, bump_scale=140, vary=0.1)
    M['face'] = pl('face', '#3b342f', rough=0.8, bump=0.1)
    M['hoof'] = pl('hoof', '#2c2623', rough=0.8, bump=0.1)
    M['deer'] = pl('deer', '#98683b', rough=0.9, bump=0.4, bump_scale=120, vary=0.08)
    M['deer_l'] = pl('deer_l', '#d9c09a', rough=0.9, bump=0.3, bump_scale=120)
    M['rabbit'] = pl('rabbit', '#a79684', rough=0.95, bump=0.5, bump_scale=140, vary=0.08)
    M['white'] = pl('white', '#f6f2ea', rough=0.9, bump=0.3, bump_scale=120)
    M['gull_g'] = pl('gull_g', '#8d98a3', rough=0.85, bump=0.2)
    M['beak'] = pl('beak', '#eaa92a', rough=0.5, bump=0.05)
    M['crab'] = pl('crab', '#cf4f33', rough=0.55, bump=0.25, bump_scale=90)
    M['duck'] = pl('duck', '#8a6a4a', rough=0.9, bump=0.4, bump_scale=120, vary=0.08)
    M['duck_h'] = pl('duck_h', '#1f6b45', rough=0.7, bump=0.2)
    M['bfly_o'] = pl('bfly_o', '#f0872a', rough=0.7, bump=0.05)
    M['bfly_k'] = pl('bfly_k', '#2a211c', rough=0.7, bump=0.05)
    M['sand_mound'] = pl('sand_mound', '#d8c59c', rough=0.95, bump=0.5,
                         bump_scale=160, vary=0.08)
    M['moss'] = pl('moss', '#5f8a3a', rough=0.95, bump=0.7, bump_scale=120, vary=0.14)
    M['wreck'] = pl('wreck', '#7d6a55', rough=0.9, bump=0.5, bump_scale=70,
                    vary=0.14, speck='#5e4e3e')
    M['sail'] = pl('sail', '#a8987a', rough=0.95, bump=0.3, bump_scale=60, vary=0.1)
    return M


def eye(M, x, y, z, r=0.007):
    ellipsoid(x, y, z, r, r, r, M['hoof'], seg=6, rings=4)


def leg(M, x, y, h, r, mat, foot='hoof'):
    cyl(x, y, G, r, r * 0.8, h, M[mat], seg=6, smooth=False)
    if foot:
        cyl(x, y, G, r * 1.05, r * 1.05, h * 0.18, M[foot], seg=6, smooth=False)


# ── animals (forward = +x) ──────────────────────────────────
def sheep(M, graze=False):
    z = G + 0.075
    ellipsoid(0, 0, z + 0.03, 0.125, 0.085, 0.078, M['wool'], seg=12, rings=9)
    ellipsoid(0.05, 0.0, z + 0.05, 0.08, 0.075, 0.06, M['wool'], seg=10, rings=8)
    ellipsoid(-0.06, 0.02, z + 0.04, 0.07, 0.07, 0.06, M['wool'], seg=10, rings=8)
    ellipsoid(-0.12, 0, z + 0.03, 0.04, 0.04, 0.04, M['wool'], seg=8, rings=6)
    hz = G + (0.06 if graze else 0.125)
    hx = 0.17 if not graze else 0.19
    ellipsoid(hx, 0, hz, 0.05, 0.034, 0.04, M['face'], seg=10, rings=8)
    ellipsoid(hx - 0.035, 0, hz + 0.028, 0.035, 0.035, 0.03, M['wool'], seg=8, rings=6)
    for s in (-1, 1):
        ellipsoid(hx - 0.02, s * 0.04, hz + 0.005, 0.022, 0.01, 0.012, M['face'],
                  seg=6, rings=4, tilt=Euler((0.4 * s, 0, 0), 'XYZ'))
        eye(M, hx + 0.025, s * 0.026, hz + 0.01, 0.006)
    for x, y in ((0.075, 0.045), (0.075, -0.045), (-0.07, 0.045), (-0.07, -0.045)):
        leg(M, x, y, 0.075, 0.014, 'face', foot=None)


def deer(M, graze=False, stag=True):
    ellipsoid(0, 0, G + 0.2, 0.17, 0.07, 0.07, M['deer'], seg=14, rings=10)
    ellipsoid(0.02, 0, G + 0.17, 0.13, 0.06, 0.05, M['deer_l'], seg=10, rings=8)
    ellipsoid(-0.17, 0, G + 0.225, 0.03, 0.04, 0.035, M['white'], seg=8, rings=6)
    if graze:
        neck_to = Vector((0.27, 0, G + 0.1))
        head = (0.32, 0, G + 0.065)
    else:
        neck_to = Vector((0.23, 0, G + 0.34))
        head = (0.275, 0, G + 0.355)
    C.log(M, Vector((0.14, 0, G + 0.22)), neck_to, 0.034, 'deer', ends=False, seg=8)
    ellipsoid(*head, 0.055, 0.03, 0.03, M['deer'], seg=10, rings=8)
    ellipsoid(head[0] + 0.045, 0, head[2] - 0.006, 0.025, 0.02, 0.018, M['deer_l'],
              seg=8, rings=6)
    ellipsoid(head[0] + 0.07, 0, head[2] - 0.003, 0.008, 0.009, 0.008, M['face'],
              seg=6, rings=4)
    for s in (-1, 1):
        eye(M, head[0] + 0.02, s * 0.026, head[2] + 0.008, 0.007)
        ellipsoid(head[0] - 0.03, s * 0.03, head[2] + 0.03, 0.012, 0.028, 0.012,
                  M['deer'], seg=6, rings=4, tilt=Euler((0.7 * s, 0, 0), 'XYZ'))
        if stag:
            base = Vector((head[0] - 0.025, s * 0.02, head[2] + 0.025))
            tip = base + Vector((-0.03, s * 0.04, 0.09))
            C.log(M, base, tip, 0.007, 'antler', ends=False, seg=5)
            C.log(M, base.lerp(tip, 0.55), base.lerp(tip, 0.55) +
                  Vector((0.05, s * 0.01, 0.05)), 0.005, 'antler', ends=False, seg=5)
    for x, y, f in ((0.12, 0.04, 1), (0.12, -0.04, 1), (-0.12, 0.04, 1), (-0.12, -0.04, 1)):
        C.log(M, Vector((x, y, G + 0.17)), Vector((x + 0.01, y, G + 0.012)),
              0.014, 'deer', ends=False, seg=6)
        cyl(x + 0.01, y, G, 0.012, 0.012, 0.025, M['hoof'], seg=6, smooth=False)


def rabbit(M, sit=True):
    ellipsoid(0, 0, G + 0.045, 0.06, 0.04, 0.045, M['rabbit'], seg=10, rings=8)
    ellipsoid(0.065, 0, G + 0.085, 0.03, 0.024, 0.027, M['rabbit'], seg=8, rings=6)
    ellipsoid(0.09, 0, G + 0.08, 0.014, 0.014, 0.012, M['deer_l'], seg=6, rings=4)
    ellipsoid(-0.062, 0, G + 0.05, 0.02, 0.02, 0.02, M['white'], seg=8, rings=6)
    for s in (-1, 1):
        C.log(M, Vector((0.055, s * 0.012, G + 0.105)),
              Vector((0.035, s * 0.016, G + 0.19)), 0.009, 'rabbit', ends=False, seg=5)
        eye(M, 0.082, s * 0.017, G + 0.093, 0.006)
        ellipsoid(-0.025, s * 0.032, G + 0.03, 0.035, 0.012, 0.028, M['rabbit'],
                  seg=8, rings=6)


def gull_stand(M):
    ellipsoid(0, 0, G + 0.075, 0.065, 0.034, 0.034, M['white'], seg=10, rings=8)
    ellipsoid(0.055, 0, G + 0.115, 0.024, 0.022, 0.024, M['white'], seg=8, rings=6)
    C.log(M, Vector((0.075, 0, G + 0.115)), Vector((0.11, 0, G + 0.105)), 0.008,
          'beak', ends=False, seg=5)
    ellipsoid(-0.01, 0, G + 0.085, 0.055, 0.037, 0.022, M['gull_g'], seg=8, rings=6)
    ellipsoid(-0.075, 0, G + 0.07, 0.025, 0.016, 0.008, M['gull_g'], seg=6, rings=4)
    for s in (-1, 1):
        eye(M, 0.068, s * 0.018, G + 0.12, 0.005)
        C.log(M, Vector((0.005, s * 0.012, G + 0.05)), Vector((0.005, s * 0.012, G)),
              0.005, 'beak', ends=False, seg=4)


def gull_fly(M, ang):
    h = G + 0.1
    ellipsoid(0, 0, h, 0.07, 0.03, 0.028, M['white'], seg=10, rings=8)
    ellipsoid(0.065, 0, h + 0.012, 0.024, 0.02, 0.022, M['white'], seg=8, rings=6)
    C.log(M, Vector((0.085, 0, h + 0.012)), Vector((0.12, 0, h + 0.004)), 0.008,
          'beak', ends=False, seg=5)
    ellipsoid(-0.075, 0, h, 0.03, 0.02, 0.008, M['gull_g'], seg=6, rings=4)
    L = 0.1
    for s in (-1, 1):
        a = ang * s
        ellipsoid(0.0, s * L * math.cos(ang), h + 0.012 + L * math.sin(ang),
                  0.05, L, 0.007, M['white'], seg=10, rings=6,
                  tilt=Euler((a, 0, 0), 'XYZ'))
        ellipsoid(-0.01, s * (L * 1.7) * math.cos(ang),
                  h + 0.012 + (L * 1.7) * math.sin(ang), 0.035, L * 0.55, 0.006,
                  M['gull_g'], seg=8, rings=5, tilt=Euler((a, 0, 0), 'XYZ'))


def crab(M):
    ellipsoid(0, 0, G + 0.022, 0.038, 0.03, 0.016, M['crab'], seg=10, rings=7)
    for s in (-1, 1):
        C.log(M, Vector((0.025, s * 0.025, G + 0.025)),
              Vector((0.055, s * 0.05, G + 0.035)), 0.006, 'crab', ends=False, seg=5)
        ellipsoid(0.065, s * 0.055, G + 0.037, 0.02, 0.016, 0.012, M['crab'],
                  seg=8, rings=6)
        C.log(M, Vector((0.03, s * 0.012, G + 0.035)),
              Vector((0.036, s * 0.014, G + 0.055)), 0.004, 'crab', ends=False, seg=4)
        eye(M, 0.036, s * 0.014, G + 0.058, 0.005)
        for k in range(3):
            x = -0.015 + k * 0.016
            C.log(M, Vector((x, s * 0.026, G + 0.02)),
                  Vector((x - 0.01, s * 0.06, G + 0.005)), 0.004, 'crab',
                  ends=False, seg=4)


def duck(M):
    ellipsoid(0, 0, G + 0.03, 0.06, 0.036, 0.032, M['duck'], seg=10, rings=8)
    ellipsoid(0.02, 0, G + 0.035, 0.04, 0.034, 0.025, M['deer_l'], seg=8, rings=6)
    ellipsoid(-0.065, 0, G + 0.045, 0.025, 0.02, 0.014, M['duck'], seg=6, rings=4,
              tilt=Euler((0, -0.4, 0), 'XYZ'))
    ellipsoid(0.055, 0, G + 0.075, 0.024, 0.022, 0.024, M['duck_h'], seg=8, rings=6)
    ellipsoid(0.08, 0, G + 0.07, 0.016, 0.014, 0.007, M['beak'], seg=6, rings=4)
    for s in (-1, 1):
        eye(M, 0.066, s * 0.017, G + 0.082, 0.005)


def butterfly(M, ang):
    h = G + 0.1
    ellipsoid(0, 0, h, 0.03, 0.007, 0.007, M['bfly_k'], seg=6, rings=4)
    for s in (-1, 1):
        a = ang * s
        L = 0.045
        ellipsoid(0.012, s * L * math.cos(ang), h + L * math.sin(ang), 0.034, L,
                  0.004, M['bfly_o'], seg=8, rings=5, tilt=Euler((a, 0, 0), 'XYZ'))
        ellipsoid(-0.018, s * 0.03 * math.cos(ang), h + 0.03 * math.sin(ang), 0.022,
                  0.03, 0.004, M['bfly_k'], seg=6, rings=4,
                  tilt=Euler((a, 0, 0), 'XYZ'))


# ── landmarks ───────────────────────────────────────────────
def _blk(M, x, y, z, rot=0.0, s=(0.16, 0.14, 0.09), mat='stone'):
    rbox((x, y, z + s[2] / 2), s, (0, 0, rot), M[mat], bevel=0.008)


def _moss(M, x, y, z, r, seed):
    rnd = random.Random(seed)
    for _ in range(3):
        ellipsoid(x + rnd.uniform(-r, r) * .5, y + rnd.uniform(-r, r) * .4, z,
                  r * rnd.uniform(.6, 1), r * rnd.uniform(.5, .8), r * 0.3,
                  M['moss'], seg=8, rings=5)


def _rubble(M, cx, cy, n, spread, seed, mat='stone'):
    rnd = random.Random(seed)
    for _ in range(n):
        s = rnd.uniform(.6, 1.1)
        _blk(M, cx + rnd.uniform(-spread, spread), cy + rnd.uniform(-spread, spread),
             G + 0.0, rnd.uniform(0, 3.1), (0.16 * s, 0.14 * s, 0.09 * s), mat)


def ruin_wall(M):
    rnd = random.Random(11)
    hs = [6, 6, 5, 6, 3, 4, 2, 1, 3]
    for i, h in enumerate(hs):
        for c in range(h):
            x = -0.64 + i * 0.16 + (0.08 if c % 2 else 0)
            _blk(M, x, 0, G + c * 0.09, rnd.uniform(-.03, .03))
    for i, h in enumerate([5, 4, 2, 3]):                 # the return wall
        for c in range(h):
            _blk(M, -0.64 + (0.08 if c % 2 else 0), 0.17 + i * 0.16 * 0.9, G + c * 0.09,
                 math.pi / 2 + rnd.uniform(-.03, .03))
    # a window gap with a lintel stump
    _blk(M, -0.32, 0, G + 6 * 0.09, 0, (0.3, 0.14, 0.07), 'stone_dk')
    _moss(M, -0.62, 0, G + 0.56, 0.1, 1)
    _moss(M, 0.0, 0, G + 0.5, 0.09, 2)
    _rubble(M, 0.3, 0.2, 6, 0.28, 3)
    _rubble(M, -0.45, -0.22, 4, 0.2, 4)


def ruin_tower(M):
    rnd = random.Random(21)
    n, R = 15, 0.36
    for i in range(n):
        a = i / n * math.tau
        top = 3 + int(5 * max(0, math.cos(a - 2.2))) + rnd.randint(0, 1)
        for c in range(top):
            if i in (0, 1) and c < 3:
                continue                                     # the doorway
            aa = a + (0.12 if c % 2 else 0)
            _blk(M, math.cos(aa) * R, math.sin(aa) * R, G + c * 0.09, aa + math.pi / 2,
                 (0.17, 0.13, 0.09), 'stone' if c % 3 else 'stone_dk')
    _blk(M, R, 0.0, G + 3 * 0.09, math.pi / 2, (0.3, 0.14, 0.06), 'stone_dk')
    _rubble(M, 0, 0, 6, 0.2, 5)
    _rubble(M, 0.5, -0.3, 5, 0.18, 6)
    for k in range(4):
        _moss(M, math.cos(2.2 + k * .35) * R, math.sin(2.2 + k * .35) * R, G + 0.58, 0.08, k)


def ruin_arch(M):
    rnd = random.Random(31)
    for side, h in ((-1, 8), (1, 6)):
        for c in range(h):
            for k in (-1, 1):
                _blk(M, side * 0.34 + k * 0.08 * (1 if c % 2 else 0.8), 0, G + c * 0.09,
                     rnd.uniform(-.03, .03), (0.14, 0.15, 0.09))
    z0, R = G + 8 * 0.09, 0.34
    th = [math.pi - i * math.pi / 9 for i in range(10)]
    for i, t in enumerate(th):
        if i in (5, 6, 7):                                   # the missing keystones
            continue
        c = (R * math.cos(t), 0, z0 + R * 0.55 * math.sin(t))
        rbox(c, (0.11, 0.15, 0.12), (0, -t, 0), M['stone'], bevel=0.008)
    _blk(M, 0.15, 0.2, G, 0.5, (0.14, 0.12, 0.12), 'stone')
    _blk(M, 0.05, -0.18, G, 1.1, (0.12, 0.12, 0.1), 'stone')
    _rubble(M, 0.0, 0.0, 5, 0.3, 7)
    _moss(M, -0.34, 0, G + 0.74, 0.08, 3)


def ruin_columns(M):
    rnd = random.Random(41)
    for (x, y, n, cap) in ((-0.3, 0.1, 6, True), (0.1, -0.15, 4, False),
                           (0.45, 0.2, 2, False)):
        rbox((x, y, G + 0.025), (0.22, 0.22, 0.05), (0, 0, rnd.uniform(-.1, .1)),
             M['stone_dk'], bevel=0.008)
        for k in range(n):
            cyl(x + rnd.uniform(-.004, .004), y, G + 0.05 + k * 0.1, 0.062, 0.058,
                0.1, M['stone'], seg=14)
        if cap:
            rbox((x, y, G + 0.05 + n * 0.1 + 0.025), (0.2, 0.2, 0.05), (0, 0, 0.2),
                 M['stone_dk'], bevel=0.008)
    for k in range(4):                                       # one lies where it fell
        C.log(M, Vector((-0.4 + k * 0.1, -0.3 + k * 0.012, G + 0.058)),
              Vector((-0.31 + k * 0.1, -0.3 + k * 0.012, G + 0.058)), 0.058,
              'stone', ends=False, seg=14)
    _rubble(M, 0.2, 0.0, 4, 0.4, 8)
    _moss(M, -0.3, 0.1, G + 0.7, 0.07, 5)


def menhirs(M):
    rnd = random.Random(51)
    for i in range(7):
        a = i / 7 * math.tau + rnd.uniform(-.1, .1)
        h = rnd.uniform(0.28, 0.5)
        w = rnd.uniform(0.12, 0.17)
        ob = rbox((math.cos(a) * 0.42, math.sin(a) * 0.36, G + h / 2 - 0.02),
                  (w, w * 0.7, h), (rnd.uniform(-.1, .1), rnd.uniform(-.1, .1), a),
                  M['rock'], bevel=0.02)
        _moss(M, math.cos(a) * 0.42, math.sin(a) * 0.36, G + 0.02, 0.06, i)
    for s in (-1, 1):
        rbox((0.0, s * 0.1, G + 0.22), (0.12, 0.1, 0.46), (0, 0, 0), M['rock'], bevel=0.02)
    rbox((0.0, 0.0, G + 0.5), (0.14, 0.34, 0.1), (0, 0, 0), M['rock'], bevel=0.02)


def wagon(M):
    rnd = random.Random(61)
    bed = rbox((0, 0, G + 0.17), (0.5, 0.26, 0.04), (0, 0.16, 0), M['planks'], bevel=0.006)
    for s in (-1, 1):                                        # low sides, one broken
        rbox((0, s * 0.125, G + 0.21), (0.5 if s > 0 else 0.26, 0.025, 0.07),
             (0, 0.16, 0), M['planks'], bevel=0.005)
    rbox((0.26, 0, G + 0.2), (0.025, 0.26, 0.08), (0, 0.16, 0), M['planks'], bevel=0.005)
    # front axle with both wheels, rear axle with one
    C.log(M, Vector((0.18, -0.17, G + 0.1)), Vector((0.18, 0.17, G + 0.1)), 0.015,
          'timber', ends=False, seg=8)
    C.wheel(M, (0.18, 0.17, G + 0.1), 0.1, axis='y', n=10, width=0.03)
    C.wheel(M, (0.18, -0.17, G + 0.1), 0.1, axis='y', n=10, width=0.03)
    C.log(M, Vector((-0.2, -0.17, G + 0.05)), Vector((-0.2, 0.17, G + 0.1)), 0.015,
          'timber', ends=False, seg=8)
    C.wheel(M, (-0.2, 0.17, G + 0.1), 0.1, axis='y', n=10, width=0.03)
    # the lost wheel lies flat in the grass
    C.wheel(M, (-0.34, -0.3, G + 0.03), 0.1, axis='z', n=10, width=0.03)
    for s in (-1, 1):                                        # shafts on the ground
        C.log(M, Vector((0.26, s * 0.08, G + 0.16)), Vector((0.62, s * 0.1, G + 0.02)),
              0.014, 'timber', ends=False, seg=6)
    F.barrel(M, 0.05, 0.02, 0.07, 0.16, z=G + 0.19)
    F.sack(M, -0.12, -0.02, 0.9, 0.6)
    ob = cyl(0, 0, -0.1, 0.07, 0.07, 0.2, M['planks'], seg=12)       # a spilt barrel
    ob.rotation_euler = (0, math.pi / 2, 0.5)
    ob.location = (0.45, -0.3, G + 0.07)
    F.hay_scatter(M, -0.05, 0.3, 0.2, 8, seed=3)
    _moss(M, -0.2, -0.1, G + 0.02, 0.1, 4)


def campfire(M):
    rnd = random.Random(71)
    for i in range(9):
        a = i / 9 * math.tau
        s = rnd.uniform(.9, 1.2)
        ellipsoid(math.cos(a) * 0.15, math.sin(a) * 0.15, G + 0.035, 0.05 * s,
                  0.04 * s, 0.035 * s, M['rock'], seg=8, rings=6,
                  tilt=Euler((0, 0, a), 'XYZ'))
    ellipsoid(0, 0, G + 0.012, 0.11, 0.11, 0.015, M['coal'], seg=10, rings=6)
    for a in (0.2, 1.4, 2.5):
        C.log(M, Vector((math.cos(a) * 0.1, math.sin(a) * 0.1, G + 0.04)),
              Vector((-math.cos(a) * 0.1, -math.sin(a) * 0.1, G + 0.05)), 0.018, 'coal',
              ends=False, seg=6)
    C.log(M, Vector((0.32, -0.12, G + 0.05)), Vector((0.14, -0.38, G + 0.05)), 0.05,
          'bark')
    C.log(M, Vector((-0.34, 0.1, G + 0.05)), Vector((-0.2, 0.36, G + 0.05)), 0.045,
          'bark')
    C.log(M, Vector((-0.3, -0.3, G + 0.05)), Vector((-0.1, -0.4, G + 0.05)), 0.04, 'bark')
    # a tripod that still stands, the pot gone
    C.tripod(M, 0.0, 0.0, 0.3)
    F.crate(M, 0.45, 0.3, 0.12, 0.4)
    F.sack(M, 0.35, 0.4, 0.8, 1.0)


def well(M):
    rnd = random.Random(81)
    n, R = 12, 0.16
    for c in range(3):
        for i in range(n):
            a = i / n * math.tau + (0.13 if c % 2 else 0)
            if c == 2 and 3 < i < 7:
                continue
            _blk(M, math.cos(a) * R, math.sin(a) * R, G + c * 0.08, a + math.pi / 2,
                 (0.12, 0.1, 0.08), 'stone')
    ellipsoid(0, 0, G + 0.1, 0.12, 0.12, 0.01, M['water'], seg=10, rings=5)
    for s in (-1, 1):
        cyl(0, s * 0.23, G, 0.018, 0.018, 0.34, M['timber'], seg=6, smooth=False)
    C.log(M, Vector((0, -0.23, G + 0.3)), Vector((0, 0.1, G + 0.32)), 0.016, 'timber',
          ends=False, seg=6)                                # the beam, broken short
    C.log(M, Vector((0, 0.0, G + 0.3)), Vector((0, 0.0, G + 0.17)), 0.004, 'net',
          ends=False, seg=4)
    cyl(0, 0, G + 0.14, 0.032, 0.026, 0.045, M['planks'], seg=8)
    _rubble(M, 0.3, 0.2, 5, 0.18, 9)
    _moss(M, 0.1, 0.1, G + 0.19, 0.06, 6)


def _hull(M, L, W, lift, strakes, gaps, mat, rib_mat, seed, x0=None):
    """A clinker boat hull from stations: ribs along its length, strakes
    between them (a `gaps` strake is missing there)."""
    rnd = random.Random(seed)
    n = 9
    xs = [-L / 2 + L * i / (n - 1) for i in range(n)]

    def hw(x):                                               # half-beam at x
        return W / 2 * math.sqrt(max(0.0, 1 - (2 * x / L) ** 2)) + 0.012

    def z0(x):                                               # bow lifts
        return G + lift * (x + L / 2) / L + 0.012

    C.log(M, Vector((xs[0], 0, z0(xs[0]) + 0.05)), Vector((xs[-1], 0, z0(xs[-1]) + 0.05)),
          0.014, rib_mat, ends=False, seg=6)                 # keel
    for i, x in enumerate(xs[1:-1], 1):
        for s in (-1, 1):
            if (i, s) in gaps.get('ribs', ()):
                continue
            beam(Vector((x, 0, z0(x) + 0.03)), Vector((x, s * hw(x), z0(x) + 0.17)),
                 0.02, M[rib_mat], bevel=0.003)
    for j in range(strakes):
        f = (j + 1) / strakes
        for i in range(n - 1):
            xa, xb = xs[i], xs[i + 1]
            for s in (-1, 1):
                if (i, j, s) in gaps.get('planks', ()):
                    continue
                a = Vector((xa, s * hw(xa) * (0.35 + 0.65 * f), z0(xa) + 0.03 + 0.14 * f))
                b = Vector((xb, s * hw(xb) * (0.35 + 0.65 * f), z0(xb) + 0.03 + 0.14 * f))
                beam(a, b, 0.024, M[mat], bevel=0.003)
    return hw, z0


def boat_wreck(M):
    ribs = [(2, -1), (3, -1), (5, 1), (6, 1), (7, -1)]
    planks = [(i, j, -1) for i in (2, 3, 4) for j in (1, 2)] + \
             [(i, 2, 1) for i in (5, 6, 7)] + [(7, 1, -1), (6, 0, 1)]
    hw, z0 = _hull(M, 0.95, 0.34, 0.1, 3, {'ribs': ribs, 'planks': planks},
                   'wreck', 'drift', 5)
    ellipsoid(0.05, 0, G + 0.005, 0.5, 0.26, 0.04, M['sand_mound'], seg=14, rings=8)
    C.log(M, Vector((0.32, -0.34, G + 0.04)), Vector((-0.4, -0.42, G + 0.02)), 0.022,
          'drift')                                           # the snapped mast
    rbox((-0.12, -0.4, G + 0.045), (0.22, 0.18, 0.012), (0, 0, 0.25), M['sail'], bevel=0.003)
    C.log(M, Vector((0.1, 0.34, G + 0.03)), Vector((0.5, 0.3, G + 0.03)), 0.01, 'drift',
          ends=False, seg=5)                                 # an oar
    ellipsoid(0.58, 0.18, G + 0.02, 0.06, 0.06, 0.02, M['net'], seg=8, rings=5)
    ellipsoid(0.3, -0.1, G + 0.015, 0.2, 0.12, 0.035, M['sand_mound'], seg=10, rings=6)


def boat_row(M):
    hw, z0 = _hull(M, 0.75, 0.3, 0.05, 3, {}, 'planks', 'timber', 6)
    # a coloured top strake
    n = 9
    xs = [-0.375 + 0.75 * i / (n - 1) for i in range(n)]
    for i in range(n - 1):
        for s in (-1, 1):
            a = Vector((xs[i], s * hw(xs[i]), z0(xs[i]) + 0.172))
            b = Vector((xs[i + 1], s * hw(xs[i + 1]), z0(xs[i + 1]) + 0.172))
            beam(a, b, 0.022, M['teal'], bevel=0.003)
    rbox((0, 0, G + 0.056), (0.7, 0.22, 0.012), (0, 0, 0), M['planks'], bevel=0.003)
    for x in (-0.15, 0.12):                                  # thwarts
        rbox((x, 0, G + 0.13), (0.07, 0.3, 0.015), (0, 0, 0), M['planks'], bevel=0.003)
    for s in (-1, 1):                                        # oars shipped inboard
        C.log(M, Vector((-0.28, s * 0.07, G + 0.14)), Vector((0.3, -s * 0.05, G + 0.17)),
              0.009, 'timber', ends=False, seg=5)
    C.log(M, Vector((-0.44, 0.02, G + 0.12)), Vector((-0.62, 0.3, G + 0.01)), 0.006,
          'net', ends=False, seg=4)                          # painter line
    cyl(-0.62, 0.3, G, 0.012, 0.012, 0.1, M['timber'], seg=6)
    ellipsoid(0.38, -0.05, G + 0.01, 0.1, 0.15, 0.03, M['sand_mound'], seg=10, rings=6)


def whale_ribs(M):
    rnd = random.Random(91)
    C.log(M, Vector((-0.5, 0.0, G + 0.04)), Vector((0.5, 0.02, G + 0.04)), 0.03, 'bone',
          ends=False, seg=8)
    for k in range(9):
        x = -0.45 + k * 0.11
        ellipsoid(x, 0.01 * (k % 2), G + 0.05, 0.035, 0.035, 0.03, M['bone'], seg=8, rings=6)
    for i in range(6):
        x = -0.32 + i * 0.13
        Rr = 0.3 + 0.1 * math.sin(i / 5 * math.pi) + rnd.uniform(-.02, .02)
        top = 1.5 if i not in (1, 4) else 1.0                # two are broken off
        pts = [Vector((x + 0.02 * t, math.sin(t) * Rr * 1.1,
                       G + 0.04 + (1 - math.cos(t)) * Rr * 0.95))
               for t in [j * top / 6 for j in range(7)]]
        for a, b in zip(pts, pts[1:]):
            C.log(M, a, b, 0.03 - 0.003 * (pts.index(b)), 'bone', ends=False, seg=6)
    ellipsoid(0, 0.02, G + 0.005, 0.55, 0.22, 0.03, M['sand_mound'], seg=14, rings=8)


def flotsam(M):
    rnd = random.Random(101)
    ellipsoid(0, 0, G + 0.01, 0.42, 0.3, 0.05, M['sand_mound'], seg=12, rings=7)
    rbox((-0.1, 0.05, G + 0.075), (0.16, 0.14, 0.14), (0.15, -0.1, 0.5), M['planks'], bevel=0.006)
    rbox((0.12, 0.12, G + 0.06), (0.14, 0.12, 0.12), (-0.1, 0.1, -0.3), M['planks'], bevel=0.006)
    ob = cyl(0, 0, -0.1, 0.075, 0.075, 0.2, M['planks'], seg=12)
    ob.rotation_euler = (0.1, math.pi / 2 - 0.2, 0.9)
    ob.location = (0.0, -0.18, G + 0.06)
    for k in range(3):
        C.log(M, Vector((-0.3 + k * 0.05, -0.2 - k * 0.04, G + 0.03)),
              Vector((0.25 + k * 0.03, -0.1 + k * 0.08, G + 0.025)), 0.014, 'drift',
              ends=False, seg=5)
    ellipsoid(0.2, 0.0, G + 0.03, 0.12, 0.09, 0.03, M['net'], seg=8, rings=5)
    cyl(0.3, 0.2, G, 0.008, 0.008, 0.28, M['drift'], seg=5)   # a stake with a rag
    rbox((0.34, 0.2, G + 0.24), (0.1, 0.01, 0.07), (0, 0, 0), M['sail'], bevel=0.002)


def _view(fn, view, k=K_ANIMAL, **kw):
    def run(M):
        fn(M, **kw)
        for o in list(bpy.data.objects):
            if o.parent is None and o.type == 'MESH':
                o.scale = (o.scale[0] * k, o.scale[1] * k, o.scale[2] * k)
                l = o.location
                o.location = (l.x * k, l.y * k, G + (l.z - G) * k)
        yaw = YAW[view]
        if yaw:
            for o in list(bpy.data.objects):
                if o.parent is None and o.type == 'MESH':
                    x, y = o.location.x, o.location.y
                    c, s = math.cos(yaw), math.sin(yaw)
                    o.location.x, o.location.y = x * c - y * s, x * s + y * c
                    o.rotation_euler.z += yaw
    return run


def _flat(fn, k=1.35, **kw):
    return _view(fn, 'se', k=k, **kw)


LIFE = {}
for _v in ('se', 'ne'):
    LIFE[f'sheep_{_v}'] = _view(sheep, _v)
    LIFE[f'deer_{_v}'] = _view(deer, _v)
    LIFE[f'rabbit_{_v}'] = _view(rabbit, _v)
    LIFE[f'gull_{_v}'] = _view(gull_stand, _v)
    LIFE[f'duck_{_v}'] = _view(duck, _v)
LIFE['sheep_graze'] = _view(sheep, 'se', graze=True)
LIFE['deer_graze'] = _view(deer, 'se', graze=True)
LIFE['gullfly_up'] = _view(gull_fly, 'se', ang=0.75)
LIFE['gullfly_down'] = _view(gull_fly, 'se', ang=-0.45)
LIFE['gullfly_up_ne'] = _view(gull_fly, 'ne', ang=0.75)
LIFE['gullfly_down_ne'] = _view(gull_fly, 'ne', ang=-0.45)
LIFE['crab'] = _view(crab, 'se', k=1.9)
LIFE['butterfly_open'] = _view(butterfly, 'se', ang=0.9)
LIFE['butterfly_shut'] = _view(butterfly, 'se', ang=0.15)
for _n in ('ruin_wall', 'ruin_tower', 'ruin_arch', 'ruin_columns', 'menhirs',
           'wagon', 'campfire', 'well', 'boat_wreck', 'boat_row', 'whale_ribs',
           'flotsam'):
    LIFE[_n] = _flat(globals()[_n], k=1.8 if _n in ('boat_wreck', 'boat_row', 'whale_ribs', 'flotsam') else 1.9)




# ── more animals (2026-11-05, second round) ─────────────────
def _mats2(M):
    pl = plain
    M.setdefault('fox', pl('fox', '#c8611f', rough=0.9, bump=0.4, bump_scale=120, vary=0.08))
    M.setdefault('boar', pl('boar', '#4a3b32', rough=0.95, bump=0.6, bump_scale=140, vary=0.1))
    M.setdefault('cow_k', pl('cow_k', '#2b2623', rough=0.9, bump=0.4, bump_scale=120))
    M.setdefault('frog', pl('frog', '#5da63a', rough=0.5, bump=0.1))
    M.setdefault('crow', pl('crow', '#26262e', rough=0.6, bump=0.2, vary=0.05))
    M.setdefault('hawk', pl('hawk', '#7a5234', rough=0.85, bump=0.3, vary=0.08))
    M.setdefault('pink', pl('pink', '#d9a3a0', rough=0.8, bump=0.1))


def fox(M):
    _mats2(M)
    ellipsoid(0, 0, G + 0.1, 0.12, 0.05, 0.05, M['fox'], seg=12, rings=8)
    ellipsoid(0.02, 0, G + 0.085, 0.09, 0.045, 0.035, M['white'], seg=8, rings=6)
    ellipsoid(0.14, 0, G + 0.15, 0.045, 0.03, 0.03, M['fox'], seg=10, rings=8)
    ellipsoid(0.185, 0, G + 0.14, 0.022, 0.016, 0.014, M['white'], seg=8, rings=6)
    ellipsoid(0.205, 0, G + 0.145, 0.007, 0.007, 0.007, M['face'], seg=6, rings=4)
    for s in (-1, 1):
        eye(M, 0.16, s * 0.022, G + 0.158, 0.006)
        ellipsoid(0.12, s * 0.022, G + 0.19, 0.012, 0.012, 0.025, M['fox'], seg=6, rings=4)
    C.log(M, Vector((-0.1, 0, G + 0.11)), Vector((-0.26, 0, G + 0.09)), 0.035, 'fox', ends=False, seg=8)
    ellipsoid(-0.28, 0, G + 0.09, 0.04, 0.035, 0.035, M['white'], seg=8, rings=6)
    for x, y in ((0.08, 0.03), (0.08, -0.03), (-0.08, 0.03), (-0.08, -0.03)):
        leg(M, x, y, 0.07, 0.012, 'face', foot=None)


def boar(M):
    _mats2(M)
    ellipsoid(0, 0, G + 0.12, 0.15, 0.085, 0.085, M['boar'], seg=12, rings=9)
    ellipsoid(0.07, 0, G + 0.15, 0.09, 0.08, 0.075, M['boar'], seg=10, rings=8)
    ellipsoid(0.19, 0, G + 0.1, 0.06, 0.045, 0.045, M['boar'], seg=10, rings=8)
    ellipsoid(0.245, 0, G + 0.085, 0.022, 0.03, 0.025, M['pink'], seg=8, rings=6)
    for s in (-1, 1):
        eye(M, 0.21, s * 0.03, G + 0.12, 0.007)
        C.log(M, Vector((0.235, s * 0.025, G + 0.075)), Vector((0.255, s * 0.04, G + 0.115)), 0.006, 'white', ends=False, seg=5)
        ellipsoid(0.16, s * 0.04, G + 0.16, 0.012, 0.012, 0.025, M['boar'], seg=6, rings=4)
    for x, y in ((0.09, 0.05), (0.09, -0.05), (-0.09, 0.05), (-0.09, -0.05)):
        leg(M, x, y, 0.075, 0.016, 'hoof', foot=None)


def cow(M, graze=False):
    _mats2(M)
    ellipsoid(0, 0, G + 0.17, 0.2, 0.09, 0.09, M['white'], seg=14, rings=10)
    ellipsoid(-0.03, 0.045, G + 0.2, 0.07, 0.05, 0.06, M['cow_k'], seg=8, rings=6)
    ellipsoid(0.09, -0.05, G + 0.17, 0.06, 0.05, 0.05, M['cow_k'], seg=8, rings=6)
    hz = G + (0.08 if graze else 0.2)
    hx = 0.27 if graze else 0.25
    ellipsoid(hx, 0, hz, 0.06, 0.04, 0.045, M['white'], seg=10, rings=8)
    ellipsoid(hx + 0.045, 0, hz - 0.012, 0.03, 0.035, 0.03, M['pink'], seg=8, rings=6)
    for s in (-1, 1):
        eye(M, hx + 0.02, s * 0.034, hz + 0.012, 0.007)
        C.log(M, Vector((hx - 0.02, s * 0.03, hz + 0.04)), Vector((hx - 0.02, s * 0.06, hz + 0.075)), 0.007, 'beak', ends=False, seg=5)
        ellipsoid(hx - 0.04, s * 0.05, hz + 0.02, 0.02, 0.012, 0.012, M['cow_k'], seg=6, rings=4)
    C.log(M, Vector((-0.2, 0, G + 0.2)), Vector((-0.23, 0, G + 0.08)), 0.008, 'cow_k', ends=False, seg=5)
    for x, y in ((0.13, 0.05), (0.13, -0.05), (-0.13, 0.05), (-0.13, -0.05)):
        leg(M, x, y, 0.1, 0.017, 'white', foot='hoof')


def frog(M):
    _mats2(M)
    ellipsoid(0, 0, G + 0.025, 0.04, 0.03, 0.025, M['frog'], seg=10, rings=7)
    ellipsoid(0.035, 0, G + 0.04, 0.022, 0.024, 0.02, M['frog'], seg=8, rings=6)
    for s in (-1, 1):
        ellipsoid(0.04, s * 0.015, G + 0.058, 0.01, 0.01, 0.01, M['frog'], seg=6, rings=4)
        eye(M, 0.047, s * 0.015, G + 0.062, 0.005)
        ellipsoid(-0.02, s * 0.035, G + 0.012, 0.03, 0.01, 0.01, M['frog'], seg=6, rings=4)


def bird_fly(M, ang, body, wing, size=1.0, span=0.11, chord=0.04):
    _mats2(M)
    h = G + 0.1
    ellipsoid(0, 0, h, 0.05 * size, 0.022 * size, 0.022 * size, M[body], seg=8, rings=6)
    ellipsoid(0.048 * size, 0, h + 0.008, 0.02 * size, 0.017 * size, 0.017 * size, M[body], seg=8, rings=6)
    C.log(M, Vector((0.066 * size, 0, h + 0.008)), Vector((0.09 * size, 0, h + 0.002)), 0.005, 'beak', ends=False, seg=4)
    ellipsoid(-0.06 * size, 0, h, 0.03 * size, 0.018 * size, 0.006, M[body], seg=6, rings=4)
    L = span * size
    for s in (-1, 1):
        a = ang * s
        ellipsoid(0.0, s * L * math.cos(ang), h + 0.01 + L * math.sin(ang),
                  chord * size, L, 0.006, M[wing], seg=10, rings=6,
                  tilt=Euler((a, 0, 0), 'XYZ'))


def crow_up(M): bird_fly(M, 0.8, 'crow', 'crow')
def crow_down(M): bird_fly(M, -0.5, 'crow', 'crow')
def hawk_soar(M): bird_fly(M, 0.12, 'hawk', 'hawk', size=1.3, span=0.2, chord=0.05)


for _v in ('se', 'ne'):
    LIFE[f'fox_{_v}'] = _view(fox, _v, k=1.8)
    LIFE[f'boar_{_v}'] = _view(boar, _v, k=1.8)
    LIFE[f'cow_{_v}'] = _view(cow, _v, k=1.8)
    LIFE[f'crow_up_{_v}'] = _view(crow_up, _v, k=1.6)
    LIFE[f'crow_down_{_v}'] = _view(crow_down, _v, k=1.6)
    LIFE[f'hawk_{_v}'] = _view(hawk_soar, _v, k=1.6)
LIFE['cow_graze'] = _view(cow, 'se', k=1.8, graze=True)
LIFE['frog'] = _view(frog, 'se', k=2.0)


def main():
    import argparse
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('what')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--out', default=P.OUT_DIR)
    args = ap.parse_args(argv)
    names = list(LIFE) if args.what == 'all' else args.what.split(',')
    for n in names:
        P.render_one(n, args.samples, args.out, funcs=LIFE, prefix='life',
                     mats=materials)


if __name__ == '__main__':
    main()
