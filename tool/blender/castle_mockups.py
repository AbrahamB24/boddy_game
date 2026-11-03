"""Ten Castle concepts, quick smooth renders for choosing one.

    blender --background --python tool/blender/castle_mockups.py -- <out_dir> [n ...]

User 2026-11-03: "Die Burg ist mir noch zu langweilig. Gib mir 10 Mockups" —
and in every one the roads run in through the four gates to an assembly
square in the middle. Built from buildings/castle.py's parts plus one idea
each; smooth (not voxelised) and low-sample, they are sketches to pick from.
"""
import math
import os
import random
import sys

import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fw_kit as F  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
from buildings import castle as C  # noqa: E402

G = K.G


# ── shared pieces ──────────────────────────────────────────
def mats():
    M = C.materials()
    M['water2'] = F.plain('water2', '#4a8fb5', rough=0.05, bump=0.08, bump_scale=30)
    M['fire'] = F.plain('fire', '#ffb347', emit='#ff7a1a', emit_strength=14, bump=0)
    M['crystal'] = F.plain('crystal', '#8fe3ff', rough=0.1, emit='#4fc8ff',
                           emit_strength=6, bump=0)
    M['rune'] = F.plain('rune', '#7a7fa8', rough=0.6, bump=0.3, bump_scale=50)
    M['bark'] = F.tex_mat('bark', 'dark_wood', 0.6, tint=(0.8, 0.62, 0.48), val=0.8)
    M['dragon'] = F.plain('dragon', '#3f5e46', rough=0.5, bump=0.4, bump_scale=40,
                          speck='#2c4433')
    M['bronze'] = F.plain('bronze', '#8a6a3a', rough=0.35, metal=1.0, bump=0)
    M['awn_r'] = F.plain('awn_r', '#c8463a', rough=0.9, bump=0.2)
    M['awn_b'] = F.plain('awn_b', '#4f7fc4', rough=0.9, bump=0.2)
    M['awn_y'] = F.plain('awn_y', '#e0b13a', rough=0.9, bump=0.2)
    M['awn_g'] = F.plain('awn_g', '#5c9a4a', rough=0.9, bump=0.2)
    M['slate'] = F.plain('slate', '#4a5560', rough=0.7, bump=0.4, bump_scale=60)
    return M


def ring(M, tower=None, wall_top=None, gates=True):
    """Curtain wall, four gatehouses and four corner pieces, one side built
    and turned four times — as buildings/castle.py does."""
    tower = tower or (lambda M, q: C.round_tower(M, C.WALL, -C.WALL, f't{q}')[0])
    for q in range(4):
        before = set(bpy.data.objects)
        gx0, gx1 = C.gatehouse(M, q) if gates else (C.GATE_A - 0.3, C.GATE_A + 0.3)
        C.curtain(M, -C.WALL + C.TOWER_R * 0.6, gx0)
        C.curtain(M, gx1, C.WALL - C.TOWER_R * 0.6)
        tip = tower(M, q)
        F.cobble_path(M, [(C.GATE_A, -C.WALL - 0.47), (C.GATE_A, -5.0)], seed=40 + q)
        F.cobble_path(M, [(C.GATE_A, -C.WALL + 0.47), (C.GATE_A, -1.0)], seed=50 + q)
        new = [o for o in bpy.data.objects if o not in before]
        C._turned(new, q)


def plaza(M, centre=True):
    """The assembly square: paving where the four roads meet."""
    F.cobble_path(M, [(-1.2, 0.0), (1.2, 0.0)], seed=61, width=1.5)
    F.cobble_path(M, [(0.0, -1.2), (0.0, 1.2)], seed=62, width=1.0)
    if centre:
        F.cyl(0, 0, G, 0.24, 0.22, 0.10, M['stone_dk'], seg=16)
        F.cyl(0, 0, G + 0.10, 0.035, 0.03, 2.6, M['timber'], seg=10)
        F.rbox((0.27, 0, G + 2.28), (0.46, 0.02, 0.62), (0, 0, 0), M['banner'])


