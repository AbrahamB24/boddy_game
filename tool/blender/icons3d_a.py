"""3D icons, batch A: resources, materials and ores."""
import math
import random

from icon_lib import *  # noqa: F401,F403
import icon_lib as L


def log_end(x, z, r=0.34, length=0.9, y=0.0):
    """A log lying along Y: bark round it, a pale end with growth rings."""
    cyl(x, y, z, r, length, 'brown', axis='y')
    cyl(x, y - length / 2 - 0.004, z, r * 0.92, 0.02, 'cream', axis='y')
    for k in (0.62, 0.32):
        ring(x, y - length / 2 - 0.02, z, r * k, 0.012, 'brown_dk', axis='y')
    ball(x, y - length / 2 - 0.02, z, 0.025, 0.012, 0.025, 'brown_dk')


@icon('wood')
def i_wood():
    log_end(-0.38, -0.28)
    log_end(0.38, -0.28)
    log_end(0.0, 0.34)


def rock(x, z, r, m='rock', seed=1, y=0.0):
    """A faceted boulder."""
    random.seed(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=(x, y, z))
    ob = bpy.context.object
    ob.scale = (r, r * 0.85, r * 0.78)
    for v in ob.data.vertices:
        k = random.uniform(0.86, 1.12)
        v.co *= k
    for p in ob.data.polygons:
        p.use_smooth = False
    ob.data.materials.append(L._m(m))
    return ob


@icon('stone')
def i_stone():
    rock(-0.3, -0.25, 0.55, 'rock', 3)
    rock(0.42, -0.35, 0.42, 'rock_lt', 5)
    rock(0.08, 0.25, 0.38, 'rock', 8)


@icon('coin')
def i_coin():
    cyl(0, 0, 0, 0.9, 0.16, 'gold', axis='y')
    ring(0, -0.09, 0, 0.78, 0.035, 'gold_dk')
    poly(starp(5, 0.5, 0.21), 0.05, 'gold_dk', y=-0.1, bev=0.012)


@icon('fish')
def i_fish():
    ball(-0.05, 0, 0, 0.78, 0.26, 0.42, 'sky')
    poly([(0.55, 0), (1.0, 0.45), (0.9, 0), (1.0, -0.45)], 0.1, 'blue', bev=0.02)
    poly([(-0.1, 0.38), (0.15, 0.62), (0.3, 0.32)], 0.08, 'blue', bev=0.015)
    ball(-0.55, -0.2, 0.1, 0.07, 0.04, 0.07, 'black')
    ball(-0.05, -0.2, -0.18, 0.5, 0.05, 0.14, 'white')


@icon('meat')
def i_meat():
    ball(0.1, 0, 0.1, 0.62, 0.38, 0.5, 'red_lt')
    ball(0.12, -0.2, 0.2, 0.4, 0.12, 0.28, 'red')
    cyl(-0.58, 0.0, -0.38, 0.12, 0.65, 'cream', axis='z', rot=(0, 40, 0))
    ball(-0.9, 0, -0.62, 0.17, 0.15, 0.17, 'cream')
    ball(-0.72, 0, -0.7, 0.14, 0.14, 0.14, 'cream')


@icon('clay')
def i_clay():
    ball(-0.3, 0, -0.25, 0.55, 0.42, 0.4, 'clay')
    ball(0.4, 0, -0.3, 0.45, 0.38, 0.34, 'clay_dk')
    ball(0.05, 0, 0.2, 0.42, 0.34, 0.34, 'clay')
    ball(-0.05, -0.3, 0.25, 0.1, 0.03, 0.06, 'white')


@icon('frame')
def i_frame():
    """A timber-frame wall panel: dark beams over plaster, X brace."""
    box(0, 0.04, 0, 1.7, 0.1, 1.5, 'plaster', bev=0.03)
    for x in (-0.82, 0.82):
        box(x, -0.02, 0, 0.16, 0.16, 1.55, 'timber', bev=0.02)
    for z in (-0.72, 0.72):
        box(0, -0.02, z, 1.75, 0.16, 0.16, 'timber', bev=0.02)
    box(0, -0.02, 0, 0.13, 0.13, 1.7, 'timber', rot=(0, 43, 0), bev=0.015)
    box(0, -0.02, 0, 0.13, 0.13, 1.7, 'timber', rot=(0, -43, 0), bev=0.015)
    box(0, -0.03, 0, 0.14, 0.14, 1.45, 'timber', bev=0.015)


