"""The Fisher's: a boathouse on piles over a pond, tier C (3 x 3 tiles).

Chosen from the mockups (user 2026-11-04: "Fischer: 3, aber mit einem
Trocknungsgestell auf einem Steg").

Reads as: fish is landed here. A half-timbered boathouse stands on piles in a
pond, an upturned tarred boat is the roof of its porch, a plank walk leads in
from the road, and a side pier carries a drying rack hung with fish. A fish on
the sign, a lantern on the porch, smoke from the chimney.

Moving parts: the fish sway on the rack, a rowing boat bobs at the bank, the
reeds sway; the windows and lamps glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    pond (back)          boathouse on its platform, porch to the south
    plank walk from the south cell (x = 0), side pier with the rack to the east
    bank with barrels and nets in front
"""
import math
import random

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'fish_shop'
W, H = 3, 3
ENTRANCE = ('s', 1)                 # the south edge's middle cell, x = 0
HEADROOM = 0.6

ZD = G + 0.16                       # deck top, 0.8 m above the water
EAVE = ZD + 0.72
HX0, HX1, HY0, HY1 = -0.95, 0.75, 0.12, 1.12
CHX, CHY, CHZ0, CHH = -0.62, 0.86, ZD + 0.92, 0.46
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)

POND = (-1.42, 1.42, -0.95, 1.40)   # x0, x1, y0, y1


def house_on(M, x0, x1, y0, y1, zb, eave, door, wins, sign):
    """The boathouse: the hut of camp_kit, but standing on a deck at zb."""
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    zpl = zb + 0.02
    box(xm, ym, zb, x1 - x0, y1 - y0, eave - zb, M['plaster'], bevel=0.008)
    faces = {'s': (y0, x0, x1), 'n': (y1, x0, x1), 'e': (x1, y0, y1), 'w': (x0, y0, y1)}
    holes = {f: [] for f in faces}
    holes[door[0]].append((door[1], DIM['door'][0]))
    for f, a, *_ in wins:
        holes[f].append((a, DIM['window'][0]))
    for f, (fx, a0, a1) in faces.items():
        nb = max(2, round((a1 - a0) / 0.3))
        F.wall_frame(M, f, fx, a0, a1, zpl, eave, nb, braces=(0, nb - 1), holes=holes[f])
    f, a = door
    F.door(M, f, faces[f][0], a, *DIM['door'], zpl)
    F.lantern(M, f, faces[f][0], a + 0.16, zpl + DIM['door'][1] - 0.02)
    zc = zpl + 0.36
    for f, a, shut, glow in wins:
        F.window(M, f, faces[f][0], a, zc, *DIM['window'], shut, glow)
    F.gable_wall(M, 'e', x1, y0, y1, eave)
    F.gable_wall(M, 'w', x0, y0, y1, eave)
    zr = F.gable_roof(M, xm, ym, eave, x1 - x0, y1 - y0, 'x', M['roof'], oh=0.12, oe=0.12)
    f, a, emb, sz = sign
    F.hanging_sign(M, f, faces[f][0], a, eave - 0.02, emblem(M, f, emb), size=sz)
    return zr


def deck(M, x0, x1, y0, y1, z=None):
    z = ZD if z is None else z
    box((x0 + x1) / 2, (y0 + y1) / 2, z - 0.05, x1 - x0, y1 - y0, 0.05, M['planks'], bevel=0.004)
    # the joists show as dark edges under the deck
    box((x0 + x1) / 2, (y0 + y1) / 2, z - 0.075, x1 - x0 - 0.04, y1 - y0 - 0.04, 0.03,
        M['timber'], bevel=0.002)


def pile(M, x, y, z=None):
    cyl(x, y, G - 0.01, 0.03, 0.03, (ZD if z is None else z) - G + 0.04, M['timber'], seg=8)


def rail(M, pts, h=0.1):
    """Posts and a rope along a deck edge."""
    for p in pts:
        beam((p[0], p[1], ZD - 0.04), (p[0], p[1], ZD + h), 0.026, M['timber'])
    for a, b in zip(pts, pts[1:]):
        beam((a[0], a[1], ZD + h - 0.01), (b[0], b[1], ZD + h - 0.01), 0.014, M['net'], bevel=0)


def lamp_post(M, x, y):
    beam((x, y, ZD - 0.04), (x, y, ZD + 0.34), 0.03, M['timber'])
    beam((x, y, ZD + 0.34), (x + 0.07, y, ZD + 0.34), 0.02, M['timber'])
    ellipsoid(x + 0.07, y, ZD + 0.30, 0.026, 0.026, 0.04, M['lamp'], seg=10, rings=8)


