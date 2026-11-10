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
W, H = 7, 6             # grown 5x4 -> 7x6 (user 2026-11-09: two storeys, arcade, trees outside the wall)
ENTRANCE = ('s', 3)     # the one main entrance (user 2026-11-09), x = 0
WALKWAY_TO = [(3, 3)]   # monsters walk in through the open gate, straight up the path to the arcade (user 2026-11-09)
HEADROOM = 1.0
GLOW = {'pane_glow': ('glow', 0.45, 6.0), **LAMP_GLOW}   # lanterns flicker weakly and out of step

EAVE = G + 0.75                     # the one-storey side wings
EAVE2 = G + 1.38                    # the two-storey main wing
NY0, NY1 = 1.1, 2.15                # main (north) wing, y range
SY0 = -1.2                          # side wings run SY0 .. NY0
WING_X = 2.0                        # side wings: WING_X .. 2.8 each side
AD = 0.36                           # the arcade's depth
WALL_Y = -2.93                      # the outer wall's south side (with the gate): the footprint's tile line
WALL_X = 3.43                       # its east / west sides
WALL_N = 2.93                       # its north side
CHIMNEY = (-2.0, 1.65, EAVE2 + 0.3 + 0.6 + 0.13)


def cart(M, x, y):
    """A small hand cart that carries the patients (user 2026-11-09): a plank bed
    with low sides on two wheels, handles pointing to the path (west), a blanket
    with the red cross and a pillow on it."""
    zb = G + 0.095
    rbox((x, y, zb), (0.34, 0.2, 0.025), (0, 0, 0), M['planks'], bevel=0.003)
    for sy in (-1, 1):                                          # the long sides
        rbox((x, y + sy * 0.1, zb + 0.04), (0.34, 0.02, 0.055), (0, 0, 0), M['timber'], bevel=0.003)
    for sx in (-1, 1):                                          # the head and foot boards
        rbox((x + sx * 0.17, y, zb + 0.04), (0.02, 0.2, 0.055), (0, 0, 0), M['timber'], bevel=0.003)
    rbox((x + 0.02, y, zb + 0.03), (0.24, 0.15, 0.035), (0, 0, 0), M['flag_w'], bevel=0.004)   # blanket
    rbox((x + 0.02, y, zb + 0.049), (0.1, 0.03, 0.006), (0, 0, 0), M['flag_r'], bevel=0.001)   # its cross
    rbox((x + 0.02, y, zb + 0.049), (0.03, 0.1, 0.006), (0, 0, 0), M['flag_r'], bevel=0.001)
    ellipsoid(x + 0.12, y, zb + 0.048, 0.04, 0.055, 0.025, M['flag_w'], seg=10, rings=6)         # pillow
    beam((x, y - 0.14, G + 0.07), (x, y + 0.14, G + 0.07), 0.02, M['timber'], bevel=0.003)       # axle
    for sy in (-1, 1):                                          # the wheels: disc, hub, two spokes
        wy = y + sy * 0.13
        ellipsoid(x, wy, G + 0.07, 0.07, 0.014, 0.07, M['planks'], seg=16, rings=8)
        rbox((x, wy + sy * 0.012, G + 0.07), (0.012, 0.012, 0.15), (0, 0, 0), M['timber'], bevel=0.002)
        rbox((x, wy + sy * 0.012, G + 0.07), (0.15, 0.012, 0.012), (0, 0, 0), M['timber'], bevel=0.002)
        ellipsoid(x, wy + sy * 0.016, G + 0.07, 0.02, 0.016, 0.02, M['iron'], seg=8, rings=5)
    for sy in (-1, 1):                                          # the two handles, down to grip height
        beam((x - 0.17, y + sy * 0.08, zb + 0.02), (x - 0.46, y + sy * 0.08, G + 0.085), 0.02,
             M['timber'], bevel=0.003)
    beam((x - 0.46, y - 0.08, G + 0.085), (x - 0.46, y + 0.08, G + 0.085), 0.022, M['timber'], bevel=0.003)


