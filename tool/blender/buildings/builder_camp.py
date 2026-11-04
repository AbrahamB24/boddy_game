"""The Builder Camp: a building site with a half-raised timber frame, tier B (5 x 5 tiles).

Reads as: things get built here. A foreman's hut with a hammer on its sign; on
the back plot a house frame half done (posts, plates, rafters, laths on one
slope, the west gable already filled); a treadwheel crane lifting a stone
block; stacks of boards, logs and stone, a sawhorse, a wheelbarrow, a mortar
tub and a ladder.

Moving parts: the crane's load rides up and down; the site pennant flutters;
plants sway; the windows and the lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    foreman's hut (west, back)        the house frame (east, back)
    stone + mortar to the west        crane in the middle, boards + logs east
              cobbled path from the hut door to the south cell (x = 0)
"""
import math
import random

from civic_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'builder_camp'
W, H = 5, 5
ENTRANCE = ('s', 2)                 # the south edge, x = 0
HEADROOM = 0.9

HX0, HX1, HY0, HY1 = -2.25, -0.85, 0.85, 2.2        # the foreman's hut
HEAVE = G + 0.78
HDOOR = -1.55
FX0, FX1, FY0, FY1 = 0.55, 2.2, 0.9, 2.2            # the house frame
FEAVE = G + 0.8
FPITCH = 48.0


def house_frame(M):
    t = 0.05
    xm, ym = (FX0 + FX1) / 2, (FY0 + FY1) / 2
    box(xm, ym, G, FX1 - FX0 + 0.06, FY1 - FY0 + 0.06, DIM['plinth'], M['stone_dk'], bevel=0.01)
    zp = G + DIM['plinth']
    xs = [FX0 + (FX1 - FX0) * k / 4 for k in range(5)]
    ys = [FY0, FY0 + (FY1 - FY0) / 2, FY1]
    for x in xs:                                   # posts, front and back rows
        for y in (FY0, FY1):
            beam((x, y, zp), (x, y, FEAVE), t, M['timber'])
    for y in ys[1:2]:
        for x in (FX0, FX1):
            beam((x, y, zp), (x, y, FEAVE), t, M['timber'])
    for y in (FY0, FY1):                           # sill and plate
        beam((FX0, y, zp + 0.02), (FX1, y, zp + 0.02), t, M['timber'])
        beam((FX0, y, FEAVE), (FX1, y, FEAVE), t, M['timber'])
    for x in (FX0, FX1):
        beam((x, FY0, zp + 0.02), (x, FY1, zp + 0.02), t, M['timber'])
        beam((x, FY0, FEAVE), (x, FY1, FEAVE), t, M['timber'])
    for k in range(4):                             # diagonal braces on the front
        beam((xs[k], FY0, zp + 0.04), (xs[k + 1], FY0, FEAVE - 0.04), 0.035, M['timber']) \
            if k % 2 == 0 else None
    # the west gable is already filled
    F.gable_wall(M, 'w', FX0, FY0, FY1, FEAVE, pitch=FPITCH)
    rise = (FY1 - FY0) / 2 * math.tan(math.radians(FPITCH))
    apex = FEAVE + rise
    # rafters over the open east part, ridge and laths on the south slope
    beam((FX0, ym, apex - 0.04), (FX1 + 0.1, ym, apex - 0.04), 0.05, M['timber'])
    for x in xs[1:]:
        for y in (FY0, FY1):
            beam((x, y, FEAVE), (x, ym, apex - 0.04), 0.04, M['timber'])
    for f in (0.3, 0.55, 0.8):
        y = FY0 + (ym - FY0) * f
        beam((FX0, y, FEAVE + rise * f - 0.0), (FX1, y, FEAVE + rise * f - 0.0), 0.022, M['planks'])
    # first tile courses at the eave, west half
    for k in range(3):
        y = FY0 - 0.03 + k * 0.1
        z = FEAVE + 0.05 + (k * 0.1) * math.tan(math.radians(FPITCH))
        rbox((FX0 + 0.45, y, z), (0.95, 0.1, 0.03), (math.radians(FPITCH), 0, 0), M['roof'],
             bevel=0.004)
    # a scaffold in front
    for x in (FX0 + 0.1, FX0 + 0.85, FX0 + 1.6):
        beam((x, FY0 - 0.18, G), (x, FY0 - 0.18, G + 0.95), 0.03, M['timber'])
    for z in (G + 0.38, G + 0.76):
        beam((FX0 + 0.1, FY0 - 0.18, z), (FX0 + 1.6, FY0 - 0.18, z), 0.026, M['timber'])
        rbox((FX0 + 0.85, FY0 - 0.1, z + 0.02), (1.55, 0.16, 0.025), (0, 0, 0), M['planks'],
             bevel=0.003)
    ladder(M, (FX0 + 1.7, FY0 - 0.4, G), (FX0 + 1.6, FY0 - 0.2, G + 0.78), w=0.1)
    # the site pennant
    beam((FX1, FY1, FEAVE), (FX1, FY1, apex + 0.2), 0.014, M['timber'], bevel=0)
    with F.anim('sitepennant', 'sway', pivot=(FX1, FY1, apex + 0.15), amp=0.5, period=1.7):
        rbox((FX1 + 0.07, FY1, apex + 0.15), (0.14, 0.012, 0.08), (0, 0, 0), M['red'], bevel=0)


