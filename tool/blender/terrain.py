"""The map's ground: grass, a sea in the west with its beach, the river that
runs east out of it, and forest along the other three rims.

    blender --background --python tool/blender/terrain.py -- \
        --out assets/images/map_background.png

── The one rule this file exists to keep ──
The water is not a picture of water. It is a SET OF CELLS, and the same set is
written out as Dart (see --dart) so the game can refuse to build on it — user
2026-08-09: "Der Fluss ist nicht bebaubar". Both the render and the rule read
`classify()`, so the coastline you can see and the coastline you can build
against cannot drift apart. Draw the water freehand and they would drift the
first time anyone nudged a number.

── What is in here and what is NOT ──
Terrain and scenery only. Nothing here is a building, nothing here is cleared,
and nothing here is saved: the picture is a backdrop and the water mask is
derived, so regenerating either is always safe.

The MOUNTAINS are gone (user 2026-08-09: "Berge löschen"). They closed the
horizon with rock, which fought a settlement built of the same warm stone —
the eye read them as more masonry rather than as distance. Forest does the same
job and recedes instead of competing.

── Size comes from the DART, not from here ──
It used to say `COLS, ROWS = 60, 40` and the grid had grown to 200 x 120, so the
background was a 60 x 40 picture stretched over three times its own map: a river
that ran nowhere near the cells it was drawn for. Numbers duplicated between two
files are numbers that will disagree, so this one reads them.
"""
import argparse
import importlib.util
import math
import os
import re
import sys

import bpy

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(os.path.dirname(_HERE))
_spec = importlib.util.spec_from_file_location(
    'render_building', os.path.join(_HERE, 'render_building.py'))
rb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rb)

_DEFS = os.path.join(_ROOT, 'lib', 'features', 'settlement', 'data',
                     'building_definitions.dart')


def _dart_const(name):
    with open(_DEFS, encoding='utf-8') as fh:
        m = re.search(rf'^const {name} = (\d+);', fh.read(), re.M)
    if not m:
        raise SystemExit(f'{name} not found in building_definitions.dart')
    return int(m.group(1))


COLS = _dart_const('kGridCols')
ROWS = _dart_const('kGridRows')
PLOT_X = _dart_const('kInitialPlotX')
PLOT_Y = _dart_const('kInitialPlotY')
PLOT_SIZE = _dart_const('kInitialPlotSize')

TERRAIN = {
    'grass': (0.36, 0.55, 0.26),
    'grass_dry': (0.44, 0.57, 0.27),
    'grass_dark': (0.31, 0.50, 0.24),
    'water': (0.20, 0.48, 0.68),
    'water_deep': (0.13, 0.34, 0.55),
    'shore': (0.80, 0.74, 0.52),
    'shore_wet': (0.68, 0.62, 0.44),
    'trunk': (0.34, 0.24, 0.16),
    'canopy': (0.24, 0.42, 0.20),
    'canopy_light': (0.34, 0.51, 0.24),
    'canopy_dark': (0.17, 0.32, 0.17),
    # ── The detail palette (user 2026-08-09: "Bitte deutlich mehr Details") ──
    # Sized to SURVIVE: the ground ships at 4096 px for a 10240 px map, so a
    # cell is about twenty pixels and nothing under a quarter of a cell will
    # ever be seen. Every tone below is therefore attached to something at least
    # that big — a bush, a boulder, a reed bed — and not to speckle.
    'shallow': (0.32, 0.62, 0.76),   # water over sand, the band at every shore
    'foam': (0.80, 0.90, 0.92),      # where the water meets the beach
    'rock': (0.52, 0.50, 0.47),
    'rock_dark': (0.38, 0.36, 0.35),
    'dirt': (0.46, 0.38, 0.27),      # worn ground, cart tracks, a bare bank
    'reed': (0.44, 0.56, 0.26),
    'heather': (0.55, 0.40, 0.52),   # the one cool flower note
    'gorse': (0.86, 0.76, 0.26),     # and the one warm one
}

# ── The shape of the land ───────────────────────────────────
# Everything below is a pure function of a cell. That is what lets the renderer
# and the exported rule be the same thing.

