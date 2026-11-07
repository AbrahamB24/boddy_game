"""3D icons, batch D: interface glyphs, gear and the rest."""
import math

from icon_lib import *  # noqa: F401,F403
import icon_lib as L


# ── interface glyphs ────────────────────────────────────────
@icon('arrowUp')
def i_arrow_up():
    poly([(0, 1.0), (0.85, 0.05), (0.35, 0.05), (0.35, -0.9), (-0.35, -0.9), (-0.35, 0.05), (-0.85, 0.05)], 0.3, 'green_lt', bev=0.05)


@icon('check')
def i_check():
    poly([(-0.95, 0.0), (-0.55, -0.4), (-0.2, -0.05), (0.6, 0.85), (0.95, 0.5), (-0.2, -0.85)], 0.3, 'green_lt', bev=0.05)


@icon('banned')
def i_banned():
    ring(0, 0, 0, 0.8, 0.17, 'red', axis='y')
    box(0, 0, 0, 1.7, 0.2, 0.3, 'red', rot=(0, 45, 0), bev=0.05)


@icon('warning')
def i_warning():
    poly([(0, 1.0), (1.0, -0.8), (-1.0, -0.8)], 0.3, 'yellow', bev=0.06)
    poly([(0, 0.72), (0.75, -0.65), (-0.75, -0.65)], 0.32, 'orange', y=-0.03, bev=0.04)
    box(0, -0.2, 0.05, 0.16, 0.1, 0.5, 'black', bev=0.03)
    ball(0, -0.2, -0.4, 0.1, 0.06, 0.1, 'black')


@icon('question')
def i_question():
    arc = [(0.42 * math.cos(math.radians(a)), 0.52 + 0.42 * math.sin(math.radians(a))) for a in range(165, -95, -10)]
    arc += [(0.04, 0.1), (0.0, -0.12)]
    poly(strip_poly(arc, 0.26), 0.26, 'blue', bev=0.04)
    ball(0, 0, -0.62, 0.16, 0.16, 0.16, 'blue')


@icon('play')
def i_play():
    poly([(-0.6, 0.85), (0.9, 0), (-0.6, -0.85)], 0.3, 'green_lt', bev=0.05)


@icon('playBack')
def i_play_back():
    poly([(0.6, 0.85), (-0.9, 0), (0.6, -0.85)], 0.3, 'sky', bev=0.05)


@icon('pause')
def i_pause():
    for x in (-0.4, 0.4):
        box(x, 0, 0, 0.5, 0.3, 1.7, 'blue', bev=0.06)


@icon('forward')
def i_forward():
    for dx in (-0.45, 0.45):
        poly([(dx - 0.45, 0.8), (dx + 0.5, 0), (dx - 0.45, -0.8)], 0.3, 'green_lt', bev=0.05)


@icon('rewind')
def i_rewind():
    for dx in (-0.45, 0.45):
        poly([(dx + 0.45, 0.8), (dx - 0.5, 0), (dx + 0.45, -0.8)], 0.3, 'sky', bev=0.05)


@icon('exchange')
def i_exchange():
    poly([(-0.9, 0.35), (-0.2, 0.35), (-0.2, 0.7), (0.9, 0.0), (-0.2, -0.7), (-0.2, -0.35), (-0.9, -0.35)], 0.25, 'green_lt', bev=0.04, loc=(0, 0, 0.45))
    poly([(0.9, 0.35), (0.2, 0.35), (0.2, 0.7), (-0.9, 0.0), (0.2, -0.7), (0.2, -0.35), (0.9, -0.35)], 0.25, 'orange', bev=0.04, loc=(0, 0, -0.45))


@icon('cycle')
def i_cycle():
    for k in range(2):
        a0 = 15 + k * 180
        arc = [(0.68 * math.cos(math.radians(a)), 0.68 * math.sin(math.radians(a))) for a in range(a0, a0 + 125, 8)]
        poly(strip_poly(arc, 0.24), 0.24, 'green_lt', bev=0.04)
        ang = math.radians(a0 + 125)
        ex, ez = arc[-1]
        tx, tz = -math.sin(ang), math.cos(ang)
        nx, nz = math.cos(ang), math.sin(ang)
        poly([(ex + nx * 0.34, ez + nz * 0.34), (ex - nx * 0.34, ez - nz * 0.34), (ex + tx * 0.42, ez + tz * 0.42)], 0.26, 'green', bev=0.03)


