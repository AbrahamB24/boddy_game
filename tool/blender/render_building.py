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
    'moss': (0.44, 0.50, 0.26),        # duller and yellower — it is on a roof
    # Mid-steps. The monsters get four to six tones out of one hue; three is
    # what a box gives you from lighting alone, so the rest has to be painted.
    # Use these for coursing, joints and mouldings — never for a whole surface.
    # ── Sporehollow: the fungal set (user 2026-08-04, free choice) ──
    # Same discipline as the Roman one and the monsters: a single hue family —
    # coral through cream — plus exactly one outsider, and here it is a cold
    # spore-light. Cold is the right accent because everything else in the
    # building is warm and damp; one teal glow reads instantly and cannot be
    # mistaken for part of the flesh.
    'cap': (0.80, 0.26, 0.21),         # the great cap: the whole silhouette
    'cap_dark': (0.55, 0.15, 0.13),    # its underside and shaded facets
    'cap_spot': (0.98, 0.92, 0.82),    # pale warts — THE fungus signal
    'stalk': (0.94, 0.88, 0.75),       # flesh, standing in for a wall
    'stalk_shade': (0.82, 0.73, 0.58),
    # ── The medieval set (user 2026-08-04) ──
    # Shingles instead of pantiles, and the beams of a timber frame. Still one
    # warm family: the frame is the DARK end of the same brown the shingles
    # are, so half-timbering is a value contrast rather than a second hue.
    'shingle': (0.47, 0.28, 0.18),
    'shingle_dark': (0.33, 0.19, 0.12),
    # ── The egg colours are the APP's (user 2026-08-04) ──
    # CreatureRarity's own values, so a nest on the map and an egg in the
    # Hatchery screen are the same object. They are the one place the single
    # warm family is broken on purpose: the eggs ARE the message this building
    # carries, and a message has to be allowed to be the loudest thing on it.
    # Lifted a little towards the shell so they read as eggs rather than as
    # billiard balls — the app's chips sit on dark UI, these sit in straw.
    'egg_common': (0.78, 0.78, 0.76),
    'egg_uncommon': (0.47, 0.78, 0.47),
    'egg_rare': (0.36, 0.68, 0.95),
    'egg_epic': (0.70, 0.36, 0.78),
    'egg_legendary': (1.00, 0.78, 0.28),
    'root': (0.50, 0.34, 0.22),        # buttress roots, withies, fences
    'root_dark': (0.36, 0.23, 0.15),
    'glow': (0.42, 0.93, 0.84),        # the one cold thing in the building
    'tile_mid': (0.69, 0.24, 0.11),
    'stucco_shade': (0.86, 0.75, 0.57),
    'travertine_shade': (0.76, 0.59, 0.37),
    'ashlar_dark': (0.50, 0.36, 0.22),
}

# How hard every edge is cut back. This is the OTHER half of matching the
# monsters: their surfaces are covered in small, irregular facets, and a box has
# none at all — it has three faces and three tones and that is the end of it.
# A bevel gives every edge its own strip catching its own amount of light, which
# is the same trick at building scale.
#
# Finer since the detail pass (user 2026-08-03: "viel detaillierter und
# feiner"). At 0.028 the bevel was wider than the joints between the stones it
# now has to sit between, and clamp_overlap quietly ate it — the detail was
# there in the geometry and gone in the render. A finer cut with one more
# segment reads as crisp instead of chunky, and leaves room for parts an order
# of magnitude smaller than a wall.
BEVEL_WIDTH = 0.014
BEVEL_SEGMENTS = 3


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
    """A box by its CENTRE-BOTTOM, because buildings stand on the ground.

    ── location=False, rotation=False, and they are not optional ──
    transform_apply's parameters ALL default to True, so `transform_apply(
    scale=True)` quietly applies location and rotation as well: the box's
    position gets baked into its mesh and its object origin snaps to the world
    origin. Nothing looks wrong until something is rotated afterwards — and
    then it turns about the world origin instead of about itself, and flies off
    across the map.

    That one default is the root cause of every stray stick in this file's
    history: the gills that speared through the mushroom caps, the column
    flutes that became a bundle of poles, the pantile ribs, and the timber
    braces. Each was diagnosed separately, three of them were redesigned around
    the symptom, and all four were the same line.
    """
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z + sz / 2))
    ob = bpy.context.object
    ob.name = name
    ob.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
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


def doorway(name, x, y, z, w, h, facing='y', depth=0.22, rim=0.2):
    """A dark opening with a stone surround, placed correctly by construction.

    Use this instead of two bare arch() calls. arch() builds a SOLID body, so a
    surround has to sit BEHIND the mouth and be larger — only its rim survives
    — and "behind" points opposite ways on the two facings: +y for a wall drawn
    towards -y, but -x for one on +x. Getting that backwards plugs the hole and
    yields a pale panel where a doorway should be, and it has now cost three
    separate openings. Here the sign is written down once.
    """
    into = 1.0 if facing == 'y' else -1.0
    sx = x + (0 if facing == 'y' else into * 0.13)
    sy = y + (into * 0.13 if facing == 'y' else 0)
    arch(f'{name}_surround', sx, sy, z, w + rim, h + rim / 2, depth,
         key='travertine', facing=facing)
    arch(f'{name}_mouth', x, y, z, w, h, depth, facing=facing)


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
             overhang=0.3, courses=14, lip=0.032):
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


def ashlar_courses(name, x, y, z, sx, sy, h, key='ashlar', dark='ashlar_dark',
                   course=0.19, block=0.42, joint=0.022):
    """A wall built out of individual stones instead of as one slab.

    The single biggest step from "a box painted stone" to "masonry". Courses
    alternate their offset by half a block, the way any real wall does, so the
    vertical joints never line up — and it is the broken joint line, more than
    the joints themselves, that the eye reads as built by hand.

    Emitted as a solid core plus a skin of blocks: the core stops daylight
    showing through the joints, and it means the joint depth can be as fine as
    it likes without the wall becoming a sieve.
    """
    box(f'{name}_core', x, y, z, sx - joint * 3, sy - joint * 3, h, mat(dark))
    rows = max(1, int(round(h / course)))
    ch = h / rows
    for r in range(rows):
        stagger = (r % 2) * block / 2
        for axis, span, other in ((0, sx, sy), (1, sy, sx)):
            n = max(1, int(round(span / block)))
            bw = span / n
            for i in range(n + 1):
                t = -span / 2 + bw * i + stagger
                if t - bw / 2 < -span / 2 - 0.001 or t + bw / 2 > span / 2:
                    continue
                for sign in (-1, 1):
                    if axis == 0:
                        bx, by = x + t, y + sign * (other / 2 - joint)
                        dims = (bw - joint, joint * 2, ch - joint)
                    else:
                        bx, by = x + sign * (other / 2 - joint), y + t
                        dims = (joint * 2, bw - joint, ch - joint)
                    box(f'{name}_{r}_{axis}_{i}_{sign}', bx, by, z + r * ch,
                        *dims, mat(key))


def string_course(name, x, y, z, sx, sy, key='travertine'):
    """A moulding running round a wall: three thin bands of different widths.

    One band is a stripe. Three of stepped width is a PROFILE, and a profile is
    what makes stone look cut rather than painted — for the price of two boxes.
    """
    box(f'{name}_a', x, y, z, sx + 0.02, sy + 0.02, 0.05, mat(key))
    box(f'{name}_b', x, y, z + 0.05, sx + 0.10, sy + 0.10, 0.045, mat(key))
    box(f'{name}_c', x, y, z + 0.095, sx + 0.05, sy + 0.05, 0.035,
        mat('travertine_shade'))


def flute_faces(ob, key='travertine', shade='travertine_shade'):
    """Flute a column by ALTERNATING THE TONE of its side faces.

    The first attempt laid thin boxes down the shaft. A groove modelled as an
    applied box is a RIB — it stands proud — and eight pale ribs on a 0.26-wide
    column stopped being a column at all and became a bundle of sticks poking
    out of the gate. Diagnosed by measuring, after --no-bevel proved it was
    geometry and not a modifier artefact.

    Alternating a material costs no geometry, cannot protrude, and is how the
    light/shadow of a real flute reads at this size anyway: a groove is not a
    shape you can see at 224 px, it is a stripe.
    """
    ob.data.materials.clear()
    ob.data.materials.append(mat(key))
    ob.data.materials.append(mat(shade))
    quad = 0
    for p in ob.data.polygons:
        if len(p.vertices) == 4:          # a side face; the caps are n-gons
            p.material_index = quad % 2
            quad += 1


def imbrices(name, x, y, z, sx, sy, h, ridge=0.45, overhang=0.3,
             key='tile_mid', courses=14, pitch=0.30):
    """The cap tiles that cover the joints between the flat tiles below.

    A Roman roof is two shapes, not one — a flat tegula with a rounded imbrex
    over every seam. The courses alone gave the roof horizontal banding; these
    cross it, and the grid of the two together is what reads as a tiled roof
    from any distance rather than as a striped one.
    """
    sx += overhang * 2
    sy += overhang * 2
    long_y = sy >= sx
    r = (sy if long_y else sx) * ridge / 2
    for i in range(courses):
        f = (i + 0.5) / courses
        if long_y:
            hx, hy = (sx / 2) * (1 - f), sy / 2 - (sy / 2 - r) * f
        else:
            hx, hy = sx / 2 - (sx / 2 - r) * f, (sy / 2) * (1 - f)
        if hx <= 0.08 or hy <= 0.08:
            break
        span = 2 * (hx if long_y else hy)
        n = max(1, int(span / pitch))
        for j in range(n):
            t = -span / 2 + span * (j + 0.5) / n
            for sign in (-1, 1):
                if long_y:
                    bx, by = x + t, y + sign * hy
                    dims = (0.1, 0.1, 0.07)
                else:
                    bx, by = x + sign * hx, y + t
                    dims = (0.1, 0.1, 0.07)
                box(f'{name}_{i}_{j}_{sign}', bx, by, z + f * h, *dims,
                    mat(key))


def plank_door(name, x, y, z, w, h, facing='y', planks=5):
    """A boarded door: vertical planks, two ledges across them, iron studs.

    A doorway is a hole. A DOOR is a made thing, and the studs are what say so —
    they are two pixels each and they are the whole difference.
    """
    def at(into, along=0.0):
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    for i in range(planks):
        t = -w / 2 + w * (i + 0.5) / planks
        bx, by = at(0.0, t)
        wall_box(f'{name}_p{i}', bx, by, z, w / planks - 0.012, 0.07, h,
                 mat('oak'), facing=facing)
    for lz in (h * 0.22, h * 0.72):
        bx, by = at(-0.02)
        wall_box(f'{name}_ledge{lz:.2f}', bx, by, z + lz, w - 0.03, 0.05,
                 0.06, mat('oak_light'), facing=facing)
        for j in range(3):
            sx_, sy_ = at(-0.05, -w / 2 + w * (j + 0.5) / 3)
            box(f'{name}_stud{lz:.2f}_{j}', sx_, sy_, z + lz + 0.01,
                0.05, 0.05, 0.04, mat('iron'))


