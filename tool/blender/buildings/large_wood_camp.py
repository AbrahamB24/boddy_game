"""The Large Wood Camp: a timber yard with a treadwheel crane, tier B (4 x 4).

Chosen from the twenty camp mockups (camp_mockups.py, concept 3, user
2026-11-03: "grosses Sägewerk: 3").

Reads as: wood is stored and moved here, in bulk. Tall open racks of dried
boards under a long roof along the back, a crane with a treadwheel hoisting a
log, two big stacks of round logs, board stacks and a sawhorse in the yard, a
small office hut with a tree on its sign and a smoking chimney.

Moving parts: the hoisted log rides up and down on its rope; plants sway, the
windows and the lantern glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    board racks under a long roof (back)          crane + hoisted log
              log stacks            sawhorse / board stacks
    office hut (door south)    cobbled path to the south cell
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'large_wood_camp'
W, H = 4, 4
ENTRANCE = ('s', 1)                 # south edge, x = -0.5
HEADROOM = 0.6

# the office hut
HX0, HX1, HY0, HY1 = -1.85, -0.70, -1.75, -0.65
EAVE = G + 0.76
CHX, CHY, CHZ0, CHH = -1.55, -1.05, G + 1.00, 0.50
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)


def racks(M, xs, y0, y1, h):
    """Open racks: posts, three shelves, boards lying on them."""
    for x in xs:
        for y in (y0, y1):
            beam((x, y, G), (x, y, G + h), 0.05, M['timber'])
        for z in (h * 0.32, h * 0.65, h):
            beam((x, y0, G + z), (x, y1, G + z), 0.04, M['timber'])
    for i in range(len(xs) - 1):
        for z in (0.0, 0.32 * h, 0.65 * h):
            rbox(((xs[i] + xs[i + 1]) / 2, (y0 + y1) / 2, G + z + 0.12),
                 (xs[i + 1] - xs[i] - 0.08, y1 - y0 - 0.06, 0.2), (0, 0, 0), M['planks'],
                 bevel=0.004)
            for f in (-0.3, 0.3):
                rbox(((xs[i] + xs[i + 1]) / 2, (y0 + y1) / 2 + f * (y1 - y0), G + z + 0.225),
                     (xs[i + 1] - xs[i] - 0.1, 0.02, 0.02), (0, 0, 0), M['timber'], bevel=0)


def build():
    M = mats()
    # ── the racks and the crane (back and right) ──────────
    xs = (-1.60, -0.90, -0.20, 0.50)
    racks(M, xs, 1.00, 1.70, 0.95)
    lean_to(M, -1.70, 0.60, 0.95, 1.75, G + 1.22, G + 1.05, 's', 'shingle', posts=False)
    treadwheel_crane(M, 1.10, 0.55, 1.45, (-0.3, -1.0), 0.78, 0.62, load='log')
    log_stack(M, 1.30, -0.75, 1.10, 4, 0.065, 'y')
    log_stack(M, 0.25, -0.30, 1.00, 3, 0.06, 'x')
    for i in range(3):
        rbox((0.55 + i * 0.14, 0.05, G + 0.03), (0.06, 0.5, 0.06), (0, 0, 0), M['timber'])
    board_stack(M, -0.35, -1.20, 0.90, 0.30, 0.26, 0.0)
    board_stack(M, 0.65, -1.40, 0.70, 0.26, 0.18, 1.57)
    sawhorse(M, 1.65, -1.35, 0.4)
    stump(M, 0.05, -0.85, axe=True)
    for i in range(7):                      # bark and chips around the stacks
        a = i * 0.95
        ellipsoid(0.8 + math.cos(a) * 0.5, -0.5 + math.sin(a) * 0.35, G + 0.012,
                  0.05, 0.035, 0.015, M['log_end'], seg=8, rings=4)

    # ── the office ────────────────────────────────────────
    hut(M, HX0, HX1, HY0, HY1, EAVE, 'x', door=('s', -0.95),
        wins=[('s', -1.55, 'red', True), ('w', -1.20, 'teal', False),
              ('n', -1.20, 'teal', True), ('e', -0.90, 'red', False)],
        sign=('e', -1.72, 'tree', F.m(2.0)))
    F.chimney(M, CHX, CHY, CHZ0, CHH)
    F.barrel(M, -0.50, -1.42, r=0.07, h=0.17)
    F.crate(M, -0.50, -1.22, 0.12)

    # ── paths and edges ───────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(-0.95, HY0 - 0.12), (ex, ey + 0.30), (ex, ey + 0.02)], seed=8)
    dirt(M, 0.35, -0.35, 1.45, 1.25, 8)
    for x, y, h, k in ((1.78, 1.78, 1.45, 'pine'), (-1.85, 0.35, 1.35, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, -0.40, -0.65, 0.13, 4, ['fl_yel'])
    F.flower_patch(M, -1.30, -1.92, 5, ['fl_red', 'fl_white'], 9)