@icon('chat')
def i_chat():
    poly([(-0.95, 0.55), (0.95, 0.55), (0.95, -0.4), (0.2, -0.4), (-0.4, -0.9), (-0.35, -0.4), (-0.95, -0.4)], 0.3, 'white', bev=0.08)
    for x in (-0.4, 0.0, 0.4):
        ball(x, -0.18, 0.08, 0.1, 0.05, 0.1, 'blue')


@icon('chartBars')
def i_chart_bars():
    box(0, 0, -0.85, 1.9, 0.5, 0.14, 'brown_dk', bev=0.03)
    for x, h, m in ((-0.55, 0.7, 'red'), (0.0, 1.2, 'green_lt'), (0.55, 1.7, 'blue')):
        box(x, 0, -0.78 + h / 2, 0.4, 0.4, h, m, bev=0.04)


@icon('dot')
def i_dot():
    ball(0, 0, 0, 0.55, 0.55, 0.55, 'glow_red')


@icon('dotBlue')
def i_dot_blue():
    ball(0, 0, 0, 0.55, 0.55, 0.55, 'glow_blue')


@icon('heart')
def i_heart():
    poly(heartp(1.8), 0.4, 'red', bev=0.07)
    ball(-0.45, -0.25, 0.4, 0.14, 0.05, 0.22, 'white', rot=(0, 30, 0))


@icon('heartGreen')
def i_heart_green():
    poly(heartp(1.8), 0.4, 'green_lt', bev=0.07)
    ball(-0.45, -0.25, 0.4, 0.14, 0.05, 0.22, 'white', rot=(0, 30, 0))


@icon('heartPink')
def i_heart_pink():
    poly(heartp(1.8), 0.4, 'pink', bev=0.07)
    ball(-0.45, -0.25, 0.4, 0.14, 0.05, 0.22, 'white', rot=(0, 30, 0))


@icon('hearts')
def i_hearts():
    poly(heartp(1.15, -0.35, -0.15), 0.3, 'red', bev=0.05)
    poly(heartp(0.9, 0.55, 0.45), 0.3, 'pink', y=-0.05, bev=0.05)


@icon('eye')
def i_eye():
    poly([(-1.0, 0), (-0.5, 0.45), (0, 0.6), (0.5, 0.45), (1.0, 0), (0.5, -0.45), (0, -0.6), (-0.5, -0.45)], 0.3, 'white', bev=0.06)
    ball(0, -0.16, 0, 0.36, 0.12, 0.36, 'blue')
    ball(0, -0.24, 0, 0.17, 0.06, 0.17, 'black')
    ball(-0.1, -0.28, 0.12, 0.06, 0.03, 0.06, 'white')


@icon('flag')
def i_flag():
    cyl(-0.55, 0, 0, 0.06, 2.0, 'brown', axis='z')
    poly([(-0.5, 0.9), (0.9, 0.55), (0.3, 0.25), (0.9, -0.1), (-0.5, 0.25)], 0.08, 'red', bev=0.015)
    ball(-0.55, 0, 1.02, 0.1, 0.1, 0.1, 'gold')


@icon('goal')
def i_goal():
    cyl(-0.65, 0, 0, 0.06, 2.0, 'brown', axis='z')
    for i in range(4):
        for j in range(3):
            m = 'black' if (i + j) % 2 == 0 else 'white'
            box(-0.4 + i * 0.35, 0, 0.65 - j * 0.3, 0.35, 0.06, 0.3, m, bev=0.005)
    ball(-0.65, 0, 1.02, 0.1, 0.1, 0.1, 'gold')


@icon('pin')
def i_pin():
    ball(0, 0, 0.35, 0.62, 0.5, 0.62, 'red')
    L.cyl(0, 0, -0.35, 0.34, 0.9, 'red', axis='z', r2=0.02)
    ball(0, -0.4, 0.4, 0.2, 0.1, 0.2, 'white')


