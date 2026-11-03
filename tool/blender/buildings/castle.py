"""The Castle: the settlement's heart, and the root of its road network.

Footprint 10 x 10 tiles (50 x 50 m) — tier S, the biggest thing on the map.

Reads as: the seat of power. A crenellated curtain wall with a round tower at
every corner, a gatehouse in the middle of every side (stone below, a
half-timbered storey above), banners on the walls, a tall keep (Bergfried)
with a timbered top and a tent roof, a timber-framed great hall (Palas) on a
stone ground floor, and a flag on a tall mast in the middle of the yard.

FOUR GATES (user 2026-11-03: "mehrere Tore … Punkte, wo die Strassen
ansetzen"): the road network starts in front of them and nowhere else on the
wall. They sit in a pinwheel — the south gate in the cell the guided intro
lays its first road in (kTutorialRoadX/Y: the Castle's x + 5, just below
it), the other three that one turned by 90 degrees — so one side of the wall
is modelled once and placed four times.

Moving: tower pennants, wall banners, the yard flag, bushes and flowers;
lanterns flicker at every gate, windows glow, the hall's chimney smokes.

The Castle does not turn (ROTATE = False): it is the same on all four sides
and there is only ever one.
"""
import math
import random

import bpy
from mathutils import Matrix, Vector

from fw_kit import *  # noqa: F401,F403
import pro_kit as K  # noqa: F401

ID = 'castle'
W, H = 10, 10
ROTATE = False
# Big enough to keep its detail on the map: the Castle spans 20 tile-widths
# where a house spans 4, so the usual 960 px would halve its sharpness.
SHIP_MAX_W = 2048
# wide and low: no minimum band of empty sky above it
HEADROOM = 0.5

WALL = 4.2                  # curtain wall centre line, from the middle
WALL_T = 0.5                # 2.5 m thick
WALL_TOP = G + 1.5          # 7.5 m
GATE_A = 0.5                # the south gate's x (one cell in from the middle)
TOWER_R = 0.75

# The south gate in the cell the intro's road goes to; the other three are it
# turned (x, y) -> (-y, x): east at y = +0.5, north at x = -0.5, west y = -0.5.
ENTRANCE = [('s', 5), ('e', 5), ('n', 4), ('w', 4)]

# the hall's chimney (smoke anchor)
PALAS = (-3.5, -1.0, 0.6, 3.5)          # x0, x1, y0, y1
CHIMNEY = (-2.25, 2.9, G + 4.28)


def materials():
    M = base_materials()
    M['banner'] = plain('banner', '#5b3f9e', rough=0.9, bump=0.2,
                        bump_scale=120, vary=0.04)
    M['banner2'] = plain('banner2', '#a8402c', rough=0.9, bump=0.2,
                         bump_scale=120, vary=0.04)
    M['roofcone'] = tex_mat('roofcone_c', 'clay_roof_tiles_02',
                            tint=(1.0, 0.82, 0.70), sat=1.1, val=1.1, nstr=1.5,
                            vary=0.05, uv_scale=(4.0, 1.4))
    M['water'] = plain('water', '#3d7fa6', rough=0.1, bump=0.0, vary=0.0)
    M['straw_dummy'] = plain('straw_dummy', '#d7b25a', rough=0.9, bump=0.3,
                             bump_scale=60, vary=0.1)
    return M


# ── turning what one side builds into the other three ──
def _turned(objs, quarter):
    """Turn freshly built objects about the castle's centre by quarter x 90
    degrees counter-clockwise (seen from above)."""
    if quarter % 4 == 0:
        return
    bpy.context.view_layer.update()
    R = Matrix.Rotation(math.radians(90 * quarter), 4, 'Z')
    for o in objs:
        o.matrix_world = R @ o.matrix_world


def _rot(p, quarter):
    x, y = p[0], p[1]
    for _ in range(quarter % 4):
        x, y = -y, x
    return (x, y) + tuple(p[2:])