def fountain(M, x=0, y=0, r=0.55):
    F.cyl(x, y, G, r, r, 0.16, M['stone'], seg=28)
    F.cyl(x, y, G + 0.155, r - 0.06, r - 0.06, 0.01, M['water2'], seg=28)
    F.cyl(x, y, G + 0.16, 0.12, 0.10, 0.45, M['stone'], seg=16)
    F.cyl(x, y, G + 0.58, 0.28, 0.24, 0.06, M['stone'], seg=20)
    F.cyl(x, y, G + 0.635, 0.22, 0.22, 0.01, M['water2'], seg=20)
    F.ellipsoid(x, y, G + 0.78, 0.06, 0.06, 0.12, M['bronze'])


def stall(M, x, y, rot, awn):
    c, s = math.cos(rot), math.sin(rot)
    for dx, dy in ((-0.18, -0.12), (0.18, -0.12), (-0.18, 0.12), (0.18, 0.12)):
        px, py = x + dx * c - dy * s, y + dx * s + dy * c
        F.beam((px, py, G), (px, py, G + 0.42), 0.025, M['timber'])
    F.rbox((x, y, G + 0.18), (0.40, 0.18, 0.04), (0, 0, rot), M['planks'])
    F.rbox((x, y, G + 0.47), (0.46, 0.34, 0.03), (0.25, 0, rot), M[awn])
    for i, k in enumerate(('awn_y', 'egg', 'awn_g')):
        F.ellipsoid(x + (i - 1) * 0.1 * c, y + (i - 1) * 0.1 * s, G + 0.23, 0.04,
                    0.04, 0.03, M[k] if k in M else M['sack'])


def brazier(M, x, y, h=0.35):
    F.beam((x, y, G), (x, y, G + h), 0.04, M['iron'])
    F.cyl(x, y, G + h, 0.08, 0.10, 0.06, M['iron'], seg=12)
    F.ellipsoid(x, y, G + h + 0.10, 0.07, 0.07, 0.11, M['fire'], egg=0.5)


def fw_house(M, x, y, w, d, floors=2, axis='x', roof='roof', seed=0):
    """A small timber-framed house, all four sides framed."""
    rnd = random.Random(seed)
    z0 = G + F.DIM['plinth']
    zt = z0 + 0.62 * floors
    F.box(x, y, G, w + 0.04, d + 0.04, z0 - G, M['stone_dk'], bevel=0.008)
    F.box(x, y, z0, w, d, zt - z0, M['plaster'], bevel=0.006)
    win = F.DIM['window']
    for face, fixed, a0, a1 in (('s', y - d / 2, x - w / 2, x + w / 2),
                                ('n', y + d / 2, x - w / 2, x + w / 2),
                                ('e', x + w / 2, y - d / 2, y + d / 2),
                                ('w', x - w / 2, y - d / 2, y + d / 2)):
        for f in range(floors):
            zl, zh = z0 + 0.62 * f, z0 + 0.62 * (f + 1)
            mid = (a0 + a1) / 2
            F.wall_frame(M, face, fixed, a0, a1, zl + 0.02, zh - 0.02, 2,
                         braces=(0, 1), holes=[(mid, win[0])])
            F.window(M, face, fixed, mid, zl + 0.33, *win,
                     rnd.choice(['teal', 'red', 'mustard']), glow=rnd.random() < 0.5)
    if axis == 'x':
        F.gable_wall(M, 'e', x + w / 2, y - d / 2, y + d / 2, zt)
        F.gable_wall(M, 'w', x - w / 2, y - d / 2, y + d / 2, zt)
        F.gable_roof(M, x, y, zt, w, d, 'x', M[roof], oh=0.1, oe=0.1)
    else:
        F.gable_wall(M, 's', y - d / 2, x - w / 2, x + w / 2, zt)
        F.gable_wall(M, 'n', y + d / 2, x - w / 2, x + w / 2, zt)
        F.gable_roof(M, x, y, zt, d, w, 'y', M[roof], oh=0.1, oe=0.1)


