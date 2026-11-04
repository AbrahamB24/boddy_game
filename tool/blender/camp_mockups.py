"""Twenty concepts for the four resource camps — quick smooth renders to choose from.

    blender --background --python tool/blender/camp_mockups.py -- <out_dir> [key ...]

User 2026-11-03: "gib mir je 5 Vorschläge für die beiden Holzfäller und
Steinbrüche als Mockup". Keys: sw1..sw5 (small_wood_camp, 3x3), lw1..lw5
(large_wood_camp, 4x4), sq1..sq5 (small_quarry, 3x3), lq1..lq5
(large_stone_camp, 5x4). Built from fw_kit parts, smooth (not voxelised)
and low-sample: sketches to pick from, not shipping art.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import fw_kit as F  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
from camp_kit import *  # noqa: E402,F401,F403

G = K.G

# ══ SMALL WOOD CAMP (3 x 3) ══════════════════════════════════
def sw1_waldhuette(M):
    """Log cabin among firs; stump with an axe, log pyramid."""
    dirt(M, 0.2, -0.3, 1.1, 0.9, 1)
    log_cabin(M, -1.2, -0.15, -0.05, 1.05, G + 0.62, 'y', door=('e', 0.25),
              wins=[('s', -0.67, 'red', True), ('e', 0.75, 'teal', False)],
              sign=('s', -1.05, 'axe'))
    F.chimney(M, -0.9, 0.85, G + 0.85, 0.45)
    for x, y, h in ((-1.25, -1.15, 1.5), (-1.3, -0.45, 1.2), (0.95, 1.2, 1.9), (1.3, 0.55, 1.4),
                    (-0.35, 1.35, 1.6), (0.35, 1.3, 1.25)):
        fir(M, x, y, h, 'pine' if (x * y) > 0 else 'pine2')
    stump(M, 0.45, -0.45, axe=True)
    stump(M, 0.85, -1.0, 0.07, 0.06)
    log_stack(M, 0.7, 0.35, 0.9, 4, 0.05)
    for i in range(6):
        a = i * 1.1
        rbox((0.45 + math.cos(a) * 0.14, -0.45 + math.sin(a) * 0.14, G + 0.015), (0.06, 0.025, 0.025),
             (0, 0, a), M['log_end'])
    path([(0.0, 0.25), (0.25, 0.0), (1.48, 0.0)])


def sw2_holzmiete(M):
    """Half-timbered shed with an open firewood lean-to; round beehive woodpiles."""
    dirt(M, 0.3, -0.4, 1.0, 0.8, 2)
    hut(M, -1.3, -0.35, 0.15, 1.25, G + 0.72, 'y', door=('e', 0.45),
        wins=[('s', -0.82, 'mustard', True)], sign=('s', -1.2, 'axe'))
    lean_to(M, -0.35, 0.75, 0.75, 1.3, G + 0.6, G + 0.42, 'e')
    billets(M, 0.2, 1.05, 0.95, 0.36, 0.3)
    holzmiete(M, 0.65, -0.7, 0.3, 0.5)
    holzmiete(M, -0.55, -0.9, 0.22, 0.38)
    sawhorse(M, 0.75, 0.15, 0.3)
    stump(M, 0.15, -0.2, axe=True)
    for x, y, h in ((-1.25, -0.35, 1.3), (1.25, 1.2, 1.6), (1.3, -1.2, 1.0)):
        fir(M, x, y, h)
    leafy(M, -1.15, -1.15, 1.0, 3)
    path([(-0.25, 0.45), (0.1, 0.0), (0.15, -1.48)])


def sw3_koehlerei(M):
    """The charcoal burner's: a smoking earth kiln, a pole hut, metre wood."""
    dirt(M, 0.1, -0.2, 1.25, 1.1, 3, 'soil')
    # the kiln: an earth dome with glowing vents, a ladder against it
    ellipsoid(0.35, -0.35, G, 0.55, 0.55, 0.4, M['soil'], seg=24, rings=14)
    for a in (0.3, 1.5, 2.7, 4.0, 5.2):
        ellipsoid(0.35 + math.cos(a) * 0.38, -0.35 + math.sin(a) * 0.38, G + 0.25, 0.04, 0.04, 0.03,
                  M['ember'], seg=8, rings=6)
    cyl(0.35, -0.35, G + 0.36, 0.06, 0.05, 0.06, M['fire'], seg=10)
    beam((0.85, -0.9, G), (0.48, -0.5, G + 0.42), 0.025, M['timber'])
    beam((0.92, -0.82, G), (0.55, -0.43, G + 0.42), 0.025, M['timber'])
    for k in range(5):
        f = 0.15 + k * 0.17
        beam((0.85 - 0.37 * f, -0.9 + 0.4 * f, G + 0.42 * f), (0.92 - 0.37 * f, -0.82 + 0.39 * f, G + 0.42 * f),
             0.015, M['timber'])
    # the pole hut: a cone of poles and sods
    cyl(-0.85, 0.75, G, 0.45, 0.04, 0.85, M['bark'], seg=14)
    for a in range(10):
        aa = TAU * a / 10
        beam((-0.85 + math.cos(aa) * 0.46, 0.75 + math.sin(aa) * 0.46, G),
             (-0.85 + math.cos(aa) * 0.03, 0.75 + math.sin(aa) * 0.03, G + 0.95), 0.025, M['timber'])
    rbox((-0.6, 0.45, G + 0.17), (0.16, 0.02, 0.32), (0, 0, 0.75), M['dark'])
    # metre wood + charcoal
    billets(M, 0.6, 0.9, 1.1, 0.35, 0.28)
    billets(M, -0.5, -0.35, 0.6, 0.3, 0.25, axis='y')
    for i, (x, y) in enumerate(((-0.15, -1.15), (0.05, -1.2), (-0.05, -1.0))):
        F.sack(M, x, y, 1.1, i * 0.7, 'sack')
    ellipsoid(1.0, -0.15, G, 0.22, 0.18, 0.1, M['coal'], seg=14, rings=8)
    signpost(M, 1.2, -0.75, 'e', 'axe')
    for x, y, h in ((-1.3, -1.2, 1.4), (1.3, 1.3, 1.7), (-0.2, 1.35, 1.3), (-1.35, 1.35, 1.2)):
        fir(M, x, y, h, 'pine2')
    path([(0.55, 0.3), (1.0, 0.1), (1.48, 0.0)])


