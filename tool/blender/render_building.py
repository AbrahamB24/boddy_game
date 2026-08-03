"""Render one low-poly building, isometric, straight onto its footprint.

    blender --background --python tool/blender/render_building.py -- \
        --preset breeding_hut --out docs/renders/breeding_hut.png

── Why Blender and not a prompt ──
The two things an image model gets wrong every time are the two things geometry
gets right for free: PARALLEL projection (an orthographic camera cannot invent a
vanishing point) and the BASE covering exactly W x H tiles. Render it and the
three art-fit numbers in Dev Mode stay 1 / 0.5 / 0 forever.

── The camera ──
2:1 dimetric, the app's own shape. A horizontal unit square must come out twice
as wide as it is tall, and that alone fixes the elevation. Seen from 45 deg of
azimuth, a unit tile is cos(45) wide on screen and sin(e) * cos(45) tall — the
cos(45) is in BOTH, because the tile's edges are themselves at 45 deg to the
view. It cancels, and 2 * sin(e) = 1 leaves e = 30 deg. Camera X rotation 60,
Z rotation 45: the numbers everyone quotes, for a reason.

── The framing ──
Nothing here is eyeballed. The four ground corners are PROJECTED through the
camera and the ortho scale and shift are solved so that they land exactly on the
image's left and right edges with the near corner on the bottom edge. That is
what makes the render drop onto the tiles with no fudging.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

# The app's grid, from iso_grid.dart. One tile = one Blender unit.
TILE_W = 64
TILE_H = 32
# Pixels per tile in the render. 4 gives a 3x4 building 896 px of base — plenty
# to downscale from, and the app scales to the footprint anyway.
SCALE = 4

ELEVATION = math.degrees(math.asin(0.5))  # 30 — see the header


# ── The style: fantasy Roman-medieval (user 2026-08-03) ────
# Roman gives the ROOF and the arch, medieval gives the timber and the pitch,
# fantasy gives permission to saturate all of it. In practice three signals do
# almost all the work, and a building that has them reads correctly even at
# 224 px where nothing else survives:
#
#   1. A TERRACOTTA roof. The single loudest signal, and the reason this style
#      suits the game: the material ladder already refines clay in tier II, so
#      the roofs literally are what the settlement learns to make.
#   2. PALE walls — limestone, travertine, lime stucco — under that roof. The
#      contrast between hot roof and cool wall IS the look.
#   3. A STONE PLINTH the building stands on. Romans never set a wall on soil,
#      and it also solves an art problem: the base reads as deliberately
#      founded on its tiles instead of dropped onto them.
#
# Timber is trim, not structure: beams, posts, shutters, doors. A building that
# is mostly timber has slid back to the Northern-European hut it came from.
#
# ── Matched to the monsters (user 2026-08-03) ──
# Look at Blazeling and Droplet and the rule is not subtle: each is ONE hue in
# four to six tonal steps, plus a single small accent — the whole orange
# creature with one yellow flame, the whole cyan creature with two dark eyes.
# No greys anywhere. Everything is saturated, and the range runs from near-white
# to a deep, still-saturated shadow.
#
# The buildings were doing the opposite: ten independent hues, three of them
# effectively grey. So the palette is now ONE warm earth family — terracotta
# through ochre through cream — with green and the banner's red as the only
# outsiders, kept to a few square pixels each. That is what makes a building
# stand next to a monster and look like it came from the same world, and it
# costs nothing but a retune.
PALETTE = {
    'tile': (0.80, 0.30, 0.13),        # terracotta pantile — the loudest note
    'tile_dark': (0.56, 0.18, 0.09),   # its shadow side and the ridge
    'stucco': (0.96, 0.87, 0.69),      # lime render, the wall default
    'travertine': (0.88, 0.71, 0.47),  # cut stone: ochre, NOT grey
    'ashlar': (0.62, 0.46, 0.29),      # the plinth and any heavy masonry
    'oak': (0.44, 0.24, 0.12),         # beams, doors, shutters
    'oak_light': (0.63, 0.38, 0.18),   # posts catching the sun
    'iron': (0.31, 0.22, 0.19),        # fittings — warm dark, not blue-black
    'gold': (0.98, 0.77, 0.22),        # finials and lamp-light
    'dark': (0.15, 0.07, 0.04),        # an opening, read as depth
    'banner': (0.74, 0.13, 0.18),      # the one saturated cloth per building
    'sand': (0.90, 0.77, 0.52),        # trodden ground inside a court
    'straw': (0.94, 0.77, 0.30),       # bedding, thatch, nests
    'leaf': (0.37, 0.53, 0.22),        # the only green; use it sparingly
}

# How hard every edge is cut back. This is the OTHER half of matching the
# monsters: their surfaces are covered in small, irregular facets, and a box has
# none at all — it has three faces and three tones and that is the end of it.
# A bevel gives every edge its own strip catching its own amount of light, which
# is the same trick at building scale.
BEVEL_WIDTH = 0.028
BEVEL_SEGMENTS = 2


# ── Materials ──────────────────────────────────────────────
def flat(name, rgb):
    """One flat colour. No specular, no roughness games — a facet is a facet."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = 1.0
    # Renamed between Blender versions; a highlight is the one thing flat
    # shading must not have, but it is not worth dying over.
    for key in ('Specular IOR Level', 'Specular'):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = 0.0
            break
    return mat