def spire_tower(M, x, y, r, h, cone=1.4, mat='roofcone'):
    F.cyl(x, y, G, r + 0.05, r + 0.03, 0.18, M['stone_dk'], seg=24)
    F.cyl(x, y, G + 0.18, r, r * 0.95, h - 0.18, M['stone'], seg=24)
    for i in range(6):
        a = 2 * math.pi * i / 6
        F.rbox((x + math.cos(a) * r * 0.97, y + math.sin(a) * r * 0.97, G + h * 0.7),
               (0.04, 0.05, 0.2), (0, 0, a), M['pane_glow'], bevel=0)
    F.cyl(x, y, G + h, r * 1.12, 0.015, cone, M[mat], seg=24, uv=True)
    F.ellipsoid(x, y, G + h + cone + 0.05, 0.04, 0.04, 0.06, M['gold'])
    F.beam((x, y, G + h + cone + 0.05), (x, y, G + h + cone + 0.45), 0.02, M['timber'])
    F.rbox((x + 0.12, y, G + h + cone + 0.35), (0.22, 0.015, 0.14), (0, 0, 0), M['banner'])


# ── the ten ────────────────────────────────────────────────
def v1_wasserburg(M):
    """Moat all round, a drawbridge at every gate."""
    ring(M)
    for q in range(4):
        before = set(bpy.data.objects)
        F.box(0, -4.75, G - 0.06, 9.9, 0.42, 0.05, M['water2'], bevel=0)
        F.box(0, -4.53, G - 0.08, 9.9, 0.06, 0.12, M['stone_dk'], bevel=0)
        F.box(0, -4.97, G - 0.08, 9.9, 0.06, 0.12, M['stone_dk'], bevel=0)
        F.rbox((C.GATE_A, -4.78, G + 0.02), (0.62, 0.55, 0.05), (0, 0, 0), M['planks'])
        for sg in (-1, 1):
            F.beam((C.GATE_A + sg * 0.3, -4.55, G + 0.02),
                   (C.GATE_A + sg * 0.3, -4.5, G + 0.9), 0.015, M['iron'])
        C._turned([o for o in bpy.data.objects if o not in before], q)
    plaza(M, centre=False)
    fountain(M)
    C.palas(M)
    C.keep(M)


def v2_marktburg(M):
    """A market on the assembly square: stalls, a fountain, a town hall."""
    ring(M)
    plaza(M, centre=False)
    fountain(M, r=0.45)
    for i, (x, y, rot, a) in enumerate(((-1.3, 1.2, 0.0, 'awn_r'), (1.3, 1.2, 0.0, 'awn_b'),
                                       (-1.3, -1.2, math.pi, 'awn_y'),
                                       (1.3, -1.2, math.pi, 'awn_g'),
                                       (1.6, -0.0, math.pi / 2, 'awn_r'),
                                       (-1.6, 0.0, -math.pi / 2, 'awn_b'))):
        stall(M, x, y, rot, a)
    C.palas(M)
    # a town hall with a clock tower where the keep was
    fw_house(M, 2.4, 2.4, 2.0, 1.4, floors=3, axis='x', seed=3)
    F.box(1.6, 2.4, G, 0.6, 0.6, 3.0, M['stone'], bevel=0.01)
    F.cyl(1.6, 2.4, G + 3.0, 0.45, 0.02, 1.1, M['slate'], seg=4)
    F.ellipsoid(1.6, 2.1, G + 2.6, 0.16, 0.02, 0.16, M['gold'])


def v3_turmkrone(M):
    """Everything reaches up: tall towers, spires, a crowned keep."""
    def tall(M, q):
        spire_tower(M, C.WALL, -C.WALL, 0.8, 3.0, cone=1.8)
    ring(M, tower=tall)
    plaza(M)
    C.palas(M)
    cx, cy = 2.3, 2.5
    F.box(cx, cy, G, 1.6, 1.6, 4.6, M['stone'], bevel=0.012)
    for dx, dy in ((-0.8, -0.8), (0.8, -0.8), (-0.8, 0.8), (0.8, 0.8)):
        F.cyl(cx + dx, cy + dy, G + 3.6, 0.28, 0.28, 1.4, M['stone'], seg=16)
        F.cyl(cx + dx, cy + dy, G + 5.0, 0.32, 0.01, 1.0, M['roofcone'], seg=16, uv=True)
    F.cyl(cx, cy, G + 4.6, 0.95, 0.01, 2.2, M['roofcone'], seg=24, uv=True)
    F.beam((cx, cy, G + 6.8), (cx, cy, G + 7.4), 0.03, M['timber'])
    F.rbox((cx + 0.25, cy, G + 7.2), (0.46, 0.02, 0.3), (0, 0, 0), M['banner'])