def arcade(M):
    """The covered walk (Laubengang) round the court on three sides: a row of
    posts, a beam and a lean-to roof sloping down to the court, a cobbled
    walkway under it and lanterns hanging from the roof (user 2026-11-09).

    No two roof planes may overlap (user 2026-11-09): the side roofs stop short
    of the north one, and the high end stays below the wings' eaves."""
    hi, lo = G + 0.66, G + 0.50
    reach = AD + 0.05
    ang = math.atan2(hi - lo, reach)

    def under(d):
        """The roof's underside at distance d from the wall."""
        return hi - math.tan(ang) * d - 0.02

    def post(x, y):
        beam((x, y, G), (x, y, lo), 0.03, M['timber'], bevel=0.004)
        box(x, y, G, 0.07, 0.07, 0.03, M['stone_dk'], bevel=0.004)

    yo = NY0 - AD
    y_end = yo                                          # the rail beam ends at the corner post
    y_roof = NY0                                        # the side roofs run on up to the main wall and cut into the north roof: a real valley (user 2026-11-09)
    # the walkway first, so the posts stand on it
    F.cobble_path(M, [(-(WING_X - AD / 2), NY0 - AD / 2), (WING_X - AD / 2, NY0 - AD / 2)],
                  seed=21, width=0.22)
    for s in (-1, 1):
        F.cobble_path(M, [(s * (WING_X - AD / 2), SY0 + 0.05), (s * (WING_X - AD / 2), NY0 - AD / 2)],
                      seed=22 + s, width=0.22)
    # north side: along the main wing's south face
    xi = WING_X - AD                                    # the posts end exactly at the corners (user 2026-11-09)
    nx = round(2 * xi / 0.4)
    xs = [-xi + 2 * xi * i / nx for i in range(nx + 1)]
    for x in xs:
        if abs(x) > 0.3:                                # the entrance bay stays open
            post(x, yo)
    beam((-WING_X, yo, lo), (WING_X, yo, lo), 0.04, M['timber'], bevel=0.004)
    rbox((0, NY0 - AD / 2 - 0.02, (hi + lo) / 2), (2 * WING_X, reach / math.cos(ang), 0.03),
         (ang, 0, 0), M['roof2'], bevel=0.004)
    # west and east sides: along the side wings' inner faces
    for s in (-1, 1):
        xo = s * (WING_X - AD)
        ny = round((yo - SY0) / 0.4)
        ys = [SY0 + (yo - SY0) * i / ny for i in range(ny + 1)]
        for y in ys:
            post(xo, y)
        beam((xo, SY0, lo), (xo, y_end, lo), 0.04, M['timber'], bevel=0.004)
        rbox((s * (WING_X - AD / 2 - 0.02), (SY0 + y_roof) / 2, (hi + lo) / 2),
             (reach / math.cos(ang), y_roof - SY0, 0.03),
             (0, -s * ang, 0), M['roof2'], bevel=0.004)
    # lanterns hang BETWEEN the posts, exactly in the middle of each bay (user
    # 2026-11-09: they hung inside the posts), on a chain from the outer beam
    for a, b in zip(xs, xs[1:]):
        sway_lamp(M, (a + b) / 2, yo, lo - 0.02)
    for s in (-1, 1):
        for a, b in zip(ys, ys[1:]):
            sway_lamp(M, s * (WING_X - AD), (a + b) / 2, lo - 0.02)