def box(name, x, y, z, sx, sy, sz, mat):
    """A box by its CENTRE-BOTTOM, because buildings stand on the ground."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z + sz / 2))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def gable(name, x, y, z, sx, sy, h, mat, overhang=0.25):
    """A pitched roof: a prism, so the two slopes are two flat facets."""
    sx += overhang * 2
    sy += overhang * 2
    verts = [
        (-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0),
        (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0),
        (0, -sy / 2, h), (0, sy / 2, h),
    ]
    faces = [(0, 1, 4), (2, 3, 5), (0, 4, 5, 3), (1, 2, 5, 4), (0, 3, 2, 1)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


_MATS = {}


def mat(key):
    """A palette colour, made once. Reaching for a raw RGB instead of a palette
    key is how a set of buildings stops matching after the third one."""
    if key not in _MATS:
        _MATS[key] = flat(key, PALETTE[key])
    return _MATS[key]


def hip_roof(name, x, y, z, sx, sy, h, key='tile', overhang=0.3, ridge=0.45):
    """The Roman roof: four slopes falling to a short ridge.

    A gable shows one big triangle to whichever side you face, which at this
    camera angle is a blank wall of colour. A hip roof always shows two slopes
    at different angles to the sun, so it shades itself — which is the whole
    reason low-poly reads as solid rather than as coloured paper.

    [ridge] is the ridge's length as a fraction of the long side. At 0 this is
    a pyramid; at 1 it is a gable. Around 0.45 is the shape that says "Roman".
    """
    sx += overhang * 2
    sy += overhang * 2
    long_y = sy >= sx
    r = (sy if long_y else sx) * ridge / 2
    verts = [
        (-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0),
        (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0),
    ]
    if long_y:
        verts += [(0, -r, h), (0, r, h)]
    else:
        verts += [(-r, 0, h), (r, 0, h)]
    faces = ([(0, 1, 4), (2, 3, 5), (0, 4, 5, 3), (1, 2, 5, 4), (0, 3, 2, 1)]
             if long_y else
             [(1, 2, 5), (3, 0, 4), (0, 1, 5, 4), (2, 3, 4, 5), (0, 3, 2, 1)])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat(key))
    for p in ob.data.polygons:
        p.use_smooth = False

    # The ridge cap, in the darker tile. It must sit DOWN in the ridge, not on
    # top of it: proud of the apex it reads as a beam laid across the roof, and
    # together with the hip lines that beam looks like a cross.
    cap_l, cap_w, cap_h = 2 * r, 0.14, 0.08
    box(f'{name}_ridge', x, y, z + h - cap_h * 0.8,
        cap_l if long_y is False else cap_w,
        cap_w if long_y is False else cap_l,
        cap_h, mat('tile_dark'))
    return ob


def plinth(name, x, y, sx, sy, h=0.22, key='ashlar'):
    """The stone course a wall stands on. Never build straight onto the soil."""
    return box(name, x, y, 0, sx, sy, h, mat(key))


def arch(name, x, y, z, w, h, depth, key='dark', segments=4, facing='y'):
    """An opening with a rounded head, faceted like everything else.

    Drawn as the DARK inside rather than as a frame: at this size an arch is
    read by its silhouette against a pale wall, and an outline around a hole
    the same colour as the wall is not a silhouette.
    """
    r = w / 2
    straight = max(0.0, h - r)
    pts = [(-r, 0.0), (-r, straight)]
    for i in range(1, segments):
        a = math.pi * i / (2 * segments)
        pts.append((-r * math.cos(a), straight + r * math.sin(a)))
    pts.append((0.0, straight + r))
    pts += [(-px, py) for px, py in reversed(pts[:-1])]

    verts, faces = [], []
    for px, pz in pts:
        verts.append((px, -depth / 2, pz))
        verts.append((px, depth / 2, pz))
    n = len(pts)
    for i in range(n - 1):
        faces.append((2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2))
    faces.append(tuple(range(0, 2 * n, 2)))          # the flat back
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    # Built in the XZ plane looking down -Y; a wall facing +X needs it turned.
    if facing == 'x':
        ob.rotation_euler = (0, 0, math.radians(90))
    ob.data.materials.append(mat(key))
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def wall_box(name, x, y, z, along, thick, height, material, facing='y'):
    """A box measured ALONG a wall and THROUGH it, whichever way the wall runs.

    Every piece of trim — sills, shutters, rails — is naturally described that
    way, and writing it as sx/sy means writing each one twice.
    """
    sx, sy = (along, thick) if facing == 'y' else (thick, along)
    return box(name, x, y, z, sx, sy, height, material)


# ── Ornament ───────────────────────────────────────────────
# Detail here is not decoration for its own sake — it is what tells the eye how
# BIG something is. A blank wall has no scale; a wall with a course of dentils
# under its eaves is unmistakably a building rather than a box. Everything below
# is sized so it still contributes at 224 px, where it stops being readable as
# itself and becomes texture. That is the correct outcome, not a failure: at
# life size you should read "carved", not count the carvings.


def pantiles(name, x, y, z, sx, sy, h, ridge=0.45, key='tile_dark',
             overhang=0.3, courses=10, lip=0.04):
    """Tile courses stepping up a hip roof, parallel to the eaves.

    The roof is the largest surface on any of these buildings, and flat it is a
    plate of colour.

    The first attempt ran ribs DOWN the slope, the way a real pantile does, and
    it looked broken: on a hip the slope is a trapezoid, so each rib had to stop
    at a different height, and their ends stood proud of the hip line in mid
    air — a staircase of snapped sticks. Courses have no ends to leave hanging.
    Each one is the roof's own horizontal cross-section at that height, so it
    follows the hips exactly, for free, at any footprint.
    """
    sx += overhang * 2
    sy += overhang * 2
    long_y = sy >= sx
    r = (sy if long_y else sx) * ridge / 2

    for i in range(courses):
        f = i / courses
        # The roof's cross-section at this height: it narrows to the ridge on
        # the short axis and to the ridge's own length on the long one.
        if long_y:
            hx = (sx / 2) * (1 - f)
            hy = sy / 2 - (sy / 2 - r) * f
        else:
            hx = sx / 2 - (sx / 2 - r) * f
            hy = (sy / 2) * (1 - f)
        if hx <= 0.06 or hy <= 0.06:
            break
        box(f'{name}_{i}', x, y, z + f * h,
            2 * hx + lip, 2 * hy + lip, 0.055, mat(key))


def hip_ridges(name, x, y, z, sx, sy, h, ridge=0.45, overhang=0.3,
               key='tile_dark', width=0.15, thick=0.09):
    """Ridge tiles capping the four diagonal hips.

    The last raw edge on the roof. Every other line had been finished — the
    ridge is capped, the eaves are edged with antefixes, the slopes are
    coursed — and the four corners were still bare geometry meeting at an
    angle, which is exactly where the eye goes to check whether a thing was
    built or generated.
    """
    sx += overhang * 2
    sy += overhang * 2
    long_y = sy >= sx
    r = (sy if long_y else sx) * ridge / 2
    for sxs in (-1, 1):
        for sys in (-1, 1):
            start = Vector((sxs * sx / 2, sys * sy / 2, 0))
            end = (Vector((0, sys * r, h)) if long_y
                   else Vector((sxs * r, 0, h)))
            d = end - start
            ob = box(f'{name}_{sxs}_{sys}', 0, 0, 0, width, d.length, thick,
                     mat(key))
            # to_track_quat aims the box's own +Y down the hip; doing this by
            # euler means one angle per corner and four chances to get a sign
            # wrong.
            ob.rotation_euler = d.to_track_quat('Y', 'Z').to_euler()
            mid = start + d / 2
            ob.location = (x + mid.x, y + mid.y, z + mid.z + 0.04)


def lantern(name, x, y, z, drop=0.3, key='iron'):
    """A hanging lamp: chain, iron cage, a hot centre.

    Small and worth it. A lit point at eye level is the one thing that tells
    you a building is OCCUPIED, and occupancy is most of what separates a
    settlement from a diorama."""
    box(f'{name}_chain', x, y, z - drop, 0.035, 0.035, drop, mat(key))
    box(f'{name}_cap', x, y, z - drop - 0.09, 0.15, 0.15, 0.05, mat(key))
    box(f'{name}_glass', x, y, z - drop - 0.24, 0.13, 0.13, 0.16, mat('gold'))
    box(f'{name}_frame', x, y, z - drop - 0.26, 0.16, 0.16, 0.05, mat(key))


def sconce(name, x, y, z, reach=0.24, key='iron', facing='y'):
    """A lamp on a bracket off a wall. Same job as the lantern where there is
    nothing overhead to hang one from."""
    ox = -reach if facing == 'x' else 0.0
    oy = -reach if facing == 'y' else 0.0
    wall_box(f'{name}_arm', x + ox / 2, y + oy / 2, z, 0.05, reach, 0.05,
             mat(key), facing='y' if facing == 'y' else 'x')
    box(f'{name}_arm2', x + ox / 2, y + oy / 2, z,
        abs(ox) + 0.05 if ox else 0.05, abs(oy) + 0.05 if oy else 0.05,
        0.05, mat(key))
    box(f'{name}_glass', x + ox, y + oy, z - 0.13, 0.1, 0.1, 0.13,
        mat('gold'))
    box(f'{name}_hood', x + ox, y + oy, z - 0.02, 0.14, 0.14, 0.05, mat(key))


def straw_bale(name, x, y, z, sx=0.44, sy=0.3, h=0.28, key='straw'):
    """A bound bale. Two dark bands, and a yellow box becomes a bale."""
    box(f'{name}_body', x, y, z, sx, sy, h, mat(key))
    for t in (-0.25, 0.25):
        box(f'{name}_band{t}', x + sx * t, y, z, 0.05, sy + 0.03, h + 0.02,
            mat('oak'))


def straw_scatter(name, x, y, z, r, n=14, key='straw'):
    """Loose straw on the ground. Deterministic, not random: a render that
    differs between runs cannot be compared against the one before it."""
    for i in range(n):
        a = 2.399963 * i                       # the golden angle, so it spreads
        rad = r * math.sqrt((i + 0.5) / n)
        ob = box(f'{name}_{i}', x + rad * math.cos(a), y + rad * math.sin(a),
                 z, 0.17, 0.05, 0.025, mat(key))
        ob.rotation_euler = (0, 0, a)


def frieze(name, x, y, z, span, key='travertine', pitch=0.17, facing='y'):
    """A running band of blocks along a wall — the plainest ornament there is,
    and the one that most reliably reads as "decorated" at a distance."""
    n = max(2, int(span / pitch))
    for i in range(n):
        t = -span / 2 + span * (i + 0.5) / n
        wall_box(f'{name}_{i}', x + (t if facing == 'y' else 0),
                 y + (0 if facing == 'y' else t), z,
                 pitch * 0.5, 0.06, 0.1, mat(key), facing=facing)


def garland(name, x, y, z, span, sag=0.16, key='leaf', facing='y'):
    """A swag hung between two points. Built as a chain of blocks stepping down
    and back up, because a real curve here would be smooth — and nothing else
    in this world is."""
    n = 7
    for i in range(n):
        t = i / (n - 1)
        off = -span / 2 + span * t
        dip = sag * math.sin(math.pi * t)
        wall_box(f'{name}_{i}', x + (off if facing == 'y' else 0),
                 y + (0 if facing == 'y' else off), z - dip,
                 span / n * 1.15, 0.07, 0.11, mat(key), facing=facing)


def mosaic(name, x, y, z, sx, sy, key_a='travertine', key_b='tile',
           tile=0.26):
    """A chequered court floor. Ground with a pattern on it reads as PAVED, and
    paved ground is the difference between a courtyard and a patch of dirt."""
    nx, ny = max(1, int(sx / tile)), max(1, int(sy / tile))
    for i in range(nx):
        for j in range(ny):
            if (i + j) % 2:
                continue
            box(f'{name}_{i}_{j}',
                x - sx / 2 + sx * (i + 0.5) / nx,
                y - sy / 2 + sy * (j + 0.5) / ny,
                z, sx / nx * 0.9, sy / ny * 0.9, 0.02,
                mat(key_a if (i * 3 + j) % 4 else key_b))


def acroterion(name, x, y, z, sx, sy, ridge=0.45, overhang=0.3, key='gold'):
    """The ornaments capping the ends of a ridge. Two of them, and the roofline
    stops just ending and starts finishing."""
    sx += overhang * 2
    sy += overhang * 2
    long_y = sy >= sx
    r = (sy if long_y else sx) * ridge / 2
    for sign in (-1, 1):
        ax = x if long_y else x + sign * r
        ay = y + sign * r if long_y else y
        box(f'{name}_stem_{sign}', ax, ay, z - 0.06, 0.11, 0.11, 0.12,
            mat('tile_dark'))
        box(f'{name}_{sign}', ax, ay, z + 0.06, 0.07, 0.07, 0.08, mat(key))


def column(name, x, y, z, r, h, key='travertine', sides=8):
    """A round column, faceted. Eight sides: at six it reads as a post, at
    sixteen the facets stop showing and it leaves the art style."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=r, depth=h,
                                        location=(x, y, z + h / 2))
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(mat(key))
    for p in ob.data.polygons:
        p.use_smooth = False
    box(f'{name}_base', x, y, z, r * 2.6, r * 2.6, 0.1, mat(key))
    box(f'{name}_cap', x, y, z + h - 0.11, r * 2.7, r * 2.7, 0.13, mat(key))
    return ob


