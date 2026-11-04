"""The Castle: the settlement's heart, and the root of its road network.

Footprint 10 x 10 tiles (50 x 50 m) — tier S, the biggest thing on the map.

Reads as: the seat of power. A Wasserburg (concept 1): a moat with a
drawbridge at every gate, a crenellated curtain wall with a round tower at
every corner, gatehouses of stone with a half-timbered storey, banners on
the walls. Inside, round the assembly square with its fountain: the great
hall (Palas), the keep (Bergfried) — and the GARRISON (user 2026-11-03: "mehr
militärische Gebäude im Innenhof und weniger Wohngebäude"): the barracks
with the company's shields, the armory, the weapon smith's forge under the
south wall, a training ground with straw dummies and archery butts, and a
trebuchet with its pile of stones.

FOUR GATES (user 2026-11-03: "mehrere Tore … Punkte, wo die Strassen
ansetzen"): the road network starts in front of them and nowhere else on the
wall. They sit in a pinwheel — the south gate in the cell the guided intro
lays its first road in (kTutorialRoadX/Y: the Castle's x + 5, just below
it), the other three that one turned by 90 degrees — so one side of the wall
is modelled once and placed four times.

Moving: tower pennants, wall banners, bushes and flowers;
lanterns flicker at every gate, windows glow, the hall's chimney smokes.

It turns like every other building (user 2026-11-03: "die Burg sollte
drehbar sein"): the walls are the same on all four sides, the yard is not.
"""
import math
import random

import bpy
from mathutils import Matrix, Vector

from fw_kit import *  # noqa: F401,F403
import pro_kit as K  # noqa: F401

ID = 'castle'
W, H = 10, 10
# Big enough to keep its detail on the map: the Castle spans 20 tile-widths
# where a house spans 4, so the usual 960 px would halve its sharpness.
SHIP_MAX_W = 2048
# wide and low: no minimum band of empty sky above it
HEADROOM = 0.5
# Monsters walk in through the gates to the square (user 2026-11-03), along
# these walkways: from every gate straight in to the square's four cells. A
# building with walkways also ships a depth map (depth_pass.py), so a monster
# inside is hidden by exactly what stands in front of it.
WALKWAY_TO = [(4, 4), (5, 4), (4, 5), (5, 5)]

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
    M['slate'] = plain('slate', '#4a5560', rough=0.7, bump=0.4, bump_scale=60)
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
    # The roof stands BEHIND the battlement (user 2026-11-03: "die Zinnen
    # schauen durch das Dach"): a narrower drum rises inside the merlons and
    # the cone sits on it, above them and no wider than their inner face, so
    # the wall walk stays open round it.
    drum_r = r * 0.78
    drum_top = top + 0.55                     # merlons end at top + 0.30
    cyl(x, y, top, drum_r, drum_r, drum_top - top, M['stone'], seg=24)
    cyl(x, y, drum_top - 0.04, drum_r * 1.04, drum_r * 1.04, 0.06, M['stone_dk'],
        seg=24)
    cone_h, cone_r = 1.35, r * 0.94           # inside the merlons' inner face
    cyl(x, y, drum_top, cone_r, 0.02, cone_h, M['roofcone'], seg=28, uv=True)
    ellipsoid(x, y, drum_top + cone_h + 0.06, 0.05, 0.05, 0.07, M['gold'],
              egg=0.2)
    # a pennant on a pole above the finial, hanging from a short arm
    pz = drum_top + cone_h + 0.1
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
    # The passage's cobbled floor ends INSIDE the gate (user 2026-11-03: "es
    # hat Gehwegplatten auf dem Holz der Zugbrücke"): a cobble reaches up to
    # 0.11 past its path's end, so the path stops that far in, and a stone
    # threshold fills the rest up to the bridge, which stops at the gate.
    cobble_path(M, [(GATE_A, yi + 0.05), (GATE_A, yo + 0.16)], seed=31 + side)
    box(GATE_A, yo + 0.075, G, pw - 0.02, 0.15, 0.03, M['stone_dk'], bevel=0.004)
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
        moat_side(M)
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

    # ── the yard: the square, the lord's hall and keep, the garrison ──
    plaza(M)
    palas(M)
    keep(M)
    garrison(M)


