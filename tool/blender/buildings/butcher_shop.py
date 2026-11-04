"""The Butcher's: a shop with a gallery of hanging hams, tier C (3 x 3 tiles).

Chosen from the mockups (user 2026-11-04: "Metzger: 1, mit einem Geweih über
dem Eingang").

Reads as: meat is sold here. A half-timbered shop with a cleaver on its sign
and a pair of antlers over the door; in front a timber gallery with hams and
sausages hanging from its beam; a chopping block with the cleaver in it, a
handcart, and barrels of brine; a smoking chimney.

Moving parts: the hams and sausages sway on the gallery; plants sway; the
windows and the lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    shop (ridge along x, door south)        chimney at the back
    gallery of hams in front of it          cobbled path from the door to the south cell
    block, cart, barrels to the east
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F

ID = 'butcher_shop'
W, H = 3, 3
ENTRANCE = ('s', 1)                 # the south edge's middle cell, x = 0
HEADROOM = 0.6

HX0, HX1, HY0, HY1 = -1.30, 0.50, 0.00, 1.00
EAVE = G + 0.78
DOOR_A = -0.35
CHX, CHY, CHZ0, CHH = -0.95, 0.72, EAVE + 0.22, 0.52
CHIMNEY = (CHX, CHY, CHZ0 + CHH + 0.13)
GAL_Y = -0.52                       # the gallery's front beam
GAL_Z = G + 0.50


def antlers(M, face, fixed, a, z, span=1.0, rise=1.0):
    """A skull plate on the wall with a pair of antlers branching up from it."""
    s0 = span
    c = P(face, fixed, a, z, 0.035)
    rbox(c, D(face, 0.06 * s0, 0.05, 0.05 * s0), (0, 0, 0), M['antler'], bevel=0.004)
    t = 0.026
    for sg in (-1, 1):
        def q(da, dz, off=0.04):
            return P(face, fixed, a + sg * da * s0, z + dz * rise, off)
        beam(q(0.03, 0.02), q(0.12, 0.10), t, M['antler'], bevel=0.002)
        beam(q(0.12, 0.10), q(0.16, 0.22), t * 0.9, M['antler'], bevel=0.002)
        beam(q(0.09, 0.075, 0.045), q(0.05, 0.17, 0.045), t * 0.75, M['antler'], bevel=0.002)
        beam(q(0.135, 0.15, 0.045), q(0.23, 0.19, 0.045), t * 0.75, M['antler'], bevel=0.002)
        beam(q(0.15, 0.2), q(0.12, 0.28), t * 0.7, M['antler'], bevel=0.002)


def ham(M, x, y, ztop, big=1.0):
    beam((x, y, ztop), (x, y, ztop - 0.06), 0.008, M['net'], bevel=0)
    ellipsoid(x, y, ztop - 0.125, 0.04 * big, 0.034 * big, 0.058 * big, M['meat'], seg=10,
              rings=8, egg=0.3)
    beam((x, y, ztop - 0.06), (x, y, ztop - 0.09), 0.02, M['bone'], bevel=0)


def sausages(M, x, y, ztop, n=3):
    for i in range(n):
        for g in (-1, 1):
            ellipsoid(x + g * 0.012, y, ztop - 0.045 - i * 0.065, 0.017, 0.017, 0.032,
                      M['meat'] if i % 2 else M['red'], seg=8, rings=6)
    beam((x, y, ztop), (x, y, ztop - 0.03), 0.008, M['net'], bevel=0)


def gallery(M):
    """A timber frame in front of the shop with the hams on its beam."""
    xs = (-1.28, -0.62, 0.0, 0.5)
    for x in xs:
        beam((x, GAL_Y, G), (x, GAL_Y, GAL_Z + 0.03), 0.045, M['timber'])
        beam((x, GAL_Y, GAL_Z - 0.12), (x, GAL_Y + 0.28, GAL_Z + 0.0), 0.03, M['timber'])
        beam((x, GAL_Y + 0.0, GAL_Z - 0.0), (x, 0.0 - 0.02, GAL_Z + 0.02), 0.03, M['timber'])
    beam((xs[0], GAL_Y, GAL_Z), (xs[-1], GAL_Y, GAL_Z), 0.05, M['timber'])
    with F.anim('hams', 'sway', pivot=(-0.4, GAL_Y, GAL_Z), amp=0.2, period=2.7):
        for i, x in enumerate((-1.18, -1.03, -0.88, -0.74, 0.08, 0.2, 0.32, 0.42)):
            ham(M, x, GAL_Y + (0.015 if i % 2 else -0.015), GAL_Z - 0.01, 1.35 + 0.1 * (i % 3))
        sausages(M, -0.60, GAL_Y, GAL_Z - 0.01, 4)
        sausages(M, 0.0, GAL_Y, GAL_Z - 0.01, 3)


def handcart(M, x, y, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)

    def at(f, side=0.0, z=0.0):
        return (x + f * c - side * s, y + f * s + side * c, G + z)
    rbox(at(0, 0, 0.115), (0.3, 0.19, 0.045), (0, 0, rot), M['planks'], bevel=0.004)
    for g in (-1, 1):
        rbox(at(0, g * 0.095, 0.16), (0.3, 0.018, 0.07), (0, 0, rot), M['planks'], bevel=0.004)
        disc(M, at(0, g * 0.115, 0.075), (-s, c, 0), 0.075, 0.025, 'timber')
        beam(at(0.14, g * 0.08, 0.12), at(0.42, g * 0.07, 0.07), 0.022, M['timber'])
    rbox(at(-0.15, 0, 0.16), (0.018, 0.19, 0.07), (0, 0, rot), M['planks'], bevel=0.004)
    for k in range(3):                         # a load of meat under a cloth
        p = at(-0.04 + k * 0.07, (k - 1) * 0.04, 0.2)
        ellipsoid(p[0], p[1], p[2], 0.045, 0.04, 0.035, M['meat'], seg=8, rings=6)
    ellipsoid(*at(0.06, 0, 0.215), 0.08, 0.07, 0.025, M['linen'], seg=10, rings=6)


def build():
    M = mats()
    # ── the shop ──────────────────────────────────────────
    hut(M, HX0, HX1, HY0, HY1, EAVE, 'x', door=('s', DOOR_A),
        wins=[('s', -0.98, 'red', True), ('e', 0.5, 'teal', True),
              ('w', 0.5, 'red', False), ('n', -0.4, 'teal', False)],
        sign=('s', 0.14, 'cleaver', F.m(2.0)))
    F.chimney(M, CHX, CHY, CHZ0, CHH)
    antlers(M, 's', HY0, DOOR_A, EAVE - 0.26, span=1.9, rise=0.8)

    # ── the gallery of hams ───────────────────────────────
    gallery(M)

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(DOOR_A, HY0 - 0.1), (DOOR_A, -0.9), (0.0, -1.15), (0.0, ey + 0.02)], seed=6)
    dirt(M, 0.9, -0.6, 0.6, 0.8, 4)
    # block with the cleaver in it
    stump(M, 0.85, -0.62, r=0.1, h=0.12)
    rbox((0.85, -0.62, G + 0.17), (0.09, 0.015, 0.06), (0, 0.3, 0.2), M['iron'])
    handcart(M, 1.05, -0.05, rot=0.5)
    F.barrel(M, 1.2, -1.0, r=0.075, h=0.18)
    F.barrel(M, 1.05, -1.18, r=0.07, h=0.17)
    F.crate(M, 0.62, -1.15, 0.12, rot=0.3)
    F.crate(M, -1.15, -1.1, 0.12)
    F.barrel(M, -1.3, -0.98, r=0.07, h=0.17)
    for x, y, h, k in ((1.3, 1.25, 1.3, 'pine'), (-1.35, 1.3, 1.35, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, 0.78, 0.55, 0.12, 4, ['fl_red'])
    F.bush(M, -0.65, -0.18, 0.1, 2, ['fl_white'])
    F.flower_patch(M, -0.7, -1.2, 5, ['fl_white', 'fl_yel'], 5)