def pot(name, x, y, z, r=0.16, h=0.42, key='tile'):
    """An amphora, in four blocks. Clutter with a job: it is the only thing in
    the kit that says PEOPLE work here."""
    box(f'{name}_foot', x, y, z, r * 0.9, r * 0.9, 0.05, mat('tile_dark'))
    box(f'{name}_belly', x, y, z + 0.04, r * 2, r * 2, h * 0.55, mat(key))
    box(f'{name}_neck', x, y, z + 0.04 + h * 0.55, r * 1.05, r * 1.05, h * 0.3,
        mat(key))
    box(f'{name}_rim', x, y, z + 0.02 + h * 0.85, r * 1.5, r * 1.5, 0.07,
        mat('tile_dark'))


def brazier(name, x, y, z, h=0.62, key='iron'):
    """A standing fire. The only light source in the palette, and the reason a
    doorway at dusk reads as somewhere you would actually walk in."""
    # Stone stem, iron bowl. Iron is the coldest colour in the palette, and a
    # whole brazier of it reads as a blue machine standing in a warm courtyard.
    # Keep it to the one part that has to look like metal.
    box(f'{name}_foot', x, y, z, 0.19, 0.19, 0.05, mat('travertine'))
    box(f'{name}_stem', x, y, z + 0.04, 0.07, 0.07, h, mat('travertine'))
    box(f'{name}_bowl', x, y, z + h, 0.22, 0.22, 0.09, mat(key))
    box(f'{name}_fire', x, y, z + h + 0.07, 0.14, 0.14, 0.1, mat('gold'))