SEA, RIVER, BEACH, GRASS = 'sea', 'river', 'beach', 'grass'

#: How far the beach reaches inland from the waterline, in cells.
BEACH_WIDTH = 3.2


def coast_at(gy):
    """Where the sea ends, along the map's WEST rim (small x).

    West is the map's upper-left edge on screen — see iso_grid.dart, where +x
    runs down-right, so the x = 0 edge is the one at the top left. That is where
    the user asked for it: "Links oben soll das Meer sein mit Strand".

    Two waves of different lengths, so the coast has bays without repeating.
    """
    return (12.0
            + 5.0 * math.sin(gy * 0.085)
            + 2.6 * math.sin(gy * 0.031 + 1.1))


def river_spine(t):
    """(x, y, half-width) a fraction t along the river, in cells.

    It starts INSIDE the sea, so the two are visibly one body of water rather
    than a channel that happens to stop near a coast, and it runs east across
    the whole map — "von welchem aus der Fluss von west nach ost fliesst".

    It also stays well clear of the starting plot. A river through the square
    the player is handed at minute one is not a feature, it is a bisected
    settlement; the assertion in main() is what keeps that true if these numbers
    are ever retuned.
    """
    x = 6.0 + (COLS - 6.0) * t
    y = 58.0 + 26.0 * math.sin(t * math.pi * 1.9 + 0.35) + 10.0 * t
    w = 3.3 + 0.75 * math.sin(t * 7.0 + 0.6)
    return x, y, w


#: The spine runs past the edge of the PICTURE on both ends — not merely past
#: the grid, which is what it did first (user 2026-08-09: "Der Fluss soll nicht
#: enden, sondern aus dem Screen hinausgehen"). The picture is the grid's
#: bounding box, so it reaches about half the far dimension beyond every rim;
#: a river that stopped at the grid stopped in open view, sixty cells short of
#: the frame, and a river with an end in the middle of the ground is the one
#: thing water never does.
_SPINE_N = 760
_SPINE = [river_spine(-0.55 + 1.95 * i / _SPINE_N) for i in range(_SPINE_N + 1)]
_SPINE_X0 = _SPINE[0][0]
_SPINE_DX = (_SPINE[-1][0] - _SPINE_X0) / _SPINE_N


def _river_depth(gx, gy):
    """How far INSIDE the river a cell is: > 0 means water, and the bigger it
    is the further from either bank.

    Only the stretch of spine NEAR this x is looked at. The spine's x is linear
    in t, so the window is an index, not a search — and without it this is 520
    hypots for every one of a hundred thousand cells, which is the difference
    between a terrain that takes seconds to build and one that takes minutes.
    """
    mid = int((gx - _SPINE_X0) / _SPINE_DX)
    lo = max(0, mid - 30)
    hi = min(len(_SPINE), mid + 31)
    best = -99.0
    for i in range(lo, hi):
        sx, sy, sw = _SPINE[i]
        d = sw - math.hypot(gx - sx, gy - sy)
        if d > best:
            best = d
    return best


def classify(gx, gy):
    """What one cell IS. The single source for the render and for the rule."""
    cx, cy = gx + 0.5, gy + 0.5
    coast = coast_at(cy)
    if cx < coast:
        return SEA
    depth = _river_depth(cx, cy)
    if depth > 0:
        return RIVER
    if cx < coast + BEACH_WIDTH or depth > -1.6:
        return BEACH
    return GRASS


def is_water(kind):
    """The rule the game enforces: sea and river cannot be built on, beach can.
    Only the water was asked for, and a beach you cannot build a harbour on
    would be a second rule nobody asked for."""
    return kind in (SEA, RIVER)


# ── Beyond the playfield ────────────────────────────────────
# The picture is the grid's BOUNDING BOX, and a diamond does not fill its own
# bounding box: a quarter of what you see is outside the map, and the corners
# are what the mountains used to occupy. Drawing only the cells that exist put
# the ground's own straight edge across the middle of the render and left the
# sea looking like a canal, because the far bank of the "sea" was grass.
#
# So everything is drawn over a padded range and only the REAL cells are
# exported. The pad is sized from the corners of the bounding box: a diamond
# COLS x ROWS has corners that sit about half the far dimension outside every
# rim, so the drawing has to reach that far to fill the picture.
EXT_X0, EXT_X1 = -80, COLS + 60
EXT_Y0, EXT_Y1 = -110, ROWS + 110

