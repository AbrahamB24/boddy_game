"""The Scout Post: a timber watchtower with a signal fire, tier D (2 x 2 tiles).

Reads as: someone watches the land from up here. A tall two-storey half-timbered
tower, its upper room jettied out over the lower one under a shingle roof, a
red pennant on the ridge; beside it a mast with a ladder and an iron fire basket
that is lit at night; a stack of fuel logs at its foot.

Moving parts: the pennant flutters; plants sway; the fire basket, the upper
windows and the lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    tower centred a little north of the middle, door in the south wall
    signal mast east of it, wood stack and barrel in front of it
              cobbled path from the door to the south cell (x = +0.5)
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'scout_post'
W, H = 2, 2
ENTRANCE = ('s', 1)                 # the south edge, x = +0.5
HEADROOM = 1.0

CX, CY = -0.16, 0.12
LO = 0.36                           # half width of the ground floor
UP = 0.42                           # half width of the jettied upper room
Z1 = G + 0.78                       # top of the ground floor
EAVE = G + 1.42
BX, BY = 0.66, 0.42                 # the signal mast
BTOP = G + 1.72
CHIMNEY = (BX, BY, BTOP + 0.2)


def storey(M, hw, z0, z1, wins, door=None, glow=False):
    """One square storey of plaster with its frame; wins = [(face, a, shut, glow)]."""
    box(CX, CY, z0, 2 * hw, 2 * hw, z1 - z0, M['plaster'], bevel=0.008)
    faces = {'s': (CY - hw, CX - hw, CX + hw), 'n': (CY + hw, CX - hw, CX + hw),
             'e': (CX + hw, CY - hw, CY + hw), 'w': (CX - hw, CY - hw, CY + hw)}
    holes = {f: [] for f in faces}
    if door:
        holes[door[0]].append((door[1], DIM['door'][0]))
    for f, a, *_ in wins:
        holes[f].append((a, DIM['window_up'][0] if z0 > Z1 - 0.01 else DIM['window'][0]))
    for f, (fx, a0, a1) in faces.items():
        F.wall_frame(M, f, fx, a0, a1, z0, z1, 3, braces=(0, 2), holes=holes[f])
    return faces


def build():
    M = mats()
    # ── the ground floor ──────────────────────────────────
    box(CX, CY, G, 2 * LO + 0.06, 2 * LO + 0.06, DIM['plinth'], M['stone_dk'], bevel=0.01)
    zpl = G + DIM['plinth']
    faces = storey(M, LO, zpl, Z1, [('e', CY, 'teal', False), ('w', CY, 'red', False),
                                    ('n', CX, 'teal', True)], door=('s', CX))
    F.door(M, 's', faces['s'][0], CX, *DIM['door'], zpl)
    F.lantern(M, 's', faces['s'][0], CX + 0.16, zpl + DIM['door'][1] - 0.02)
    for f, a, shut, gl in (('e', CY, 'teal', False), ('w', CY, 'red', False), ('n', CX, 'teal', True)):
        F.window(M, f, faces[f][0], a, zpl + 0.28, *DIM['window'], shut, gl)

    # ── the jettied watch room ────────────────────────────
    rbox((CX, CY, Z1 - 0.025), (2 * UP + 0.06, 2 * UP + 0.06, 0.05), (0, 0, 0), M['timber'],
         bevel=0.004)
    for sx in (-1, 1):                               # brackets under the overhang
        for sy in (-1, 1):
            beam((CX + sx * LO, CY + sy * (UP - 0.02), Z1 - 0.2),
                 (CX + sx * (UP - 0.02), CY + sy * (UP - 0.02), Z1 - 0.03), 0.03, M['timber'])
    wins_up = [('s', CX, 'red', True), ('e', CY, 'teal', True), ('w', CY, 'teal', False),
               ('n', CX, 'red', True)]
    fu = storey(M, UP, Z1, EAVE, wins_up)
    for f, a, shut, gl in wins_up:
        F.window(M, f, fu[f][0], a, Z1 + 0.36, *DIM['window_up'], shut, gl)
    # gables to the south and north, ridge along y
    F.gable_wall(M, 's', CY - UP, CX - UP, CX + UP, EAVE)
    F.gable_wall(M, 'n', CY + UP, CX - UP, CX + UP, EAVE)
    zr = F.gable_roof(M, CX, CY, EAVE, 2 * UP, 2 * UP, 'y', M['shingle'], oh=0.09, oe=0.1)
    # pennant on the ridge
    beam((CX, CY, zr - 0.04), (CX, CY, zr + 0.26), 0.014, M['timber'], bevel=0)
    with F.anim('pennant', 'sway', pivot=(CX, CY, zr + 0.2), amp=0.5, period=1.6):
        rbox((CX + 0.07, CY, zr + 0.2), (0.14, 0.012, 0.07), (0, 0, 0), M['red'], bevel=0)
        rbox((CX + 0.17, CY, zr + 0.2), (0.07, 0.012, 0.04), (0, 0, 0), M['red'], bevel=0)

    # ── the signal mast ───────────────────────────────────
    for sx in (-1, 1):
        beam((BX + sx * 0.06, BY, G), (BX + sx * 0.04, BY, BTOP), 0.03, M['timber'])
    for z in (G + 0.5, G + 1.0):
        beam((BX - 0.06, BY, z), (BX + 0.06, BY, z), 0.022, M['timber'])
    ladder(M, (BX - 0.1, BY - 0.07, G), (BX - 0.1, BY - 0.07, BTOP - 0.12), w=0.1)
    cyl(BX, BY, BTOP, 0.07, 0.11, 0.1, M['iron'], seg=12)       # the fire basket
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        beam((BX + 0.11 * math.cos(a), BY + 0.11 * math.sin(a), BTOP + 0.1),
             (BX + 0.06 * math.cos(a), BY + 0.06 * math.sin(a), BTOP - 0.02), 0.012,
             M['iron'], bevel=0)
    ellipsoid(BX, BY, BTOP + 0.12, 0.075, 0.075, 0.14, M['fire'], seg=10, rings=8, egg=0.4)
    ellipsoid(BX, BY, BTOP + 0.08, 0.1, 0.1, 0.05, M['ember'], seg=10, rings=6)

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(CX, CY - LO - 0.1), (CX, -0.72), (0.3, -0.9), (ex, ey + 0.02)], seed=3)
    dirt(M, 0.35, -0.42, 0.7, 0.5, 3)
    log_stack(M, 0.42, 0.78, 0.4, 3, 0.05, 'x')                  # fuel for the fire
    F.barrel(M, BX + 0.05, BY - 0.3, r=0.07, h=0.17)
    F.crate(M, 0.72, -0.18, 0.12, rot=0.3)
    stump(M, -0.78, -0.4, axe=True)
    # a low fence closing the yard on the west
    for k in range(5):
        y = -0.7 + k * 0.17
        beam((-0.93, y, G), (-0.93, y, G + 0.17), 0.018, M['timber'])
    beam((-0.93, -0.7, G + 0.13), (-0.93, -0.02, G + 0.13), 0.014, M['timber'])
    beam((-0.93, -0.7, G + 0.06), (-0.93, -0.02, G + 0.06), 0.014, M['timber'])
    fir(M, -0.8, 0.85, 1.25, 'pine')
    fir(M, 0.85, 0.8, 1.0, 'pine2')
    F.bush(M, -0.62, -0.62, 0.1, 3, ['fl_white'])
    F.flower_patch(M, 0.55, -0.62, 4, ['fl_red', 'fl_yel'], 5)
