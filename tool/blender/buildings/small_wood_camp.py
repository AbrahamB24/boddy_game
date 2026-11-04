"""The Small Wood Camp: a woodsman's hut with a pit saw, tier C (3 x 3 tiles).

Chosen from the twenty camp mockups (camp_mockups.py, concept 2, user
2026-11-03: "2, aber Zweimannsäge anstatt Holzmieten und dafür noch
Bretterstapel").

Reads as: wood is cut here. A half-timbered hut with an axe on its sign and a
smoking chimney; in front of it a log lies on a trestle with a two-man pit saw
standing in the cut; sawn boards are stacked to dry beside it, split billets
sit in an open shed, an axe stands in a stump.

Moving parts: the saw rides up and down in its kerf; plants sway, the windows
and the lantern glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    hut (ridge along y, gable south)     open billet shed
    stump + sawhorse   pit saw on trestle     board stacks
                 cobbled path from the door down to the south cell
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'small_wood_camp'
W, H = 3, 3
ENTRANCE = ('s', 1)                 # the south edge's middle cell, x = 0

# the hut, authoring coordinates
HX0, HX1, HY0, HY1 = -1.40, -0.40, -0.10, 1.30
EAVE = G + 0.74
CHX, CHY, CHZ0, CHH = -0.64, 0.95, G + 1.02, 0.50
HEADROOM = 0.6
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)


def pit_saw(M, x0, x1, y, h=0.46):
    """A log on a trestle with a two-man saw in it."""
    xm = (x0 + x1) / 2
    for x in (x0 + 0.06, x1 - 0.06):
        for g in (-1, 1):
            beam((x, y + g * 0.18, G), (x, y + g * 0.05, G + h), 0.04, M['timber'])
        beam((x, y - 0.07, G + h), (x, y + 0.07, G + h), 0.05, M['timber'])
        beam((x, y - 0.14, G + 0.17), (x, y + 0.14, G + 0.17), 0.03, M['timber'])
    r = 0.07
    log(M, (x0, y, G + h + r), (x1, y, G + h + r), r)
    # the saw: a long blade standing in the cut, a handle at each end
    with anim('pitsaw', 'bob', pivot=(xm, y, G + h + r), amp=0.05, period=1.3):
        rbox((xm, y, G + h + r), (0.12, 0.022, 0.62), (0, 0, 0), M['iron'], bevel=0)
        beam((xm, y - 0.07, G + h + r + 0.3), (xm, y + 0.07, G + h + r + 0.3), 0.04,
             M['timber'])
        beam((xm, y - 0.07, G + h + r - 0.3), (xm, y + 0.07, G + h + r - 0.3), 0.04,
             M['timber'])
    # sawdust on the ground, the first planks leaned on the trestle
    for i in range(5):
        a = i * 1.3
        ellipsoid(xm + math.cos(a) * 0.12, y + math.sin(a) * 0.1 - 0.02, G + 0.012,
                  0.05, 0.035, 0.015, M['log_end'], seg=8, rings=4)
    for k in range(3):
        rbox((x1 + 0.1 + k * 0.03, y + 0.08, G + 0.22), (0.02, 0.2, 0.44),
             (0, 0.2, 0.0), M['planks'], bevel=0.003)


def build():
    M = mats()
    # ── the hut ───────────────────────────────────────────
    hut(M, HX0, HX1, HY0, HY1, EAVE, 'y', door=('e', 0.20),
        wins=[('e', 0.72, 'mustard', True), ('w', 0.30, 'teal', False),
              ('w', 0.90, 'red', True), ('n', -0.90, 'teal', False)],
        sign=('s', -1.33, 'axe', F.m(2.0)))
    F.chimney(M, CHX, CHY, CHZ0, CHH)

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(HX1 + 0.12, 0.20), (0.02, 0.08), (0.0, ey + 0.02)], seed=4)
    dirt(M, 0.55, -0.45, 0.85, 0.7, 2)
    pit_saw(M, 0.25, 1.30, -0.55)
    board_stack(M, 1.15, 0.22, 0.72, 0.24, 0.30, 1.57)
    board_stack(M, 0.55, 0.36, 0.52, 0.22, 0.20, 0.0)
    # the open billet shed, back to the north
    lean_to(M, 0.20, 1.30, 0.92, 1.45, G + 0.62, G + 0.44, 's', 'roof2')
    billets(M, 0.75, 1.28, 0.95, 0.36, 0.14)
    stump(M, -0.30, -0.80, axe=True)
    sawhorse(M, -0.85, -0.65, 0.3)
    F.barrel(M, -0.28, 0.80, r=0.07, h=0.17)
    signpost(M, 1.30, -0.15, 'e', 'axe', h=0.34, size=0.26)

    for x, y, h, k in ((-1.32, -1.22, 1.35, 'pine'), (-1.32, 1.38, 1.4, 'pine2'),
                       (1.38, -1.35, 0.95, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, -1.30, -0.50, 0.17, 3, ['fl_white'])
    F.bush(M, -0.20, 0.58, 0.11, 6, ['fl_yel'])
    F.flower_patch(M, 0.30, -1.05, 5, ['fl_white', 'fl_pink'], 7)