def v4_doppelring(M):
    """A second, inner ring round the square, arches where the roads pass."""
    ring(M)
    plaza(M)
    for q in range(4):
        before = set(bpy.data.objects)
        for a0, a1 in ((-2.6, C.GATE_A - 0.45), (C.GATE_A + 0.45, 2.6)):
            F.box((a0 + a1) / 2, -2.6, G, a1 - a0, 0.32, 0.95, M['stone'], bevel=0.01)
            C.merlons(M, a0 + 0.1, a1 - 0.1, -2.72, G + 0.95)
        F.box(C.GATE_A, -2.6, G + 0.7, 0.9, 0.34, 0.35, M['stone_dk'], bevel=0.01)
        spire_tower(M, 2.6, -2.6, 0.38, 1.6, cone=0.9)
        C._turned([o for o in bpy.data.objects if o not in before], q)
    C.keep(M)


def v5_drachenhort(M):
    """A dragon on the square, fire in braziers at every gate."""
    ring(M)
    plaza(M, centre=False)
    d = M['dragon']
    F.cyl(0, 0, G, 0.6, 0.6, 0.18, M['stone_dk'], seg=24)
    F.ellipsoid(0, 0, G + 0.55, 0.42, 0.28, 0.32, d)                 # body
    F.beam((0.25, 0, G + 0.7), (0.55, -0.1, G + 1.35), 0.17, d)      # neck
    F.ellipsoid(0.62, -0.12, G + 1.45, 0.2, 0.11, 0.11, d)           # head
    for sg in (-1, 1):
        F.beam((0.66, -0.12 + sg * 0.06, G + 1.52), (0.5, -0.12 + sg * 0.1, G + 1.75),
               0.03, M['stone'])                                     # horns
        F.rbox((-0.05, sg * 0.55, G + 1.05), (0.7, 0.04, 0.55),
               (sg * 0.7, 0, 0.2), d)                                # wings
    F.beam((-0.35, 0, G + 0.45), (-0.9, 0.4, G + 0.2), 0.12, d)      # tail
    F.ellipsoid(0.82, -0.12, G + 1.42, 0.09, 0.05, 0.05, M['fire'])
    for q in range(4):
        x, y = C._rot((C.GATE_A + 0.55, -C.WALL + 0.7, 0), q)[:2]
        brazier(M, x, y)
        x, y = C._rot((C.GATE_A - 0.55, -C.WALL + 0.7, 0), q)[:2]
        brazier(M, x, y)
    C.palas(M)
    C.keep(M)


def v6_magierturm(M):
    """A mage's tower in place of the keep; a crystal hangs above it."""
    ring(M)
    plaza(M)
    C.palas(M)
    cx, cy = 2.3, 2.5
    spire_tower(M, cx, cy, 0.75, 4.2, cone=1.2, mat='slate')
    for k in range(3):
        F.cyl(cx, cy, G + 1.2 + k * 1.2, 0.80, 0.80, 0.06, M['rune'], seg=24)
    F.cyl(cx, cy, G + 6.3, 0.30, 0.0, 0.5, M['crystal'], seg=6)
    F.cyl(cx, cy, G + 5.8, 0.0, 0.30, 0.5, M['crystal'], seg=6)
    for i in range(5):
        a = 2 * math.pi * i / 5
        F.rbox((cx + math.cos(a) * 1.0, cy + math.sin(a) * 1.0, G + 5.2 + 0.3 * math.sin(a)),
               (0.14, 0.08, 0.2), (0.3, 0.2, a), M['rune'])
        F.ellipsoid(cx + math.cos(a) * 1.0, cy + math.sin(a) * 1.0,
                    G + 5.45 + 0.3 * math.sin(a), 0.03, 0.03, 0.03, M['crystal'])
    for q in range(4):
        x, y = C._rot((C.GATE_A, -1.6, 0), q)[:2]
        F.cyl(x, y, G, 0.12, 0.10, 0.5, M['rune'], seg=8)
        F.ellipsoid(x, y, G + 0.58, 0.06, 0.06, 0.08, M['crystal'])


