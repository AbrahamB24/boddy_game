"""The Caravanserai: a walled inn courtyard for travellers, tier B (4 x 3 tiles).

Reads as: caravans rest here. A low stone wall with a timber gate encloses a
courtyard; at the back a half-timbered inn with a lit window row, to the east
an open stable shed with hay, in the yard a well, a covered wagon and stacked
bales and barrels; a banner over the gate.

Moving parts: the gate banner and the wagon's pennant flutter; plants sway; the
windows and the lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    inn (back, ridge along x)       chimney        stable shed (east)
    well, wagon, bales in the courtyard
    wall along the south edge with the gate at x = -0.5
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'caravanserai'
W, H = 4, 3
ENTRANCE = ('s', 1)                 # the south edge, x = -0.5
HEADROOM = 0.8

X0, X1, Y0, Y1 = -1.9, 0.75, 0.35, 1.4
EAVE = G + 0.82
GATE_X = -0.5
WALL_Y = -1.3
GATE_W = 0.5


def wall(M, x0, x1, y, h=0.26):
    box((x0 + x1) / 2, y, G, x1 - x0, 0.1, h, M['stone'], bevel=0.008)
    box((x0 + x1) / 2, y, G + h, x1 - x0 + 0.02, 0.13, 0.03, M['stone_dk'], bevel=0.006)


def covered_wagon(M, x, y, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)

    def at(f, side=0.0, z=0.0):
        return (x + f * c - side * s, y + f * s + side * c, G + z)
    rbox(at(0, 0, 0.12), (0.46, 0.22, 0.04), (0, 0, rot), M['planks'], bevel=0.004)
    for g in (-1, 1):
        rbox(at(0, g * 0.105, 0.17), (0.46, 0.016, 0.07), (0, 0, rot), M['planks'], bevel=0.004)
        for f in (-0.14, 0.14):
            disc(M, at(f, g * 0.13, 0.08), (-s, c, 0), 0.08, 0.025, 'timber')
    ellipsoid(*at(0, 0, 0.26), 0.25, 0.115, 0.12, M['linen'], seg=14, rings=8, tilt=(0, 0, rot))
    beam(at(0.3, 0.05, 0.13), at(0.62, 0.04, 0.08), 0.022, M['timber'])
    beam(at(0.3, -0.05, 0.13), at(0.62, -0.04, 0.08), 0.022, M['timber'])
    for k in range(3):
        beam(at(-0.14 + k * 0.14, 0.0, 0.17), at(-0.14 + k * 0.14, 0.0, 0.37), 0.01, M['timber'],
             bevel=0)


def well(M, x, y):
    for k in range(8):
        a = k * math.pi / 4
        rbox((x + 0.08 * math.cos(a), y + 0.08 * math.sin(a), G + 0.06),
             (0.07, 0.04, 0.12), (0, 0, a + math.pi / 2), M['stone'], bevel=0.006)
    cyl(x, y, G + 0.1, 0.07, 0.07, 0.012, M['water'], seg=14)
    for g in (-1, 1):
        beam((x + g * 0.09, y, G), (x + g * 0.09, y, G + 0.32), 0.02, M['timber'])
    beam((x - 0.09, y, G + 0.32), (x + 0.09, y, G + 0.32), 0.022, M['timber'])
    rbox((x, y, G + 0.34), (0.26, 0.17, 0.02), (0, 0, 0), M['roof2'], bevel=0.004)


def build():
    random.seed(8)
    M = mats()
    dw, dh = DIM['door_wide'][0], DIM['door_wide'][1]
    hall(M, X0, X1, Y0, Y1, EAVE, 'x', 'roof',
         doors=[('s', -0.6, dw, dh), ('s', -1.55, DIM['door'][0], DIM['door'][1])],
         wins=[('s', -1.05, 'red', True), ('s', 0.05, 'teal', True), ('s', 0.5, 'red', True),
               ('e', 0.88, 'teal', False), ('w', 0.88, 'teal', True), ('n', -0.6, 'red', True)])
    F.chimney(M, 0.3, 1.1, EAVE + 0.3, 0.45)
    star = [(0, 0, 0.4, 0.4, 0.0, 'gold'), (0, 0, 0.4, 0.4, 0.785, 'gold'),
            (0, 0, 0.12, 0.12, 0.0, 'dark')]
    F.hanging_sign(M, 's', Y0, -0.0, EAVE - 0.02, flat_emblem(M, 's', star), size=F.m(2.0))

    # ── the stable shed to the east ───────────────────────
    lean_to(M, 1.05, 1.95, -0.6, 0.9, G + 0.6, G + 0.42, 's', 'roof2')
    rbox((1.5, 0.88, G + 0.2), (0.88, 0.03, 0.4), (0, 0, 0), M['planks'], bevel=0.004)
    F.hay_bale(M, 1.75, 0.6, G, 0.2, 0.14, 0.14, 0.1)
    F.hay_bale(M, 1.4, 0.65, G, 0.2, 0.14, 0.14, -0.1)
    F.hay_bale(M, 1.4, 0.65, G + 0.14, 0.18, 0.13, 0.13, 0.4)
    trough(M, 1.5, -0.3, 0.5, math.pi / 2, 'hay')
    trough(M, 1.3, 0.1, 0.3, math.pi / 2)

    # ── the wall and the gate ─────────────────────────────
    wall(M, -1.95, GATE_X - GATE_W / 2 - 0.04, WALL_Y)
    wall(M, GATE_X + GATE_W / 2 + 0.04, 1.95, WALL_Y)
    for g in (-1, 1):
        px = GATE_X + g * (GATE_W / 2 + 0.02)
        beam((px, WALL_Y, G), (px, WALL_Y, G + 0.62), 0.05, M['timber'])
        F.lantern(M, 's', WALL_Y - 0.03, px + g * 0.0, G + 0.44)
    beam((GATE_X - GATE_W / 2 - 0.02, WALL_Y, G + 0.6), (GATE_X + GATE_W / 2 + 0.02, WALL_Y, G + 0.6),
         0.05, M['timber'])
    for g in (-1, 1):
        beam((GATE_X + g * (GATE_W / 2 + 0.02), WALL_Y, G + 0.46),
             (GATE_X + g * (GATE_W / 2 - 0.1), WALL_Y, G + 0.6), 0.03, M['timber'])
    beam((GATE_X, WALL_Y, G + 0.6), (GATE_X, WALL_Y, G + 0.95), 0.016, M['timber'], bevel=0)
    with F.anim('gatebanner', 'sway', pivot=(GATE_X, WALL_Y, G + 0.9), amp=0.5, period=1.8):
        rbox((GATE_X + 0.09, WALL_Y, G + 0.84), (0.18, 0.012, 0.14), (0, 0, 0), M['red'], bevel=0)
        rbox((GATE_X + 0.09, WALL_Y, G + 0.85), (0.07, 0.016, 0.07), (0, 0, 0), M['gold'], bevel=0)
    # side walls, half height, running back to the inn
    wall_side = lambda x, y0, y1: box(x, (y0 + y1) / 2, G, 0.1, y1 - y0, 0.26, M['stone'],
                                      bevel=0.008)
    wall_side(-1.95, WALL_Y, Y0)
    wall_side(1.95, WALL_Y, 1.0)

    # ── the courtyard ─────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(-0.6, Y0 - 0.1), (-0.6, -0.4), (GATE_X, -0.85), (ex, ey + 0.02)], seed=3)
    dirt(M, -0.2, -0.45, 1.6, 0.8, 3)
    well(M, -0.25, 0.0)
    covered_wagon(M, -1.2, -0.6, 0.3)
    F.barrel(M, 0.6, -0.9, r=0.075, h=0.18)
    F.barrel(M, 0.78, -0.8, r=0.07, h=0.17)
    F.crate(M, 0.35, -1.0, 0.12, rot=0.2)
    sack(M, 0.05, -0.85)
    sack(M, 0.18, -0.78)
    F.hay_bale(M, -1.7, -0.1, G, 0.2, 0.14, 0.14, 0.2)
    F.barrel(M, -1.75, -1.0, r=0.07, h=0.17)
    for x, y, h, k in ((-1.95, 1.5, 1.4, 'pine2'), (1.95, 1.5, 1.3, 'pine'),
                       (1.95, -1.45, 1.0, 'pine2'), (-1.95, -1.45, 1.1, 'pine')):
        fir(M, x, y, h, k)
    F.bush(M, -0.9, -1.1, 0.1, 3, ['fl_white'])
    F.flower_patch(M, 0.3, -1.5, 5, ['fl_yel', 'fl_red'], 5)
    F.flower_patch(M, -1.3, -1.5, 5, ['fl_white', 'fl_pink'], 6)