# ── parts ──
def merlons(M, x0, x1, y, z, along='x', step=0.30, w=0.16, t=0.14, h=0.20):
    """A row of merlons (the teeth of a crenellation) on a wall top."""
    n = int((x1 - x0) / step)
    for i in range(n + 1):
        a = x0 + (x1 - x0) * i / max(n, 1)
        if along == 'x':
            box(a, y, z, w, t, h, M['stone'], bevel=0.008)
        else:
            box(y, a, z, t, w, h, M['stone'], bevel=0.008)


def curtain(M, x0, x1):
    """A stretch of the SOUTH curtain wall from x0 to x1 (canonical frame)."""
    y = -WALL
    L = x1 - x0
    xm = (x0 + x1) / 2
    box(xm, y, G, L, WALL_T + 0.08, 0.18, M['stone_dk'], bevel=0.01)
    box(xm, y, G + 0.18, L, WALL_T, WALL_TOP - G - 0.18, M['stone'], bevel=0.01)
    # a string course under the battlement, then the teeth on the outer edge
    box(xm, y - WALL_T / 2 + 0.02, WALL_TOP - 0.10, L, 0.08, 0.06,
        M['stone_dk'], bevel=0.004)
    merlons(M, x0 + 0.1, x1 - 0.1, y - WALL_T / 2 + 0.07, WALL_TOP)
    # a low parapet on the yard side
    box(xm, y + WALL_T / 2 - 0.04, WALL_TOP, L, 0.08, 0.10, M['stone'],
        bevel=0.006)


def round_tower(M, x, y, name):
    r = TOWER_R
    top = G + 2.4
    cyl(x, y, G, r + 0.06, r + 0.04, 0.2, M['stone_dk'], seg=28)
    cyl(x, y, G + 0.2, r, r * 0.95, top - G - 0.2, M['stone'], seg=28)
    cyl(x, y, top - 0.02, r * 0.98, r * 1.08, 0.12, M['stone_dk'], seg=28)
    for i in range(14):                       # crown of merlons
        a = 2 * math.pi * i / 14
        rbox((x + math.cos(a) * r * 1.02, y + math.sin(a) * r * 1.02, top + 0.2),
             (0.12, 0.16, 0.2), (0, 0, a), M['stone'], bevel=0.006)
    # arrow slits facing every way
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        for zc in (G + 0.9, G + 1.7):
            rbox((x + math.cos(a) * r * 0.97, y + math.sin(a) * r * 0.97, zc),
                 (0.05, 0.06, 0.24), (0, 0, a), M['pane'], bevel=0)
    # tent of tiles + gold finial
    cone_h, cone_r = 1.25, r * 1.18
    cyl(x, y, top + 0.1, cone_r, 0.02, cone_h, M['roofcone'], seg=28, uv=True)
    ellipsoid(x, y, top + 0.1 + cone_h + 0.06, 0.05, 0.05, 0.07, M['gold'],
              egg=0.2)
    # a pennant on a pole above the finial, hanging from a short arm
    pz = top + 0.1 + cone_h + 0.1
    beam((x, y, pz), (x, y, pz + 0.5), 0.025, M['timber'])
    beam((x, y, pz + 0.48), (x + 0.22, y, pz + 0.48), 0.02, M['timber'])
    return (x, y, pz + 0.48), name


def pennant(M, x, y, z, along, name, mat='banner'):
    """A cloth hanging from an arm, swaying from its top edge."""
    with anim(name, 'sway', pivot=(x, y, z), amp=0.35, period=2.2):
        if along == 'x':
            rbox((x, y, z - 0.17), (0.22, 0.02, 0.32), (0, 0, 0), M[mat], bevel=0.004)
        else:
            rbox((x, y, z - 0.17), (0.02, 0.22, 0.32), (0, 0, 0), M[mat], bevel=0.004)


def wall_banner(M, x, y, name, mat='banner'):
    """A long banner hung from the battlement on the wall's OUTER face."""
    z = WALL_TOP - 0.12
    beam((x - 0.2, y, z), (x + 0.2, y, z), 0.03, M['timber'])
    with anim(name, 'sway', pivot=(x, y - 0.02, z), amp=0.12, period=3.0):
        rbox((x, y - 0.02, z - 0.36), (0.32, 0.02, 0.66), (0, 0, 0), M[mat],
             bevel=0.004)
        ellipsoid(x, y - 0.04, z - 0.32, 0.08, 0.012, 0.08, M['gold'], seg=14,
                  rings=8)
        # a pointed foot
        tri_prism((x - 0.16, z - 0.69), (x + 0.16, z - 0.69), (x, z - 0.82),
                  y - 0.03, y - 0.01, M[mat], axis='x')