def sw4_riesenstumpf(M):
    """Fantasy: a workshop hollowed into a giant stump, the woodsman's axe in its rim."""
    dirt(M, 0.35, -0.35, 1.0, 0.9, 4)
    cx, cy, R = -0.45, 0.4, 0.68
    cyl(cx, cy, G, R * 1.25, R, 1.0, M['bark'], seg=20)
    for a in (0.4, 1.6, 2.9, 4.3, 5.4):
        beam((cx + math.cos(a) * R, cy + math.sin(a) * R, G + 0.25),
             (cx + math.cos(a) * (R + 0.4), cy + math.sin(a) * (R + 0.4), G), 0.12, M['bark'])
    cyl(cx, cy, G + 0.995, R * 0.94, R * 0.94, 0.01, M['log_end'], seg=20)
    for k in range(1, 5):
        cyl(cx, cy, G + 1.0, R * k / 5, R * k / 5 - 0.012, 0.012, M['bark'], seg=20)
    # a shingle cap house sitting on top
    cyl(cx - 0.1, cy + 0.1, G + 1.0, 0.36, 0.36, 0.28, M['plaster'], seg=12)
    cyl(cx - 0.1, cy + 0.1, G + 1.28, 0.48, 0.0, 0.5, M['shingle'], seg=12)
    F.chimney(M, cx - 0.25, cy + 0.25, G + 1.4, 0.3)
    # door + round windows on the south / east
    F.door(M, 's', cy - R - 0.02, cx + 0.05, *DIM['door'], G + 0.02)
    for a, z in ((-0.55, 0.55), (-0.15, 0.35)):
        p = Vector((cx + math.cos(a) * (R + 0.01), cy + math.sin(a) * (R + 0.01), G + z))
        ellipsoid(p.x, p.y, p.z, 0.07, 0.07, 0.07, M['pane_glow'], seg=12, rings=8)
        ellipsoid(p.x, p.y, p.z, 0.085, 0.085, 0.085, M['timber'], seg=12, rings=8)
    # the giant axe stuck in the rim
    beam((cx + 0.35, cy - 0.15, G + 1.02), (cx + 0.95, cy - 0.55, G + 1.9), 0.07, M['timber'])
    rbox((cx + 0.33, cy - 0.12, G + 1.06), (0.36, 0.05, 0.26), (0, 0.55, -0.6), M['iron'])
    log_stack(M, 0.85, 0.85, 0.8, 3, 0.06, 'y')
    sawhorse(M, 0.75, -0.55, 0.2)
    stump(M, 0.2, -0.9, 0.07, 0.07)
    for x, y, h in ((1.3, 1.3, 1.5), (-1.3, -1.25, 1.2), (1.35, -1.2, 0.9)):
        fir(M, x, y, h)
    path([(cx + 0.05, cy - R - 0.1), (0.1, -0.55), (0.0, -1.48)])


def sw5_saegegrube(M):
    """A two-man pit saw on a trestle; half-timbered tool hut with a saw sign."""
    dirt(M, 0.35, -0.3, 1.0, 0.85, 5)
    hut(M, -1.3, -0.3, 0.2, 1.25, G + 0.75, 'x', door=('s', -0.55),
        wins=[('s', -1.0, 'teal', True), ('e', 0.75, 'red', False)], sign=('s', -0.35, 'saw'))
    # the trestle and the log on it
    for x in (0.05, 0.85):
        for g in (-1, 1):
            beam((x, -0.25 + g * 0.18, G), (x, -0.25 + g * 0.05, G + 0.42), 0.035, M['timber'])
        beam((x, -0.32, G + 0.42), (x, -0.18, G + 0.42), 0.04, M['timber'])
    log(M, (-0.15, -0.25, G + 0.48), (1.1, -0.25, G + 0.48), 0.065)
    rbox((0.45, -0.25, G + 0.52), (0.04, 0.008, 0.62), (0, 0, 0), M['iron'], bevel=0)
    beam((0.39, -0.25, G + 0.83), (0.51, -0.25, G + 0.83), 0.02, M['timber'])
    beam((0.39, -0.25, G + 0.22), (0.51, -0.25, G + 0.22), 0.02, M['timber'])
    board_stack(M, 0.95, 0.55, 0.7, 0.24, 0.24, 1.57)
    log_stack(M, 0.45, 1.15, 0.9, 3, 0.055)
    # a tool rack against the hut
    for k in range(4):
        beam((-0.25, -0.05 + k * 0.09, G), (-0.25, -0.05 + k * 0.09, G + 0.28), 0.015, M['timber'])
    for x, y, h in ((-1.3, -0.8, 1.4), (1.3, -1.25, 1.1), (1.3, 1.35, 1.6), (-0.3, 1.38, 1.2)):
        fir(M, x, y, h, 'pine2' if x > 0 else 'pine')
    F.bush(M, -0.85, -0.25, 0.16, 4)
    path([(-0.55, 0.12), (-0.5, -0.7), (0.0, -1.0), (0.0, -1.48)])


# ══ LARGE WOOD CAMP (4 x 4) ══════════════════════════════════
def lw1_wassersaege(M):
    """A water-powered sawmill: millrace, undershot wheel, log yard."""
    dirt(M, -0.2, -0.7, 1.6, 1.1, 6)
    hut(M, -1.6, 0.35, 0.15, 1.55, G + 1.0, 'x', door=('s', -0.4),
        wins=[('s', -1.15, 'teal', True), ('s', 0.0, 'red', False), ('e', 0.55, 'teal', True)],
        roof='roof', sign=('s', -1.5, 'saw'))
    water_channel(M, 0.55, 1.05, -2.0, 2.0)
    wheel(M, (0.8, 0.85, G + 0.42), 0.42, 'x', n=14, width=0.18, paddles=True)
    beam((0.35, 0.85, G + 0.42), (0.8, 0.85, G + 0.42), 0.06, M['timber'])
    for y in (-1.2, 0.0):
        rbox((0.8, y, G + 0.1), (0.62, 0.22, 0.04), (0, 0, 0), M['planks'])
    log_stack(M, -0.7, -0.55, 1.4, 4, 0.06)
    board_stack(M, -1.35, -1.35, 0.8, 0.3, 0.3)
    board_stack(M, -0.3, -1.45, 0.8, 0.3, 0.22)
    log(M, (0.35, 0.3, G + 0.07), (-0.6, 0.0, G + 0.07), 0.07)
    for x, y, h in ((1.6, 1.6, 2.0), (1.7, 0.7, 1.6), (-1.75, -0.5, 1.6), (1.6, -1.4, 1.3),
                    (-1.0, 1.8, 1.7), (-1.8, 1.7, 1.4)):
        fir(M, x, y, h, 'pine' if y > 0 else 'pine2')
    path([(-0.4, 0.0), (-0.1, -0.5), (0.5, -0.5), (0.5, -1.98)])