#: Distant woods: past this far outside a rim, trees stop being drawn one at a
#: time and become one dark mass. Individually they would be tens of thousands
#: of objects for the corners of a picture nobody zooms into.
WOOD_EDGE = -16

#: How far the tree band reaches INSIDE the playfield.
WOOD_BAND = 12

WOOD = 'wood'


def in_picture(gx, gy):
    """Is this cell anywhere in the rendered image?

    The picture is the diamond's BOUNDING BOX, which in grid terms is the band
    where (gx - gy) and (gx + gy) each stay inside the map's own span. Half of
    the padded range falls outside it, and scattering thousands of objects there
    is thousands of objects nobody can ever see.
    """
    u, v = gx - gy, gx + gy
    return -ROWS <= u <= COLS and 0 <= v <= COLS + ROWS


def rim_distance(gx, gy):
    """How far inside the playfield a cell is, counting only the three rims
    that are NOT the sea. Negative outside."""
    return min(COLS - gx, gy, ROWS - gy)


def classify_ext(gx, gy):
    """[classify], plus the distant woods that only exist off the map."""
    kind = classify(gx, gy)
    if kind is GRASS and rim_distance(gx, gy) < WOOD_EDGE:
        return WOOD
    return kind


# ── Drawing it ──────────────────────────────────────────────
def tmat(key):
    if key not in rb._MATS:
        rb._MATS[key] = rb.flat(key, TERRAIN[key])
    return rb._MATS[key]


def world(gx, gy):
    """Grid cell → Blender world, centred on the cell.

    The frame puts the grid's middle at the origin, and Blender's y runs the
    OTHER WAY from the game's: under this camera +y goes up-right on screen
    where the Dart projection sends +y down-left. Flipped once, here.
    """
    return gx + 0.5 - COLS / 2.0, ROWS / 2.0 - gy - 0.5


def slab(name, x, y, w, d, z, h, key):
    """Ground drawn as flat slabs at slightly different heights, so the edges
    between them are real geometry catching real light rather than a painted
    line. A painted boundary reads as texture; a step reads as a bank."""
    return rb.box(name, x, y, z, w, d, h, tmat(key))


class Terrain:
    """The classified ground over the padded range, indexed by real cell."""

    def __init__(self):
        self.rows = [[classify_ext(x, y) for x in range(EXT_X0, EXT_X1)]
                     for y in range(EXT_Y0, EXT_Y1)]

    def at(self, gx, gy):
        if not (EXT_X0 <= gx < EXT_X1 and EXT_Y0 <= gy < EXT_Y1):
            return GRASS
        return self.rows[gy - EXT_Y0][gx - EXT_X0]

    def runs(self, kinds):
        """Every maximal run of a wanted kind, as (kind, gx0, gx1, gy)."""
        for gy in range(EXT_Y0, EXT_Y1):
            gx = EXT_X0
            while gx < EXT_X1:
                kind = self.at(gx, gy)
                if kind not in kinds:
                    gx += 1
                    continue
                end = gx
                while end < EXT_X1 and self.at(end, gy) == kind:
                    end += 1
                yield kind, gx, end, gy
                gx = end


def ground(t):
    """The water, the beach and the distant woods, one slab per RUN.

    Per cell would be a hundred thousand boxes and a visible lattice; per run it
    is a couple of thousand, and the only edges left are the ones between two
    different kinds of ground — which are exactly the edges worth having.
    """
    layers = {
        # Above the base grass slab, whose top is at -0.10. At -0.34 the
        # distant woods finished at -0.12 and were buried under the very
        # lawn they were meant to cover: the map's outside stayed plain
        # green and only the individually-placed trees showed.
        WOOD: (-0.24, 0.22, 'canopy_dark'),
        BEACH: (-0.20, 0.20, 'shore'),
        SEA: (-0.30, 0.24, 'water'),
        RIVER: (-0.28, 0.22, 'water'),
    }
    n = 0
    for kind, x0, x1, gy in t.runs(layers.keys()):
        z, h, key = layers[kind]
        wx0, wy = world(x0, gy)
        wx1, _ = world(x1 - 1, gy)
        slab(f'{kind}{gy}_{x0}', (wx0 + wx1) / 2, wy, x1 - x0, 1.0, z, h, key)
        n += 1
    print(f'  {n} ground runs')


