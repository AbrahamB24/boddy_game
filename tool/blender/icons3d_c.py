"""3D icons, batch C: animals, people, faces, status effects and weather."""
import math

from icon_lib import *  # noqa: F401,F403
import icon_lib as L


# ── animals ─────────────────────────────────────────────────
@icon('paw')
def i_paw():
    ball(0, 0, -0.25, 0.52, 0.22, 0.42, 'copper')
    for x, z, r, rot in ((-0.66, 0.30, 0.17, -25), (-0.24, 0.62, 0.19, -8), (0.24, 0.62, 0.19, 8), (0.66, 0.30, 0.17, 25)):
        ball(x, 0, z, r, 0.16, r * 1.35, 'copper', rot=(0, rot, 0))


@icon('egg')
def i_egg():
    ball(0, 0, 0, 0.62, 0.62, 0.82, 'cream')
    for x, z, r in ((-0.2, 0.25, 0.1), (0.25, -0.1, 0.12), (-0.15, -0.4, 0.08), (0.2, 0.45, 0.07)):
        ball(x, -0.58, z, r, 0.03, r, 'blue')
    ball(-0.25, -0.5, 0.35, 0.1, 0.05, 0.2, 'white')


@icon('chick')
def i_chick():
    ball(0, 0, -0.15, 0.7, 0.6, 0.65, 'yellow')
    ball(0.1, -0.3, 0.45, 0.45, 0.42, 0.42, 'yellow')
    poly([(-0.12, 0.1), (0.12, 0.1), (0, -0.14)], 0.1, 'orange', y=-0.6, bev=0.01, loc=(0.1, 0, 0.45))
    for x in (-0.12, 0.3):
        ball(x, -0.65, 0.6, 0.05, 0.03, 0.06, 'black')
    for x in (-0.25, 0.25):
        box(x, -0.1, -0.85, 0.05, 0.05, 0.3, 'orange', bev=0.01)
        box(x - 0.08, -0.2, -1.0, 0.25, 0.1, 0.05, 'orange', bev=0.01)


@icon('fox')
def i_fox():
    poly([(-0.9, 0.1), (-0.65, 0.95), (-0.2, 0.45)], 0.25, 'fur', bev=0.03)
    poly([(0.9, 0.1), (0.65, 0.95), (0.2, 0.45)], 0.25, 'fur', bev=0.03)
    poly([(-0.9, 0.1), (0, 0.5), (0.9, 0.1), (0.5, -0.4), (0, -0.85), (-0.5, -0.4)], 0.5, 'fur', bev=0.05)
    poly([(-0.5, -0.35), (0, -0.85), (0.5, -0.35), (0, 0.0)], 0.52, 'fur_lt', y=-0.02, bev=0.03)
    ball(0, -0.3, -0.7, 0.13, 0.1, 0.1, 'black')
    for x in (-0.3, 0.3):
        ball(x, -0.28, 0.1, 0.08, 0.05, 0.1, 'black')


@icon('horse')
def i_horse():
    poly([(-0.5, -0.9), (-0.3, 0.6), (0.1, 0.95), (0.35, 0.7), (0.9, -0.1), (0.8, -0.35), (0.35, -0.1), (0.4, -0.9)], 0.45, 'brown', bev=0.05)
    poly([(-0.3, 0.6), (-0.65, 0.2), (-0.7, -0.6), (-0.45, -0.1), (-0.2, 0.2)], 0.2, 'brown_dk', y=0.1, bev=0.03)
    poly([(0.1, 0.95), (0.18, 1.2), (0.3, 0.85)], 0.15, 'brown', bev=0.02)
    ball(0.45, -0.26, 0.45, 0.07, 0.05, 0.07, 'black')
    ball(0.85, -0.2, -0.2, 0.06, 0.04, 0.05, 'black')


@icon('camel')
def i_camel():
    ball(0, 0, 0, 0.9, 0.45, 0.5, 'sand')
    ball(-0.3, 0, 0.55, 0.28, 0.32, 0.3, 'sand')
    ball(0.25, 0, 0.55, 0.28, 0.32, 0.3, 'sand')
    box(0.75, 0, 0.3, 0.25, 0.25, 0.9, 'sand', rot=(0, -20, 0), bev=0.08)
    ball(0.97, 0, 0.78, 0.28, 0.22, 0.2, 'sand')
    ball(1.02, -0.18, 0.84, 0.04, 0.03, 0.04, 'black')
    for x in (-0.55, -0.2, 0.2, 0.55):
        box(x, 0, -0.7, 0.14, 0.14, 0.7, 'sand', bev=0.04)


