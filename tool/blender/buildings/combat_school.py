"""The Combat School: a drill hall with a fenced training ring, tier B (5 x 4 tiles).

Reads as: fighters are trained here. A half-timbered drill hall with crossed
swords on its sign and a wide door; in front a fenced sand ring with straw
dummies, a pair of archery targets and a weapon rack with swords and shields;
banners on poles.

Moving parts: the banners flutter; plants sway; the windows and the lanterns
glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    drill hall (west, back, ridge along x)      banner poles
    fenced ring (east)  dummies + targets       weapon rack by the hall
              cobbled path from the hall door to the south cell (x = 0)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'combat_school'
W, H = 5, 4
ENTRANCE = ('s', 2)                 # the south edge, x = 0
HEADROOM = 0.8

X0, X1, Y0, Y1 = -2.3, -0.4, 0.5, 1.8
EAVE = G + 0.86
DOOR_A = -1.0


def dummy(M, x, y, rot=0.0):
    beam((x, y, G), (x, y, G + 0.36), 0.035, M['timber'])
    beam((x - 0.1, y, G + 0.27), (x + 0.1, y, G + 0.27), 0.028, M['timber'])
    ellipsoid(x, y, G + 0.24, 0.07, 0.055, 0.1, M['straw'], seg=10, rings=8)
    ellipsoid(x, y, G + 0.4, 0.04, 0.04, 0.04, M['sack'], seg=10, rings=8)
    rbox((x, y - 0.02, G + 0.27), (0.17, 0.05, 0.02), (0, 0, rot), M['red'], bevel=0.003)


def target(M, x, y):
    for g in (-1, 1):
        beam((x + g * 0.08, y + 0.06, G), (x + g * 0.02, y, G + 0.26), 0.02, M['timber'])
    beam((x, y + 0.08, G), (x, y, G + 0.26), 0.02, M['timber'])
    for w, mat, dy in ((0.24, 'linen', 0.0), (0.18, 'red', 0.012), (0.12, 'linen', 0.024),
                       (0.06, 'red', 0.036)):
        rbox((x, y - 0.03 - dy, G + 0.3), (w, 0.015, w), (0, 0.785, 0), M[mat], bevel=0.002)
    beam((x - 0.01, y - 0.06, G + 0.3), (x + 0.07, y - 0.1, G + 0.36), 0.008, M['timber'], bevel=0)


def rack(M, x, y):
    for g in (-1, 1):
        beam((x + g * 0.2, y, G), (x + g * 0.2, y, G + 0.26), 0.03, M['timber'])
    for z in (0.12, 0.24):
        beam((x - 0.2, y, G + z), (x + 0.2, y, G + z), 0.02, M['timber'])
    for i, dx in enumerate((-0.14, -0.07, 0.0)):
        rbox((x + dx, y - 0.025, G + 0.19), (0.016, 0.014, 0.17), (0, 0, 0), M['iron'], bevel=0)
        rbox((x + dx, y - 0.025, G + 0.27), (0.045, 0.014, 0.012), (0, 0, 0), M['timber'], bevel=0)
    for dx, mat in ((0.09, 'red'), (0.17, 'teal')):
        rbox((x + dx, y - 0.04, G + 0.17), (0.065, 0.016, 0.085), (0, 0, 0), M[mat], bevel=0.004)
        rbox((x + dx, y - 0.052, G + 0.17), (0.02, 0.01, 0.02), (0, 0, 0), M['iron'], bevel=0)


def banner(M, x, y, mat):
    beam((x, y, G), (x, y, G + 0.9), 0.022, M['timber'])
    ellipsoid(x, y, G + 0.92, 0.022, 0.022, 0.022, M['gold'], seg=8, rings=6)
    with F.anim(f'banner{x:+.1f}', 'sway', pivot=(x, y, G + 0.86), amp=0.5, period=1.9):
        rbox((x + 0.09, y, G + 0.78), (0.18, 0.012, 0.14), (0, 0, 0), M[mat], bevel=0)
        rbox((x + 0.09, y, G + 0.79), (0.07, 0.016, 0.07), (0, 0, 0), M['gold'], bevel=0)


def build():
    random.seed(4)
    M = mats()
    dw, dh = DIM['door_wide'][0], DIM['door_wide'][1]
    hall(M, X0, X1, Y0, Y1, EAVE, 'x', 'roof', doors=[('s', DOOR_A, dw, dh)],
         wins=[('s', -1.9, 'red', True), ('s', -0.55, 'red', True), ('e', 1.15, 'teal', False),
               ('w', 1.15, 'teal', True), ('n', -1.0, 'red', False)])
    F.chimney(M, -1.9, 1.5, EAVE + 0.3, 0.45)
    swords = [(-0.2, 0.0, 0.07, 0.62, 0.62, 'iron'), (0.2, 0.0, 0.07, 0.62, -0.62, 'iron'),
              (-0.2, -0.17, 0.2, 0.05, 0.62, 'timber'), (0.2, -0.17, 0.2, 0.05, -0.62, 'timber')]
    F.hanging_sign(M, 's', Y0, DOOR_A + 0.55, EAVE - 0.02, flat_emblem(M, 's', swords),
                   size=F.m(2.0))

    # ── the ring ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(DOOR_A, Y0 - 0.12), (DOOR_A, -0.35), (-0.5, -0.95), (-0.1, -1.4),
                      (ex, ey + 0.02)], seed=7)
    dirt(M, 1.15, 0.2, 1.3, 1.3, 3, 'gravel')
    fence_line(M, [(-0.3, -0.7), (2.35, -0.7), (2.35, 1.8), (-0.3, 1.8)], h=0.15, step=0.12)
    for x, y, r in ((0.25, 0.1, 0.1), (0.85, 0.5, -0.2), (1.45, 0.0, 0.3)):
        dummy(M, x, y, r)
    target(M, 1.0, 1.55)
    target(M, 1.8, 1.5)
    rack(M, -0.25, 0.15)
    F.hay_bale(M, 2.0, 0.1, G, 0.2, 0.14, 0.14, 0.2)
    F.hay_bale(M, 2.0, 0.3, G, 0.2, 0.14, 0.14, -0.1)
    banner(M, -0.35, -0.7, 'red')
    banner(M, 2.35, -0.7, 'teal')

    F.barrel(M, -2.2, -0.2, r=0.07, h=0.17)
    F.crate(M, -1.85, -0.15, 0.12, rot=0.2)
    sack(M, -2.1, 0.05)
    for x, y, h, k in ((-2.4, -1.7, 1.2, 'pine2'), (2.4, 2.3, 1.4, 'pine'),
                       (-2.4, 2.35, 1.4, 'pine')):
        fir(M, x, y, h, k)
    F.bush(M, -1.4, -0.7, 0.12, 3, ['fl_white'])
    F.flower_patch(M, 0.9, -1.6, 5, ['fl_yel', 'fl_red'], 5)
    F.flower_patch(M, 1.9, -1.3, 4, ['fl_white', 'fl_pink'], 6)