def gatehouse(M, side):
    """The SOUTH gatehouse (canonical frame): stone piers and a lintel round
    a passage, a half-timbered storey above, a gable roof whose ridge runs
    through the wall, open gate leaves, lanterns."""
    x0, x1 = GATE_A - 0.85, GATE_A + 0.85      # 8.5 m along the wall
    yo, yi = -WALL - 0.42, -WALL + 0.42        # outer and inner faces
    pw = 0.62                                  # passage 3.1 m wide
    pa, pb = GATE_A - pw / 2, GATE_A + pw / 2
    z_up = G + 1.30                            # stone up to here
    z_eave = G + 2.05
    # plinth + piers + lintel
    for a0, a1 in ((x0, pa), (pb, x1)):
        box((a0 + a1) / 2, (yo + yi) / 2, G, a1 - a0 + 0.06, yi - yo + 0.06,
            0.18, M['stone_dk'], bevel=0.01)
        box((a0 + a1) / 2, (yo + yi) / 2, G + 0.18, a1 - a0, yi - yo,
            z_up - G - 0.18, M['stone'], bevel=0.01)
    box(GATE_A, (yo + yi) / 2, G + 0.86, pw, yi - yo, z_up - G - 0.86,
        M['stone'], bevel=0.01)
    # voussoirs: a dark arch ring on both faces
    for yy in (yo - 0.01, yi + 0.01):
        for i in range(9):
            a = math.pi * i / 8
            px = GATE_A - math.cos(a) * (pw / 2 + 0.04)
            pz = G + 0.62 + math.sin(a) * 0.24
            rbox((px, yy, pz), (0.09, 0.05, 0.09), (0, a - math.pi / 2, 0),
                 M['stone_dk'], bevel=0.006)
    # the passage's own arch fill (round top) and cobbled floor
    cobble_path(M, [(GATE_A, yi + 0.05), (GATE_A, yo - 0.05)], seed=31 + side)
    # open gate leaves, swung inward against the passage walls
    for sgn in (-1, 1):
        hx = GATE_A + sgn * (pw / 2 - 0.03)
        rbox((hx, yi - 0.17, G + 0.40), (0.04, 0.32, 0.76), (0, 0, 0),
             M['planks'], bevel=0.004)
        for fz in (0.2, 0.6):
            box(hx - sgn * 0.025, yi - 0.17, G + 0.40 - 0.38 + fz * 0.76, 0.012,
                0.30, 0.03, M['iron'], bevel=0)
    # half-timbered upper storey, jettied out over the road
    j = DIM['jetty']
    ux0, ux1, uyo, uyi = x0 - 0.02, x1 + 0.02, yo - j, yi + j
    box((ux0 + ux1) / 2, (uyo + uyi) / 2, z_up, ux1 - ux0, uyi - uyo,
        z_eave - z_up, M['plaster'], bevel=0.008)
    beam((ux0, uyo, z_up + 0.02), (ux1, uyo, z_up + 0.02), 0.07, M['timber'])
    beam((ux0, uyi, z_up + 0.02), (ux1, uyi, z_up + 0.02), 0.07, M['timber'])
    win = DIM['window_up']
    zc = z_up + 0.36
    for face, fixed in (('s', uyo), ('n', uyi)):
        wall_frame(M, face, fixed, ux0, ux1, z_up + 0.045, z_eave - 0.03, 6,
                   braces=(0, 5), holes=[(GATE_A - 0.42, win[0]),
                                         (GATE_A + 0.42, win[0])])
        for a, sh, gl in ((GATE_A - 0.42, 'teal', True), (GATE_A + 0.42, 'red', False)):
            window(M, face, fixed, a, zc, *win, sh, glow=gl)
    for face, fixed in (('w', ux0), ('e', ux1)):
        wall_frame(M, face, fixed, uyo, uyi, z_up + 0.045, z_eave - 0.03, 3,
                   braces=(0, 2), holes=[((uyo + uyi) / 2, win[0])])
        window(M, face, fixed, (uyo + uyi) / 2, zc, *win, 'mustard', glow=True)
    # roof, ridge through the wall, gables to the road and to the yard
    gable_wall(M, 's', uyo, ux0, ux1, z_eave)
    gable_wall(M, 'n', uyi, ux0, ux1, z_eave)
    ridge = gable_roof(M, GATE_A, (uyo + uyi) / 2, z_eave, uyi - uyo, ux1 - ux0,
                       'y', M['roof'], oh=0.14, oe=0.15)
    ellipsoid(GATE_A, uyo - 0.15, ridge + 0.03, 0.05, 0.05, 0.07, M['gold'],
              egg=0.2)
    # lanterns either side of the road, outside and in
    for a in (pa - 0.12, pb + 0.12):
        lantern(M, 's', yo, a, G + 0.78)
        lantern(M, 'n', yi, a, G + 0.78)
    return x0, x1