def pergola(name, x, y, z, sx, sy, h=1.0, posts=2, key='oak'):
    """Posts and cross-beams over a yard. Roofless on purpose: it shades the
    court without hiding what is IN the court, which is the whole point of
    having an open court in the first place."""
    for sxs in (-1, 1):
        for sys in (-1, 1):
            box(f'{name}_post_{sxs}_{sys}', x + sxs * sx / 2, y + sys * sy / 2,
                z, 0.14, 0.14, h, mat(key))
    for sys in (-1, 1):
        box(f'{name}_beam_{sys}', x, y + sys * sy / 2, z + h - 0.1,
            sx + 0.4, 0.11, 0.12, mat(key))
    for i in range(posts * 2 + 1):
        bx = x - sx / 2 + sx * i / (posts * 2)
        box(f'{name}_rafter_{i}', bx, y, z + h, 0.08, sy + 0.5, 0.08,
            mat(key))


def nest(name, x, y, z, r, key='straw'):
    """A ring of straw. Eggs lying on bare ground are eggs someone dropped."""
    n = 10
    for i in range(n):
        a = 2 * math.pi * i / n
        box(f'{name}_{i}', x + r * math.cos(a), y + r * math.sin(a), z,
            0.19, 0.19, 0.1, mat(key))
    box(f'{name}_bed', x, y, z, r * 1.7, r * 1.7, 0.05, mat(key))


def plant(name, x, y, z, r=0.13, key='leaf'):
    """A potted shrub. Green is the rarest colour in the palette on purpose —
    two of these read as tended, five read as a garden centre."""
    box(f'{name}_pot', x, y, z, r * 2, r * 2, 0.18, mat('tile'))
    box(f'{name}_rim', x, y, z + 0.16, r * 2.3, r * 2.3, 0.05,
        mat('tile_dark'))
    box(f'{name}_bush', x, y, z + 0.2, r * 2.4, r * 2.4, 0.2, mat(key))
    box(f'{name}_top', x, y, z + 0.38, r * 1.5, r * 1.5, 0.14, mat(key))


