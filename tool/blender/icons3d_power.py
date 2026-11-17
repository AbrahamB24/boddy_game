"""3D icons, batch POWER: ten crest-shield proposals for the monster-power icon (user 2026-11-15: the old lightning bolt now belongs
to the Lightning element, "wappenschild" was picked from the mockup).

    blender --background --python tool/blender/make_icons.py -- power_1 ... power_10 --no-ship
"""
import math

from icon_lib import *  # noqa: F401,F403
import icon_lib as L


def sym(right):
    """A shield outline from its right half (top centre -> bottom centre), mirrored for the left."""
    return list(right) + [(-x, z) for x, z in reversed(right[1:-1])]


def scaled(pts, k, dz=0.0):
    return [(x * k, z * k + dz) for x, z in pts]


def clip(pts, a, b, c):
    """Sutherland-Hodgman: keep the part of the polygon where a*x + b*z + c >= 0."""
    out = []
    n = len(pts)
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        fp, fq = a * p[0] + b * p[1] + c, a * q[0] + b * q[1] + c
        if fp >= 0:
            out.append(p)
        if (fp >= 0) != (fq >= 0):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


HEATER = sym([(0, 0.92), (0.4, 0.84), (0.8, 0.78), (0.8, 0.12), (0.72, -0.18), (0.56, -0.46), (0.32, -0.72), (0, -0.95)])
KITE = sym([(0, 1.0), (0.62, 0.62), (0.7, 0.1), (0.45, -0.5), (0, -1.0)])
HEX = sym([(0, 0.95), (0.82, 0.48), (0.82, -0.48), (0, -0.95)])
TOWER = sym([(0, 1.0), (0.52, 1.0), (0.58, 0.92), (0.58, -0.55), (0.4, -0.88), (0, -1.0)])

FY = -0.17   # the plane the ornaments sit on (front of the field)


def base(pts, rim, field, k=0.84, depth=0.2):
    poly(pts, depth, rim, bev=0.04)
    poly(scaled(pts, k), 0.1, field, y=-0.1, bev=0.03)


def star(cx, cz, ro, m='gold', ri=None):
    poly(starp(5, ro, ri or ro * 0.45, cx, cz), 0.06, m, y=FY, bev=0.015)


@icon('power_1')
def p1():
    """Heater shield, red field, gold rim, one big gold star."""
    base(HEATER, 'gold', 'red')
    star(0, 0.02, 0.5)


@icon('power_2')
def p2():
    """Blue shield with a sword upright on it."""
    base(HEATER, 'steel', 'blue_dk')
    poly([(0, 0.74), (0.19, 0.5), (0.19, -0.14), (-0.19, -0.14), (-0.19, 0.5)], 0.07, 'white', y=FY, bev=0.015)
    box(0, FY, -0.2, 0.8, 0.08, 0.16, 'gold', bev=0.02)
    box(0, FY, -0.45, 0.14, 0.08, 0.32, 'brown_dk', bev=0.02)
    ball(0, FY, -0.66, 0.12, 0.06, 0.12, 'gold')


@icon('power_3')
def p3():
    """Round buckler: steel plate, gold ring, spiked red boss."""
    poly(circ(0.92), 0.2, 'steel', bev=0.04)
    poly(circ(0.78), 0.1, 'iron', y=-0.1, bev=0.03)
    ring(0, FY, 0, 0.6, 0.07, 'gold')
    poly(starp(8, 0.5, 0.3), 0.05, 'gold', y=FY, bev=0.012)
    ball(0, FY - 0.03, 0, 0.36, 0.16, 0.36, 'red')


@icon('power_4')
def p4():
    """Kite shield quartered red and cream, gold rim."""
    base(KITE, 'gold', 'cream')
    f = scaled(KITE, 0.84)
    for a, b in ((-1, 1), (1, -1)):
        q = clip(clip(f, a, 0, 0), 0, b, 0)
        poly(q, 0.05, 'red', y=FY + 0.03, bev=0.012)
    box(0, FY - 0.005, 0, 0.05, 0.05, 1.6, 'gold', bev=0.01)
    box(0, FY - 0.005, 0, 1.2, 0.05, 0.05, 'gold', bev=0.01)