def build():
    random.seed(23)
    M = materials()

    # ── one side, four times ──────────────────────────────
    for q in range(4):
        before = set(bpy.data.objects)
        gx0, gx1 = gatehouse(M, q)
        curtain(M, -WALL + TOWER_R * 0.6, gx0)
        curtain(M, gx1, WALL - TOWER_R * 0.6)
        tip, _ = round_tower(M, WALL, -WALL, f'tower{q}')
        # this side's road out of the gate, up to the entrance cell's edge,
        # and in to the yard's plaza
        cobble_path(M, [(GATE_A, -WALL - 0.47), (GATE_A, -H / 2)], seed=40 + q)
        cobble_path(M, [(GATE_A, -WALL + 0.47), (GATE_A, -1.0)], seed=50 + q)
        # banners either side of the gatehouse on the wall's outer face
        bx = (-2.0, 2.7)
        for i, x in enumerate(bx):
            p = _rot((x, -WALL - WALL_T / 2 - 0.02, 0), q)
            # built in the canonical frame, then turned with the rest — the
            # anim pivot is given already turned
            wall_banner(M, x, -WALL - WALL_T / 2 - 0.02, f'banner{q}{i}',
                        'banner' if i == 0 else 'banner2')
        new = [o for o in bpy.data.objects if o not in before]
        _turned(new, q)
        # pivots of this side's moving parts, turned the same way
        for spec in ANIMS:
            if spec['name'].startswith((f'banner{q}',)) and not spec.get('_turned'):
                spec['pivot'] = _rot(spec['pivot'], q)
                spec['_turned'] = True
        # the tower pennant: built after the turn, at the turned arm
        px, py, pz = _rot(tip, q)
        ax, ay, _ = _rot((tip[0] + 0.22, tip[1], 0), q)
        pennant(M, (px + ax) / 2 + (ax - px) * 0.0, (py + ay) / 2, pz,
                'x' if abs(ax - px) > abs(ay - py) else 'y', f'pennant{q}')

    # ── the yard ───────────────────────────────────────────
    # plaza where the four gate roads meet, the flag mast in its middle
    cobble_path(M, [(-0.9, 0.0), (0.9, 0.0)], seed=61, width=1.1)
    cobble_path(M, [(0.0, -0.9), (0.0, 0.9)], seed=62, width=0.6)
    cyl(0, 0, G, 0.24, 0.22, 0.10, M['stone_dk'], seg=16)
    cyl(0, 0, G + 0.10, 0.035, 0.03, 2.6, M['timber'], seg=10)
    ellipsoid(0, 0, G + 2.72, 0.05, 0.05, 0.05, M['gold'])
    beam((0, 0, G + 2.6), (0.5, 0, G + 2.6), 0.025, M['timber'])
    with anim('yard_flag', 'sway', pivot=(0.25, 0, G + 2.6), amp=0.25, period=2.6):
        rbox((0.27, 0, G + 2.6 - 0.32), (0.46, 0.02, 0.62), (0, 0, 0), M['banner'],
             bevel=0.004)
        ellipsoid(0.27, -0.015, G + 2.6 - 0.30, 0.10, 0.012, 0.10, M['gold'],
                  seg=14, rings=8)
    for i in range(8):
        a = 2 * math.pi * i / 8 + 0.4
        flower_patch(M, math.cos(a) * 0.55, math.sin(a) * 0.55, 3,
                     ['fl_red', 'fl_yel', 'fl_white'], 70 + i, rx=0.06, ry=0.06)

    palas(M)
    keep(M)
    stable(M)
    garden(M)