def lw2_zimmerei(M):
    """Carpenter's yard: an open long hall, a house frame being raised, a gin pole."""
    dirt(M, 0.2, -0.4, 1.7, 1.3, 7)
    # the open hall: posts and a big gable roof, planks under it
    x0, x1, y0, y1 = -1.8, 0.4, 0.75, 1.75
    for i in range(6):
        x = x0 + (x1 - x0) * i / 5
        for y in (y0, y1):
            beam((x, y, G), (x, y, G + 0.7), 0.05, M['timber'])
    for y in (y0, y1):
        beam((x0, y, G + 0.68), (x1, y, G + 0.68), 0.05, M['timber'])
    F.gable_roof(M, (x0 + x1) / 2, (y0 + y1) / 2, G + 0.7, x1 - x0, y1 - y0, 'x', M['roof'],
                 oh=0.12, oe=0.12)
    board_stack(M, -1.2, 1.25, 0.9, 0.5, 0.3)
    board_stack(M, -0.2, 1.25, 0.7, 0.5, 0.2)
    # the half-raised house frame in the yard
    fx0, fx1, fy0, fy1, fz = 0.3, 1.4, -1.5, -0.5, G + 0.06
    box((fx0 + fx1) / 2, (fy0 + fy1) / 2, G, fx1 - fx0 + 0.1, fy1 - fy0 + 0.1, 0.06, M['stone_dk'])
    for x in (fx0, (fx0 + fx1) / 2, fx1):
        for y in (fy0, fy1):
            beam((x, y, fz), (x, y, fz + 0.7), 0.05, M['timber'])
    for y in (fy0, fy1):
        beam((fx0, y, fz + 0.7), (fx1, y, fz + 0.7), 0.05, M['timber'])
        beam((fx0, y, fz + 0.35), (fx1, y, fz + 0.35), 0.04, M['timber'])
        beam((fx0, y, fz), ((fx0 + fx1) / 2, y, fz + 0.7), 0.04, M['timber'])
    for x in (fx0, fx1):
        beam((x, fy0, fz + 0.7), (x, fy1, fz + 0.7), 0.05, M['timber'])
    for x in (fx0, fx0 + 0.37):
        beam((x, fy0, fz + 0.7), (x, (fy0 + fy1) / 2, fz + 0.7 + 0.5 * 1.19), 0.04, M['timber'])
        beam((x, fy1, fz + 0.7), (x, (fy0 + fy1) / 2, fz + 0.7 + 0.5 * 1.19), 0.04, M['timber'])
    rbox((fx0 + 0.02, (fy0 + fy1) / 2, fz + 1.35), (0.04, 0.3, 0.04), (0, 0, 0), M['leaf'])
    # gin pole lifting a beam
    beam((1.6, 0.2, G), (1.35, 0.0, G + 1.5), 0.05, M['timber'])
    beam((1.35, 0.0, G + 1.5), (1.35, 0.0, G + 0.62), 0.008, M['iron'], bevel=0)
    beam((1.05, 0.0, G + 0.6), (1.65, 0.0, G + 0.6), 0.05, M['timber'])
    hut(M, -1.75, -0.85, -1.6, -0.6, G + 0.68, 'y', door=('e', -1.2),
        wins=[('s', -1.3, 'teal', True)], sign=('e', -0.85, 'saw'))
    for i in range(4):
        beam((-0.4 + i * 0.12, -0.3, G + 0.03), (-0.4 + i * 0.12, 0.45, G + 0.03), 0.05, M['timber'])
    sawhorse(M, 0.6, 0.15, 1.57, False)
    for x, y, h in ((1.7, 1.7, 1.8), (1.75, 1.0, 1.4), (-1.85, 0.2, 1.5)):
        fir(M, x, y, h)
    path([(-0.85, -1.2), (-0.2, -1.2), (-0.5, -1.98)], seed=7)


def lw3_holzhof(M):
    """Timber yard: a treadwheel crane loading logs onto tall racks, an office."""
    dirt(M, 0.1, -0.2, 1.7, 1.5, 8)
    # tall racks of boards along the back
    for x in (-1.6, -0.9, -0.2, 0.5):
        for y in (1.0, 1.7):
            beam((x, y, G), (x, y, G + 0.95), 0.05, M['timber'])
        for z in (0.3, 0.62, 0.95):
            beam((x, 1.0, G + z), (x, 1.7, G + z), 0.04, M['timber'])
    for z in (0.0, 0.31, 0.63):
        for x0 in (-1.6, -0.9, -0.2):
            rbox((x0 + 0.35, 1.35, G + z + 0.12), (0.62, 0.66, 0.2), (0, 0, 0), M['planks'], bevel=0.004)
    lean_to(M, -1.7, 0.6, 0.95, 1.75, G + 1.22, G + 1.05, 's', 'shingle', posts=False)
    treadwheel_crane(M, 1.0, 0.6, 1.4, (-0.3, -1.0), 0.75, 0.6, load='log')
    log_stack(M, 1.15, -0.8, 1.1, 4, 0.065, 'y')
    log_stack(M, 0.2, -0.3, 1.0, 3, 0.06)
    hut(M, -1.75, -0.65, -1.7, -0.6, G + 0.75, 'x', door=('e', -1.15),
        wins=[('s', -1.2, 'red', True)], sign=('s', -0.8, 'tree'))
    cyl(-0.35, -1.45, G, 0.04, 0.04, 0.35, M['timber'])
    for x, y, h in ((1.75, 1.75, 1.6), (-1.85, 0.4, 1.5), (1.8, -1.75, 1.1)):
        fir(M, x, y, h)
    path([(-0.55, -1.15), (-0.1, -1.4), (-0.5, -1.98)], seed=8)


