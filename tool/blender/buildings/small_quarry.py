"""The Small Quarry: a hillside cut with a plank chute, tier C (3 x 3 tiles).

Chosen from the twenty camp mockups (camp_mockups.py, concept 4, user
2026-11-03: "klein Stein: 4, inkl. Schubkarre"). The footprint shrinks from
5 x 4 to 3 x 3, which puts the stone pair back in the ladder small < large.

Reads as: stone is broken here. A rock face cut into a clean light bench, a
ladder up it, a plank chute carrying broken stones down into a slatted bin,
dressed blocks stacked at the foot, a wheelbarrow of rubble, a pick on a sign
post and a tool shed. No chimney: nobody lives here.

Moving parts: plants sway, the shed's window and lantern glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    rock face (back, left)         trees
    ladder   bench   chute -> bin   wheelbarrow, block stack
    tool shed (left front)   cobbled path to the south cell
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'small_quarry'
W, H = 3, 3
ENTRANCE = ('s', 1)                 # south edge, x = 0
HEADROOM = 0.6


def chute(M, top, bot):
    """Two rails, a plank trough, trestle legs and three stones sliding down."""
    top, bot = Vector(top), Vector(bot)
    d = (bot - top)
    side = Vector((-d.y, d.x, 0)).normalized() * 0.075
    for s in (-1, 1):
        beam(top + side * s, bot + side * s, 0.03, M['timber'])
    rbox((top + bot) / 2, (d.length, 0.17, 0.025),
         Vector((1, 0, 0)).rotation_difference(d.normalized()).to_euler(), M['planks'])
    for f in (0.3, 0.55, 0.8):
        p = top.lerp(bot, f)
        beam((p.x, p.y, G), (p.x, p.y, p.z - 0.02), 0.04, M['timber'])
    for f in (0.18, 0.42, 0.66):
        p = top.lerp(bot, f)
        stone_block(M, p.x, p.y, p.z + 0.02, (0.11, 0.1, 0.09), 0.6, 'rock')


def bin_(M, x, y):
    """A slatted gravel bin the chute empties into."""
    for g in (-1, 1):
        rbox((x + g * 0.22, y, G + 0.15), (0.04, 0.44, 0.30), (0, 0, 0), M['planks'])
    rbox((x, y - 0.21, G + 0.15), (0.48, 0.04, 0.30), (0, 0, 0), M['planks'])
    for xx in (x - 0.22, x + 0.22):
        beam((xx, y - 0.21, G), (xx, y - 0.21, G + 0.34), 0.05, M['timber'])
    ellipsoid(x, y, G + 0.2, 0.2, 0.18, 0.13, M['gravel'], seg=12, rings=8)


def build():
    M = mats()
    # ── the rock face and its cut bench ───────────────────
    rock_mass(M, -0.62, 0.58, 1.85, 1.75, 1.2, seed=5, n=30)
    cut_step(M, -1.05, 0.05, -0.42, 0.10, G, G + 0.5, top='gravel')
    ladder(M, (-1.12, -0.25, G + 0.02), (-1.12, 0.12, G + 1.0))
    # a loading platform on the face, the chute runs east from it down to the bin
    box(0.02, 0.45, G + 0.93, 0.3, 0.3, 0.04, M['planks'])
    for y in (0.31, 0.59):
        beam((0.12, y, G), (0.12, y, G + 0.93), 0.04, M['timber'])
    chute(M, (0.05, 0.45, G + 1.0), (0.98, 0.45, G + 0.32))
    bin_(M, 1.17, 0.45)

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    dirt(M, 0.35, -0.50, 1.0, 0.85, 14, 'gravel')
    hut(M, -1.40, -0.90, -1.40, -0.75, G + 0.56, 'x', door=('e', -1.07), roof='roof2',
        wins=[('s', -1.15, 'teal', True)])
    F.cobble_path(M, [(-0.80, -1.07), (0.0, -1.15), (0.0, ey + 0.02)], seed=14)
    wheelbarrow(M, 0.98, -0.55, 0.9, 'rock', s=1.6)
    block_stack(M, 0.42, -0.42, 3, 2, 2, seed=2)
    stone_block(M, -0.3, -0.62, s=(0.18, 0.13, 0.11), rot=0.2)
    signpost(M, 0.62, -1.22, 's', 'pick', h=0.42, size=0.34)
    F.barrel(M, -0.72, -0.62, r=0.065, h=0.16)
    for x, y, h, k in ((1.30, 1.28, 1.35, 'pine'),):
        fir(M, x, y, h, k)
    F.bush(M, -1.30, -0.15, 0.14, 2, ['fl_yel'])
    F.flower_patch(M, 1.2, -1.3, 5, ['fl_white', 'fl_blue'], 3)
