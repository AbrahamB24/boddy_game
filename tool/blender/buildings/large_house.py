"""The Large House: a long stable-house for monsters, tier C (2 x 5 tiles).

Reads as: many animals sleep here. One long half-timbered hall, its ridge
running the whole 5 tiles; a row of stable half-doors on the long side, each
with a trough in front; a hay loft under the south gable with a hoist and a
bale on its rope; a paddock fence along the yard; hay bales, a water trough, a
smoking chimney at the back.

Moving parts: the hay bale rides its rope; plants sway; the windows and the
lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    hall (ridge along y, gable south, loft hoist)     chimney at the back
    stable doors along its east wall + troughs        paddock fence
              cobbled path from the south gate to the south cell (x = -0.5)
"""
import math

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'large_house'
W, H = 2, 5
ENTRANCE = ('s', 0)                 # the south edge, x = -0.5
HEADROOM = 0.7

X0, X1, Y0, Y1 = -0.95, 0.05, -2.15, 2.20
EAVE = G + 0.82
PITCH = 46.0
GATE_A = -0.45
CHX, CHY, CHZ0, CHH = -0.55, 1.75, EAVE + 0.34, 0.5
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)
STALLS = (-1.3, -0.1, 1.1, 1.95)    # stable half-doors on the east wall


def build():
    M = mats()
    dw, dh = DIM['door_wide'][0] * 0.85, DIM['door_wide'][1] * 0.95
    doors = [('s', GATE_A, dw, dh)] + [('e', a, DIM['door'][0] * 0.9, DIM['door'][1] * 0.8)
                                      for a in STALLS]
    wins = [('w', a, s, g) for a, s, g in ((-1.5, 'teal', False), (-0.6, 'red', True),
                                           (0.4, 'teal', False), (1.4, 'red', True))]
    zr = hall(M, X0, X1, Y0, Y1, EAVE, 'y', 'roof', doors=doors, wins=wins, pitch=PITCH,
              oh=0.08, oe=0.1)
    F.chimney(M, CHX, CHY, CHZ0, CHH)

    # ── the hay loft in the south gable ───────────────────
    xm = (X0 + X1) / 2
    zl = EAVE + 0.2
    rbox((xm, Y0 - 0.005, zl), (0.17, 0.03, 0.2), (0, 0, 0), M['dark'], bevel=0)
    for g in (-1, 1):
        beam((xm + g * 0.1, Y0 - 0.02, zl - 0.1), (xm + g * 0.1, Y0 - 0.02, zl + 0.1), 0.03,
             M['timber'])
    beam((xm - 0.1, Y0 - 0.02, zl + 0.1), (xm + 0.1, Y0 - 0.02, zl + 0.1), 0.03, M['timber'])
    bz = zl + 0.22
    beam((xm, Y0 + 0.04, bz), (xm, Y0 - 0.32, bz), 0.04, M['timber'])
    beam((xm, Y0 - 0.02, bz - 0.1), (xm, Y0 - 0.26, bz - 0.01), 0.026, M['timber'])
    with F.anim('hay_hoist', 'bob', pivot=(xm, Y0 - 0.32, bz), amp=0.06, period=3.2):
        beam((xm, Y0 - 0.32, bz), (xm, Y0 - 0.32, bz - 0.14), 0.012, M['iron'], bevel=0)
        F.hay_bale(M, xm, Y0 - 0.32, bz - 0.27, 0.14, 0.12, 0.12)

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(GATE_A, Y0 - 0.1), (GATE_A, -2.35), (ex, ey + 0.02)], seed=3)
    dirt(M, 0.5, 0.0, 0.5, 1.9, 2)
    for a in STALLS:
        trough(M, X1 + 0.22, a, 0.26, math.pi / 2, 'hay' if a > 0 else 'water')
    fence_line(M, [(0.95, -2.2), (0.95, 2.35), (0.45, 2.35)])
    fence_line(M, [(0.95, -2.2), (0.55, -2.2)])
    F.hay_bale(M, 0.72, -1.7, G, 0.2, 0.14, 0.14, 0.3)
    F.hay_bale(M, 0.78, -1.5, G, 0.2, 0.14, 0.14, -0.2)
    F.hay_bale(M, 0.74, -1.6, G + 0.14, 0.2, 0.14, 0.14, 0.1)
    F.hay_scatter(M, 0.5, 0.6, 0.35, 28, seed=4)
    F.barrel(M, -0.15, -2.3, r=0.07, h=0.17)
    F.crate(M, -0.9, -2.35, 0.12, rot=0.2)
    fir(M, -0.9, 2.45, 1.4, 'pine2')
    fir(M, 0.8, 2.5, 1.3, 'pine')
    fir(M, -0.9, -2.5, 1.0, 'pine')
    F.bush(M, -0.2, -1.95, 0.11, 3, ['fl_yel'])
    F.bush(M, -0.9, 0.0, 0.1, 5, ['fl_white'])
    F.flower_patch(M, 0.3, -2.4, 4, ['fl_red', 'fl_white'], 6)