def palas(M):
    """The great hall, NW quarter: stone ground floor, two timbered storeys,
    its gable to the yard road, door onto the north gate's road."""
    x0, x1, y0, y1 = PALAS
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    z1, z2, z3 = G + 0.85, G + 1.55, G + 2.25
    box(xm, ym, G, x1 - x0 + 0.08, y1 - y0 + 0.08, 0.18, M['stone_dk'], bevel=0.01)
    box(xm, ym, G + 0.18, x1 - x0, y1 - y0, z1 - G - 0.18, M['stone'], bevel=0.01)
    box(xm, ym, z1, x1 - x0, y1 - y0, z3 - z1, M['plaster'], bevel=0.008)
    win, win_up = DIM['window'], DIM['window_up']
    door_w, door_h = DIM['door_wide']
    # ground floor: stone, deep windows; the door on the east face
    for face, fixed, a0, a1, n in (('s', y0, x0, x1, 3), ('n', y1, x0, x1, 3),
                                    ('e', x1, y0, y1, 4), ('w', x0, y0, y1, 4)):
        span = a1 - a0
        for i in range(n):
            a = a0 + span * (i + 0.5) / n
            if face == 'e' and i == 1:
                continue
            window(M, face, fixed, a, G + 0.52, *win, None, glow=i % 2 == 0)
        for st in (1, 2):
            zlo = z1 if st == 1 else z2
            zhi = z2 if st == 1 else z3
            holes = [(a0 + span * (i + 0.5) / n, win_up[0]) for i in range(n)]
            wall_frame(M, face, fixed, a0, a1, zlo + 0.045, zhi - 0.03, 2 * n,
                       braces=(0, 2 * n - 1), holes=holes)
            for i, (a, _w) in enumerate(holes):
                window(M, face, fixed, a, zlo + 0.36, *win_up,
                       ('teal', 'red', 'mustard')[(i + st) % 3],
                       glow=(i + st) % 2 == 0,
                       planter=['fl_red', 'fl_white'] if st == 1 and i % 2 else None)
    dy = y0 + (y1 - y0) * 1.5 / 4
    door(M, 'e', x1, dy, door_w, door_h, G + 0.18)
    rbox((x1 + 0.14, dy, G + 0.06), (0.24, door_w + 0.2, 0.12), (0, 0, 0),
         M['stone'], bevel=0.008)
    lantern(M, 'e', x1, dy + door_w / 2 + 0.12, G + 0.18 + door_h - 0.02)
    # roof: ridge along y, gables south (to the yard) and north
    gable_wall(M, 's', y0, x0, x1, z3)
    gable_wall(M, 'n', y1, x0, x1, z3)
    gable_roof(M, xm, ym, z3, y1 - y0, x1 - x0, 'y', M['roof'], oh=0.16, oe=0.17)
    for cy in (1.4, 2.9):
        chimney(M, -2.25, cy, G + 3.30, 0.85)       # clears the ridge
    # a short road from the north gate's road to the door
    cobble_path(M, [(x1 + 0.27, dy), (-0.5, dy)], seed=81)