# ── the moat (user 2026-11-03: the Wasserburg, concept 1) ──
def moat_side(M):
    """The SOUTH stretch of the moat (canonical frame), between the wall and
    the edge of the footprint, and the drawbridge over it at the gate."""
    y0, y1 = -H / 2 + 0.03, -WALL - WALL_T / 2 - 0.06     # outer edge, wall foot
    ym = (y0 + y1) / 2
    box(0, ym, G - 0.14, W - 0.06, y1 - y0, 0.11, M['water'], bevel=0)
    box(0, y1 + 0.02, G - 0.16, W - 0.06, 0.05, 0.16, M['stone_dk'], bevel=0.004)
    box(0, y0 - 0.02, G - 0.16, W - 0.06, 0.05, 0.18, M['stone_dk'], bevel=0.004)
    # the bridge: planks on two beams, chains up to the gatehouse; it ends
    # at the gate's outer face, where the stone threshold begins
    bw = 0.62
    ye = -WALL - 0.42 - 0.005
    for sg in (-1, 1):
        beam((GATE_A + sg * bw * 0.38, y0 - 0.03, G - 0.01),
             (GATE_A + sg * bw * 0.38, ye, G - 0.01), 0.05, M['timber'])
    n = 7
    for i in range(n):
        y = y0 + (ye - y0) * (i + 0.5) / n
        rbox((GATE_A, y, G + 0.025), (bw, (ye - y0) / n * 0.92, 0.03), (0, 0, 0),
             M['planks'], bevel=0.003)
    for sg in (-1, 1):
        beam((GATE_A + sg * bw * 0.46, y0 + 0.05, G + 0.04),
             (GATE_A + sg * bw * 0.46, -WALL - 0.44, G + 0.95), 0.014, M['iron'],
             bevel=0)
        beam((GATE_A + sg * bw * 0.46, y0 + 0.02, G),
             (GATE_A + sg * bw * 0.46, y0 + 0.02, G + 0.12), 0.04, M['timber'])


def plaza(M):
    """The assembly square where the four gate roads meet, a fountain in it."""
    cobble_path(M, [(-1.2, 0.0), (1.2, 0.0)], seed=61, width=1.5)
    cobble_path(M, [(0.0, -1.0), (0.0, 1.0)], seed=62, width=1.0)
    r = 0.55
    cyl(0, 0, G, r, r, 0.16, M['stone'], seg=28)
    cyl(0, 0, G + 0.15, r - 0.06, r - 0.06, 0.012, M['water'], seg=28)
    cyl(0, 0, G + 0.16, 0.12, 0.10, 0.45, M['stone'], seg=16)
    cyl(0, 0, G + 0.58, 0.28, 0.24, 0.06, M['stone'], seg=20)
    cyl(0, 0, G + 0.635, 0.22, 0.22, 0.01, M['water'], seg=20)
    ellipsoid(0, 0, G + 0.78, 0.06, 0.06, 0.12, M['gold'], egg=0.2)
    for i in range(4):
        a = math.pi / 4 + math.pi / 2 * i
        x, y = math.cos(a) * 0.95, math.sin(a) * 0.95
        rbox((x, y, G + 0.09), (0.36, 0.1, 0.035), (0, 0, a + math.pi / 2),
             M['planks'], bevel=0.004)                        # benches
        for sg in (-1, 1):
            px = x + math.cos(a + math.pi / 2) * sg * 0.13
            py = y + math.sin(a + math.pi / 2) * sg * 0.13
            box(px, py, G, 0.03, 0.08, 0.075, M['timber'], bevel=0)
    for i in range(4):
        a = math.pi / 4 + math.pi / 2 * i
        flower_patch(M, math.cos(a) * 1.25, math.sin(a) * 1.25, 4,
                     ['fl_red', 'fl_yel', 'fl_white', 'fl_pink'], 70 + i,
                     rx=0.08, ry=0.08)