def hang_fish(M, x, y, ztop, i):
    """One fish on a string from the beam at ztop."""
    mat = M['fish_o'] if i % 3 == 2 else M['fish_s']
    beam((x, y, ztop), (x, y, ztop - 0.045), 0.006, M['net'], bevel=0)
    ellipsoid(x, y, ztop - 0.115, 0.02, 0.03, 0.085, mat, seg=10, rings=8)
    rbox((x, y, ztop - 0.205), (0.05, 0.008, 0.045), (0, 0, 0), mat, bevel=0)


def drying_rack(M, x0, x1, y):
    """Two posts, a top beam and a low one, fish on strings, a net draped over."""
    ztop, zlow = ZD + 0.58, ZD + 0.34
    for x in (x0, x1):
        for g in (-1, 1):
            beam((x, y + g * 0.07, ZD), (x, y, ztop + 0.02), 0.034, M['timber'])
    beam((x0, y, ztop), (x1, y, ztop), 0.04, M['timber'])
    beam((x0, y, zlow), (x1, y, zlow), 0.03, M['timber'])
    with F.anim('rack_fish', 'sway', pivot=((x0 + x1) / 2, y, ztop), amp=0.22, period=2.5):
        n = 8
        for i in range(n):
            hang_fish(M, x0 + 0.05 + (x1 - x0 - 0.1) * i / (n - 1), y + (0.02 if i % 2 else -0.02),
                      ztop, i)
    # a net over the lower beam, bank side
    rbox(((x0 + x1) / 2, y - 0.045, zlow - 0.07), (x1 - x0 - 0.06, 0.012, 0.15), (0.12, 0, 0),
         M['net'], bevel=0)