def v7_baumburg(M):
    """An ancient tree in the middle of the square."""
    ring(M)
    plaza(M, centre=False)
    F.cyl(0, 0, G, 0.75, 0.75, 0.18, M['stone'], seg=28)
    F.cyl(0, 0, G + 0.18, 0.32, 0.22, 1.8, M['bark'], seg=16)
    for a in (0.3, 2.2, 4.1):
        F.beam((0, 0, G + 1.4), (math.cos(a) * 0.8, math.sin(a) * 0.8, G + 2.2),
               0.12, M['bark'])
        F.beam((0, 0, G + 0.3), (math.cos(a + 1) * 0.65, math.sin(a + 1) * 0.65, G + 0.05),
               0.1, M['bark'])
    rnd = random.Random(4)
    for i in range(14):
        a = rnd.uniform(0, 6.28)
        d = rnd.uniform(0.0, 1.1)
        r = rnd.uniform(0.45, 0.7)
        F.ellipsoid(math.cos(a) * d, math.sin(a) * d, G + 2.3 + rnd.uniform(0, 0.6),
                    r, r, r * 0.75, M['leaf' if i % 2 else 'leaf2'], seg=14, rings=10)
    for i in range(10):
        a = 2 * math.pi * i / 10
        F.ellipsoid(math.cos(a) * 1.0, math.sin(a) * 1.0, G + 2.0, 0.04, 0.04, 0.06,
                    M['lamp'])
    C.palas(M)
    C.keep(M)


def v8_wehrdorf(M):
    """A walled little town: timber houses lining the roads to the square."""
    ring(M)
    plaza(M)
    rnd = random.Random(8)
    spots = [(-1.6, 1.8), (-2.9, 1.8), (-1.6, 3.2), (-2.9, 3.2), (1.6, 1.6), (3.0, 1.6),
             (1.6, 3.1), (3.0, 3.1), (-1.6, -1.7), (-2.9, -1.7), (-2.9, -3.1),
             (1.7, -1.7), (3.0, -1.7), (3.0, -3.1)]
    for i, (x, y) in enumerate(spots):
        fw_house(M, x, y, rnd.uniform(0.9, 1.15), rnd.uniform(0.8, 1.0),
                 floors=rnd.choice([1, 2, 2]), axis=rnd.choice('xy'),
                 roof=rnd.choice(['roof', 'roof2']), seed=i)
    # the chapel with its steeple in the last quarter
    fw_house(M, -1.7, -3.1, 1.1, 0.8, floors=2, axis='x', seed=99)
    F.box(1.7, -3.1, G, 0.5, 0.5, 2.4, M['stone'], bevel=0.01)
    F.cyl(1.7, -3.1, G + 2.4, 0.38, 0.01, 1.4, M['slate'], seg=4)


def v9_kathedrale(M):
    """A great church with a bell tower as the castle's landmark."""
    ring(M)
    plaza(M)
    C.palas(M)
    x0, x1, y0, y1 = 1.0, 3.6, 1.4, 3.0
    F.box((x0 + x1) / 2, (y0 + y1) / 2, G, x1 - x0, y1 - y0, 1.5, M['stone'], bevel=0.01)
    for i in range(5):
        x = x0 + 0.3 + i * 0.5
        F.rbox((x, y0 - 0.01, G + 0.9), (0.14, 0.03, 0.7), (0, 0, 0), M['pane_glow'])
        F.box(x + 0.25, y0 - 0.06, G, 0.1, 0.12, 1.5, M['stone_dk'], bevel=0.008)
    F.gable_roof(M, (x0 + x1) / 2, (y0 + y1) / 2, G + 1.5, x1 - x0, y1 - y0, 'x',
                 M['slate'], oh=0.1, oe=0.1, pitch=58)
    F.box(1.0, 2.2, G, 0.8, 0.8, 3.6, M['stone'], bevel=0.01)
    F.ellipsoid(1.0, 1.79, G + 2.8, 0.24, 0.02, 0.24, M['pane_glow'])
    F.cyl(1.0, 2.2, G + 3.6, 0.6, 0.01, 2.0, M['slate'], seg=4)
    F.ellipsoid(1.0, 2.2, G + 5.7, 0.06, 0.06, 0.1, M['gold'])