def deep_water(t, reach=3):
    """A darker channel where the water is wide, so the sea is not one flat
    blue. Only where every cell within [reach] is also water — a creek three
    cells across has no deep water in it."""
    def deep(gx, gy):
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                if t.at(gx + dx, gy + dy) not in (SEA, RIVER):
                    return False
        return True

    for gy in range(EXT_Y0, EXT_Y1):
        gx = EXT_X0
        while gx < EXT_X1:
            if t.at(gx, gy) not in (SEA, RIVER) or not deep(gx, gy):
                gx += 1
                continue
            end = gx
            while (end < EXT_X1 and t.at(end, gy) in (SEA, RIVER)
                   and deep(end, gy)):
                end += 1
            wx0, wy = world(gx, gy)
            wx1, _ = world(end - 1, gy)
            slab(f'deep{gy}_{gx}', (wx0 + wx1) / 2, wy, end - gx, 1.0,
                 -0.24, 0.2, 'water_deep')
            gx = end


def meadow(t, count=650):
    """Patches of a slightly different green over the base grass.

    Flat green over four thousand pixels is the same failure as a flat roof: a
    surface that large needs a break.

    ── Placed by HASH, not by the golden angle ──
    The golden angle spreads points evenly, which is why it is used for scatter
    everywhere else in this kit — but every point in it lies on one of a few
    spiral arms, and that is invisible for a dozen straw stalks and glaring for
    six hundred patches the size of a house. The map came out looking like
    ploughed farmland laid out in a whorl. A hash has no arms.

    The tones are also much closer to the base than they were: this is meant to
    read as grass that is not perfectly even, not as fields.
    """
    for i in range(count):
        gx = rb._hash01(f'mx{i}') * COLS
        gy = rb._hash01(f'my{i}') * ROWS
        if t.at(int(gx), int(gy)) != GRASS:
            continue
        j = rb._hash01(f'ms{i}')
        s = 4.0 + 9.0 * j * j
        x, y = world(gx, gy)
        # ABOVE the base slab, whose top is at -0.10. At -0.34 every patch
        # finished at -0.20 and was buried under the very lawn it was meant to
        # break up, which is why the middle of the map stayed one flat green.
        ob = slab(f'meadow{i}', x, y, s, s * (0.6 + 0.5 * j), -0.20, 0.12,
                  'grass_dry' if i % 3 else 'grass_dark')
        # Turned off the grid, so a patch is a patch rather than a field.
        ob.rotation_euler = (0, 0, rb._hash01(f'mr{i}') * 3.14159)


def _touches(t, gx, gy, kinds, reach=1):
    """Is any cell within [reach] one of [kinds]?"""
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            if t.at(gx + dx, gy + dy) in kinds:
                return True
    return False


def shoreline(t):
    """The band where the water meets the land, on both sides of the line.

    ── The single biggest thing missing (user 2026-08-09) ──
    A coast drawn as blue meeting sand is two flat colours with a step between
    them, and it is the longest edge on the map — every metre of the sea, the
    river and the lake shares it. Real water gets PALE where it is shallow
    enough to see the bottom, and paler still where it breaks. Three tones
    across four cells is the difference between a body of water and a blue
    shape.
    """
    for gy in range(EXT_Y0, EXT_Y1):
        for gx in range(EXT_X0, EXT_X1):
            kind = t.at(gx, gy)
            x, y = world(gx, gy)
            if kind in (SEA, RIVER):
                if _touches(t, gx, gy, (BEACH, GRASS, WOOD), reach=1):
                    slab(f'foam{gx}_{gy}', x, y, 1.0, 1.0, -0.26, 0.23, 'foam')
                elif _touches(t, gx, gy, (BEACH, GRASS, WOOD), reach=3):
                    slab(f'shal{gx}_{gy}', x, y, 1.0, 1.0, -0.27, 0.22,
                         'shallow')
            elif kind is BEACH and _touches(t, gx, gy, (SEA, RIVER), reach=1):
                # Wet sand: darker, and only the strip the water actually
                # reaches.
                slab(f'wet{gx}_{gy}', x, y, 1.0, 1.0, -0.19, 0.20, 'shore_wet')


