"""The Gold Vault: a stone keep with a timber upper floor, tier B (4 x 4 tiles).

Chosen from the mockups (user 2026-11-04: "Goldtresor: 1", the keep with a
rampart).

Reads as: this is where the gold is kept, and it is guarded. A massive stone
keep with an iron-banded door guarded by two braziers; a rampart (Wehrgang)
with merlons runs round its top; on it stands a half-timbered upper floor with
glowing windows, reached by one long stair up the east wall; a stone tower with
a flag stands at the back corner. A coin on the sign, chests and a heap of gold
in the yard.

Moving parts: the flag waves; plants sway; the braziers, lanterns and the
glowing windows flicker by themselves.

Layout (x east, y north; the camera looks from +x/-y):

    tower (back, west)            upper floor on the rampart
    keep, door south (x = -0.5)   stair up the east wall
    braziers at the door, chests and the gold heap in the yard
              cobbled path from the door to the south cell
"""
import math

import bmesh
from mathutils import Vector

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F
import pro_kit as K

ID = 'gold_vault'
W, H = 4, 4
ENTRANCE = ('s', 1)                 # the south edge, x = -1.0 ... cell 1 = x -0.5
HEADROOM = 0.8

KX0, KX1, KY0, KY1 = -1.30, 0.70, 0.00, 1.70       # the stone keep
KT = G + 0.95                                      # its top, the rampart floor
SLAB = 0.05
TT = G + 1.70
RZ = KT + SLAB                                      # rampart walking level
TX0, TX1, TY0, TY1 = -1.55, -0.85, -0.25, 0.45      # the tower (front-left corner)

UX0, UX1, UY0, UY1 = -0.72, 0.42, 0.28, 1.30       # the upper floor
UE = RZ + 0.52                                      # its eave
DOOR_A = -0.5