@icon('wine')
def i_wine():
    lathe([(0, 0), (0.3, 0), (0.34, 0.05), (0.34, 0.85), (0.26, 1.05), (0.12, 1.25), (0.12, 1.55), (0.15, 1.6), (0.15, 1.7), (0, 1.7)], 'glass_green', z=-0.85)
    cyl(0, 0, 0.88, 0.13, 0.2, 'leather_dk', axis='z')
    box(0, -0.345, -0.25, 0.5, 0.03, 0.55, 'cream', bev=0.01)
    ball(0, -0.37, -0.25, 0.12, 0.02, 0.12, 'red')
    ball(0, 0, -0.5, 0.27, 0.27, 0.34, 'red', seg=20)


@icon('lime')
def i_lime():
    lathe([(0, 0), (0.95, 0), (0.9, 0.08), (0.55, 0.5), (0.2, 0.85), (0, 0.9)], 'lime', z=-0.55, sub=0)
    for x, z in ((-0.5, -0.4), (0.3, -0.5), (0.6, -0.3), (-0.1, -0.2)):
        ball(x, -0.2, z, 0.12, 0.1, 0.1, 'white')


@icon('daub')
def i_daub():
    """A wattle-and-daub wall: a woven stick lattice filled with clay."""
    box(0, 0.05, 0, 1.7, 0.14, 1.5, 'clay', bev=0.04)
    for i in range(6):
        x = -0.7 + i * 0.28
        cyl(x, -0.06, 0, 0.045, 1.5, 'brown', axis='z')
    for i in range(5):
        z = -0.6 + i * 0.3
        cyl(0, -0.1 if i % 2 else -0.02, z, 0.04, 1.7, 'brown_dk', axis='x')
    for x in (-0.86, 0.86):
        box(x, -0.04, 0, 0.1, 0.18, 1.6, 'timber', bev=0.02)


@icon('chili')
def i_chili():
    poly([(-0.1, 0.62), (0.28, 0.5), (0.5, 0.0), (0.34, -0.75), (0.2, -0.95), (0.08, -0.7), (0.12, -0.12), (-0.12, 0.28)], 0.34, 'red', bev=0.07, loc=(-0.2, 0, 0))
    poly([(-0.2, 0.62), (0.0, 0.88), (0.16, 0.62), (0.0, 0.5)], 0.3, 'green', bev=0.04, loc=(-0.2, 0, 0))
    poly([(0.3, 0.5), (0.55, 0.0), (0.4, -0.7), (0.52, -0.1), (0.4, 0.4)], 0.2, 'red_lt', y=-0.06, bev=0.03, loc=(-0.25, 0, 0))


@icon('copperOre')
def i_copper_ore():
    rock(0, -0.05, 0.85, 'rock', 4)
    for x, z, s in ((-0.3, 0.2, 0.2), (0.3, 0.1, 0.17), (0.0, -0.3, 0.22), (0.45, -0.3, 0.14)):
        ball(x, -0.6, z, s, 0.05, s * 0.8, 'copper')


@icon('ironOre')
def i_iron_ore():
    rock(0, -0.05, 0.85, 'rock', 6)
    for x, z, s in ((-0.3, 0.2, 0.2), (0.3, 0.1, 0.17), (0.0, -0.3, 0.22), (0.45, -0.3, 0.14)):
        ball(x, -0.6, z, s, 0.05, s * 0.8, 'iron_dk')
        ball(x + 0.02, -0.63, z + 0.03, s * 0.5, 0.03, s * 0.4, 'red')


@icon('goldOre')
def i_gold_ore():
    rock(0, -0.05, 0.85, 'rock', 9)
    for x, z, s in ((-0.3, 0.2, 0.2), (0.3, 0.1, 0.17), (0.0, -0.3, 0.22), (0.45, -0.3, 0.14)):
        ball(x, -0.6, z, s, 0.06, s * 0.8, 'gold')


@icon('silverOre')
def i_silver_ore():
    rock(0, -0.05, 0.85, 'rock', 12)
    for x, z, s in ((-0.3, 0.2, 0.2), (0.3, 0.1, 0.17), (0.0, -0.3, 0.22), (0.45, -0.3, 0.14)):
        ball(x, -0.6, z, s, 0.06, s * 0.8, 'silver')