def keep(M):
    """The Bergfried, NE quarter: the tallest thing in the settlement — a
    square stone tower, a timbered top storey, a tent roof and a banner."""
    cx, cy, s = 2.3, 2.5, 1.5
    top = G + 3.6
    box(cx, cy, G, s + 0.1, s + 0.1, 0.22, M['stone_dk'], bevel=0.012)
    box(cx, cy, G + 0.22, s, s, top - G - 0.22, M['stone'], bevel=0.012)
    # a ring of corbels under the jettied top
    for face in ('s', 'n', 'e', 'w'):
        fixed = {'s': cy - s / 2, 'n': cy + s / 2, 'e': cx + s / 2, 'w': cx - s / 2}[face]
        mid = cx if face in ('s', 'n') else cy
        for i in range(7):
            a = mid - s / 2 + 0.1 + (s - 0.2) * i / 6
            rbox(P(face, fixed, a, top - 0.06, 0.05), D(face, 0.06, 0.1, 0.1),
                 (0, 0, 0), M['stone_dk'], bevel=0.006)
        # slits up the shaft
        for zc in (G + 1.0, G + 2.0, G + 2.9):
            rbox(P(face, fixed, mid, zc, 0.0), D(face, 0.07, 0.03, 0.28),
                 (0, 0, 0), M['pane_glow' if zc > G + 2.5 else 'pane'], bevel=0)
    # timbered top storey
    j = 0.1
    t0, t1 = top, top + 0.72
    ts = s + 2 * j
    box(cx, cy, t0, ts, ts, t1 - t0, M['plaster'], bevel=0.008)
    win = DIM['window_up']
    for face in ('s', 'n', 'e', 'w'):
        fixed = {'s': cy - ts / 2, 'n': cy + ts / 2, 'e': cx + ts / 2, 'w': cx - ts / 2}[face]
        mid = cx if face in ('s', 'n') else cy
        wall_frame(M, face, fixed, mid - ts / 2, mid + ts / 2, t0 + 0.045, t1 - 0.03,
                   4, braces=(0, 3), holes=[(mid, win[0])])
        window(M, face, fixed, mid, t0 + 0.36, *win, 'red', glow=True)
    # tent roof: four tiled faces up to a point
    th = 1.5
    tent = cyl(0, 0, t1, ts * 0.76, 0.02, th, M['roofcone'], seg=4, uv=True,
               smooth=False)
    tent.location = (cx, cy, 0)                # built round the origin,
    tent.rotation_euler = (0, 0, math.radians(45))   # then squared to the tower
    ellipsoid(cx, cy, t1 + th + 0.06, 0.06, 0.06, 0.08, M['gold'], egg=0.2)
    # the castle's banner, from an arm off the roof's point
    pz = t1 + th + 0.12
    beam((cx, cy, pz), (cx, cy, pz + 0.7), 0.03, M['timber'])
    beam((cx, cy, pz + 0.68), (cx + 0.36, cy, pz + 0.68), 0.025, M['timber'])
    with anim('keep_banner', 'sway', pivot=(cx + 0.18, cy, pz + 0.68), amp=0.3,
              period=2.4):
        rbox((cx + 0.2, cy, pz + 0.68 - 0.26), (0.34, 0.02, 0.5), (0, 0, 0),
             M['banner'], bevel=0.004)
        ellipsoid(cx + 0.2, cy - 0.015, pz + 0.68 - 0.24, 0.08, 0.012, 0.08,
                  M['gold'], seg=14, rings=8)
    # its door, onto the east gate's road
    door(M, 's', cy - s / 2, cx - 0.35, *DIM['door'], G + 0.22)
    cobble_path(M, [(cx - 0.35, cy - s / 2 - 0.15), (cx - 0.35, 0.5)], seed=82)