def v10_sternfestung(M):
    """Pointed bastions instead of round towers, cannons on the walls."""
    def bastion(M, q):
        x, y = C.WALL, -C.WALL
        F.rbox((x, y, G + 0.7), (1.5, 1.5, 1.4), (0, 0, math.radians(45)), M['stone'],
               bevel=0.012)
        F.rbox((x, y, G + 1.43), (1.6, 1.6, 0.08), (0, 0, math.radians(45)),
               M['stone_dk'], bevel=0.008)
        for i, (dx, dy) in enumerate(((0.55, 0.0), (0.0, -0.55))):
            F.beam((x + dx, y + dy, G + 1.55), (x + dx * 1.5, y + dy * 1.5, G + 1.6),
                   0.07, M['iron'])
            F.rbox((x + dx, y + dy, G + 1.5), (0.18, 0.12, 0.08), (0, 0, 0), M['planks'])
        F.beam((x, y, G + 1.45), (x, y, G + 2.3), 0.025, M['timber'])
        F.rbox((x + 0.13, y, G + 2.15), (0.24, 0.015, 0.16), (0, 0, 0), M['banner'])
    ring(M, tower=bastion)
    plaza(M)
    C.palas(M)
    C.keep(M)
    for i in range(3):
        F.rbox((1.4 + i * 0.35, -2.2, G + 0.12), (0.22, 0.22, 0.24), (0, 0, 0.3 * i),
               M['planks'])
        F.ellipsoid(1.4 + i * 0.35, -2.6, G + 0.08, 0.07, 0.07, 0.07, M['iron'])


# -- second pass: the first five of these read as the plain castle with a
#    garnish; each now has ONE big thing of its own --------------------------
def v2_marktburg(M):
    """A timbered market hall on the square, big coloured stalls round it."""
    ring(M)
    plaza(M, centre=False)
    x0, x1, y0, y1 = -0.85, 0.85, -0.55, 0.55
    zf, zt = G + 0.62, G + 1.25
    for i in range(5):
        for y in (y0, y1):
            x = x0 + (x1 - x0) * i / 4
            F.beam((x, y, G), (x, y, zf), 0.07, M['timber'])
    for x in (x0, x1):
        F.beam((x, (y0 + y1) / 2, G), (x, (y0 + y1) / 2, zf), 0.07, M['timber'])
    F.box(0, 0, zf, x1 - x0 + 0.1, y1 - y0 + 0.1, zt - zf, M['plaster'], bevel=0.006)
    for face, fixed, a0, a1 in (('s', y0 - 0.05, x0 - 0.05, x1 + 0.05),
                                ('n', y1 + 0.05, x0 - 0.05, x1 + 0.05),
                                ('e', x1 + 0.05, y0 - 0.05, y1 + 0.05),
                                ('w', x0 - 0.05, y0 - 0.05, y1 + 0.05)):
        F.wall_frame(M, face, fixed, a0, a1, zf + 0.02, zt - 0.02, 4, braces=(0, 1, 2, 3))
    F.gable_roof(M, 0, 0, zt, x1 - x0 + 0.1, y1 - y0 + 0.1, 'x', M['roof'], oh=0.15, oe=0.15)
    F.box(0.0, 0.0, zt + 0.95, 0.24, 0.24, 0.45, M['timber'])
    F.cyl(0.0, 0.0, zt + 1.4, 0.2, 0.01, 0.45, M['slate'], seg=4)
    F.ellipsoid(0.0, -0.13, zt + 1.15, 0.09, 0.015, 0.09, M['gold'])
    for x, y, rot, a in ((-1.6, 1.25, 0.0, 'awn_r'), (1.6, 1.25, 0.0, 'awn_b'),
                         (-1.6, -1.25, math.pi, 'awn_y'), (1.6, -1.25, math.pi, 'awn_g'),
                         (1.9, 0.35, math.pi / 2, 'awn_r'), (-1.9, -0.35, -math.pi / 2, 'awn_b')):
        before = set(bpy.data.objects)
        stall(M, 0, 0, rot, a)
        bpy.context.view_layer.update()
        S = Matrix.Translation((x, y, G)) @ Matrix.Scale(1.7, 4) @ Matrix.Translation((0, 0, -G))
        for o in [o for o in bpy.data.objects if o not in before]:
            o.matrix_world = S @ o.matrix_world
    C.palas(M)
    C.keep(M)


