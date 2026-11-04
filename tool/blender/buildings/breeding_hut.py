"""The Breeding Hut: a nursery cottage with a nesting porch, tier B (4 x 4 tiles).

Reads as: eggs and young are tended here. A half-timbered cottage with a
heart on its sign; in front a timber porch holding a row of straw nests with
eggs in them, a fenced run with a hen and hay, a heat lamp of warm windows.

Moving parts: plants sway; the windows, the lanterns and one glowing egg
glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    cottage (ridge along x, door south)       chimney at the back
    nesting porch in front of it              fenced run with hay to the east
              cobbled path from the door to the south cell (x = +0.5)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F
from buildings import hatchery as Hy

ID = 'breeding_hut'
W, H = 4, 4
ENTRANCE = ('s', 2)                 # the south edge, x = +0.5
HEADROOM = 0.7
GLOW = Hy.GLOW

X0, X1, Y0, Y1 = -1.75, 0.35, 0.10, 1.45
EAVE = G + 0.82
DOOR_A = 0.0
CHX, CHY, CHZ0, CHH = -1.25, 1.1, EAVE + 0.3, 0.5
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)


def build():
    random.seed(7)
    M = Hy.materials()
    M.update({k: v for k, v in mats().items() if k not in M})
    hall(M, X0, X1, Y0, Y1, EAVE, 'x', 'roof',
         doors=[('s', DOOR_A, DIM['door'][0], DIM['door'][1])],
         wins=[('s', -1.25, 'red', True), ('s', -0.65, 'teal', True), ('e', 0.78, 'red', False),
               ('w', 0.78, 'teal', False), ('n', -0.7, 'red', True)])
    F.chimney(M, CHX, CHY, CHZ0, CHH)
    # the sign: a heart in egg-yolk gold
    heart = [(-0.1, 0.06, 0.2, 0.2, 0.785, 'red'), (0.1, 0.06, 0.2, 0.2, 0.785, 'red'),
             (0.0, -0.06, 0.2, 0.2, 0.785, 'red')]
    F.hanging_sign(M, 's', Y0, DOOR_A + 0.42, EAVE - 0.02, flat_emblem(M, 's', heart),
                   size=F.m(1.9))

    # ── the nesting porch (west half, so the door stays free) ──
    for x in (-1.7, -0.75):
        beam((x, -0.62, G), (x, -0.62, G + 0.42), 0.04, M['timber'])
    lean_to(M, -1.78, -0.7, -0.66, -0.2, G + 0.55, G + 0.42, 's', 'roof2', posts=False)
    for i, (x, eggs) in enumerate(((-1.5, ('cream', 'blue')), (-1.0, ('gold',)))):
        Hy.nest(M, x, -0.4, 0.13, eggs, seed=i)
    Hy.nest(M, -0.4, -0.35, 0.13, ('green', 'cream'), seed=3)
    Hy.nest(M, 0.3, -0.35, 0.13, ('rose',), seed=4)
    Hy.egg(M, 'gold', -1.0, -0.43, G, 0.055, glow=True)

    # ── the run ───────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(DOOR_A, Y0 - 0.12), (DOOR_A, -0.8), (0.3, -1.3), (ex, ey + 0.02)], seed=2)
    dirt(M, 1.15, -0.2, 0.75, 1.0, 3)
    fence_line(M, [(0.55, -1.0), (1.85, -1.0), (1.85, 1.1), (0.55, 1.1)])
    Hy.hen(M, 1.2, -0.3, 0.6)
    Hy.hen(M, 1.45, 0.3, 2.4, 'hen_r')
    Hy.hen(M, 0.95, 0.55, 4.0)
    F.hay_bale(M, 1.6, 0.85, G, 0.2, 0.14, 0.14, 0.2)
    F.hay_bale(M, 1.6, 0.85, G + 0.14, 0.18, 0.13, 0.13, 0.5)
    trough(M, 1.4, -0.75, 0.3, 0.0)
    F.hay_scatter(M, 1.2, 0.2, 0.4, 30, seed=2)
    F.barrel(M, 0.55, -0.52, r=0.07, h=0.17)
    F.crate(M, -1.85, -0.7, 0.12, rot=0.3)
    sack(M, 0.7, -0.75)
    for x, y, h, k in ((-1.85, 1.75, 1.4, 'pine2'), (1.7, 1.6, 1.3, 'pine'),
                       (-1.8, -1.75, 1.0, 'pine')):
        fir(M, x, y, h, k)
    F.bush(M, -0.15, -0.55, 0.12, 4, ['fl_pink'])
    F.bush(M, 0.45, 0.2, 0.11, 2, ['fl_white'])
    F.flower_patch(M, -0.9, -1.35, 6, ['fl_yel', 'fl_pink', 'fl_white'], 8)
