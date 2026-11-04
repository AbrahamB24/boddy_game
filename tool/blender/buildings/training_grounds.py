"""The Training Grounds: a round arena with tiered stands, tier C (3 x 3 tiles).

Chosen from the mockups (user 2026-11-04: "Traininggrounds: 2", the arena).

Reads as: monsters are drilled here, and others watch (era III, terracotta).
A round sand arena ringed by two steps of terracotta-and-timber benches, open
to the south where the gate is, pennant masts on the stands, a sparring post
and two straw dummies on the sand, a weapon rack and a water barrel by the
gate.

Moving parts: the pennants flutter; plants sway; the gate lanterns glow by
themselves.

Layout (x east, y north; the camera looks from +x/-y):

    stands in a ring (radius 1.2 / 1.36), gap at the south
    sand disc inside, sparring post in the middle
    cobbled path from the gate to the south cell (x = 0)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'training_grounds'
W, H = 3, 3
ENTRANCE = ('s', 1)                 # the south edge, x = 0
HEADROOM = 1.0

CX, CY = 0.0, 0.1
GATE = -math.pi / 2                 # the ring's gap faces south
GAP = 0.42                          # half gap, radians


def ring(M, r, h, mat, seat=None, n=30):
    """Bench segments around the arena, leaving the gate open."""
    seg = 2 * math.pi * r / n * 1.02
    for i in range(n):
        a = 2 * math.pi * i / n
        d = (a - GATE + math.pi) % (2 * math.pi) - math.pi
        if abs(d) < GAP:
            continue
        x, y = CX + r * math.cos(a), CY + r * math.sin(a)
        rbox((x, y, G + h / 2), (0.15, seg, h), (0, 0, a), M[mat], bevel=0.006)
        if seat:
            rbox((x, y, G + h + 0.012), (0.15, seg, 0.025), (0, 0, a), M[seat], bevel=0.003)


def dummy(M, x, y, rot=0.0):
    beam((x, y, G), (x, y, G + 0.36), 0.035, M['timber'])
    beam((x - 0.1, y, G + 0.27), (x + 0.1, y, G + 0.27), 0.028, M['timber'])
    ellipsoid(x, y, G + 0.24, 0.07, 0.055, 0.1, M['straw'], seg=10, rings=8)
    ellipsoid(x, y, G + 0.4, 0.04, 0.04, 0.04, M['sack'], seg=10, rings=8)
    rbox((x, y - 0.02, G + 0.27), (0.17, 0.05, 0.02), (0, 0, rot), M['red'], bevel=0.003)


def sparring_post(M, x, y):
    cyl(x, y, G, 0.12, 0.13, 0.03, M['stone_dk'], seg=14)
    beam((x, y, G), (x, y, G + 0.72), 0.06, M['bark'])
    for z, rot in ((0.3, 0.0), (0.45, 1.2), (0.58, 2.3)):
        d = (math.cos(rot) * 0.18, math.sin(rot) * 0.18)
        beam((x - d[0], y - d[1], G + z), (x + d[0], y + d[1], G + z), 0.026, M['timber'])
        for s in (-1, 1):
            ellipsoid(x + s * d[0], y + s * d[1], G + z, 0.03, 0.03, 0.03, M['straw'], seg=8, rings=6)
    ellipsoid(x, y, G + 0.8, 0.065, 0.065, 0.07, M['sack'], seg=12, rings=8)
    rbox((x, y - 0.06, G + 0.55), (0.14, 0.03, 0.1), (0, 0, 0), M['red'], bevel=0.004)


def pennant(M, x, y, mat, i):
    beam((x, y, G), (x, y, G + 0.75), 0.022, M['timber'])
    ellipsoid(x, y, G + 0.77, 0.022, 0.022, 0.022, M['gold'], seg=8, rings=6)
    with F.anim(f'pennant{i}', 'sway', pivot=(x, y, G + 0.7), amp=0.5, period=1.7 + 0.2 * i):
        rbox((x + 0.1, y, G + 0.62), (0.2, 0.012, 0.13), (0, 0, 0), M[mat], bevel=0)
        rbox((x + 0.23, y, G + 0.62), (0.08, 0.012, 0.07), (0, 0, 0), M[mat], bevel=0)


def build():
    random.seed(10)
    M = mats()
    # the sand
    cyl(CX, CY, G, 1.16, 1.16, 0.02, M['gravel'], seg=48)
    cyl(CX, CY, G + 0.02, 0.5, 0.5, 0.006, M['dirt'], seg=32)
    # two tiers of stands, terracotta bodies with plank seats; a low back wall
    ring(M, 1.24, 0.09, 'roof', 'planks')
    ring(M, 1.38, 0.19, 'roof', 'planks')
    ring(M, 1.48, 0.21, 'plaster')
    # the gate: two posts, a lintel and lanterns
    for g in (-1, 1):
        gx = CX + g * 0.42
        gy = CY - 1.3
        beam((gx, gy, G), (gx, gy, G + 0.5), 0.05, M['timber'])
        cyl(gx, gy, G, 0.06, 0.06, 0.04, M['stone_dk'], seg=10)
    beam((CX - 0.44, CY - 1.3, G + 0.5), (CX + 0.44, CY - 1.3, G + 0.5), 0.05, M['timber'])
    for g in (-1, 1):
        beam((CX + g * 0.42, CY - 1.3, G + 0.36), (CX + g * 0.3, CY - 1.3, G + 0.5), 0.03, M['timber'])
        F.lantern(M, 's', CY - 1.33, CX + g * 0.42, G + 0.42)
    # pennants on the stands
    for i, (a, mat) in enumerate(((GATE + 0.9, 'red'), (GATE - 0.9, 'mustard'),
                                  (GATE + 2.5, 'teal'), (GATE - 2.5, 'red'))):
        pennant(M, CX + 1.42 * math.cos(a), CY + 1.42 * math.sin(a), mat, i)

    # the arena
    sparring_post(M, CX, CY)
    dummy(M, CX - 0.6, CY - 0.1, 0.4)
    dummy(M, CX + 0.55, CY + 0.3, -0.3)
    F.hay_bale(M, CX + 0.2, CY + 0.7, G, 0.2, 0.14, 0.14, 0.3)
    # weapon rack and barrel by the gate
    rx, ry = CX - 0.8, CY - 1.0
    for g in (-1, 1):
        beam((rx + g * 0.18, ry, G), (rx + g * 0.18, ry, G + 0.24), 0.028, M['timber'])
    beam((rx - 0.18, ry, G + 0.18), (rx + 0.18, ry, G + 0.18), 0.02, M['timber'])
    for dx in (-0.1, -0.03, 0.04):
        rbox((rx + dx, ry - 0.02, G + 0.2), (0.016, 0.014, 0.16), (0, 0, 0.2), M['iron'], bevel=0)
    rbox((rx + 0.12, ry - 0.04, G + 0.12), (0.06, 0.016, 0.08), (0, 0, 0), M['red'], bevel=0.004)
    F.barrel(M, CX + 0.8, CY - 0.95, r=0.065, h=0.16)

    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(0.0, CY - 1.0), (0.0, ey + 0.02)], seed=4)
    for x, y, h, k in ((-1.45, 1.45, 1.3, 'pine2'), (1.45, 1.45, 1.35, 'pine'),
                       (-1.45, -1.4, 0.95, 'pine'), (1.45, -1.4, 0.95, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, 0.75, -1.4, 0.1, 3, ['fl_white'])
    F.flower_patch(M, -0.8, -1.42, 4, ['fl_yel', 'fl_red'], 5)