def lw4_windsaege(M):
    """A wind-driven sawmill on a stone base, sails facing the yard."""
    dirt(M, 0.3, -0.5, 1.5, 1.2, 9)
    cx, cy = -0.6, 0.55
    cyl(cx, cy, G, 0.75, 0.7, 0.35, M['stone'], seg=24)
    hut(M, cx - 0.55, cx + 0.55, cy - 0.65, cy + 0.65, G + 1.35, 'x',
        wins=[('s', cx - 0.15, 'teal', True), ('e', cy - 0.3, 'red', True)],
        roof='shingle')
    hub = Vector((cx + 0.7, cy - 0.1, G + 1.55))
    beam(hub - Vector((0.25, 0, 0)), hub + Vector((0.06, 0, 0)), 0.07, M['timber'])
    for k in range(4):
        a = TAU * k / 4 + 0.35
        d = Vector((0, math.cos(a), math.sin(a)))
        n = Vector((0, -math.sin(a), math.cos(a)))
        L = 1.25
        beam(hub, hub + d * L, 0.04, M['timber'])
        for g in (0.06, 0.13, 0.2):
            beam(hub + d * 0.25 + n * g, hub + d * L + n * g, 0.012, M['timber'], bevel=0)
        for f in range(6):
            p = hub + d * (0.25 + (L - 0.25) * f / 5)
            beam(p, p + n * 0.2, 0.012, M['timber'], bevel=0)
        rbox(hub + d * (0.25 + L) / 2 + n * 0.13 + Vector((0.01, 0, 0)), (0.006, 1.0, 0.13),
             (math.atan2(d.z, d.y), 0, 0), M['linen'], bevel=0)
    # ramp up to the mill floor, logs waiting at its foot
    rbox((cx + 0.95, cy - 0.85, G + 0.17), (0.75, 0.3, 0.03), (0, -0.42, 0), M['planks'])
    log_stack(M, 0.9, -0.8, 1.0, 3, 0.06, 'x')
    board_stack(M, -0.5, -1.25, 1.0, 0.3, 0.28)
    lean_to(M, 0.9, 1.75, 0.6, 1.6, G + 0.6, G + 0.45, 'e', 'roof2')
    billets(M, 1.3, 1.1, 0.8, 0.35, 0.4, axis='y')
    signpost(M, 1.5, -1.35, 'e', 'saw')
    for x, y, h in ((-1.75, -0.8, 1.5), (-1.7, 1.75, 1.7), (1.8, -1.8, 1.0)):
        fir(M, x, y, h, 'pine2')
    path([(0.4, -0.45), (0.5, -1.1), (0.5, -1.98)], seed=9)


def lw5_waldlodge(M):
    """Fantasy: a Nordic log lodge with crossed gable heads in a ring of tall firs; a log lift."""
    dirt(M, 0.25, -0.35, 1.5, 1.3, 10)
    x0, x1, y0, y1 = -1.4, 0.4, 0.2, 1.3
    zr = log_cabin(M, x0, x1, y0, y1, G + 0.75, 'x', door=('s', -0.5),
                   wins=[('s', -1.0, 'red', True), ('s', 0.0, 'red', True), ('e', 0.75, 'teal', True)],
                   roof='shingle', sign=('s', -0.2, 'axe'))
    ym = (y0 + y1) / 2
    for x in (x0 - 0.12, x1 + 0.12):
        for g in (-1, 1):
            beam((x, ym, zr - 0.05), (x, ym + g * 0.3, zr + 0.3), 0.05, M['timber'])
        ellipsoid(x, ym - 0.3 + 0.0, zr + 0.32, 0.05, 0.05, 0.05, M['mustard'], seg=8, rings=6)
        ellipsoid(x, ym + 0.3, zr + 0.32, 0.05, 0.05, 0.05, M['mustard'], seg=8, rings=6)
    # the log lift: a tall A-frame with a pulley, a log on the rope
    for g in (-1, 1):
        beam((1.05 + g * 0.3, 0.9, G), (1.05, 0.9, G + 1.6), 0.06, M['bark'])
    beam((1.05, 0.9, G + 1.6), (1.05, 0.9, G + 0.75), 0.008, M['iron'], bevel=0)
    disc(M, (1.05, 0.9, G + 1.55), (0, 1, 0), 0.07, 0.03, 'iron')
    log(M, (0.75, 0.9, G + 0.72), (1.35, 0.9, G + 0.72), 0.06)
    log_stack(M, 1.0, -0.4, 1.0, 4, 0.065, 'y')
    holzmiete(M, -0.9, -0.85, 0.3, 0.5)
    stump(M, -0.2, -0.5, axe=True)
    # a fire bowl
    cyl(0.1, -1.25, G, 0.1, 0.08, 0.08, M['iron'], seg=12)
    cyl(0.1, -1.25, G + 0.08, 0.05, 0.0, 0.1, M['fire'], seg=10)
    for i in range(10):
        a = TAU * i / 10 + 0.2
        x, y = math.cos(a) * 1.8, math.sin(a) * 1.8
        if x > 0.6 and y < -0.6:
            continue
        fir(M, x, y, 1.9 + (i % 3) * 0.35, 'pine' if i % 2 else 'pine2')
    path([(-0.5, 0.05), (-0.2, -0.85), (0.5, -1.2), (0.5, -1.98)], seed=10)


# ══ SMALL QUARRY (3 x 3) ═════════════════════════════════════
def sq1_felsanbruch(M):
    """An outcrop cut into clean benches; a shed, a barrow, blocks ready."""
    dirt(M, 0.3, -0.45, 1.1, 0.85, 11, 'gravel')
    rock_mass(M, -0.2, 0.75, 2.4, 1.3, 1.1, seed=1)
    cut_step(M, -0.9, 0.7, 0.05, 0.6, G, G + 0.32)
    cut_step(M, -0.5, 0.5, 0.25, 0.75, G + 0.32, G + 0.62)
    for x in (-0.6, -0.3, 0.0, 0.3):
        stone_block(M, x, -0.05, s=(0.16, 0.1, 0.1))
    stone_block(M, 0.2, 0.32, G + 0.32, (0.2, 0.14, 0.13), 0.3)
    lean_to(M, -1.45, -0.75, -1.4, -0.75, G + 0.55, G + 0.4, 's', 'roof2')
    for k in range(3):
        F.crate(M, -1.25 + k * 0.17, -1.2, 0.13)
    block_stack(M, 0.85, -0.85, 3, 2, 2)
    wheelbarrow(M, 0.35, -0.55, 0.5, 'rock_cut')
    signpost(M, 1.25, -0.25, 'e', 'pick')
    ladder(M, (0.55, 0.45, G + 0.32), (0.55, 0.62, G + 0.95))
    fir(M, 1.3, 1.25, 1.3)
    leafy(M, -1.3, 0.1, 1.0, 2)
    path([(0.1, -0.3), (0.8, -0.2), (1.48, 0.0)], seed=11)