def back_side(M):
    """The north face (user 2026-11-09: 'die Rückseite spannender'): a timber
    balcony with an outside stair and a door, a bay window, a washing line,
    barrels and crates - and windows that do not sit in one row."""
    DW, DH = DIM['door']
    yb = NY1                                   # the north face
    zf = G + 0.74                              # the upper floor / balcony level
    # balcony: floor, four posts, rail, canopy, the door onto it
    box(0, yb + 0.12, zf - 0.04, 2.5, 0.24, 0.04, M['planks'], bevel=0.004)
    for x in (-1.2, 1.2):
        beam((x, yb + 0.2, G), (x, yb + 0.2, zf - 0.04), 0.03, M['timber'], bevel=0.004)
    n = 9
    for i in range(n):
        x = -1.2 + 2.4 * i / (n - 1)
        beam((x, yb + 0.22, zf), (x, yb + 0.22, zf + 0.15), 0.018, M['timber'], bevel=0.002)
    for z in (zf + 0.15, zf + 0.07):
        beam((-1.2, yb + 0.22, z), (1.2, yb + 0.22, z), 0.02, M['timber'], bevel=0.002)
    for s in (-1, 1):
        beam((s * 1.2, yb + 0.22, zf), (s * 1.2, yb + 0.22, zf + 0.15), 0.025, M['timber'])
    F.door(M, 'n', yb, 0.0, DW, DH, zf + 0.0)
    rbox((0, yb + 0.16, zf + 0.5), (0.55, 0.34, 0.03), (-0.35, 0, 0), M['roof2'], bevel=0.004)
    F.lantern(M, 'n', yb, 0.2, zf + 0.34)
    # outside stair down to the ground at the east end
    for i in range(6):
        top = zf - 0.04 - 0.105 * (i + 1) + 0.105
        box(1.32 + 0.13 * i, yb + 0.14, G, 0.13, 0.2, max(0.03, top - G), M['planks'], bevel=0.003)
    # the stair's rail: posts on the steps' outer edge, hand rail + lower rail
    # parallel to the slope, joined to the balcony rail at the top
    ry = yb + 0.235
    tops = [zf - 0.04 - 0.105 * i for i in range(6)]
    for i in (0, 2, 4, 5):
        px = 1.32 + 0.13 * i
        beam((px, ry, tops[i]), (px, ry, tops[i] + 0.17), 0.022, M['timber'], bevel=0.003)
    for dz, tt in ((0.17, 0.02), (0.08, 0.014)):
        beam((1.32, ry, tops[0] + dz), (1.32 + 0.13 * 5, ry, tops[5] + dz), tt, M['timber'], bevel=0.002)
    beam((1.2, yb + 0.22, zf + 0.15), (1.32, ry, tops[0] + 0.17), 0.02, M['timber'], bevel=0.002)
    # the small rail on the balcony's west end (it was open there)
    for y in (yb + 0.05, yb + 0.135):
        beam((-1.2, y, zf), (-1.2, y, zf + 0.15), 0.018, M['timber'], bevel=0.002)
    for z in (zf + 0.15, zf + 0.07):
        beam((-1.2, yb + 0.01, z), (-1.2, yb + 0.22, z), 0.02, M['timber'], bevel=0.002)
    # the door canopy stands on two posts
    for x in (-0.28, 0.28):
        beam((x, yb + 0.22, zf), (x, yb + 0.22, zf + 0.455), 0.026, M['timber'], bevel=0.003)
    # the bay window (oriel) over the west end, on a corbel, with its own roof
    box(-1.9, yb + 0.07, zf + 0.0, 0.5, 0.14, 0.44, M['plaster'], bevel=0.006)
    box(-1.9, yb + 0.07, zf - 0.05, 0.56, 0.17, 0.05, M['timber'], bevel=0.004)
    rbox((-1.9, yb + 0.08, zf + 0.5), (0.6, 0.28, 0.03), (-0.3, 0, 0), M['roof2'], bevel=0.004)
    F.window(M, 'n', yb + 0.14, -1.9, zf + 0.22, *DIM['window_up'], 'teal', True)
    # washing line (the cloths wave), barrels and crates
    for x in (-2.75, -1.45):
        beam((x, yb + 0.3, G), (x, yb + 0.3, G + 0.52), 0.022, M['timber'], bevel=0.003)
    beam((-2.75, yb + 0.3, G + 0.5), (-1.45, yb + 0.3, G + 0.5), 0.008, M['iron'], bevel=0)
    for k, (x, col) in enumerate(((-2.55, 'flag_w'), (-2.3, 'red'), (-2.05, 'mustard'),
                                  (-1.75, 'teal'))):
        with F.anim(f'wash{k}', 'sway', pivot=(x, yb + 0.3, G + 0.5), amp=0.18, period=2.6 + 0.3 * k):
            rbox((x, yb + 0.3, G + 0.5 - 0.085), (0.13, 0.016, 0.17), (0, 0, 0), M[col], bevel=0.002)
    barrel(M, -0.75, yb + 0.24, 0.11, 0.26)
    barrel(M, -0.45, yb + 0.25, 0.09, 0.22)
    crate(M, 0.7, yb + 0.25, 0.14, 0.3)
    crate(M, 0.7, yb + 0.25, 0.12, -0.2, z=G + 0.14)