@icon('tag')
def i_tag():
    poly([(-0.9, 0.25), (-0.45, 0.7), (0.9, 0.7), (0.9, -0.7), (-0.45, -0.7), (-0.9, -0.25)], 0.2, 'yellow', bev=0.05)
    ring(-0.5, -0.12, 0.0, 0.1, 0.03, 'black')
    box(0.2, -0.12, 0.15, 0.7, 0.04, 0.08, 'brown_dk', bev=0.01)
    box(0.2, -0.12, -0.1, 0.5, 0.04, 0.08, 'brown_dk', bev=0.01)


@icon('target')
def i_target():
    for r, m in ((0.95, 'red'), (0.72, 'white'), (0.5, 'red'), (0.28, 'white'), (0.12, 'red')):
        cyl(0, -0.02 * (1 - r), 0, r, 0.2 + (1 - r) * 0.06, m, axis='y')
    b = snapshot()
    box(0, 0, 0, 0.06, 0.06, 1.3, 'brown', bev=0.01)
    poly([(-0.14, 0.7), (0, 0.5), (0.14, 0.7), (0.0, 0.85)], 0.05, 'red', y=0.0, bev=0.005)
    rotate_since(b, -45, pivot=(0, 0, 0))


@icon('map')
def i_map():
    for i, (x, rot) in enumerate(((-0.62, 14), (0.0, -14), (0.62, 14))):
        box(x, 0, 0, 0.66, 0.04, 1.35, 'parchment', rot=(0, 0, rot), bev=0.01)
    box(-0.62, -0.03, 0.35, 0.4, 0.02, 0.3, 'blue', bev=0.0)
    box(0.0, -0.03, -0.25, 0.34, 0.02, 0.3, 'green', bev=0.0)
    for a in (45, -45):
        box(0.62, -0.035, 0.3, 0.34, 0.02, 0.07, 'red', rot=(0, a, 0), bev=0.0)


@icon('compass')
def i_compass():
    cyl(0, 0, 0, 0.9, 0.22, 'brass', axis='y')
    cyl(0, -0.13, 0, 0.74, 0.05, 'cream', axis='y')
    poly([(0, 0.62), (0.12, 0), (-0.12, 0)], 0.04, 'red', y=-0.18, bev=0.005)
    poly([(0, -0.62), (0.12, 0), (-0.12, 0)], 0.04, 'steel', y=-0.18, bev=0.005)
    ball(0, -0.22, 0, 0.06, 0.04, 0.06, 'gold')


@icon('globe')
def i_globe():
    ball(0, 0, 0.1, 0.75, 0.75, 0.75, 'water')
    for x, z, r in ((-0.2, 0.3, 0.3), (0.3, -0.1, 0.25), (-0.3, -0.25, 0.18)):
        ball(x, -0.58, z + 0.1, r, 0.14, r * 0.8, 'green')
    ring(0, 0, 0.1, 0.84, 0.04, 'brass', axis='y', rot=(0, 0, 0))
    box(0, 0, -0.85, 0.7, 0.5, 0.12, 'brown_dk', bev=0.03)
    box(0, 0, -0.65, 0.1, 0.1, 0.3, 'brass', bev=0.01)


# ── gear and odds and ends ──────────────────────────────────
@icon('backpack')
def i_backpack():
    box(0, 0, -0.1, 1.1, 0.62, 1.25, 'leather', bev=0.16)
    box(0, -0.08, 0.38, 1.14, 0.66, 0.52, 'leather_dk', bev=0.12)
    box(0, -0.34, -0.45, 0.8, 0.14, 0.42, 'leather_dk', bev=0.06)
    for x in (-0.34, 0.34):
        box(x, -0.36, 0.3, 0.12, 0.05, 0.9, 'leather_dk', bev=0.02)
    box(0, -0.42, 0.18, 0.22, 0.05, 0.18, 'gold', bev=0.03)
    ring(0, 0, 0.72, 0.2, 0.035, 'leather_dk', axis='y')


