"""The Trade Center: a merchants' house with open market stalls, tier B (4 x 3 tiles).

Reads as: goods change hands here. A half-timbered merchants' house with a
golden coin on its sign and a wide door; in front of it two market stalls under
striped awnings, one with fruit and cloth, one with pots and a scale; a loaded
handcart, crates, barrels and sacks, a banner on a pole.

Moving parts: the awning fringe and banner flutter; plants sway; the windows
and the lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    merchants' house (back, ridge along x)        chimney
    stall west (fruit, cloth)    stall east (pots, scale)     handcart
              cobbled path from the door to the south cell (x = -0.5)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'trading_post'
W, H = 4, 3
ENTRANCE = ('s', 1)                 # the south edge, x = -0.5
HEADROOM = 0.8

X0, X1, Y0, Y1 = -1.85, 1.85, 0.30, 1.35
EAVE = G + 0.8
DOOR_A = -0.5


def stall(M, x0, x1, y0, y1, goods, seed):
    """Four posts, a striped awning sloping to the front, a counter."""
    zh, zl = G + 0.5, G + 0.36
    for x in (x0 + 0.03, x1 - 0.03):
        beam((x, y1 - 0.03, G), (x, y1 - 0.03, zh), 0.035, M['timber'])
        beam((x, y0 + 0.03, G), (x, y0 + 0.03, zl), 0.035, M['timber'])
    n = max(2, round((x1 - x0) / 0.11))
    sw = (x1 - x0) / n
    for i in range(n):
        lean_to(M, x0 + i * sw, x0 + (i + 1) * sw, y0, y1, zh, zl, 's',
                'red' if i % 2 == 0 else 'linen', posts=False)
    with F.anim(f'fringe{x0:+.1f}', 'sway', pivot=((x0 + x1) / 2, y0, zl), amp=0.3, period=2.2):
        for i in range(n):
            rbox((x0 + (i + 0.5) * sw, y0 - 0.075, zl + 0.01), (sw, 0.015, 0.04), (0, 0, 0),
                 M['red'] if i % 2 == 0 else M['linen'], bevel=0)
    box((x0 + x1) / 2, y0 + 0.07, G, x1 - x0 - 0.08, 0.14, 0.17, M['planks'], bevel=0.006)
    box((x0 + x1) / 2, y0 + 0.07, G + 0.17, x1 - x0 - 0.02, 0.17, 0.02, M['timber'], bevel=0.004)
    rnd = random.Random(seed)
    for i in range(int((x1 - x0) / 0.1)):
        x = x0 + 0.08 + i * 0.1
        goods(M, x, y0 + 0.07, G + 0.19, i, rnd)
    rbox(((x0 + x1) / 2, y1 - 0.03, G + 0.22), (x1 - x0 - 0.06, 0.02, 0.44), (0, 0, 0),
         M['planks'], bevel=0.004)


def fruit(M, x, y, z, i, rnd):
    if i % 3 == 2:                                     # a bolt of cloth
        rbox((x, y, z + 0.04), (0.08, 0.07, 0.08), (0, 0, 0),
             M['teal'] if i % 2 else M['mustard'], bevel=0.01)
        return
    for k in range(3):
        ellipsoid(x + (k - 1) * 0.026, y + rnd.uniform(-0.02, 0.02), z + 0.025,
                  0.02, 0.02, 0.02, M['fl_red'] if (i + k) % 2 else M['mustard'], seg=8, rings=5)


def pots(M, x, y, z, i, rnd):
    if i % 4 == 3:
        beam((x, y, z), (x, y, z + 0.1), 0.01, M['iron'], bevel=0)         # scale post
        beam((x - 0.05, y, z + 0.1), (x + 0.05, y, z + 0.1), 0.008, M['iron'], bevel=0)
        for g in (-1, 1):
            cyl(x + g * 0.05, y, z + 0.06, 0.025, 0.025, 0.006, M['gold'], seg=10)
        return
    cyl(x, y, z, 0.026, 0.034, 0.05 + 0.02 * (i % 3), M['ox'], seg=10)
    cyl(x, y, z + 0.05 + 0.02 * (i % 3), 0.03, 0.02, 0.012, M['ox'], seg=10)


def cart(M, x, y, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)

    def at(f, side=0.0, z=0.0):
        return (x + f * c - side * s, y + f * s + side * c, G + z)
    rbox(at(0, 0, 0.115), (0.34, 0.2, 0.045), (0, 0, rot), M['planks'], bevel=0.004)
    for g in (-1, 1):
        rbox(at(0, g * 0.1, 0.17), (0.34, 0.018, 0.08), (0, 0, rot), M['planks'], bevel=0.004)
        disc(M, at(0, g * 0.12, 0.075), (-s, c, 0), 0.075, 0.025, 'timber')
        beam(at(0.16, g * 0.08, 0.12), at(0.46, g * 0.07, 0.07), 0.022, M['timber'])
    for k in range(3):
        sack(M, *at(-0.08 + k * 0.09, 0.0)[:2], s=0.8, rot=k)
    F.barrel(M, *at(0.08, 0.0)[:2], r=0.06, h=0.14, z=G + 0.14)


def build():
    random.seed(6)
    M = mats()
    dw, dh = DIM['door_wide'][0], DIM['door_wide'][1]
    hall(M, X0, X1, Y0, Y1, EAVE, 'x', 'roof', doors=[('s', DOOR_A, dw, dh)],
         wins=[('s', -1.4, 'red', True), ('s', 0.2, 'teal', True), ('s', 1.3, 'red', True),
               ('e', 0.82, 'teal', False), ('w', 0.82, 'teal', True), ('n', 0.0, 'red', False)])
    F.chimney(M, 1.45, 1.05, EAVE + 0.3, 0.45)
    F.hanging_sign(M, 's', Y0, DOOR_A + 0.55, EAVE - 0.02, emblem(M, 's', 'coin'), size=F.m(2.0))

    stall(M, -1.7, -0.75, -0.45, 0.05, fruit, 1)
    stall(M, 0.45, 1.4, -0.45, 0.05, pots, 2)

    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(DOOR_A, Y0 - 0.12), (DOOR_A, -0.2), (-0.45, -0.7), (ex, ey + 0.02)], seed=5)
    dirt(M, 0.1, -0.7, 1.9, 0.7, 3)
    cart(M, 1.55, -0.95, 2.5)
    F.crate(M, -1.75, -0.8, 0.12, rot=0.2)
    F.crate(M, -1.75, -0.8, 0.12, z=G + 0.12, rot=0.5)
    F.barrel(M, -1.45, -1.05, r=0.075, h=0.18)
    F.barrel(M, -1.3, -1.2, r=0.07, h=0.17)
    sack(M, 0.0, -1.1)
    sack(M, 0.14, -1.02)
    F.crate(M, 1.85, -0.45, 0.12, rot=0.3)
    beam((-1.95, -1.2, G), (-1.95, -1.2, G + 0.85), 0.022, M['timber'])
    with F.anim('tradebanner', 'sway', pivot=(-1.95, -1.2, G + 0.8), amp=0.5, period=1.9):
        rbox((-1.86, -1.2, G + 0.72), (0.18, 0.012, 0.14), (0, 0, 0), M['red'], bevel=0)
        rbox((-1.86, -1.2, G + 0.73), (0.07, 0.016, 0.07), (0, 0, 0), M['gold'], bevel=0)
    for x, y, h, k in ((-1.95, 1.45, 1.4, 'pine2'), (1.95, 1.45, 1.3, 'pine'),
                       (1.95, -1.45, 1.0, 'pine')):
        fir(M, x, y, h, k)
    F.bush(M, 0.1, 0.05, 0.1, 3, ['fl_white'])
    F.flower_patch(M, 0.7, -1.25, 5, ['fl_yel', 'fl_red'], 5)