class _Rng:
    """A little LCG, seeded by name.

    ── Why not rb._hash01, like everything else ──
    That hash is FNV-1a over a string, and for the strings a scatter feeds it —
    "flowersx1", "flowersx2", … — consecutive inputs stay close, so consecutive
    x and y come out correlated. At a dozen straw stalks nobody notices; at
    seven hundred flower clumps the map grew tidy horizontal ROWS of them
    (2026-08-09). A generator whose whole job is to decorrelate does not have
    that problem, and it is just as repeatable.
    """

    def __init__(self, name):
        self.s = 2166136261
        for ch in name:
            self.s = ((self.s ^ ord(ch)) * 16777619) & 0x7FFFFFFF

    def next(self):
        self.s = (self.s * 1103515245 + 12345) & 0x7FFFFFFF
        return self.s / 0x7FFFFFFF


def scatter(t, name, count, kinds, place, near=None, avoid_plot=True):
    """Lay [count] things on cells of [kinds], deterministically.

    One generator for every kind of clutter: the passes below differ only in
    what they are allowed to stand on and what they draw. Hashed rather than
    spiralled — see meadow() for what a golden angle does at this density.
    """
    rng = _Rng(name)
    made = 0
    i = 0
    while made < count and i < count * 60:
        i += 1
        gx = rng.next() * (EXT_X1 - EXT_X0) + EXT_X0
        gy = rng.next() * (EXT_Y1 - EXT_Y0) + EXT_Y0
        cx, cy = int(gx), int(gy)
        if t.at(cx, cy) not in kinds or not in_picture(cx, cy):
            continue
        if near is not None and not _touches(t, cx, cy, near, reach=2):
            continue
        if avoid_plot and (PLOT_X - 2 <= cx < PLOT_X + PLOT_SIZE + 2
                           and PLOT_Y - 2 <= cy < PLOT_Y + PLOT_SIZE + 2):
            continue
        x, y = world(gx, gy)
        place(f'{name}{made}', x, y, rng.next(), i)
        made += 1
    print(f'  {made} {name}')