@icon('tasks')
def i_tasks():
    box(0, 0.04, 0, 1.25, 0.08, 1.6, 'planks', bev=0.05)
    box(0, -0.02, -0.02, 1.02, 0.03, 1.36, 'parchment', bev=0.01)
    box(0, -0.06, 0.78, 0.5, 0.07, 0.18, 'brass', bev=0.04)
    for z in (0.38, 0.0, -0.38):
        box(0.14, -0.045, z, 0.5, 0.015, 0.06, 'black', bev=0.0)
        box(-0.36, -0.05, z - 0.02, 0.1, 0.02, 0.05, 'green', rot=(0, -40, 0), bev=0.0)
        box(-0.28, -0.05, z + 0.03, 0.2, 0.02, 0.05, 'green', rot=(0, 50, 0), bev=0.0)


@icon('clipboard')
def i_clipboard():
    i_tasks()


@icon('balance')
def i_balance():
    box(0, 0, -0.1, 0.1, 0.1, 1.7, 'brown_dk', bev=0.02)
    box(0, 0, -0.95, 0.9, 0.55, 0.14, 'brown_dk', bev=0.03)
    box(0, 0, 0.72, 1.9, 0.1, 0.1, 'brass', rot=(0, 5, 0), bev=0.03)
    ball(0, 0, 0.82, 0.13, 0.1, 0.13, 'gold')
    for x, z in ((-0.9, 0.78), (0.9, 0.66)):
        for dx in (-0.25, 0.25):
            box(x + dx * 0.5, 0, (z + 0.0) / 2 + 0.0 - 0.05, 0.015, 0.015, z + 0.12, 'brass', rot=(0, -dx * 12, 0), bev=0.0)
        lathe([(0, 0), (0.36, 0.0), (0.4, 0.04), (0.34, 0.12), (0, 0.12)], 'brass', x=x, z=z - 0.45 - 0.1, sub=0)


@icon('ball')
def i_ball():
    ball(0, 0, 0, 0.85, 0.85, 0.85, 'red_lt')
    ring(0, -0.1, 0, 0.8, 0.03, 'white', axis='y')
    ring(0, 0, 0, 0.84, 0.03, 'white', axis='x')


@icon('bandage')
def i_bandage():
    L.cyl(0, 0, 0, 0.62, 0.8, 'white', axis='y')
    ring(0, -0.4, 0, 0.62, 0.05, 'cream', axis='y')
    box(0.0, -0.42, 0.0, 0.5, 0.04, 0.16, 'red', bev=0.01)
    box(0.0, -0.42, 0.0, 0.16, 0.04, 0.5, 'red', bev=0.01)
    box(0.95, -0.0, -0.45, 0.6, 0.06, 0.34, 'white', rot=(0, 20, 0), bev=0.02)


@icon('bed')
def i_bed():
    box(0, 0, -0.45, 1.9, 1.0, 0.3, 'brown_dk', bev=0.04)
    box(0, 0, -0.2, 1.7, 0.9, 0.3, 'white', bev=0.08)
    box(0.3, -0.04, -0.02, 1.2, 0.92, 0.16, 'red', bev=0.06)
    ball(-0.62, -0.1, 0.05, 0.4, 0.28, 0.2, 'white')
    box(-0.92, 0.0, 0.1, 0.12, 0.9, 0.9, 'brown', bev=0.03)


@icon('boot')
def i_boot():
    box(-0.15, 0, 0.2, 0.7, 0.55, 1.3, 'leather', bev=0.12)
    box(0.25, 0, -0.5, 1.4, 0.55, 0.45, 'leather', bev=0.12)
    box(0.25, 0, -0.78, 1.5, 0.6, 0.12, 'brown_dk', bev=0.03)
    box(-0.15, -0.28, 0.85, 0.75, 0.05, 0.14, 'leather_dk', bev=0.03)


@icon('shoe')
def i_shoe():
    box(0.0, 0, -0.5, 1.9, 0.62, 0.18, 'white', bev=0.06)
    poly([(-0.9, -0.42), (-0.9, 0.3), (-0.4, 0.5), (0.1, 0.1), (0.9, -0.1), (0.95, -0.42)], 0.58, 'blue', bev=0.12)
    for x in (-0.15, 0.1, 0.35):
        box(x, -0.31, 0.0 - (x * 0.3), 0.05, 0.03, 0.3, 'white', rot=(0, 15, 0), bev=0.005)