@icon('snail')
def i_snail():
    ball(0, 0, -0.35, 1.0, 0.35, 0.2, 'clay')
    ball(0.85, 0, -0.1, 0.18, 0.18, 0.3, 'clay', rot=(0, 15, 0))
    for x in (0.8, 1.0):
        cyl(x, 0, 0.3, 0.025, 0.4, 'clay', axis='z')
        ball(x, 0, 0.5, 0.06, 0.06, 0.06, 'black')
    ball(-0.1, 0, 0.15, 0.55, 0.3, 0.55, 'brown')
    ring(-0.1, -0.3, 0.15, 0.32, 0.05, 'cream')
    ring(-0.1, -0.31, 0.15, 0.18, 0.04, 'cream')


@icon('turtle')
def i_turtle():
    ball(0, 0, 0.0, 0.85, 0.5, 0.5, 'green_dk')
    for i, (x, z) in enumerate(((-0.4, 0.1), (0.0, 0.1), (0.4, 0.1), (-0.2, -0.2), (0.2, -0.2))):
        ball(x, -0.38, z + 0.1, 0.17, 0.05, 0.14, 'green')
    ball(1.0, 0, 0.1, 0.25, 0.22, 0.22, 'green_lt')
    ball(1.08, -0.2, 0.18, 0.04, 0.03, 0.04, 'black')
    for x in (-0.55, 0.45):
        ball(x, 0, -0.5, 0.2, 0.2, 0.14, 'green_lt')
    ball(-0.95, 0, -0.1, 0.12, 0.1, 0.07, 'green_lt')


@icon('beaver')
def i_beaver():
    ball(0, 0, -0.1, 0.65, 0.5, 0.6, 'brown')
    ball(0.45, -0.1, 0.5, 0.42, 0.38, 0.38, 'brown')
    box(0.5, -0.4, 0.15, 0.16, 0.08, 0.18, 'white', bev=0.02)
    ball(0.7, -0.3, 0.55, 0.08, 0.05, 0.06, 'black')
    ball(0.42, -0.45, 0.65, 0.05, 0.03, 0.06, 'black')
    box(-0.85, 0, -0.35, 0.8, 0.12, 0.5, 'brown_dk', rot=(0, 25, 0), bev=0.06)


@icon('moai')
def i_moai():
    poly([(-0.6, -0.9), (-0.7, 0.2), (-0.5, 0.95), (0.5, 0.95), (0.65, 0.2), (0.55, -0.9)], 0.7, 'rock_lt', bev=0.06)
    box(0, -0.4, 0.5, 1.0, 0.18, 0.18, 'rock', bev=0.03)
    box(0, -0.45, 0.0, 0.2, 0.3, 0.75, 'rock', bev=0.04)
    box(0, -0.4, -0.45, 0.5, 0.15, 0.1, 'rock', bev=0.02)


# ── people ──────────────────────────────────────────────────
def figure(x, z, s, m):
    ball(x, 0, z + 0.42 * s, 0.27 * s, 0.27 * s, 0.27 * s, m)
    ball(x, 0, z - 0.18 * s, 0.46 * s, 0.28 * s, 0.42 * s, m)


@icon('person')
def i_person():
    figure(0, 0.05, 1.35, 'copper')


@icon('groups')
def i_groups():
    figure(-0.6, -0.05, 0.9, 'steel')
    figure(0.6, -0.05, 0.9, 'steel')
    figure(0, 0.1, 1.15, 'copper')


@icon('personAdd')
def i_person_add():
    figure(-0.2, 0.05, 1.2, 'copper')
    box(0.72, -0.2, 0.55, 0.12, 0.12, 0.62, 'green', bev=0.03)
    box(0.72, -0.2, 0.55, 0.62, 0.12, 0.12, 'green', bev=0.03)