def sq2_steinmetz(M):
    """The mason's lodge: an open-fronted workshop, dressed stones, a column and a bust."""
    dirt(M, 0.35, -0.35, 1.0, 0.9, 12, 'gravel')
    hut(M, -1.35, -0.25, 0.25, 1.3, G + 0.78, 'x', door=('e', 0.95),
        wins=[('s', -1.05, 'teal', True)], sign=('s', -0.45, 'hammer'))
    lean_to(M, -0.25, 0.8, 0.35, 1.25, G + 0.66, G + 0.5, 'e', 'roof2')
    rbox((0.25, 0.8, G + 0.22), (0.5, 0.28, 0.06), (0, 0, 0), M['planks'])
    for x in (0.05, 0.45):
        box(x, 0.8, G, 0.06, 0.24, 0.2, M['timber'])
    stone_block(M, 0.2, 0.8, G + 0.25, (0.14, 0.12, 0.09))
    # a finished column, a capital, a bust on a plinth
    cyl(0.75, -0.4, G, 0.1, 0.1, 0.05, M['rock_cut'], seg=16)
    cyl(0.75, -0.4, G + 0.05, 0.075, 0.07, 0.6, M['rock_cut'], seg=16)
    box(0.75, -0.4, G + 0.65, 0.2, 0.2, 0.06, M['rock_cut'])
    box(-0.5, -0.65, G, 0.22, 0.22, 0.28, M['rock_cut'])
    ellipsoid(-0.5, -0.65, G + 0.38, 0.08, 0.07, 0.1, M['rock_cut'], seg=12, rings=10)
    ellipsoid(-0.5, -0.65, G + 0.3, 0.11, 0.07, 0.04, M['rock_cut'], seg=12, rings=8)
    block_stack(M, 0.3, -1.05, 3, 2, 2, seed=3)
    # raw rock behind and to the right
    rock_mass(M, 0.9, 1.0, 1.0, 0.8, 0.65, seed=2, n=14)
    for i in range(10):
        a = i * 2.3
        ellipsoid(0.0 + math.cos(a) * 0.2, 0.05 + math.sin(a) * 0.14, G + 0.01, 0.03, 0.02, 0.012,
                  M['rock_cut'], seg=6, rings=4)
    leafy(M, -1.2, -1.1, 1.0, 4)
    F.bush(M, -1.25, -0.2, 0.15, 5, ['fl_yel'])
    path([(-0.15, 0.95), (0.05, 0.0), (0.0, -0.4), (0.0, -1.48)], seed=12)


def sq3_findling(M):
    """A giant boulder split by wedges; a tripod hoist lifting a fresh block."""
    dirt(M, 0.15, -0.2, 1.25, 1.1, 13, 'gravel')
    for g, dx in ((-1, -0.12), (1, 0.12)):
        ellipsoid(-0.3 + dx, 0.45, G + 0.05, 0.55, 0.6, 0.62, M['rock'], seg=20, rings=14)
    rbox((-0.3, -0.12, G + 0.35), (0.22, 0.04, 0.64), (0, 0, 0), M['rock_cut'])
    for z in (0.35, 0.55, 0.75):
        rbox((-0.3, -0.13, G + z), (0.05, 0.06, 0.07), (0, 0, 0), M['iron'])
    ellipsoid(-0.75, 0.9, G + 0.6, 0.18, 0.15, 0.06, M['leaf'], seg=10, rings=6)
    tripod(M, 0.75, -0.35, 1.0, hang=0.55)
    block_stack(M, 0.95, 0.75, 2, 2, 2, (0.18, 0.13, 0.11), seed=4)
    lean_to(M, -1.45, -0.85, -1.4, -0.7, G + 0.5, G + 0.38, 's', 'shingle')
    F.barrel(M, -1.25, -1.15)
    F.crate(M, -1.0, -1.2, 0.12)
    for i in range(14):
        a = i * 1.7
        ellipsoid(0.0 + math.cos(a) * 0.4, -0.35 + math.sin(a) * 0.25, G + 0.012, 0.045, 0.035, 0.02,
                  M['rock'], seg=6, rings=4)
    signpost(M, 1.25, -1.1, 'e', 'pick')
    fir(M, 1.25, 1.3, 1.4)
    leafy(M, -1.25, 1.25, 1.1, 6)
    path([(0.4, -0.75), (0.9, -0.6), (1.48, -0.5)], seed=13)


def sq4_hangrutsche(M):
    """A hillside quarry: stones slide down a plank chute into a gravel bin."""
    dirt(M, 0.4, -0.5, 1.0, 0.8, 14, 'gravel')
    rock_mass(M, -0.45, 0.55, 2.0, 1.8, 1.25, seed=5, n=30)
    cut_step(M, -0.2, 0.55, -0.1, 0.55, G, G + 0.62, top='gravel')
    # the chute from the top of the cut down into the bin
    top = Vector((-0.2, 0.75, G + 1.1))
    bot = Vector((0.85, -0.35, G + 0.3))
    for g in (-0.07, 0.07):
        beam(top + Vector((g, g, 0)), bot + Vector((g, g, 0)), 0.02, M['timber'])
    rbox((top + bot) / 2, ((bot - top).length, 0.14, 0.02),
         Vector((1, 0, 0)).rotation_difference((bot - top).normalized()).to_euler(), M['planks'])
    for f in (0.3, 0.55, 0.8):
        p = top.lerp(bot, f)
        beam((p.x, p.y, G), (p.x, p.y, p.z - 0.02), 0.03, M['timber'])
    for f in (0.2, 0.45, 0.65):
        p = top.lerp(bot, f)
        stone_block(M, p.x, p.y, p.z, (0.09, 0.08, 0.07), 0.6, 'rock')
    # the bin
    for g in (-1, 1):
        rbox((0.95 + g * 0.22, -0.55, G + 0.14), (0.03, 0.4, 0.28), (0, 0, 0), M['planks'])
    rbox((0.95, -0.75, G + 0.14), (0.44, 0.03, 0.28), (0, 0, 0), M['planks'])
    ellipsoid(0.95, -0.55, G + 0.18, 0.2, 0.17, 0.12, M['gravel'], seg=12, rings=8)
    ladder(M, (-0.75, -0.25, G), (-0.75, 0.05, G + 1.0))
    hut(M, -1.4, -0.9, -1.4, -0.75, G + 0.55, 'x', door=('e', -1.05), roof='roof2')
    mine_cart(M, 0.2, -0.8, 0.3)
    signpost(M, 0.55, -1.2, 's', 'pick')
    fir(M, 1.3, 1.25, 1.5)
    fir(M, 1.3, 0.55, 1.1, 'pine2')
    path([(-0.85, -1.05), (0.0, -1.1), (0.0, -1.48)], seed=14)