def v4_doppelring(M):
    """A tall inner ring round the square with its own gate towers."""
    ring(M)
    plaza(M)
    for q in range(4):
        before = set(bpy.data.objects)
        for a0, a1 in ((-2.4, C.GATE_A - 0.5), (C.GATE_A + 0.5, 2.4)):
            F.box((a0 + a1) / 2, -2.4, G, a1 - a0, 0.36, 1.3, M['stone'], bevel=0.01)
            C.merlons(M, a0 + 0.1, a1 - 0.1, -2.53, G + 1.3)
        F.box(C.GATE_A, -2.4, G + 0.85, 1.0, 0.38, 0.45, M['stone_dk'], bevel=0.01)
        for sg in (-1, 1):
            spire_tower(M, C.GATE_A + sg * 0.62, -2.4, 0.26, 1.9, cone=0.8)
        spire_tower(M, 2.4, -2.4, 0.42, 2.2, cone=1.0)
        C._turned([o for o in bpy.data.objects if o not in before], q)
    F.box(1.2, 1.2, G, 1.0, 1.0, 3.4, M['stone'], bevel=0.012)
    F.cyl(1.2, 1.2, G + 3.4, 0.78, 0.01, 1.4, M['roofcone'], seg=4, uv=True)


def v5_drachenhort(M):
    """A great dragon on the square, wings spread, fire in its jaws."""
    ring(M)
    plaza(M, centre=False)
    d = M['dragon']
    s = 2.2
    b = G + 0.25
    F.cyl(0, 0, G, 0.9, 0.9, 0.25, M['stone_dk'], seg=28)
    F.ellipsoid(0, 0, b + 0.3 * s, 0.42 * s, 0.28 * s, 0.32 * s, d)
    F.beam((0.25 * s, 0, b + 0.42 * s), (0.6 * s, -0.1 * s, b + 1.0 * s), 0.17 * s, d)
    F.ellipsoid(0.68 * s, -0.12 * s, b + 1.1 * s, 0.2 * s, 0.11 * s, 0.11 * s, d)
    for sg in (-1, 1):
        F.beam((0.7 * s, (-0.12 + sg * 0.06) * s, b + 1.17 * s),
               (0.52 * s, (-0.12 + sg * 0.12) * s, b + 1.42 * s), 0.035 * s, M['stone'])
        F.rbox((-0.05 * s, sg * 0.62 * s, b + 0.95 * s), (0.8 * s, 0.03 * s, 0.6 * s),
               (sg * 0.75, 0, 0.25), d)
        F.beam((0.1 * s, sg * 0.15 * s, b), (0.15 * s, sg * 0.2 * s, b + 0.35 * s), 0.09 * s, d)
    F.beam((-0.35 * s, 0, b + 0.25 * s), (-1.0 * s, 0.45 * s, G + 0.3), 0.12 * s, d)
    F.cyl(0.95 * s, -0.12 * s, b + 1.0 * s, 0.03 * s, 0.14 * s, 0.6, M['fire'], seg=12)
    for q in range(4):
        for dx in (0.6, -0.6):
            x, y = C._rot((C.GATE_A + dx, -C.WALL + 0.75, 0), q)[:2]
            brazier(M, x, y, h=0.5)
    C.palas(M)
    C.keep(M)