# ── the garrison (user 2026-11-03: "mehr militärische Gebäude im Innenhof
# und weniger Wohngebäude") ──
def shield(M, face, fixed, a, z, mat, r=0.08):
    """A round shield hung flat on a wall, a gold boss in its middle."""
    c = P(face, fixed, a, z, 0.03)
    b = P(face, fixed, a, z, 0.06)
    if face in ('s', 'n'):
        ellipsoid(c.x, c.y, c.z, r, 0.018, r, M[mat], seg=18, rings=10)
        ellipsoid(b.x, b.y, b.z, 0.025, 0.016, 0.025, M['gold'], seg=10, rings=6)
    else:
        ellipsoid(c.x, c.y, c.z, 0.018, r, r, M[mat], seg=18, rings=10)
        ellipsoid(b.x, b.y, b.z, 0.016, 0.025, 0.025, M['gold'], seg=10, rings=6)


def weapon_rack(M, x, y, along='x', n=4):
    """Two posts, two rails, spears leaning on the top rail."""
    L = 0.42

    def pt(a, b, z):
        return (x + a, y + b, z) if along == 'x' else (x + b, y + a, z)
    for sg in (-1, 1):
        beam(pt(sg * L / 2, 0, G), pt(sg * L / 2, 0, G + 0.30), 0.028, M['timber'])
    beam(pt(-L / 2, 0, G + 0.27), pt(L / 2, 0, G + 0.27), 0.022, M['timber'])
    beam(pt(-L / 2, 0, G + 0.07), pt(L / 2, 0, G + 0.07), 0.022, M['timber'])
    for i in range(n):
        a = -L / 2 + L * (i + 0.5) / n
        beam(pt(a, -0.07, G + 0.005), pt(a, 0.022, G + 0.52), 0.013, M['timber'])
        tip = pt(a, 0.026, G + 0.56)
        ellipsoid(*tip, 0.013, 0.013, 0.04, M['iron'], seg=8, rings=6)


def barracks(M):
    """The Kaserne, SW quarter: the garrison's quarters — a long stone ground
    floor with a timbered storey on it, two doors onto the west gate's road,
    the company's shields hung between them."""
    x0, x1, y0, y1 = -3.45, -0.75, -2.35, -1.0
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    z1, z2 = G + 0.80, G + 1.46
    box(xm, ym, G, x1 - x0 + 0.06, y1 - y0 + 0.06, 0.14, M['stone_dk'], bevel=0.008)
    box(xm, ym, G + 0.14, x1 - x0, y1 - y0, z1 - G - 0.14, M['stone'], bevel=0.008)
    box(xm, ym, z1, x1 - x0, y1 - y0, z2 - z1, M['plaster'], bevel=0.006)
    win, win_up = DIM['window'], DIM['window_up']
    dw, dh = DIM['door']
    doors = (1, 3)
    for face, fixed, a0, a1, n in (('s', y0, x0, x1, 5), ('n', y1, x0, x1, 5),
                                    ('e', x1, y0, y1, 2), ('w', x0, y0, y1, 2)):
        span = a1 - a0
        spots = [a0 + span * (i + 0.5) / n for i in range(n)]
        for i, a in enumerate(spots):
            if face == 'n' and i in doors:
                door(M, face, fixed, a, dw, dh, G + 0.14)
                st = P(face, fixed, a, G + 0.03, 0.09)
                rbox((st.x, st.y, G + 0.035), D(face, dw + 0.12, 0.16, 0.07),
                     (0, 0, 0), M['stone'], bevel=0.006)
                lantern(M, face, fixed, a + dw / 2 + 0.07, G + 0.14 + dh - 0.02)
            else:
                window(M, face, fixed, a, G + 0.50, *win, None, glow=i % 2 == 1)
        if face in ('n', 's'):
            for i in range(n - 1):
                shield(M, face, fixed, (spots[i] + spots[i + 1]) / 2, G + 0.50,
                       'banner' if i % 2 == 0 else 'banner2')
        wall_frame(M, face, fixed, a0, a1, z1 + 0.045, z2 - 0.03, 2 * n,
                   braces=(0, 2 * n - 1), holes=[(a, win_up[0]) for a in spots])
        for i, a in enumerate(spots):
            window(M, face, fixed, a, z1 + 0.36, *win_up,
                   ('red', 'teal')[i % 2], glow=i % 3 == 0)
    gable_wall(M, 'e', x1, y0, y1, z2)
    gable_wall(M, 'w', x0, y0, y1, z2)
    ridge = gable_roof(M, xm, ym, z2, x1 - x0, y1 - y0, 'x', M['roof'],
                       oh=0.12, oe=0.12)
    chimney(M, x0 + 0.55, ym + 0.2, ridge - 0.38, 0.5)
    chimney(M, x1 - 0.55, ym + 0.2, ridge - 0.38, 0.5)
    # the spears for the morning muster, by the east gable
    weapon_rack(M, -0.32, -1.75, 'y')