def stable(M):
    """SE quarter: a timbered stable with hay, a well and the yard's stores."""
    x0, x1, y0, y1 = 1.4, 3.5, -3.55, -2.45
    zt = G + 0.95
    box((x0 + x1) / 2, (y0 + y1) / 2, G, x1 - x0 + 0.06, y1 - y0 + 0.06, 0.12,
        M['stone_dk'], bevel=0.01)
    box((x0 + x1) / 2, (y0 + y1) / 2, G + 0.12, x1 - x0, y1 - y0, zt - G - 0.12,
        M['plaster'], bevel=0.008)
    gate_w = DIM['gate'][0]
    for face, fixed, a0, a1, holes in (
            ('n', y1, x0, x1, [((x0 + x1) / 2, gate_w)]),
            ('s', y0, x0, x1, [(x0 + 0.5, DIM['window'][0]), (x1 - 0.5, DIM['window'][0])]),
            ('e', x1, y0, y1, [((y0 + y1) / 2, DIM['window'][0])]),
            ('w', x0, y0, y1, [((y0 + y1) / 2, DIM['window'][0])])):
        wall_frame(M, face, fixed, a0, a1, G + 0.12, zt - 0.03, 4 if face in 'ns' else 2,
                   braces=(0, 3) if face in 'ns' else (0, 1), holes=holes)
        for a, w in holes:
            if face == 'n':
                door(M, 'n', fixed, a, gate_w * 0.9, DIM['gate'][1] * 0.8, G + 0.12)
            else:
                window(M, face, fixed, a, G + 0.55, *DIM['window'], 'teal')
    gable_wall(M, 'e', x1, y0, y1, zt)
    gable_wall(M, 'w', x0, y0, y1, zt)
    gable_roof(M, (x0 + x1) / 2, (y0 + y1) / 2, zt, x1 - x0, y1 - y0, 'x',
               M['roof2'], oh=0.12, oe=0.13)
    hay_bale(M, 1.75, -2.15, G, 0.32, 0.22, 0.2, 0.2)
    hay_bale(M, 2.10, -2.10, G, 0.30, 0.22, 0.2, -0.3)
    hay_bale(M, 1.92, -2.12, G + 0.2, 0.30, 0.2, 0.18, 0.1)
    hay_scatter(M, 2.0, -2.0, 0.35, 50, 7)
    # the well
    wx, wy = 2.9, -1.3
    cyl(wx, wy, G, 0.26, 0.26, 0.24, M['stone'], seg=20)
    cyl(wx, wy, G + 0.235, 0.20, 0.20, 0.01, M['water'], seg=20)
    for sg in (-1, 1):
        beam((wx + sg * 0.22, wy, G + 0.235), (wx + sg * 0.22, wy, G + 0.62), 0.04,
             M['timber'])
    beam((wx - 0.26, wy, G + 0.60), (wx + 0.26, wy, G + 0.60), 0.035, M['timber'])
    rbox((wx, wy, G + 0.72), (0.56, 0.4, 0.03), (math.radians(20), 0, 0),
         M['roof2'], bevel=0.006)
    barrel(M, 3.45, -1.75)
    barrel(M, 3.55, -1.55, 0.075, 0.17)
    crate(M, 3.5, -2.05, 0.16, 0.2)
    sack(M, 3.25, -1.95, 1.0, 0.4)


def garden(M):
    """SW quarter: training dummies, a herb garden and bushes."""
    for i, (x, y) in enumerate(((-2.6, -2.2), (-1.9, -2.6), (-2.9, -3.0))):
        beam((x, y, G), (x, y, G + 0.36), 0.04, M['timber'])
        beam((x - 0.12, y, G + 0.28), (x + 0.12, y, G + 0.28), 0.035, M['timber'])
        ellipsoid(x, y, G + 0.24, 0.08, 0.06, 0.12, M['straw_dummy'], seg=10, rings=8)
        ellipsoid(x, y, G + 0.40, 0.055, 0.055, 0.06, M['straw_dummy'], seg=10, rings=8)
    for i, (x, y) in enumerate(((-3.3, -1.5), (-2.2, -1.4), (-3.0, -3.45),
                                (-1.2, -3.4))):
        bush(M, x, y, 0.2, 10 + i, ['fl_red', 'fl_white'] if i % 2 else None)
    for i, (x, y) in enumerate(((-2.7, -1.6), (-1.5, -2.0), (-1.4, -3.0))):
        flower_patch(M, x, y, 6, ['fl_pink', 'fl_yel', 'fl_blue'], 90 + i)
    # bushes along the hall and the keep
    bush(M, 0.6, 1.4, 0.16, 20, ['fl_white'])
    bush(M, 3.55, 1.6, 0.18, 21)
    bush(M, 0.2, 3.5, 0.15, 22, ['fl_pink'])
