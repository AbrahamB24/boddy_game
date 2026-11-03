"""The sixteen road tiles, in the Fachwerk buildings' world.

    blender --background --python tool/blender/make_roads.py -- [--samples 96] [--only N]

Writes docs/renders/roads/road_NN.png and ships assets/images/roads/road_NN.webp.

Same world as make_building.py (user 2026-11-03: "nun mache die Strassen"):
rounded cobbles like the buildings' own paths, on a dirt bed, edged with dark
kerb stones, voxelised, lit by the same golden-hour sun. The SHAPE rules are
the old ones (render_building._road_covers): a lone patch, dead ends, straights,
an ARC for every corner, tees and a crossroads — sixteen from the four
neighbour bits, in road_tiles.dart's order.

── Seamless ──
A tile is only ever drawn next to other tiles, so three things are exact:
  * the frame: the cell's own diamond, 2:1, with fit=False — a road reaching
    the tile edge must not grow the picture, or no junction lines up;
  * the voxel grid: 1/60 tile (fw_kit.VOX is 1/60.6), so both tile edges at
    +-0.5 fall on block boundaries and neighbours meet block to block;
  * the stones: every cobble lies wholly inside its own tile, on a grid with
    the same phase in every tile, so two tiles meet at an ordinary joint.
"""
import argparse
import math
import os
import random
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import anim_pass as ap  # noqa: E402
import fw_kit  # noqa: E402
import make_building as mb  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
import voxelizer  # noqa: E402

G = K.G
V_ROAD = 1 / 60
HALF_W = 0.28            # carriageway 0.56 tiles = 2.8 m; kerbs outside it
STEP = 1 / 18            # cobble pitch, ~28 cm
SCALE = 5                # 320 x 160 px per tile, shipped as rendered
# game +x, +y, -x, -y — the game's +y is Blender's -y (road_tiles.dart)
DIRS = ((1, 0), (0, -1), (-1, 0), (0, 1))


def covers(px, py, mask, hw=HALF_W):
    """Is (px, py), tile coordinates -0.5..0.5, on the road? A corner is the
    ARC joining the two edge midpoints; everything else is arms + a pad."""
    dirs = [d for i, d in enumerate(DIRS) if mask >> i & 1]
    if len(dirs) == 2 and dirs[0][0] * dirs[1][0] + dirs[0][1] * dirs[1][1] == 0:
        (ax, ay), (bx, by) = dirs
        ox, oy = px - (ax + bx) / 2, py - (ay + by) / 2
        if ox * ax + oy * ay > 0 or ox * bx + oy * by > 0:
            return False
        return abs(math.hypot(ox, oy) - 0.5) <= hw
    if max(abs(px), abs(py)) <= hw:
        return True
    for dx, dy in dirs:
        along, across = px * dx + py * dy, px * -dy + py * dx
        if 0 <= along <= 0.5 + 1e-9 and abs(across) <= hw:
            return True
    return False


def materials():
    M = fw_kit.base_materials()
    M['bed'] = fw_kit.tex_mat('road_bed', 'park_dirt', 1.0, tint=(0.85, 0.70, 0.52),
                              sat=1.0, val=0.75, nstr=1.0, vary=0.05)
    M['cobble2'] = fw_kit.plain('cobble2', '#bfae8e', rough=0.85, bump=0.55,
                                bump_scale=40, vary=0.14, speck='#988a70')
    return M


def tile(mask):
    M = materials()
    n = round(1 / STEP)
    rnd = random.Random(1000 + mask)

    def centre(ix, iy):
        return -0.5 + STEP * (ix + 0.5), -0.5 + STEP * (iy + 0.5)

    on = {(ix, iy) for iy in range(n) for ix in range(n)
          if covers(*centre(ix, iy), mask)}
    for ix, iy in on:
        px, py = centre(ix, iy)
        fw_kit.box(px, py, G, STEP, STEP, 0.014, M['bed'], bevel=0)
        # a stone, jittered but kept inside its own square, so nothing ever
        # crosses into the neighbouring tile
        r = STEP * rnd.uniform(0.40, 0.47)
        slack = STEP / 2 - r
        jx, jy = rnd.uniform(-slack, slack), rnd.uniform(-slack, slack)
        fw_kit.ellipsoid(px + jx, py + jy, G + 0.016, r, r * rnd.uniform(0.85, 1.0),
                         0.022, M['cobble' if rnd.random() < 0.7 else 'cobble2'],
                         seg=12, rings=7, tilt=(0, 0, rnd.uniform(0, 3.14)))
    # The kerb finds itself: a square that is not road but touches road
    # (eight-way, so outer corners close). It opens by itself at a junction —
    # the ground beside one arm is the middle of the next.
    for iy in range(n):
        for ix in range(n):
            if (ix, iy) in on:
                continue
            if not any((ix + dx, iy + dy) in on
                       for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy):
                continue
            px, py = centre(ix, iy)
            fw_kit.box(px, py, G, STEP * 0.9, STEP * 0.9, 0.032,
                       M['stone_dk'], bevel=0)


def render_tile(mask, samples, out_png):
    rb.clear()
    K._mats.clear()
    tile(mask)
    mb.lower_to_yard()
    voxelizer.voxelize(V_ROAD, f'road_{mask:02d}')
    K.lighting()
    K.setup_render(samples, SCALE, 1, 1, headroom=0.5)
    # EXACTLY the cell's diamond: rebuilt with fit=False
    for o in list(bpy.data.objects):
        if o.type == 'CAMERA':
            bpy.data.objects.remove(o)
    rb.frame(1, 1, SCALE, 0.5, 0.0, fit=False)
    K.render(out_png)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap_ = argparse.ArgumentParser()
    ap_.add_argument('--samples', type=int, default=96)
    ap_.add_argument('--only', type=int)
    args = ap_.parse_args(argv)
    docs = os.path.join(ROOT, 'docs', 'renders', 'roads')
    assets = os.path.join(ROOT, 'assets', 'images', 'roads')
    os.makedirs(docs, exist_ok=True)
    for mask in ([args.only] if args.only is not None else range(16)):
        png = os.path.join(docs, f'road_{mask:02d}.png')
        render_tile(mask, args.samples, png)
        ap.save_webp(ap.load_rgba(png), os.path.join(assets, f'road_{mask:02d}.webp'),
                     90)


main()