@icon('worker')
def i_worker():
    ball(0, 0, -0.35, 0.62, 0.38, 0.55, 'yellow')
    ball(0, 0, 0.35, 0.3, 0.3, 0.3, 'skin')
    lathe([(0, 0), (0.45, 0), (0.42, 0.12), (0.3, 0.3), (0, 0.32)], 'yellow', z=0.45, sub=1)
    box(0, 0, 0.45, 1.0, 0.5, 0.06, 'yellow', bev=0.02)
    ball(-0.1, -0.28, 0.38, 0.04, 0.03, 0.05, 'black')
    ball(0.1, -0.28, 0.38, 0.04, 0.03, 0.05, 'black')


@icon('robot')
def i_robot():
    box(0, 0, 0.0, 1.3, 0.9, 1.1, 'silver', bev=0.1)
    box(0, -0.46, 0.1, 1.0, 0.05, 0.5, 'iron_dk', bev=0.04)
    for x in (-0.28, 0.28):
        ball(x, -0.5, 0.12, 0.13, 0.05, 0.13, 'glow_cyan')
    box(0, -0.48, -0.32, 0.6, 0.05, 0.14, 'iron', bev=0.02)
    cyl(0, 0, 0.68, 0.04, 0.3, 'steel', axis='z')
    ball(0, 0, 0.9, 0.09, 0.09, 0.09, 'glow_red')
    for x in (-0.74, 0.74):
        box(x, 0, 0.0, 0.14, 0.3, 0.4, 'steel', bev=0.04)


@icon('gi')
def i_gi():
    """A white martial-arts jacket with a black belt."""
    poly([(-0.45, 0.85), (-0.2, 0.95), (0, 0.55), (0.2, 0.95), (0.45, 0.85), (0.95, 0.35), (0.85, -0.05), (0.6, 0.1), (0.55, -0.9), (-0.55, -0.9), (-0.6, 0.1), (-0.85, -0.05), (-0.95, 0.35)], 0.4, 'white', bev=0.05)
    poly([(-0.2, 0.95), (0, 0.55), (0.2, 0.95), (0.08, 0.95), (0, 0.78), (-0.08, 0.95)], 0.05, 'grey', y=-0.22, bev=0.005)
    box(0, -0.22, -0.2, 1.15, 0.06, 0.22, 'black', bev=0.02)
    box(0.12, -0.24, -0.5, 0.14, 0.04, 0.45, 'black', rot=(0, 10, 0), bev=0.01)


# ── faces and moods ─────────────────────────────────────────
def head(m='yellow'):
    ball(0, 0, 0, 0.9, 0.55, 0.9, m)


@icon('faceCold')
def i_face_cold():
    head('sky')
    for x in (-0.3, 0.3):
        ball(x, -0.5, 0.2, 0.1, 0.05, 0.13, 'black')
    box(0, -0.53, -0.28, 0.45, 0.04, 0.07, 'black', bev=0.01)
    for x in (-0.62, 0.62):
        poly([(x - 0.08, -0.15), (x, 0.1), (x + 0.08, -0.15)], 0.05, 'white', y=-0.52, bev=0.005, loc=(0, 0, 0))
    box(0, -0.54, 0.62, 0.7, 0.05, 0.15, 'white', bev=0.03)


@icon('faceFear')
def i_face_fear():
    head()
    for x in (-0.3, 0.3):
        ball(x, -0.5, 0.2, 0.18, 0.06, 0.2, 'white')
        ball(x, -0.56, 0.2, 0.06, 0.03, 0.08, 'black')
    ball(0, -0.52, -0.3, 0.2, 0.05, 0.25, 'black')
    for x in (-0.3, 0.3):
        box(x, -0.54, 0.5, 0.3, 0.04, 0.05, 'brown_dk', rot=(0, 18 if x < 0 else -18, 0), bev=0.01)
    ball(0.72, -0.4, 0.4, 0.08, 0.05, 0.12, 'sky')


@icon('faceSleep')
def i_face_sleep():
    head()
    for x in (-0.3, 0.3):
        box(x, -0.52, 0.1, 0.3, 0.04, 0.06, 'black', bev=0.01)
    ball(0, -0.52, -0.3, 0.1, 0.04, 0.07, 'black')
    for i, (x, z, s) in enumerate(((0.85, 0.6, 0.22), (1.1, 0.95, 0.3))):
        poly([(-1, 1), (1, 1), (-1, -1), (1, -1)], 0.04, 'blue', y=-0.1, bev=0.005, loc=(x, 0, z), rot=(0, 0, 0)) if False else None


