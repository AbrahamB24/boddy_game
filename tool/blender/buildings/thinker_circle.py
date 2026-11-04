"""The Workshop: a potter's workshop, tier C (3 x 3 tiles).

Chosen from the mockups (user 2026-11-04: "workshop: 2", the pottery).

Reads as: things are made here, and in era II that means clay. An open
straw-roofed hut on posts with a potter's wheel, shelves of jugs and a plank
back wall; beside it a clay kiln with a glowing mouth and smoke; in front a
clay pit full of water, raw pots drying on boards, a heap of clay and a
jug-shaped sign.

Moving parts: the wheel's jugs sway gently, the drying pots sway; the kiln
fire and the lantern glow by themselves; plants sway.

Layout (x east, y north; the camera looks from +x/-y):

    hut (west, back, ridge along x)       kiln (east, back)
    wheel and shelves under the roof      clay pit in front of the hut
    drying boards, pots; cobbled path to the south cell (x = 0)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'thinker_circle'
W, H = 3, 3
ENTRANCE = ('s', 1)                 # the south edge, x = 0
HEADROOM = 0.8

X0, X1, Y0, Y1 = -1.4, 0.25, 0.25, 1.35
EAVE = G + 0.78
KX, KY = 0.95, 0.85


def jug(M, x, y, z, h=0.1, r=0.03, mat='ox'):
    cyl(x, y, z, r * 0.8, r, h * 0.55, M[mat], seg=10)
    cyl(x, y, z + h * 0.55, r, r * 0.55, h * 0.35, M[mat], seg=10)
    cyl(x, y, z + h * 0.9, r * 0.6, r * 0.7, h * 0.1, M[mat], seg=10)


def kiln(M):
    box(KX, KY, G, 0.52, 0.52, 0.05, M['stone_dk'], bevel=0.008)
    ellipsoid(KX, KY, G + 0.05, 0.23, 0.23, 0.27, M['ox'], seg=18, rings=12)
    rbox((KX, KY - 0.21, G + 0.12), (0.12, 0.05, 0.11), (0, 0, 0), M['dark'], bevel=0.004)
    rbox((KX, KY - 0.225, G + 0.1), (0.07, 0.02, 0.06), (0, 0, 0), M['fire'], bevel=0)
    for g in (-1, 1):
        beam((KX + g * 0.09, KY - 0.23, G + 0.05), (KX + g * 0.09, KY - 0.23, G + 0.19), 0.018,
             M['stone'])
    beam((KX - 0.09, KY - 0.23, G + 0.19), (KX + 0.09, KY - 0.23, G + 0.19), 0.02, M['stone'])
    F.chimney(M, KX, KY, G + 0.24, 0.32)
    # fuel stack
    log_stack(M, KX + 0.05, KY + 0.42, 0.4, 2, 0.045, 'x')


def hut(M):
    xm, ym = (X0 + X1) / 2, (Y0 + Y1) / 2
    box(xm, ym, G, X1 - X0, Y1 - Y0, 0.02, M['planks'], bevel=0.004)           # the floor
    for x in (X0 + 0.04, X1 - 0.04):
        for y in (Y0 + 0.04, Y1 - 0.04):
            beam((x, y, G), (x, y, EAVE), 0.05, M['timber'])
    beam((X0, Y0 + 0.04, EAVE), (X1, Y0 + 0.04, EAVE), 0.05, M['timber'])
    beam((X0, Y1 - 0.04, EAVE), (X1, Y1 - 0.04, EAVE), 0.05, M['timber'])
    box(xm, Y1 - 0.03, G + 0.02, X1 - X0, 0.04, EAVE - G - 0.02, M['planks'], bevel=0.004)  # back wall
    box(X0 + 0.03, ym, G + 0.02, 0.04, Y1 - Y0, 0.5, M['planks'], bevel=0.004)        # west half wall
    F.gable_fill(M, 'w', X0 + 0.05, Y0, Y1, EAVE, mat='planks')
    F.gable_fill(M, 'e', X1 - 0.05, Y0, Y1, EAVE, mat='planks')
    zr = F.gable_roof(M, xm, ym, EAVE, X1 - X0, Y1 - Y0, 'x', M['hay'], oh=0.12, oe=0.12)
    # shelves of jugs along the back wall
    for z in (0.22, 0.42):
        rbox((xm - 0.1, Y1 - 0.1, G + z), (1.35, 0.12, 0.025), (0, 0, 0), M['planks'], bevel=0.003)
    with F.anim('shelfjugs', 'sway', pivot=(xm, Y1 - 0.1, G + 0.2), amp=0.06, period=3.4):
        for i in range(8):
            jug(M, X0 + 0.25 + i * 0.17, Y1 - 0.1, G + 0.235, 0.1 + 0.02 * (i % 3), 0.03,
                'ox' if i % 2 else 'log_end')
            if i % 2 == 0:
                jug(M, X0 + 0.3 + i * 0.17, Y1 - 0.1, G + 0.435, 0.09, 0.028, 'log_end')
    # the potter's wheel: a stool and a low wheel with a jug being thrown
    wx, wy = -0.55, 0.62
    rbox((wx - 0.28, wy, G + 0.09), (0.12, 0.12, 0.025), (0, 0, 0), M['planks'], bevel=0.004)
    for g in (-1, 1):
        beam((wx - 0.28 + g * 0.04, wy, G), (wx - 0.28 + g * 0.04, wy, G + 0.09), 0.018, M['timber'])
    for g in (-1, 1):
        beam((wx + g * 0.1, wy - 0.07, G), (wx + g * 0.06, wy, G + 0.15), 0.02, M['timber'])
        beam((wx + g * 0.1, wy + 0.07, G), (wx + g * 0.06, wy, G + 0.15), 0.02, M['timber'])
    cyl(wx, wy, G + 0.15, 0.1, 0.1, 0.018, M['timber'], seg=16)
    cyl(wx, wy, G + 0.168, 0.05, 0.05, 0.015, M['ox'], seg=12)
    with F.anim('wheeljug', 'sway', pivot=(wx, wy, G + 0.17), amp=0.1, period=1.6):
        jug(M, wx, wy, G + 0.18, 0.13, 0.04, 'ox')
    rbox((wx + 0.2, wy + 0.2, G + 0.06), (0.14, 0.1, 0.12), (0, 0, 0.3), M['ox'], bevel=0.01)   # clay lump
    F.lantern(M, 's', Y0 + 0.04, X1 - 0.12, EAVE - 0.08)
    return zr


def clay_pit(M, x, y):
    K.blob(x, y, 0.42, 0.3, G - 0.004, 0.035, M['ox'], seed=4)
    K.blob(x, y, 0.32, 0.22, G + 0.02, 0.012, M['water'], seed=5)
    stone_block(M, x - 0.38, y + 0.12, s=(0.08, 0.06, 0.05), rot=0.3)
    cyl(x + 0.35, y + 0.05, G, 0.05, 0.06, 0.09, M['planks'], seg=10)        # a water bucket


def drying_board(M, x, y, n):
    for g in (-1, 1):
        beam((x + g * 0.3, y, G), (x + g * 0.3, y, G + 0.1), 0.02, M['timber'])
    rbox((x, y, G + 0.1), (0.7, 0.14, 0.02), (0, 0, 0), M['planks'], bevel=0.003)
    with F.anim(f'dry{x:+.1f}', 'sway', pivot=(x, y, G + 0.11), amp=0.05, period=3.0):
        for i in range(n):
            jug(M, x - 0.27 + i * 0.12, y, G + 0.11, 0.09, 0.028, 'log_end')


def build():
    random.seed(3)
    M = mats()
    hut(M)
    kiln(M)
    # jug sign on a post at the hut's front corner
    jugs = [(0, -0.1, 0.34, 0.26, 0.0, 'ox'), (0, 0.12, 0.2, 0.18, 0.0, 'ox'),
            (0, 0.28, 0.12, 0.1, 0.0, 'ox'), (-0.2, 0.0, 0.07, 0.2, 0.0, 'ox')]
    F.hanging_sign(M, 's', Y0 + 0.04, -0.95, EAVE - 0.02, flat_emblem(M, 's', jugs), size=F.m(2.0))

    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(-0.55, Y0 - 0.05), (-0.55, -0.35), (-0.25, -0.8), (ex, ey + 0.02)], seed=3)
    dirt(M, 0.2, -0.5, 1.4, 0.9, 4)
    clay_pit(M, -1.0, -0.65)
    drying_board(M, 0.4, -0.35, 5)
    drying_board(M, 0.95, -0.85, 4)
    jug(M, 1.3, -0.25, G, 0.14, 0.045)
    jug(M, 1.38, -0.4, G, 0.11, 0.04, 'log_end')
    F.barrel(M, -1.35, -1.1, r=0.07, h=0.17)
    F.crate(M, -0.9, -1.25, 0.12, rot=0.2)
    sack(M, 0.0, -1.25)
    for x, y, h, k in ((-1.4, 1.5, 1.4, 'pine2'), (1.4, 1.45, 1.3, 'pine'),
                       (1.4, -1.4, 0.95, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, 0.45, 0.0, 0.1, 3, ['fl_white'])
    F.flower_patch(M, 0.55, -1.4, 5, ['fl_yel', 'fl_red'], 5)