def boat_canopy(M, x, y, z, rx=0.38, ry=0.17):
    """An upturned tarred rowing boat on four posts: the porch roof."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            beam((x + sx * rx * 0.62, y + sy * ry * 0.7, ZD), (x + sx * rx * 0.62, y + sy * ry * 0.7, z),
                 0.03, M['timber'])
    ellipsoid(x, y, z, rx, ry, 0.13, M['tar'], seg=20, rings=12, egg=0.18)
    for sy in (-1, 1):                              # the gunwales
        beam((x - rx * 0.92, y + sy * ry * 0.72, z + 0.012), (x + rx * 0.92, y + sy * ry * 0.72, z + 0.012),
             0.024, M['planks'])
    beam((x - rx * 0.98, y, z + 0.125), (x + rx * 0.98, y, z + 0.125), 0.026, M['planks'])
    for k in (-0.5, 0.0, 0.5):                      # ribs
        ellipsoid(x + k * rx, y, z + 0.05, 0.012, ry * (1 - k * k * 0.55), 0.09, M['planks'],
                  seg=8, rings=6)


def rowboat(M, x, y):
    with F.anim('rowboat', 'bob', pivot=(x, y, G), amp=0.012, period=2.8):
        ellipsoid(x, y, G + 0.05, 0.22, 0.085, 0.05, M['planks'], seg=16, rings=8, egg=0.15)
        ellipsoid(x + 0.01, y, G + 0.075, 0.19, 0.06, 0.035, M['dark'], seg=14, rings=6)
        for k in (-0.08, 0.06):
            beam((x + k, y - 0.085, G + 0.08), (x + k, y + 0.085, G + 0.08), 0.02, M['timber'])
        beam((x - 0.15, y + 0.04, G + 0.1), (x + 0.06, y + 0.2, G + 0.13), 0.012, M['timber'])


def reeds(M, x, y, n, seed):
    rnd = random.Random(seed)
    with F.anim(f'reed{x:+.2f}{y:+.2f}', 'sway', pivot=(x, y, G), amp=0.28, period=3.3):
        for _ in range(n):
            px, py = x + rnd.uniform(-0.09, 0.09), y + rnd.uniform(-0.07, 0.07)
            h = rnd.uniform(0.2, 0.34)
            lean = (rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04))
            beam((px, py, G), (px + lean[0], py + lean[1], G + h), 0.014, M['stem'], bevel=0)
            ellipsoid(px + lean[0], py + lean[1], G + h, 0.016, 0.016, 0.04, M['timber'], seg=8,
                      rings=6)


def pond(M):
    x0, x1, y0, y1 = POND
    box((x0 + x1) / 2, (y0 + y1) / 2, G - 0.004, x1 - x0, y1 - y0, 0.05, M['water'], bevel=0)
    rnd = random.Random(11)
    pts = []
    n = 0.19
    x = x0
    while x <= x1:
        for y in (y0, y1):
            if not (y == y0 and abs(x) < 0.27):      # the walk comes in here
                pts.append((x, y))
        x += n
    y = y0
    while y <= y1:
        pts += [(x0, y), (x1, y)]
        y += n
    for px, py in pts:
        r = rnd.uniform(0.06, 0.1)
        ellipsoid(px + rnd.uniform(-0.03, 0.03), py + rnd.uniform(-0.03, 0.03), G + r * 0.45,
                  r, r * 0.85, r * 0.7, M['rock'], seg=10, rings=7)


def build():
    M = mats()
    pond(M)

    # ── piles ─────────────────────────────────────────────
    for x in (-1.0, -0.5, 0.0, 0.5, 0.8):
        for y in (0.04, 0.45, 0.85, 1.2):
            pile(M, x, y)
    for y in (-0.8, -0.5, -0.15):
        for x in (-0.12, 0.12):
            pile(M, x, y)
    for x in (0.4, 0.9, 1.28):
        for y in (-0.62, -0.38):
            pile(M, x, y)
    for x in (-0.7, 0.3):
        pile(M, x, -0.28)

    # ── decks ─────────────────────────────────────────────
    deck(M, -1.07, 0.87, 0.0, 1.24)                      # the boathouse platform
    deck(M, -0.13, 0.13, -0.98, 0.02)                    # the plank walk
    deck(M, -0.80, 0.36, -0.30, 0.02)                    # the porch
    deck(M, 0.12, 1.32, -0.64, -0.36)                    # the side pier
    # the ramp from the bank up onto the walk
    rbox((0, -1.24, (G + 0.02 + ZD) / 2 - 0.02), (0.26, 0.56, 0.04), (0.28, 0, 0), M['planks'],
         bevel=0.004)
    F.cobble_path(M, [(0.0, -1.5), (0.0, -1.42)], seed=3, width=0.2)
    rail(M, [(0.13, -0.9), (0.13, -0.68)])
    rail(M, [(-0.13, -0.9), (-0.13, -0.5), (-0.13, -0.32)])
    rail(M, [(1.32, -0.64), (1.32, -0.36)])
    rail(M, [(0.45, -0.64), (0.9, -0.64), (1.32, -0.64)], h=0.1)
    rail(M, [(0.45, -0.36), (0.9, -0.36), (1.32, -0.36)], h=0.1)
    lamp_post(M, 0.13, -0.92)
    lamp_post(M, 1.32, -0.5)

    # ── the boathouse ─────────────────────────────────────
    house_on(M, HX0, HX1, HY0, HY1, ZD, EAVE, door=('s', 0.0),
             wins=[('s', -0.58, 'teal', True), ('e', 0.62, 'red', True),
                   ('w', 0.62, 'teal', False), ('n', -0.1, 'teal', False)],
             sign=('s', 0.30, 'fish', F.m(2.0)))
    F.chimney(M, CHX, CHY, CHZ0, CHH)
    boat_canopy(M, -0.44, -0.14, ZD + 0.5)
    F.barrel(M, -0.72, -0.2, r=0.07, h=0.17, z=ZD)
    F.barrel(M, -0.66, -0.06, r=0.06, h=0.15, z=ZD)
    F.crate(M, 0.22, -0.2, 0.11, z=ZD)
    ellipsoid(0.26, -0.06, ZD + 0.04, 0.09, 0.07, 0.05, M['net'], seg=10, rings=7)

    # ── the drying rack on the side pier ──────────────────
    drying_rack(M, 0.52, 1.18, -0.5)
    F.crate(M, 1.2, -0.45, 0.1, z=ZD)

    # ── the bank ──────────────────────────────────────────
    rowboat(M, -1.0, -0.55)
    reeds(M, -1.32, 0.2, 7, 1)
    reeds(M, 1.32, 0.9, 7, 2)
    reeds(M, 1.28, -0.2, 6, 3)
    F.barrel(M, 0.55, -1.25, r=0.075, h=0.18)
    F.barrel(M, 0.74, -1.18, r=0.06, h=0.15)
    F.crate(M, -0.55, -1.3, 0.13)
    sack(M, -0.78, -1.18)
    stump(M, 0.95, -1.3)
    leafy(M, -1.28, -1.25, 0.95, seed=2)
    leafy(M, 1.25, 1.25, 0.85, seed=5)
    F.bush(M, -0.4, -1.3, 0.12, 3, ['fl_white'])
    F.flower_patch(M, 1.05, -1.0, 5, ['fl_yel', 'fl_white'], 7)