@icon('coal')
def i_coal():
    rock(-0.3, -0.3, 0.5, 'coal', 2)
    rock(0.4, -0.35, 0.4, 'coal', 7)
    rock(0.05, 0.22, 0.42, 'coal', 11)
    ball(0.15, -0.45, 0.35, 0.08, 0.02, 0.05, 'white')


@icon('salt')
def i_salt():
    """A heap of salt crystals."""
    random.seed(4)
    for i in range(16):
        x = random.uniform(-0.7, 0.7)
        z = random.uniform(-0.6, 0.3) + max(0, 0.45 - abs(x)) * 0.5
        s = random.uniform(0.17, 0.27)
        box(x, random.uniform(-0.2, 0.1), z, s, s, s, 'salt', rot=(random.uniform(0, 70), random.uniform(0, 70), random.uniform(0, 70)), bev=0.01)


@icon('sand')
def i_sand():
    lathe([(0, 0), (1.0, 0), (0.95, 0.06), (0.6, 0.3), (0.25, 0.62), (0, 0.68)], 'sand', z=-0.5, sub=0)
    for x, z in ((-0.5, -0.4), (0.4, -0.45), (0.0, -0.35)):
        ball(x, -0.3, z, 0.07, 0.05, 0.04, 'sand')


@icon('brick')
def i_brick():
    box(0, 0, -0.38, 1.4, 0.7, 0.56, 'clay', bev=0.05)
    box(0, 0, 0.3, 1.4, 0.7, 0.56, 'clay_dk', bev=0.05, rot=(0, 0, 0))
    box(0.35, 0.2, 0.05, 1.0, 0.7, 0.14, 'lime', bev=0.02)
    for x in (-0.4, 0.4):
        box(x, -0.36, -0.38, 0.18, 0.02, 0.35, 'clay_dk', bev=0.005)
        box(x + 0.2, -0.36, 0.3, 0.18, 0.02, 0.35, 'clay', bev=0.005)


@icon('plaster')
def i_plaster():
    """A plastered wall: smooth cream render on stone, a trowel across it."""
    box(0, 0.05, 0, 1.7, 0.2, 1.5, 'stone', bev=0.05)
    box(0, -0.08, 0.1, 1.5, 0.08, 1.05, 'cream', bev=0.04)
    box(0.15, -0.16, -0.15, 0.9, 0.04, 0.5, 'white', rot=(0, -10, 0), bev=0.02)
    box(0.7, -0.2, -0.28, 0.5, 0.05, 0.1, 'brown', rot=(0, -10, 0), bev=0.02)
    poly([(-0.5, -0.5), (0.4, -0.58), (0.5, -0.42), (-0.4, -0.35)], 0.03, 'steel', y=-0.22, bev=0.01)


@icon('truss')
def i_truss():
    """An iron truss: a triangular girder."""
    for z, w in ((-0.55, 1.7), (0.55, 1.7)):
        box(0, 0, z, w, 0.2, 0.18, 'iron', bev=0.025)
    for i in range(5):
        x = -0.68 + i * 0.34
        box(x, 0, 0, 0.12, 0.14, 1.25, 'iron_dk', rot=(0, 28 if i % 2 else -28, 0), bev=0.015)
    for x in (-0.82, 0.82):
        box(x, 0, 0, 0.18, 0.22, 1.3, 'iron', bev=0.02)
    for x, z in ((-0.82, 0.55), (0.82, 0.55), (-0.82, -0.55), (0.82, -0.55)):
        ball(x, -0.12, z, 0.07, 0.03, 0.07, 'steel')


@icon('coffee')
def i_coffee():
    lathe([(0, 0), (0.4, 0), (0.5, 0.05), (0.62, 0.7), (0.6, 0.72), (0, 0.72)], 'cream', z=-0.55)
    cyl(0, 0, 0.12, 0.54, 0.04, 'brown_dk')
    ring(0.64, 0, 0.2, 0.22, 0.06, 'cream', axis='y')
    cyl(0, 0, -0.62, 0.78, 0.06, 'cream')
    for dx in (-0.2, 0.05, 0.28):
        ring(dx, 0, 0.62, 0.1, 0.025, 'white', axis='y', rot=(0, 0, 0))