@icon('power_5')
def p5():
    """Green shield with two gold chevrons (the rank stripes of a veteran)."""
    base(HEATER, 'gold', 'green_dk')
    for dz in (0.34, -0.12):
        poly(L.strip_poly([(-0.52, dz - 0.3), (0, dz + 0.12), (0.52, dz - 0.3)], 0.2), 0.06, 'gold', y=FY, bev=0.015)
    for x in (-0.5, 0.5):
        ball(x, FY, 0.66, 0.05, 0.03, 0.05, 'gold')


@icon('power_6')
def p6():
    """Hexagonal iron shield, gold inner frame, a cut red gem."""
    base(HEX, 'silver', 'iron_dk', k=0.86)
    poly(scaled(HEX, 0.66), 0.05, 'gold', y=FY, bev=0.012)
    poly(scaled(HEX, 0.5), 0.06, 'iron_dk', y=FY - 0.01, bev=0.01)
    poly([(0, 0.44), (0.32, 0), (0, -0.44), (-0.32, 0)], 0.09, 'red_lt', y=FY - 0.02, bev=0.025)


@icon('power_7')
def p7():
    """Purple shield with a gold crown."""
    base(HEATER, 'gold', 'purple')
    poly([(-0.38, -0.12), (-0.42, 0.26), (-0.2, 0.08), (0, 0.36), (0.2, 0.08), (0.42, 0.26), (0.38, -0.12)], 0.07, 'gold', y=FY, bev=0.02)
    box(0, FY, -0.2, 0.8, 0.07, 0.12, 'gold_dk', bev=0.02)
    for x, m in ((-0.26, 'red_lt'), (0, 'sky'), (0.26, 'red_lt')):
        ball(x, FY - 0.04, -0.2, 0.045, 0.03, 0.045, m)


@icon('power_8')
def p8():
    """Dark kite shield with a red stripe and two bone horns on top."""
    for s in (-1, 1):
        cyl(s * 0.62, 0, 0.92, 0.17, 0.62, 'cream', axis='z', r2=0.02, rot=(0, -s * 28, 0))
    base(KITE, 'iron', 'iron_dk')
    box(0, FY, 0, 0.2, 0.06, 1.5, 'red', bev=0.015)
    for z in (0.5, 0.0, -0.5):
        for x in (-0.36, 0.36):
            ball(x, FY, z, 0.045, 0.03, 0.045, 'steel')


@icon('power_9')
def p9():
    """Winged shield: blue field, gold star, white feather wings behind."""
    wing = [(0.7, 0.4), (1.1, 0.7), (1.45, 0.62), (1.3, 0.4), (1.5, 0.28), (1.28, 0.1), (1.38, -0.06), (1.0, -0.02), (0.7, -0.15)]
    for pts in (wing, [(-x, z) for x, z in reversed(wing)]):
        poly(pts, 0.08, 'white', y=0.12, bev=0.02)
    base(HEATER, 'gold', 'blue')
    star(0, 0.02, 0.46)


@icon('power_10')
def p10():
    """Wooden tower shield with iron bands, rivets and a gold star."""
    base(TOWER, 'iron', 'brown', k=0.86)
    for x in (-0.19, 0.19):
        box(x, FY, 0, 0.05, 0.04, 1.6, 'brown_dk', bev=0.01)
    for z in (0.62, -0.5):
        box(0, FY - 0.01, z, 1.02, 0.07, 0.15, 'iron', bev=0.02)
        for x in (-0.38, 0.38):
            ball(x, FY - 0.04, z, 0.045, 0.03, 0.045, 'steel')
    star(0, 0.06, 0.46)