@icon('zzz')
def i_zzz():
    for x, z, s in ((-0.6, -0.55, 0.45), (-0.05, -0.02, 0.65), (0.6, 0.62, 0.85)):
        m = 'sky' if s < 0.7 else 'blue'
        w = s * 0.7
        box(x, 0, z + w * 0.5, w, 0.14, w * 0.18, m, bev=0.02)
        box(x, 0, z - w * 0.5, w, 0.14, w * 0.18, m, bev=0.02)
        box(x, 0, z, w * 1.05, 0.14, w * 0.2, m, rot=(0, 52, 0), bev=0.02)


@icon('dizzy')
def i_dizzy():
    for k in range(3):
        R = 0.3 + k * 0.28
        ring(0, 0, 0, R, 0.05, 'yellow' if k % 2 == 0 else 'orange', axis='y')
    for a in (30, 150, 270):
        s = starp(5, 0.2, 0.09, 0.8 * math.cos(math.radians(a)), 0.8 * math.sin(math.radians(a)))
        poly(s, 0.06, 'gold', bev=0.01)


@icon('anger')
def i_anger():
    for sx in (-1, 1):
        for sz in (-1, 1):
            pts = [(sx * 0.12, sz * 0.12), (sx * 0.95, sz * 0.12), (sx * 0.95, sz * 0.3), (sx * 0.5, sz * 0.32), (sx * 0.32, sz * 0.5), (sx * 0.3, sz * 0.95), (sx * 0.12, sz * 0.95)]
            poly(pts, 0.14, 'red', bev=0.03)


@icon('skull')
def i_skull():
    ball(0, 0, 0.15, 0.8, 0.6, 0.75, 'cream')
    box(0, 0, -0.55, 0.62, 0.5, 0.5, 'cream', bev=0.06)
    for x in (-0.3, 0.3):
        ball(x, -0.5, 0.15, 0.2, 0.1, 0.24, 'black')
    poly([(-0.07, -0.18), (0.07, -0.18), (0, 0.0)], 0.06, 'black', y=-0.6, bev=0.005, loc=(0, 0, 0))
    for x in (-0.2, -0.07, 0.07, 0.2):
        box(x, -0.3, -0.62, 0.04, 0.02, 0.28, 'black', bev=0.005)


@icon('skullBones')
def i_skull_bones():
    for s in (1, -1):
        box(0, 0.2, -0.45, 0.14, 0.14, 1.8, 'cream', rot=(0, 55 * s, 0), bev=0.05)
        for e in (1, -1):
            ball(e * 0.74 * math.sin(math.radians(55 * s)) * 1.0, 0.2, -0.45 + e * 0.74 * math.cos(math.radians(55 * s)), 0.13, 0.12, 0.13, 'cream')
    ball(0, 0, 0.25, 0.65, 0.5, 0.6, 'cream')
    box(0, 0, -0.25, 0.5, 0.4, 0.4, 'cream', bev=0.05)
    for x in (-0.24, 0.24):
        ball(x, -0.42, 0.28, 0.16, 0.08, 0.2, 'black')
    for x in (-0.12, 0.0, 0.12):
        box(x, -0.24, -0.3, 0.04, 0.02, 0.22, 'black', bev=0.005)


@icon('sparkles')
def i_sparkles():
    for x, z, r in ((-0.35, -0.1, 0.8), (0.65, 0.65, 0.4), (0.6, -0.65, 0.33)):
        poly(starp(4, r, r * 0.22, x, z), 0.1, 'glow_gold', bev=0.015)


@icon('boom')
def i_boom():
    poly(starp(9, 0.98, 0.55), 0.2, 'orange', bev=0.04)
    poly(starp(9, 0.7, 0.4), 0.2, 'yellow', y=-0.06, bev=0.03)
    poly(starp(9, 0.38, 0.22), 0.2, 'white', y=-0.12, bev=0.02)


@icon('blood')
def i_blood():
    poly(dropp(1.2, -0.3, 0.0), 0.3, 'red', bev=0.05)
    poly(dropp(0.7, 0.55, -0.35), 0.3, 'red_lt', y=-0.02, bev=0.04)
    ball(-0.5, -0.2, 0.0, 0.09, 0.04, 0.14, 'white')


@icon('drop')
def i_drop():
    poly(dropp(1.5), 0.45, 'water', bev=0.08)
    ball(-0.25, -0.24, -0.05, 0.1, 0.05, 0.22, 'white')


