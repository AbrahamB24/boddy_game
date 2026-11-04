"""The Large Stone Camp: a stone-sawing quarry with an ox wagon and a crane,
tier B (5 x 4 tiles).

Chosen from the twenty camp mockups (camp_mockups.py, concept 4, user
2026-11-03: "gross Stein: 4, inkl. Ochsenwagen und Kran"). The footprint grows
from 4 x 4 to 5 x 4, so the large camp is again bigger than the small one.

Reads as: stone is cut, dressed and carried away. A big rock face with a cut
bench, a water wheel on a flume driving a frame saw that cuts a block into
slabs under an open shed, slabs stacked on edge, a post crane lowering a block
onto an ox wagon, the ox waiting in its yoke, a pile of finished blocks and a
mason's hut with a block on its sign.

Moving parts: the crane's block rides up and down on its rope, the ox shifts
its weight, the saw frame bobs; plants sway, the hut's windows and lantern
glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    rock face + bench (back left)     saw shed        flume + water wheel
    slabs                crane + wagon + ox    block stack
    mason's hut (front left)   path to the south edge
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'large_stone_camp'
W, H = 5, 4
ENTRANCE = ('s', 1)                 # south edge, x = -1.0
HEADROOM = 0.55


def ox(M, x, y, rot=0.0, s=1.0):
    """A standing ox: body, head with horns, four legs, a tail. It faces
    along `rot` (0 = +x). Built as one swaying layer (it shifts its weight)."""
    c, sn = math.cos(rot), math.sin(rot)

    def at(f, side=0.0, z=0.0):
        return (x + (f * c - side * sn) * s, y + (f * sn + side * c) * s, G + z * s)
    with anim('ox', 'sway', pivot=(x, y, G), amp=0.12, period=3.6):
        p = at(0, 0, 0.17)
        ellipsoid(*p, 0.17 * s, 0.085 * s, 0.085 * s, M['ox'], seg=14, rings=10,
                  tilt=(0, 0, rot))
        p = at(0.19, 0, 0.2)
        ellipsoid(*p, 0.065 * s, 0.055 * s, 0.06 * s, M['ox'], seg=10, rings=8,
                  tilt=(0, 0, rot))
        p = at(0.15, 0, 0.26)                            # the hump
        ellipsoid(*p, 0.06 * s, 0.06 * s, 0.045 * s, M['ox'], seg=10, rings=8)
        for g in (-1, 1):
            a, b = at(0.215, g * 0.05, 0.25), at(0.215, g * 0.09, 0.31)
            beam(a, b, 0.018 * s, M['linen'], bevel=0)
            for f in (-0.1, 0.11):
                beam(at(f, g * 0.05, 0.12), at(f, g * 0.05, 0.0), 0.03 * s, M['ox'], bevel=0.002)
        beam(at(-0.16, 0, 0.2), at(-0.2, 0, 0.1), 0.014 * s, M['ox'], bevel=0)


def ox_wagon(M, x, y, rot, load=True):
    """A two-wheeled wagon (axle across `rot`) with a stone block on its bed;
    `rot` is the direction its pole points."""
    c, sn = math.cos(rot), math.sin(rot)

    def at(f, side=0.0, z=0.0):
        return (x + f * c - side * sn, y + f * sn + side * c, G + z)
    rbox(at(0, 0, 0.2), (0.62, 0.34, 0.04), (0, 0, rot), M['planks'], bevel=0.005)
    for g in (-1, 1):
        rbox(at(0, g * 0.17, 0.25), (0.62, 0.02, 0.07), (0, 0, rot), M['planks'], bevel=0.004)
    rbox(at(-0.31, 0, 0.25), (0.02, 0.34, 0.07), (0, 0, rot), M['planks'], bevel=0.004)
    for g in (-1, 1):                                   # big wheels on a heavy axle
        wc = at(-0.06, g * 0.2, 0.14)
        ax = (-sn, c, 0)
        disc(M, wc, ax, 0.14, 0.035, 'timber')
        disc(M, wc, ax, 0.145, 0.012, 'iron')
        disc(M, wc, ax, 0.035, 0.05, 'iron')
    beam(at(-0.06, -0.2, 0.14), at(-0.06, 0.2, 0.14), 0.04, M['timber'])
    beam(at(0.3, 0, 0.18), at(0.62, 0, 0.17), 0.035, M['timber'])      # the pole
    if load:
        rbox(at(-0.03, 0, 0.3), (0.3, 0.2, 0.15), (0, 0, rot + 0.1), M['rock_cut'], bevel=0.01)


def mason_hut(M):
    hut(M, -2.35, -1.55, -1.80, -0.95, G + 0.72, 'x', door=('s', -1.95),
        wins=[('w', -1.38, 'red', True), ('n', -1.95, 'teal', True), ('s', -1.72, 'teal', False)],
        sign=('e', -1.78, 'block', F.m(2.0)))


def frame_saw(M, x, y):
    """The saw frame in its sash over a block on the bed: its blades bob."""
    stone_block(M, x, y, None, (0.5, 0.36, 0.28))
    for g in (-1, 1):
        beam((x, y + g * 0.24, G), (x, y + g * 0.24, G + 0.78), 0.045, M['timber'])
    beam((x, y - 0.26, G + 0.78), (x, y + 0.26, G + 0.78), 0.045, M['timber'])
    with anim('sawframe', 'bob', pivot=(x, y, G + 0.4), amp=0.03, period=1.1):
        beam((x, y - 0.2, G + 0.58), (x, y + 0.2, G + 0.58), 0.04, M['timber'])
        beam((x, y - 0.2, G + 0.3), (x, y + 0.2, G + 0.3), 0.04, M['timber'])
        for k in range(3):
            rbox((x - 0.12 + k * 0.12, y, G + 0.44), (0.014, 0.4, 0.3), (0, 0, 0), M['iron'],
                 bevel=0)


def build():
    M = mats()
    # ── the rock face, bench and the water power ──────────
    rock_mass(M, -1.35, 1.2, 2.3, 1.7, 1.4, seed=11, n=30)
    cut_step(M, -2.25, -0.35, 0.25, 0.80, G, G + 0.5)
    ladder(M, (-2.35, 0.45, G), (-2.35, 0.75, G + 0.5))
    water_channel(M, 2.0, 2.45, -2.0, 2.0)
    wheel(M, (2.22, 0.55, G + 0.45), 0.45, 'x', n=14, width=0.18, paddles=True)
    beam((2.22, 0.55, G + 0.45), (0.9, 0.55, G + 0.45), 0.05, M['iron'])      # the shaft

    # ── the saw shed ──────────────────────────────────────
    lean_to(M, 0.2, 1.75, 0.0, 1.15, G + 0.92, G + 0.72, 'w', 'roof2')
    frame_saw(M, 1.0, 0.58)
    for i in range(5):                                  # slabs coming off the saw
        rbox((0.52 + i * 0.06, 1.05, G + 0.15), (0.025, 0.28, 0.3), (0, 0.15, 0), M['rock_cut'])

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    dirt(M, 0.2, -0.85, 2.0, 1.05, 19, 'gravel')
    for i in range(6):                                  # slabs stacked on edge
        rbox((-0.95 + i * 0.07, -0.25, G + 0.17), (0.025, 0.4, 0.34), (0, 0.18, 0), M['rock_cut'])
    beam((-1.05, -0.25, G + 0.04), (-0.45, -0.25, G + 0.04), 0.05, M['timber'])
    for i in range(4):
        rbox((-1.8 + i * 0.07, -0.3, G + 0.15), (0.025, 0.3, 0.3), (0, 0.2, 0), M['rock_cut'])
    ox_wagon(M, 0.25, -1.25, math.pi)
    ox(M, -0.95, -1.25, math.pi, 1.3)
    beam((-0.37, -1.25, G + 0.18), (-0.90, -1.37, G + 0.26), 0.035, M['timber'])  # the traces
    crane(M, 0.82, -0.55, 1.3, (0.4, -1.05), 0.58)
    block_stack(M, 1.55, -1.0, 3, 2, 2, (0.22, 0.16, 0.14), seed=9)
    mason_hut(M)
    F.cobble_path(M, [(-1.95, HY_DOOR), (ex, ey + 0.02)], seed=19)
    F.barrel(M, -1.33, -1.55, r=0.07, h=0.17)
    F.crate(M, -2.0, -0.62, 0.12)
    for x, y, h, k in ((2.30, 1.65, 1.45, 'pine'), (0.1, 1.85, 1.2, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, -2.35, -0.40, 0.13, 3, ['fl_yel'])
    F.flower_patch(M, 2.0, -1.7, 5, ['fl_white', 'fl_blue'], 4)


HY_DOOR = -1.92                          # just in front of the hut's south door