def mortar_tub(M, x, y):
    cyl(x, y, G, 0.09, 0.11, 0.09, M['planks'], seg=14)
    cyl(x, y, G + 0.085, 0.095, 0.095, 0.012, M['rock_cut'], seg=14)
    beam((x - 0.04, y + 0.03, G + 0.1), (x + 0.1, y - 0.05, G + 0.2), 0.012, M['timber'])


def build():
    random.seed(9)
    M = mats()
    hall(M, HX0, HX1, HY0, HY1, HEAVE, 'x', 'roof',
         doors=[('s', HDOOR, DIM['door'][0], DIM['door'][1])],
         wins=[('s', -2.0, 'teal', True), ('e', 1.5, 'red', False), ('w', 1.5, 'teal', True),
               ('n', -1.5, 'red', False)])
    F.chimney(M, -2.0, 1.95, HEAVE + 0.3, 0.45)
    F.hanging_sign(M, 's', HY0, HDOOR + 0.4, HEAVE - 0.02, emblem(M, 's', 'hammer'),
                   size=F.m(2.0))
    house_frame(M)

    # ── the crane ─────────────────────────────────────────
    treadwheel_crane(M, 0.15, 0.1, 1.2, (1.0, 0.8), 0.9, 0.42)

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(HDOOR, HY0 - 0.1), (HDOOR, 0.5), (-0.9, -0.1), (-0.3, -0.9), (0.0, -1.7),
                      (ex, ey + 0.02)], seed=8)
    dirt(M, 0.2, -0.5, 2.0, 1.5, 4)
    block_stack(M, -1.9, 0.0, 3, 2, 2, seed=2)
    stone_block(M, -1.5, -0.4, s=(0.17, 0.13, 0.1), rot=0.4)
    stone_block(M, -2.1, -0.5, s=(0.15, 0.12, 0.1), rot=-0.3)
    mortar_tub(M, -1.35, 0.35)
    board_stack(M, 1.6, -0.75, 0.7, 0.22, 0.24, 0.2)
    board_stack(M, 1.9, -1.1, 0.6, 0.2, 0.18, 0.0)
    log_stack(M, 1.55, -1.7, 0.8, 3, 0.055, 'x')
    sawhorse(M, 0.95, -0.5, 0.6)
    wheelbarrow(M, -0.75, -1.1, 0.5, 'rock')
    F.barrel(M, 2.1, 0.25, r=0.07, h=0.17)
    F.crate(M, 2.15, -0.15, 0.12, rot=0.2)
    F.crate(M, 1.0, 0.5, 0.12)
    sack(M, 0.8, 0.62)
    tripod(M, -0.2, -1.8, 0.7)
    for x, y, h, k in ((-2.35, 2.4, 1.4, 'pine2'), (2.35, 2.45, 1.35, 'pine'),
                       (-2.35, -2.2, 1.1, 'pine'), (2.4, -2.3, 1.0, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, -0.55, 0.62, 0.11, 3, ['fl_white'])
    F.flower_patch(M, 0.9, -2.2, 5, ['fl_yel', 'fl_red'], 5)
    F.flower_patch(M, -1.2, -2.0, 5, ['fl_white', 'fl_pink'], 6)