def sq5_kristall(M):
    """Fantasy: a crystal quarry — glowing veins in the rock, a cart on a short track."""
    dirt(M, 0.3, -0.4, 1.1, 0.9, 15, 'gravel')
    rock_mass(M, -0.35, 0.6, 2.2, 1.5, 1.2, seed=6, n=30, grass=False)
    cut_step(M, -0.75, 0.55, -0.05, 0.4, G, G + 0.45, top=None)
    rnd = random.Random(7)
    for i in range(16):
        x = rnd.uniform(-1.2, 0.5)
        y = rnd.uniform(-0.05, 1.0)
        z = G + (0.45 if y < 0.4 else rnd.uniform(0.5, 1.0))
        L = rnd.uniform(0.12, 0.3)
        tilt = (rnd.uniform(-0.6, 0.2), rnd.uniform(-0.5, 0.5), 0)
        ob = cyl(0, 0, 0, 0.04, 0.0, L, M['crystal'], seg=6, smooth=False)
        ob.location = (x, y, z - 0.02)
        ob.rotation_euler = tilt
    for x, y in ((0.15, -0.6), (0.4, -0.75)):
        for k in range(3):
            ob = cyl(0, 0, 0, 0.035, 0.0, 0.18 - k * 0.04, M['crystal'], seg=6, smooth=False)
            ob.location = (x + k * 0.04, y, G)
            ob.rotation_euler = (0.3 * (k - 1), 0.2, 0)
    rails(M, [(-0.4, -0.25), (0.6, -0.25), (1.48, 0.25)])
    mine_cart(M, 0.55, -0.25, 0.0, load='crystal')
    for x in (-0.9, 0.3):
        beam((x, -0.1, G), (x, -0.1, G + 0.6), 0.03, M['timber'])
        ellipsoid(x, -0.13, G + 0.58, 0.03, 0.03, 0.04, M['lamp'], seg=8, rings=6)
    lean_to(M, -1.4, -0.8, -1.35, -0.75, G + 0.5, G + 0.38, 's', 'roof2')
    F.barrel(M, -1.2, -1.15)
    signpost(M, 1.2, -0.75, 'e', 'crystal')
    fir(M, 1.3, 1.3, 1.4)
    path([(-0.6, -0.9), (0.3, -1.1), (0.0, -1.48)], seed=15)


# ══ LARGE QUARRY (5 x 4) ═════════════════════════════════════
def lq1_terrassen(M):
    """Terraced quarry: three benches into the hill, a treadwheel crane on the top one."""
    dirt(M, 0.0, -0.9, 2.2, 1.0, 16, 'gravel')
    rock_mass(M, -0.2, 1.3, 5.0, 1.6, 1.7, seed=8, n=40)
    cut_step(M, -2.0, 1.6, -0.3, 0.9, G, G + 0.45)
    cut_step(M, -1.6, 1.2, 0.2, 1.1, G + 0.45, G + 0.9)
    cut_step(M, -1.1, 0.7, 0.6, 1.3, G + 0.9, G + 1.35)
    treadwheel_crane(M, 0.9, 0.35, 1.5, (0.0, -1.0), 0.85, 0.2)
    for x in (-1.6, -1.2, -0.8):
        stone_block(M, x, 0.4, G + 0.45, (0.2, 0.14, 0.13), 0.1)
    ladder(M, (-1.85, -0.25, G), (-1.85, 0.15, G + 0.45))
    ladder(M, (-1.45, 0.25, G + 0.45), (-1.45, 0.62, G + 0.9))
    # an ox cart with a block
    rbox((-0.3, -1.1, G + 0.18), (0.55, 0.3, 0.04), (0, 0, 0), M['planks'])
    for x in (-0.45, -0.15):
        disc(M, (x, -1.1, G + 0.11), (0, 1, 0), 0.11, 0.34, 'timber')
    stone_block(M, -0.3, -1.1, G + 0.2, (0.24, 0.18, 0.16))
    beam((-0.05, -1.1, G + 0.18), (0.35, -1.1, G + 0.18), 0.03, M['timber'])
    ellipsoid(0.55, -1.1, G + 0.17, 0.18, 0.08, 0.09, M['ox'], seg=12, rings=8)
    ellipsoid(0.75, -1.1, G + 0.2, 0.06, 0.05, 0.05, M['ox'], seg=10, rings=6)
    for x in (0.45, 0.65):
        for g in (-1, 1):
            beam((x, -1.1 + g * 0.04, G), (x, -1.1 + g * 0.04, G + 0.1), 0.025, M['ox'])
    hut(M, -2.3, -1.4, -1.85, -1.05, G + 0.7, 'x', door=('e', -1.45),
        wins=[('s', -1.85, 'teal', True)], sign=('s', -1.55, 'pick'))
    block_stack(M, 1.6, -1.2, 4, 2, 3, seed=5)
    fir(M, 2.3, 1.6, 1.6)
    leafy(M, 2.3, -0.2, 1.2, 7)
    path([(-1.35, -1.45), (-0.8, -1.6), (-0.5, -1.98)], seed=16)


