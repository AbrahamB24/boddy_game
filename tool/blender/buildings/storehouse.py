"""The Storehouse: two gabled halls side by side, tier B (4 x 3 tiles).

Chosen from the mockups (user 2026-11-04: "Lagerhaus: 2", the two-gable
hall).

Reads as: goods are stored here, and what kind is on the signs. Two tall
half-timbered halls with one wide gate each. The west hall (tile roof) holds
wood and stone: a tree and a cut block on its signs, a log stack and stacked
blocks in front. The east hall (shingle roof) holds fish and meat: a fish and a
ham on its signs, barrels and crates in front. Each gable carries a hoist
beam with a crate on its rope.

Moving parts: the two crates ride up and down their ropes; plants sway; the
windows and the lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    west hall (wood, stone)   |   east hall (fish, meat)      ridges along y
    stacks in front of it     |   barrels, crates in front of it
              cobbled path from the gates to the south cell (x = -0.5)
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'storehouse'
W, H = 4, 3
ENTRANCE = ('s', 1)                 # the south edge, x = -0.5
HEADROOM = 0.7

Y0, Y1 = -0.50, 1.35
EAVE = G + 0.95
PITCH = 42.0
GATE_W, GATE_H = DIM['gate'][0] * 0.95, DIM['gate'][1] * 0.95
HALLS = (                           # x0, x1, roof, gate centre
    (-1.92, -0.06, 'roof', -0.99),
    (0.06, 1.92, 'shingle', 0.99),
)


def hall(M, x0, x1, roof, gate_a, wins, signs):
    """One tall hall: gate in the south gable, windows on the long sides."""
    xm, ym = (x0 + x1) / 2, (Y0 + Y1) / 2
    box(xm, ym, G, x1 - x0 + 0.06, Y1 - Y0 + 0.06, DIM['plinth'], M['stone_dk'], bevel=0.01)
    zpl = G + DIM['plinth']
    box(xm, ym, zpl, x1 - x0, Y1 - Y0, EAVE - zpl, M['plaster'], bevel=0.008)
    faces = {'s': (Y0, x0, x1), 'n': (Y1, x0, x1), 'e': (x1, Y0, Y1), 'w': (x0, Y0, Y1)}
    holes = {f: [] for f in faces}
    holes['s'].append((gate_a, GATE_W))
    for f, a, *_ in wins:
        holes[f].append((a, DIM['window'][0]))
    for f, (fx, a0, a1) in faces.items():
        nb = max(2, round((a1 - a0) / 0.31))
        F.wall_frame(M, f, fx, a0, a1, zpl, EAVE, nb, braces=(0, nb - 1), mid=True,
                     holes=holes[f])
    F.door(M, 's', Y0, gate_a, GATE_W, GATE_H, zpl)
    for g in (-1, 1):
        F.lantern(M, 's', Y0, gate_a + g * (GATE_W / 2 + 0.09), zpl + GATE_H - 0.08)
    for f, a, shut, glow in wins:
        F.window(M, f, faces[f][0], a, zpl + 0.42, *DIM['window'], shut, glow)
    apex = F.gable_wall(M, 's', Y0, x0, x1, EAVE, pitch=PITCH)
    F.gable_wall(M, 'n', Y1, x0, x1, EAVE, pitch=PITCH)
    F.gable_roof(M, xm, ym, EAVE, Y1 - Y0, x1 - x0, 'y', M[roof], oh=0.07, oe=0.08, pitch=PITCH)
    # two guild signs either side of the gate
    for off, emb in zip((-0.76, 0.24), signs):
        F.hanging_sign(M, 's', Y0, gate_a + off, EAVE - 0.02, emblem(M, 's', emb),
                       size=F.m(1.9))
    # the hoist: a beam out of the gable's apex, a rope and a crate on it
    bz = apex - 0.1
    beam((xm, Y0 + 0.05, bz), (xm, Y0 - 0.34, bz), 0.04, M['timber'])
    beam((xm, Y0 - 0.02, bz - 0.1), (xm, Y0 - 0.26, bz - 0.01), 0.026, M['timber'])
    with F.anim(f'hoist{gate_a:+.0f}', 'bob', pivot=(xm, Y0 - 0.34, bz), amp=0.06, period=3.0):
        beam((xm, Y0 - 0.34, bz), (xm, Y0 - 0.34, bz - 0.2), 0.012, M['iron'], bevel=0)
        F.crate(M, xm, Y0 - 0.34, 0.12, z=bz - 0.33)
    return apex


def build():
    M = mats()
    hall(M, *HALLS[0][:3], HALLS[0][3],
         wins=[('w', 0.05, 'teal', False), ('w', 0.55, 'teal', True), ('w', 1.1, 'teal', False)],
         signs=('tree', 'block'))
    hall(M, *HALLS[1][:3], HALLS[1][3],
         wins=[('e', 0.05, 'red', True), ('e', 0.55, 'red', False), ('e', 1.1, 'red', True)],
         signs=('fish', 'ham'))

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(-0.99, Y0 - 0.12), (-0.99, -0.85), (-0.5, -1.15), (ex, ey + 0.02)], seed=2)
    F.cobble_path(M, [(0.99, Y0 - 0.12), (0.99, -0.85), (0.3, -1.2), (-0.5, -1.2)], seed=5)
    dirt(M, 0.0, -0.95, 1.7, 0.55, 3)
    # west: wood and stone
    log_stack(M, -1.52, -0.98, 0.72, 3, 0.06, 'x')
    block_stack(M, -0.22, -0.98, 2, 2, 2, seed=2)
    stone_block(M, -1.6, -1.3, s=(0.17, 0.13, 0.1), rot=0.4)
    board_stack(M, -1.0, -1.38, 0.5, 0.2, 0.16, 0.0)
    # east: fish and meat
    F.barrel(M, 1.5, -0.9, r=0.075, h=0.18)
    F.barrel(M, 1.68, -0.78, r=0.07, h=0.17)
    F.barrel(M, 1.74, -1.0, r=0.07, h=0.17)
    F.crate(M, 1.2, -1.15, 0.13, rot=0.2)
    F.crate(M, 1.2, -1.15, 0.12, z=G + 0.13, rot=0.5)
    F.crate(M, 0.65, -1.3, 0.12)
    sack(M, 1.5, -1.3)
    sack(M, 1.64, -1.22)
    for x, y, h, k in ((-1.9, -1.4, 1.3, 'pine2'),):
        fir(M, x, y, h, k)
    F.bush(M, 0.0, -0.62, 0.1, 3, ['fl_white'])
    F.flower_patch(M, 0.2, -1.4, 5, ['fl_yel', 'fl_red'], 4)
