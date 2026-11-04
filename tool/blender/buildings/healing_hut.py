"""The Healing Hut: a herbalist's cottage with a garden, tier B (5 x 4 tiles).

Reads as: the sick are cured here. A half-timbered cottage with a green cross
on its sign; raised herb beds, a cauldron bubbling over a fire, bundles of
herbs hung to dry, two cots under an open lean-to, a stone well with a bucket.

Moving parts: the herbs sway on their line; plants sway; the cauldron fire,
the windows and the lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    cottage (ridge along x, door south)       chimney at the back
    cots under a lean-to on its west side     herb beds and well in front
              cobbled path from the door to the south cell (x = 0)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'healing_hut'
W, H = 5, 4
# The front door (south) and a back door (north): the tutorial lays the first
# road NORTH of the hut, so the hut has to open that way too (and a door on the
# camera-facing side shows when it is turned).
ENTRANCE = [('s', 2), ('n', 2)]     # both at x = 0
HEADROOM = 0.7

X0, X1, Y0, Y1 = -0.55, 1.65, 0.10, 1.45
EAVE = G + 0.8
DOOR_A = 0.4
CHX, CHY, CHZ0, CHH = 1.25, 1.1, EAVE + 0.3, 0.5
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)


def herb_bed(M, x0, x1, y0, y1, seed, kind='leaf'):
    rnd = random.Random(seed)
    box((x0 + x1) / 2, (y0 + y1) / 2, G, x1 - x0, y1 - y0, 0.06, M['planks'], bevel=0.006)
    box((x0 + x1) / 2, (y0 + y1) / 2, G + 0.04, x1 - x0 - 0.05, y1 - y0 - 0.05, 0.03,
        M['soil'], bevel=0.004)
    with F.anim(f'herbs{x0:+.1f}{y0:+.1f}', 'sway', pivot=((x0 + x1) / 2, y0, G + 0.07),
                amp=0.12, period=3.3):
        n = int((x1 - x0) / 0.085)
        for i in range(n):
            for j in range(2):
                x = x0 + 0.06 + i * (x1 - x0 - 0.12) / max(1, n - 1)
                y = y0 + 0.06 + j * (y1 - y0 - 0.12)
                ellipsoid(x, y + rnd.uniform(-0.01, 0.01), G + 0.11, 0.032, 0.032,
                          0.045 + 0.02 * rnd.random(), M['leaf' if (i + j) % 2 else 'leaf2'],
                          seg=8, rings=5)
                if (i * 3 + j) % 5 == 0:
                    ellipsoid(x, y, G + 0.17, 0.016, 0.016, 0.016, M['fl_pink'], seg=6, rings=4)


def cauldron(M, x, y):
    for k in range(3):
        a = k * 2.09 + 0.4
        beam((x + 0.09 * math.cos(a), y + 0.09 * math.sin(a), G),
             (x, y, G + 0.17), 0.016, M['timber'])
    for k in range(5):
        a = k * 1.26
        beam((x + 0.05 * math.cos(a), y + 0.05 * math.sin(a), G + 0.005),
             (x + 0.04 * math.cos(a + 1.0), y + 0.04 * math.sin(a + 1.0), G + 0.03), 0.014,
             M['log_end'], bevel=0)
    ellipsoid(x, y, G + 0.015, 0.065, 0.065, 0.03, M['ember'], seg=10, rings=6)
    ellipsoid(x, y, G + 0.17, 0.1, 0.1, 0.075, M['iron'], seg=14, rings=8)
    cyl(x, y, G + 0.2, 0.082, 0.082, 0.012, M['pine'], seg=14)    # the green brew


def cot(M, x, y):
    rbox((x, y, G + 0.07), (0.34, 0.15, 0.04), (0, 0, 0), M['planks'], bevel=0.004)
    for sx in (-1, 1):
        for sy in (-1, 1):
            beam((x + sx * 0.15, y + sy * 0.06, G), (x + sx * 0.15, y + sy * 0.06, G + 0.09),
                 0.016, M['timber'])
    rbox((x + 0.01, y, G + 0.1), (0.3, 0.13, 0.035), (0, 0, 0), M['linen'], bevel=0.01)
    rbox((x - 0.12, y, G + 0.125), (0.07, 0.1, 0.03), (0, 0, 0), M['linen'], bevel=0.01)


def well(M, x, y):
    for k in range(8):
        a = k * math.pi / 4
        rbox((x + 0.08 * math.cos(a), y + 0.08 * math.sin(a), G + 0.05),
             (0.07, 0.04, 0.1), (0, 0, a + math.pi / 2), M['stone'], bevel=0.006)
    cyl(x, y, G + 0.09, 0.07, 0.07, 0.012, M['water'], seg=14)
    for g in (-1, 1):
        beam((x + g * 0.09, y, G), (x + g * 0.09, y, G + 0.3), 0.02, M['timber'])
    beam((x - 0.09, y, G + 0.3), (x + 0.09, y, G + 0.3), 0.022, M['timber'])
    rbox((x, y, G + 0.32), (0.26, 0.17, 0.02), (0, 0, 0), M['roof2'], bevel=0.004)


def build():
    random.seed(5)
    M = mats()
    hall(M, X0, X1, Y0, Y1, EAVE, 'x', 'roof',
         doors=[('s', DOOR_A, DIM['door'][0], DIM['door'][1]),
                ('n', DOOR_A, DIM['door'][0], DIM['door'][1])],
         wins=[('s', -0.2, 'teal', True), ('s', 1.1, 'teal', True), ('e', 0.78, 'red', False),
               ('w', 0.78, 'red', True), ('n', 1.2, 'teal', False), ('n', -0.1, 'teal', True)])
    F.chimney(M, CHX, CHY, CHZ0, CHH)
    cross = [(0, 0, 0.17, 0.55, 0.0, 'pine'), (0, 0.03, 0.55, 0.17, 0.0, 'pine')]
    F.hanging_sign(M, 's', Y0, DOOR_A + 0.38, EAVE - 0.02, flat_emblem(M, 's', cross),
                   size=F.m(1.9))

    # the dried-herb line under the eave
    with F.anim('driedherbs', 'sway', pivot=(0.5, Y0 - 0.08, EAVE - 0.04), amp=0.22, period=2.6):
        for i, x in enumerate((-0.45, -0.38, 0.8, 0.9, 1.0, 1.2)):
            ellipsoid(x, Y0 - 0.07, EAVE - 0.14, 0.025, 0.02, 0.06,
                      M['leaf' if i % 2 else 'straw_dk'], seg=8, rings=6)
            beam((x, Y0 - 0.07, EAVE - 0.03), (x, Y0 - 0.07, EAVE - 0.08), 0.007, M['net'],
                 bevel=0)

    # ── the cots under a lean-to, west of the cottage ─────
    lean_to(M, -2.2, -0.6, 0.15, 1.1, G + 0.62, G + 0.45, 's', 'roof2')
    cot(M, -1.75, 0.55)
    cot(M, -1.2, 0.55)
    rbox((-1.5, 0.95, G + 0.2), (0.7, 0.03, 0.4), (0, 0, 0), M['planks'], bevel=0.004)

    # ── the garden ────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE[0])
    F.cobble_path(M, [(DOOR_A, Y0 - 0.12), (DOOR_A, -0.5), (0.1, -0.95), (ex, ey + 0.02)], seed=4)
    nx, ny = F.entrance_point(W, H, 'n', 2)
    F.cobble_path(M, [(DOOR_A, Y1 + 0.1), (0.2, 1.8), (nx, ny - 0.02)], seed=9)
    dirt(M, 0.4, -0.9, 1.5, 0.85, 2)
    herb_bed(M, -2.15, -1.15, -0.85, -0.55, 1)
    herb_bed(M, -2.15, -1.15, -1.25, -0.95, 2)
    herb_bed(M, 1.0, 2.0, -0.7, -0.4, 3)
    herb_bed(M, 1.0, 2.0, -1.1, -0.8, 4)
    cauldron(M, -0.6, -0.55)
    well(M, 1.1, 0.45)
    F.barrel(M, 2.0, 0.5, r=0.07, h=0.17)
    F.crate(M, 2.15, 1.1, 0.12, rot=0.2)
    F.crate(M, -0.55, -1.4, 0.12)
    sack(M, -0.35, -1.35)
    for x, y, h, k in ((-2.3, 1.7, 1.4, 'pine2'), (2.25, 1.7, 1.3, 'pine'),
                       (-2.3, -1.75, 1.0, 'pine')):
        fir(M, x, y, h, k)
    F.bush(M, 0.6, -0.35, 0.12, 3, ['fl_white'])
    F.bush(M, -0.45, 0.65, 0.1, 5, ['fl_pink'])
    F.flower_patch(M, 0.9, -1.35, 6, ['fl_blue', 'fl_white', 'fl_yel'], 7)