@icon('dice')
def i_dice():
    box(0, 0, 0, 1.4, 1.4, 1.4, 'white', rot=(18, 0, 28), bev=0.12)
    for x, z in ((-0.35, 0.35), (0.35, -0.35), (0, 0)):
        ball(x - 0.12, -0.72, z + 0.18, 0.1, 0.03, 0.1, 'black')


@icon('dumbbell')
def i_dumbbell():
    box(0, 0, 0, 1.4, 0.14, 0.14, 'steel', bev=0.03)
    for x in (-0.8, 0.8):
        cyl(x, 0, 0, 0.45, 0.35, 'iron', axis='y')
        cyl(x + (0.35 if x > 0 else -0.35), 0, 0, 0.32, 0.22, 'iron_dk', axis='y')


@icon('derelict')
def i_derelict():
    box(-0.5, 0, -0.5, 0.6, 0.5, 0.8, 'stone', bev=0.03)
    poly([(0.0, -0.9), (0.0, 0.5), (0.35, 0.2), (0.5, 0.55), (0.9, -0.1), (0.9, -0.9)], 0.5, 'plaster', bev=0.04)
    box(0.3, -0.26, -0.5, 0.35, 0.04, 0.35, 'black', bev=0.01)
    box(-0.5, -0.26, -0.45, 0.2, 0.04, 0.2, 'black', bev=0.01)
    box(-0.5, 0, 0.0, 0.08, 0.08, 0.5, 'timber', rot=(0, 25, 0), bev=0.01)
    ball(-0.9, -0.3, -0.85, 0.14, 0.1, 0.1, 'rock')
    ball(0.3, -0.35, -0.85, 0.1, 0.08, 0.08, 'rock')


@icon('dna')
def i_dna():
    for i in range(9):
        z = -0.9 + i * 0.225
        x = 0.5 * math.sin(i * 0.8)
        ball(x, 0, z, 0.13, 0.13, 0.13, 'blue' if True else 'red')
        ball(-x, 0, z, 0.13, 0.13, 0.13, 'red_lt')
        box(0, 0, z, abs(x) * 2 + 0.02, 0.05, 0.05, 'cream', bev=0.0)


@icon('footprints')
def i_footprints():
    for x, z, a in ((-0.35, -0.2, 10), (0.35, 0.35, -10)):
        ball(x, 0, z, 0.3, 0.1, 0.5, 'brown_dk', rot=(0, a, 0))
        for k, dx in enumerate((-0.18, -0.06, 0.06, 0.18)):
            ball(x + dx, 0, z + 0.62 - abs(dx) * 0.4, 0.07, 0.07, 0.09, 'brown_dk')


@icon('gradcap')
def i_gradcap():
    poly([(0, 0.55), (1.0, 0.12), (0, -0.3), (-1.0, 0.12)], 0.12, 'black', y=0.0, bev=0.02, loc=(0, 0, 0.2))
    lathe([(0, 0), (0.55, 0), (0.5, 0.18), (0, 0.3)], 'black', z=-0.28, sub=0)
    box(0.85, -0.05, -0.05, 0.04, 0.04, 0.7, 'gold', bev=0.01)
    ball(0.85, -0.05, -0.45, 0.1, 0.1, 0.1, 'gold')


@icon('medical')
def i_medical():
    box(0, 0, 0, 1.7, 0.7, 1.4, 'white', bev=0.12)
    box(0, -0.37, 0, 0.8, 0.06, 0.26, 'red', bev=0.02)
    box(0, -0.37, 0, 0.26, 0.06, 0.8, 'red', bev=0.02)
    box(0, 0, 0.78, 0.6, 0.2, 0.16, 'grey', bev=0.05)


@icon('microscope')
def i_microscope():
    box(0, 0, -0.9, 1.4, 0.8, 0.16, 'iron', bev=0.04)
    box(-0.3, 0, -0.2, 0.16, 0.16, 1.5, 'iron', bev=0.03)
    L.cyl(0.1, 0, 0.45, 0.17, 1.4, 'brass', axis='z', rot=(0, 25, 0))
    L.cyl(0.38, 0, -0.15, 0.1, 0.45, 'steel', axis='z', rot=(0, 25, 0))
    box(0.3, 0, -0.55, 0.9, 0.5, 0.08, 'steel', bev=0.02)
    ball(-0.05, 0, 1.18, 0.15, 0.15, 0.1, 'black')