def lq2_stollen(M):
    """A hill with a timbered adit; a rail track to a tipping trestle and gravel heap."""
    dirt(M, 0.3, -0.7, 2.2, 1.2, 17, 'gravel')
    rock_mass(M, -1.1, 0.9, 2.8, 2.2, 1.6, seed=9, n=36)
    # the portal
    px, py = -0.35, -0.1
    rbox((px, py - 0.02, G + 0.3), (0.38, 0.04, 0.6), (0, 0, 0), M['dark'])
    for g in (-1, 1):
        beam((px + g * 0.22, py - 0.05, G), (px + g * 0.2, py - 0.05, G + 0.62), 0.06, M['timber'])
    beam((px - 0.3, py - 0.05, G + 0.64), (px + 0.3, py - 0.05, G + 0.64), 0.07, M['timber'])
    F.lantern(M, 's', py - 0.08, px + 0.3, G + 0.55)
    # track out of it, over a trestle, to the tip
    rails(M, [(px, py + 0.2), (px, -0.6), (1.3, -0.6)])
    for x in (0.5, 0.9, 1.3):
        for g in (-1, 1):
            beam((x, -0.6 + g * 0.12, G), (x, -0.6 + g * 0.08, G + 0.05), 0.04, M['timber'])
    mine_cart(M, 0.3, -0.6, 0.0)
    mine_cart(M, px, -0.35, 1.57)
    ellipsoid(1.65, -0.6, G, 0.45, 0.4, 0.35, M['gravel'], seg=20, rings=10)
    ellipsoid(1.6, -1.25, G, 0.3, 0.26, 0.2, M['rock'], seg=16, rings=8)
    # sorting shed + office
    lean_to(M, 0.9, 2.1, 0.5, 1.5, G + 0.72, G + 0.55, 'e', 'roof2')
    block_stack(M, 1.45, 1.0, 3, 2, 2, seed=6)
    hut(M, -2.3, -1.3, -1.8, -0.85, G + 0.72, 'y', door=('e', -1.15),
        wins=[('s', -1.8, 'red', True)], sign=('e', -1.5, 'pick'))
    F.barrel(M, -1.05, -0.65)
    F.crate(M, -0.95, -1.75, 0.13)
    fir(M, 2.3, 1.7, 1.6)
    fir(M, 0.6, 1.75, 1.3, 'pine2')
    path([(-1.15, -1.15), (-0.5, -1.5), (-0.5, -1.98)], seed=17)


def lq3_bauhuette(M):
    """The master mason's lodge: a long hall with an arcade, a crane, an arch template."""
    dirt(M, 0.3, -0.6, 2.2, 1.2, 18, 'gravel')
    zr = hut(M, -2.2, 0.6, 0.45, 1.65, G + 0.95, 'x', door=('s', -0.35),
             wins=[('s', -1.8, 'teal', True), ('s', -1.2, 'teal', False), ('s', 0.25, 'red', True),
                   ('e', 1.05, 'teal', True)], roof='roof', sign=('s', 0.45, 'hammer'))
    lean_to(M, -2.2, 0.6, -0.1, 0.45, G + 0.75, G + 0.55, 's', 'roof2')
    for x in (-1.6, -1.0, 0.0):
        rbox((x, 0.15, G + 0.22), (0.4, 0.22, 0.05), (0, 0, 0), M['planks'])
        stone_block(M, x, 0.15, G + 0.25, (0.15, 0.12, 0.1), 0.2)
    # a wooden arch centring with voussoirs on it
    ax, ay = 1.3, -0.5
    for k in range(9):
        a0, a1 = math.pi * k / 9, math.pi * (k + 1) / 9
        p0 = Vector((ax + math.cos(a0) * 0.45, ay, G + 0.35 + math.sin(a0) * 0.45))
        p1 = Vector((ax + math.cos(a1) * 0.45, ay, G + 0.35 + math.sin(a1) * 0.45))
        beam(p0, p1, 0.05, M['timber'])
        if k < 6:
            am = (a0 + a1) / 2
            rbox((ax + math.cos(am) * 0.52, ay, G + 0.35 + math.sin(am) * 0.52), (0.1, 0.14, 0.14),
                 (0, -(am - math.pi / 2), 0), M['rock_cut'])
    for g in (-1, 1):
        box(ax + g * 0.52, ay, G, 0.14, 0.16, 0.35, M['rock_cut'])
    crane(M, 1.75, 0.6, 1.4, (1.3, -0.1), 0.5)
    block_stack(M, -0.9, -1.3, 4, 2, 2, seed=7)
    block_stack(M, 0.3, -1.4, 3, 2, 3, seed=8)
    rock_mass(M, 2.0, 1.4, 1.0, 1.0, 0.75, seed=10, n=12)
    cyl(-1.8, -1.0, G, 0.08, 0.08, 0.5, M['rock_cut'], seg=16)
    cyl(-1.55, -1.1, G, 0.08, 0.08, 0.3, M['rock_cut'], seg=16)
    leafy(M, -2.25, -1.6, 1.1, 8)
    path([(-0.35, 0.3), (-0.3, -0.6), (-0.5, -1.0), (-0.5, -1.98)], seed=18)


def lq4_steinsaege(M):
    """A stone saw driven by a water wheel: a frame saw cutting a block into slabs."""
    dirt(M, 0.4, -0.6, 2.0, 1.2, 19, 'gravel')
    rock_mass(M, -1.35, 1.1, 2.3, 1.7, 1.4, seed=11, n=30)
    cut_step(M, -2.2, -0.4, 0.2, 0.75, G, G + 0.5)
    water_channel(M, 0.9, 1.4, -2.0, 2.0)
    wheel(M, (1.15, 0.6, G + 0.45), 0.45, 'x', n=14, width=0.18, paddles=True)
    # the open saw shed with a frame saw over a block
    lean_to(M, -0.2, 0.85, 0.05, 1.15, G + 0.9, G + 0.7, 'w', 'roof2')
    beam((0.85, 0.6, G + 0.45), (0.35, 0.6, G + 0.45), 0.05, M['iron'])
    beam((0.35, 0.6, G + 0.45), (0.3, 0.6, G + 0.65), 0.03, M['timber'])
    stone_block(M, 0.2, 0.6, None, (0.5, 0.36, 0.3))
    for g in (-0.25, 0.25):
        beam((0.2, 0.6 + g, G + 0.25), (0.2, 0.6 + g, G + 0.75), 0.04, M['timber'])
    beam((0.2, 0.35, G + 0.75), (0.2, 0.85, G + 0.75), 0.04, M['timber'])
    for k in range(3):
        rbox((0.08 + k * 0.12, 0.6, G + 0.4), (0.006, 0.5, 0.04), (0, 0, 0), M['iron'], bevel=0)
    # slabs leaning in racks
    for i in range(6):
        rbox((-0.5 + i * 0.07, -0.85, G + 0.17), (0.025, 0.35, 0.34), (0, 0.18, 0), M['rock_cut'])
    beam((-0.6, -0.85, G + 0.05), (0.0, -0.85, G + 0.05), 0.05, M['timber'])
    for i in range(4):
        rbox((-1.4 + i * 0.07, -1.05, G + 0.15), (0.025, 0.3, 0.3), (0, 0.2, 0), M['rock_cut'])
    hut(M, -2.35, -1.55, -1.8, -0.95, G + 0.72, 'x', door=('e', -1.4),
        wins=[('s', -1.95, 'red', True)], sign=('s', -1.65, 'block'))
    block_stack(M, 2.0, -0.9, 2, 3, 2, (0.22, 0.16, 0.14), seed=9)
    fir(M, 2.2, 1.6, 1.5)
    path([(-1.5, -1.4), (-0.6, -1.5), (-0.5, -1.98)], seed=19)