@icon('tea')
def i_tea():
    lathe([(0, 0), (0.35, 0), (0.55, 0.12), (0.62, 0.42), (0.52, 0.62), (0.3, 0.7), (0, 0.72)], 'white', z=-0.5)
    cyl(0, 0, 0.32, 0.12, 0.2, 'white', axis='z')
    ball(0, 0, 0.45, 0.12, 0.12, 0.08, 'white')
    cyl(-0.82, 0, -0.1, 0.07, 0.5, 'white', axis='z', r2=0.04, rot=(0, 60, 0))
    ring(0.7, 0, -0.1, 0.22, 0.055, 'white')
    for dx in (-0.1, 0.12):
        poly([(dx, 0.6), (dx + 0.12, 0.8), (dx - 0.02, 0.95), (dx - 0.12, 0.78)], 0.02, 'green_lt', y=-0.3, bev=0.005)


@icon('glasswork')
def i_glasswork():
    """A glass front: a window pane in a timber frame."""
    box(0, 0, 0, 1.6, 0.14, 1.5, 'glass', bev=0.01)
    for x in (-0.8, 0.8):
        box(x, 0, 0, 0.16, 0.2, 1.55, 'timber', bev=0.02)
    for z in (-0.75, 0.75):
        box(0, 0, z, 1.7, 0.2, 0.16, 'timber', bev=0.02)
    box(0, -0.02, 0, 0.07, 0.12, 1.45, 'timber', bev=0.01)
    box(0, -0.02, 0, 1.5, 0.12, 0.07, 'timber', bev=0.01)
    poly([(-0.55, 0.45), (-0.2, 0.6), (-0.45, 0.6)], 0.02, 'white', y=-0.09, bev=0.005)


@icon('perfume')
def i_perfume():
    lathe([(0, 0), (0.6, 0), (0.62, 0.05), (0.62, 0.65), (0.5, 0.78), (0.2, 0.82), (0.15, 0.95), (0, 0.95)], 'glass', z=-0.85, sub=1)
    cyl(0, 0, -0.5, 0.52, 0.45, 'pink', axis='z', r2=0.55)
    cyl(0, 0, 0.18, 0.14, 0.3, 'gold', axis='z')
    ball(0, 0, 0.5, 0.3, 0.3, 0.3, 'pink', seg=24)
    ball(-0.35, -0.1, 0.5, 0.03, 0.03, 0.03, 'white')


@icon('aether')
def i_aether():
    ball(0, 0, 0, 0.55, 0.55, 0.55, 'glow_cyan')
    ring(0, 0, 0, 0.85, 0.03, 'glow_white', rot=(0, 0, 25))
    ring(0, 0, 0, 0.85, 0.03, 'glow_pink', rot=(0, 55, -25))
    for a in range(0, 360, 72):
        ball(0.95 * math.cos(math.radians(a)), 0, 0.95 * math.sin(math.radians(a)), 0.06, 0.06, 0.06, 'glow_white')


def crystal(x, z, h, w, m, tilt=0.0):
    """A six-sided crystal standing on (x, z), leaning by tilt degrees about its foot."""
    b = snapshot()
    cyl(x, 0, z + h * 0.375, w, h * 0.75, m, axis='z', seg=6, smooth=False)
    cyl(x, 0, z + h * 0.75 + h * 0.125, w, h * 0.25, m, axis='z', r2=0.001, seg=6, smooth=False)
    rotate_since(b, tilt, pivot=(x, 0, z))


@icon('crystalBlue')
def i_crystal_blue():
    crystal(0, -0.5, 1.5, 0.3, 'glow_blue')
    crystal(-0.62, -0.55, 0.95, 0.2, 'blue', 22)
    crystal(0.62, -0.55, 0.85, 0.19, 'glow_blue', -24)


@icon('crystalCyan')
def i_crystal_cyan():
    crystal(0, -0.5, 1.5, 0.3, 'glow_cyan')
    crystal(-0.62, -0.55, 0.95, 0.2, 'sky', 22)
    crystal(0.62, -0.55, 0.85, 0.19, 'glow_cyan', -24)