def detail(t):
    """Everything that turns ground into a PLACE.

    All of it is scatter, and all of it is sized to be legible at the map's own
    resolution. The order is the order the eye finds them: what breaks the
    silhouette first (boulders, bushes), then what tells you about the ground
    (reeds at the water, gorse on the heath), then what tells you people are
    here (worn tracks).
    """
    def boulder(nm, x, y, j, i):
        h = 0.4 + 0.6 * j
        w = 0.55 + 0.9 * j
        ob = rb.box(f'{nm}a', x, y, 0.0, w, w * 0.82, h,
                    tmat('rock' if i % 2 else 'rock_dark'))
        ob.rotation_euler = (0, 0, j * 3.1)
        if j > 0.55:
            ob2 = rb.box(f'{nm}b', x + w * 0.4, y - w * 0.3, 0.0, w * 0.55,
                         w * 0.5, h * 0.6, tmat('rock_dark'))
            ob2.rotation_euler = (0, 0, j * 1.7)

    def bush(nm, x, y, j, i):
        w = 0.6 + 0.7 * j
        tone = 'canopy_light' if i % 3 else 'canopy'
        ob = rb.box(f'{nm}a', x, y, 0.0, w, w * 0.9, 0.34 + 0.3 * j, tmat(tone))
        ob.rotation_euler = (0, 0, j * 2.4)
        rb.box(f'{nm}b', x + w * 0.22, y + w * 0.18, 0.0, w * 0.6, w * 0.55,
               0.5 + 0.34 * j, tmat('canopy_dark' if i % 2 else tone))

    def reeds(nm, x, y, j, i):
        # A bed, not a blade: five thin uprights inside one cell read as reeds
        # where one would read as a stray stick.
        for k in range(5):
            a = rb._hash01(f'{nm}r{k}')
            b = rb._hash01(f'{nm}q{k}')
            rb.box(f'{nm}{k}', x + (a - 0.5) * 0.8, y + (b - 0.5) * 0.8, 0.0,
                   0.11, 0.11, 0.55 + 0.5 * a, tmat('reed'))

    def flowers(nm, x, y, j, i):
        tone = 'gorse' if i % 2 else 'heather'
        for k in range(4):
            a = rb._hash01(f'{nm}f{k}')
            b = rb._hash01(f'{nm}g{k}')
            rb.box(f'{nm}{k}', x + (a - 0.5) * 1.1, y + (b - 0.5) * 1.1, 0.0,
                   0.3 + 0.2 * a, 0.3 + 0.2 * b, 0.16 + 0.12 * a, tmat(tone))

    def stone(nm, x, y, j, i):
        # In the water: a boulder the river has not moved.
        ob = rb.box(f'{nm}a', x, y, -0.06, 0.45 + 0.5 * j, 0.4 + 0.4 * j,
                    0.26 + 0.2 * j, tmat('rock' if i % 2 else 'rock_dark'))
        ob.rotation_euler = (0, 0, j * 2.9)

    def pebbles(nm, x, y, j, i):
        for k in range(3):
            a = rb._hash01(f'{nm}p{k}')
            b = rb._hash01(f'{nm}o{k}')
            ob = rb.box(f'{nm}{k}', x + (a - 0.5) * 1.2, y + (b - 0.5) * 1.2,
                        0.0, 0.24 + 0.18 * a, 0.2 + 0.16 * b, 0.1,
                        tmat('rock' if k % 2 else 'rock_dark'))
            ob.rotation_euler = (0, 0, a * 3.0)

    def scrape(nm, x, y, j, i):
        # Bare earth: a patch worn through the turf. Cheap, and it does more for
        # "somebody walks here" than any amount of green.
        ob = slab(f'{nm}', x, y, 1.6 + 2.6 * j, 1.2 + 2.0 * j, -0.19, 0.11,
                  'dirt')
        ob.rotation_euler = (0, 0, j * 3.1)

    scatter(t, 'boulder', 420, (GRASS,), boulder)
    scatter(t, 'bush', 1600, (GRASS,), bush)
    scatter(t, 'reeds', 700, (BEACH,), reeds, near=(SEA, RIVER))
    scatter(t, 'flowers', 1100, (GRASS,), flowers)
    scatter(t, 'stone', 150, (SEA, RIVER), stone, near=(BEACH,))
    scatter(t, 'pebbles', 450, (BEACH,), pebbles)
    scatter(t, 'scrape', 300, (GRASS,), scrape)


def canopy_mass(t, name='cm'):
    """The forest BEYOND the map, given a CANOPY instead of a flat colour.

    ── The biggest bare thing left (user 2026-08-09) ──
    "diese grossen grünen unbepflanzten Flächen möchte ich nicht". Outside the
    playfield the woods were one dark slab — correct in tone, and completely
    flat, so a third of the picture was an empty green field with a line of
    trees along its inner edge. From above, a forest is a lumpy surface of
    crowns at different heights, and that is all this is: one blob per few
    cells, three tones, three heights, each casting its own small shadow.
    Cheaper than a tree apiece by a factor of four, and at this size the
    difference between a crown and a whole tree is invisible anyway.

    Restricted to what the frame can show — half the padded range falls outside
    the picture, and objects there cost the same and are seen by nobody.
    """
    rng = _Rng('canopy')
    n = 0
    for gy in range(EXT_Y0, EXT_Y1):
        for gx in range(EXT_X0, EXT_X1):
            if t.at(gx, gy) is not WOOD or not in_picture(gx, gy):
                continue
            if rng.next() > 0.36:
                continue
            j, k, m = rng.next(), rng.next(), rng.next()
            w = 1.3 + 1.6 * j
            x, y = world(gx + (k - 0.5) * 0.9, gy + (m - 0.5) * 0.9)
            tone = ('canopy' if j > 0.62 else
                    'canopy_light' if j > 0.3 else 'canopy_dark')
            ob = rb.box(f'{name}{n}', x, y, 0.0, w, w * 0.85,
                        0.5 + 1.5 * j, tmat(tone))
            ob.rotation_euler = (0, 0, k * 3.1)
            n += 1
    print(f'  {n} canopy')