def trough(name, x, y, z, sx, sy, key='ashlar'):
    """A stone water trough. Livestock needs drinking, and a building that
    shows the chore reads as used rather than as displayed."""
    box(f'{name}_body', x, y, z, sx, sy, 0.22, mat(key))
    box(f'{name}_water', x, y, z + 0.18, sx - 0.12, sy - 0.12, 0.05,
        mat('iron'))
    for sign in (-1, 1):
        box(f'{name}_end_{sign}', x + sign * sx / 2, y, z,
            0.07, sy + 0.04, 0.28, mat('travertine'))


def dentils(name, x, y, z, sx, sy, key='travertine', pitch=0.2, size=0.09):
    """A course of small blocks under the eaves. The most Roman thing there is,
    and the cheapest scale cue in the whole kit."""
    for axis in (0, 1):
        span = sx if axis == 0 else sy
        n = max(2, int(span / pitch))
        for i in range(n):
            t = -span / 2 + span * (i + 0.5) / n
            for sign in (-1, 1):
                if axis == 0:
                    bx, by = x + t, y + sign * sy / 2
                else:
                    bx, by = x + sign * sx / 2, y + t
                box(f'{name}_{axis}_{i}_{sign}', bx, by, z,
                    size, size, size * 1.1, mat(key))


def antefixes(name, x, y, z, sx, sy, key='tile_dark', pitch=0.34):
    """Upright tile-ends standing along the eaves. Roman roofs are edged, not
    cut off, and the little row of them is what stops the roof's bottom edge
    reading as a straight machine cut."""
    for sign in (-1, 1):
        n = max(2, int(sx / pitch))
        for i in range(n):
            bx = x - sx / 2 + sx * (i + 0.5) / n
            box(f'{name}_{i}_{sign}', bx, y + sign * sy / 2, z,
                0.12, 0.07, 0.13, mat(key))


def window(name, x, y, z, w, h, depth, shutters=True, facing='y'):
    """An arched window: dark opening, travertine surround, oak shutters.

    [depth] is how far the surround stands behind the hole. Same rule as the
    doorway — the surround is BEHIND and larger, so only its rim survives.
    """
    def at(into, along=0.0):
        """A point `into` the wall (positive = deeper) and `along` it.

        The two facings point OPPOSITE ways: a wall drawn for -Y goes deeper as
        y grows, a wall on +X goes deeper as x SHRINKS. Getting that sign wrong
        puts the surround in front of the hole, which plugs it — the same
        failure as the doorway, mirrored, and it looks like a pale panel
        instead of a window.
        """
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    sx, sy = at(depth * 0.6)
    arch(f'{name}_surround', sx, sy, z, w + 0.14, h + 0.07, depth,
         key='travertine', facing=facing)
    hx, hy = at(0.0)
    arch(f'{name}_hole', hx, hy, z, w, h, depth, facing=facing)
    lx, ly = at(0.02)
    wall_box(f'{name}_sill', lx, ly, z - 0.09, w + 0.26, 0.18, 0.09,
             mat('travertine'), facing=facing)
    if shutters:
        for sign in (-1, 1):
            bx, by = at(-0.04, sign * (w / 2 + 0.11))
            wall_box(f'{name}_shutter_{sign}', bx, by, z + 0.04,
                     0.14, 0.07, h * 0.74, mat('oak'), facing=facing)


def steps(name, x, y, z, w, count=3, rise=0.075, tread=0.16, key='travertine'):
    """A flight up to a threshold. Three steps say "there is a way in" louder
    than any door does, because a door is a shape and a step is an invitation."""
    for i in range(count):
        box(f'{name}_{i}', x, y - i * tread, z + (count - 1 - i) * rise,
            w - i * 0.1, tread + 0.02, rise + (count - 1 - i) * rise,
            mat(key))


def banner(name, x, y, z, w, h, key='banner', facing='y'):
    """Cloth hung from a rail. The medieval half of the style, and the one place
    a saturated colour is allowed to sit on an otherwise pale wall."""
    def at(into, along=0.0):
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    rx, ry = at(0.0)
    wall_box(f'{name}_rail', rx, ry, z, w + 0.18, 0.07, 0.07, mat('iron'),
             facing=facing)
    cx, cy = at(-0.015)
    wall_box(f'{name}_cloth', cx, cy, z - h, w, 0.04, h, mat(key),
             facing=facing)
    # The swallow-tail, faked with two blocks — a notch at this size is two
    # pixels, and two pixels of silhouette is what a pennant IS.
    for sign in (-1, 1):
        tx, ty = at(-0.015, sign * w / 4)
        wall_box(f'{name}_tail_{sign}', tx, ty, z - h - 0.09, w / 2.4, 0.04,
                 0.1, mat(key), facing=facing)