def grille(name, x, y, z, w, h, facing='y', bars=3):
    """Iron bars across a window. Fine enough to be texture, present enough to
    stop the opening reading as a rectangle of pure black."""
    for i in range(bars):
        t = -w / 2 + w * (i + 1) / (bars + 1)
        wall_box(f'{name}_v{i}', x + (t if facing == 'y' else 0),
                 y + (0 if facing == 'y' else t), z, 0.03, 0.05, h,
                 mat('iron'), facing=facing)
    wall_box(f'{name}_h', x, y, z + h * 0.45, w, 0.05, 0.03, mat('iron'),
             facing=facing)


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
           tile=0.155):
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


# ── Medieval parts ─────────────────────────────────────────
def half_timber(name, x, y, z, sx, sy, h, bays=3, beam=0.115,
                panel='stucco', wood='oak'):
    """A timber frame with plaster between it — THE medieval signal.

    Nothing else says the period so fast, and it costs almost nothing: a pale
    box, then a dark frame laid on all four faces — sill and head plates, a
    post at every corner, studs dividing the wall into bays, and one diagonal
    brace per face.

    The brace is the part that matters. A grid of verticals reads as
    panelling; it is the DIAGONAL that reads as carpentry, because a diagonal
    is the one line you cut only when a building has to stand up. One per face
    and not one per bay: a real frame braces where the racking is worst, and
    bracing everywhere turns the wall back into a pattern.
    """
    box(f'{name}_panel', x, y, z, sx, sy, h, mat(panel))
    for axis, span, other in ((0, sx, sy), (1, sy, sx)):
        for sign in (-1, 1):
            def put(nm, along, zz, ln, hh, ang=None):
                if axis == 0:
                    bx, by = x + along, y + sign * other / 2
                    dims = (ln, beam, hh)
                else:
                    bx, by = x + sign * other / 2, y + along
                    dims = (beam, ln, hh)
                ob = box(f'{name}_{nm}_{axis}{sign}', bx, by, zz, *dims,
                         mat(wood))
                if ang:
                    ob.rotation_euler = ((0, ang, 0) if axis == 0
                                         else (-ang, 0, 0))
                return ob

            put('sill', 0, z, span + beam, beam)
            put('head', 0, z + h - beam, span + beam, beam)
            for i in range(bays + 1):
                put(f'stud{i}', -span / 2 + span * i / bays, z, beam, h)
            bw, bh = span / bays, h * 0.66
            b = put('brace', 0, z, beam, math.hypot(bw, bh),
                    math.atan2(bw, bh) * (1 if sign > 0 else -1))
            b.location = (x + (-span / 2 + bw / 2 if axis == 0
                               else sign * other / 2),
                          y + (sign * other / 2 if axis == 0
                               else -span / 2 + bw / 2),
                          z + h / 2)


def shingle_gable(name, x, y, z, sx, sy, h, overhang=0.22, rows=9,
                  key='shingle', dark='shingle_dark', ridge_along='y'):
    """A steep gabled roof laid in courses of shingles.

    Simpler than the Roman hip and better for it: a gable's slopes are
    RECTANGLES, so a course is one box the full length of the roof — no
    trapezoid to solve, no ends left hanging where the plane narrows. The
    lesson from the pantiles holds either way: courses parallel to the eaves
    have no ends to leave in mid air.

    Steep on purpose. A medieval roof is nearly as tall as the wall beneath
    it, and that proportion is most of what separates it from a Roman one.
    """
    sx += overhang * 2
    sy += overhang * 2
    if ridge_along == 'y':
        span, run = sy, sx / 2
        verts = [(-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0),
                 (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0),
                 (0, -sy / 2, h), (0, sy / 2, h)]
        faces = [(0, 1, 4), (2, 3, 5), (0, 4, 5, 3), (1, 2, 5, 4),
                 (0, 3, 2, 1)]
    else:
        span, run = sx, sy / 2
        verts = [(-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0),
                 (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0),
                 (-sx / 2, 0, h), (sx / 2, 0, h)]
        faces = [(0, 4, 3), (1, 2, 5), (0, 1, 5, 4), (3, 2, 5, 4),
                 (0, 3, 2, 1)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat(dark))
    for p in ob.data.polygons:
        p.use_smooth = False

    for i in range(rows):
        f = (i + 0.3) / rows
        off = run * (1 - f)
        for sign in (-1, 1):
            if ridge_along == 'y':
                bx, by = x + sign * off, y
                dims = (run / rows * 1.6, span, 0.055)
            else:
                bx, by = x, y + sign * off
                dims = (span, run / rows * 1.6, 0.055)
            box(f'{name}_c{i}_{sign}', bx, by, z + h * f, *dims,
                mat(key if i % 2 else dark))
    if ridge_along == 'y':
        box(f'{name}_ridge', x, y, z + h - 0.05, 0.15, span + 0.05, 0.1,
            mat('oak'))
    else:
        box(f'{name}_ridge', x, y, z + h - 0.05, span + 0.05, 0.15, 0.1,
            mat('oak'))
    return ob


def gable_boards(name, x, y, z, span, h, thick=0.06, count=9, key='oak',
                 axis='x', sign=-1):
    """Boarding across a gable's triangle, plus the rake trim down its edges.

    The triangular end wall was the one big blank surface left on the building.
    A gable is where a roof's structure is EXPOSED — it is the one wall with no
    floor behind it — so leaving it as flat plaster reads as a wall that was
    never finished, exactly where the eye goes first because it is the tallest
    thing in the silhouette.

    Boards, not another timber frame: a frame is what the walls below already
    say, and a gable that repeats it has nothing of its own. Vertical boarding
    on the triangle and a frame beneath is how these were actually built.
    """
    for i in range(count):
        t = -span / 2 + span * (i + 0.5) / count
        bh = h * (1 - abs(t) / (span / 2)) * 0.94
        if bh <= 0.06:
            continue
        w = span / count * 0.86
        bx, by = (x + t, y) if axis == 'x' else (x, y + t)
        dims = (w, thick, bh) if axis == 'x' else (thick, w, bh)
        box(f'{name}_{i}', bx, by, z, *dims,
            mat(key if i % 2 else 'oak_light'))
    # The rake boards down both slopes, and the collar tie across the middle.
    ln = math.hypot(span / 2, h)
    ang = math.atan2(span / 2, h)
    for s in (-1, 1):
        dims = (0.11, thick, ln) if axis == 'x' else (thick, 0.11, ln)
        ob = box(f'{name}_rake{s}', 0, 0, 0, *dims, mat('oak'))
        ob.rotation_euler = ((0, -s * ang, 0) if axis == 'x'
                             else (s * ang, 0, 0))
        off = s * span / 4
        ob.location = ((x + off, y, z + h / 2) if axis == 'x'
                       else (x, y + off, z + h / 2))
    tie = (span * 0.52, thick + 0.02, 0.12) if axis == 'x' \
        else (thick + 0.02, span * 0.52, 0.12)
    box(f'{name}_tie', x, y, z + h * 0.38, *tie, mat('oak'))
    _ = sign


def egg_banner(name, x, y, z, w, h, facing='y', shell='egg_legendary'):
    """A hanging cloth with an EGG on it — the building's sign.

    A banner in a plain colour says "someone lives here". A banner with the
    thing you came for painted on it says WHICH building this is, and at 256 px
    a single bold shape on a flat field is the only kind of sign that survives.
    Same reason shop signs were pictures: nobody could read either.
    """
    def at(into, along=0.0):
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    rx, ry = at(0.0)
    wall_box(f'{name}_rail', rx, ry, z, w + 0.2, 0.07, 0.07, mat('iron'),
             facing=facing)
    for s in (-1, 1):
        hx, hy = at(0.0, s * (w / 2 + 0.06))
        wall_box(f'{name}_ring{s}', hx, hy, z - 0.06, 0.05, 0.06, 0.08,
                 mat('iron'), facing=facing)
    cx, cy = at(-0.02)
    wall_box(f'{name}_cloth', cx, cy, z - h, w, 0.04, h, mat('banner'),
             facing=facing)
    # The swallow tail.
    for s in (-1, 1):
        tx, ty = at(-0.02, s * w / 4)
        wall_box(f'{name}_tail{s}', tx, ty, z - h - 0.1, w / 2.4, 0.04, 0.11,
                 mat('banner'), facing=facing)
    # The egg: three stacked slabs, widest in the middle. A faceted lozenge
    # rather than a circle, so it belongs to the same world as the eggs in the
    # yard instead of looking like a printed logo.
    #
    # Five steps, not three. At three the silhouette is a stack of blocks and
    # reads as a crate; the shape only becomes an EGG once it narrows at both
    # ends and does it faster at the top than the bottom. It also has to be
    # BIG — an emblem that leaves a margin round itself is a logo, and a sign
    # this far up the gable has one job.
    ex, ey = at(-0.05)
    steps = ((0.34, 0.13, 0.74), (0.52, 0.13, 0.61), (0.62, 0.16, 0.45),
             (0.58, 0.16, 0.29), (0.42, 0.13, 0.16))
    for i, (dw, dh, dz) in enumerate(steps):
        wall_box(f'{name}_egg{i}', ex, ey, z - h + h * dz,
                 w * dw, 0.03, h * dh, mat(shell), facing=facing)


def jetty(name, x, y, z, sx, sy, out=0.2, key='oak', count=4):
    """Brackets under an overhanging upper floor.

    A jetty — the first floor pushed out past the ground floor — is the second
    medieval signal after the frame, and it earns its geometry because it
    BREAKS THE WALL LINE. An unbroken face from ground to eaves reads as a box
    no matter what is painted on it.
    """
    box(f'{name}_plate', x, y, z, sx + out * 2, sy + out * 2, 0.1, mat(key))
    for axis, span, other in ((0, sx, sy), (1, sy, sx)):
        for sign in (-1, 1):
            for i in range(count):
                t = -span / 2 + span * (i + 0.5) / count
                if axis == 0:
                    bx, by = x + t, y + sign * (other / 2 + out / 2)
                    dims = (0.11, out, 0.14)
                else:
                    bx, by = x + sign * (other / 2 + out / 2), y + t
                    dims = (out, 0.11, 0.14)
                box(f'{name}_b{axis}{sign}{i}', bx, by, z - 0.13, *dims,
                    mat(key))