def tree(name, x, y, h, seed):
    """One faceted tree. Two shapes only, and both are stacks of boxes.

    A tree here is a handful of pixels on the map, so its whole job is
    SILHOUETTE: a tapering stack reads as conifer, a fat double blob reads as
    broadleaf, and nothing finer than that survives the size it is drawn at.
    """
    rb.box(f'{name}_t', x, y, 0.0, h * 0.13, h * 0.13, h * 0.44, tmat('trunk'))
    tone = ('canopy' if seed % 3 else
            'canopy_light' if seed % 2 else 'canopy_dark')
    if seed % 2:
        for i in range(3):
            f = 1.0 - i * 0.3
            rb.box(f'{name}_c{i}', x, y, h * (0.32 + i * 0.24),
                   h * 0.62 * f, h * 0.62 * f, h * 0.3, tmat(tone))
    else:
        rb.box(f'{name}_c0', x, y, h * 0.3, h * 0.76, h * 0.76, h * 0.44,
               tmat(tone))
        rb.box(f'{name}_c1', x, y, h * 0.64, h * 0.5, h * 0.5, h * 0.32,
               tmat('canopy_dark' if seed % 3 else 'canopy_light'))


def forest(t, name='wd'):
    """Woods along the three rims that are not sea (user 2026-08-09).

    Placed by DISTANCE FROM THE RIM rather than by any curve, so the band
    follows the map's own edges instead of an ellipse laid over them — which is
    what the first attempt did, and it drew a thin arc through the corners
    rather than a wood along the sides.

    It straddles the rim: dense a little way outside, thinning inland, so the
    playfield's edge is a wood you are looking into rather than a line the trees
    stop on. Past [WOOD_EDGE] the individual trees give way to the flat dark
    mass laid by ground(), and this band is the transition between them.
    """
    placed = 0
    for gy in range(EXT_Y0, EXT_Y1):
        for gx in range(EXT_X0, EXT_X1):
            d = rim_distance(gx, gy)
            if d > WOOD_BAND or d < WOOD_EDGE - 6:
                continue
            if t.at(gx, gy) != GRASS:
                continue
            # Not on the doorstep of the starting settlement.
            if (PLOT_X - 7 <= gx < PLOT_X + PLOT_SIZE + 7
                    and PLOT_Y - 7 <= gy < PLOT_Y + PLOT_SIZE + 7):
                continue
            # Dense at the rim, thinning inland — an inside edge that is a
            # scatter rather than a line.
            near = (WOOD_BAND - d) / float(WOOD_BAND - WOOD_EDGE)
            if rb._hash01(f'f{gx}:{gy}') > 0.10 + 0.62 * near * near:
                continue
            j = rb._hash01(f'j{gx}:{gy}')
            k = rb._hash01(f'k{gx}:{gy}')
            x, y = world(gx + j * 0.8 - 0.4, gy + k * 0.8 - 0.4)
            tree(f'{name}{placed}', x, y, 1.9 + 1.9 * j, gx * 7 + gy)
            placed += 1
    print(f'  {placed} trees')