def armory(M):
    """The Zeughaus, NE quarter beside the keep: two storeys of stone with
    only slits for windows, a timbered gable, an iron-studded double door
    under a shield and two crossed swords."""
    x0, x1, y0, y1 = -0.15, 1.15, 2.0, 3.45
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    z1 = G + 1.25
    box(xm, ym, G, x1 - x0 + 0.06, y1 - y0 + 0.06, 0.12, M['stone_dk'], bevel=0.008)
    box(xm, ym, G + 0.12, x1 - x0, y1 - y0, z1 - G - 0.12, M['stone'], bevel=0.008)
    box(xm, ym, z1 - 0.06, x1 - x0 + 0.04, y1 - y0 + 0.04, 0.06, M['stone_dk'],
        bevel=0.004)
    for face, fixed, a0, a1, n in (('s', y0, x0, x1, 3), ('n', y1, x0, x1, 3),
                                    ('e', x1, y0, y1, 3), ('w', x0, y0, y1, 3)):
        for i in range(n):
            a = a0 + (a1 - a0) * (i + 0.5) / n
            for zc in (G + 0.45, G + 0.95):
                if face == 's' and i == 1 and zc < G + 0.6:
                    continue
                rbox(P(face, fixed, a, zc, 0.0), D(face, 0.06, 0.03, 0.2),
                     (0, 0, 0), M['pane_glow' if zc > G + 0.6 and i == 1 else 'pane'],
                     bevel=0)
    door(M, 's', y0, xm, *DIM['door_wide'], G + 0.12)
    for sg in (-1, 1):
        lantern(M, 's', y0, xm + sg * 0.22, G + 0.52)
    shield(M, 's', y0, xm, G + 0.80, 'banner', r=0.1)
    for sg in (-1, 1):
        beam(P('s', y0, xm - 0.15 * sg, G + 0.66, 0.058),
             P('s', y0, xm + 0.15 * sg, G + 0.94, 0.058), 0.011, M['iron'], bevel=0)
    gable_wall(M, 's', y0, x0, x1, z1)
    gable_wall(M, 'n', y1, x0, x1, z1)
    gable_roof(M, xm, ym, z1, y1 - y0, x1 - x0, 'y', M['roof2'], oh=0.1, oe=0.1)
    cobble_path(M, [(xm, y0 - 0.2), (xm, 0.9)], seed=83)
    weapon_rack(M, 1.36, 2.75, 'y')
    for (x, y) in ((-0.02, 1.8), (1.0, 1.82)):
        barrel(M, x, y, r=0.07, h=0.17)