@icon('flame')
def i_flame():
    pts = [(0, 1.0), (0.3, 0.5), (0.55, 0.65), (0.62, 0.1), (0.5, -0.45), (0, -0.85), (-0.5, -0.45), (-0.62, 0.1), (-0.4, 0.45), (-0.2, 0.35)]
    poly(pts, 0.3, 'orange', bev=0.05)
    poly([(0, 0.4), (0.3, -0.05), (0.32, -0.4), (0, -0.7), (-0.32, -0.4), (-0.3, -0.05)], 0.32, 'yellow', y=-0.04, bev=0.04)
    poly([(0, -0.05), (0.14, -0.35), (0, -0.55), (-0.14, -0.35)], 0.34, 'white', y=-0.08, bev=0.02)


@icon('snow')
def i_snow():
    for a in (0, 60, 120):
        box(0, 0, 0, 0.12, 0.12, 2.0, 'ice', rot=(0, a, 0), bev=0.03)
        for s in (1, -1):
            for dz in (0.55,):
                for e in (1, -1):
                    pass
    for a in (0, 60, 120, 180, 240, 300):
        r = math.radians(a)
        for d in (0.55,):
            for br in (45, -45):
                box(d * math.sin(r) + 0.18 * math.sin(r + math.radians(br)) * 1.0, 0, d * math.cos(r) + 0.18 * math.cos(r + math.radians(br)), 0.09, 0.1, 0.36, 'white', rot=(0, math.degrees(r) + br, 0), bev=0.02)
    ball(0, -0.08, 0, 0.14, 0.08, 0.14, 'white')


@icon('ice')
def i_ice():
    box(-0.2, 0, -0.2, 0.95, 0.8, 0.95, 'ice', rot=(0, 18, 0), bev=0.1)
    box(0.5, -0.05, 0.35, 0.6, 0.5, 0.6, 'ice', rot=(0, -25, 0), bev=0.08)
    ball(-0.45, -0.45, 0.05, 0.14, 0.03, 0.08, 'white')


@icon('wind')
def i_wind():
    for z, w in ((0.45, 1.5), (0.0, 1.8), (-0.45, 1.3)):
        box(-0.1, 0, z, w, 0.12, 0.1, 'sky', bev=0.04)
        ring(0.7 + (w - 1.5) * 0.4, 0, z + 0.15, 0.17, 0.05, 'sky')


@icon('wave')
def i_wave():
    pts = [(-1.0, -0.5), (-1.0, -0.1), (-0.6, 0.35), (-0.1, 0.6), (0.4, 0.5), (0.75, 0.2), (0.6, 0.0), (0.4, 0.15), (0.2, 0.0), (0.45, -0.25), (0.8, -0.35), (1.0, -0.5)]
    poly(pts, 0.5, 'water', bev=0.05)
    poly([(-1.0, -0.5), (1.0, -0.5), (1.0, -0.75), (-1.0, -0.75)], 0.52, 'blue', bev=0.03)
    for x, z in ((0.35, 0.58), (0.58, 0.4), (0.15, 0.62)):
        ball(x, -0.3, z, 0.07, 0.03, 0.07, 'white')


@icon('moon')
def i_moon():
    pts = []
    for i in range(0, 41):
        a = math.radians(-60 + i * 4.5)
        pts.append((0.9 * math.cos(a + math.pi / 2), 0.9 * math.sin(a + math.pi / 2)))
    outer = [(0.9 * math.cos(math.radians(a)), 0.9 * math.sin(math.radians(a))) for a in range(100, 300, 8)]
    inner = [(0.35 + 0.78 * math.cos(math.radians(a)), 0.78 * math.sin(math.radians(a))) for a in range(270, 90, -8)]
    poly(outer + inner, 0.3, 'yellow', bev=0.04)


@icon('sun')
def i_sun():
    cyl(0, 0, 0, 0.58, 0.3, 'glow_gold', axis='y')
    for a in range(0, 360, 30):
        r = math.radians(a)
        box(0.92 * math.sin(r), 0, 0.92 * math.cos(r), 0.14, 0.14, 0.34, 'yellow', rot=(0, -a, 0), bev=0.03)


@icon('star')
def i_star():
    poly(starp(5, 0.98, 0.42), 0.3, 'gold', bev=0.05)
    poly(starp(5, 0.62, 0.27), 0.3, 'yellow', y=-0.05, bev=0.03)