def lq5_riesenkopf(M):
    """Fantasy landmark: the cliff face is being carved into a giant head; scaffolds and ladders."""
    dirt(M, 0.2, -0.8, 2.2, 1.0, 20, 'gravel')
    rock_mass(M, -0.4, 1.2, 4.4, 1.6, 2.0, seed=12, n=36)
    hx, hy, hz = -0.5, 0.35, G + 1.05
    ellipsoid(hx, hy, hz, 0.7, 0.55, 0.95, M['rock_cut'], seg=24, rings=18)
    rbox((hx, hy - 0.5, hz + 0.0), (0.16, 0.2, 0.36), (0.35, 0, 0), M['rock_cut'])
    for g in (-1, 1):
        ellipsoid(hx + g * 0.24, hy - 0.45, hz + 0.25, 0.11, 0.06, 0.07, M['dark'], seg=12, rings=8)
        rbox((hx + g * 0.24, hy - 0.48, hz + 0.38), (0.28, 0.1, 0.06), (0, g * 0.15, 0), M['rock_cut'])
    rbox((hx, hy - 0.46, hz - 0.35), (0.34, 0.08, 0.05), (0, 0, 0), M['dark'])
    ellipsoid(hx, hy, hz + 0.9, 0.62, 0.5, 0.18, M['rock'], seg=16, rings=8)
    # scaffold on the right side of the face
    sx0, sx1 = 0.25, 1.05
    for x in (sx0, (sx0 + sx1) / 2, sx1):
        for y in (-0.1, 0.25):
            beam((x, y, G), (x, y, G + 1.6), 0.035, M['timber'])
    for z in (0.5, 1.0, 1.5):
        rbox(((sx0 + sx1) / 2, 0.075, G + z), (sx1 - sx0 + 0.1, 0.38, 0.03), (0, 0, 0), M['planks'])
        beam((sx0, -0.1, G + z + 0.2), (sx1, -0.1, G + z + 0.2), 0.02, M['timber'])
    ladder(M, (sx1 + 0.05, -0.05, G), (sx1 + 0.05, 0.2, G + 1.0))
    crane(M, 1.5, 0.6, 1.8, (0.9, 0.2), 1.05)
    for x in (-1.5, -1.1):
        stone_block(M, x, -0.4, None, (0.2, 0.16, 0.14), 0.3 * x)
    hut(M, -2.35, -1.45, -1.85, -1.0, G + 0.7, 'x', door=('e', -1.4),
        wins=[('s', -1.9, 'teal', True)], sign=('s', -1.55, 'hammer'))
    block_stack(M, 1.5, -1.25, 3, 2, 2, seed=11)
    wheelbarrow(M, 0.4, -0.75, 2.6, 'rock_cut')
    fir(M, 2.3, 1.6, 1.7)
    fir(M, 2.3, 0.8, 1.2, 'pine2')
    path([(-1.4, -1.4), (-0.6, -1.5), (-0.5, -1.98)], seed=20)


VARIANTS = {
    'sw1': (sw1_waldhuette, 3, 3), 'sw2': (sw2_holzmiete, 3, 3), 'sw3': (sw3_koehlerei, 3, 3),
    'sw4': (sw4_riesenstumpf, 3, 3), 'sw5': (sw5_saegegrube, 3, 3),
    'lw1': (lw1_wassersaege, 4, 4), 'lw2': (lw2_zimmerei, 4, 4), 'lw3': (lw3_holzhof, 4, 4),
    'lw4': (lw4_windsaege, 4, 4), 'lw5': (lw5_waldlodge, 4, 4),
    'sq1': (sq1_felsanbruch, 3, 3), 'sq2': (sq2_steinmetz, 3, 3), 'sq3': (sq3_findling, 3, 3),
    'sq4': (sq4_hangrutsche, 3, 3), 'sq5': (sq5_kristall, 3, 3),
    'lq1': (lq1_terrassen, 5, 4), 'lq2': (lq2_stollen, 5, 4), 'lq3': (lq3_bauhuette, 5, 4),
    'lq4': (lq4_steinsaege, 5, 4), 'lq5': (lq5_riesenkopf, 5, 4),
}
M_REF = {}


def main():
    global M_REF
    argv = sys.argv[sys.argv.index('--') + 1:]
    out = argv[0]
    which = argv[1:] or list(VARIANTS)
    os.makedirs(out, exist_ok=True)
    for key in which:
        fn, w, h = VARIANTS[key]
        rb.clear()
        K._mats.clear()
        F.reset_anims()
        random.seed(hash(key) & 0xffff)
        M = mats()
        M_REF = M
        K._mats_ref = M
        globals()['M_REF'] = M
        fn(M)
        # a turf plate the size of the footprint, so the yard reads
        box(0, 0, G - 0.04, w, h, 0.04, M['grass'], bevel=0.0)
        for o in bpy.data.objects:            # lower the yard to z = 0
            if o.parent is None:
                o.location.z -= G
        K.lighting()
        scale = 768 / ((w + h) * rb.TILE_W / 2)
        K.setup_render(24, scale, w, h, headroom=0.75)
        scene = bpy.context.scene
        scene.render.image_settings.file_format = 'WEBP'
        scene.render.image_settings.color_mode = 'RGBA'
        scene.render.image_settings.quality = 88
        scene.render.filepath = os.path.abspath(os.path.join(out, f'{key}.webp'))
        bpy.ops.render.render(write_still=True)
        print('wrote', key)


main()