def chimney(name, x, y, z, w, h, key='ashlar'):
    """A stone stack. Its vertical is what keeps the roofline from being one
    unbroken triangle, and smoke is the cheapest sign of someone home."""
    ashlar_courses(f'{name}_stack', x, y, z, w, w, h, key=key,
                   dark='ashlar_dark', course=0.17, block=0.26)
    box(f'{name}_corbel', x, y, z + h, w + 0.13, w + 0.13, 0.07,
        mat('travertine'))
    box(f'{name}_cap', x, y, z + h + 0.07, w + 0.02, w + 0.02, 0.09, mat(key))
    box(f'{name}_pot', x, y, z + h + 0.16, w * 0.4, w * 0.4, 0.14, mat('tile'))


def leaded_window(name, x, y, z, w, h, facing='y', shutters=True):
    """A small window with a cross of mullions and a pair of shutters.

    Small on purpose. Glass was dear: a wall of it reads as a shopfront, two
    little lit panes read as a home. The pane is the gold — a window that is
    not LIT is a hole, and a hole says nobody is in.
    """
    def at(into, along=0.0):
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    fx, fy = at(0.05)
    wall_box(f'{name}_frame', fx, fy, z - 0.06, w + 0.15, 0.11, h + 0.15,
             mat('oak'), facing=facing)
    gx, gy = at(-0.01)
    wall_box(f'{name}_glass', gx, gy, z, w, 0.07, h, mat('gold'),
             facing=facing)
    mx, my = at(-0.045)
    wall_box(f'{name}_mv', mx, my, z, 0.04, 0.05, h, mat('oak'), facing=facing)
    wall_box(f'{name}_mh', mx, my, z + h / 2 - 0.02, w, 0.05, 0.04,
             mat('oak'), facing=facing)
    sx_, sy_ = at(0.02)
    wall_box(f'{name}_sill', sx_, sy_, z - 0.13, w + 0.32, 0.17, 0.07,
             mat('oak_light'), facing=facing)
    if shutters:
        for sign in (-1, 1):
            bx, by = at(-0.07, sign * (w / 2 + 0.13))
            wall_box(f'{name}_sh{sign}', bx, by, z - 0.03, 0.21, 0.07,
                     h + 0.08, mat('oak_light'), facing=facing)


# ── Sporehollow parts ──────────────────────────────────────
def cap(name, x, y, z, r, h, sides=12, rings=5, key='cap', flare=0.13):
    """A faceted mushroom cap: rings of an n-gon, shrinking and rising.

    The strongest silhouette available at 256 px. A tile roof has to be READ —
    pitch, ridge, eaves — before it says "building"; a cap is recognised whole,
    before any detail resolves, which is exactly what a sprite that small needs.

    The profile is deliberately not a hemisphere. `flare` pushes the widest
    point BELOW the rim so the edge turns under itself, and that turned-under
    lip is the difference between a mushroom and an umbrella.
    """
    verts = []
    prof = []
    for ri in range(rings + 1):
        t = ri / rings
        rr = r * (math.cos(t * math.pi / 2) ** 0.55)
        zz = h * math.sin(t * math.pi / 2) ** 1.15
        if ri == 0:                      # the rim turns under
            rr, zz = r * (1 - flare), -h * flare * 0.7
        prof.append((max(rr, r * 0.1), zz))
    for rr, zz in prof:
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append((rr * math.cos(a), rr * math.sin(a), zz))
    faces = []
    for ri in range(rings):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((ri * sides + i, ri * sides + j,
                          (ri + 1) * sides + j, (ri + 1) * sides + i))
    faces.append(tuple(range(rings * sides, (rings + 1) * sides)))
    faces.append(tuple(range(sides - 1, -1, -1)))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat(key))
    for p in ob.data.polygons:
        p.use_smooth = False
    return prof


# ── There are no gills, and there is a reason ──
# I built them twice and cut them both times. The argument for them was that
# the underside of a cap is always in view and would carry fine detail the way
# a tiled roof cannot. That argument is simply false for this camera: at 30
# degrees above the horizon you look at the TOP of a cap, never under it. So a
# ring of blades can only ever stick OUT past the silhouette — as a fan inside
# the shell it escaped through the rim, and hung below the rim it read as
# spokes on a wheel, because nothing overhangs them from that angle.
#
# The finding generalises past mushrooms: detail that lives on a downward-
# facing surface is invisible here and can only cost you. Put it on the top,
# the two visible walls, or the ground — nowhere else earns its geometry.
def warts(name, prof, x, y, z, count=11, key='cap_spot'):
    """Pale warts scattered over a cap, sitting ON its profile.

    Two colours of dome is a dome. A dome with warts is a MUSHROOM — this is
    the single cheapest piece of recognition in the whole building, and it only
    works because each one is placed against the same profile the cap was built
    from instead of guessed at.
    """
    for i in range(count):
        t = 0.18 + 0.72 * ((i + 0.5) / count)
        k = t * (len(prof) - 1)
        lo = min(int(k), len(prof) - 2)
        f = k - lo
        rr = prof[lo][0] + (prof[lo + 1][0] - prof[lo][0]) * f
        zz = prof[lo][1] + (prof[lo + 1][1] - prof[lo][1]) * f
        a = 2.399963 * i                      # golden angle: never a row
        s = 0.1 + 0.07 * ((i * 5) % 3) / 2
        box(f'{name}_{i}', x + rr * 0.94 * math.cos(a),
            y + rr * 0.94 * math.sin(a), z + zz - 0.02, s, s, 0.06, mat(key))