def v7_baumburg(M):
    """An ancient tree whose crown spans half the yard."""
    ring(M)
    plaza(M, centre=False)
    F.cyl(0, 0, G, 0.95, 0.95, 0.2, M['stone'], seg=32)
    F.cyl(0, 0, G + 0.2, 0.62, 0.42, 3.0, M['bark'], seg=20)
    for a in (0.2, 1.3, 2.4, 3.5, 4.6, 5.6):
        F.beam((0, 0, G + 2.4), (math.cos(a) * 1.5, math.sin(a) * 1.5, G + 3.6), 0.2, M['bark'])
        F.beam((0, 0, G + 0.5), (math.cos(a + 0.5) * 1.1, math.sin(a + 0.5) * 1.1, G + 0.05),
               0.16, M['bark'])
    rnd = random.Random(4)
    for i in range(34):
        a = rnd.uniform(0, 6.28)
        dd = rnd.uniform(0.0, 1.9)
        r = rnd.uniform(0.55, 0.9)
        F.ellipsoid(math.cos(a) * dd, math.sin(a) * dd, G + 3.6 + rnd.uniform(0, 1.0),
                    r, r, r * 0.75, M['leaf' if i % 2 else 'leaf2'], seg=14, rings=10)
    for i in range(14):
        a = 2 * math.pi * i / 14
        x, y = math.cos(a) * 1.6, math.sin(a) * 1.6
        F.beam((x, y, G + 3.4), (x, y, G + 3.1), 0.01, M['iron'])
        F.ellipsoid(x, y, G + 3.05, 0.05, 0.05, 0.07, M['lamp'])
    C.palas(M)
    C.keep(M)


def v10_sternfestung(M):
    """Arrowhead bastions jutting from every corner, guns on the walls."""
    def bastion(M, q):
        x, y = C.WALL + 0.15, -C.WALL - 0.15
        r45 = math.radians(45)
        F.rbox((x, y, G + 0.85), (1.75, 1.75, 1.7), (0, 0, r45), M['stone'], bevel=0.014)
        F.rbox((x, y, G + 0.12), (1.95, 1.95, 0.24), (0, 0, r45), M['stone_dk'], bevel=0.01)
        F.rbox((x, y, G + 1.74), (1.83, 1.83, 0.09), (0, 0, r45), M['stone_dk'], bevel=0.008)
        for dx, dy in ((0.95, -0.95), (0.5, -1.15), (1.15, -0.5)):
            F.beam((x + dx * 0.55, y + dy * 0.55, G + 1.88),
                   (x + dx * 0.8, y + dy * 0.8, G + 1.92), 0.08, M['iron'])
            F.rbox((x + dx * 0.5, y + dy * 0.5, G + 1.84), (0.2, 0.2, 0.1), (0, 0, r45),
                   M['planks'])
        F.cyl(x + 0.95, y - 0.95, G + 1.2, 0.17, 0.2, 0.8, M['stone'], seg=12)
        F.cyl(x + 0.95, y - 0.95, G + 2.0, 0.24, 0.01, 0.4, M['slate'], seg=12)
        F.beam((x, y, G + 1.78), (x, y, G + 2.8), 0.03, M['timber'])
        F.rbox((x + 0.17, y, G + 2.6), (0.32, 0.015, 0.22), (0, 0, 0), M['banner'])
    ring(M, tower=bastion)
    plaza(M)
    C.palas(M)
    C.keep(M)
    for i in range(4):
        F.rbox((1.4 + i * 0.4, -2.0, G + 0.12), (0.24, 0.24, 0.24), (0, 0, 0.3 * i), M['planks'])
        F.ellipsoid(1.45 + i * 0.4, -2.5, G + 0.08, 0.08, 0.08, 0.08, M['iron'])


VARIANTS = [v1_wasserburg, v2_marktburg, v3_turmkrone, v4_doppelring, v5_drachenhort,
            v6_magierturm, v7_baumburg, v8_wehrdorf, v9_kathedrale, v10_sternfestung]


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    out = argv[0]
    which = [int(a) for a in argv[1:]] or list(range(1, 11))
    os.makedirs(out, exist_ok=True)
    for n in which:
        rb.clear()
        K._mats.clear()
        F.reset_anims()
        random.seed(n)
        M = mats()
        VARIANTS[n - 1](M)
        for o in bpy.data.objects:            # lower the yard to z = 0
            if o.parent is None:
                o.location.z -= G
        K.lighting()
        K.setup_render(20, 2, 10, 10, headroom=0.5)
        K.render(os.path.join(out, f'castle_mock_{n:02d}.png'))


main()