def smithy(M):
    """The Waffenschmiede, SE quarter: an open lean-to against the south wall,
    the forge glowing under a stone hood, an anvil on its stump, a quench
    tub."""
    x0, x1 = 1.6, 3.0
    yb, yf = -WALL + WALL_T / 2, -3.2          # against the wall, open front
    zb, zf = G + 1.05, G + 0.80
    xm = (x0 + x1) / 2
    box(xm, (yb + yf) / 2, G, x1 - x0, yf - yb, 0.015, M['stone_dk'], bevel=0)
    xs = (x0 + 0.04, xm, x1 - 0.04)
    for x in xs:
        beam((x, yf, G), (x, yf, zf), 0.035, M['timber'])
    for x in (xs[0], xs[2]):
        beam((x, yb + 0.04, G), (x, yb + 0.04, zb), 0.035, M['timber'])
    beam((xs[0], yf, zf), (xs[2], yf, zf), 0.03, M['timber'])
    beam((xs[0], yb + 0.04, zb), (xs[2], yb + 0.04, zb), 0.03, M['timber'])
    for x in (xs[0], xs[2]):
        beam((x, yb + 0.04, zb), (x, yf, zf), 0.03, M['timber'])
    # the roof: one tiled slope, down to the yard
    L = math.hypot(yf - yb, zb - zf)
    ang = math.atan2(zb - zf, yf - yb)
    rbox((xm, (yb + yf) / 2 + 0.07, (zb + zf) / 2 + 0.05),
         (x1 - x0 + 0.2, L + 0.14, 0.05), (-ang, 0, 0), M['roof2'], bevel=0.004)
    # forge, coals, hood and its flue up past the wall walk
    fx = 2.62
    box(fx, yb + 0.2, G, 0.44, 0.38, 0.22, M['stone'], bevel=0.008)
    box(fx, yb + 0.2, G + 0.22, 0.32, 0.26, 0.025, M['lamp'], bevel=0)
    box(fx, yb + 0.12, G + 0.45, 0.34, 0.24, 0.12, M['stone_dk'], bevel=0.006)
    box(fx, yb + 0.12, G + 0.57, 0.22, 0.20, 1.05, M['stone'], bevel=0.006)
    # the anvil
    cyl(2.05, -3.5, G, 0.075, 0.08, 0.13, M['planks'], seg=14)
    box(2.05, -3.5, G + 0.13, 0.17, 0.075, 0.07, M['iron'], bevel=0.004)
    ellipsoid(2.155, -3.5, G + 0.175, 0.05, 0.022, 0.022, M['iron'], seg=10, rings=6)
    # the quench tub
    cyl(2.38, -3.38, G, 0.075, 0.08, 0.13, M['planks'], seg=16)
    cyl(2.38, -3.38, G + 0.115, 0.06, 0.06, 0.01, M['water'], seg=16)
    crate(M, 1.8, -3.72, 0.14, 0.2)


def training_ground(M):
    """The Exerzierplatz, SE quarter in front of the smithy: trampled earth,
    straw dummies in a row, two archery butts, a rack of spears."""
    x0, x1, y0, y1 = 1.32, 3.55, -2.75, -0.1
    box((x0 + x1) / 2, (y0 + y1) / 2, G, x1 - x0, y1 - y0, 0.012, M['dirt'], bevel=0)
    for y in (-2.25, -1.6, -0.95):
        dummy(M, 3.2, y)
    for x in (1.75, 2.45):
        target(M, x, -0.42)
    weapon_rack(M, 1.85, -2.45, 'x')


def dummy(M, x, y):
    """A straw man on a post, his arms out along the y axis."""
    box(x, y, G + 0.012, 0.16, 0.035, 0.03, M['timber'], bevel=0.004)
    box(x, y, G + 0.012, 0.035, 0.16, 0.03, M['timber'], bevel=0.004)
    beam((x, y, G + 0.04), (x, y, G + 0.36), 0.02, M['timber'])
    ellipsoid(x, y, G + 0.23, 0.05, 0.065, 0.1, M['straw_dummy'], seg=14, rings=10)
    ellipsoid(x, y, G + 0.27, 0.028, 0.15, 0.028, M['straw_dummy'], seg=12, rings=8)
    ellipsoid(x, y, G + 0.37, 0.042, 0.042, 0.048, M['sack'], seg=14, rings=10)