@icon('vault')
def i_vault():
    """A crystal vault: a glowing stone archway holding a crystal."""
    box(-0.7, 0, -0.1, 0.4, 0.5, 1.5, 'stone', bev=0.04)
    box(0.7, 0, -0.1, 0.4, 0.5, 1.5, 'stone', bev=0.04)
    poly(circ(0.9, 28, 0, 0.45)[:15], 0.5, 'stone', bev=0.03)
    box(0, 0, 0.9, 1.9, 0.5, 0.35, 'stone', bev=0.04)
    crystal(0, -0.7, 1.1, 0.26, 'glow_cyan')


@icon('gem')
def i_gem():
    pts = [(-0.55, 0.45), (-0.9, 0.1), (0, -0.85), (0.9, 0.1), (0.55, 0.45)]
    poly(pts, 0.4, 'glow_cyan', bev=0.03)
    poly([(-0.55, 0.45), (-0.25, 0.1), (0, 0.45)], 0.42, 'white', y=-0.02, bev=0.01)
    poly([(0.55, 0.45), (0.25, 0.1), (0, 0.45)], 0.42, 'sky', y=-0.02, bev=0.01)
    poly([(-0.25, 0.1), (0, -0.55), (0.25, 0.1)], 0.42, 'blue', y=-0.02, bev=0.01)


@icon('ruby')
def i_ruby():
    pts = [(-0.55, 0.45), (-0.9, 0.1), (0, -0.85), (0.9, 0.1), (0.55, 0.45)]
    poly(pts, 0.4, 'glow_red', bev=0.03)
    poly([(-0.55, 0.45), (-0.25, 0.1), (0, 0.45)], 0.42, 'red_lt', y=-0.02, bev=0.01)
    poly([(0.55, 0.45), (0.25, 0.1), (0, 0.45)], 0.42, 'red', y=-0.02, bev=0.01)
    poly([(-0.25, 0.1), (0, -0.55), (0.25, 0.1)], 0.42, 'red', y=-0.02, bev=0.01)


@icon('nut')
def i_nut():
    ball(0, 0, -0.1, 0.7, 0.55, 0.75, 'brown')
    ball(0, -0.2, -0.05, 0.5, 0.2, 0.55, 'leather')
    cyl(0, 0, 0.55, 0.62, 0.34, 'brown_dk', axis='z', r2=0.5)
    cyl(0, 0, 0.85, 0.05, 0.3, 'brown_dk', axis='z')


@icon('herb')
def i_herb():
    cyl(0, 0, -0.1, 0.05, 1.5, 'green_dk', axis='z')
    for i in range(5):
        z = -0.45 + i * 0.32
        for sx in (-1, 1):
            poly([(0, z), (sx * 0.5, z + 0.25), (sx * 0.28, z + 0.05)], 0.05, 'green_lt' if i % 2 else 'green', bev=0.012)
    poly([(0, 0.78), (0.16, 0.95), (0, 1.1), (-0.16, 0.95)], 0.05, 'green_lt', bev=0.012)


@icon('sprout')
def i_sprout():
    lathe([(0, 0), (0.7, 0), (0.62, 0.1), (0.3, 0.2), (0, 0.22)], 'brown_dk', z=-0.75, sub=0)
    cyl(0, 0, -0.2, 0.07, 0.95, 'green', axis='z')
    for sx in (-1, 1):
        poly([(0, 0.15), (sx * 0.8, 0.4), (sx * 0.7, 0.05)], 0.06, 'green_lt', bev=0.015)


@icon('flower')
def i_flower():
    cyl(0, 0, -0.45, 0.06, 1.0, 'green', axis='z')
    for a in range(0, 360, 60):
        r = 0.34
        ball(r * math.cos(math.radians(a)), -0.02, 0.45 + r * math.sin(math.radians(a)), 0.22, 0.08, 0.22, 'pink')
    ball(0, -0.06, 0.45, 0.17, 0.12, 0.17, 'yellow')
    poly([(0, -0.5), (0.5, -0.1), (0.3, -0.55)], 0.04, 'green_lt', bev=0.01)


@icon('grass')
def i_grass():
    random.seed(8)
    for i in range(9):
        x = -0.7 + i * 0.175
        h = random.uniform(0.7, 1.3)
        cyl(x, 0, -0.6 + h / 2, 0.07, h, 'green_lt' if i % 2 else 'green', axis='z', r2=0.008, rot=(0, random.uniform(-14, 14), 0))