@icon('party')
def i_party():
    poly([(-0.55, -0.85), (0.1, 0.45), (0.45, -0.85)], 0.7, 'red', bev=0.04, rot=(0, 0, 0), loc=(-0.1, 0, 0))
    for k, (x, z, m) in enumerate(((0.35, 0.8, 'yellow'), (0.7, 0.35, 'blue'), (0.1, 0.95, 'green_lt'), (0.8, 0.8, 'pink'), (-0.4, 0.8, 'orange'))):
        box(x, -0.2, z, 0.14, 0.05, 0.14, m, rot=(0, 20 * k, 0), bev=0.01)
    ball(-0.1, -0.1, 0.5, 0.12, 0.1, 0.12, 'yellow')


@icon('road')
def i_road():
    for r in range(4):
        for c in range(3):
            x = -0.55 + c * 0.55 + (0.27 if r % 2 else 0)
            z = -0.78 + r * 0.5
            box(x, 0, z, 0.5, 0.35, 0.45, 'rock_lt' if (r + c) % 2 else 'rock', rot=(0, 0, 0), bev=0.06)
    box(-1.0, 0.2, 0, 0.25, 0.3, 2.0, 'green', bev=0.1)
    box(1.0, 0.2, 0, 0.25, 0.3, 2.0, 'green', bev=0.1)


@icon('roadOff')
def i_road_off():
    i_road()
    ring(0, -0.4, 0, 0.75, 0.1, 'red', axis='y')
    box(0, -0.4, 0, 1.5, 0.12, 0.18, 'red', rot=(0, 45, 0), bev=0.03)


@icon('save')
def i_save():
    box(0, 0, 0, 1.6, 0.3, 1.6, 'blue_dk', bev=0.07)
    box(0, -0.16, 0.5, 1.0, 0.05, 0.5, 'silver', bev=0.02)
    box(0.25, -0.18, 0.5, 0.2, 0.05, 0.34, 'iron_dk', bev=0.01)
    box(0, -0.16, -0.38, 1.1, 0.05, 0.7, 'white', bev=0.02)
    box(-0.2, -0.2, -0.3, 0.7, 0.03, 0.05, 'blue', bev=0.0)


@icon('scissors')
def i_scissors():
    for s in (1, -1):
        box(0.35 * s, 0.02 * s, 0.45, 0.2, 0.06, 1.3, 'steel', rot=(0, -12 * s, 0), bev=0.02)
        ring(0.3 * s * 1.0, 0.0, -0.55, 0.28, 0.07, 'red')
        box(0.12 * s, 0.01 * s, -0.12, 0.14, 0.07, 0.6, 'steel', rot=(0, 18 * s, 0), bev=0.02)
    ball(0, -0.08, 0.0, 0.07, 0.05, 0.07, 'gold')


@icon('shades')
def i_shades():
    for x in (-0.5, 0.5):
        poly(circ(0.42, 28), 0.14, 'black', bev=0.03, loc=(x, 0, -0.05))
        ball(x - 0.12, -0.1, 0.1, 0.1, 0.03, 0.06, 'white')
    box(0, 0, 0.0, 0.3, 0.1, 0.07, 'black', bev=0.02)
    for x in (-0.95, 0.95):
        box(x, 0.2, 0.0, 0.08, 0.5, 0.07, 'black', bev=0.02)


@icon('sponge')
def i_sponge():
    box(0, 0, 0, 1.6, 0.9, 1.1, 'yellow', bev=0.16)
    for x, z, r in ((-0.4, 0.2, 0.12), (0.2, -0.2, 0.15), (0.45, 0.25, 0.1), (-0.1, 0.0, 0.09), (-0.5, -0.3, 0.1)):
        ball(x, -0.46, z, r, 0.05, r, 'orange')


@icon('stethoscope')
def i_stethoscope():
    for a in range(200, 520, 14):
        r = math.radians(a)
        ball(0.5 * math.cos(r), 0, 0.25 + 0.55 * math.sin(r), 0.07, 0.07, 0.07, 'iron_dk')
    cyl(-0.5, 0, 0.82, 0.08, 0.3, 'steel', axis='z')
    cyl(0.5, 0, 0.82, 0.08, 0.3, 'steel', axis='z')
    ring(0, 0, -0.62, 0.3, 0.08, 'steel', axis='y')
    cyl(0, 0, -0.62, 0.22, 0.12, 'silver', axis='y')