def target(M, x, y):
    """An archery butt on three legs, its face to the south (to the
    archers' line, and to the camera)."""
    zc = G + 0.30
    ellipsoid(x, y, zc, 0.15, 0.03, 0.15, M['straw_dummy'], seg=24, rings=12)
    ellipsoid(x, y - 0.022, zc, 0.105, 0.03, 0.105, M['banner2'], seg=22, rings=12)
    ellipsoid(x, y - 0.044, zc, 0.062, 0.03, 0.062, M['linen'], seg=18, rings=10)
    ellipsoid(x, y - 0.066, zc, 0.026, 0.03, 0.026, M['gold'], seg=12, rings=8)
    for sg in (-1, 1):
        beam((x + sg * 0.13, y - 0.02, G), (x + sg * 0.07, y + 0.01, zc - 0.09),
             0.016, M['timber'])
    beam((x, y + 0.2, G), (x, y + 0.02, zc + 0.04), 0.016, M['timber'])


def trebuchet(M):
    """A Blide, SW quarter behind the barracks: two A-frames on a sill, the
    arm cocked, its counterweight hanging, the sling down — and a pile of
    stones for it."""
    xc, yc = -2.0, -3.15
    for sg in (-1, 1):
        beam((xc - 0.6, yc + sg * 0.2, G + 0.035), (xc + 0.6, yc + sg * 0.2, G + 0.035),
             0.035, M['timber'])
        beam((xc + sg * 0.5, yc - 0.24, G + 0.035), (xc + sg * 0.5, yc + 0.24, G + 0.035),
             0.035, M['timber'])
    for y in (yc - 0.2, yc + 0.2):
        beam((xc - 0.45, y, G + 0.05), (xc, y, G + 1.0), 0.03, M['timber'])
        beam((xc + 0.45, y, G + 0.05), (xc, y, G + 1.0), 0.03, M['timber'])
        beam((xc - 0.225, y, G + 0.52), (xc + 0.225, y, G + 0.52), 0.025, M['timber'])
    beam((xc, yc - 0.25, G + 1.0), (xc, yc + 0.25, G + 1.0), 0.028, M['iron'], bevel=0)
    longe = (xc - 1.0, yc, G + 1.84)
    short = (xc + 0.27, yc, G + 0.78)
    beam(short, longe, 0.035, M['timber'])
    beam(short, (xc + 0.27, yc, G + 0.6), 0.012, M['iron'], bevel=0)
    box(xc + 0.27, yc, G + 0.32, 0.26, 0.26, 0.29, M['planks'], bevel=0.008)
    beam(longe, (xc - 1.05, yc, G + 1.42), 0.008, M['linen'], bevel=0)
    ellipsoid(xc - 1.05, yc, G + 1.39, 0.045, 0.035, 0.035, M['sack'], seg=12, rings=8)
    # the stones
    pile = (-1.0, -3.3)
    for k in range(3):
        a = 2 * math.pi * k / 3
        ellipsoid(pile[0] + math.cos(a) * 0.072, pile[1] + math.sin(a) * 0.072,
                  G + 0.06, 0.06, 0.06, 0.06, M['stone_dk'], seg=14, rings=10)
    ellipsoid(pile[0], pile[1], G + 0.16, 0.06, 0.06, 0.06, M['stone_dk'], seg=14,
              rings=10)


def garrison(M):
    barracks(M)
    armory(M)
    smithy(M)
    training_ground(M)
    trebuchet(M)
    for i, (x, y) in enumerate(((3.45, 1.4), (-3.55, -0.05))):
        bush(M, x, y, 0.15, 30 + i, ['fl_white', 'fl_pink'] if i % 2 else None)


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