# ── The buildings ──────────────────────────────────────────
# Each preset gets the footprint it has in the roster and builds itself inside
# it. NOTHING may cross the base except a roof overhang — the same rule the art
# contract states, here enforced by the modelling rather than hoped for.
def egg(name, x, y, z, r, mat):
    """A faceted egg. Two subdivisions: at one it reads as a cut gem, at three
    the facets stop being visible and it is no longer this art style."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r,
                                          location=(x, y, z + r * 1.15))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (1, 1, 1.35)
    ob.rotation_euler = (0, math.radians(9), 0)
    bpy.ops.object.transform_apply(scale=True)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def breeding_hut(w, h):
    """A stuccoed hall under a terracotta roof, with a walled nesting court.

    The read has to survive being 224 px wide on a phone, so the identity is
    carried by SILHOUETTE and contrast, not by detail: a hot tile roof over pale
    walls, an arched mouth of pure black under it, and three white eggs on warm
    sand in an open court where nothing else competes for attention.

    The court is the Roman part that does the most work here — a building with a
    walled forecourt is legible as one property from any angle, where a hut with
    things scattered in front of it is legible as a hut with clutter.
    """
    wall_h = 1.15
    body_d = h * 0.52
    body_w = w - 0.35
    body_y = h / 2 - body_d / 2 - 0.18         # pushed to the back

    plinth('plinth', 0, body_y, body_w + 0.26, body_d + 0.26)
    box('plinth_cap', 0, body_y, 0.22, body_w + 0.18, body_d + 0.18, 0.07,
        mat('travertine'))
    box('body', 0, body_y, 0.22, body_w, body_d, wall_h, mat('stucco'))
    # A course of cut stone at the base of the render: Roman walls change
    # material as they rise, and the change is what stops a wall reading as one
    # blank rectangle of light.
    box('course', 0, body_y, 0.22, body_w + 0.04, body_d + 0.04, 0.3,
        mat('travertine'))
    # The entablature: dentils, then the cornice they carry. Together they are
    # the line that separates wall from roof, and without it the roof looks set
    # down on the walls rather than built onto them.
    dentils('dentils', 0, body_y, 0.22 + wall_h - 0.15, body_w + 0.04,
            body_d + 0.04)
    box('cornice', 0, body_y, 0.22 + wall_h - 0.05, body_w + 0.2,
        body_d + 0.2, 0.1, mat('travertine'))
    # The doorway. Two arches, not one: the travertine surround is what makes
    # the dark shape read as an OPENING. On its own the hole is a black blob
    # leaning on the wall, because a pale wall and a dark patch share no edge
    # the eye can call a frame. It also stands ON the plinth — an opening that
    # floats above the floor is the other half of that same illusion.
    # arch() builds a SOLID body, not a ring, so the surround must sit BEHIND
    # the mouth and be larger — it is seen only as the rim that survives around
    # the dark shape. Put it in front, as I first did, and it simply plugs the
    # hole and the doorway disappears.
    door_w, door_h = body_w * 0.30, wall_h * 0.66
    face_y = body_y - body_d / 2
    arch('surround', 0, face_y + 0.17, 0.22,
         door_w + 0.20, door_h + 0.10, 0.22, key='travertine')
    arch('mouth', 0, face_y + 0.04, 0.22, door_w, door_h, 0.22)
    # A keystone over the arch. One block, and the arch stops being a hole with
    # a rim and becomes something that was built.
    box('keystone', 0, face_y + 0.02, 0.22 + door_h - 0.02,
        0.17, 0.1, 0.2, mat('travertine'))
    steps('steps', 0, face_y - 0.06, 0.0, door_w + 0.3)

    box('plaque', 0, face_y - 0.01, 0.22 + door_h + 0.2, 0.52, 0.06, 0.18,
        mat('travertine'))
    # Lamps either side of the door, with the swag slung between them. They are
    # the reason the facade reads as an entrance rather than as a wall that
    # happens to have a hole in it.
    #
    # The garland first hung above the plaque, which put it through the roof —
    # there is no wall left up there. Hung BETWEEN two things that exist, it
    # cannot drift: move the sconces and it follows.
    lamp_x, lamp_z = door_w / 2 + 0.34, 1.10
    for sign in (-1, 1):
        sconce(f'sconce{sign}', sign * lamp_x, face_y, lamp_z)
    garland('garland', 0, face_y - 0.05, lamp_z + 0.02, lamp_x * 2, sag=0.14)

    roof_z = 0.22 + wall_h
    hip_roof('roof', 0, body_y, roof_z, body_w, body_d, 0.85)
    pantiles('tiles', 0, body_y, roof_z, body_w, body_d, 0.85)
    hip_ridges('hips', 0, body_y, roof_z, body_w, body_d, 0.85)
    antefixes('antefix', 0, body_y, roof_z - 0.02, body_w + 0.6, body_d + 0.6)
    acroterion('acro', 0, body_y, roof_z + 0.85, body_w, body_d)

    # A bundle of thatch stored up under the eaves, where a farmyard keeps it.
    for i, sy in enumerate((-0.3, 0.1)):
        straw_bale(f'thatch{i}', -body_w / 2 + 0.34,
                   body_y + body_d * sy, roof_z - 0.3, 0.3, 0.24, 0.2)

    # Corner pilasters — travertine, not timber. Timber corners drag the whole
    # thing back to a Northern hut; stone corners under a tile roof are Roman.
    # Base and capital both: a plain post is a post, a post with a foot and a
    # head is a column, and that difference is four small boxes.
    for sx in (-1, 1):
        for sy in (-1, 1):
            px = sx * (body_w / 2 - 0.07)
            py = body_y + sy * (body_d / 2 - 0.07)
            box('pilaster', px, py, 0.22, 0.22, 0.22, wall_h,
                mat('travertine'))
            box('pil_base', px, py, 0.22, 0.31, 0.31, 0.12, mat('travertine'))
            box('pil_cap', px, py, 0.22 + wall_h - 0.16, 0.32, 0.32, 0.16,
                mat('travertine'))

    # Two arched windows on the long wall, which is otherwise the largest blank
    # surface the camera ever sees.
    for i, sy in enumerate((-1, 1)):
        window(f'win{i}', body_w / 2 - 0.02, body_y + sy * body_d * 0.26, 0.68,
               0.28, 0.4, 0.2, facing='x')
    banner('banner', body_w / 2 + 0.04, body_y, 1.14, 0.32, 0.42, facing='x')
    # A course of blocks under the windows, running the length of the long
    # wall — the largest surface the camera ever sees, and the one that most
    # needs something on it.
    frieze('frieze', body_w / 2 + 0.02, body_y, 0.38, body_d * 0.92,
           facing='x')

    # ── The court ──
    court_d = h - body_d - 0.35
    court_y = body_y - body_d / 2 - court_d / 2
    court_w = w - 0.35
    box('sand', 0, court_y, 0, court_w - 0.3, court_d - 0.3, 0.16,
        mat('sand'))
    mosaic('floor', 0, court_y, 0.16, court_w - 0.42, court_d - 0.42)
    # Low walls, not a fence: masonry on three sides, open to the front so the
    # eggs are visible. Capped in travertine so the top edge catches light.
    for sx in (-1, 1):
        box('court_wall', sx * (court_w / 2 - 0.09), court_y, 0,
            0.18, court_d, 0.46, mat('ashlar'))
        box('court_cap', sx * (court_w / 2 - 0.09), court_y, 0.46,
            0.24, court_d, 0.07, mat('travertine'))
    front_y = court_y - court_d / 2 + 0.09
    for sx in (-1, 1):
        column(f'gatecol{sx}', sx * (court_w / 2 - 0.09), front_y, 0,
               0.13, 0.78)
        box(f'finial{sx}', sx * (court_w / 2 - 0.09), front_y, 0.78,
            0.11, 0.11, 0.1, mat('gold'))
        # A lamp hung off each gate column: the pair of them is what makes the
        # gap between the columns read as a WAY IN after dark.
        lantern(f'gatelamp{sx}', sx * (court_w / 2 - 0.30), front_y, 0.86,
                drop=0.12)
        box(f'gatearm{sx}', sx * (court_w / 2 - 0.20), front_y, 0.84,
            0.24, 0.05, 0.05, mat('iron'))
    # The threshold between the columns stays LOW: the eggs are what the
    # building says about itself, and nothing may stand in front of them.
    box('threshold', 0, front_y, 0, court_w - 0.5, 0.18, 0.2, mat('ashlar'))

    # NO pergola here, though the kit has one. It fitted the court and covered
    # the eggs and the doorway both — and the eggs are the entire reason this
    # building is recognisable. More detail is only ever worth having while it
    # costs nothing that already reads. Keep it for a building with room.
    nest('nest', -0.12, court_y + 0.06, 0.18, 0.42)
    straw_scatter('litter', -0.12, court_y + 0.06, 0.18, 0.78)
    straw_bale('bale', court_w / 2 - 0.42, court_y - court_d * 0.30, 0.18,
               0.4, 0.28, 0.26)
    egg('egg_a', -0.36, court_y + 0.18, 0.20, 0.23, mat('stucco'))
    egg('egg_b', 0.06, court_y + 0.26, 0.20, 0.26, mat('stucco'))
    egg('egg_c', -0.10, court_y - 0.20, 0.20, 0.21, mat('stucco'))

    # The working clutter, kept to the edges so the middle stays the eggs.
    pot('pot_a', court_w / 2 - 0.36, court_y + court_d * 0.32, 0.16)
    plant('plant_a', court_w / 2 - 0.34, court_y - court_d * 0.10, 0.16)
    # The brazier goes to the GATE, not beside the door: anything tall on the
    # near-left stands directly across the line from the camera to the arch,
    # and the arch is half of what makes this building legible.
    trough('trough', -court_w / 2 + 0.46, court_y + court_d * 0.28, 0.16,
           0.58, 0.28)
    brazier('brazier', -court_w / 2 + 0.30, court_y - court_d * 0.34, 0.16,
            h=0.46)


PRESETS = {'breeding_hut': (breeding_hut, 3, 4)}


def guide_plane(w, h):
    """--guides: the bare W x H footprint, so the framing can be CHECKED.

    Render once with this on and the base's corners must touch the left, right
    and bottom edges of the image. If they do, the art numbers in Dev Mode are
    1 / 0.5 / 0 and nothing needs dialling in. Never ship a render made with it.
    """
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0.002))
    ob = bpy.context.object
    ob.name = 'guide'
    ob.scale = (w, h, 1)
    bpy.ops.object.transform_apply(scale=True)
    mat = flat('guide', (1.0, 0.0, 0.6))
    mat.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'] \
        .default_value = 1.0
    mat.node_tree.nodes['Principled BSDF'].inputs['Emission Color'] \
        .default_value = (1.0, 0.0, 0.6, 1)
    ob.data.materials.append(mat)


# ── Scene ──────────────────────────────────────────────────
def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for b in list(block):
            block.remove(b)


def light():
    """One sun, one soft sky fill, and NO film look.

    The colour transform is the whole ballgame here. Blender defaults to AgX,
    which rolls saturated colour towards grey on purpose — it makes photographic
    renders believable and makes flat-colour assets look like they were left in
    the rain. The first render came out uniformly beige because of it. Standard
    means the colour that goes in is the colour that comes out, which is the
    only sane contract for an asset that has to sit next to hand-picked UI
    colours.
    """
    scene = bpy.context.scene
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'

    bpy.ops.object.light_add(type='SUN')
    sun = bpy.context.object
    # 2.6 blew the pale walls out to near-white, which cost the stucco exactly
    # the warmth it is chosen for. Flat colour has no highlight roll-off to
    # rescue it — what clips is simply gone.
    sun.data.energy = 2.4
    sun.data.angle = 0  # hard-edged shadows; a soft one is a gradient

    # The sun must be on the CAMERA's side of the building. The camera looks
    # from +x/-y, so the two walls a player ever sees are the +x and -y faces;
    # lighting from -x/-y (the first attempt) lit one of them and left the big
    # one to the ambient, which is why the stucco came out grey instead of warm.
    # Travel direction here is (-x, +y, -z): over the shoulder, but off-axis
    # enough that the two visible walls still differ. That difference IS the
    # shading — light them equally and the building goes flat.
    sun.rotation_euler = (math.radians(50), 0, math.radians(32))

    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes['Background']
    # The fill lands hardest on exactly the faces the sun misses, so its
    # strength IS the depth of every shadow in the picture. The monsters run
    # from near-white to a deep, still-saturated dark within one hue; at 0.32
    # the buildings only ran from pale to slightly less pale. Down to 0.18, and
    # tinted warm rather than sky-blue, so the shadows stay in the family
    # instead of turning grey.
    bg.inputs['Color'].default_value = (0.55, 0.50, 0.58, 1)
    bg.inputs['Strength'].default_value = 0.18


def frame(w, h, px_per_tile, headroom):
    """Point the camera and SOLVE its framing from the four ground corners.

    Two things about an orthographic camera that are easy to get wrong, and both
    of which I did on the first run:

      * `ortho_scale` measures the LARGER of the two render dimensions. Ours is
        the height, so setting it to the base's width zooms in by exactly the
        aspect ratio.
      * The camera's position still matters. Distance does not — that is what
        orthographic means — but sliding it sideways slides the whole picture.
        So instead of nudging `shift`, the camera is PLACED on the axis that
        already frames the base, and shift stays zero.
    """
    scene = bpy.context.scene
    base_px = int((w + h) * (TILE_W / 2) * px_per_tile)
    scene.render.resolution_x = base_px
    scene.render.resolution_y = int(base_px * headroom)
    scene.render.film_transparent = True

    bpy.ops.object.camera_add()
    cam = bpy.context.object
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (math.radians(90 - ELEVATION), 0, math.radians(45))
    scene.camera = cam

    # From the euler, NOT from cam.matrix_world: the matrix is evaluated lazily
    # and still holds the identity at this point, which aims the camera at
    # nothing and renders an empty picture.
    q = Euler(cam.rotation_euler).to_quaternion()
    right, up, back = q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0)), \
        q @ Vector((0, 0, 1))

    # Where the base's four ground corners land, in the camera's own axes.
    corners = [
        Vector((-w / 2, -h / 2, 0)), Vector((w / 2, -h / 2, 0)),
        Vector((w / 2, h / 2, 0)), Vector((-w / 2, h / 2, 0)),
    ]
    xs = [c.dot(right) for c in corners]
    ys = [c.dot(up) for c in corners]

    span_x = max(xs) - min(xs)                                   # the base fills
    span_y = span_x * scene.render.resolution_y / base_px        # the width
    cam.data.ortho_scale = max(span_x, span_y)

    # Aim at the point that puts the base's near corner on the bottom edge.
    aim_x = (max(xs) + min(xs)) / 2
    aim_y = min(ys) + span_y / 2
    cam.location = right * aim_x + up * aim_y + back * 60
    cam.data.clip_start = 0.1
    cam.data.clip_end = 200


def bevel_everything():
    """Cut every edge back a little, on every mesh in the scene.

    Done once at the end rather than per part on purpose: a bevel is a property
    of the STYLE, not of any one wall, and threading it through thirty
    constructors would mean thirty places to forget it.

    use_clamp_overlap is what makes a single width safe across parts that differ
    by two orders of magnitude — a 0.028 bevel would otherwise consume a 0.05
    roof tile whole. Blender shrinks it to fit instead.
    """
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        m = ob.modifiers.new('facets', 'BEVEL')
        m.width = BEVEL_WIDTH
        m.segments = BEVEL_SEGMENTS
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(30)
        m.use_clamp_overlap = True
        m.harden_normals = False


def show_in_viewport():
    """Open on the camera, shaded the way it will render.

    Deferred through a timer on purpose: when Blender runs a --python script at
    startup the window is not built yet, so there is no 3D view to talk to. The
    timer fires once the UI exists, and returns None so it never fires again.
    """
    def once():
        for area in bpy.context.screen.areas:
            if area.type != 'VIEW_3D':
                continue
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.region_3d.view_perspective = 'CAMERA'
                    space.shading.type = 'RENDERED'
                    space.overlay.show_overlays = False
        return None

    bpy.app.timers.register(once, first_interval=0.4)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--preset', required=True, choices=sorted(PRESETS))
    ap.add_argument('--out', help='PNG to write (not needed with --no-render)')
    ap.add_argument('--scale', type=int, default=SCALE)
    ap.add_argument('--headroom', type=float, default=1.25,
                    help='image height as a multiple of the base width')
    ap.add_argument('--guides', action='store_true',
                    help='mark the footprint, to check the framing')
    ap.add_argument('--no-render', action='store_true',
                    help='build the scene and stop — for opening it in the GUI')
    ap.add_argument('--blend', help='also save the scene to this .blend')
    args = ap.parse_args(argv)

    build, w, h = PRESETS[args.preset]
    clear()
    build(w, h)
    if args.guides:
        guide_plane(w, h)
    bevel_everything()
    light()
    frame(w, h, args.scale, args.headroom)

    scene = bpy.context.scene
    # EEVEE's identifier moved in 4.2 and again after; ask, do not assume.
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for name in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
        if name in engines:
            scene.render.engine = name
            break

    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
    if args.no_render:
        show_in_viewport()
        return
    if not args.out:
        ap.error('--out is required unless --no-render is given')
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    # Blender resolves a relative path against the .blend file, and in
    # --background there is none — it lands on the drive root. Always absolute.
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


main()