def pyramid(M, cx, cy, z, half, h, mat):
    bm = bmesh.new()
    c = [bm.verts.new((cx + sx * half, cy + sy * half, z)) for sx, sy in
         ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    a = bm.verts.new((cx, cy, z + h))
    bm.faces.new(c[::-1])
    for i in range(4):
        bm.faces.new((c[i], c[(i + 1) % 4], a))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return K._put(K._mesh('pyramid', bm), mat, 0.004, False)


def merlons(M, x0, x1, y0, y1, z, step=0.2):
    for x0_, x1_, y_ in ((x0, x1, y0), (x0, x1, y1)):
        n = max(1, int(round((x1_ - x0_) / step)))
        for i in range(0, n + 1, 1):
            if i % 2 == 0:
                box(x0_ + (x1_ - x0_) * i / n, y_, z, 0.11, 0.07, 0.1, M['stone'], bevel=0.006)
    for y0_, y1_, x_ in ((y0, y1, x0), (y0, y1, x1)):
        n = max(1, int(round((y1_ - y0_) / step)))
        for i in range(1, n):
            if i % 2 == 0:
                box(x_, y0_ + (y1_ - y0_) * i / n, z, 0.07, 0.11, 0.1, M['stone'], bevel=0.006)


def quoins(M, x, y, z0, z1):
    """Alternating corner stones up a corner."""
    z = z0
    i = 0
    while z < z1 - 0.05:
        ox = 0.035 if i % 2 else -0.035
        box(x + ox, y + (0.035 if i % 2 else -0.035), z, 0.17, 0.17, 0.1, M['stone_dk'], bevel=0.008)
        z += 0.1
        i += 1


def slit(M, face, fixed, a, z, glow=True):
    rbox(P(face, fixed, a, z, 0.012), D(face, 0.12, 0.028, 0.27), (0, 0, 0), M['stone_dk'], bevel=0.004)
    rbox(P(face, fixed, a, z, 0.026), D(face, 0.05, 0.02, 0.2), (0, 0, 0),
         M['pane_glow'] if glow else M['dark'], bevel=0)


def brazier(M, x, y):
    cyl(x, y, G, 0.06, 0.045, 0.16, M['stone_dk'], seg=10)          # a stone pedestal
    cyl(x, y, G + 0.15, 0.07, 0.09, 0.06, M['iron'], seg=12)         # the bowl
    ellipsoid(x, y, G + 0.25, 0.06, 0.06, 0.08, M['lamp'], seg=10, rings=8)


def chest(M, x, y, rot=0.0, gold=True):
    rbox((x, y, G + 0.05), (0.19, 0.11, 0.1), (0, 0, rot), M['planks'], bevel=0.006)
    rbox((x, y, G + 0.115), (0.19, 0.11, 0.045), (0, 0, rot), M['timber'], bevel=0.012)
    for f in (-0.06, 0.06):
        c, s = math.cos(rot), math.sin(rot)
        rbox((x + f * c, y + f * s, G + 0.085), (0.018, 0.118, 0.13), (0, 0, rot), M['iron'], bevel=0)
    if gold:
        ellipsoid(x, y, G + 0.14, 0.07, 0.04, 0.03, M['gold'], seg=10, rings=6)


def gold_heap(M, x, y, r=0.16):
    ellipsoid(x, y, G + 0.03, r, r * 0.8, 0.05, M['gold'], seg=14, rings=8)
    import random
    rnd = random.Random(5)
    for _ in range(12):
        a = rnd.uniform(0, 6.28)
        d = rnd.uniform(0, r * 0.7)
        ellipsoid(x + math.cos(a) * d, y + math.sin(a) * d * 0.8, G + rnd.uniform(0.05, 0.1),
                  0.035, 0.03, 0.022, M['gold'], seg=8, rings=6)


def keep(M):
    xm, ym = (KX0 + KX1) / 2, (KY0 + KY1) / 2
    box(xm, ym, G, KX1 - KX0 + 0.1, KY1 - KY0 + 0.1, 0.13, M['stone_dk'], bevel=0.012)
    box(xm, ym, G + 0.13, KX1 - KX0, KY1 - KY0, KT - G - 0.13, M['stone'], bevel=0.01)
    box(xm, ym, KT, KX1 - KX0 + 0.14, KY1 - KY0 + 0.14, SLAB, M['stone_dk'], bevel=0.008)
    for x, y in ((KX0, KY0), (KX1, KY0), (KX1, KY1)):
        quoins(M, x, y, G + 0.13, KT)
    merlons(M, KX0 - 0.04, KX1 + 0.04, KY0 - 0.04, KY1 + 0.04, RZ)
    # the iron door in a stone surround, a lantern and a coin sign
    zpl = G + 0.13
    dw, dh = DIM['door_wide']
    box(DOOR_A, KY0 - 0.01, zpl + dh + 0.01, dw + 0.16, 0.1, 0.07, M['stone_dk'], bevel=0.008)
    F.door(M, 's', KY0, DOOR_A, dw, dh, zpl)
    for g in (-1, 1):
        F.lantern(M, 's', KY0, DOOR_A + g * (dw / 2 + 0.1), zpl + dh - 0.03)
    F.hanging_sign(M, 's', KY0, DOOR_A + 0.2, G + 0.80, emblem(M, 's', 'coin'), size=F.m(2.0))
    # arrow slits, lit from within
    for a, z, gl in ((-1.0, G + 0.62, True), (0.2, G + 0.62, True), (0.55, G + 0.62, False)):
        slit(M, 's', KY0, a, z, gl)
    for a in (0.4, 0.95, 1.4):
        slit(M, 'e', KX1, a, G + 0.62, a == 0.95)
    for a in (-1.0, -0.4, 0.2):
        slit(M, 'n', KY1, a, G + 0.62, a != -0.4)
    for a in (0.4, 0.95, 1.4):
        slit(M, 'w', KX0, a, G + 0.62, a != 0.95)


def stair(M):
    """One long stair up the east wall, a stone parapet on its outer side."""
    x0, x1 = KX1 + 0.02, KX1 + 0.34
    y0, y1, n = -0.30, 1.35, 12
    dy = (y1 - y0) / n
    rise = RZ - G
    for i in range(n):
        top = (i + 1) * rise / n
        box((x0 + x1) / 2, y0 + dy * (i + 0.5), G, x1 - x0, dy + 0.004, top, M['stone'], bevel=0.004)
        box(x1 - 0.02, y0 + dy * (i + 0.5), G + top - 0.005, 0.045, dy + 0.004, 0.1,
            M['stone_dk'], bevel=0.004)


def upper_floor(M):
    xm, ym = (UX0 + UX1) / 2, (UY0 + UY1) / 2
    z0 = RZ
    box(xm, ym, z0, UX1 - UX0, UY1 - UY0, UE - z0, M['plaster'], bevel=0.008)
    faces = {'s': (UY0, UX0, UX1), 'n': (UY1, UX0, UX1), 'e': (UX1, UY0, UY1), 'w': (UX0, UY0, UY1)}
    wins = [('s', -0.45, 'mustard', True), ('s', 0.05, 'mustard', True), ('n', -0.2, 'teal', False),
            ('w', 0.78, 'teal', True), ('e', 0.5, 'mustard', True)]
    holes = {f: [] for f in faces}
    holes['e'].append((0.95, DIM['door'][0]))
    for f, a, *_ in wins:
        holes[f].append((a, DIM['window'][0]))
    for f, (fx, a0, a1) in faces.items():
        nb = max(2, round((a1 - a0) / 0.28))
        F.wall_frame(M, f, fx, a0, a1, z0, UE, nb, braces=(0, nb - 1), holes=holes[f])
    F.door(M, 'e', UX1, 0.95, *DIM['door'], z0)
    F.lantern(M, 'e', UX1, 1.11, z0 + DIM['door'][1] - 0.02)
    for f, a, shut, glow in wins:
        F.window(M, f, faces[f][0], a, z0 + 0.28, *DIM['window'], shut, glow)
    F.gable_wall(M, 'e', UX1, UY0, UY1, UE)
    F.gable_wall(M, 'w', UX0, UY0, UY1, UE)
    return F.gable_roof(M, xm, ym, UE, UX1 - UX0, UY1 - UY0, 'x', M['roof'], oh=0.1, oe=0.1)


def tower(M):
    xm, ym = (TX0 + TX1) / 2, (TY0 + TY1) / 2
    box(xm, ym, G, TX1 - TX0 + 0.1, TY1 - TY0 + 0.1, 0.13, M['stone_dk'], bevel=0.012)
    box(xm, ym, G + 0.13, TX1 - TX0, TY1 - TY0, TT - G - 0.13, M['stone'], bevel=0.01)
    box(xm, ym, TT, TX1 - TX0 + 0.14, TY1 - TY0 + 0.14, SLAB, M['stone_dk'], bevel=0.008)
    for x, y in ((TX0, TY0), (TX1, TY0), (TX0, TY1), (TX1, TY1)):
        quoins(M, x, y, G + 0.13, TT)
    slit(M, 'w', TX0, 0.1, G + 1.1)
    slit(M, 's', TY0, -1.2, G + 1.1)
    slit(M, 'n', TY1, -1.2, G + 1.1, False)
    slit(M, 'w', TX0, 0.1, G + 0.5, False)
    slit(M, 's', TY0, -1.2, G + 0.5, False)
    # the timber lantern room and its pyramid roof
    zr = TT + SLAB
    rx0, rx1, ry0, ry1 = TX0 + 0.09, TX1 - 0.09, TY0 + 0.09, TY1 - 0.09
    zt = zr + 0.36
    box((rx0 + rx1) / 2, (ry0 + ry1) / 2, zr, rx1 - rx0, ry1 - ry0, zt - zr, M['plaster'], bevel=0.008)
    faces = {'s': (ry0, rx0, rx1), 'n': (ry1, rx0, rx1), 'e': (rx1, ry0, ry1), 'w': (rx0, ry0, ry1)}
    for f, (fx, a0, a1) in faces.items():
        F.wall_frame(M, f, fx, a0, a1, zr, zt, 2, braces=(0,),
                     holes=[((a0 + a1) / 2, DIM['window_small'][0])])
        F.window(M, f, fx, (a0 + a1) / 2, zr + 0.18, *DIM['window_small'], 'red', True)
    cx, cy = (rx0 + rx1) / 2, (ry0 + ry1) / 2
    pyramid(M, cx, cy, zt, (rx1 - rx0) / 2 + 0.07, 0.42, M['roof2'])
    # the flag
    beam((cx, cy, zt + 0.4), (cx, cy, zt + 0.72), 0.014, M['timber'])
    with F.anim('flag', 'sway', pivot=(cx, cy, zt + 0.7), amp=0.18, period=1.6):
        rbox((cx + 0.1, cy, zt + 0.64), (0.19, 0.012, 0.1), (0, 0, 0), M['red'], bevel=0)
        rbox((cx + 0.1, cy, zt + 0.64), (0.07, 0.016, 0.07), (0, 0, 0.785), M['gold'], bevel=0)
    return zt


def build():
    M = mats()
    keep(M)
    stair(M)
    zt_up = upper_floor(M)
    tower(M)

    # ── the yard ──────────────────────────────────────────
    ex, ey = F.entrance_point(W, H, *ENTRANCE)
    F.cobble_path(M, [(DOOR_A, KY0 - 0.14), (DOOR_A, -1.0), (ex, ey + 0.02)], seed=7)
    dirt(M, 0.35, -0.85, 1.25, 0.8, 5)
    brazier(M, DOOR_A - 0.40, -0.45)
    brazier(M, DOOR_A + 0.45, -0.45)
    chest(M, 0.38, -0.55, 0.3)
    chest(M, 0.62, -0.78, -0.2)
    chest(M, 0.45, -0.35, 0.1, gold=False)
    gold_heap(M, 1.25, -0.9)
    sack(M, 1.05, -0.55)
    sack(M, 1.18, -0.42)
    F.barrel(M, -1.5, -0.3, r=0.075, h=0.18)
    F.crate(M, -1.45, -0.55, 0.13)
    F.crate(M, -1.0, -1.05, 0.12, rot=0.3)
    stone_block(M, -1.3, -1.2, s=(0.17, 0.13, 0.1), rot=0.4)
    # the banner post in the yard
    beam((-1.7, -0.95, G), (-1.7, -0.95, G + 0.7), 0.025, M['timber'])
    with F.anim('banner', 'sway', pivot=(-1.7, -0.95, G + 0.68), amp=0.15, period=1.9):
        rbox((-1.7, -0.95 + 0.0, G + 0.5), (0.012, 0.16, 0.3), (0, 0, 0), M['red'], bevel=0)
        rbox((-1.7, -0.95, G + 0.5), (0.016, 0.07, 0.07), (0.785, 0, 0), M['gold'], bevel=0)
    for x, y, h, k in ((-1.8, -1.7, 1.25, 'pine2'), (1.8, 1.8, 1.4, 'pine'), (1.85, -1.6, 1.0, 'pine2')):
        fir(M, x, y, h, k)
    F.bush(M, 0.1, -0.2, 0.1, 3, ['fl_white'])
    F.flower_patch(M, -0.9, -1.5, 5, ['fl_yel', 'fl_red'], 6)
