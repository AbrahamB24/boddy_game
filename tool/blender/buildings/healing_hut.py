"""The Healing Hut: a small cloister of herb gardens, tier B (5 x 4 tiles).

Reads as: the sick are cured here. Three half-timbered terracotta wings round
a cobbled court with a well and four raised herb beds, a low stone wall with a
gate in front, two more herb beds outside it, and the white flag with the red
cross (on the gate pillar and on the north ridge) as the sign of an infirmary.

Replaces the herbalist's cottage (user 2026-11-08, from the mockup 'Kreuzgang-
Hof' plus herb beds plus a healing flag, with the vivid colours of the city
reference). Same 5 x 4 footprint and the same two doors.

Moving parts: the herbs sway; the windows and lanterns glow by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    north wing (ridge along x), doors onto the court (s) and the road (n)
    west + east wings (ridge along y) framing the court
    court: cobbled cross path, well, four herb beds
    low front wall with a gate; two herb beds outside it
"""
import random

from civic_kit import *  # noqa: F401,F403
from pro_kit import plain, tex_mat
import fw_kit as F

ID = 'healing_hut'
W, H = 5, 4
# The front door (south) and a back door (north): the tutorial lays the first
# road NORTH of the hut, so the hut has to open that way too.
ENTRANCE = [('s', 2), ('n', 2)]     # both at x = 0
HEADROOM = 0.8

EAVE = G + 0.75
NY0, NY1 = 1.0, 1.9                 # north wing, y range
SY0 = -0.95                         # side wings run SY0 .. NY0
WALL_Y = -1.2                       # the low gate wall
CHIMNEY = (-1.45, 1.6, EAVE + 0.3 + 0.5 + 0.13)


def vivid(M):
    """The city reference's palette, over the shared one."""
    M['roof'] = tex_mat('roof_v', 'clay_roof_tiles_02', 1.55, tint=(1.32, 0.76, 0.52),
                        sat=1.5, val=1.32, nstr=1.5, vary=0.05)
    M['roof2'] = tex_mat('roof2_v', 'clay_roof_tiles_02', 1.55, tint=(1.25, 0.72, 0.5),
                         sat=1.5, val=1.2, nstr=1.5, vary=0.05)
    M['plaster'] = tex_mat('plaster_v', 'white_plaster_rough_01', 1.0,
                           tint=(1.0, 0.94, 0.80), sat=0.22, val=2.2, rough=1.0,
                           nstr=0.9, vary=0.05)
    M['timber'] = tex_mat('timber_v', 'dark_wood', 0.8, tint=(0.9, 0.58, 0.38), sat=1.25,
                          val=0.9, nstr=0.8, vary=0.12)
    M['teal'] = plain('teal_v', '#1fa89c', rough=0.7, vary=0.08)
    M['red'] = plain('red_v', '#e0402a', rough=0.7, vary=0.08)
    M['leaf'] = plain('leaf_v', '#4fb01e', rough=0.7, bump=0.5, bump_scale=70, vary=0.2,
                      speck='#74c82e')
    M['leaf2'] = plain('leaf2_v', '#7cc934', rough=0.7, bump=0.5, bump_scale=70, vary=0.2,
                       speck='#a2da44')
    M['pine'] = plain('pine_v', '#2a8c3a', rough=0.8, bump=0.5, bump_scale=60, vary=0.15,
                      speck='#3aa24a')
    M['pine2'] = plain('pine2_v', '#46a838', rough=0.8, bump=0.5, bump_scale=60, vary=0.15,
                       speck='#62bd44')
    M['flag_w'] = plain('flag_w', '#fbf8f0', rough=0.95, bump=0.15, bump_scale=120, vary=0.03)
    M['flag_r'] = plain('flag_r', '#e32a2a', rough=0.85, bump=0.1, vary=0.04)
    return M


def herb_bed(M, x0, x1, y0, y1, seed):
    rnd = random.Random(seed)
    box((x0 + x1) / 2, (y0 + y1) / 2, G, x1 - x0, y1 - y0, 0.06, M['planks'], bevel=0.006)
    box((x0 + x1) / 2, (y0 + y1) / 2, G + 0.04, x1 - x0 - 0.05, y1 - y0 - 0.05, 0.03,
        M['soil'], bevel=0.004)
    with F.anim(f'herbs{x0:+.1f}{y0:+.1f}', 'sway', pivot=((x0 + x1) / 2, y0, G + 0.07),
                amp=0.12, period=3.3):
        n = int((x1 - x0) / 0.085)
        for i in range(n):
            for j in range(2):
                x = x0 + 0.06 + i * (x1 - x0 - 0.12) / max(1, n - 1)
                y = y0 + 0.06 + j * (y1 - y0 - 0.12)
                ellipsoid(x, y + rnd.uniform(-0.01, 0.01), G + 0.11, 0.032, 0.032,
                          0.045 + 0.02 * rnd.random(), M['leaf' if (i + j) % 2 else 'leaf2'],
                          seg=8, rings=5)
                if (i * 3 + j) % 5 == 0:
                    ellipsoid(x, y, G + 0.17, 0.016, 0.016, 0.016, M['fl_pink'], seg=6, rings=4)