def build():
    random.seed(11)
    reset_lamps()
    M = vivid(mats())
    lamp_mats(M)
    DW, DH = DIM['door']

    # main wing, TWO storeys (user 2026-11-09), ridge along x. Window entries:
    # (face, a, shut, glow[, dz[, 'small']]) - dz staggers the rows.
    hall(M, -WING_X - 0.8, WING_X + 0.8, NY0, NY1, EAVE2, 'x', 'roof', mid=True,
         doors=[('s', -0.1, DW, DH)],
         wins=[('s', -1.5, 'teal', True), ('s', -0.85, 'red', False, 0.05),
               ('s', 0.9, 'red', False, 0.05), ('s', 1.5, 'teal', True),
               ('n', -2.4, 'teal', True), ('n', -1.3, 'red', False, 0.1, 'small'),
               ('n', -0.3, 'teal', True, -0.03), ('n', 0.8, 'red', True, 0.08, 'small')],
         wins_up=[('s', -1.7, 'teal', True), ('s', -1.1, 'red', False, 0.07),
                  ('s', -0.55, 'teal', True), ('s', 0.55, 'teal', True, 0.07),
                  ('s', 1.1, 'red', False), ('s', 1.7, 'teal', True, 0.07),
                  ('n', -2.5, 'red', True, 0.12, 'small'), ('n', -0.8, 'teal', True, -0.05),
                  ('n', 0.8, 'red', True, 0.04), ('n', 2.0, 'teal', True, -0.08),
                  ('n', 2.55, 'red', False, 0.1, 'small'),
                  ('e', 1.4, 'teal', True), ('w', 1.8, 'teal', True, 0.08)],
         extra_holes=[('n', 0.0, 0.2), ('n', -1.9, 0.5)], mid_through=True)
    # west and east wings, ridge along y, one storey
    ridges = {}
    for s, (a, b) in ((-1, (-WING_X - 0.8, -WING_X)), (1, (WING_X, WING_X + 0.8))):
        # the wing's roof ends AT the main wall, it does not run into it (no timber pierces it)
        ridge = hall(M, a, b, SY0, NY0 - 0.1, EAVE, 'y', 'roof',
             wins=[('e' if s < 0 else 'w', -0.5, 'teal', True), ('e' if s < 0 else 'w', 0.3, 'red', False),
                   ('s', (a + b) / 2, 'teal', True), ('w' if s < 0 else 'e', 0.0, 'red', True)],
             lanterns=False)
        ridges[s] = ridge
    F.chimney(M, -WING_X, 1.65, EAVE2 + 0.3, 0.6)
    # at least one chimney per wing (user 2026-11-09): a second on the main wing, one on each side wing
    F.chimney(M, 1.3, 1.65, EAVE2 + 0.3, 0.6)
    for s in (-1, 1):
        F.chimney(M, s * (WING_X + 0.4), 0.25, ridges[s] - 0.15, 0.5)
    arcade(M)
    back_side(M)

    # court: cobbled cross path, well, four raised herb beds
    F.cobble_path(M, [(0.0, WALL_Y), (0.0, NY0 - AD + 0.02)], seed=3)   # one straight path, from the gate to the arcade
    well(M, -0.95, -0.22)                      # beside the path, so the path runs straight
    cart(M, 1.15, -0.22)                       # the patients' cart, on the other side of the path
    herb_bed(M, -1.6, -0.55, -1.1, -0.6, 1)
    herb_bed(M, 0.55, 1.6, -1.1, -0.6, 2)
    herb_bed(M, -1.6, -0.55, 0.15, 0.55, 3)
    herb_bed(M, 0.55, 1.6, 0.15, 0.55, 4)

    # the outer wall, on the footprint's outer tile line (user 2026-11-09), the
    # gate in the south; ivy and moss grow on parts of it
    plot_wall(M, WALL_X, WALL_Y, WALL_N)
    iron_gate(M, WALL_Y)
    wall_ivy(M, WALL_X, WALL_Y, WALL_N)

    # THE sign of the building (exaggerated on purpose, user 2026-11-09): a huge
    # flag on the gate pillar, a small one on each wing. The cloths wave.
    with F.anim('flag_gate', 'sway', pivot=(0.32, WALL_Y, G + 0.54), amp=0.05, period=3.0):
        cross_flag(M, 0.32, WALL_Y, G + 0.54, 2.0, 0.62)
    # the poles stand IN the wings' ridge caps (the ridge height comes from hall())
    for s in (-1, 1):
        fx, fy, fz = s * (WING_X + 0.4), SY0 + 0.25, ridges[s] + 0.05
        with F.anim(f'flag_wing{s}', 'sway', pivot=(fx, fy, fz), amp=0.06, period=3.2 + 0.2 * s):
            cross_flag(M, fx, fy, fz, 0.9, 0.3)
    # the gate path IS the road's carriageway, flowing straight into the road tile
    F.road_apron(M, W, H, *ENTRANCE, depth=0.11)   # only to the gate (y -3.0 .. -2.89): the stone path inside has no road under it (user 2026-11-09)
    herb_bed(M, -2.7, -0.8, -2.25, -1.85, 5)          # front yard, inside the wall
    herb_bed(M, 0.8, 2.7, -2.25, -1.85, 6)
    F.bush(M, -0.6, -2.0, 0.1, 3, ['fl_white'])
    F.bush(M, 0.6, -2.0, 0.1, 5, ['fl_pink'])
    # the map's own trees: in the four corners, clear of the wall and the roofs
    for tx, ty, kind in ((-2.85, -2.35, 'broadleaf'), (2.85, -2.35, 'conifer'),
                         (-3.0, 2.6, 'conifer'), (3.0, 2.6, 'broadleaf')):
        F.map_tree(M, tx, ty, kind, s=2.2)             # big, realistic (user 2026-11-09: first 2x, then still bigger)
    # bushes and flowers along the wall's inner side
    for i, x in enumerate((-2.9, -2.4, 2.4, 2.9)):
        F.bush(M, x, WALL_Y + 0.22, 0.16, 10 + i, ['fl_white', 'fl_pink'][i % 2:i % 2 + 1])
    for i, (x, y) in enumerate(((-3.2, -1.6), (-3.2, -0.2), (3.2, -1.8), (3.2, 0.6),
                                (-2.3, WALL_N - 0.2), (2.4, WALL_N - 0.2))):
        F.bush(M, x, y, 0.18, 20 + i, ['fl_pink'] if i % 2 else ['fl_white'])
    F.flower_patch(M, -1.4, -2.6, 14, ['fl_pink', 'fl_white'], 31)
    F.flower_patch(M, 1.4, -2.6, 14, ['fl_white', 'fl_pink'], 32)
    F.flower_patch(M, -3.15, 0.9, 12, ['fl_pink'], 33)
    F.flower_patch(M, 3.15, -0.5, 12, ['fl_white'], 34)
    F.flower_patch(M, 2.7, 2.15, 10, ['fl_pink', 'fl_white'], 35)
    # stock by the east wing: barrels, a sack, a crate
    F.barrel(M, 3.2, -1.05, 0.11, 0.26)
    F.barrel(M, 3.2, -0.75, 0.09, 0.22)
    F.sack(M, 3.15, -1.35, 1.0, 0.4)
    F.crate(M, 3.2, 1.5, 0.14, 0.3)
