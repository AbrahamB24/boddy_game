"""Steel-and-gold HUD glyphs in the buildings' voxel look (user 2026-11-07: the
second concept image: dark-steel cells, silver-to-gold rims, voxel icons that
match what they stand for).

    blender --background --python tool/blender/make_ui5.py -- hud_log hud_stone \
        hud_fish hud_coin hud_house hud_clock icon_monster chest_nr compass_nr \
        [--samples N --px N]

Only the GLYPHS are rendered. The steel boards and every ring (chest, compass)
are drawn smooth in Flutter, which is why `chest_nr` / `compass_nr` are the
existing bare pieces with their voxel gold ring left out.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_ui4 as M4  # noqa: E402
import make_ui as U  # noqa: E402
from make_ui4 import vox, finish  # noqa: E402
from icon_lib import box, ball, cyl, ring, poly, circ, starp  # noqa: E402


def piece_hud_log(M):
    """Three logs, ends toward the viewer, a little turned."""
    vox(0.024)
    for x, z in ((-0.36, -0.30), (0.36, -0.30), (0.0, 0.28)):
        cyl(x, 0, z, 0.34, 1.0, 'brown', axis='y', seg=20, rot=(0, 0, 0))
        cyl(x, -0.52, z, 0.31, 0.06, 'sand', axis='y', seg=20)
        cyl(x, -0.56, z, 0.17, 0.05, 'clay', axis='y', seg=16)
        cyl(x, -0.58, z, 0.06, 0.05, 'sand', axis='y', seg=10)
    finish()
    return [], 2.1


def piece_hud_stone(M):
    """A cairn of three rough boulders, light from the upper left."""
    vox(0.022)
    ball(-0.42, 0, -0.34, 0.52, 0.34, 0.38, 'rock', seg=18, rot=(0, 10, 0))
    ball(0.44, 0, -0.38, 0.50, 0.34, 0.34, 'stone_dk', seg=18, rot=(0, -12, 0))
    ball(0.02, -0.04, 0.20, 0.56, 0.36, 0.42, 'rock_lt', seg=18, rot=(0, 6, 0))
    ball(-0.18, -0.30, 0.34, 0.20, 0.06, 0.12, 'white', seg=8)
    box(-0.40, -0.30, -0.30, 0.20, 0.05, 0.05, 'iron_dk', rot=(0, 30, 0), bev=0.0)
    box(0.42, -0.30, -0.36, 0.18, 0.05, 0.05, 'iron_dk', rot=(0, -40, 0), bev=0.0)
    finish()
    return [], 2.1


def piece_hud_fish(M):
    """A blue fish, side-on, tail to the left."""
    vox(0.022)
    ball(0.10, 0, 0, 0.62, 0.18, 0.36, 'blue', seg=24)
    ball(0.12, -0.12, -0.10, 0.50, 0.12, 0.20, 'sky', seg=20)
    poly([(-0.46, 0.0), (-0.96, 0.42), (-0.86, 0.0), (-0.96, -0.42)], 0.12, 'blue_dk', bev=0.0)
    poly([(0.0, 0.30), (0.22, 0.64), (0.42, 0.28)], 0.10, 'blue_dk', bev=0.0)
    poly([(-0.1, -0.28), (0.04, -0.54), (0.2, -0.28)], 0.10, 'blue_dk', bev=0.0)
    ball(0.52, -0.16, 0.10, 0.10, 0.06, 0.10, 'white', seg=10)
    ball(0.55, -0.21, 0.10, 0.05, 0.03, 0.05, 'black', seg=8)
    finish()
    return [], 2.2


def piece_hud_coin(M):
    """A gold coin with a star."""
    vox(0.022)
    cyl(0, 0, 0, 0.78, 0.16, 'gold', axis='y', seg=36)
    ring(0, -0.08, 0, 0.70, 0.06, 'gold_dk')
    poly(starp(5, 0.46, 0.20), 0.05, 'gold_dk', y=-0.10, bev=0.0)
    poly(starp(5, 0.38, 0.16), 0.05, 'yellow', y=-0.13, bev=0.0)
    finish()
    return [], 2.0


def piece_hud_house(M):
    """HOUSING: a small timber-and-plaster house with a tiled roof."""
    vox(0.022)
    box(0, 0, -0.30, 1.24, 0.80, 0.80, 'plaster', bev=0.0)
    for x in (-0.60, 0.60):
        box(x, -0.40, -0.30, 0.10, 0.06, 0.82, 'timber', bev=0.0)
    box(0, -0.40, -0.68, 1.30, 0.06, 0.10, 'timber', bev=0.0)
    box(0, -0.42, -0.50, 0.28, 0.06, 0.46, 'timber', bev=0.0)
    box(-0.36, -0.42, -0.22, 0.24, 0.05, 0.24, 'pane_glow', bev=0.0)
    box(0.36, -0.42, -0.22, 0.24, 0.05, 0.24, 'pane_glow', bev=0.0)
    poly([(-0.80, 0.08), (0.0, 0.84), (0.80, 0.08)], 1.0, 'roof', y=0.0, bev=0.0)
    poly([(-0.66, 0.0), (0.0, 0.64), (0.66, 0.0)], 0.06, 'timber', y=-0.52, bev=0.0)
    box(0.42, 0.1, 0.62, 0.20, 0.20, 0.42, 'stone', bev=0.0)
    finish()
    return [], 2.3


def piece_hud_clock(M):
    """TRIPS: a gold stopwatch."""
    vox(0.022)
    cyl(0, 0, 0, 0.74, 0.30, 'gold', axis='y', seg=40)
    cyl(0, -0.16, 0, 0.60, 0.06, 'cream', axis='y', seg=40)
    box(0, 0, 0.88, 0.18, 0.18, 0.18, 'gold', bev=0.0)
    box(0, 0, 0.78, 0.30, 0.24, 0.10, 'gold_dk', bev=0.0)
    box(0.62, 0, 0.62, 0.14, 0.14, 0.14, 'gold', rot=(0, 45, 0), bev=0.0)
    for k in range(12):
        a = k * math.tau / 12
        s = 0.12 if k % 3 == 0 else 0.07
        box(0.50 * math.sin(a), -0.20, 0.50 * math.cos(a), s, 0.04, s, 'iron_dk', bev=0.0)
    box(0, -0.22, 0.17, 0.07, 0.04, 0.36, 'iron_dk', bev=0.0)
    box(0.12, -0.24, 0.0, 0.30, 0.04, 0.07, 'red', rot=(0, -20, 0), bev=0.0)
    ball(0, -0.26, 0, 0.07, 0.04, 0.07, 'red', seg=8)
    finish()
    return [], 2.2


def piece_icon_monster(M):
    """MONSTERS: a horned green monster head with a grin (the paw said nothing
    about WHICH monsters; this is the game's own kind of face)."""
    vox(0.022)
    ball(0, 0, -0.04, 0.72, 0.50, 0.62, 'green_lt', seg=28)
    ball(0, -0.18, -0.22, 0.52, 0.34, 0.34, 'green', seg=22)
    for sx in (-1, 1):
        cyl(sx * 0.50, 0, 0.58, 0.16, 0.55, 'cream', axis='z', r2=0.02, seg=12, rot=(0, sx * 24, 0))
        ball(sx * 0.30, -0.40, 0.14, 0.17, 0.09, 0.19, 'white', seg=14)
        ball(sx * 0.31, -0.47, 0.14, 0.08, 0.04, 0.10, 'black', seg=10)
        ball(sx * 0.62, 0.0, -0.10, 0.14, 0.12, 0.2, 'green', seg=10, rot=(0, 0, sx * 20))
    box(0, -0.52, -0.30, 0.44, 0.04, 0.09, 'iron_dk', bev=0.0)
    for sx in (-1, 1):
        box(sx * 0.12, -0.54, -0.26, 0.07, 0.03, 0.09, 'white', bev=0.0)
    for sx in (-1, 1):
        ball(sx * 0.06, -0.50, -0.06, 0.04, 0.03, 0.05, 'iron_dk', seg=6)
    finish()
    return [], 2.2


# ── the existing bare pieces, minus their voxel gold ring ─────
def _no_ring(fn):
    def run(M):
        real = M4.ring
        M4.ring = lambda *a, **k: None
        try:
            return fn(M)
        finally:
            M4.ring = real
    return run


NEW = {
    'hud_log': (piece_hud_log, False, 8.0),
    'hud_stone': (piece_hud_stone, False, 8.0),
    'hud_fish': (piece_hud_fish, False, 8.0),
    'hud_coin': (piece_hud_coin, False, 8.0),
    'hud_house': (piece_hud_house, False, 8.0),
    'hud_clock': (piece_hud_clock, False, 8.0),
    'icon_monster': (piece_icon_monster, False, 8.0),
    'chest_nr': (_no_ring(U.PIECES['chest_bare'][0]), False, 12.0),
    'compass_nr': (_no_ring(U.PIECES['compass_bare'][0]), False, 12.0),
}
U.PIECES.update(NEW)


# User 2026-11-07: 'viel kräftiger und fröhlicher'. AgX greys everything a little;
# the glyphs are rendered with the plain 'Standard' transform instead, and a touch
# brighter, so the greens, blues and golds keep their full colour.
_cycles = U.cycles


def _vivid_cycles(samples):
    _cycles(samples)
    import bpy
    vs = bpy.context.scene.view_settings
    vs.view_transform = 'Standard'
    vs.look = 'None'
    vs.exposure = 0.25


U.cycles = _vivid_cycles

if __name__ == '__main__':
    U.main()
