"""The Guild Hall: a long meeting hall with a crest and banners, tier B (4 x 4 tiles).

Reads as: people who belong together meet here. A broad half-timbered hall
with a gold-and-red crest on its sign and a wide door; in front a cobbled
court with two tall banner poles, a notice board and a bench; barrels and
crates by the wall.

Moving parts: the banners flutter; plants sway; the windows and the lanterns
glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    hall (back, ridge along x, door south)       chimney at the back left
    court in front: banners left and right of the path, notice board west,
    bench east.   cobbled path from the door to the south cell (x = 0)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'guild_hall'
W, H = 4, 4
ENTRANCE = ('s', 2)                 # the south edge, x = 0
HEADROOM = 0.8

X0, X1, Y0, Y1 = -1.8, 1.8, 0.45, 1.75
EAVE = G + 0.86
DOOR_A = 0.0


def banner(M, x, y, mat):
    beam((x, y, G), (x, y, G + 1.0), 0.024, M['timber'])
    ellipsoid(x, y, G + 1.02, 0.024, 0.024, 0.024, M['gold'], seg=8, rings=6)
    with F.anim(f'banner{x:+.1f}', 'sway', pivot=(x, y, G + 0.96), amp=0.5, period=1.9):
        rbox((x + 0.1, y, G + 0.8), (0.2, 0.012, 0.28), (0, 0, 0), M[mat], bevel=0)
        rbox((x + 0.1, y, G + 0.84), (0.09, 0.016, 0.09), (0, 0.785, 0), M['gold'], bevel=0)


def board(M, x, y):
    for g in (-1, 1):
        beam((x + g * 0.17, y, G), (x + g * 0.17, y, G + 0.34), 0.026, M['timber'])
    rbox((x, y - 0.02, G + 0.28), (0.4, 0.02, 0.24), (0, 0, 0), M['timber'], bevel=0.003)
    for dx, dz, mat in ((-0.1, 0.03, 'linen'), (0.1, 0.0, 'linen'), (0.0, -0.05, 'red')):
        rbox((x + dx, y - 0.036, G + 0.28 + dz), (0.11, 0.008, 0.1), (0, 0, 0.1 * dx * 10),
             M[mat], bevel=0)


def bench(M, x, y):
    rbox((x, y, G + 0.1), (0.5, 0.12, 0.03), (0, 0, 0), M['timber'], bevel=0.003)
    for g in (-1, 1):
        beam((x + g * 0.2, y, G), (x + g * 0.2, y, G + 0.1), 0.02, M['timber'])


def build():
    random.seed(11)
    M = mats()
    dw, dh = DIM['door_wide'][0], DIM['door_wide'][1]
    hall(M, X0, X1, Y0, Y1, EAVE, 'x', 'roof', doors=[('s', DOOR_A, dw, dh)],
         wins=[('s', -1.3, 'red', True), ('s', 1.35, 'red', True), ('s', -0.7, 'teal', True),
               ('e', 1.1, 'teal', False), ('w', 1.1, 'teal', True),
               ('n', -0.9, 'red', False), ('n', 0.9, 'red', False)])
    F.chimney(M, -1.4, 1.5, EAVE + 0.3, 0.5)
    # the crest: a gold shield with a red heart and a gold pip
    crest = [(0.0, 0.0, 0.3, 0.3, 0.785, 'gold'), (0.0, 0.0, 0.2, 0.2, 0.785, 'red'),
             (0.0, 0.02, 0.09, 0.09, 0.785, 'gold')]
    F.hanging_sign(M, 's', Y0, DOOR_A + 0.62, EAVE - 0.02, flat_emblem(M, 's', crest),
                   size=F.m(1.9))

    # ── the court ─────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(DOOR_A, Y0 - 0.12), (DOOR_A, -0.4), (-0.15, -1.0), (ex, ey + 0.02)],
                  seed=3)
    banner(M, -0.75, -0.35, 'red')
    banner(M, 0.65, -0.35, 'teal')
    board(M, -1.45, -0.3)
    bench(M, 1.4, -0.45)
    F.barrel(M, 1.55, 0.1, r=0.07, h=0.17)
    F.crate(M, 1.2, 0.15, 0.12, rot=0.25)
    sack(M, -1.55, 0.15)
    for x, y, h, k in ((-1.85, -1.7, 1.2, 'pine2'), (1.85, 1.9, 1.4, 'pine'),
                       (-1.85, 1.9, 1.4, 'pine'), (1.9, -1.5, 1.0, 'pine')):
        fir(M, x, y, h, k)
    F.bush(M, -0.3, 0.15, 0.12, 3, ['fl_white'])
    F.bush(M, 0.35, 0.15, 0.12, 2, ['fl_pink'])
    F.flower_patch(M, 0.9, -1.4, 5, ['fl_yel', 'fl_red'], 5)
    F.flower_patch(M, -1.0, -1.3, 4, ['fl_white', 'fl_pink'], 6)