def well(M, x, y):
    for k in range(8):
        a = k * math.pi / 4
        rbox((x + 0.08 * math.cos(a), y + 0.08 * math.sin(a), G + 0.05),
             (0.07, 0.04, 0.1), (0, 0, a + math.pi / 2), M['stone'], bevel=0.006)
    cyl(x, y, G + 0.09, 0.07, 0.07, 0.012, M['water'], seg=14)
    for g in (-1, 1):
        beam((x + g * 0.09, y, G), (x + g * 0.09, y, G + 0.3), 0.02, M['timber'])
    beam((x - 0.09, y, G + 0.3), (x + 0.09, y, G + 0.3), 0.022, M['timber'])
    rbox((x, y, G + 0.32), (0.26, 0.17, 0.02), (0, 0, 0), M['roof2'], bevel=0.004)


def cross_flag(M, x, y, z0, h, w):
    """Pole with a white cloth carrying a red cross, facing south."""
    beam((x, y, z0), (x, y, z0 + h), 0.014, M['timber'], bevel=0.002)
    ellipsoid(x, y, z0 + h + 0.012, 0.016, 0.016, 0.016, M['gold'], seg=8, rings=5)
    cw, ch = w, w * 1.25
    cx, cz = x + cw / 2 + 0.01, z0 + h - ch / 2 - 0.02
    rbox((cx, y, cz), (cw, 0.012, ch), (0, 0, 0), M['flag_w'], bevel=0.002)
    rbox((cx, y - 0.008, cz), (cw * 0.26, 0.012, ch * 0.9), (0, 0, 0), M['flag_r'], bevel=0.001)
    rbox((cx, y - 0.008, cz + ch * 0.06), (cw * 0.9, 0.012, ch * 0.24), (0, 0, 0),
         M['flag_r'], bevel=0.001)


def build():
    random.seed(11)
    M = vivid(mats())
    DW, DH = DIM['door']

    # north wing, ridge along x
    hall(M, -2.0, 2.0, NY0, NY1, EAVE, 'x', 'roof',
         doors=[('s', -0.1, DW, DH), ('n', -0.1, DW, DH)],
         wins=[('s', -1.55, 'teal', True), ('s', -0.85, 'red', False), ('s', 0.65, 'red', False),
               ('s', 1.3, 'teal', True), ('e', 1.4, 'teal', True), ('n', -1.2, 'teal', True),
               ('n', 0.8, 'teal', True)])
    # west and east wings, ridge along y
    hall(M, -2.0, -1.1, SY0, NY0, EAVE, 'y', 'roof',
         wins=[('e', -0.6, 'teal', True), ('e', 0.2, 'red', False),
               ('s', -1.7, 'teal', True), ('w', -0.2, 'red', True)], lanterns=False)
    hall(M, 1.1, 2.0, SY0, NY0, EAVE, 'y', 'roof',
         wins=[('e', -0.6, 'teal', True), ('e', 0.2, 'red', False),
               ('s', 1.3, 'teal', True), ('w', -0.2, 'red', True)], lanterns=False)
    F.chimney(M, -1.45, 1.6, EAVE + 0.3, 0.5)
    F.hanging_sign(M, 's', NY0, -0.1 + DW + 0.12, EAVE - 0.04,
                   flat_emblem(M, 's', [(0, 0, 0.17, 0.55, 0.0, 'red'),
                                        (0, 0.03, 0.55, 0.17, 0.0, 'red')]), size=F.m(1.9))

    # court: cobbled cross path, well, four raised herb beds
    F.cobble_path(M, [(0.0, WALL_Y), (0.0, -0.25)], seed=3)
    F.cobble_path(M, [(0.0, 0.05), (0.0, NY0 + 0.05)], seed=4)
    well(M, 0.0, -0.1)
    herb_bed(M, -1.0, -0.25, -0.95, -0.45, 1)
    herb_bed(M, 0.25, 1.0, -0.95, -0.45, 2)
    herb_bed(M, -1.0, -0.25, 0.2, 0.7, 3)
    herb_bed(M, 0.25, 1.0, 0.2, 0.7, 4)

    # low front wall with a gate, pillars, healing flag
    for x0, x1 in ((-2.0, -0.32), (0.32, 2.0)):
        box((x0 + x1) / 2, WALL_Y, G, x1 - x0, 0.1, 0.24, M['stone'], bevel=0.008)
    for sx in (-1, 1):
        box(sx * 0.32, WALL_Y, G, 0.14, 0.14, 0.5, M['stone'], bevel=0.01)
        box(sx * 0.32, WALL_Y, G + 0.5, 0.18, 0.18, 0.04, M['stone_dk'], bevel=0.006)
    cross_flag(M, 0.32, WALL_Y, G + 0.54, 0.95, 0.2)
    cross_flag(M, 0.0, 1.45, EAVE + 0.55, 0.55, 0.14)

    # outside the wall: path to the south cell, two more herb beds, bushes, firs
    ex, ey = F.entrance_point(W, H, *ENTRANCE[0])
    F.cobble_path(M, [(0.0, WALL_Y), (0.0, ey + 0.02)], seed=6)
    nx, ny = F.entrance_point(W, H, 'n', 2)
    F.cobble_path(M, [(0.0, NY1 + 0.1), (nx, ny - 0.02)], seed=9)
    herb_bed(M, -2.0, -0.8, -1.9, -1.55, 5)
    herb_bed(M, 0.8, 2.0, -1.9, -1.55, 6)
    F.bush(M, -0.55, -1.55, 0.1, 3, ['fl_white'])
    F.bush(M, 0.55, -1.55, 0.1, 5, ['fl_pink'])
    for x, y, h, k in ((-2.35, 1.85, 1.2, 'pine2'), (2.35, 1.85, 1.1, 'pine'),
                       (-2.35, -0.3, 0.9, 'pine'), (2.35, -1.8, 0.8, 'pine2')):
        fir(M, x, y, h, k)