@icon('syringe')
def i_syringe():
    b = snapshot()
    cyl(0, 0, 0.0, 0.2, 1.1, 'glass', axis='z')
    cyl(0, 0, -0.08, 0.15, 0.7, 'glow_cyan', axis='z')
    box(0, 0, 0.62, 0.55, 0.06, 0.08, 'steel', bev=0.01)
    box(0, 0, 0.75, 0.1, 0.1, 0.45, 'steel', bev=0.01)
    box(0, 0, 0.98, 0.5, 0.1, 0.07, 'steel', bev=0.01)
    box(0, 0, -0.62, 0.04, 0.04, 0.5, 'steel', bev=0.0)
    box(0, 0, -0.36, 0.5, 0.1, 0.07, 'steel', bev=0.01)
    rotate_since(b, 40)


@icon('testtube')
def i_testtube():
    lathe([(0, 0), (0.28, 0.0), (0.32, 0.4), (0.32, 1.5), (0.38, 1.55), (0.3, 1.6), (0, 1.6)], 'glass', z=-0.85, sub=1)
    lathe([(0, 0), (0.24, 0.0), (0.27, 0.35), (0.27, 0.8), (0, 0.8)], 'glow_green', z=-0.8, sub=0)
    ball(0.05, -0.1, 0.1, 0.07, 0.07, 0.07, 'glow_white')


@icon('alembic')
def i_alembic():
    ball(-0.45, 0, -0.3, 0.6, 0.6, 0.6, 'glass_amber')
    ball(-0.45, 0, -0.45, 0.5, 0.5, 0.4, 'glow_fire')
    L.cyl(-0.45, 0, 0.45, 0.14, 0.7, 'glass', axis='z')
    box(0.15, 0, 0.88, 1.2, 0.1, 0.1, 'copper', rot=(0, -8, 0), bev=0.03)
    ball(0.8, 0, -0.55, 0.3, 0.3, 0.3, 'glass')
    L.cyl(0.8, 0, 0.1, 0.07, 1.0, 'copper', axis='z', rot=(0, 0, 0))
    box(-0.45, 0, -0.98, 0.9, 0.4, 0.12, 'iron_dk', bev=0.03)


@icon('wand')
def i_wand():
    box(0, 0, -0.1, 0.1, 0.1, 1.9, 'brown_dk', rot=(0, 40, 0), bev=0.03)
    poly(starp(5, 0.38, 0.16, 0.62, 0.8), 0.12, 'glow_gold', bev=0.02)
    for x, z in ((0.1, 1.0), (1.0, 0.2), (0.95, 1.0)):
        poly(starp(4, 0.14, 0.04, x, z), 0.05, 'glow_white', bev=0.005)


@icon('trap')
def i_trap():
    box(0, 0, -0.65, 1.7, 0.8, 0.16, 'iron_dk', bev=0.03)
    for sx in (-1, 1):
        for k in range(6):
            x = sx * (0.1 + k * 0.12)
            poly([(x - 0.06, -0.55), (x, -0.05), (x + 0.06, -0.55)], 0.1, 'steel', bev=0.01) if False else None
    ring(0, 0, -0.2, 0.8, 0.07, 'steel', axis='y')
    for a in range(20, 170, 20):
        r = math.radians(a)
        poly([(0.8 * math.cos(r) - 0.06, -0.2 + 0.8 * math.sin(r)), (0.8 * math.cos(r) - 0.0, -0.2 + 0.8 * math.sin(r) - 0.22), (0.8 * math.cos(r) + 0.06, -0.2 + 0.8 * math.sin(r))], 0.08, 'silver', bev=0.005)
    ball(0, -0.2, -0.55, 0.14, 0.05, 0.1, 'red')


