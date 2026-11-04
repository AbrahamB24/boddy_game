"""The Building Plot: a staked-out lot waiting for a house, tier S-ground (5 x 5 tiles).

Reads as: this ground is claimed, build here. A low rope fence on timber posts
around the whole lot, a pennant on each corner post, boundary stakes with
cloth flags, a notice board by the south corner with a coin on it, a surveyor's
tripod, a rolled measuring cord and a few pegs inside. Nothing tall: the lot
must stay readable as empty ground.

Moving parts: the four corner pennants and the stake flags flutter; plants sway.

Layout (x east, y north; the camera looks from +x/-y):

    posts every half tile along the four edges, ropes between them
    notice board and tools near the south corner; no path, no entrance
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'building_plot'
W, H = 5, 5
ROTATE = False                      # a plot has no front
HEADROOM = 0.4

E = 2.42                            # the fence line, just inside the edge
POSTS = 10


def post(M, x, y, h=0.2):
    beam((x, y, G), (x, y, G + h), 0.03, M['timber'])
    ellipsoid(x, y, G + h + 0.006, 0.02, 0.02, 0.016, M['timber'], seg=8, rings=5)


def build():
    random.seed(12)
    M = mats()
    edges = [((-E, -E), (E, -E)), ((E, -E), (E, E)), ((E, E), (-E, E)), ((-E, E), (-E, -E))]
    for (x0, y0), (x1, y1) in edges:
        for k in range(POSTS):
            t = k / POSTS
            post(M, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
        for z in (0.09, 0.16):
            beam((x0, y0, G + z), (x1, y1, G + z), 0.01, M['net'], bevel=0)
    # corner posts, tall, with pennants
    for i, (cx, cy, mat) in enumerate(((-E, -E, 'red'), (E, -E, 'mustard'), (E, E, 'teal'),
                                       (-E, E, 'red'))):
        beam((cx, cy, G), (cx, cy, G + 0.62), 0.04, M['timber'])
        cyl(cx, cy, G, 0.07, 0.07, 0.04, M['stone_dk'], seg=10)
        ellipsoid(cx, cy, G + 0.64, 0.03, 0.03, 0.03, M['gold'], seg=8, rings=6)
        with F.anim(f'corner{i}', 'sway', pivot=(cx, cy, G + 0.58), amp=0.5, period=1.6 + 0.2 * i):
            rbox((cx + 0.1, cy, G + 0.52), (0.2, 0.012, 0.12), (0, 0, 0), M[mat], bevel=0)
            rbox((cx + 0.23, cy, G + 0.52), (0.08, 0.012, 0.06), (0, 0, 0), M[mat], bevel=0)

    # boundary stakes with cloth flags along the inside
    for i, (x, y) in enumerate(((-1.2, -1.9), (0.0, -1.9), (1.2, -1.9), (1.9, -0.8), (1.9, 0.4),
                                (1.9, 1.5), (0.8, 1.9), (-0.6, 1.9), (-1.9, 1.0), (-1.9, -0.3),
                                (-1.9, -1.2))):
        beam((x, y, G), (x, y, G + 0.24), 0.014, M['timber'], bevel=0)
        with F.anim(f'stake{i}', 'sway', pivot=(x, y, G + 0.2), amp=0.5, period=1.4 + 0.1 * (i % 4)):
            rbox((x + 0.04, y, G + 0.21), (0.08, 0.008, 0.05), (0, 0, 0),
                 M['red'] if i % 2 else M['linen'], bevel=0)

    # the notice board by the south corner
    bx, by = 0.55, -2.15
    for g in (-1, 1):
        beam((bx + g * 0.17, by, G), (bx + g * 0.17, by, G + 0.38), 0.025, M['timber'])
    rbox((bx, by, G + 0.31), (0.42, 0.025, 0.28), (0, 0, 0), M['planks'], bevel=0.004)
    emblem(M, 's', 'coin')(F.P('s', by, bx, G + 0.31, 0.02), 0.26)
    rbox((bx, by + 0.01, G + 0.46), (0.5, 0.05, 0.03), (0, 0, 0), M['roof2'], bevel=0.004)

    # surveyor's tripod and a measuring cord
    tripod(M, -0.6, -2.0, 0.34)
    rbox((-0.6, -2.0, G + 0.34), (0.05, 0.05, 0.04), (0, 0, 0), M['iron'], bevel=0.004)
    cyl(-1.35, -2.1, G, 0.06, 0.06, 0.07, M['straw_dk'], seg=12)
    cyl(-1.35, -2.1, G + 0.07, 0.025, 0.025, 0.02, M['timber'], seg=8)
    for k in range(3):
        beam((-1.1 + k * 0.07, -2.05 + k * 0.02, G + 0.004), (-0.8 + k * 0.04, -2.0, G + 0.004),
             0.006, M['straw_dk'], bevel=0)
    # pegs and a few stones in the lot
    for x, y in ((-0.5, -0.4), (0.6, 0.5), (-1.0, 0.9), (1.2, -0.9)):
        beam((x, y, G), (x, y, G + 0.12), 0.012, M['timber'], bevel=0)
    stone_block(M, 1.0, 1.3, s=(0.14, 0.11, 0.08), rot=0.3)
    stone_block(M, -0.4, 0.7, s=(0.12, 0.1, 0.07), rot=-0.5)
    F.flower_patch(M, 0.3, 0.1, 5, ['fl_yel', 'fl_white'], 3, rx=0.5, ry=0.4)
    F.flower_patch(M, -1.3, -0.6, 5, ['fl_pink', 'fl_white'], 4, rx=0.4, ry=0.3)
    F.bush(M, 1.5, 0.9, 0.1, 3, ['fl_white'])
    F.bush(M, -1.6, 1.5, 0.1, 5, ['fl_yel'])
    fir(M, -2.1, 2.1, 1.0, 'pine2')