def stalk(name, x, y, z, r_bot, r_top, h, sides=10, key='stalk'):
    """A tapered, faceted stalk — the wall of a fungal building.

    Tapered on purpose: a straight cylinder under a cap reads as a lamp post.
    Living things are thicker where they carry weight.
    """
    verts = []
    steps = 4
    prof = [(r_bot, 0.0), (r_bot * 0.9, h * 0.28), (r_bot * 0.84, h * 0.6),
            (r_top * 1.06, h * 0.88), (r_top, h)]
    for rr, zz in prof:
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append((rr * math.cos(a), rr * math.sin(a), zz))
    faces = []
    for ri in range(steps):
        for i in range(sides):
            j = (i + 1) % sides
            faces.append((ri * sides + i, ri * sides + j,
                          (ri + 1) * sides + j, (ri + 1) * sides + i))
    faces.append(tuple(range(steps * sides, (steps + 1) * sides)))
    faces.append(tuple(range(sides - 1, -1, -1)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    for p in ob.data.polygons:
        p.use_smooth = False
    flute_faces(ob, key=key, shade='stalk_shade')
    return ob


def roots(name, x, y, z, r, count=7, reach=0.5, key='root'):
    """Buttress roots splaying from the foot of a stalk.

    They do the job the stone plinth did on the Roman set — join the building
    to its ground so it is not standing on a line — and they do it in a way
    that says GROWN rather than founded.
    """
    for i in range(count):
        a = 2.399963 * i
        ln = reach * (0.7 + 0.5 * ((i * 3) % 3) / 2)
        ob = box(f'{name}_{i}', x + (r + ln / 2 - 0.1) * math.cos(a),
                 y + (r + ln / 2 - 0.1) * math.sin(a), z,
                 ln, 0.15, 0.2, mat(key if i % 2 else 'root_dark'))
        ob.rotation_euler = (0, 0, a)
        box(f'{name}_k{i}', x + (r + ln - 0.06) * math.cos(a),
            y + (r + ln - 0.06) * math.sin(a), z, 0.14, 0.14, 0.1,
            mat('root_dark'))


def spore_lamp(name, x, y, z, h=0.7, key='glow'):
    """A glowing pod on a bent stem. The only cold colour in the building, and
    the thing that says someone tends this place after dark."""
    box(f'{name}_base', x, y, z, 0.16, 0.16, 0.07, mat('root_dark'))
    box(f'{name}_stem', x, y, z + 0.05, 0.06, 0.06, h, mat('root'))
    box(f'{name}_arm', x + 0.09, y, z + h, 0.22, 0.06, 0.06, mat('root'))
    box(f'{name}_pod', x + 0.18, y, z + h - 0.2, 0.15, 0.15, 0.19, mat(key))
    box(f'{name}_tip', x + 0.18, y, z + h - 0.25, 0.09, 0.09, 0.06, mat(key))


def withy_fence(name, x, y, z, span, h=0.5, axis='x', key='root'):
    """A woven fence of bent withies: uprights, two rails, and a curved top.

    A masonry wall would fight the cap. Everything on this building has to look
    grown or woven, and a fence is where that rule is easiest to break.
    """
    n = max(3, int(span / 0.24))
    for i in range(n):
        t = -span / 2 + span * (i + 0.5) / n
        bx, by = (x + t, y) if axis == 'x' else (x, y + t)
        hh = h * (0.86 + 0.16 * ((i * 7) % 3) / 2)
        box(f'{name}_p{i}', bx, by, z, 0.055, 0.055, hh,
            mat(key if i % 2 else 'root_dark'))
    for k, hz in enumerate((0.32, 0.72)):
        sx, sy = (span, 0.05) if axis == 'x' else (0.05, span)
        box(f'{name}_r{k}', x, y, z + h * hz, sx, sy, 0.045, mat('root_dark'))


def colonnade(name, x, y, z, span, depth, h, count=4, axis='x'):
    """A row of columns carrying an architrave and a mono-pitch roof.

    The most Roman thing that can be built and the best value in the whole kit:
    a portico is the one element that reads as DEPTH from a fixed camera. A flat
    wall is a plane whatever you put on it; a colonnade has a lit front, shaded
    columns, and a dark space behind them, and the eye reads three layers.
    """
    for i in range(count):
        t = -span / 2 + span * (i + 0.5) / count
        cx, cy = (x + t, y) if axis == 'x' else (x, y + t)
        column(f'{name}_c{i}', cx, cy, z, 0.115, h - 0.26)
    # Architrave, then the frieze band it carries, then the roof.
    sx, sy = (span + 0.3, depth) if axis == 'x' else (depth, span + 0.3)
    box(f'{name}_arch', x, y, z + h - 0.26, sx, sy, 0.13, mat('travertine'))
    box(f'{name}_frieze', x, y, z + h - 0.13, sx - 0.06, sy - 0.06, 0.09,
        mat('stucco'))
    dentils(f'{name}_dent', x, y, z + h - 0.05, sx - 0.1, sy - 0.1)
    lean_to(f'{name}_roof', x, y, z + h - 0.04, sx - 0.1, sy - 0.1, 0.34,
            drop=0.22, courses=7)


def well(name, x, y, z, r=0.36):
    """A round stone well with a timber winch. Every settlement has one, and it
    is the single prop that most says PEOPLE LIVE HERE rather than "storage"."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=r, depth=0.42,
                                        location=(x, y, z + 0.21))
    ob = bpy.context.object
    ob.name = f'{name}_ring'
    for p in ob.data.polygons:
        p.use_smooth = False
    flute_faces(ob, key='ashlar', shade='ashlar_dark')
    box(f'{name}_water', x, y, z + 0.34, r * 1.3, r * 1.3, 0.04, mat('dark'))
    box(f'{name}_rim', x, y, z + 0.38, r * 1.75, r * 1.75, 0.06,
        mat('travertine'))
    for sign in (-1, 1):
        box(f'{name}_post{sign}', x + sign * (r - 0.02), y, z + 0.45,
            0.09, 0.09, 0.62, mat('oak'))
    box(f'{name}_beam', x, y, z + 1.05, r * 2.4, 0.1, 0.1, mat('oak'))
    box(f'{name}_roller', x, y, z + 0.86, r * 1.9, 0.11, 0.11, mat('oak_light'))
    box(f'{name}_rope', x, y, z + 0.62, 0.035, 0.035, 0.25, mat('straw'))
    box(f'{name}_bucket', x, y, z + 0.5, 0.17, 0.17, 0.16, mat('oak'))


def moss(name, x, y, z, sx, sy, h, ridge=0.45, overhang=0.3, patches=9,
         key='moss'):
    """Moss creeping up a roof from the eaves.

    Weathering is what says a building has been standing a while rather than
    having been placed this morning, and this is the cheapest kind: a handful
    of patches, biased LOW on the slope, because that is where a real roof stays
    damp. Spread by the golden angle so they never line up into a row.
    """
    sx += overhang * 2
    sy += overhang * 2
    long_y = sy >= sx
    r = (sy if long_y else sx) * ridge / 2
    for i in range(patches):
        # sqrt biases towards the eaves; the ridge dries out first.
        f = 0.06 + 0.5 * ((i + 0.5) / patches) ** 1.7
        a = 2.399963 * i
        t = (a / (2 * math.pi)) % 1.0 - 0.5
        if long_y:
            hx, hy = (sx / 2) * (1 - f), sy / 2 - (sy / 2 - r) * f
            bx, by = x + t * 2 * hx, y + math.copysign(hy, math.sin(a))
        else:
            hx, hy = sx / 2 - (sx / 2 - r) * f, (sy / 2) * (1 - f)
            bx, by = x + math.copysign(hx, math.sin(a)), y + t * 2 * hy
        s = 0.11 + 0.09 * ((i * 7) % 3) / 2
        box(f'{name}_{i}', bx, by, z + f * h, s, s, 0.045, mat(key))


def vine(name, x, y, z, h, key='leaf', facing='y', leaves=9):
    """A creeper up a wall: one stem and a scatter of leaves either side.

    Green is the rarest colour in this palette, so a vine is a strong move —
    one per building, on the wall that has the least going on."""
    def at(into, along=0.0):
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    sx_, sy_ = at(-0.02)
    wall_box(f'{name}_stem', sx_, sy_, z, 0.045, 0.05, h, mat('oak'),
             facing=facing)
    for i in range(leaves):
        f = (i + 0.5) / leaves
        side = 1 if i % 2 else -1
        lx, ly = at(-0.035, side * (0.05 + 0.09 * ((i * 5) % 3)))
        s = 0.09 + 0.05 * ((i * 3) % 2)
        box(f'{name}_leaf{i}', lx, ly, z + h * f, s, s, s * 0.55, mat(key))


def tufts(name, x, y, sx, sy, key='leaf', pitch=0.42):
    """Grass at the foot of a wall, where a broom never quite reaches."""
    for axis, span, other in ((0, sx, sy), (1, sy, sx)):
        n = max(1, int(span / pitch))
        for i in range(n):
            t = -span / 2 + span * (i + 0.5) / n
            for sign in (-1, 1):
                if _hash01(f'{name}{axis}{i}{sign}') < 0.45:
                    continue          # bald patches; a fringe is a hedge
                if axis == 0:
                    bx, by = x + t, y + sign * (other / 2 + 0.03)
                else:
                    bx, by = x + sign * (other / 2 + 0.03), y + t
                box(f'{name}_{axis}_{i}_{sign}', bx, by, 0,
                    0.13, 0.13, 0.11, mat(key))
                box(f'{name}_b{axis}_{i}_{sign}', bx, by, 0.09,
                    0.07, 0.07, 0.07, mat(key))


def dovecote(name, x, y, z, w, h, holes=3):
    """A small tower with its own roof and a wall of nest holes.

    Asymmetry that earns its keep. A tower on ONE corner does three things at
    once: it breaks the silhouette, it gives the roofline a second height to
    read against, and on a breeding building it says what happens inside
    without a single word. Symmetry is what made the hut look correct and
    lifeless; one thing that only exists on one side fixes it.
    """
    ashlar_courses(f'{name}_base', x, y, z, w + 0.1, w + 0.1, 0.16,
                   course=0.16, block=0.3)
    box(f'{name}_shaft', x, y, z + 0.16, w, w, h, mat('stucco'))
    box(f'{name}_band', x, y, z + 0.16 + h * 0.5, w + 0.05, w + 0.05, 0.06,
        mat('travertine'))
    # The holes face the two walls a player can see, and nothing is spent on
    # the two they cannot.
    for i in range(holes):
        hz = z + 0.24 + h * (0.24 + 0.26 * i)
        arch(f'{name}_hole_a{i}', x, y - w / 2 + 0.03, hz, 0.1, 0.13, 0.1)
        arch(f'{name}_hole_b{i}', x + w / 2 - 0.03, y, hz, 0.1, 0.13, 0.1,
             facing='x')
        box(f'{name}_ledge_a{i}', x, y - w / 2 - 0.02, hz - 0.045,
            0.2, 0.08, 0.035, mat('travertine'))
        box(f'{name}_ledge_b{i}', x + w / 2 + 0.02, y, hz - 0.045,
            0.08, 0.2, 0.035, mat('travertine'))
    top = z + 0.16 + h
    box(f'{name}_cornice', x, y, top - 0.05, w + 0.16, w + 0.16, 0.06,
        mat('travertine'))
    hip_roof(f'{name}_roof', x, y, top, w, w, w * 0.55, overhang=0.14,
             ridge=0.2)
    pantiles(f'{name}_tiles', x, y, top, w, w, w * 0.55, overhang=0.14,
             ridge=0.2, courses=7, lip=0.022)
    box(f'{name}_finial', x, y, top + w * 0.55, 0.08, 0.08, 0.11, mat('gold'))


def lean_to(name, x, y, z, sx, sy, h, drop=0.28, key='tile', courses=0):
    """A mono-pitch shelter on posts: high at the back, low at the front.

    The other half of breaking symmetry. A second roof at a different pitch and
    a different height stops the building reading as one shape repeated.
    """
    for sxs in (-1, 1):
        for sys in (-1, 1):
            box(f'{name}_post_{sxs}_{sys}', x + sxs * (sx / 2 - 0.06),
                y + sys * (sy / 2 - 0.06), z, 0.13, 0.13,
                h - (drop if sys < 0 else 0), mat('oak'))
    verts = [
        (-sx / 2 - 0.12, -sy / 2 - 0.12, h - drop),
        (sx / 2 + 0.12, -sy / 2 - 0.12, h - drop),
        (sx / 2 + 0.12, sy / 2 + 0.12, h),
        (-sx / 2 - 0.12, sy / 2 + 0.12, h),
    ]
    verts += [(vx, vy, vz - 0.07) for vx, vy, vz in verts]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
             (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat(key))
    for p in ob.data.polygons:
        p.use_smooth = False

    # Courses across the slope, low edge to high. Without them a mono-pitch is
    # the one big untextured plane left in the whole kit, and on a portico it
    # sits right in the middle of the picture.
    if courses:
        for i in range(courses):
            f = (i + 0.5) / courses
            box(f'{name}_t{i}', x, y - sy / 2 + sy * f,
                z + h - drop + drop * f - 0.02,
                sx + 0.24, sy / courses * 0.62, 0.05, mat('tile_dark'))
    return ob


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


def column(name, x, y, z, r, h, key='travertine', sides=12):
    """A round column, faceted and fluted. Twelve sides: six light faces and
    six shaded ones, which is a fluted shaft — and still few enough that the
    facets show, which is the whole art style."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=r, depth=h,
                                        location=(x, y, z + h / 2))
    ob = bpy.context.object
    ob.name = name
    for p in ob.data.polygons:
        p.use_smooth = False
    flute_faces(ob)
    box(f'{name}_base', x, y, z, r * 2.6, r * 2.6, 0.07, mat(key))
    box(f'{name}_torus', x, y, z + 0.07, r * 2.2, r * 2.2, 0.045,
        mat('travertine_shade'))
    box(f'{name}_neck', x, y, z + h - 0.17, r * 2.1, r * 2.1, 0.04,
        mat('travertine_shade'))
    box(f'{name}_cap', x, y, z + h - 0.13, r * 2.7, r * 2.7, 0.075, mat(key))
    box(f'{name}_abacus', x, y, z + h - 0.055, r * 2.95, r * 2.95, 0.055,
        mat(key))
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


def dentils(name, x, y, z, sx, sy, key='travertine', pitch=0.115, size=0.055):
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


def antefixes(name, x, y, z, sx, sy, key='tile_dark', pitch=0.21):
    """Upright tile-ends standing along the eaves. Roman roofs are edged, not
    cut off, and the little row of them is what stops the roof's bottom edge
    reading as a straight machine cut."""
    for sign in (-1, 1):
        n = max(2, int(sx / pitch))
        for i in range(n):
            bx = x - sx / 2 + sx * (i + 0.5) / n
            box(f'{name}_{i}_{sign}', bx, y + sign * sy / 2, z,
                0.085, 0.055, 0.095, mat(key))


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
    """The Hatchery: fantasy medieval — timber frame, jetty, steep shingles.

    ── What carries the period ──
    Three things, in order of how much work they do. The HALF-TIMBERING, which
    no other style shares and which the eye reads before anything else. The
    JETTY, because an upper floor pushed out past a lower one breaks the wall
    line, and an unbroken face from ground to eaves reads as a box whatever is
    painted on it. And the ROOF PITCH: a medieval roof is nearly as tall as the
    wall beneath it, where a Roman one is a lid.

    Everything the last three versions taught is kept. One warm family, and the
    frame is the dark end of the same brown the shingles are, so half-timbering
    is a value contrast rather than a second hue. Nothing tall between the
    camera and the eggs. Courses parallel to the eaves. Detail only on the top,
    the two visible walls and the ground — never on a downward-facing surface,
    which this camera cannot see.

    ── The plan is an L, and that is the whole composition ──
    A tall house at the back left, a lower wing at the right with its gable
    turned across it, and the yard filling the near corner between them. The
    turned gable is what makes it read as a building someone extended rather
    than a shape someone chose.
    """
    half = w / 2.0

    # ── The house ──
    hx, hy = -0.66, 0.82
    hw, hd = 2.06, 1.86
    base_h, floor_h, upper_h = 0.3, 0.98, 0.82
    ashlar_courses('hbase', hx, hy, 0, hw + 0.12, hd + 0.12, base_h,
                   course=0.15, block=0.3)
    half_timber('hlow', hx, hy, base_h, hw, hd, floor_h, bays=3)
    jetty('hjet', hx, hy, base_h + floor_h, hw, hd, out=0.17)
    up_w, up_d = hw + 0.34, hd + 0.34
    half_timber('hup', hx, hy, base_h + floor_h + 0.1, up_w, up_d, upper_h,
                bays=3)
    roof_z = base_h + floor_h + 0.1 + upper_h
    shingle_gable('hroof', hx, hy, roof_z, up_w, up_d, 1.24, overhang=0.26,
                  rows=11, ridge_along='y')
    moss('hmoss', hx, hy, roof_z, up_w * 0.8, up_d * 0.8, 0.7,
         overhang=0.0, patches=8)
    chimney('chim', hx - hw / 2 + 0.16, hy + 0.34, 0, 0.4, roof_z + 1.5)

    # BOTH gables get boarded, not just the one on show: the map lets a
    # building be seen from any side once the camera is anywhere but here.
    face_y = hy - up_d / 2
    for s, gy in ((-1, face_y - 0.24), (1, hy + up_d / 2 + 0.24)):
        gable_boards(f'hgab{s}', hx, gy, roof_z, up_w + 0.5, 1.2,
                     axis='x', sign=s)
    # THE SIGN: an egg on a banner, hung on the gable that faces the camera.
    # This is what tells you which building you are looking at.
    egg_banner('flag', hx, face_y - 0.32, roof_z + 0.94, 0.56, 0.72)

    # ── Ground floor: the way in, off centre ──
    door_x = hx - 0.34
    low_face = hy - hd / 2
    doorway('hdoor', door_x, low_face, base_h, 0.62, 0.8)
    plank_door('hleaf', door_x, low_face - 0.06, base_h + 0.02, 0.56, 0.5,
               planks=4)
    steps('hsteps', door_x, low_face - 0.12, 0, 0.9, count=2, rise=0.09)
    for sign in (-1, 1):
        sconce(f'hlamp{sign}', door_x + sign * 0.52, low_face, base_h + 0.86)
    leaded_window('hw0', hx + 0.56, low_face, base_h + 0.4, 0.3, 0.38)
    leaded_window('hw1', hx + hw / 2, hy + 0.3, base_h + 0.4, 0.3, 0.38,
                  facing='x')
    # Upper floor windows sit on the jetty, where the overhang shades them.
    uz = base_h + floor_h + 0.34
    for i, ox in enumerate((-0.5, 0.42)):
        leaded_window(f'hu{i}', hx + ox, face_y, uz, 0.28, 0.34)
    leaded_window('hu2', hx + up_w / 2, hy + 0.24, uz, 0.28, 0.34, facing='x')

    # ── The wing, its gable turned across the house's ──
    wx, wy = 1.06, 0.96
    ww, wd = 1.42, 1.5
    ashlar_courses('wbase', wx, wy, 0, ww + 0.1, wd + 0.1, 0.26,
                   course=0.14, block=0.28)
    half_timber('wlow', wx, wy, 0.26, ww, wd, 1.02, bays=2)
    w_roof_z = 1.28
    shingle_gable('wroof', wx, wy, w_roof_z, ww, wd, 0.86, overhang=0.24,
                  rows=8, ridge_along='x')
    moss('wmoss', wx, wy, w_roof_z, ww * 0.8, wd * 0.8, 0.5, overhang=0.0,
         patches=5)
    w_face = wy - wd / 2
    doorway('wdoor', wx + 0.1, w_face, 0.26, 0.5, 0.62, rim=0.13)
    plank_door('wleaf', wx + 0.1, w_face - 0.05, 0.28, 0.44, 0.36, planks=3)
    leaded_window('ww0', wx + ww / 2, wy + 0.3, 0.72, 0.28, 0.34, facing='x')
    lantern('wlamp', wx - 0.44, w_face - 0.12, 1.02, drop=0.16)
    box('wlamparm', wx - 0.36, w_face - 0.06, 1.0, 0.24, 0.06, 0.05,
        mat('iron'))
    vine('wvine', wx + ww / 2 - 0.02, wy - 0.42, 0.26, 0.78, facing='x')

    # ── The yard, filling the near corner ──
    yx0, yx1 = -half + 0.16, half - 0.16
    yy0, yy1 = -half + 0.16, -0.28
    yxc, yyc = (yx0 + yx1) / 2, (yy0 + yy1) / 2
    yw, yd = yx1 - yx0, yy1 - yy0
    box('yard', yxc, yyc, 0, yw, yd, 0.1, mat('sand'))
    # The scatter is a DISC, so it is sized off the yard's short side. Off the
    # long one it spills through the fence and litters the map's own ground.
    straw_scatter('yfloor', yxc, yyc, 0.1, yd * 0.46, n=26, key='straw')
    straw_scatter('yfloor2', yxc - yw * 0.22, yyc, 0.1, yd * 0.4, n=14,
                  key='straw')
    straw_scatter('yfloor3', yxc + yw * 0.22, yyc, 0.1, yd * 0.4, n=14,
                  key='straw')

    withy_fence('fy', yxc, yy0 + 0.06, 0, yw, 0.5, axis='x')
    withy_fence('fx', yx1 - 0.06, yyc + 0.05, 0, yd, 0.5, axis='y')
    withy_fence('fl', yx0 + 0.06, yyc + 0.05, 0, yd, 0.5, axis='y')
    for i, (px, py) in enumerate(((yx1 - 0.06, yy0 + 0.06),
                                  (yx0 + 0.06, yy0 + 0.06))):
        box(f'ypost{i}', px, py, 0, 0.16, 0.16, 0.76, mat('oak'))
        box(f'ycap{i}', px, py, 0.76, 0.13, 0.13, 0.09, mat('oak_light'))
        lantern(f'ylamp{i}', px, py, 0.84, drop=0.1)

    # No lean-to (user 2026-08-04: "das Vordach bitte löschen"). It shaded half
    # the yard and shaded the half the eggs are in — and the eggs are the whole
    # reason this building is recognisable. lean_to() stays in the kit.

    # The nest moves to the MIDDLE of the yard with the shed gone, and the eggs
    # take the app's own rarity colours so a nest here and an egg in the
    # Hatchery screen are the same object.
    nx, ny = yxc + 0.1, yyc - 0.02
    nest('nest', nx, ny, 0.1, 0.5)
    straw_scatter('litter', nx, ny, 0.1, 0.86)
    egg('egg_a', nx - 0.34, ny + 0.14, 0.12, 0.26, mat('egg_rare'))
    egg('egg_b', nx + 0.24, ny + 0.22, 0.12, 0.29, mat('egg_legendary'))
    egg('egg_c', nx + 0.02, ny - 0.28, 0.12, 0.24, mat('egg_uncommon'))
    # A fourth, tucked at the edge — three in a triangle is an arrangement,
    # four is a clutch.
    egg('egg_d', nx - 0.58, ny - 0.18, 0.12, 0.22, mat('egg_epic'))

    straw_bale('bale', yx0 + 0.56, yy0 + 0.44, 0.1, 0.4, 0.28, 0.26)
    trough('trough', yx1 - 0.42, yyc + 0.3, 0.1, 0.24, 0.5, key='oak')
    pot('pot', yx0 + 0.3, yy1 - 0.22, 0.1, r=0.14, h=0.36)
    plant('plant', yx1 - 0.28, yy0 + 0.5, 0.1)
    # ── THE BACK AND THE FAR SIDE (user 2026-08-04) ──
    # Detailed to the same level as the front, and not because the map shows
    # them: it does not, from this one camera. It is because a building that is
    # only finished on two faces is a stage flat, and the first time a preset is
    # reused, mirrored, or looked at in Blender, the empty half is all you see.
    # It also costs almost nothing — the parts already exist.
    back_y = hy + up_d / 2
    leaded_window('hb0', hx - 0.5, back_y, uz, 0.28, 0.34, facing='y')
    leaded_window('hb1', hx + 0.5, back_y, uz, 0.28, 0.34, facing='y')
    leaded_window('hb2', hx + 0.3, hy + hd / 2, base_h + 0.4, 0.3, 0.38)
    # A back door onto the yard behind, with its own step and lamp.
    back_door_x = hx - 0.62
    doorway('hbdoor', back_door_x, hy + hd / 2, base_h, 0.5, 0.66, rim=0.13)
    plank_door('hbleaf', back_door_x, hy + hd / 2 + 0.05, base_h + 0.02,
               0.44, 0.4, planks=3)
    sconce('hblamp', back_door_x + 0.46, hy + hd / 2, base_h + 0.8)

    # The far wall of the house: a lean of firewood and a water butt, the two
    # things every one of these had and the two that read at any size.
    lx = hx - hw / 2 - 0.16
    for i in range(6):
        ob = box(f'logs{i}', lx, hy + 0.5 - i * 0.115, 0.02,
                 0.34, 0.1, 0.1, mat('oak' if i % 2 else 'oak_light'))
        ob.rotation_euler = (0, math.radians(9 if i % 2 else -6), 0)
    box('lograck', lx - 0.14, hy + 0.5 - 2.5 * 0.115, 0, 0.07, 0.85, 0.42,
        mat('oak'))
    box('butt', lx - 0.02, hy - 0.62, 0, 0.36, 0.36, 0.42, mat('oak'))
    box('butt_hoop', lx - 0.02, hy - 0.62, 0.14, 0.39, 0.39, 0.05, mat('iron'))
    box('butt_water', lx - 0.02, hy - 0.62, 0.38, 0.28, 0.28, 0.05,
        mat('iron'))

    # Behind the wing: a compost heap and a pair of barrels, so the far corner
    # of the plot is used rather than mown.
    box('heap', wx + 0.2, wy + wd / 2 + 0.3, 0, 0.7, 0.42, 0.22, mat('straw'))
    straw_scatter('heaptop', wx + 0.2, wy + wd / 2 + 0.3, 0.22, 0.3, n=10)
    for i, ox in enumerate((-0.5, -0.16)):
        pot(f'barrel{i}', wx + ox, wy + wd / 2 + 0.34, 0, r=0.15, h=0.4,
            key='oak')

    tufts('grass_h', hx, hy, hw + 0.5, hd + 0.5)
    tufts('grass_w', wx, wy, ww + 0.4, wd + 0.4)
    vine('hvine', hx - hw / 2 - 0.01, hy + 0.9, base_h, 0.7, facing='x')


def breeding_hut_spore(w, h):
    """Sporehollow: a hatchery grown under fungus, not built out of stone.

    ── Why fungus ──
    A cap is one of the very few silhouettes a player recognises WHOLE, before
    any detail resolves — which is the only kind that survives at 256 px. A tile
    roof has to be read (pitch, ridge, eaves) before it says "building". And it
    is the right shape for this particular building: eggs are kept somewhere
    warm, damp and dark, and a fungus is all three by nature. The Roman version
    had to explain itself with a courtyard and a dovecote; this one does not.

    ── The rules it keeps ──
    Everything else carries over, because none of it was Roman — it was just
    good. One hue family (coral through cream) with exactly one outsider, and
    here that outsider is COLD: a spore-light, which cannot be mistaken for
    flesh. Nothing tall between the camera and the eggs. Detail concentrated
    where the eye lands, which for a cap is the underside of the rim — hence
    the gills, which are the band a tiled roof can never give you.

    Three caps at three heights, not one: a single mushroom is a prop, and a
    cluster at different scales is a settlement.
    """
    half = w / 2.0
    inset = 0.15

    # ── The great cap ──
    gx, gy = -0.5, 0.5
    g_stalk_h, g_r = 1.32, 1.34
    roots('groots', gx, gy, 0, 0.8, count=8, reach=0.62)
    stalk('gstalk', gx, gy, 0, 0.86, 0.6, g_stalk_h)
    # The way in, facing the court. Set into the flesh, not applied to it.
    doorway('gdoor', gx + 0.16, gy - 0.72, 0.06, 0.6, 0.78)
    plank_door('gleaf', gx + 0.16, gy - 0.79, 0.08, 0.54, 0.36, planks=4)
    for i, (wx, wy, f) in enumerate(((gx + 0.72, gy + 0.1, 'x'),
                                     (gx - 0.5, gy - 0.6, 'y'))):
        doorway(f'gwin{i}', wx, wy, 0.66, 0.26, 0.3, facing=f, rim=0.13)
    gprof = cap('gcap', gx, gy, g_stalk_h, g_r, 0.92)
    warts('gwart', gprof, gx, gy, g_stalk_h, count=13)
    moss('gmoss', gx, gy, g_stalk_h - 0.1, g_r * 0.9, g_r * 0.9, 0.5,
         overhang=0.0, patches=7)

    # ── The second cap, lower and behind ──
    sx_, sy_ = 0.95, 1.12
    s_h, s_r = 0.86, 0.82
    roots('sroots', sx_, sy_, 0, 0.44, count=5, reach=0.34)
    stalk('sstalk', sx_, sy_, 0, 0.48, 0.36, s_h, sides=8)
    doorway('swin', sx_ - 0.02, sy_ - 0.5, 0.34, 0.24, 0.28, rim=0.12)
    sprof = cap('scap', sx_, sy_, s_h, s_r, 0.6, sides=10, rings=4)
    warts('swart', sprof, sx_, sy_, s_h, count=8)

    # ── The third, a stub at the front — the smallest of the three, and the
    #    one that keeps the near corner from being empty ground.
    tx, ty = -1.32, -0.62
    t_h, t_r = 0.44, 0.5
    roots('troots', tx, ty, 0, 0.26, count=4, reach=0.22)
    stalk('tstalk', tx, ty, 0, 0.3, 0.22, t_h, sides=8)
    tprof = cap('tcap', tx, ty, t_h, t_r, 0.36, sides=9, rings=3)
    warts('twart', tprof, tx, ty, t_h, count=5)

    # ── The nesting court, in the near corner ──
    cx0, cx1 = -0.72, half - inset
    cy0, cy1 = -half + inset, 0.12
    cxc, cyc = (cx0 + cx1) / 2, (cy0 + cy1) / 2
    cw, cd = cx1 - cx0, cy1 - cy0

    box('yard', cxc, cyc, 0, cw - 0.1, cd - 0.1, 0.12, mat('sand'))
    # Trodden earth, not paving: nothing here was cut, so nothing is laid out.
    straw_scatter('yfloor', cxc, cyc, 0.12, cw * 0.46, n=26, key='straw')

    withy_fence('fx', cx1 - 0.07, cyc, 0, cd, 0.52, axis='y')
    withy_fence('fy', cxc, cy0 + 0.07, 0, cw, 0.52, axis='x')
    # The gate: two root-posts and a pair of spore-lights at the near corner.
    for i, (px, py) in enumerate(((cx1 - 0.07, cy0 + 0.62),
                                  (cx1 - 0.66, cy0 + 0.07))):
        box(f'gpost{i}', px, py, 0, 0.16, 0.16, 0.78, mat('root_dark'))
        box(f'gknob{i}', px, py, 0.78, 0.13, 0.13, 0.1, mat('root'))
        spore_lamp(f'glamp{i}', px, py, 0.88, h=0.24)

    nx, ny = cxc + 0.12, cyc - 0.12
    nest('nest', nx, ny, 0.12, 0.48)
    straw_scatter('litter', nx, ny, 0.12, 0.86)
    egg('egg_a', nx - 0.24, ny + 0.1, 0.14, 0.26, mat('stalk'))
    egg('egg_b', nx + 0.26, ny + 0.17, 0.14, 0.29, mat('stalk'))
    egg('egg_c', nx + 0.05, ny - 0.3, 0.14, 0.24, mat('stalk'))

    spore_lamp('lamp_a', cx0 + 0.2, cy1 - 0.28, 0.12, h=0.78)
    straw_bale('bale', cx0 + 0.24, cy0 + 0.42, 0.12, 0.4, 0.28, 0.26)
    trough('trough', cx1 - 0.36, cyc + 0.42, 0.12, 0.26, 0.56, key='root')
    pot('pot', cx1 - 0.34, cy0 + 0.46, 0.12, r=0.14, h=0.36)
    plant('plant_a', cx0 - 0.18, cy0 + 0.9, 0.0)

    tufts('grass_g', gx, gy, 1.9, 1.9)
    tufts('grass_s', sx_, sy_, 1.1, 1.1)


def breeding_hut_roman(w, h):
    """An L of two wings around a court that opens towards the camera.

    ── Why 4x4, and why an L ──
    A square footprint projects to a true rhombus, and its near corner sits at
    the bottom of the picture. Wrap the FAR corner with two wings and leave the
    near one open, and the camera looks between them INTO the court: two
    facades, a colonnade, and the yard's floor, all at once. The old 3x4 could
    only ever show one front with things standing in front of it.

    The portico is the piece doing the most work. A wall is a plane whatever
    you decorate it with; a row of columns has a lit front, shaded shafts and a
    dark space behind, so the eye reads three layers of depth from a camera
    that cannot move.

    ── The read at 256 px ──
    Roof mass, then the pale colonnade against the dark under-porch, then three
    white eggs on straw in the middle of an open court. Everything else is
    texture. Nothing tall stands between the camera and the eggs — that rule
    has cost two features already (a pergola and a brazier) and it still holds.
    """
    half = w / 2.0
    hall_d = 1.5                       # the back wing's depth
    wing_w = 1.3                       # the left wing's width
    inset = 0.15                       # air between building and plot edge
    wall_h = 1.28

    x0, x1 = -half + inset, half - inset
    y0, y1 = -half + inset, half - inset

    hall_y = y1 - hall_d / 2
    hall_w = x1 - x0
    wing_x = x0 + wing_w / 2
    wing_y0, wing_y1 = y0, y1 - hall_d
    wing_d = wing_y1 - wing_y0
    wing_yc = (wing_y0 + wing_y1) / 2
    wing_h = wall_h * 0.82

    court_x0, court_x1 = x0 + wing_w, x1
    court_y0, court_y1 = y0, y1 - hall_d
    court_xc = (court_x0 + court_x1) / 2
    court_yc = (court_y0 + court_y1) / 2
    court_w, court_d = court_x1 - court_x0, court_y1 - court_y0

    # ── The hall, along the back ──
    ashlar_courses('hall_p', 0, hall_y, 0, hall_w + 0.22, hall_d + 0.22, 0.2)
    box('hall_pc', 0, hall_y, 0.2, hall_w + 0.14, hall_d + 0.14, 0.05,
        mat('travertine'))
    box('hall', 0, hall_y, 0.22, hall_w, hall_d, wall_h, mat('stucco'))
    ashlar_courses('hall_c', 0, hall_y, 0.22, hall_w + 0.03, hall_d + 0.03,
                   0.3, key='travertine', dark='travertine_shade',
                   course=0.15, block=0.34)
    string_course('hall_sc', 0, hall_y, 0.52, hall_w, hall_d)
    dentils('hall_d', 0, hall_y, 0.22 + wall_h - 0.15, hall_w + 0.03,
            hall_d + 0.03)
    box('hall_cor', 0, hall_y, 0.22 + wall_h - 0.05, hall_w + 0.2,
        hall_d + 0.2, 0.1, mat('travertine'))
    for sxs in (-1, 1):
        for sys in (-1, 1):
            px, py = sxs * (hall_w / 2 - 0.07), hall_y + sys * (hall_d / 2 - 0.07)
            box('hall_pil', px, py, 0.22, 0.22, 0.22, wall_h, mat('travertine'))
            box('hall_pilb', px, py, 0.22, 0.31, 0.31, 0.11, mat('travertine'))
            box('hall_pilc', px, py, 0.22 + wall_h - 0.16, 0.32, 0.32, 0.16,
                mat('travertine'))

    hall_rz = 0.22 + wall_h
    hall_rh = 0.92
    hip_roof('hall_r', 0, hall_y, hall_rz, hall_w, hall_d, hall_rh)
    pantiles('hall_t', 0, hall_y, hall_rz, hall_w, hall_d, hall_rh)
    imbrices('hall_i', 0, hall_y, hall_rz, hall_w, hall_d, hall_rh)
    hip_ridges('hall_h', 0, hall_y, hall_rz, hall_w, hall_d, hall_rh)
    antefixes('hall_a', 0, hall_y, hall_rz - 0.02, hall_w + 0.6, hall_d + 0.6)
    acroterion('hall_ac', 0, hall_y, hall_rz + hall_rh, hall_w, hall_d)
    moss('hall_m', 0, hall_y, hall_rz, hall_w, hall_d, hall_rh)

    # ── The west wing, lower, at right angles ──
    ashlar_courses('wing_p', wing_x, wing_yc, 0, wing_w + 0.22, wing_d + 0.22,
                   0.2)
    box('wing', wing_x, wing_yc, 0.22, wing_w, wing_d, wing_h, mat('stucco'))
    ashlar_courses('wing_c', wing_x, wing_yc, 0.22, wing_w + 0.03,
                   wing_d + 0.03, 0.26, key='travertine',
                   dark='travertine_shade', course=0.13, block=0.3)
    dentils('wing_d', wing_x, wing_yc, 0.22 + wing_h - 0.13, wing_w + 0.03,
            wing_d + 0.03)
    box('wing_cor', wing_x, wing_yc, 0.22 + wing_h - 0.04, wing_w + 0.17,
        wing_d + 0.17, 0.09, mat('travertine'))
    wing_rz, wing_rh = 0.22 + wing_h, 0.7
    hip_roof('wing_r', wing_x, wing_yc, wing_rz, wing_w, wing_d, wing_rh,
             overhang=0.26, ridge=0.5)
    pantiles('wing_t', wing_x, wing_yc, wing_rz, wing_w, wing_d, wing_rh,
             overhang=0.26, ridge=0.5, courses=12)
    imbrices('wing_i', wing_x, wing_yc, wing_rz, wing_w, wing_d, wing_rh,
             overhang=0.26, ridge=0.5, courses=12)
    hip_ridges('wing_h', wing_x, wing_yc, wing_rz, wing_w, wing_d, wing_rh,
               overhang=0.26, ridge=0.5)
    antefixes('wing_a', wing_x, wing_yc, wing_rz - 0.02, wing_w + 0.52,
              wing_d + 0.52)
    moss('wing_m', wing_x, wing_yc, wing_rz, wing_w, wing_d, wing_rh,
         overhang=0.26, ridge=0.5, patches=6)

    # The wing's court-facing wall: a stable door and a shuttered window, both
    # looking in at the yard, because that is the wall the camera sees.
    wf_x = wing_x + wing_w / 2
    doorway('wdoorway', wf_x - 0.02, wing_yc - 0.42, 0.22, 0.5, 0.72,
            facing='x')
    plank_door('wdoor', wf_x - 0.03, wing_yc - 0.42, 0.24, 0.46, 0.34,
               facing='x')
    window('wwin', wf_x - 0.02, wing_yc + 0.5, 0.68, 0.28, 0.38, 0.2,
           facing='x')
    grille('wbars', wf_x - 0.06, wing_yc + 0.5, 0.68, 0.28, 0.34, facing='x')
    sconce('wsc', wf_x, wing_yc - 0.02, 1.02, facing='x')
    vine('wvine', wf_x - 0.02, wing_yc + 1.0, 0.28, 0.86, facing='x')

    # ── The portico across the hall's court side ──
    # Shallower than it wants to be. At 0.7 deep its roof reached out over the
    # middle of the court and put the eggs in shade — the same mistake the
    # pergola made on the old hut, in a new shape.
    port_y = hall_y - hall_d / 2 - 0.26
    colonnade('port', 0, port_y, 0.22, hall_w - 0.5, 0.52, 1.22, count=5)
    box('port_step', 0, port_y - 0.36, 0, hall_w - 0.3, 0.3, 0.22,
        mat('travertine'))
    # Behind the columns: the way in, kept dark so the colonnade has something
    # to stand against.
    hf_y = hall_y - hall_d / 2
    doorway('halldoor', -0.5, hf_y + 0.03, 0.22, 0.72, 0.84)
    box('keystone', -0.5, hf_y + 0.01, 0.22 + 0.84 - 0.02, 0.17, 0.1, 0.2,
        mat('travertine'))
    plank_door('door', -0.5, hf_y - 0.04, 0.24, 0.68, 0.4)
    for i, wx in enumerate((0.62, 1.28)):
        window(f'hwin{i}', wx, hf_y, 0.66, 0.26, 0.36, 0.2)
        grille(f'hbars{i}', wx, hf_y - 0.04, 0.66, 0.26, 0.32)

    # ── The dovecote in the angle of the L ──
    cote_w = 0.72
    dovecote('cote', x0 + cote_w / 2 + 0.06, y1 - hall_d - cote_w / 2 - 0.06,
             0, cote_w, 2.35)

    # ── The court ──
    box('yard', court_xc, court_yc, 0, court_w - 0.16, court_d - 0.16, 0.16,
        mat('sand'))
    mosaic('yfloor', court_xc, court_yc, 0.16, court_w - 0.42, court_d - 0.42)
    # Low walls on the two OPEN sides only; the wings close the other two.
    ashlar_courses('yw_x', court_x1 - 0.09, court_yc, 0, 0.18, court_d, 0.44,
                   course=0.15, block=0.32)
    box('yw_xc', court_x1 - 0.09, court_yc, 0.44, 0.24, court_d, 0.055,
        mat('travertine'))
    ashlar_courses('yw_y', court_xc, court_y0 + 0.09, 0, court_w, 0.18, 0.44,
                   course=0.15, block=0.32)
    box('yw_yc', court_xc, court_y0 + 0.09, 0.44, court_w, 0.24, 0.055,
        mat('travertine'))
    # The gate is cut into the near corner, where the two low walls meet.
    gx, gy = court_x1 - 0.09, court_y0 + 0.09
    for i, (cx, cy) in enumerate(((gx, gy + 0.62), (gx - 0.62, gy))):
        column(f'gcol{i}', cx, cy, 0, 0.14, 0.82)
        box(f'gfin{i}', cx, cy, 0.82, 0.12, 0.12, 0.1, mat('gold'))
        lantern(f'glamp{i}', cx, cy, 0.92, drop=0.1)

    well('well', court_x0 + 0.52, court_y1 - 0.52, 0.16)
    # The nest sits in the OPEN half, towards the near corner: the portico
    # shades the back of the court and nothing may shade the eggs.
    nx, ny = court_xc + 0.05, court_y0 + court_d * 0.34
    nest('nest', nx, ny, 0.18, 0.46)
    straw_scatter('litter', nx, ny, 0.18, 0.84)
    egg('egg_a', nx - 0.22, ny + 0.1, 0.2, 0.25, mat('stucco'))
    egg('egg_b', nx + 0.24, ny + 0.16, 0.2, 0.28, mat('stucco'))
    egg('egg_c', nx + 0.04, ny - 0.28, 0.2, 0.23, mat('stucco'))

    straw_bale('bale', court_x0 + 0.36, court_y0 + 0.46, 0.16, 0.42, 0.3, 0.28)
    pot('pot', court_x1 - 0.34, court_y1 - 0.44, 0.16)
    plant('plant', court_x0 + 0.32, court_y1 - 0.34, 0.16)
    trough('trough', court_x1 - 0.42, court_yc - 0.2, 0.16, 0.28, 0.6)
    brazier('brz', court_x0 + 0.3, court_y0 + 1.02, 0.16, h=0.46)

    tufts('grass_h', 0, hall_y, hall_w + 0.22, hall_d + 0.22)
    tufts('grass_w', wing_x, wing_yc, wing_w + 0.22, wing_d + 0.22)


def _breeding_hut_old(w, h):
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

    # The plinth is laid as STONES, not cast as a slab — see ashlar_courses.
    ashlar_courses('plinth', 0, body_y, 0, body_w + 0.26, body_d + 0.26, 0.22)
    tufts('grass', 0, body_y, body_w + 0.26, body_d + 0.26)
    box('plinth_cap', 0, body_y, 0.22, body_w + 0.18, body_d + 0.18, 0.05,
        mat('travertine'))
    box('body', 0, body_y, 0.24, body_w, body_d, wall_h, mat('stucco'))
    # A course of cut stone at the base of the render: Roman walls change
    # material as they rise, and the change is what stops a wall reading as one
    # blank rectangle of light. Coursed too, and capped with a moulding.
    ashlar_courses('course', 0, body_y, 0.24, body_w + 0.04, body_d + 0.04,
                   0.3, key='travertine', dark='travertine_shade',
                   course=0.15, block=0.34)
    string_course('sc', 0, body_y, 0.53, body_w + 0.02, body_d + 0.02)
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
    # ── The door is OFF CENTRE (user 2026-08-03: "noch schöner") ──
    # A centred door under a centred roof between mirrored windows is a
    # building that is correct and lifeless. Everything hung off the doorway —
    # steps, lamps, garland, keystone — takes its x from door_x, so moving the
    # door moves the whole composition and nothing has to be re-measured.
    door_w, door_h = body_w * 0.30, wall_h * 0.66
    door_x = -body_w * 0.16
    face_y = body_y - body_d / 2
    arch('surround', door_x, face_y + 0.17, 0.22,
         door_w + 0.20, door_h + 0.10, 0.22, key='travertine')
    arch('mouth', door_x, face_y + 0.04, 0.22, door_w, door_h, 0.22)
    # A stable door: boarded to hip height, open above. Exactly right for a
    # place animals go in and out of, and it puts a made thing in the one
    # opening that was a plain black hole.
    plank_door('door', door_x, face_y - 0.03, 0.24, door_w - 0.03,
               door_h * 0.46)
    # A keystone over the arch. One block, and the arch stops being a hole with
    # a rim and becomes something that was built.
    box('keystone', door_x, face_y + 0.02, 0.22 + door_h - 0.02,
        0.17, 0.1, 0.2, mat('travertine'))
    steps('steps', door_x, face_y - 0.06, 0.0, door_w + 0.3)

    box('plaque', door_x, face_y - 0.01, 0.22 + door_h + 0.2, 0.52, 0.06, 0.18,
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
        sconce(f'sconce{sign}', door_x + sign * lamp_x, face_y, lamp_z)
    garland('garland', door_x, face_y - 0.05, lamp_z + 0.02, lamp_x * 2,
            sag=0.14)

    roof_z = 0.22 + wall_h
    hip_roof('roof', 0, body_y, roof_z, body_w, body_d, 0.85)
    pantiles('tiles', 0, body_y, roof_z, body_w, body_d, 0.85)
    imbrices('caps', 0, body_y, roof_z, body_w, body_d, 0.85)
    hip_ridges('hips', 0, body_y, roof_z, body_w, body_d, 0.85)
    antefixes('antefix', 0, body_y, roof_z - 0.02, body_w + 0.6, body_d + 0.6)
    acroterion('acro', 0, body_y, roof_z + 0.85, body_w, body_d)
    moss('moss', 0, body_y, roof_z, body_w, body_d, 0.85)

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
    # ONE window, not a mirrored pair — the tower takes the other end of the
    # wall, and a tower opposite a window is a composition where two windows
    # were only a pattern.
    wy = body_y + body_d * 0.28
    window('win', body_w / 2 - 0.02, wy, 0.68, 0.28, 0.4, 0.2, facing='x')
    grille('bars', body_w / 2 - 0.06, wy, 0.68, 0.28, 0.36, facing='x')
    banner('banner', body_w / 2 + 0.04, body_y - body_d * 0.06, 1.14, 0.32,
           0.42, facing='x')
    vine('vine', body_w / 2 - 0.02, body_y + body_d * 0.44, 0.28, 1.0,
         facing='x')

    # The dovecote as a CORNER tower, its two outer faces flush with the two
    # walls the camera can see. Placed inside the block it simply rose through
    # the main roof and its whole shaft — the nest holes, the ledges, the point
    # of it — was buried. Flush with the corner, all of that is on show and the
    # tower still breaks the roofline.
    cote_w = 0.62
    dovecote('cote', body_w / 2 - cote_w / 2, face_y + cote_w / 2, 0,
             cote_w, 1.95)
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
        ashlar_courses(f'court_wall{sx}', sx * (court_w / 2 - 0.09), court_y,
                       0, 0.18, court_d, 0.46, course=0.155, block=0.34)
        box(f'court_cap{sx}', sx * (court_w / 2 - 0.09), court_y, 0.46,
            0.24, court_d, 0.055, mat('travertine'))
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
    # A shelter over the LEFT of the court only. The nest moves right to meet
    # it, so the court has a covered half and an open half instead of one even
    # rectangle — and nothing stands in front of the eggs, which was the lesson
    # the pergola taught.
    lean_to('shelter', -court_w * 0.31, court_y + 0.02, 0.16, 0.84, 0.9, 0.96,
            key='straw')

    nest('nest', court_w * 0.16, court_y + 0.02, 0.18, 0.40)
    straw_scatter('litter', court_w * 0.16, court_y + 0.02, 0.18, 0.72)
    straw_bale('bale', -court_w * 0.30, court_y + 0.24, 0.18, 0.4, 0.28, 0.26)
    ex = court_w * 0.16
    egg('egg_a', ex - 0.24, court_y + 0.14, 0.20, 0.23, mat('stucco'))
    egg('egg_b', ex + 0.18, court_y + 0.22, 0.20, 0.26, mat('stucco'))
    egg('egg_c', ex + 0.02, court_y - 0.24, 0.20, 0.21, mat('stucco'))

    # The working clutter, kept to the edges so the middle stays the eggs.
    pot('pot_a', court_w / 2 - 0.34, court_y + court_d * 0.30, 0.16)
    plant('plant_a', court_w / 2 - 0.32, court_y - court_d * 0.14, 0.16)
    # The brazier goes to the GATE, not beside the door: anything tall on the
    # near-left stands directly across the line from the camera to the arch,
    # and the arch is half of what makes this building legible.
    trough('trough', -court_w / 2 + 0.46, court_y + court_d * 0.28, 0.16,
           0.58, 0.28)
    brazier('brazier', -court_w / 2 + 0.30, court_y - court_d * 0.34, 0.16,
            h=0.46)


PRESETS = {
    'breeding_hut': (breeding_hut, 4, 4),
    'breeding_hut_spore': (breeding_hut_spore, 4, 4),
    # Kept, not deleted. It is a finished design in a different world, and the
    # kit that built it (hip roofs, pantiles, colonnades, ashlar) is the same
    # kit every stone building will use. Throwing it away would throw away the
    # only worked example of that half of the vocabulary.
    'breeding_hut_roman': (breeding_hut_roman, 4, 4),
}


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


def light(azimuth=0.0):
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
    sun.data.energy = 2.5
    sun.data.angle = math.radians(2.2)   # a hair of softness, not a gradient
    sun.data.color = (1.0, 0.95, 0.86)   # warm key against the cool fill

    # ── Why the sun is LOW ──
    # It has to stay on the camera's side — the camera looks from +x/-y, so
    # those two walls are the only ones a player ever sees, and lighting the
    # other pair leaves them to the ambient and turns the stucco grey.
    #
    # But at 40 degrees above the horizon it was almost directly over the
    # camera's shoulder, and nothing visible fell into shadow. That is why
    # switching on occlusion changed nothing and why even a full path trace
    # changed nothing: there were no shadows to deepen. Occlusion darkens what
    # is already shaded; if everything is lit, there is nothing to occlude.
    #
    # At 28 degrees the shadows get long enough to do the work: the eaves lay a
    # deep band down the wall, every pilaster and dentil casts, the court walls
    # throw across the floor, and the columns reach over the paving. That, and
    # not the renderer, is what makes it look solid.
    # The sun TURNS WITH THE CAMERA. It has to: the whole lighting argument is
    # that the two walls a player sees are lit and the others are not, and a
    # fixed sun would light the front of one view and the back of the next —
    # the same building would go dark when you turned the map a quarter.
    #
    # It is the same reason a sprite sheet works at all. Each view is its own
    # picture of the same object, so each is allowed its own light; what must
    # not change between them is which RELATIVE side the light comes from.
    sun.rotation_euler = (math.radians(62), 0, math.radians(28 + azimuth))

    # A fill from the opposite side so the shadow side keeps its colour instead
    # of dying. Weak and cool — its whole job is to stop black, not to light.
    bpy.ops.object.light_add(type='SUN')
    fill = bpy.context.object
    fill.name = 'fill'
    fill.data.energy = 0.55
    fill.data.color = (0.72, 0.80, 1.0)
    fill.data.angle = math.radians(30)
    fill.rotation_euler = (math.radians(58), 0, math.radians(-150 + azimuth))

    # ── Contact darkening ──
    # The one thing missing that no amount of ornament could supply: every part
    # sat ON the next one without ever getting DARKER where they meet. Under
    # the eaves, in the court corners, where the nest touches the floor — all
    # of it was lit as if nothing was in the way, which is exactly what makes a
    # render read as flat colour rather than as a solid object.
    #
    # Fast GI is EEVEE's screen-space approximation and it is the right tool
    # here: the effect wanted is short-range occlusion at junctions, not
    # accurate bounce light. Distance is in world units and one tile is 1.0, so
    # 0.55 darkens a corner and leaves the open court alone.
    ev = scene.eevee
    ev.use_raytracing = True
    ev.use_fast_gi = True
    if hasattr(ev, 'fast_gi_method'):
        try:
            ev.fast_gi_method = 'AMBIENT_OCCLUSION_ONLY'
        except TypeError:
            pass
    ev.fast_gi_distance = 0.55
    ev.fast_gi_ray_count = 4
    ev.fast_gi_step_count = 12
    ev.taa_render_samples = 96
    ev.use_shadows = True
    if hasattr(ev, 'ray_tracing_options'):
        ev.ray_tracing_options.use_denoise = True
        try:
            ev.ray_tracing_options.resolution_scale = '1'
        except TypeError:
            pass

    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes['Background']
    # The fill lands hardest on exactly the faces the sun misses, so its
    # strength IS the depth of every shadow in the picture. The monsters run
    # from near-white to a deep, still-saturated dark within one hue; at 0.32
    # the buildings only ran from pale to slightly less pale. Down to 0.18, and
    # tinted warm rather than sky-blue, so the shadows stay in the family
    # instead of turning grey.
    bg.inputs['Color'].default_value = (0.55, 0.50, 0.58, 1)
    bg.inputs['Strength'].default_value = 0.22


def frame(w, h, px_per_tile, headroom, azimuth=0.0):
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
    # ── TURNING THE VILLAGE (user 2026-08-04) ──
    # [azimuth] spins the camera round the building in 90-degree steps. Two
    # things make this nearly free, and both are properties of the projection
    # rather than of any building:
    #
    #   * The framing already SOLVES from the projected ground corners, so it
    #     re-solves for the turned view without a line changing.
    #   * The image size does not move. A footprint's base spans (w + h) tiles
    #     on screen, and w + h is the same after a quarter turn — a 3x4 seen
    #     from the side is a 4x3, and 7 is 7. All four views come out the same
    #     size, on the same base, which is exactly what a sprite swap needs.
    cam.rotation_euler = (math.radians(90 - ELEVATION), 0,
                          math.radians(45 + azimuth))
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


_VARIANTS = {}


def _hash01(text):
    """A stable pseudo-random in [0,1) from a string. Deterministic on purpose:
    a render that differs between runs cannot be compared against the one
    before it, and comparing against the one before it is the whole method."""
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h / 0xFFFFFFFF


def vary_tones(spread=0.075):
    """Give every piece its own slightly different shade of its own colour.

    A roof of two hundred tiles painted in ONE orange is the giveaway. No two
    real tiles fired the same, no two stones came off the same bed, and the eye
    knows it long before it can say why. Varying the colour per PIECE — not per
    material — turns a flat plate into a surface, and it is the cheapest beauty
    in the whole kit: no geometry, no light, one pass at the end.

    The spread is small on purpose. Past about a tenth the pieces stop reading
    as one material and start reading as a mistake.
    """
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or ob.name == 'guide':
            continue
        for slot_i, slot in enumerate(ob.material_slots):
            base = slot.material
            if base is None:
                continue
            # Three steps rather than a continuum: this is a faceted art style,
            # and a smooth gradient across a roof would be a different one.
            step = int(_hash01(f'{ob.name}#{slot_i}') * 3) - 1
            if step == 0:
                continue
            key = (base.name, step)
            if key not in _VARIANTS:
                rgb = base.node_tree.nodes['Principled BSDF'] \
                    .inputs['Base Color'].default_value
                f = 1.0 + step * spread
                _VARIANTS[key] = flat(
                    f'{base.name}_{step}',
                    tuple(min(1.0, c * f) for c in rgb[:3]),
                )
            slot.material = _VARIANTS[key]


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
    ap.add_argument('--azimuth', type=float, default=0.0,
                    help='turn the camera round the building, in degrees. '
                         'Use 0/90/180/270 for the four map views.')
    ap.add_argument('--guides', action='store_true',
                    help='mark the footprint, to check the framing')
    # NOT --cycles: the Cycles add-on parses sys.argv itself and claims every
    # --cycles* option, so Blender aborts with "ambiguous option" before this
    # script is even reached.
    ap.add_argument('--pathtrace', action='store_true',
                    help='path-trace instead of rasterise: real contact '
                         'shading, at the cost of render time')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--no-bevel', action='store_true',
                    help='skip the edge bevel — tells geometry bugs from '
                         'modifier artefacts apart in one render')
    ap.add_argument('--no-render', action='store_true',
                    help='build the scene and stop — for opening it in the GUI')
    ap.add_argument('--blend', help='also save the scene to this .blend')
    args = ap.parse_args(argv)

    build, w, h = PRESETS[args.preset]
    clear()
    build(w, h)
    if args.guides:
        guide_plane(w, h)
    vary_tones()
    if not args.no_bevel:
        bevel_everything()
    light(args.azimuth)
    frame(w, h, args.scale, args.headroom, args.azimuth)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    if args.pathtrace and 'CYCLES' in engines:
        # Cycles for the real contact shading. EEVEE's fast GI only occludes
        # INDIRECT light, and this scene is lit almost entirely by one sun —
        # there was barely any indirect light left to occlude, which is why the
        # corners stayed as bright as the open court.
        scene.render.engine = 'CYCLES'
        scene.cycles.samples = args.samples
        scene.cycles.use_denoising = True
        scene.cycles.max_bounces = 4
        scene.cycles.diffuse_bounces = 3
    else:
        # EEVEE's identifier moved in 4.2 and again after; ask, do not assume.
        for name in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
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