@icon('trash')
def i_trash():
    lathe([(0, 0), (0.55, 0), (0.7, 1.3), (0, 1.3)], 'steel', z=-0.85, sub=0)
    cyl(0, 0, 0.5, 0.78, 0.14, 'iron', axis='z')
    box(0, 0, 0.68, 0.4, 0.14, 0.1, 'iron', bev=0.03)
    for x in (-0.3, 0, 0.3):
        box(x, -0.5, -0.2, 0.06, 0.04, 1.0, 'iron', bev=0.01)


@icon('tree')
def i_tree():
    cyl(0, 0, -0.55, 0.14, 0.9, 'brown', axis='z', r2=0.1)
    ball(0, 0, 0.35, 0.78, 0.7, 0.62, 'green')
    ball(-0.4, -0.1, 0.1, 0.5, 0.5, 0.42, 'green_lt')
    ball(0.4, -0.1, 0.12, 0.5, 0.5, 0.42, 'green_dk')
    ball(0, -0.3, 0.55, 0.45, 0.4, 0.38, 'green_lt')


def vehicle_wheels(xs, z=-0.55, r=0.26):
    for x in xs:
        cyl(x, -0.42, z, r, 0.14, 'black', axis='y')
        cyl(x, -0.5, z, r * 0.5, 0.04, 'steel', axis='y')


@icon('truck')
def i_truck():
    box(-0.3, 0, -0.1, 1.5, 0.8, 0.9, 'blue', bev=0.06)
    box(0.85, 0, -0.25, 0.7, 0.8, 0.6, 'red', bev=0.06)
    box(0.95, -0.42, -0.05, 0.4, 0.04, 0.3, 'sky', bev=0.01)
    box(0, 0, -0.62, 2.0, 0.8, 0.12, 'iron_dk', bev=0.03)
    vehicle_wheels((-0.7, 0.0, 0.85))


@icon('truckSmall')
def i_truck_small():
    box(0.55, 0, -0.1, 0.9, 0.8, 0.7, 'green', bev=0.07)
    box(-0.5, 0, -0.3, 1.0, 0.8, 0.3, 'planks', bev=0.03)
    box(0.7, -0.42, 0.0, 0.4, 0.04, 0.3, 'sky', bev=0.01)
    box(0.0, 0, -0.55, 1.9, 0.8, 0.1, 'iron_dk', bev=0.03)
    vehicle_wheels((-0.6, 0.6), -0.52, 0.28)


@icon('train')
def i_train():
    L.cyl(-0.15, 0, -0.1, 0.45, 1.4, 'iron', axis='x')
    box(0.78, 0, 0.0, 0.7, 0.9, 0.95, 'red', bev=0.05)
    box(0.78, 0, 0.62, 0.9, 1.0, 0.1, 'iron_dk', bev=0.02)
    L.cyl(-0.65, 0, 0.55, 0.14, 0.5, 'iron_dk', axis='z', r2=0.2)
    ball(-0.9, 0, 0.95, 0.2, 0.2, 0.15, 'grey')
    box(0.0, 0, -0.52, 2.0, 0.9, 0.1, 'iron_dk', bev=0.02)
    for x, r in ((-0.55, 0.3), (0.1, 0.3), (0.75, 0.24)):
        cyl(x, -0.46, -0.6, r, 0.12, 'red', axis='y')
        cyl(x, -0.54, -0.6, r * 0.35, 0.04, 'steel', axis='y')
    ball(-0.98, -0.0, -0.12, 0.1, 0.1, 0.1, 'glow_gold')


@icon('bolt')
def i_bolt():
    poly([(0.15, 1.0), (-0.55, -0.1), (-0.05, -0.1), (-0.25, -1.0), (0.6, 0.15), (0.05, 0.15)], 0.3, 'glow_gold', bev=0.05)


@icon('battery')
def i_battery():
    box(0, 0, 0, 1.0, 0.7, 1.7, 'iron_dk', bev=0.1)
    box(0, -0.36, -0.1, 0.84, 0.06, 1.3, 'green', bev=0.03)
    box(0, 0, 1.0, 0.4, 0.4, 0.2, 'silver', bev=0.04)
    poly([(0.12, 0.45), (-0.2, -0.05), (0.02, -0.05), (-0.12, -0.5), (0.22, 0.05), (0.0, 0.05)], 0.05, 'glow_gold', y=-0.4, bev=0.01)