# ── The water, as Dart ─────────────────────────────────────
def emit_dart(t, path):
    """Write the water mask as a Dart source file: row runs, one line a row.

    Only the REAL cells. The sea drawn beyond the map's edge is scenery, and a
    rule about cells that do not exist is a rule nothing can ever ask about.
    """
    runs = []
    for gy in range(ROWS):
        row, gx = [], 0
        while gx < COLS:
            if is_water(t.at(gx, gy)):
                end = gx
                while end < COLS and is_water(t.at(end, gy)):
                    end += 1
                row.append((gx, end))
                gx = end
            else:
                gx += 1
        runs.append(row)
    cells = sum(e - s for row in runs for s, e in row)
    body = ',\n'.join(
        '  [' + ', '.join(f'{s}, {e}' for s, e in row) + ']' for row in runs)
    text = (
        '// GENERATED by tool/blender/terrain.py \u2014 do not edit by hand.\n'
        '//\n'
        '// The same classify() that drew assets/images/map_background.png\n'
        '// wrote this, so the coastline you can SEE and the coastline you can\n'
        '// BUILD against are one thing. Re-render the background and this file\n'
        '// is rewritten with it; edit this file alone and the two immediately\n'
        '// disagree, which is the whole failure it exists to prevent.\n'
        '//\n'
        f'// {cells} water cells of {COLS * ROWS}.\n'
        '\n'
        '/// Water, row by row, as flat [start, end) column pairs. Row y is\n'
        '/// index y.\n'
        'const List<List<int>> kWaterRuns = [\n'
        f'{body},\n'
        '];\n'
        '\n'
        '/// True when (x, y) is sea or river \u2014 the cells the settlement may\n'
        '/// not build on (user 2026-08-09: "Der Fluss ist nicht bebaubar").\n'
        '///\n'
        '/// Off-map counts as NOT water: callers already range-check, and\n'
        '/// answering "yes, water" for a cell that does not exist would quietly\n'
        '/// turn every out-of-bounds bug into a placement refusal instead of an\n'
        '/// error.\n'
        'bool isWaterCell(int x, int y) {\n'
        '  if (y < 0 || y >= kWaterRuns.length || x < 0) return false;\n'
        '  final row = kWaterRuns[y];\n'
        '  for (var i = 0; i < row.length; i += 2) {\n'
        '    if (x >= row[i] && x < row[i + 1]) return true;\n'
        '  }\n'
        '  return false;\n'
        '}\n'
    )
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)
    print(f'  wrote {os.path.relpath(path, _ROOT)}  ({cells} water cells)')


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='assets/images/map_background.png')
    ap.add_argument('--dart',
                    default='lib/features/settlement/data/water_cells.dart')
    # 0.4 of a screen pixel per map pixel. The map is 10240 px across at 1:1,
    # which is a 52-megapixel render and a texture no phone should decode; the
    # ground is a backdrop and is allowed to be soft, unlike the buildings and
    # the roads drawn on top of it.
    ap.add_argument('--scale', type=float, default=0.4)
    ap.add_argument('--no-render', action='store_true',
                    help='rewrite the Dart mask only')
    args = ap.parse_args(argv)

    t = Terrain()

    # The starting plot must be dry. Everything else about the terrain is taste;
    # this one is a rule, and a river through the square the player is handed at
    # minute one would be found by the player rather than by us.
    wet = [(x, y)
           for y in range(PLOT_Y, PLOT_Y + PLOT_SIZE)
           for x in range(PLOT_X, PLOT_X + PLOT_SIZE)
           if is_water(t.at(x, y))]
    if wet:
        raise SystemExit(
            f'{len(wet)} water cells inside the starting plot, e.g. {wet[0]} '
            '\u2014 move the river (river_spine) or the coast (coast_at)')

    emit_dart(t, os.path.join(_ROOT, args.dart))
    if args.no_render:
        return

    rb.clear()
    # The base: one slab big enough for the whole PICTURE, not just the map.
    # A diamond COLS x ROWS has a bounding box whose corners sit about half the
    # far dimension outside every rim, so the ground has to reach (COLS + ROWS)
    # across whichever way it is measured.
    span = (COLS + ROWS) * 1.15
    slab('ground', 0, 0, span, span, -0.4, 0.3, 'grass')
    meadow(t)
    ground(t)
    deep_water(t)
    shoreline(t)
    canopy_mass(t)
    forest(t)
    detail(t)

    rb.vary_tones(spread=0.05)
    rb.bevel_everything()
    rb.light()
    # Framed on the GRID, exactly as a building is framed on its footprint —
    # which is what guarantees the picture lines up with iso_grid.dart instead
    # of merely looking as though it does.
    # fit=False: this picture must be EXACTLY the grid's bounding box, or
    # the ground stops lining up with iso_grid.dart.
    rb.frame(COLS, ROWS, args.scale, 0.5, fit=False)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for e in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if e in engines:
            scene.render.engine = e
            break
    # OPAQUE: this is the ground, and everything else is drawn on top of it.
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = os.path.abspath(os.path.join(_ROOT, args.out))
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


main()
