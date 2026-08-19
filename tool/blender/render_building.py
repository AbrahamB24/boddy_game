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
#   2. PALE walls — limestone, limestone, lime stucco — under that roof. The
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
    # Cut stone: ochre, NOT grey. Called travertine until 2026-08-12,
    # which is a Roman quarry and the wrong century for a name that
    # thirty builders reach for.
    'limestone': (0.88, 0.71, 0.47),
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
    # A BOLETE, not a fly agaric (user 2026-08-09). Scarlet is the only
    # saturated red the whole map has, and the habitat is the building a player
    # puts down most often — a settlement of scarlet toadstools drowns
    # everything around it. The dome on a stalk is what reads as a mushroom at
    # map size; the colour never had to carry any of it.
    'cap_wood': (0.60, 0.41, 0.25),
    # ── Props (user 2026-08-09) ──
    # "gib den Gebäuden noch mehr Individualität, so dass es sofort erkennbar
    #  ist, was es ist … Fish Hut braucht ein Boot und Wasser. Treasury braucht
    #  Gold und Caravanserai braucht Wagen und ev. Kamele"
    #
    # A building's SHAPE says how it is built; its PROPS say what it does, and
    # at map size the props win. These are the tones the props needed and the
    # architecture never did.
    # ── Life (user 2026-08-09) ──
    'smoke': (0.86, 0.86, 0.84),       # goes up, and says somebody is in
    'critter': (0.72, 0.56, 0.32),     # the small beasts underfoot
    'critter_dark': (0.48, 0.35, 0.20),
    'critter_alt': (0.58, 0.62, 0.70),
    'linen': (0.92, 0.90, 0.84),       # washing, bandages, sailcloth
    # ── Accents (user 2026-08-09) ──
    # One saturated note per building, so six half-timbered houses stop
    # being the same house. Deliberately DEEP rather than bright: the
    # ground is a mid green and the walls are warm stone, so a pastel
    # vanishes into both and a primary tears a hole in the picture.
    'cloth_red': (0.71, 0.24, 0.22),
    'cloth_teal': (0.22, 0.50, 0.49),
    'cloth_plum': (0.47, 0.28, 0.45),
    'cloth_gold': (0.85, 0.66, 0.24),
    'cloth_blue': (0.28, 0.40, 0.62),
    'bloom_red': (0.80, 0.29, 0.26),
    'bloom_white': (0.94, 0.93, 0.88),
    'bloom_blue': (0.44, 0.52, 0.78),
    'bloom_pink': (0.87, 0.55, 0.62),
    'herb': (0.44, 0.60, 0.28),
    'dirt': (0.42, 0.32, 0.21),        # the soil a planting sits in
    # A straw roof is the loudest ROOF the palette can make, which is why
    # the store gets it: a granary you can find from across the map.
    'thatch': (0.85, 0.65, 0.24),
    'thatch_dark': (0.63, 0.44, 0.15),
    'slate': (0.42, 0.45, 0.50),       # the cold roof, for the fish dock
    'slate_dark': (0.30, 0.33, 0.38),
    'water': (0.22, 0.50, 0.70),       # a dock, a pond, a trough worth seeing
    'water_deep': (0.14, 0.36, 0.56),
    'foam': (0.80, 0.90, 0.92),
    'hide': (0.49, 0.33, 0.19),        # a pack beast, a stretched pelt
    'hide_dark': (0.33, 0.21, 0.13),
    'cloth': (0.86, 0.80, 0.66),       # awnings, sacks, sailcloth
    'cloth_stripe': (0.72, 0.36, 0.30),
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
    'limestone_shade': (0.76, 0.59, 0.37),
    'ashlar_dark': (0.50, 0.36, 0.22),
    # ROAD STONE — greyer and cooler than the walls on purpose. A road paved in
    # the same ochre the buildings are built from reads as a courtyard spreading
    # between them rather than as something you travel along; it is the one
    # surface that has to recede.
    # ── Signature materials (user 2026-08-12) ──
    # One roof material per building means five more of them, and the
    # three metals below are the ones a medieval roof could actually be:
    # copper gone green, gold leaf, and lead-black iron.
    'verdigris': (0.36, 0.56, 0.48),   # the minster's copper, weathered
    'verdigris_dark': (0.24, 0.40, 0.35),
    'gold_dark': (0.72, 0.52, 0.14),   # gilt in shadow, for the treasury
    'copper': (0.74, 0.44, 0.22),      # the still, and nothing else
    # ── QUARRY ROCK (user 2026-08-12, from a reference) ──
    # The palette note above says "No greys anywhere", and it was right about
    # the settlement: a village of houses in one warm family is what makes it
    # look like one world. Living rock is the exception that proves it — it is
    # the only thing on the map that was never built, never fired and never
    # dyed, and warm ochre boulders read as sandcastles.
    #
    # Still not a true grey: every tone below is pulled a little towards blue
    # on the shadow side and a little towards the walls' ochre on the lit one,
    # so the quarry sits beside a house instead of in front of it.
    # Pitched a step and a half down from the first attempt: at 0.60 under a
    # 2.5 sun the lit face renders near-white and the seam has nothing to be
    # darker than, which is where the whole painted look lives.
    'rock': (0.45, 0.45, 0.45),          # the face the sun is on
    'rock_light': (0.58, 0.58, 0.56),    # the top, catching sky
    'rock_shade': (0.31, 0.32, 0.35),    # the turned face
    'rock_deep': (0.15, 0.16, 0.19),     # THE tone that does the work
    'rock_warm': (0.49, 0.45, 0.39),     # every fourth block, weathered
    'steel': (0.40, 0.45, 0.52),         # the cool metal of the gear
    'steel_dark': (0.24, 0.28, 0.34),
    'cobble': (0.55, 0.46, 0.38),
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
BEVEL_WIDTH = 0.0068
BEVEL_SEGMENTS = 3


# ── Materials ──────────────────────────────────────────────
# ── How each family of material CATCHES LIGHT ──────────────
# (roughness, metallic, grain scale, grain depth, bump, stretch)
#
# grain scale   how fine the noise is, in cycles per world unit
# grain depth   how far the ramp swings either side of the base tone
# bump          relief strength; 0 leaves the surface dead flat
# stretch       pulls the noise along z, for anything with a grain direction
#
# Matched by the LONGEST key prefix, so 'rock_deep' finds 'rock' and a new
# tone in an existing family needs no entry. Anything unmatched keeps the old
# behaviour exactly — chalk — which is what most of the small props want.
FINISH = {
    # Stone: the roughest thing here, and the one that needs the most relief.
    'rock': (0.94, 0.0, 26, 0.16, 0.55, 1.0),
    'ashlar': (0.90, 0.0, 30, 0.10, 0.35, 1.0),
    'limestone': (0.88, 0.0, 32, 0.09, 0.32, 1.0),
    'cobble': (0.92, 0.0, 34, 0.11, 0.4, 1.0),
    'stucco': (0.95, 0.0, 44, 0.05, 0.2, 1.0),
    # Timber, with the grain pulled along the piece.
    'oak': (0.80, 0.0, 22, 0.10, 0.3, 5.0),
    'root': (0.84, 0.0, 20, 0.11, 0.34, 4.0),
    'shingle': (0.78, 0.0, 26, 0.09, 0.28, 3.0),
    'thatch': (0.88, 0.0, 40, 0.12, 0.42, 3.5),
    'straw': (0.88, 0.0, 42, 0.12, 0.4, 3.0),
    'hide': (0.82, 0.0, 30, 0.10, 0.3, 1.6),
    # Metal. The single biggest change: at metallic 1 the sun becomes a
    # highlight instead of a flat lighter patch.
    'steel': (0.34, 1.0, 46, 0.05, 0.12, 1.0),
    'iron': (0.42, 1.0, 44, 0.06, 0.14, 1.0),
    'gold': (0.26, 1.0, 40, 0.04, 0.08, 1.0),
    'copper': (0.30, 1.0, 40, 0.05, 0.1, 1.0),
    'verdigris': (0.62, 0.0, 34, 0.09, 0.22, 1.0),
    'slate': (0.60, 0.0, 34, 0.08, 0.26, 2.0),
    # Cloth and leaf: soft, faintly sheened, barely relieved.
    'cloth': (0.86, 0.0, 36, 0.06, 0.12, 1.0),
    'linen': (0.86, 0.0, 38, 0.05, 0.1, 1.0),
    'banner': (0.80, 0.0, 34, 0.06, 0.12, 1.0),
    'leaf': (0.74, 0.0, 30, 0.10, 0.2, 1.0),
    'moss': (0.86, 0.0, 34, 0.13, 0.3, 1.0),
    'herb': (0.74, 0.0, 30, 0.10, 0.2, 1.0),
    'water': (0.12, 0.0, 18, 0.05, 0.08, 1.0),
    'tile': (0.72, 0.0, 30, 0.08, 0.24, 2.0),
    'sand': (0.94, 0.0, 40, 0.09, 0.3, 1.0),
    'dirt': (0.95, 0.0, 34, 0.12, 0.36, 1.0),
}
DEFAULT_FINISH = (0.92, 0.0, 0, 0.0, 0.0, 1.0)   # chalk, as before


def finish_for(name):
    """The finish for a palette key, by longest matching prefix.

    vary_tones() invents names like 'rock_shade_-1', so this has to survive a
    suffix as well as a family — matching on prefix does both at once.
    """
    best = None
    for key in FINISH:
        if name.startswith(key) and (best is None or len(key) > len(best)):
            best = key
    return FINISH[best] if best else DEFAULT_FINISH


def flat(name, rgb):
    """One material: its colour, its grain, its relief and its response.

    ── Was chalk, on purpose, and is not any more (user 2026-08-12) ──
    This used to set roughness 1 and specular 0 and stop: "No specular, no
    roughness games — a facet is a facet." That is what made the renders read
    as pixel art rather than as painted objects. Nothing about the FORMS was
    ever the problem; a box with grain and a highlight is a stone block, and
    the same box in one flat tone is a pixel.

    Everything is still procedural — no image files, nothing to ship, and a
    part that is a millimetre across gets the same treatment as a wall.
    """
    rough, metal, scale, depth, bump, stretch = finish_for(name)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = rough
    if 'Metallic' in bsdf.inputs:
        bsdf.inputs['Metallic'].default_value = metal
    # A dielectric still wants SOME specular or it cannot read as wet, waxed or
    # polished; only the old chalk finish keeps it at zero.
    for key in ('Specular IOR Level', 'Specular'):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = 0.0 if scale == 0 else 0.35
            break
    if scale == 0:
        return mat

    # ── Grain ──
    # A ramp between a darker and a lighter version of the SAME tone, driven by
    # noise. Deliberately narrow: past about a fifth the surface stops reading
    # as one material and starts reading as camouflage.
    coord = nt.nodes.new('ShaderNodeTexCoord')
    mapping = nt.nodes.new('ShaderNodeMapping')
    mapping.inputs['Scale'].default_value = (1.0, 1.0, 1.0 / stretch)
    noise = nt.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = scale
    noise.inputs['Detail'].default_value = 8.0
    noise.inputs['Roughness'].default_value = 0.62
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    lo = tuple(max(0.0, c * (1.0 - depth)) for c in rgb)
    hi = tuple(min(1.0, c * (1.0 + depth)) for c in rgb)
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (*lo, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (*hi, 1)
    nt.links.new(coord.outputs['Object'], mapping.inputs['Vector'])
    nt.links.new(mapping.outputs['Vector'], noise.inputs['Vector'])
    nt.links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])

    # ── Relief ──
    # A second, finer noise into a Bump. This is the one that makes the light
    # BREAK across a surface instead of sliding over it, and it is the whole
    # difference between grey plastic and stone.
    if bump > 0:
        fine = nt.nodes.new('ShaderNodeTexNoise')
        fine.inputs['Scale'].default_value = scale * 2.6
        fine.inputs['Detail'].default_value = 6.0
        fine.inputs['Roughness'].default_value = 0.7
        bmp = nt.nodes.new('ShaderNodeBump')
        bmp.inputs['Strength'].default_value = bump
        bmp.inputs['Distance'].default_value = 0.02
        nt.links.new(mapping.outputs['Vector'], fine.inputs['Vector'])
        nt.links.new(fine.outputs['Fac'], bmp.inputs['Height'])
        nt.links.new(bmp.outputs['Normal'], bsdf.inputs['Normal'])
    return mat


# A unit cube centred on the origin — BLENDER'S OWN cube, corner for corner and
# winding for winding, copied out of what primitive_cube_add(size=1) produces.
#
# Any outward-wound cube would look right, and a different vertex ORDER still
# would not: the bevel modifier walks the mesh in index order, so it lays its
# new geometry down in a different sequence and the rasteriser resolves a few
# hundred edge pixels a shade differently. Harmless, and it would still have
# made every render in docs/ differ from every render made before this change,
# for no reason anyone could point at. Matching the order exactly means the
# switch is provably free: same bytes out.
_CUBE_CORNERS = (
    (-0.5, -0.5, -0.5), (-0.5, -0.5, 0.5), (-0.5, 0.5, -0.5), (-0.5, 0.5, 0.5),
    (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (0.5, 0.5, -0.5), (0.5, 0.5, 0.5),
)
_CUBE_FACES = (
    (0, 1, 3, 2), (2, 3, 7, 6), (6, 7, 5, 4),
    (4, 5, 1, 0), (2, 6, 4, 0), (7, 3, 1, 5),
)


def box(name, x, y, z, sx, sy, sz, mat):
    """A box by its CENTRE-BOTTOM, because buildings stand on the ground.

    ── Built by hand, NOT by bpy.ops (user 2026-08-09: Blender hangs) ──
    This used to be `primitive_cube_add` followed by `transform_apply`. Two
    OPERATORS per box — and an operator is not a function call: it pushes an
    undo step, tags the depsgraph, and makes Blender re-evaluate and redraw the
    whole scene before it returns. The cost is per box and it grows with how
    many boxes are already there, so the last stone of a castle is far more
    expensive than the first.
    """
    verts = [(cx * sx, cy * sy, cz * sz) for cx, cy, cz in _CUBE_CORNERS]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], list(_CUBE_FACES))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    # ── The origin is the box's OWN centre, and that is not decoration ──
    # Baking the position into the vertices instead would put every object's
    # origin at the world origin, and anything rotated afterwards would then
    # turn about the map's centre and fly off across it. That was the root
    # cause of every stray stick in this file's history: the gills that speared
    # through the mushroom caps, the column flutes that became a bundle of
    # poles, the pantile ribs and the timber braces — four separate diagnoses,
    # three redesigns around the symptom, one cause.
    ob.location = (x, y, z + sz / 2)
    ob.data.materials.append(mat)
    for p in mesh.polygons:
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


def glow_mat(key, rgb, strength=2.0):
    """A palette colour that is also a light source, made once and cached
    exactly like mat() — for the handful of things (a lit window, a lamp)
    that need to visibly EMIT rather than just look pale under the sun."""
    if key not in _MATS:
        m = flat(key, rgb)
        bsdf = m.node_tree.nodes['Principled BSDF']
        bsdf.inputs['Emission Strength'].default_value = strength
        bsdf.inputs['Emission Color'].default_value = (*rgb, 1)
        _MATS[key] = m
    return _MATS[key]


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
         key='limestone', facing=facing)
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


def ashlar_courses(name, x, y, z, sx, sy, h, key='ashlar', dark='ashlar_dark',
                   course=0.0691, block=0.144, joint=0.0122):
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
            # ── CLIP to the wall, do not SKIP (user 2026-08-06) ──
            # A course is offset by half a block on alternate rows, so its first
            # and last stone always hang over one end. Skipping those left a
            # bare vertical strip up every corner — visible on the towers as an
            # unstoned band exactly where two walls meet, which is the one place
            # masonry has to be convincing.
            #
            # Cut them to the wall's edge instead. A short stone at the end of a
            # course is what a real wall has: the mason cuts one to fit rather
            # than leaving a hole.
            # ── ONE RUN OWNS THE CORNER (user 2026-08-09) ──
            # Both runs used to reach the full span, so at every corner of every
            # wall two stones stood in the same place with identical top faces —
            # and identical surfaces at identical depth are what the renderer
            # flickers between as the view moves. The x-run carries the corner
            # and the y-run stops just inside it, which is also how a mason
            # bonds one: one course runs through, the next butts against it.
            # Just inside, not flush: a hair of overlap leaves no seam to see
            # and still no plane to fight over.
            edge = span / 2 - (0 if axis == 0 else joint * 2 - 0.004)
            for i in range(n + 2):
                t = -span / 2 + bw * i + stagger - bw
                lo = max(t - bw / 2, -edge)
                hi = min(t + bw / 2, edge)
                if hi - lo <= joint * 1.5:
                    continue
                mid, wide = (lo + hi) / 2, hi - lo
                for sign in (-1, 1):
                    if axis == 0:
                        bx, by = x + mid, y + sign * (other / 2 - joint)
                        dims = (wide - joint, joint * 2, ch - joint)
                    else:
                        bx, by = x + sign * (other / 2 - joint), y + mid
                        dims = (joint * 2, wide - joint, ch - joint)
                    box(f'{name}_{r}_{axis}_{i}_{sign}', bx, by, z + r * ch,
                        *dims, mat(key))
            # ── NO QUOINS, and the reason is cost, not taste ──
            # Long-and-short stones binding the corners were the right detail
            # and I built them: four extra boxes per course, on every stone
            # surface in the building. box() goes through a Blender OPERATOR,
            # which carries a scene update each time, so the castle stopped
            # being slow to draw and became slow to BUILD — past ten minutes
            # with no picture at all.
            #
            # The corner GAP was the actual bug and the clipping above fixes
            # it. Quoins were a second, cosmetic improvement riding along, and
            # a cosmetic improvement that makes the tool unusable is not an
            # improvement. If they come back it must be as one stone every
            # third course, not every one.


def string_course(name, x, y, z, sx, sy, key='limestone'):
    """A moulding running round a wall: three thin bands of different widths.

    One band is a stripe. Three of stepped width is a PROFILE, and a profile is
    what makes stone look cut rather than painted — for the price of two boxes.
    """
    box(f'{name}_a', x, y, z, sx + 0.02, sy + 0.02, 0.05, mat(key))
    box(f'{name}_b', x, y, z + 0.05, sx + 0.10, sy + 0.10, 0.045, mat(key))
    box(f'{name}_c', x, y, z + 0.095, sx + 0.05, sy + 0.05, 0.035,
        mat('limestone_shade'))


def flute_faces(ob, key='limestone', shade='limestone_shade'):
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


def plank_door(name, x, y, z, w, h, facing='y', planks=10):
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


def arched_door(name, x, y, z, w, h, facing='y', boards=12, straps=(0.28, 0.74)):
    """A door with a ROUND head — boards cut to the arch they stand in.

    ── Why the DOOR has to carry the curve (user 2026-08-09: "das Tor der Burg
       soll Rund sein") ──
    The gate already stood in an arched opening, and it still read as square,
    because the stone is pale on pale and the door is the one dark high-contrast
    shape in the middle of the facade. The eye takes the DOOR for the opening.
    Carving the arch and then filling it with a rectangle of planks means the
    arch is never seen.

    Each board is cut where the arc crosses its OUTER top corner, not its
    centre: cut at the centre, half of every board pokes its corner through the
    stone above — and it is the outer boards, the ones on the steep part of the
    curve, where that is worst.

    The straps stay BELOW the springing line on purpose. That is the only band
    of the door where every board is still full width, so one straight strap
    crosses all of them; above it, iron would have to be cut to the curve too,
    and a stepped strap at this size is noise.
    """
    r = w / 2
    straight = max(0.0, h - r)

    def at(into, along=0.0):
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    bw = w / boards
    for i in range(boards):
        t = -w / 2 + bw * (i + 0.5)
        # The outer top corner, which is what the arc has to clear.
        edge = abs(t) + bw / 2
        top = straight + (math.sqrt(max(0.0, r * r - edge * edge))
                          if edge < r else 0.0)
        if top <= 0.05:
            continue
        bx, by = at(0.0, t)
        wall_box(f'{name}_b{i}', bx, by, z, bw - 0.022, 0.1, top,
                 mat('oak' if i % 2 else 'oak_light'), facing=facing)
    for j, hz in enumerate(straps):
        sx_, sy_ = at(-0.06)
        wall_box(f'{name}_strap{j}', sx_, sy_, z + hz, w - 0.02, 0.07, 0.13,
                 mat('iron'), facing=facing)
        # Rivets spaced to the BOARDS, so the two rhythms agree instead of
        # arguing — the lesson from the studded version of this gate.
        for i in range(boards):
            t = -w / 2 + bw * (i + 0.5)
            rx, ry = at(-0.11, t)
            box(f'{name}_riv{j}{i}', rx, ry, z + hz + 0.03, 0.06, 0.05, 0.06,
                mat('limestone'))
    hx, hy = at(-0.06, -w / 2 + 0.05)
    wall_box(f'{name}_hinge', hx, hy, z, 0.1, 0.07, straight, mat('iron'),
             facing=facing)
    rx, ry = at(-0.12, w * 0.28)
    box(f'{name}_ring', rx, ry, z + straight * 0.62, 0.15, 0.05, 0.15,
        mat('iron'))


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


def lantern(name, x, y, z, drop=0.3, key='iron'):
    """A lantern on a chain: a turned cap, a glass, a ring below."""
    tube(f'{name}_chain', [(x, y, z), (x, y, z - drop)], r=0.014, key=key,
         sides=5)
    lathe(f'{name}_cap', x, y, z - drop - 0.11, [(0.02, 0.0), (0.082, 0.06),
                                                 (0.065, 0.1)], sides=10,
          key=key)
    cyl(f'{name}_glass', x, y, z - drop - 0.25, 0.062, 0.15, sides=10,
        key='gold')
    ring(f'{name}_frame', x, y, z - drop - 0.25, 0.064, 0.014, key=key,
         sides=10, tube_sides=5)
    ring(f'{name}_frame2', x, y, z - drop - 0.11, 0.064, 0.014, key=key,
         sides=10, tube_sides=5)


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
    """A round bale on its side, corded twice. It was a box with two straps,
    and a bale is the most obviously cylindrical object in any yard."""
    ob = cyl(f'{name}_body', x, y - sy / 2, z + h / 2, h / 2, sy, sides=12,
             axis='y', key=key, smooth=False)
    ob.scale = (1.0, 1.0, sx / max(h, 1e-6) * 0.62)
    for t in (-0.26, 0.26):
        ring(f'{name}_band{t}', x + sx * t * 0.7, y, z + h / 2, h * 0.52,
             0.016, key='root', axis='y', sides=12, tube_sides=5)


def straw_scatter(name, x, y, z, r, n=14, key='straw'):
    """Loose straw on the ground. Deterministic, not random: a render that
    differs between runs cannot be compared against the one before it."""
    for i in range(n):
        a = 2.399963 * i                       # the golden angle, so it spreads
        rad = r * math.sqrt((i + 0.5) / n)
        ob = box(f'{name}_{i}', x + rad * math.cos(a), y + rad * math.sin(a),
                 z, 0.17, 0.05, 0.025, mat(key))
        ob.rotation_euler = (0, 0, a)


def paving(name, x, y, z, sx, sy, key_a='ashlar', key_b='ashlar_dark',
           tile=0.06):
    """A yard laid in irregular stone flags.

    ── Was a MOSAIC, which is the wrong century (user 2026-08-12) ──
    A grid of small square tesserae in two alternating colours is a Roman
    floor and nothing else; it was the giveaway in four courtyards. A medieval
    yard is flagged: big slabs, no two the same, laid to no pattern, with the
    joints wide enough to see.
    """
    n = max(2, int(sx / (tile * 3.2)))
    m = max(2, int(sy / (tile * 3.2)))
    box(f'{name}_bed', x, y, z, sx, sy, 0.02, mat('dirt'))
    for i in range(n):
        for j in range(m):
            h1 = _hash01(f'{name}{i}.{j}')
            h2 = _hash01(f'{name}b{i}.{j}')
            if h1 < 0.06:
                continue                     # a flag gone, and weeds in it
            fw = sx / n * (0.78 + 0.16 * h1)
            fd = sy / m * (0.78 + 0.16 * h2)
            fl = box(f'{name}_{i}_{j}',
                     x - sx / 2 + sx * (i + 0.5) / n + (h1 - 0.5) * 0.03,
                     y - sy / 2 + sy * (j + 0.5) / m + (h2 - 0.5) * 0.03,
                     z + 0.01, fw, fd, 0.022 + 0.014 * h1,
                     mat(key_a if h1 > 0.4 else key_b))
            fl.rotation_euler = (0, 0, (h2 - 0.5) * 0.12)


def half_timber(name, x, y, z, sx, sy, h, bays=7, beam=0.0638,
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
            # ── The studs run BETWEEN the plates (user 2026-08-09) ──
            # They used to run the full height, straight through both, so every
            # crossing was two timbers of identical thickness occupying the same
            # space with all four faces coincident — a flicker at every joint on
            # every timbered wall. Between the plates is also how a frame is
            # actually cut: the stud is tenoned into the plate, not laid over it.
            #
            # And the CORNERS belong to one run only. Both runs put a post on
            # each of the four corners, which is the same box built twice.
            for i in range(bays + 1):
                if axis == 1 and i in (0, bays):
                    continue
                put(f'stud{i}', -span / 2 + span * i / bays, z + beam, beam,
                    h - 2 * beam)
            bw, bh = span / bays, h * 0.66
            b = put('brace', 0, z, beam, math.hypot(bw, bh),
                    math.atan2(bw, bh) * (1 if sign > 0 else -1))
            b.location = (x + (-span / 2 + bw / 2 if axis == 0
                               else sign * other / 2),
                          y + (sign * other / 2 if axis == 0
                               else -span / 2 + bw / 2),
                          z + h / 2)


def shingle_gable(name, x, y, z, sx, sy, h, overhang=0.22, rows=32,
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
        # PROUD OF THE VERGE, not flush with it. Flush means every course ends
        # on exactly the plane the roof body ends on, and two surfaces at the
        # same depth are two surfaces the renderer has to choose between — per
        # pixel, and differently as the view moves. That is half of "die Seiten
        # der Dächer flackern" (user 2026-08-09); it also happens to be what a
        # real course does, which laps the barge board rather than stopping
        # level with it.
        for sign in (-1, 1):
            if ridge_along == 'y':
                bx, by = x + sign * off, y
                dims = (run / rows * 1.6, span + 0.012, 0.055)
            else:
                bx, by = x, y + sign * off
                dims = (span + 0.012, run / rows * 1.6, 0.055)
            box(f'{name}_c{i}_{sign}', bx, by, z + h * f, *dims,
                mat(key if i % 2 else dark))
    # ── THE ENDS GET COURSES TOO (user 2026-08-04: "diese sind zu flach") ──
    # The slopes were coursed and the two triangular ends were left as one
    # plain face — which is exactly the surface that faces the camera on a
    # small roof (a porch, a spire, a turret), so those read as flat plates of
    # colour while the big roofs read as roofs.
    #
    # A triangle narrows towards its apex, so each course is shorter than the
    # one below by the same fraction the triangle has closed. That is the same
    # solve as the hip roof's, one dimension simpler — and like it, a course
    # parallel to the eaves has no end to leave hanging.
    for i in range(rows):
        f = (i + 0.3) / rows
        half_span = run * (1 - f)
        if half_span <= 0.04:
            break
        # ── HEIGHT COMES FROM h, NOT FROM run ──
        # It used to be run/rows*1.5, and run is how far the slope reaches
        # SIDEWAYS — nothing to do with the step between courses, which is
        # h/rows. On a wide, shallow roof (the keep's is four tiles across and
        # one tall) that made every course more than twice as tall as the gap
        # to the next, so all eleven of them overlapped each other while sharing
        # one outer face. That is the other half of "die Seiten der Dächer
        # flackern" (user 2026-08-09) and by far the larger half: 76 pairs of
        # coincident faces on the keep roof alone.
        #
        # 1.35 of the step is a lap you can see; the proudness then TAPERS, so
        # each course stands a hair further out than the one above it. Two
        # courses that overlap now differ in depth wherever they meet, and a
        # lower course lapping over the one above is what a shingled verge is.
        ch = h / rows * 1.35
        out = 0.03 - 0.014 * f
        for sign in (-1, 1):
            if ridge_along == 'y':
                bx, by = x, y + sign * (span / 2 + out)
                dims = (2 * half_span, 0.06, ch)
            else:
                bx, by = x + sign * (span / 2 + out), y
                dims = (0.06, 2 * half_span, ch)
            # Dropped a hair as well: the slope course at the same index starts
            # at exactly z + h*f, and two boxes sharing a bottom plane fight the
            # same way two sharing a side plane do.
            box(f'{name}_e{i}_{sign}', bx, by, z + h * f - 0.004, *dims,
                mat(key if i % 2 else dark))

    if ridge_along == 'y':
        box(f'{name}_ridge', x, y, z + h - 0.05, 0.15, span + 0.05, 0.1,
            mat('oak'))
    else:
        box(f'{name}_ridge', x, y, z + h - 0.05, span + 0.05, 0.15, 0.1,
            mat('oak'))
    return ob


def gable_boards(name, x, y, z, span, h, thick=0.05, count=22, key='oak',
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
        # PROUD of the boarding, like the collar tie below. At the same
        # thickness the rake and the boards it crosses share both faces exactly,
        # and two surfaces at one depth are what flickers as the view moves
        # (user 2026-08-09: "die Seiten der Dächer flackern"). Trim standing a
        # little off the boarding is also simply what trim does.
        dims = ((0.11, thick + 0.03, ln) if axis == 'x'
                else (thick + 0.03, 0.11, ln))
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


def jetty(name, x, y, z, sx, sy, out=0.2, key='oak', count=6):
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


def battlements(name, x, y, z, sx, sy, key='ashlar', merlon=0.1072, gap=0.0844,
                h=0.3, inset=0.0):
    """Crenellations round the top of a wall — THE castle signal.

    Nothing else says fortress so cheaply. A wall is a wall until its top is
    notched, and then it is a wall someone expected to be shot at from.

    The corbel course under them matters as much as the teeth: a parapet that
    grows straight out of the wall reads as a wall with holes in it, while one
    that steps OUT first reads as something built on top for a purpose.

    [inset] pulls the whole parapet — corbel included — in from the corners, for
    a wall-head that has something of its own standing on each corner. A turret
    corbelled off the corner and a parapet that runs straight through it are two
    solid things in the same place; on the donjon that put four spires through
    four merlons (user 2026-08-09: "Holz und Zinnen nicht überlappen lassen").
    """
    box(f'{name}_corbel', x, y, z, sx + 0.16 - 2 * inset,
        sy + 0.16 - 2 * inset, 0.1, mat('limestone'))
    step = merlon + gap
    # A corner is on BOTH runs, so both would stand a merlon on it — two blocks
    # in the same place with identical top faces, which the renderer then picks
    # between per pixel and per frame. One of the flickers reported on
    # 2026-08-09. Let the long run own the corners; the short one stops short.
    # Unless the inset has already moved the two apart, in which case skipping
    # would leave a real gap instead of removing a real overlap.
    # …and only when the long run is actually there to own them: a curtain wall
    # is thinner than one merlon, so its short run places nothing at all, and
    # skipping the long run's ends as well would leave both ends of the wall
    # bare.
    corners_collide = (inset + 0.05 < (0.16 + merlon) / 2
                       and sx - 2 * inset > merlon)
    for axis, span, other in ((0, sx, sy), (1, sy, sx)):
        run = span - 2 * inset
        if run <= merlon:
            continue
        n = max(1, int(run / step))
        for i in range(n + 1):
            if axis == 1 and corners_collide and i in (0, n):
                continue
            t = -run / 2 + run * i / n
            for sign in (-1, 1):
                if axis == 0:
                    bx, by = x + t, y + sign * (other / 2 + 0.05)
                    dims = (merlon, 0.16, h)
                else:
                    bx, by = x + sign * (other / 2 + 0.05), y + t
                    dims = (0.16, merlon, h)
                box(f'{name}_{axis}{sign}{i}', bx, by, z + 0.1, *dims,
                    mat(key))


def arrow_slit(name, x, y, z, h=0.5, facing='y', key='dark'):
    """A tall thin opening with a stone surround. The castle's window.

    Narrow on purpose, and not only for the fiction: at 256 px a slit is one
    dark pixel-wide line, which reads as a slit, where a scaled-down leaded
    window reads as a smudge.
    """
    def at(into, along=0.0):
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    fx, fy = at(0.03)
    wall_box(f'{name}_frame', fx, fy, z - 0.07, 0.26, 0.1, h + 0.14,
             mat('limestone'), facing=facing)
    hx, hy = at(-0.02)
    wall_box(f'{name}_slit', hx, hy, z, 0.08, 0.07, h, mat(key), facing=facing)


def chimney(name, x, y, z, w, h, key='ashlar'):
    """A stone stack. Its vertical is what keeps the roofline from being one
    unbroken triangle, and smoke is the cheapest sign of someone home."""
    ashlar_courses(f'{name}_stack', x, y, z, w, w, h, key=key,
                   dark='ashlar_dark', course=0.0871, block=0.1289)
    box(f'{name}_corbel', x, y, z + h, w + 0.13, w + 0.13, 0.07,
        mat('limestone'))
    box(f'{name}_cap', x, y, z + h + 0.07, w + 0.02, w + 0.02, 0.09, mat(key))
    box(f'{name}_pot', x, y, z + h + 0.16, w * 0.4, w * 0.4, 0.14, mat('tile'))


def leaded_window(name, x, y, z, w, h, facing='y', shutters=True, open=False,
                  lit=False, key='oak', glass='gold', panes=1, out=1):
    """A small window with a cross of mullions and a pair of shutters.

    Small on purpose. Glass was dear: a wall of it reads as a shopfront, two
    little lit panes read as a home. The pane is the gold — a window that is
    not LIT is a hole, and a hole says nobody is in.

    ── open (user 2026-08-16: "Die Fenster bitte öffnen") ──
    Default False: every existing building keeps its flat, closed shutters
    unchanged. True swings each shutter out on its OUTER edge — the hinge —
    rather than spinning it in place around its own centre, which would
    read as the shutter floating off the wall instead of opening on it.

    ── lit (user 2026-08-16: "es soll Licht herausscheinen") ──
    Default False keeps the plain 'gold' pane every other building already
    uses. True swaps in an emissive glass — an actual light source in the
    render, not just a warm colour.

    ── out (user 2026-08-17, two more photos: no glass at all on some
    windows, "dunkles Holz verdeckt das Fenster") ──
    The real bug, not a shutter problem at all: at() moves the glass by
    into=-0.01, meant to sit it just PROUD of the wall. For facing='y' that
    is `y + into`, which is proud on a wall whose face is at MIN y — every
    such window in this kit happens to be built that way, so it always
    worked. For facing='x' it is `x - into`, proud on a MAX-x face but
    EMBEDDED half a centimetre inside the solid wall panel on a MIN-x
    face — invisible behind opaque timber, which is exactly "kein Fenster,
    dunkles Holz davor". The same asymmetry bites facing='y' on a MAX-y
    face. out=-1 flips at()'s sign (and the open shutter's swing direction
    with it) for the walls where the default guess is backwards; default
    out=1 reproduces the exact behaviour every existing caller already
    depends on.

    ── key, glass, panes (user 2026-08-17, with a reference photo: "Bitte
    alle genau so wie im Foto gestalten") ──
    Three more knobs, all defaulting to the original look: key recolours
    the frame and mullions (the photo wants the lighter 'oak_light', not
    the dark 'oak' every other building keeps), glass picks the pane's
    material key ('moss' for the photo's olive tint), and panes subdivides
    the glass into an N x N lattice instead of one plain cross — a proper
    leaded window, the kind the function is named for but never actually
    built until now.
    """
    def at(into, along=0.0):
        into *= out
        return (x + (along if facing == 'y' else -into),
                y + (into if facing == 'y' else along))

    fx, fy = at(0.05)
    wall_box(f'{name}_frame', fx, fy, z - 0.06, w + 0.15, 0.11, h + 0.15,
             mat(key), facing=facing)
    gx, gy = at(-0.01)
    wall_box(f'{name}_glass', gx, gy, z, w, 0.07, h,
             glow_mat('window_glow', (1.0, 0.78, 0.42), 2.4) if lit
             else mat(glass), facing=facing)
    mx, my = at(-0.045)
    if panes <= 1:
        wall_box(f'{name}_mv', mx, my, z, 0.04, 0.05, h, mat(key),
                 facing=facing)
        wall_box(f'{name}_mh', mx, my, z + h / 2 - 0.02, w, 0.05, 0.04,
                 mat(key), facing=facing)
    else:
        for i in range(1, panes):
            t = -w / 2 + w * i / panes
            vx, vy = at(-0.045, t)
            wall_box(f'{name}_mv{i}', vx, vy, z, 0.035, 0.05, h, mat(key),
                     facing=facing)
        for j in range(1, panes):
            t = -h / 2 + h * j / panes
            wall_box(f'{name}_mh{j}', mx, my, z + t, w, 0.05, 0.035,
                     mat(key), facing=facing)
    sx_, sy_ = at(0.02)
    wall_box(f'{name}_sill', sx_, sy_, z - 0.13, w + 0.32, 0.17, 0.07,
             mat('oak_light'), facing=facing)
    if shutters:
        for sign in (-1, 1):
            if not open:
                bx, by = at(-0.07, sign * (w / 2 + 0.13))
                wall_box(f'{name}_sh{sign}', bx, by, z - 0.03, 0.21, 0.07,
                         h + 0.08, mat('oak_light'), facing=facing)
                continue
            # ── Hinged on the OUTER edge, swung open (user 2026-08-16
            # screenshots: shutters were landing as a small box floating
            # loose of the window instead of standing open beside it) ──
            # The previous version rotated the box around its OWN centre
            # and then tried to patch the resulting gap by shifting its
            # location — but with sin/cos on the wrong axes, and rotating
            # around Y instead of Z on the facing='x' wall (tipping the
            # shutter flat instead of swinging it sideways). Rebuilt from
            # the hinge point outward instead: HP is the window edge the
            # shutter actually pivots on, and the box's centre is placed
            # r (its own half-width) from HP along cos(theta)*inward +
            # sin(theta)*outward — closed (theta=0) puts it flush over the
            # opening, open swings it round. theta=175°, not 90-100°: a
            # shutter propped out at an angle isn't "open" here, it has to
            # lie flat back against the wall (user 2026-08-17: "Die
            # Fensterläden müssen flach an der Wand sein") — just short of
            # a full 180° fold so it doesn't sit exactly coplanar with the
            # wall panel. The same two lines work on both wall facings
            # because inward/outward are expressed in world XY, not in the
            # box's own local axes.
            # out does NOT apply here — it corrects at()'s sign convention
            # for the glass/frame/sill (see the docstring), which is an
            # unrelated bug to which way a shutter physically swings. The
            # shutter's own hinge point comes from at(0.0, ...), where
            # into=0 makes out a no-op anyway; its SWING still has to point
            # into genuinely open air on every wall, which for both
            # facings is this fixed pair regardless of out.
            r, theta = 0.105, math.radians(175)
            if facing == 'y':
                inward, outward = (-sign, 0.0), (0.0, 1.0)
            else:
                inward, outward = (0.0, -sign), (-1.0, 0.0)
            comp = (math.cos(theta) * inward[0] + math.sin(theta) * outward[0],
                   math.cos(theta) * inward[1] + math.sin(theta) * outward[1])
            hpx, hpy = at(0.0, sign * (w / 2 + 0.02))
            sh = box(f'{name}_sh{sign}', hpx + r * comp[0], hpy + r * comp[1],
                    z - 0.03, 0.21, 0.07, h + 0.08, mat('oak_light'))
            sh.rotation_euler = (0, 0, math.atan2(comp[1], comp[0]))


# ── Sporehollow parts ──────────────────────────────────────
def cap(name, x, y, z, r, h, sides=20, rings=11, key='cap', flare=0.13):
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
def warts(name, prof, x, y, z, count=16, key='cap_spot'):
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


def roots(name, x, y, z, r, count=10, reach=0.5, key='root'):
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
    """Woven withies: round rods and round rails, because a withy is a whip
    of hazel and every one of them was a square stick."""
    n = max(3, int(span / 0.24))
    for i in range(n):
        t = -span / 2 + span * (i + 0.5) / n
        bx, by = (x + t, y) if axis == 'x' else (x, y + t)
        hh = h * (0.86 + 0.16 * ((i * 7) % 3) / 2)
        cyl(f'{name}_p{i}', bx, by, z, 0.028, hh, sides=8,
            key=key if i % 2 else 'root_dark')
    for k, hz in enumerate((0.32, 0.72)):
        a = (x - span / 2, y) if axis == 'x' else (x, y - span / 2)
        b = (x + span / 2, y) if axis == 'x' else (x, y + span / 2)
        tube(f'{name}_r{k}', [(a[0], a[1], z + h * hz),
                              (b[0], b[1], z + h * hz)], r=0.022,
             key='root_dark', sides=6)


def well(name, x, y, z, r=0.36):
    """A wellhead: a turned stone ring, a windlass on round posts, a bucket.

    Was the other builder still calling bpy.ops — a cylinder primitive plus a
    transform apply, for a shape lathe() returns from vertices.
    """
    lathe(f'{name}_ring', x, y, z, [(r, 0.0), (r * 1.02, 0.36),
                                    (r * 0.98, 0.42)], sides=14,
          key='ashlar', smooth=False)
    lathe(f'{name}_in', x, y, z + 0.3, [(r * 0.82, 0.0), (r * 0.82, 0.06)],
          sides=14, key='dark')
    ring(f'{name}_rim', x, y, z + 0.42, r * 1.02, 0.05, key='limestone',
         sides=14, tube_sides=6)
    for sign in (-1, 1):
        cyl(f'{name}_post{sign}', x + sign * (r - 0.02), y, z + 0.45, 0.045,
            0.62, sides=10, key='oak')
    cyl(f'{name}_beam', x, y, z + 1.06, 0.05, r * 2.4, sides=10, axis='x',
        key='oak')
    cyl(f'{name}_roller', x, y, z + 0.88, 0.055, r * 1.9, sides=12, axis='x',
        key='oak_light')
    for k in range(3):
        ring(f'{name}_turn{k}', x - r * 0.5 + k * r * 0.5, y, z + 0.88, 0.06,
             0.014, key='straw', axis='x', sides=10, tube_sides=5)
    tube(f'{name}_rope', [(x, y, z + 0.86), (x, y, z + 0.62)], r=0.016,
         key='straw')
    lathe(f'{name}_bucket', x, y, z + 0.46, [(0.075, 0.0), (0.088, 0.16)],
          sides=10, key='oak')
    ring(f'{name}_bhoop', x, y, z + 0.56, 0.088, 0.014, key='iron', sides=10,
         tube_sides=5)


def moss(name, x, y, z, sx, sy, h, ridge=0.45, overhang=0.3, patches=14,
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


def tufts(name, x, y, sx, sy, key='leaf', pitch=0.3024):
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
                orb(f'{name}_{axis}_{i}_{sign}', bx, by, 0,
                    0.15, 0.15, 0.13, key=key, subdiv=0, wobble=0.3,
                    seed=i * 3 + axis)
                orb(f'{name}_b{axis}_{i}_{sign}', bx, by, 0.08,
                    0.09, 0.09, 0.09, key=key, subdiv=0, wobble=0.34,
                    seed=i * 5 + sign)


def dovecote(name, x, y, z, w, h, holes=3):
    """A small tower with its own roof and a wall of nest holes.

    Asymmetry that earns its keep. A tower on ONE corner does three things at
    once: it breaks the silhouette, it gives the roofline a second height to
    read against, and on a breeding building it says what happens inside
    without a single word. Symmetry is what made the hut look correct and
    lifeless; one thing that only exists on one side fixes it.
    """
    ashlar_courses(f'{name}_base', x, y, z, w + 0.1, w + 0.1, 0.16,
                   course=0.0821, block=0.149)
    box(f'{name}_shaft', x, y, z + 0.16, w, w, h, mat('stucco'))
    box(f'{name}_band', x, y, z + 0.16 + h * 0.5, w + 0.05, w + 0.05, 0.06,
        mat('limestone'))
    # The holes face the two walls a player can see, and nothing is spent on
    # the two they cannot.
    for i in range(holes):
        hz = z + 0.24 + h * (0.24 + 0.26 * i)
        arch(f'{name}_hole_a{i}', x, y - w / 2 + 0.03, hz, 0.1, 0.13, 0.1)
        arch(f'{name}_hole_b{i}', x + w / 2 - 0.03, y, hz, 0.1, 0.13, 0.1,
             facing='x')
        box(f'{name}_ledge_a{i}', x, y - w / 2 - 0.02, hz - 0.045,
            0.2, 0.08, 0.035, mat('limestone'))
        box(f'{name}_ledge_b{i}', x + w / 2 + 0.02, y, hz - 0.045,
            0.08, 0.2, 0.035, mat('limestone'))
    top = z + 0.16 + h
    box(f'{name}_cornice', x, y, top - 0.05, w + 0.16, w + 0.16, 0.06,
        mat('limestone'))
    # A Roman hip in pantiles became a shingled cone with a finial: the
    # dovecote is the only part of the Storehouse that rises above the ridge,
    # so it is the one silhouette that had to stop being Roman.
    spire(f'{name}_roof', x, y, top, w * 0.72, w * 0.62, sides=10, rings=7)
    finial(f'{name}_fin', x, y, top + w * 0.62, 0.16, key='iron')


def lean_to(name, x, y, z, sx, sy, h, drop=0.28, key='tile', courses=3):
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


def column(name, x, y, z, r, h, key='limestone', sides=20):
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
        mat('limestone_shade'))
    box(f'{name}_neck', x, y, z + h - 0.17, r * 2.1, r * 2.1, 0.04,
        mat('limestone_shade'))
    box(f'{name}_cap', x, y, z + h - 0.13, r * 2.7, r * 2.7, 0.075, mat(key))
    box(f'{name}_abacus', x, y, z + h - 0.055, r * 2.95, r * 2.95, 0.055,
        mat(key))
    return ob


def pot(name, x, y, z, r=0.16, h=0.42, key='tile'):
    """An amphora, turned. Clutter with a job: it is the only thing in the kit
    that says PEOPLE work here, and four stacked blocks said POTTERY-SHAPED."""
    lathe(f'{name}_p', x, y, z, [
        (r * 0.42, 0.0), (r * 0.7, h * 0.08), (r * 1.0, h * 0.34),
        (r * 0.92, h * 0.55), (r * 0.55, h * 0.78), (r * 0.5, h * 0.9),
        (r * 0.66, h),
    ], sides=14, key=key)
    ring(f'{name}_rim', x, y, z + h, r * 0.62, 0.022, key='tile_dark',
         sides=14, tube_sides=6)


def brazier(name, x, y, z, h=0.62, key='iron'):
    """A fire basket on a turned stem, with the flame in it.

    The flame is three overlapping spheres rather than one flat plate: it is
    the only light source most yards have, and a plate reads as a painted
    orange square the moment anything else in the picture is round.
    """
    lathe(f'{name}_foot', x, y, z, [(0.11, 0.0), (0.09, 0.04),
                                    (0.045, 0.07)], sides=10,
          key='limestone')
    cyl(f'{name}_stem', x, y, z + 0.05, 0.032, h, sides=10, key='limestone')
    lathe(f'{name}_bowl', x, y, z + h - 0.02, [(0.055, 0.0), (0.1, 0.05),
                                               (0.13, 0.11)], sides=12,
          key=key)
    ring(f'{name}_rim', x, y, z + h + 0.09, 0.126, 0.016, key=key, sides=12,
         tube_sides=5)
    for i, (ox, oy, sz_) in enumerate(((0.0, 0.0, 0.15), (0.045, 0.03, 0.1),
                                       (-0.04, -0.02, 0.09))):
        orb(f'{name}_fire{i}', x + ox, y + oy, z + h + 0.05, 0.13 - i * 0.03,
            0.12 - i * 0.03, sz_, key='gold' if i % 2 else 'banner',
            wobble=0.3, seed=i + 2)


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
    """A ring of coiled straw with a bed in it. The coil is a torus, because
    that is what somebody twisting straw into a circle makes."""
    ring(f'{name}_r', x, y, z + 0.05, r, 0.06, key=key, sides=12,
         tube_sides=6)
    ring(f'{name}_r2', x, y, z + 0.11, r * 0.94, 0.05, key='root', sides=12,
         tube_sides=6)
    lathe(f'{name}_bed', x, y, z, [(r * 0.95, 0.0), (r * 0.9, 0.05)],
          sides=12, key=key)


def plant(name, x, y, z, r=0.13, key='leaf'):
    """A pot with something growing out of it. Two turned rings and two
    lumpy spheres, where it used to be four stacked slabs."""
    lathe(f'{name}_pot', x, y, z, [(r * 0.62, 0.0), (r * 0.95, 0.06),
                                   (r * 1.0, 0.15), (r * 0.86, 0.2)],
          sides=12, key='tile')
    ring(f'{name}_rim', x, y, z + 0.2, r * 0.88, 0.026, key='tile_dark',
         sides=12, tube_sides=6)
    orb(f'{name}_bush', x, y, z + 0.16, r * 2.3, r * 2.2, r * 1.9, key=key,
        wobble=0.3, seed=3)
    orb(f'{name}_top', x + r * 0.3, y - r * 0.2, z + 0.34, r * 1.4, r * 1.3,
        r * 1.2, key='moss' if key == 'leaf' else key, wobble=0.34, seed=8)


def trough(name, x, y, z, sx, sy, key='ashlar'):
    """A stone water trough. Livestock needs drinking, and a building that
    shows the chore reads as used rather than as displayed."""
    box(f'{name}_body', x, y, z, sx, sy, 0.22, mat(key))
    box(f'{name}_water', x, y, z + 0.18, sx - 0.12, sy - 0.12, 0.05,
        mat('iron'))
    for sign in (-1, 1):
        box(f'{name}_end_{sign}', x + sign * sx / 2, y, z,
            0.07, sy + 0.04, 0.28, mat('limestone'))


def window(name, x, y, z, w, h, depth, shutters=True, facing='y'):
    """An arched window: dark opening, limestone surround, oak shutters.

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
         key='limestone', facing=facing)
    hx, hy = at(0.0)
    arch(f'{name}_hole', hx, hy, z, w, h, depth, facing=facing)
    lx, ly = at(0.02)
    wall_box(f'{name}_sill', lx, ly, z - 0.09, w + 0.26, 0.18, 0.09,
             mat('limestone'), facing=facing)
    if shutters:
        for sign in (-1, 1):
            bx, by = at(-0.04, sign * (w / 2 + 0.11))
            wall_box(f'{name}_shutter_{sign}', bx, by, z + 0.04,
                     0.14, 0.07, h * 0.74, mat('oak'), facing=facing)


def steps(name, x, y, z, w, count=4, rise=0.075, tread=0.16, key='limestone'):
    """A flight up to a threshold. Three steps say "there is a way in" louder
    than any door does, because a door is a shape and a step is an invitation."""
    for i in range(count):
        box(f'{name}_{i}', x, y - i * tread, z + (count - 1 - i) * rise,
            w - i * 0.1, tread + 0.02, rise + (count - 1 - i) * rise,
            mat(key))


def cross_flag(name, x, y, z, w=0.34, h=0.5, facing='y',
               ground='linen', charge='banner'):
    """A flag with a cross on it — white field, red cross.

    The one piece of heraldry in the kit, and it exists for one building: an
    infirmary is recognised by its FLAG and by nothing else, at any size, in
    any century. Three boxes for the charge, because the arms have to reach
    the edges or it reads as a dot.
    """
    box(f'{name}_pole', x, y, z, 0.05, 0.05, h * 1.5, mat('oak'))
    box(f'{name}_fin', x, y, z + h * 1.5, 0.08, 0.08, 0.09, mat('gold'))
    bw, bd = ((w, 0.035) if facing == 'y' else (0.035, w))
    ox, oy = ((w / 2 + 0.03, 0.0) if facing == 'y' else (0.0, w / 2 + 0.03))
    fz = z + h * 1.5 - h - 0.06
    box(f'{name}_field', x + ox, y + oy, fz, bw, bd, h, mat(ground))
    # The cross: an upright and a bar, both reaching the edges.
    box(f'{name}_up', x + ox, y + oy - (0.012 if facing == 'y' else 0),
        z + h * 1.5 - h - 0.05,
        (w * 0.26 if facing == 'y' else 0.03),
        (0.03 if facing == 'y' else w * 0.26), h * 0.98, mat(charge))
    box(f'{name}_bar', x + ox, y + oy - (0.012 if facing == 'y' else 0),
        fz + h * 0.44,
        (w * 0.96 if facing == 'y' else 0.03),
        (0.03 if facing == 'y' else w * 0.96), h * 0.26, mat(charge))
    for i in range(3):
        box(f'{name}_tie{i}', x, y, fz + h * (0.15 + 0.35 * i), 0.07, 0.07,
            0.05, mat('iron'))


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


# ── The medieval-fantasy ornament kit (user 2026-08-09) ────
# "ich möchte, dass es mittelalterliche fantasy gebäude sind, welche zusätzlich
#  stärker verziert sein sollen (mehr Details)"
#
# The roster came out half Roman: shallow hipped roofs, colonnades, pediments,
# friezes. Those are the wrong century AND the wrong amount — a Roman building
# is severe by design, and severe is the opposite of what was asked for.
#
# Everything below is the vocabulary that was missing. The rule they all follow:
# ORNAMENT ON THE SKYLINE FIRST. At map size a building is read by its outline,
# so a spire, a crest and a vane are worth more than any amount of carving on a
# wall — and they cost three boxes each.


def spire(name, x, y, z, r, h, sides=16, key='shingle',
          dark='shingle_dark', rings=18):
    """A tall pointed roof: rings of an n-gon shrinking to a point.

    THE fantasy silhouette. A steep cone over a tower is the single shape that
    separates this world from a Roman one, and stacked rings give it the
    coursing a plain cone has no room for.
    """
    for i in range(rings):
        f0 = 1.0 - i / rings
        rz = z + h * i / rings
        rh = h / rings * 1.12
        verts, faces = [], []
        rr = r * f0
        for k in range(sides):
            a = 2 * math.pi * k / sides
            verts.append((rr * math.cos(a), rr * math.sin(a), 0))
        for k in range(sides):
            a = 2 * math.pi * k / sides
            r1 = r * (1.0 - (i + 1) / rings)
            verts.append((r1 * math.cos(a), r1 * math.sin(a), rh))
        for k in range(sides):
            n = (k + 1) % sides
            faces.append((k, n, sides + n, sides + k))
        faces.append(tuple(range(sides)))
        faces.append(tuple(range(2 * sides - 1, sides - 1, -1)))
        mesh = bpy.data.meshes.new(f'{name}_{i}')
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        ob = bpy.data.objects.new(f'{name}_{i}', mesh)
        bpy.context.collection.objects.link(ob)
        ob.location = (x, y, rz)
        ob.data.materials.append(mat(key if i % 2 else dark))
        for p in ob.data.polygons:
            p.use_smooth = False


def finial(name, x, y, z, h=0.34, key='gold'):
    """A knop and a spike on top of something. Two boxes, and a roof stops
    ending and starts finishing."""
    box(f'{name}_knop', x, y, z, h * 0.42, h * 0.42, h * 0.34, mat(key))
    box(f'{name}_spike', x, y, z + h * 0.34, h * 0.16, h * 0.16, h * 0.8,
        mat(key))


def weathervane(name, x, y, z, h=0.5, key='iron'):
    """A rod, a cross of arms and a pennant that points somewhere.

    The one piece of ornament that reads as a DIRECTION rather than as a shape,
    which is why a skyline full of them looks inhabited.
    """
    box(f'{name}_rod', x, y, z, 0.05, 0.05, h, mat(key))
    box(f'{name}_ax', x, y, z + h * 0.62, 0.34, 0.04, 0.04, mat(key))
    box(f'{name}_ay', x, y, z + h * 0.62, 0.04, 0.34, 0.04, mat(key))
    van = box(f'{name}_vane', x + 0.13, y, z + h, 0.26, 0.03, 0.16,
              mat('banner'))
    van.rotation_euler = (0, 0, 0.18)
    box(f'{name}_tip', x, y, z + h + 0.16, 0.08, 0.08, 0.1, mat('gold'))


def ridge_crest(name, x, y, z, span, axis='x', key='iron', pitch=0.1224):
    """A run of crest tiles along a ridge — the spiky comb every fairy-tale
    roof has. Alternating tall and short, so it reads as a rhythm rather than
    as a fence."""
    n = max(2, int(span / pitch))
    for i in range(n):
        t = -span / 2 + span * (i + 0.5) / n
        tall = 0.2 if i % 2 else 0.13
        bx, by = (x + t, y) if axis == 'x' else (x, y + t)
        ob = box(f'{name}_{i}', bx, by, z, 0.05, 0.05, tall, mat(key))
        ob.rotation_euler = (0, 0, math.pi / 4)


def dagged(name, x, y, z, span, axis='x', key='oak_light', teeth=None,
           drop=0.13):
    """A bargeboard cut into points — the scalloped verge under a gable.

    Cheap and unmistakably of the period: a straight eave says shed, a toothed
    one says somebody carved it.
    """
    teeth = teeth or max(4, int(span / 0.15))
    for i in range(teeth):
        t = -span / 2 + span * (i + 0.5) / teeth
        bx, by = (x + t, y) if axis == 'x' else (x, y + t)
        w = span / teeth * 0.72
        box(f'{name}_{i}', bx, by, z - drop, w, 0.07, drop, mat(key))
        box(f'{name}p_{i}', bx, by, z - drop - 0.07, w * 0.42, 0.07, 0.08,
            mat(key))


def corbel_head(name, x, y, z, facing='y', key='limestone'):
    """A carved head on a corbel. Three boxes and a face's worth of shadow —
    the medieval habit of putting somebody's likeness where a bracket goes."""
    into = -0.09 if facing == 'y' else 0.09
    hx, hy = (x, y + into) if facing == 'y' else (x - into, y)
    box(f'{name}_c', hx, hy, z, 0.16, 0.16, 0.1, mat(key))
    box(f'{name}_h', hx, hy, z + 0.1, 0.2, 0.2, 0.2, mat(key))
    box(f'{name}_j', hx, hy, z + 0.1, 0.13, 0.13, 0.08, mat('dark'))


def hanging_sign(name, x, y, z, w=0.42, facing='y', key='oak',
                 board='banner'):
    """A bracket off a wall with a board swinging from it.

    What a shop IS at this size. A door tells you a building can be entered; a
    sign tells you what for, and it is the only label the map has room for.
    """
    reach = 0.42
    ox = -reach if facing == 'x' else 0.0
    oy = -reach if facing == 'y' else 0.0
    box(f'{name}_arm', x + ox / 2, y + oy / 2, z,
        abs(ox) + 0.06 if ox else 0.06, abs(oy) + 0.06 if oy else 0.06, 0.06,
        mat('iron'))
    br = box(f'{name}_br', x + ox / 3, y + oy / 3, z - 0.16, 0.06, 0.06, 0.24,
             mat('iron'))
    br.rotation_euler = (0.6 if oy else 0, -0.6 if ox else 0, 0)
    box(f'{name}_ch', x + ox, y + oy, z - 0.1, 0.03, 0.03, 0.1, mat('iron'))
    bw, bd = (w, 0.06) if facing == 'y' else (0.06, w)
    box(f'{name}_bd', x + ox, y + oy, z - 0.44, bw, bd, 0.34, mat(board))
    box(f'{name}_rim', x + ox, y + oy, z - 0.46, bw + 0.05, bd + 0.05, 0.05,
        mat(key))


def gothic_arch(name, x, y, z, w, h, depth, key='dark', facing='y',
                segments=5):
    """A POINTED opening. The same silhouette job [arch] does, in the other
    century — two arcs meeting at a point instead of one semicircle."""
    r = w / 2
    straight = max(0.0, h - r * 1.35)
    pts = [(-r, 0.0), (-r, straight)]
    for i in range(1, segments + 1):
        f = i / segments
        # Two struck arcs: the left side swings from the RIGHT springing point.
        a = math.pi * (0.5 - 0.28 * f)
        pts.append((-r + w * 0.5 * (1 - math.cos(math.pi * 0.34 * f)) * 0.9,
                    straight + (h - straight) * math.sin(math.pi * 0.5 * f)))
        _ = a
    pts.append((0.0, h))
    pts += [(-px, py) for px, py in reversed(pts[:-1])]
    verts, faces = [], []
    for px, pz in pts:
        verts.append((px, -depth / 2, pz))
        verts.append((px, depth / 2, pz))
    n = len(pts)
    for i in range(n - 1):
        faces.append((2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2))
    faces.append(tuple(range(0, 2 * n, 2)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    if facing == 'x':
        ob.rotation_euler = (0, 0, math.radians(90))
    ob.data.materials.append(mat(key))
    for p in ob.data.polygons:
        p.use_smooth = False


def gothic_door(name, x, y, z, w, h, facing='y', rim=0.2):
    """A pointed doorway with its own surround — [doorway] for this century."""
    into = 1.0 if facing == 'y' else -1.0
    sx = x + (0 if facing == 'y' else into * 0.13)
    sy = y + (into * 0.13 if facing == 'y' else 0)
    gothic_arch(f'{name}_sur', sx, sy, z, w + rim, h + rim / 2, 0.22,
                key='limestone', facing=facing)
    gothic_arch(f'{name}_mouth', x, y, z, w, h, 0.22, facing=facing)


def oriel(name, x, y, z, w, h, facing='y', key='oak'):
    """A bay window jettied out on corbels, with its own little roof.

    The most decorative thing a medieval wall can do, and it breaks the wall
    line — which at map size matters more than the window itself.
    """
    into = -1.0 if facing == 'y' else 1.0
    d = 0.3
    ox, oy = (0, into * d / 2) if facing == 'y' else (-into * d / 2, 0)
    for s in (-1, 1):
        cx = x + (s * w / 3 if facing == 'y' else ox * 1.2)
        cy = y + (oy * 1.2 if facing == 'y' else s * w / 3)
        cb = box(f'{name}_cor{s}', cx, cy, z - 0.02, 0.12, 0.12, 0.2,
                 mat('limestone'))
        cb.rotation_euler = (0, 0, math.pi / 4)
    bw, bd = (w, d) if facing == 'y' else (d, w)
    box(f'{name}_body', x + ox, y + oy, z + 0.16, bw, bd, h, mat(key))
    leaded_window(f'{name}_win',
                  x + ox + (0 if facing == 'y' else -d / 2),
                  y + oy + (-d / 2 if facing == 'y' else 0),
                  z + 0.28, w * 0.62, h * 0.6, facing=facing, shutters=False)
    for k in range(3):
        f = 1.0 - k * 0.3
        box(f'{name}_roof{k}', x + ox, y + oy, z + 0.16 + h + k * 0.07,
            bw * f + 0.14, bd * f + 0.14, 0.08,
            mat('shingle' if k % 2 else 'shingle_dark'))


def turret(name, x, y, z, r, h, key='ashlar', spire_h=0.9, crown=True):
    """A round-ish tower with a spire on it. Three shapes, and any wall it is
    stuck to stops being a wall and becomes a castle."""
    stalk_sides = 8
    for i in range(max(3, int(h / 0.2))):
        ch = h / max(3, int(h / 0.2))
        box(f'{name}_c{i}', x, y, z + i * ch, r * 2, r * 2, ch * 0.94,
            mat(key if i % 2 else 'ashlar_dark'))
    _ = stalk_sides
    if crown:
        box(f'{name}_cor', x, y, z + h, r * 2 + 0.16, r * 2 + 0.16, 0.1,
            mat('limestone'))
        spire(f'{name}_sp', x, y, z + h + 0.1, r * 1.28, spire_h)
        finial(f'{name}_fin', x, y, z + h + 0.1 + spire_h, 0.3)
    else:
        spire(f'{name}_sp', x, y, z + h, r * 1.2, spire_h)


def carved_post(name, x, y, z, h, key='oak', head='oak_light'):
    """A turned post with a collar and a cap. A post is a tree with the bark
    off; it was a square prism, and every yard on the map has four."""
    cyl(f'{name}_p', x, y, z, 0.062, h, sides=12, taper=0.9, key=key)
    ring(f'{name}_col', x, y, z + h * 0.62, 0.072, 0.026, key=head, sides=12,
         tube_sides=6)
    lathe(f'{name}_cap', x, y, z + h - 0.02, [(0.075, 0.0), (0.11, 0.05),
                                              (0.085, 0.1)], sides=12,
          key=head)
    for s in (-1, 1):
        br = cyl(f'{name}_br{s}', x + s * 0.11, y, z + h - 0.3, 0.035, 0.36,
                 sides=8, key=key)
        br.rotation_euler = (0, -s * 0.72, 0)


def rose_window(name, x, y, z, r, facing='y', key='limestone'):
    """A wheel of tracery. One round window is worth a whole wall of square
    ones, and it is the fastest way to say "this building matters"."""
    d = 0.1
    bw, bd = (r * 2.3, d) if facing == 'y' else (d, r * 2.3)
    box(f'{name}_ring', x, y, z, bw, bd, r * 2.3, mat(key))
    bw2, bd2 = (r * 2, d * 1.4) if facing == 'y' else (d * 1.4, r * 2)
    box(f'{name}_dark', x, y, z + r * 0.15, bw2, bd2, r * 2, mat('dark'))
    for i in range(6):
        a = math.pi * i / 6
        sp = box(f'{name}_sp{i}', x, y, z + r * 1.15,
                 (r * 1.9 if facing == 'y' else d * 1.6),
                 (d * 1.6 if facing == 'y' else r * 1.9), 0.07, mat(key))
        sp.rotation_euler = ((0, a, 0) if facing == 'y' else (a, 0, 0))
    box(f'{name}_hub', x, y, z + r * 1.05, r * 0.5, r * 0.5, r * 0.5,
        mat('gold'))


# ── Props: the things that NAME a building ─────────────────
# At map size a roof is a roof. What tells you which building you are looking
# at is the stuff in its yard — the boat, the camels, the gold, the cart. So
# these are sized to READ: nothing here is smaller than a third of a cell, and
# each one is a silhouette before it is an object.


def water_patch(name, x, y, sx, sy, z=0.0):
    """A sunken pool with a wet rim and a ripple or two.

    The Fish Hut asked for it by name, and it is the one prop that cannot be
    faked with a colour: water is a HOLE in the ground, so the rim steps down
    into it and the surface sits below the plinth it is cut into.
    """
    box(f'{name}_pit', x, y, z - 0.16, sx + 0.24, sy + 0.24, 0.16,
        mat('shore') if 'shore' in PALETTE else mat('sand'))
    box(f'{name}_w', x, y, z - 0.12, sx, sy, 0.12, mat('water'))
    box(f'{name}_d', x, y, z - 0.1, sx * 0.6, sy * 0.6, 0.1, mat('water_deep'))
    for i in range(3):
        j = _hash01(f'{name}rip{i}')
        box(f'{name}_rip{i}', x + (j - 0.5) * sx * 0.6,
            y + (_hash01(f"{name}q{i}") - 0.5) * sy * 0.6, z - 0.005,
            sx * (0.2 + 0.2 * j), 0.05, 0.02, mat('foam'))


def pier(name, x, y, z, span, axis='x', key='oak'):
    """Planks on posts, reaching out over water."""
    n = max(3, int(span / 0.34))
    for i in range(n):
        t = -span / 2 + span * (i + 0.5) / n
        bx, by = (x + t, y) if axis == 'x' else (x, y + t)
        box(f'{name}_pl{i}', bx, by, z, span / n * 0.86 if axis == 'x' else 0.5,
            0.5 if axis == 'x' else span / n * 0.86, 0.07, mat('oak_light'))
    for s in (-1, 1):
        for i in range(2):
            t = -span / 2 + span * (0.25 + 0.5 * i)
            bx, by = ((x + t, y + s * 0.2) if axis == 'x'
                      else (x + s * 0.2, y + t))
            box(f'{name}_po{s}{i}', bx, by, z - 0.34, 0.09, 0.09, 0.4,
                mat(key))


def cart(name, x, y, z, angle=0.0, load='sack', key='oak'):
    """A two-wheeled cart, loaded.

    The most useful prop in the kit: a camp that HAS a cart is a camp that
    ships something. Wheels are octagons, which at this size is a circle and
    at four boxes is not.
    """
    bed = box(f'{name}_bed', x, y, z + 0.26, 0.95, 0.6, 0.16, mat(key))
    bed.rotation_euler = (0, 0, angle)
    for s in (-1, 1):
        box(f'{name}_side{s}', x, y, z + 0.34, 0.95, 0.06, 0.22,
            mat('oak_light')).rotation_euler = (0, 0, angle)
    for s in (-1, 1):
        wx = x - math.sin(angle) * s * 0.34
        wy = y + math.cos(angle) * s * 0.34
        for k in range(4):
            sp = box(f'{name}_sp{s}{k}', wx, wy, z + 0.26, 0.5, 0.07, 0.07,
                     mat('oak_light'))
            sp.rotation_euler = (math.pi / 4 * k, 0, angle)
        box(f'{name}_hub{s}', wx, wy, z + 0.26, 0.14, 0.14, 0.14, mat('iron'))
    sh = box(f'{name}_shaft', x + math.cos(angle) * 0.58,
             y + math.sin(angle) * 0.58, z + 0.22, 0.5, 0.3, 0.07,
             mat(key))
    sh.rotation_euler = (0, 0.3, angle)
    if load == 'sack':
        for i in range(3):
            box(f'{name}_ld{i}', x - 0.24 + i * 0.24, y, z + 0.42,
                0.3, 0.34, 0.26, mat('cloth' if i % 2 else 'straw'))
    elif load == 'stone':
        for i in range(3):
            box(f'{name}_ld{i}', x - 0.22 + i * 0.22, y, z + 0.42,
                0.26, 0.34, 0.2,
                mat('limestone' if i % 2 else 'limestone_shade'))
    elif load == 'log':
        for i in range(3):
            box(f'{name}_ld{i}', x, y - 0.14 + i * 0.14, z + 0.44 + i * 0.02,
                0.9, 0.2, 0.2, mat('oak' if i % 2 else 'oak_light'))
    elif load == 'barrel':
        for i in range(2):
            barrel(f'{name}_ld{i}', x - 0.18 + i * 0.36, y, z + 0.42, r=0.17,
                   h=0.34)


def pack_beast(name, x, y, z, angle=0.0, hump=True, key='hide'):
    """A camel, or a mule when the hump is off.

    Six boxes and a neck. It does not need to be a good animal — it needs to be
    unmistakably an ANIMAL at forty pixels, which is a body on four legs with a
    neck going up at one end.
    """
    # ── Rounded (user 2026-08-12: "Kamele mehr Rundungen") ──
    # A camel made of cuboids is a crate on legs. The barrel of the body and
    # the hump are the two shapes anyone actually draws, and both are orbs.
    body = orb(f'{name}_b', x, y, z + 0.26, 0.92, 0.46, 0.44, key=key,
               subdiv=1, wobble=0.1, seed=3)
    body.rotation_euler = (0, 0, angle)
    if hump:
        orb(f'{name}_h', x - math.cos(angle) * 0.06, y - math.sin(angle) * 0.06,
            z + 0.62, 0.5, 0.42, 0.34, key=key, subdiv=1, wobble=0.14, seed=7)
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            lx = x + math.cos(angle) * sx_ * 0.3 - math.sin(angle) * sy_ * 0.14
            ly = y + math.sin(angle) * sx_ * 0.3 + math.cos(angle) * sy_ * 0.14
            cyl(f'{name}_l{sx_}{sy_}', lx, ly, z, 0.045, 0.44, sides=8,
                taper=0.8, key='hide_dark')
            orb(f'{name}_k{sx_}{sy_}', lx, ly, z + 0.2, 0.11, 0.11, 0.11,
                key='hide_dark', subdiv=0)
    nx = x + math.cos(angle) * 0.44
    ny = y + math.sin(angle) * 0.44
    neck = cyl(f'{name}_n', nx, ny, z + 0.5, 0.08, 0.44, sides=10,
               taper=0.78, key=key)
    neck.rotation_euler = (0, -0.3, angle)
    hx = nx + math.cos(angle) * 0.12
    hy = ny + math.sin(angle) * 0.12
    orb(f'{name}_hd', hx, hy, z + 0.86, 0.3, 0.19, 0.19, key=key, subdiv=1,
        wobble=0.12, seed=11)
    orb(f'{name}_mz', hx + math.cos(angle) * 0.12, hy + math.sin(angle) * 0.12,
        z + 0.84, 0.16, 0.13, 0.13, key='hide_dark', subdiv=0)
    for e_ in (-1, 1):
        orb(f'{name}_e{e_}', hx - math.sin(angle) * e_ * 0.06,
            hy + math.cos(angle) * e_ * 0.06, z + 1.02, 0.07, 0.07, 0.09,
            key='hide_dark', subdiv=0)
    tail = box(f'{name}_t', x - math.cos(angle) * 0.46,
               y - math.sin(angle) * 0.46, z + 0.5, 0.06, 0.06, 0.28,
               mat('hide_dark'))
    tail.rotation_euler = (0, 0.4, angle)


def gold_pile(name, x, y, z, r=0.42, bars=True):
    """A heap of coin. The heap is turned and the loose coins are DISCS —
    which is the only shape a coin has ever been, and the reason a square one
    reads as a tile."""
    lathe(f'{name}_h', x, y, z, [(r * 1.0, 0.0), (r * 0.86, r * 0.24),
                                 (r * 0.6, r * 0.46), (r * 0.24, r * 0.6)],
          sides=14, key='gold')
    for i in range(7):
        j = _hash01(f'{name}c{i}')
        ob = cyl(f'{name}_c{i}', x + (j - 0.5) * r * 2.4,
                 y + (_hash01(f'{name}d{i}') - 0.5) * r * 2.0, z,
                 0.075, 0.022, sides=12, key='gold')
        ob.rotation_euler = (0.14 * (j - 0.5), 0, j * 3.0)
    if bars:
        for k in range(4):
            box(f'{name}_b{k}', x + r * 1.45 + (k % 2) * 0.06,
                y - 0.12 + (k % 2) * 0.06, z + (k // 2) * 0.12,
                0.36, 0.18, 0.12, mat('gold'))


def barrel(name, x, y, z, r=0.19, h=0.4, key='oak'):
    """A cask: a bellied body, two real hoops, a lid.

    ── Turned, not stacked (user 2026-08-12) ──
    A cask was a cube with two flat plates round it. Every building on the map
    has two or three, so this one function is worth more than any single
    building's rebuild: a barrel is the most recognisably ROUND object in the
    whole set, and a square one is the loudest tell there is.
    """
    lathe(f'{name}_b', x, y, z, [
        (r * 0.82, 0.0), (r * 0.97, h * 0.18), (r * 1.0, h * 0.5),
        (r * 0.97, h * 0.82), (r * 0.82, h),
    ], sides=16, key=key)
    for f in (0.2, 0.74):
        ring(f'{name}_hp{f}', x, y, z + h * f, r * 0.99, 0.022, key='iron',
             sides=16, tube_sides=6)
    lathe(f'{name}_lid', x, y, z + h - 0.01, [(r * 0.84, 0.0),
                                              (r * 0.8, 0.045)],
          sides=16, key='oak_light')


def crate(name, x, y, z, s=0.34, key='oak_light'):
    """A box with battens — the difference between a crate and a cube."""
    box(f'{name}_b', x, y, z, s, s * 0.86, s * 0.8, mat(key))
    for t in (-0.3, 0.3):
        box(f'{name}_bt{t}', x + s * t, y, z, s * 0.14, s * 0.9, s * 0.82,
            mat('oak'))
    box(f'{name}_lid', x, y, z + s * 0.8, s * 1.06, s * 0.92, 0.05, mat('oak'))


def sack_pile(name, x, y, z, n=3, key='cloth'):
    """Sacks, leaning on each other."""
    for i in range(n):
        j = _hash01(f'{name}s{i}')
        ob = box(f'{name}_{i}', x + (j - 0.5) * 0.4, y + (i % 2) * 0.16,
                 z, 0.3 + 0.1 * j, 0.26 + 0.08 * j, 0.34 + 0.1 * j,
                 mat(key if i % 2 else 'straw'))
        ob.rotation_euler = (0, 0, j * 1.2)
        box(f'{name}_n{i}', x + (j - 0.5) * 0.4, y + (i % 2) * 0.16,
            z + 0.34 + 0.1 * j, 0.12, 0.12, 0.08, mat('oak'))


def awning(name, x, y, z, w, d, facing='y', key='cloth',
           stripe='cloth_stripe'):
    """A striped cloth on two poles. THE market signal — nothing else on the
    map is striped, so a stall is legible from any distance."""
    n = max(3, int(w / 0.22))
    for i in range(n):
        t = -w / 2 + w * (i + 0.5) / n
        bx, by = (x + t, y) if facing == 'y' else (x, y + t)
        sw, sd = (w / n * 0.98, d) if facing == 'y' else (d, w / n * 0.98)
        pan = box(f'{name}_{i}', bx, by, z, sw, sd, 0.06,
                  mat(key if i % 2 else stripe))
        pan.rotation_euler = ((0.34, 0, 0) if facing == 'y' else (0, -0.34, 0))
    for s in (-1, 1):
        px, py = ((x + s * w / 2, y - d / 2) if facing == 'y'
                  else (x - d / 2, y + s * w / 2))
        box(f'{name}_p{s}', px, py, z - 0.9, 0.08, 0.08, 0.94, mat('oak'))


def cauldron(name, x, y, z, r=0.26, key='iron'):
    """A pot over a fire, with steam. Says apothecary, kitchen or alchemy
    depending on what is standing next to it — and it is a hemisphere, which
    a cube has never once been mistaken for."""
    lathe(f'{name}_b', x, y, z + 0.12, [
        (r * 0.34, 0.0), (r * 0.78, r * 0.3), (r * 1.0, r * 0.75),
        (r * 0.98, r * 1.15),
    ], sides=16, key=key)
    ring(f'{name}_rim', x, y, z + 0.12 + r * 1.15, r * 0.99, 0.026,
         key='iron', sides=16, tube_sides=6)
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.5
        leg = cyl(f'{name}_leg{i}', x + r * 0.62 * math.cos(a),
                  y + r * 0.62 * math.sin(a), z, 0.03, 0.16, sides=8,
                  key='iron')
        leg.rotation_euler = (math.cos(a) * 0.2, math.sin(a) * 0.2, 0)
    box(f'{name}_fire', x, y, z, r * 1.5, r * 1.5, 0.09, mat('gold'))
    smoke(f'{name}_st', x, y, z + 0.12 + r * 1.3, h=0.5, puffs=3)


def net_frame(name, x, y, z, w=0.7, h=0.7, facing='y', key='straw'):
    """A net hung to dry on a frame. Hatched, so it reads as mesh."""
    for s in (-1, 1):
        px, py = ((x + s * w / 2, y) if facing == 'y' else (x, y + s * w / 2))
        box(f'{name}_p{s}', px, py, z, 0.07, 0.07, h + 0.1, mat('oak'))
    bw, bd = (w, 0.05) if facing == 'y' else (0.05, w)
    box(f'{name}_top', x, y, z + h, bw, bd, 0.06, mat('oak_light'))
    for i in range(4):
        box(f'{name}_v{i}', x + (-w / 2 + w * (i + 0.5) / 4 if facing == 'y'
                                 else 0),
            y + (0 if facing == 'y' else -w / 2 + w * (i + 0.5) / 4),
            z + h * 0.3, 0.04, 0.04, h * 0.66, mat(key))
    for k in range(3):
        box(f'{name}_h{k}', x, y, z + h * (0.35 + k * 0.2),
            bw * 0.9, bd, 0.04, mat(key))


def tool_rack(name, x, y, z, w=0.8, facing='y'):
    """Tools leaning on a rail. Which tools is the label."""
    bw, bd = (w, 0.06) if facing == 'y' else (0.06, w)
    box(f'{name}_rail', x, y, z + 0.62, bw, bd, 0.07, mat('oak'))
    for s in (-1, 1):
        px, py = ((x + s * w / 2, y) if facing == 'y' else (x, y + s * w / 2))
        box(f'{name}_p{s}', px, py, z, 0.07, 0.07, 0.68, mat('oak'))
    for i in range(3):
        t = -w / 2 + w * (i + 0.5) / 3
        hx, hy = ((x + t, y - 0.06) if facing == 'y' else (x - 0.06, y + t))
        sh = box(f'{name}_h{i}', hx, hy, z + 0.06, 0.06, 0.06, 0.62,
                 mat('oak_light'))
        sh.rotation_euler = (0.14, 0, 0)
        box(f'{name}_t{i}', hx, hy, z + 0.62, 0.18, 0.1, 0.12, mat('iron'))


def bell(name, x, y, z, r=0.2):
    """A bell on a headstock. Turned, because a cast bell has a profile and
    three stacked boxes have a staircase."""
    for s_ in (-1, 1):
        cyl(f'{name}_p{s_}', x + s_ * r * 1.4, y, z, 0.045, r * 2.4, sides=10,
            key='oak')
    cyl(f'{name}_beam', x, y, z + r * 2.4, 0.05, r * 3.2, sides=10, axis='x',
        key='oak_light')
    lathe(f'{name}_b', x, y, z + r * 2.4 - r * 1.45, [
        (r * 0.2, 0.0), (r * 0.34, r * 0.1), (r * 0.3, r * 0.24),
        (r * 0.52, r * 0.5), (r * 0.8, r * 1.05), (r * 1.0, r * 1.3),
        (r * 1.02, r * 1.42), (r * 0.9, r * 1.45),
    ], sides=16, key='gold', smooth=True)
    orb(f'{name}_cl', x, y, z + r * 1.0, 0.075, 0.075, 0.1, key='iron',
        smooth=True)


def smoke(name, x, y, z, h=1.1, puffs=5, key='smoke'):
    """Smoke: spheres that grow and drift. A puff was a rotated box, which is
    the one thing smoke has never been."""
    for i in range(puffs):
        t = i / max(1, puffs - 1)
        # Half the old radius. At 0.15 growing to 0.37 the puffs came out
        # as three white balls the size of a barrel — a chimney makes wisps,
        # and the give-away is the SPREAD, not the volume.
        r = 0.075 + 0.115 * t
        orb(f'{name}_{i}', x + t * t * 0.5 + (_hash01(f'{name}x{i}') - 0.5) * 0.2,
            y + t * 0.26, z + h * t,
            r * 2, r * 1.7, r * 1.5, key=key, wobble=0.3, seed=i + 11,
            smooth=True)


def critter(name, x, y, z, angle=0.0, kind=0, scale=1.0):
    """A small beast, about knee high on whatever built the place.

    Five boxes and a tail. It does not need to be a good animal — it needs to
    be unmistakably ALIVE at forty pixels, which is a body on four legs with a
    head at one end and something sticking up at the other.
    """
    s_ = 0.34 * scale
    tone = ('critter' if kind % 3 else
            'critter_dark' if kind % 2 else 'critter_alt')
    body = box(f'{name}_b', x, y, z + s_ * 0.9, s_ * 1.9, s_ * 0.95, s_ * 0.9,
               mat(tone))
    body.rotation_euler = (0, 0, angle)
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            lx = x + math.cos(angle) * sx_ * s_ * 0.6 \
                - math.sin(angle) * sy_ * s_ * 0.3
            ly = y + math.sin(angle) * sx_ * s_ * 0.6 \
                + math.cos(angle) * sy_ * s_ * 0.3
            box(f'{name}_l{sx_}{sy_}', lx, ly, z, s_ * 0.24, s_ * 0.24,
                s_ * 0.95, mat('critter_dark'))
    hx = x + math.cos(angle) * s_ * 1.05
    hy = y + math.sin(angle) * s_ * 1.05
    box(f'{name}_h', hx, hy, z + s_ * 1.1, s_ * 0.8, s_ * 0.7, s_ * 0.72,
        mat(tone))
    for sy_ in (-1, 1):
        box(f'{name}_e{sy_}', hx, hy + sy_ * s_ * 0.22, z + s_ * 1.8,
            s_ * 0.2, s_ * 0.16, s_ * 0.34,
            mat('critter_dark' if kind % 2 else tone))
    tail = box(f'{name}_t', x - math.cos(angle) * s_ * 1.05,
               y - math.sin(angle) * s_ * 1.05, z + s_ * 1.2,
               s_ * 0.2, s_ * 0.2, s_ * 0.8, mat('critter_dark'))
    tail.rotation_euler = (0, -0.6, angle)


def fowl(name, x, y, z, angle=0.0, kind=0):
    """Something smaller, on two legs, pecking. Reads as poultry."""
    tone = 'linen' if kind % 2 else 'critter'
    box(f'{name}_b', x, y, z + 0.16, 0.24, 0.18, 0.2, mat(tone))
    for s_ in (-1, 1):
        box(f'{name}_l{s_}', x, y + s_ * 0.05, z, 0.05, 0.05, 0.17,
            mat('gold'))
    hx = x + math.cos(angle) * 0.14
    hy = y + math.sin(angle) * 0.14
    box(f'{name}_h', hx, hy, z + 0.3, 0.13, 0.12, 0.14, mat(tone))
    box(f'{name}_bk', hx + math.cos(angle) * 0.09,
        hy + math.sin(angle) * 0.09, z + 0.33, 0.08, 0.05, 0.05, mat('gold'))
    box(f'{name}_c', hx, hy, z + 0.42, 0.09, 0.06, 0.08, mat('banner'))
    t = box(f'{name}_t', x - math.cos(angle) * 0.16,
            y - math.sin(angle) * 0.16, z + 0.24, 0.16, 0.13, 0.14, mat(tone))
    t.rotation_euler = (0, -0.8, angle)


def washing(name, x, y, z, span, axis='x', h=0.9, items=4):
    """A line between two posts with cloth over it.

    Nothing else on the map is pure pale linen, so a washing line is legible
    from any distance — and there is no stronger way to say that somebody lives
    here rather than merely works here.
    """
    for s_ in (-1, 1):
        px, py = ((x + s_ * span / 2, y) if axis == 'x'
                  else (x, y + s_ * span / 2))
        box(f'{name}_p{s_}', px, py, z, 0.07, 0.07, h, mat('oak'))
    lw, ld = (span, 0.04) if axis == 'x' else (0.04, span)
    box(f'{name}_line', x, y, z + h, lw, ld, 0.04, mat('iron'))
    for i in range(items):
        t = -span / 2 + span * (i + 0.7) / (items + 0.4)
        cx, cy = ((x + t, y) if axis == 'x' else (x, y + t))
        j = _hash01(f'{name}{i}')
        cw = span / items * 0.62
        bw, bd = (cw, 0.05) if axis == 'x' else (0.05, cw)
        box(f'{name}_c{i}', cx, cy, z + h - (0.3 + 0.24 * j), bw, bd,
            0.3 + 0.24 * j,
            mat('linen' if i % 2 else ('cloth' if j < 0.6 else 'banner')))


def anvil(name, x, y, z, key='iron'):
    """An anvil on a block. One silhouette, one trade."""
    box(f'{name}_blk', x, y, z, 0.3, 0.3, 0.3, mat('oak'))
    box(f'{name}_a', x, y, z + 0.3, 0.42, 0.2, 0.14, mat(key))
    box(f'{name}_horn', x + 0.26, y, z + 0.34, 0.2, 0.12, 0.09, mat(key))
    box(f'{name}_ham', x - 0.14, y - 0.12, z + 0.44, 0.16, 0.09, 0.09,
        mat(key))
    box(f'{name}_hh', x - 0.02, y - 0.12, z + 0.44, 0.24, 0.05, 0.05,
        mat('oak_light'))


def firewood(name, x, y, z, w=0.9, rows=7, key='oak'):
    """Split logs, stacked. Round, and the END GRAIN is the whole read: a wall
    of circles is unmistakable and a wall of squares is a brick wall."""
    for r in range(rows):
        for c in range(3):
            if _hash01(f'{name}{r}{c}') < 0.1:
                continue
            cyl(f'{name}_{r}{c}', x - w / 2 + w * (c + 0.5) / 3,
                y - 0.21 + (r % 2) * 0.03, z + r * 0.19 + 0.09,
                0.088, 0.42, sides=10, axis='y',
                key=key if (r + c) % 2 else 'oak_light')


def basket(name, x, y, z, r=0.17, h=0.26, fill=None):
    """A woven basket: a turned body that flares, two withy hoops, and what is
    in it heaped above the rim."""
    lathe(f'{name}_b', x, y, z, [(r * 0.72, 0.0), (r * 0.9, h * 0.25),
                                 (r * 1.0, h * 0.72), (r * 1.05, h)],
          sides=12, key='straw')
    for k in range(2):
        ring(f'{name}_hp{k}', x, y, z + h * (0.3 + 0.52 * k),
             r * (0.93 + 0.12 * k), 0.02, key='root', sides=12, tube_sides=5)
    if fill:
        orb(f'{name}_f', x, y, z + h - 0.03, r * 1.9, r * 1.9, 0.16, key=fill,
            wobble=0.2, seed=5)


def beehive(name, x, y, z, r=0.19):
    """A skep: a dome of coiled straw. It was three stacked slabs, and a skep
    is the one object in the kit whose entire identity is that it is a
    smooth dome with rings round it."""
    lathe(f'{name}_b', x, y, z, [(r * 1.0, 0.0), (r * 0.96, r * 0.4),
                                 (r * 0.82, r * 0.78), (r * 0.52, r * 1.05),
                                 (r * 0.18, r * 1.2)],
          sides=12, key='straw')
    for k in range(3):
        f = (k + 1) / 4
        ring(f'{name}_c{k}', x, y, z + r * 1.2 * f,
             r * (0.99 - 0.3 * f * f), 0.018, key='root', sides=12,
             tube_sides=5)
    box(f'{name}_hole', x, y - r * 0.86, z + r * 0.22, 0.07, 0.05, 0.06,
        mat('dark'))
    lathe(f'{name}_stand', x, y, z - 0.07, [(r * 1.2, 0.0), (r * 1.15, 0.07)],
          sides=12, key='oak')


def signpost(name, x, y, z, arms=2, h=1.15):
    """A post with arms pointing off the tile. The building says where it
    sends things, which is the one thing a yard cannot show."""
    box(f'{name}_p', x, y, z, 0.1, 0.1, h, mat('oak'))
    box(f'{name}_cap', x, y, z + h, 0.18, 0.18, 0.09, mat('oak_light'))
    for i in range(arms):
        a = box(f'{name}_a{i}', x + 0.24, y, z + h - 0.18 - i * 0.22,
                0.44, 0.06, 0.14, mat('oak_light'))
        a.rotation_euler = (0, 0, 1.7 * i)


def perch_bird(name, x, y, z, kind=0):
    """A bird on a ridge or a rail. Three boxes; it is a silhouette."""
    tone = 'critter_dark' if kind % 2 else 'iron'
    box(f'{name}_b', x, y, z, 0.16, 0.12, 0.13, mat(tone))
    box(f'{name}_h', x + 0.09, y, z + 0.11, 0.09, 0.08, 0.09, mat(tone))
    t = box(f'{name}_t', x - 0.11, y, z + 0.05, 0.14, 0.07, 0.05, mat(tone))
    t.rotation_euler = (0, -0.5, 0)


# ── Colour: planting and cloth ─────────────────────────────
# The two things a medieval building is allowed to be bright about. Everything
# else in the palette is a material — stone, timber, tile — and materials are
# earth colours. Flowers and cloth are the exception, and being the exception
# is what makes them read from across the map.


def window_box(name, x, y, z, w=0.5, facing='y', bloom='bloom_red'):
    """A planted box under a window. Two boxes and four blooms, and a blank
    wall becomes a lived-in one."""
    bw, bd = (w, 0.14) if facing == 'y' else (0.14, w)
    box(f'{name}_b', x, y, z, bw, bd, 0.11, mat('oak'))
    box(f'{name}_soil', x, y, z + 0.11, bw * 0.88, bd * 0.7, 0.03, mat('dirt'))
    for i in range(4):
        t = -w / 2 + w * (i + 0.5) / 4
        bx, by = ((x + t, y) if facing == 'y' else (x, y + t))
        j = _hash01(f'{name}{i}')
        box(f'{name}_g{i}', bx, by, z + 0.12, 0.07, 0.07, 0.1 + 0.06 * j,
            mat('herb'))
        box(f'{name}_f{i}', bx, by, z + 0.2 + 0.06 * j, 0.11, 0.1, 0.09,
            mat(bloom if i % 2 else 'bloom_white'))


def flower_bed(name, x, y, z, w=0.7, d=0.4, bloom='bloom_pink', n=7):
    """A bed of blooms edged in stone. The one place on the map where a
    saturated colour is allowed to sit on the ground."""
    box(f'{name}_e', x, y, z, w + 0.1, d + 0.1, 0.07, mat('ashlar'))
    box(f'{name}_s', x, y, z + 0.05, w, d, 0.05, mat('dirt'))
    for i in range(n):
        j = _hash01(f'{name}p{i}')
        k = _hash01(f'{name}q{i}')
        bx = x + (j - 0.5) * w * 0.86
        by = y + (k - 0.5) * d * 0.8
        box(f'{name}_g{i}', bx, by, z + 0.08, 0.06, 0.06, 0.12 + 0.08 * j,
            mat('herb'))
        box(f'{name}_f{i}', bx, by, z + 0.18 + 0.08 * j, 0.12, 0.11, 0.09,
            mat(bloom if i % 3 else ('bloom_white' if i % 2
                                     else 'bloom_blue')))


def bunting(name, x, y, z, span, axis='x', n=7, a='cloth_red', b='cloth_gold'):
    """A string of little flags. Nothing says FESTIVAL, MARKET or ARRIVAL
    faster, and it is the cheapest colour in the kit: one box a flag."""
    lw, ld = (span, 0.03) if axis == 'x' else (0.03, span)
    box(f'{name}_line', x, y, z, lw, ld, 0.03, mat('iron'))
    for i in range(n):
        t = -span / 2 + span * (i + 0.5) / n
        bx, by = ((x + t, y) if axis == 'x' else (x, y + t))
        dip = 0.05 * math.sin(math.pi * (i + 0.5) / n)
        flag = box(f'{name}_{i}', bx, by, z - 0.14 - dip,
                   span / n * 0.6 if axis == 'x' else 0.04,
                   0.04 if axis == 'x' else span / n * 0.6, 0.16,
                   mat(a if i % 2 else b))
        flag.rotation_euler = (0, 0, 0)


def curtain(name, x, y, z, w, h, facing='y', key='cloth_red'):
    """Cloth hung in an opening — a shop shut, a shrine veiled, a stall
    shaded. Reads as colour in a dark hole, which is the strongest contrast
    the palette has."""
    bw, bd = (w, 0.05) if facing == 'y' else (0.05, w)
    box(f'{name}_rod', x, y, z + h, bw + 0.06, bd + 0.03, 0.05, mat('iron'))
    n = max(3, int(w / 0.12))
    for i in range(n):
        t = -w / 2 + w * (i + 0.5) / n
        bx, by = ((x + t, y) if facing == 'y' else (x, y + t))
        j = _hash01(f'{name}{i}')
        box(f'{name}_{i}', bx, by, z + h - (h * (0.72 + 0.28 * j)),
            (w / n * 0.94) if facing == 'y' else 0.05,
            0.05 if facing == 'y' else (w / n * 0.94),
            h * (0.72 + 0.28 * j), mat(key if i % 2 else 'cloth'))


def turf_roof(name, x, y, z, sx, sy, h, ridge_along='y', overhang=0.24):
    """Grass growing on a roof, with flowers in it. The apothecary's roof is
    part of the apothecary's stock."""
    shingle_gable(f'{name}_r', x, y, z, sx, sy, h, overhang=overhang, rows=20,
                  key='herb', dark='moss', ridge_along=ridge_along)
    span = sy if ridge_along == 'y' else sx
    run = (sx if ridge_along == 'y' else sy) / 2
    for i in range(14):
        j = _hash01(f'{name}f{i}')
        k = _hash01(f'{name}g{i}')
        f = 0.15 + 0.7 * j
        off = run * (1 - f) * (1 if k > 0.5 else -1)
        along = (k - 0.5) * span * 0.82
        bx, by = ((x + off, y + along) if ridge_along == 'y'
                  else (x + along, y + off))
        box(f'{name}_f{i}', bx, by, z + h * f + 0.04, 0.1, 0.1, 0.09,
            mat('bloom_white' if i % 3 else
                ('bloom_pink' if i % 2 else 'bloom_blue')))


# ── Signatures: the one thing you see FIRST ────────────────
# Every prop before this point lives in a yard, at ground level, at prop scale.
# Zoomed out that whole layer becomes texture and the roof becomes the picture,
# which is why twenty buildings could still read as one building with twenty
# roofs. The dimension nothing was using is HEIGHT — it costs no ground, and a
# shape above the ridge is the last thing to vanish as the camera pulls back.
#
# So: one object per building, big enough to break its own roofline, and shaped
# so that it could not be bolted onto any other building on the map.


def _at(ob, x, y, z, rx=0.0, ry=0.0, rz=0.0):
    """Place a box by its CENTRE and turn it.

    box() places by centre-bottom, which is right for everything that stands on
    the ground and wrong for everything arranged around a hub — a wheel rim, a
    chain, a ring of rays. Those want a centre.
    """
    ob.location = (x, y, z)
    ob.rotation_euler = (rx, ry, rz)
    return ob


def _tan_x(a):
    """The turn that lays a box ALONG a circle in the y-z plane, not across it.

    A box knows its own size and nothing about where it has been put, so a ring
    of them turned by their own bearing all point at the hub and the wheel
    comes out a sunburst. The tangent is a quarter turn off the radius.
    """
    return a + math.pi / 2


def _tan_y(a):
    """The same, for a circle in the x-z plane. The sign flips because a turn
    about y sends +x to (cos t, 0, -sin t) rather than to (cos t, sin t)."""
    return -a - math.pi / 2


def water_wheel(name, x, y, z, r=0.78, segs=18, key='oak'):
    """An overshot mill wheel, on edge, against the hall's flank.

    THE test case for this whole pass: nothing else in the settlement is a
    circle standing upright, so the wheel is read before the building it is
    bolted to, at any zoom, without a single prop being visible.
    """
    cz = z + r + 0.14
    for s in (-1, 1):
        box(f'{name}_pier{s}', x + s * 0.34, y, z, 0.2, 0.26, r + 0.14,
            mat('ashlar'))
    box(f'{name}_axle', x, y, cz - 0.06, 0.86, 0.12, 0.12, mat('iron'))
    for i in range(segs):
        a = 2 * math.pi * i / segs
        oy, oz = r * math.cos(a), r * math.sin(a)
        for s in (-1, 1):
            _at(box(f'{name}_rim{i}{s}', 0, 0, 0, 0.1,
                    2 * math.pi * r / segs * 1.2, 0.09,
                    mat(key if i % 2 else 'oak_light')),
                x + s * 0.27, y + oy, cz + oz, _tan_x(a), 0, 0)
        _at(box(f'{name}_pad{i}', 0, 0, 0, 0.5, 0.05, 0.26,
                mat('oak_light' if i % 2 else 'oak')),
            x, y + oy * 0.86, cz + oz * 0.86, _tan_x(a), 0, 0)
    for i in range(6):
        a = math.pi * i / 6
        _at(box(f'{name}_spoke{i}', 0, 0, 0, 0.08, 0.08, 2 * r - 0.12,
                mat(key)), x, y, cz, a, 0, 0)
    box(f'{name}_hub', x, y, cz - 0.11, 0.2, 0.22, 0.22, mat('oak'))
    # The race: the water is why the wheel turns, and a wheel over dry ground
    # is a fairground ride.
    box(f'{name}_race', x, y + r * 0.62, z + r * 1.55, 0.44, r * 0.9, 0.12,
        mat('oak'))
    box(f'{name}_flow', x, y + r * 0.5, z + r * 1.62, 0.3, r * 0.7, 0.06,
        mat('water'))
    for i in range(4):
        box(f'{name}_spray{i}', x + (_hash01(f'{name}s{i}') - 0.5) * 0.4,
            y - r * 0.75, z + 0.1 + i * 0.12, 0.14, 0.14, 0.1, mat('foam'))
    box(f'{name}_tail', x, y - r * 0.5, z, 0.6, r * 0.8, 0.05, mat('water'))


def tracery(name, x, y, z, w=0.82, hh=1.3, facing='y'):
    """A traceried window, cut, glazed and standing in the yard on trestles.

    ── Why this and not the crane (user 2026-08-12) ──
    The masons had a treadwheel and the carpenters next door have a mill
    wheel, and A BIG WHEEL on both put the two buildings that were already the
    hardest pair to tell apart back into the same silhouette. A crane is what
    a SITE has; what a lodge has is the finished work, and nothing else in the
    settlement is a pointed arch standing on its own in the open air.
    """
    for s in (-1, 1):
        for t in (-1, 1):
            leg = box(f'{name}_tl{s}{t}', x + s * (w / 2 - 0.02),
                      y + t * 0.16, z, 0.11, 0.11, 0.34, mat('oak'))
            leg.rotation_euler = (-t * 0.22, 0, 0)
        box(f'{name}_tt{s}', x + s * (w / 2 - 0.02), y, z + 0.34, 0.2, 0.42,
            0.09, mat('oak_light'))
    base = z + 0.4
    for s in (-1, 1):
        box(f'{name}_jamb{s}', x + s * w / 2, y, base, 0.15, 0.22,
            hh * 0.52, mat('limestone'))
    springer = base + hh * 0.52
    box(f'{name}_sill', x, y, base - 0.09, w + 0.3, 0.28, 0.1,
        mat('limestone_shade'))
    # A two-centred arch: one arc struck from each side, meeting in a point.
    for s in (-1, 1):
        cxx = x - s * w * 0.2
        rr = w * 0.7
        for i in range(6):
            a = math.radians(22 + i * 10.5)
            th = -(a + math.pi / 2) if s > 0 else (a - math.pi / 2)
            _at(box(f'{name}_vs{s}{i}', 0, 0, 0, 0.26, 0.22, 0.15,
                    mat('limestone' if i % 2 else 'limestone_shade')),
                cxx + s * rr * math.cos(a), y, springer + rr * math.sin(a),
                0, th, 0)
    box(f'{name}_glassa', x, y + 0.02, springer - 0.02, w - 0.28, 0.06,
        hh * 0.34, mat('glow'))
    box(f'{name}_glassb', x, y + 0.02, base, w - 0.28, 0.06, hh * 0.52,
        mat('water_deep'))
    # Two lights and the mullion between them, then the cusps that make it
    # tracery rather than a hole.
    box(f'{name}_mull', x, y - 0.02, base, 0.1, 0.16, hh * 0.62,
        mat('limestone'))
    for s in (-1, 1):
        for k in range(3):
            box(f'{name}_cusp{s}{k}', x + s * (0.1 + k * 0.09),
                y - 0.03, base + hh * 0.5 + k * 0.06, 0.1, 0.13, 0.09,
                mat('limestone_shade'))
        box(f'{name}_ml{s}', x + s * w * 0.3, y - 0.02, base, 0.07, 0.14,
            hh * 0.5, mat('limestone_shade'))
    box(f'{name}_key', x, y - 0.04, springer + w * 0.62, 0.16, 0.18, 0.22,
        mat('limestone'))
    # The pinnacle beside it: the same lodge's other line of work, finished.
    px = x + w / 2 + 0.42
    for k, (sz_, hz) in enumerate(((0.3, 0.26), (0.24, 0.22), (0.2, 0.18))):
        box(f'{name}_pb{k}', px, y - 0.1, z + k * 0.24, sz_, sz_, hz,
            mat('limestone' if k % 2 else 'limestone_shade'))
    spire(f'{name}_psp', px, y - 0.1, z + 0.72, 0.16, 0.5, sides=8, rings=7,
          key='limestone', dark='limestone_shade')
    for i in range(4):
        a = 2 * math.pi * i / 4 + 0.8
        box(f'{name}_crock{i}', px + 0.15 * math.cos(a),
            y - 0.1 + 0.15 * math.sin(a), z + 0.82, 0.11, 0.11, 0.1,
            mat('limestone_shade'))
    finial(f'{name}_pfin', px, y - 0.1, z + 1.22, 0.22, key='limestone')


def treadwheel(name, x, y, z, r=0.56, jib=1.5):
    """A treadwheel crane: the drum a man walks inside to lift a stone.

    Two circles and a boom, and it is the one machine that says MASONS rather
    than builders — the quarry has a derrick and the site has scaffolding, and
    neither of them has a wheel with a floor in it.
    """
    cz = z + 1.15 + r
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            leg = box(f'{name}_leg{sx_}{sy_}', x + sx_ * 0.42,
                      y + sy_ * (r + 0.12), z, 0.13, 0.13, 1.15 + r,
                      mat('oak'))
            leg.rotation_euler = (-sy_ * 0.12, 0, 0)
    box(f'{name}_sill', x, y, z + 1.1, 1.0, 2 * r + 0.5, 0.11,
        mat('oak_light'))
    box(f'{name}_axle', x, y, cz - 0.06, 0.12, 2 * r + 0.6, 0.12, mat('iron'))
    for i in range(14):
        a = 2 * math.pi * i / 14
        ox, oz = r * math.cos(a), r * math.sin(a)
        for s in (-1, 1):
            _at(box(f'{name}_rim{i}{s}', 0, 0, 0,
                    2 * math.pi * r / 14 * 1.2, 0.09, 0.1,
                    mat('oak' if i % 2 else 'oak_light')),
                x + ox, y + s * (r * 0.62), cz + oz, 0, _tan_y(a), 0)
        _at(box(f'{name}_tread{i}', 0, 0, 0, 2 * math.pi * r / 14 * 1.1,
                r * 1.15, 0.05, mat('oak_light')),
            x + ox * 0.9, y, cz + oz * 0.9, 0, _tan_y(a), 0)
    for i in range(4):
        a = math.pi * i / 4
        for s in (-1, 1):
            _at(box(f'{name}_sp{i}{s}', 0, 0, 0, 2 * r - 0.1, 0.06, 0.06,
                    mat('oak')), x, y + s * (r * 0.62), cz, 0, a, 0)
    boom = box(f'{name}_boom', x - jib * 0.36, y, cz + 0.1, jib, 0.13, 0.13,
               mat('oak_light'))
    boom.rotation_euler = (0, 0.42, 0)
    tipx, tipz = x - jib * 0.82, cz + 0.1 + jib * 0.4
    box(f'{name}_stay', x + 0.1, y, cz + 0.1, 0.06, 0.06, 0.9, mat('iron'))
    box(f'{name}_rope', tipx, y, z + 0.9, 0.05, 0.05, tipz - z - 0.9,
        mat('iron'))
    box(f'{name}_hook', tipx, y, z + 0.78, 0.12, 0.12, 0.14, mat('iron'))
    box(f'{name}_load', tipx, y, z + 0.42, 0.46, 0.42, 0.36,
        mat('limestone'))
    for s in (-1, 1):
        box(f'{name}_sling{s}', tipx + s * 0.24, y, z + 0.42, 0.05, 0.05,
            0.38, mat('iron'))


def hoist(name, x, y, z, out=0.34, key='oak'):
    """A gable hoist: the beam, its wheel, and a sack halfway up the rope.

    It belongs at the APEX and nowhere else. Hung at eave height it crosses
    the roof slope behind it and reads as a fallen branch; at the ridge it has
    nothing behind it but sky, which is the whole reason for putting a shape up
    there in the first place.
    """
    box(f'{name}_beam', x, y - out / 2, z, 0.13, out + 0.62, 0.13, mat(key))
    box(f'{name}_brace', x, y - 0.12, z - 0.34, 0.11, 0.14, 0.42, mat(key))
    for s_ in (-1, 1):
        box(f'{name}_cheek{s_}', x + s_ * 0.11, y - out, z + 0.015, 0.04,
            0.2, 0.22, mat('oak_light'))
    for i in range(8):
        a = 2 * math.pi * i / 8
        _at(box(f'{name}_wh{i}', 0, 0, 0, 0.05, 0.09, 0.055,
                mat('oak_light' if i % 2 else 'oak')),
            x, y - out + 0.085 * math.cos(a), z + 0.085 * math.sin(a),
            _tan_x(a), 0, 0)
    box(f'{name}_rope', x, y - out, z - 0.52, 0.045, 0.045, 0.56, mat('iron'))
    box(f'{name}_hookb', x, y - out, z - 0.58, 0.1, 0.1, 0.1, mat('iron'))
    sack_pile(f'{name}_sack', x, y - out, z - 0.86, n=1, key='straw')
    box(f'{name}_cleat', x + 0.18, y + 0.1, z - 1.15, 0.12, 0.1, 0.24,
        mat('iron'))


def chain_wrap(name, x, y, z, sx, sy, per=6):
    """A chain right round a building, and a padlock the size of its door.

    Bars and slits say "defended"; a chain says "shut, and not by you". The
    vault is the one building whose entire subject is that nobody gets in.
    """
    for s in (-1, 1):
        for i in range(per):
            t = -sx / 2 + sx * (i + 0.5) / per
            box(f'{name}_l{s}{i}', x + t, y + s * sy / 2, z,
                sx / per * 0.62, 0.11, 0.13 if i % 2 else 0.2, mat('iron'))
        for i in range(per + 2):
            t = -sy / 2 + sy * (i + 0.5) / (per + 2)
            box(f'{name}_m{s}{i}', x + s * sx / 2, y + t, z,
                0.11, sy / (per + 2) * 0.62, 0.13 if i % 2 else 0.2,
                mat('iron'))
    box(f'{name}_body', x, y - sy / 2 - 0.12, z - 0.16, 0.36, 0.18, 0.4,
        mat('iron'))
    box(f'{name}_shack', x, y - sy / 2 - 0.12, z + 0.2, 0.26, 0.12, 0.18,
        mat('iron'))
    box(f'{name}_hole', x, y - sy / 2 - 0.22, z - 0.06, 0.1, 0.05, 0.12,
        mat('gold'))


def portcullis(name, x, y, z, w, h, facing='y', bars=5):
    """The grid in the gate. Cheap, and it turns a doorway into a refusal."""
    for i in range(bars):
        t = -w / 2 + w * (i + 0.5) / bars
        bx, by = ((x + t, y) if facing == 'y' else (x, y + t))
        box(f'{name}_v{i}', bx, by, z, 0.05, 0.05, h, mat('iron'))
        box(f'{name}_p{i}', bx, by, z - 0.08, 0.05, 0.05, 0.1, mat('iron'))
    for k in range(3):
        bw, bd = (w, 0.05) if facing == 'y' else (0.05, w)
        box(f'{name}_h{k}', x, y, z + h * (k + 1) / 4, bw, bd, 0.05,
            mat('iron'))


def still(name, x, y, z):
    """An alembic on a furnace: pot, swan neck, condenser, steam.

    A cauldron on a fire is a kitchen. A copper vessel with a bent neck running
    into a tub of water is a LABORATORY, and the apothecary is the only
    building on the map entitled to one.
    """
    ashlar_courses(f'{name}_furn', x, y, z, 0.62, 0.58, 0.44, course=0.0691,
                   block=0.13)
    box(f'{name}_mouth', x, y - 0.3, z + 0.06, 0.3, 0.06, 0.24, mat('dark'))
    for i in range(3):
        box(f'{name}_fire{i}', x - 0.08 + i * 0.08, y - 0.28, z + 0.08,
            0.09, 0.05, 0.14 + 0.05 * (i % 2),
            mat('gold' if i % 2 else 'banner'))
    for k, (rr, hh) in enumerate(((0.44, 0.18), (0.4, 0.16), (0.3, 0.14))):
        box(f'{name}_pot{k}', x, y, z + 0.44 + k * 0.16, rr, rr, hh,
            mat('copper' if k % 2 else 'gold_dark'))
    box(f'{name}_dome', x, y, z + 0.92, 0.2, 0.2, 0.16, mat('copper'))
    neck = box(f'{name}_neck', x + 0.24, y, z + 0.98, 0.42, 0.09, 0.09,
               mat('copper'))
    neck.rotation_euler = (0, 0.5, 0)
    box(f'{name}_drop', x + 0.44, y, z + 0.6, 0.08, 0.08, 0.3,
        mat('gold_dark'))
    barrel(f'{name}_tub', x + 0.5, y, z, r=0.2, h=0.44)
    box(f'{name}_water', x + 0.5, y, z + 0.44, 0.28, 0.28, 0.04, mat('water'))
    for i in range(3):
        box(f'{name}_coil{i}', x + 0.5, y, z + 0.12 + i * 0.12, 0.36, 0.36,
            0.05, mat('copper'))
    box(f'{name}_phial', x - 0.4, y - 0.2, z + 0.44, 0.12, 0.12, 0.2,
        mat('glow'))
    smoke(f'{name}_steam', x, y, z + 1.08, h=0.8, puffs=4)


def beacon(name, x, y, z, mast=1.15, r=0.26):
    """A fire in an iron cage on a mast. The whole POINT of a watchtower.

    A brazier on the deck is somewhere to warm your hands; the same fire lifted
    above the spire is a signal, and it is the only flame on the map that is
    higher than everything around it.
    """
    box(f'{name}_mast', x, y, z, 0.11, 0.11, mast, mat('oak'))
    for k in range(3):
        box(f'{name}_step{k}', x, y, z + 0.24 + k * 0.3, 0.3, 0.07, 0.05,
            mat('oak_light'))
    box(f'{name}_arm', x, y, z + mast - 0.1, 0.44, 0.44, 0.08, mat('iron'))
    for i in range(8):
        a = 2 * math.pi * i / 8
        box(f'{name}_bar{i}', x + r * math.cos(a), y + r * math.sin(a),
            z + mast, 0.06, 0.06, 0.34, mat('iron'))
    for k, rr in enumerate((r * 2.1, r * 2.3)):
        box(f'{name}_ring{k}', x, y, z + mast + k * 0.26, rr, rr, 0.06,
            mat('iron'))
    for i in range(5):
        j = _hash01(f'{name}f{i}')
        box(f'{name}_flame{i}', x + (j - 0.5) * r * 1.1,
            y + (_hash01(f'{name}g{i}') - 0.5) * r * 1.1, z + mast + 0.18,
            0.14, 0.14, 0.2 + 0.24 * j, mat('gold' if i % 2 else 'banner'))
    smoke(f'{name}_smoke', x, y, z + mast + 0.55, h=0.9, puffs=4)


def scales(name, x, y, z, span=1.05, h=1.35):
    """A great balance, standing where the haggling happens.

    Every other market prop is a thing being sold; this is the thing that
    settles the price, it is chest-high on a person and it is a shape — beam,
    two chains, two pans — with no second reading.
    """
    box(f'{name}_foot', x, y, z, 0.44, 0.4, 0.12, mat('ashlar'))
    box(f'{name}_post', x, y, z + 0.12, 0.14, 0.14, h, mat('oak'))
    box(f'{name}_cap', x, y, z + h + 0.12, 0.24, 0.22, 0.12, mat('iron'))
    box(f'{name}_beam', x, y, z + h + 0.22, span, 0.09, 0.09, mat('iron'))
    box(f'{name}_ptr', x, y, z + h + 0.3, 0.05, 0.05, 0.22, mat('gold'))
    for i, s in enumerate((-1, 1)):
        drop = 0.42 if s < 0 else 0.3
        for k in range(3):
            box(f'{name}_ch{s}{k}', x + s * (span / 2 - 0.04 * k), y,
                z + h + 0.22 - 0.08 - k * drop / 3, 0.05, 0.05, drop / 3,
                mat('iron'))
        px = x + s * (span / 2 - 0.1)
        box(f'{name}_pan{s}', px, y, z + h + 0.14 - drop, 0.38, 0.34, 0.05,
            mat('iron'))
        box(f'{name}_rim{s}', px, y, z + h + 0.19 - drop, 0.42, 0.38, 0.04,
            mat('iron'))
    box(f'{name}_load', x - (span / 2 - 0.1), y, z + h - 0.22, 0.24, 0.2,
        0.1, mat('gold'))
    for k in range(3):
        box(f'{name}_wt{k}', x + (span / 2 - 0.16) + 0.04 * k, y,
            z + h + 0.03 + k * 0.06, 0.16 - 0.03 * k, 0.14, 0.06,
            mat('iron'))


def tent(name, x, y, z, r=0.72, h=0.95, key='cloth', stripe='cloth_red'):
    """A striped pavilion — the tent the caravan actually sleeps in.

    The caravanserai's whole subject is arrival, and arrival means people who
    brought their own roof. A cone in cloth colours next to a stone gate says
    that in one shape, and no other building on the map is allowed cloth for a
    roof.
    """
    for i in range(8):
        a = 2 * math.pi * i / 8
        box(f'{name}_pole{i}', x + r * 0.96 * math.cos(a),
            y + r * 0.96 * math.sin(a), z, 0.07, 0.07, h * 0.62, mat('oak'))
    box(f'{name}_ring', x, y, z + h * 0.62, r * 2, r * 2, 0.06,
        mat('oak_light'))
    spire(f'{name}_top', x, y, z + h * 0.62, r * 1.06, h, sides=8, rings=9,
          key=key, dark=stripe)
    dagged(f'{name}_val', x, y - r * 0.98, z + h * 0.62, r * 1.7, teeth=9,
           drop=0.14, key=stripe)
    box(f'{name}_mast', x, y, z + h * 1.5, 0.07, 0.07, 0.34, mat('oak'))
    pen = box(f'{name}_pen', x + 0.16, y, z + h * 1.62, 0.3, 0.03, 0.14,
              mat(stripe))
    pen.rotation_euler = (0, 0, 0.2)
    curtain(f'{name}_flap', x, y - r * 0.94, z, r * 0.8, h * 0.6, key=stripe)
    for s in (-1, 1):
        box(f'{name}_guy{s}', x + s * (r + 0.26), y - 0.1, z, 0.06, 0.06,
            0.5, mat('iron'))
        box(f'{name}_peg{s}', x + s * (r + 0.4), y - 0.1, z, 0.07, 0.07, 0.16,
            mat('oak'))


def cradle_egg(name, x, y, z, r=0.42, key='egg_legendary'):
    """One egg, kept warm, at a size no yard prop is allowed to be.

    The Hatchery already had a clutch and the clutch is prop-sized — five of
    them side by side still read as pebbles. ONE egg as tall as the door, in a
    stone cradle over its own fire, is the building's name in one object.
    """
    for s in (-1, 1):
        ashlar_courses(f'{name}_arm{s}', x + s * (r + 0.16), y, z, 0.24,
                       r * 1.7, 0.62, course=0.0691, block=0.13)
    box(f'{name}_bed', x, y, z + 0.5, r * 2.1, r * 1.8, 0.12,
        mat('limestone'))
    straw_scatter(f'{name}_straw', x, y, z + 0.62, r * 1.2, n=14)
    egg(f'{name}_egg', x, y, z + 0.62, r, mat(key))
    for i in range(3):
        box(f'{name}_fire{i}', x - 0.16 + i * 0.16, y - r * 0.9, z + 0.06,
            0.11, 0.06, 0.16 + 0.06 * (i % 2),
            mat('gold' if i % 2 else 'banner'))
    for s in (-1, 1):
        box(f'{name}_hoop{s}', x + s * r * 0.62, y, z + 0.62 + r * 0.9,
            0.06, r * 1.5, 0.06, mat('iron'))
    smoke(f'{name}_warm', x, y, z + 0.62 + r * 2.1, h=0.6, puffs=3)


def hung_net(name, x, y, z, span=1.5, mast=1.4, axis='x'):
    """A net slung between two masts, with the floats and the catch in it.

    A rack of split fish is a texture; this is a shape, and it stands as high
    as the hut's ridge. It must NOT go where the rails already are — a lattice
    hung in front of a lattice is one unreadable thing instead of two readable
    ones — so it takes the open side and runs the other way.
    """
    def at(t, d=0.0):
        return ((x + t, y + d) if axis == 'x' else (x + d, y + t))

    for s_ in (-1, 1):
        mx, my = at(s_ * span / 2)
        box(f'{name}_mast{s_}', mx, my, z, 0.11, 0.11, mast, mat('oak'))
        box(f'{name}_cap{s_}', mx, my, z + mast, 0.17, 0.17, 0.09,
            mat('oak_light'))
        box(f'{name}_stay{s_}', mx, my, z, 0.07, 0.07, mast * 0.5,
            mat('root'))
    sw, sd = ((span + 0.3, 0.09) if axis == 'x' else (0.09, span + 0.3))
    box(f'{name}_spar', x, y, z + mast - 0.07, sw, sd, 0.08, mat('oak_light'))
    cols = 6
    for i in range(cols):
        t = -span / 2 + span * i / (cols - 1)
        sag = 0.3 * math.sin(math.pi * i / (cols - 1))
        vx, vy = at(t)
        box(f'{name}_v{i}', vx, vy, z + mast - 0.14 - sag / 2, 0.04, 0.04,
            0.66 + sag, mat('root'))
    for k in range(3):
        d = 0.2 + k * 0.22
        for i in range(cols - 1):
            t = -span / 2 + span * (i + 0.5) / (cols - 1)
            sag = 0.3 * math.sin(math.pi * (i + 0.5) / (cols - 1))
            hx_, hy_ = at(t)
            hw, hd = ((span / (cols - 1) * 1.05, 0.04) if axis == 'x'
                      else (0.04, span / (cols - 1) * 1.05))
            box(f'{name}_h{k}{i}', hx_, hy_, z + mast - d - sag, hw, hd, 0.04,
                mat('root_dark' if k % 2 else 'root'))
    for i in range(3):
        j = _hash01(f'{name}f{i}')
        fx, fy = at(-span / 2 + span * (i + 0.5) / 3, -0.07)
        box(f'{name}_float{i}', fx, fy, z + mast - 0.12, 0.13, 0.13, 0.13,
            mat('cloth_stripe' if i % 2 else 'cloth'))
        cx_, cy_ = at(-span / 2 + 0.28 + j * (span - 0.56), 0.05)
        box(f'{name}_fish{i}', cx_, cy_, z + mast - 0.66 - 0.18 * j, 0.19,
            0.19, 0.3, mat('slate' if i % 2 else 'stucco_shade'))


def hoop_pelt(name, x, y, z, r=0.56, key='hide_dark', post=0.85,
              frame='oak_light'):
    """One pelt on a hoop as wide as the lodge is tall.

    The three little frames read as "some brown rectangles". A single round
    frame with a whole bear in it reads as a trophy, from any distance, and a
    circle is the one outline the fish hut can never borrow.
    """
    box(f'{name}_post', x, y, z, 0.14, 0.14, post, mat(frame))
    cz = z + post + r
    for i in range(16):
        a = 2 * math.pi * i / 16
        _at(box(f'{name}_h{i}', 0, 0, 0, 2 * math.pi * r / 16 * 1.25, 0.09,
                0.09, mat(frame if i % 2 else 'limestone_shade')),
            x + r * math.cos(a), y, cz + r * math.sin(a), 0, _tan_y(a), 0)
    # THREE courses, not five. Five closed into a solid disc and the head and
    # the paws — the only two parts that say bear rather than blanket —
    # disappeared into it.
    for k, (wf, hf) in enumerate(((1.0, 0.36), (0.9, 0.34), (0.66, 0.3))):
        box(f'{name}_pelt{k}', x, y + 0.05, cz - r * 0.66 + k * r * 0.48,
            r * 1.6 * wf, 0.06, r * hf,
            mat(key if k % 2 else 'root_dark'))
    box(f'{name}_head', x, y + 0.09, cz + r * 0.44, r * 0.56, 0.07, r * 0.46,
        mat('hide'))
    box(f'{name}_snout', x, y + 0.13, cz + r * 0.4, r * 0.24, 0.06, r * 0.2,
        mat('hide_dark'))
    for s in (-1, 1):
        box(f'{name}_ear{s}', x + s * r * 0.24, y + 0.09, cz + r * 0.82,
            0.12, 0.06, 0.12, mat('hide'))
        box(f'{name}_eye{s}', x + s * r * 0.11, y + 0.15, cz + r * 0.56,
            0.06, 0.04, 0.06, mat('dark'))
        box(f'{name}_paw{s}', x + s * r * 0.82, y + 0.07, cz - r * 0.26,
            0.24, 0.06, 0.28, mat('hide'))
        for k in range(3):
            box(f'{name}_claw{s}{k}', x + s * (r * 0.82 - 0.07 + k * 0.07),
                y + 0.1, cz - r * 0.44, 0.05, 0.04, 0.07, mat('cloth'))
        box(f'{name}_leg{s}', x + s * r * 0.6, y + 0.06, cz - r * 0.74,
            0.2, 0.05, 0.26, mat('hide_dark'))
    for i in range(8):
        a = 2 * math.pi * i / 8
        box(f'{name}_lash{i}', x + r * 0.93 * math.cos(a), y + 0.02,
            cz + r * 0.93 * math.sin(a), 0.1, 0.07, 0.1, mat('cloth'))


def antlers(name, x, y, z, span=0.5, key='limestone', post=0.0):
    """A skull and a rack, on a trophy post.

    It was over the door until the render showed every tine lying on the roof
    slope behind it: between the door head and the eave there is a quarter of
    a metre and a rack is half of one. A post costs one box and gives it the
    open sky it needed all along.
    """
    if post:
        carved_post(f'{name}_p', x, y, z, post)
        z += post
    box(f'{name}_skull', x, y, z, 0.2, 0.12, 0.26, mat(key))
    box(f'{name}_muzzle', x, y - 0.03, z - 0.12, 0.13, 0.12, 0.16, mat(key))
    for s in (-1, 1):
        base = box(f'{name}_b{s}', x + s * 0.1, y, z + 0.24, 0.06, 0.06, span,
                   mat(key))
        base.rotation_euler = (0, -s * 0.5, 0)
        for k in range(3):
            tine = box(f'{name}_t{s}{k}', x + s * (0.2 + k * 0.11), y,
                       z + 0.34 + k * 0.13, 0.05, 0.05, span * 0.42,
                       mat(key))
            tine.rotation_euler = (0, -s * (0.9 - k * 0.18), 0)


def belfry(name, x, y, z, w=0.78, hh=0.72, key='verdigris',
           dark='verdigris_dark'):
    """An open bell stage astride the ridge.

    The minster is the tallest thing the settlement builds and it ended in a
    plain crest, which is what every other steep roof ends in. A belfry is
    architecture rather than ornament: you can see through it, and a shape with
    sky inside it is unmistakable at any size.
    """
    box(f'{name}_deck', x, y, z, w + 0.34, w + 0.34, 0.12, mat('ashlar'))
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            column(f'{name}_c{sx_}{sy_}', x + sx_ * w / 2, y + sy_ * w / 2,
                   z + 0.12, 0.09, hh, key='limestone')
    for s in (-1, 1):
        arch(f'{name}_a{s}', x, y + s * w / 2, z + 0.12 + hh * 0.62, w - 0.1,
             hh * 0.42, 0.1, key='dark')
        arch(f'{name}_ax{s}', x + s * w / 2, y, z + 0.12 + hh * 0.62,
             w - 0.1, hh * 0.42, 0.1, key='dark', facing='x')
    box(f'{name}_lint', x, y, z + 0.12 + hh, w + 0.3, w + 0.3, 0.11,
        mat('limestone'))
    bell(f'{name}_bell', x, y, z + 0.12 + hh - 0.34, r=0.19)
    box(f'{name}_beam', x, y, z + 0.12 + hh - 0.06, w + 0.1, 0.09, 0.09,
        mat('oak'))
    spire(f'{name}_sp', x, y, z + 0.23 + hh, w * 0.86, hh * 1.15, sides=8,
          rings=10, key=key, dark=dark)
    finial(f'{name}_fin', x, y, z + 0.23 + hh * 2.15, 0.28)


def coin_emblem(name, x, y, z, r=0.34, facing='y', key='gold'):
    """A struck coin the size of a rose window, on the wall above the door.

    The Vault hides its gold behind a chain; this one hangs it on the front and
    puts a light on it. Same material, opposite argument, and at map size the
    two buildings can never be confused again.
    """
    for i in range(16):
        a = 2 * math.pi * i / 16
        ox, oz = r * math.cos(a), r * math.sin(a)
        bx, by = ((x + ox, y) if facing == 'y' else (x, y + ox))
        seg = box(f'{name}_rim{i}', 0, 0, 0,
                  (2 * math.pi * r / 16 * 1.25) if facing == 'y' else 0.09,
                  0.09 if facing == 'y' else (2 * math.pi * r / 16 * 1.25),
                  0.1, mat('gold_dark'))
        _at(seg, bx, by, z + oz,
            0 if facing == 'y' else _tan_x(a),
            _tan_y(a) if facing == 'y' else 0, 0)
    fw, fd = ((r * 1.7, 0.07) if facing == 'y' else (0.07, r * 1.7))
    box(f'{name}_face', x, y, z - r * 0.85, fw, fd, r * 1.7, mat(key))
    box(f'{name}_cross', x, y, z - r * 0.62, fw * 0.72, fd * 1.6, 0.09,
        mat('gold_dark'))
    box(f'{name}_crossv', x, y, z - r * 0.62,
        (0.09 if facing == 'y' else fw * 0.72),
        (fd * 1.6 if facing == 'y' else 0.09), r * 1.24, mat('gold_dark'))
    for i in range(8):
        a = 2 * math.pi * i / 8 + 0.4
        ox, oz = r * 1.22 * math.cos(a), r * 1.22 * math.sin(a)
        bx, by = ((x + ox, y) if facing == 'y' else (x, y + ox))
        # A ray points OUTWARD, so it is the one part of a circle that does
        # want the radius rather than the tangent.
        ray = box(f'{name}_ray{i}', 0, 0, 0, 0.06, 0.06, r * 0.44, mat(key))
        _at(ray, bx, by, z + oz,
            0 if facing == 'y' else a - math.pi / 2,
            a - math.pi / 2 if facing == 'y' else 0, 0)


def spar_tree(name, x, y, z, hgt=2.75, key='oak'):
    """A standing trunk with its top taken off and its limbs cut to stubs.

    First attempt was a pale square column, which next to a chimney IS a
    chimney. What makes a trunk a trunk is bark — rings of little ridges all
    the way up — and what makes it a FELLED one is the limbs cut back to
    stumps and the climbing rope still round it.
    """
    for k in range(4):
        f = 1.0 - k * 0.13
        box(f'{name}_t{k}', x, y, z + hgt * k / 4, 0.27 * f, 0.27 * f,
            hgt / 4 + 0.02, mat(key if k % 2 else 'root_dark'))
    for ring in range(7):
        rz = z + 0.16 + ring * (hgt - 0.3) / 6
        rr = 0.135 * (1.0 - 0.4 * ring / 6)
        for i in range(6):
            a = 2 * math.pi * i / 6 + ring * 0.4
            box(f'{name}_bk{ring}{i}', x + rr * math.cos(a),
                y + rr * math.sin(a), rz, 0.07, 0.07, 0.2,
                mat('root_dark' if (ring + i) % 2 else 'oak'))
    box(f'{name}_cut', x, y, z + hgt, 0.23, 0.23, 0.06, mat('oak_light'))
    box(f'{name}_heart', x, y, z + hgt + 0.06, 0.13, 0.13, 0.02,
        mat('cloth'))
    # The stubs lean out and DOWN-camera, or the tree keeps its limbs behind
    # itself and stays a post.
    for i, (ax, ay, az, ln) in enumerate(((1, -0.4, 0.4, 0.52),
                                          (-1, -0.5, 0.62, 0.44),
                                          (1, 0.5, 0.8, 0.38),
                                          (-1, 0.3, 0.26, 0.46),
                                          (0.4, -1, 0.54, 0.4))):
        stub = box(f'{name}_st{i}', x + ax * 0.24, y + ay * 0.18,
                   z + hgt * az, ln, 0.12, 0.12, mat('root_dark'))
        stub.rotation_euler = (0, -ax * 0.5, math.atan2(ay, ax) * 0.4)
        box(f'{name}_sc{i}', x + ax * (0.24 + ln * 0.42), y + ay * 0.18,
            z + hgt * az + 0.1, 0.12, 0.12, 0.05, mat('oak_light'))
    for k in range(4):
        box(f'{name}_rope{k}', x, y, z + hgt * 0.5 + k * 0.09, 0.3, 0.3, 0.05,
            mat('straw'))
    box(f'{name}_tail', x + 0.15, y - 0.14, z + 0.2, 0.05, 0.05,
        hgt * 0.42, mat('straw'))
    for k in range(3):
        box(f'{name}_coil{k}', x + 0.3, y - 0.2, z + 0.02 + k * 0.06,
            0.32, 0.3, 0.05, mat('straw'))


def centring_arch(name, x, y, z, w=0.95, rise=0.5):
    """A pointed arch half-turned, still standing on its timber centring.

    A camp full of scaffolding says work; an arch with its keystone not yet in
    says work IN PROGRESS, which is the only permanent state a builder's yard
    is ever in.
    """
    for s in (-1, 1):
        box(f'{name}_pier{s}', x + s * (w / 2 + 0.1), y, z, 0.22, 0.3, 0.34,
            mat('limestone'))
    segs = 7
    for i in range(segs):
        f = (i + 0.5) / segs
        a = math.pi * f
        ox = -math.cos(a) * (w / 2 + 0.08)
        oz = math.sin(a) * rise
        if i in (3,):
            continue
        v = box(f'{name}_vs{i}', 0, 0, 0, 0.3, 0.34, 0.24,
                mat('limestone' if i % 2 else 'limestone_shade'))
        _at(v, x + ox, y, z + 0.34 + oz, 0, -(a - math.pi / 2), 0)
    for i in range(9):
        a = math.pi * (i + 0.5) / 9
        ox = -math.cos(a) * (w / 2 + 0.02)
        oz = math.sin(a) * (rise - 0.12)
        rib = box(f'{name}_ctr{i}', 0, 0, 0, 0.16, 0.4, 0.07,
                  mat('oak_light'))
        _at(rib, x + ox, y, z + 0.34 + oz, 0, -(a - math.pi / 2), 0)
    for s in (-1, 1):
        box(f'{name}_prop{s}', x + s * 0.3, y, z + 0.34, 0.09, 0.09,
            rise - 0.16, mat('oak'))
    box(f'{name}_key', x + w / 2 + 0.42, y, z, 0.3, 0.3, 0.26,
        mat('limestone'))
    box(f'{name}_line', x, y - 0.2, z + 0.34 + rise + 0.2, 0.04, 0.04, 0.42,
        mat('iron'))
    box(f'{name}_bob', x, y - 0.2, z + 0.34 + rise + 0.12, 0.08, 0.08, 0.12,
        mat('iron'))


# ── The round kit ──────────────────────────────────────────
# The five shapes reality has that a box cannot make. See the note in the
# joinery section for why this is not "make everything curved": straight sawn
# timber and squared blocks stay boxes, because that is what they are. These
# are for the things that were only square because the kit had nothing else.


def _mesh(name, verts, faces, key, smooth=False, bevel=None):
    """One mesh from vertices and faces, placed and materialled like box()."""
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat(key))
    for p in me.polygons:
        p.use_smooth = smooth
    if bevel is not None:
        ob['bevel'] = bevel
    return ob


def _noise3(x, y, z):
    """Value noise on an integer lattice, smoothstepped between corners.

    Pure Python and driven by _hash01, so it is the same on every machine and
    every run. Blender's own noise textures would need a Displace modifier,
    and a modifier is a thing every later pass has to remember to apply.
    """
    xi, yi, zi = math.floor(x), math.floor(y), math.floor(z)
    xf, yf, zf = x - xi, y - yi, z - zi
    u = xf * xf * (3 - 2 * xf)
    v = yf * yf * (3 - 2 * yf)
    w = zf * zf * (3 - 2 * zf)

    def corner(i, j, k):
        return _hash01(f'n{xi + i}.{yi + j}.{zi + k}')

    def mix(a, b, t):
        return a + (b - a) * t

    c00 = mix(corner(0, 0, 0), corner(0, 0, 1), w)
    c01 = mix(corner(0, 1, 0), corner(0, 1, 1), w)
    c10 = mix(corner(1, 0, 0), corner(1, 0, 1), w)
    c11 = mix(corner(1, 1, 0), corner(1, 1, 1), w)
    return mix(mix(c00, c01, v), mix(c10, c11, v), u)


def _fbm(x, y, z, octaves=3):
    """Three octaves of it. One octave is a lump; four is sandpaper."""
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for _ in range(octaves):
        total += amp * _noise3(x * freq, y * freq, z * freq)
        norm += amp
        amp *= 0.5
        freq *= 2.07
    return total / norm


_ICO_T = (1.0 + math.sqrt(5.0)) / 2.0
_ICO_VERTS = (
    (-1, _ICO_T, 0), (1, _ICO_T, 0), (-1, -_ICO_T, 0), (1, -_ICO_T, 0),
    (0, -1, _ICO_T), (0, 1, _ICO_T), (0, -1, -_ICO_T), (0, 1, -_ICO_T),
    (_ICO_T, 0, -1), (_ICO_T, 0, 1), (-_ICO_T, 0, -1), (-_ICO_T, 0, 1),
)
_ICO_FACES = (
    (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
    (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
    (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
    (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
)


def _icosphere(subdiv=2):
    """A sphere with EVEN triangles — the only base that displaces without
    pinching at a pole, which a UV sphere always does."""
    verts = [Vector(v).normalized() for v in _ICO_VERTS]
    faces = [tuple(f) for f in _ICO_FACES]
    for _ in range(subdiv):
        mid, out = {}, []

        def middle(a, b):
            k = (min(a, b), max(a, b))
            if k not in mid:
                verts.append(((verts[a] + verts[b]) / 2).normalized())
                mid[k] = len(verts) - 1
            return mid[k]

        for a, b, c in faces:
            ab, bc, ca = middle(a, b), middle(b, c), middle(c, a)
            out += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = out
    return verts, faces


def orb(name, x, y, z, sx, sy, sz, key='leaf', subdiv=1, smooth=False,
        seed=0, wobble=0.0, mtl=None):
    """A sphere or ellipsoid, placed by its centre-bottom like box().

    subdiv 0 is twenty faces and is right for anything under about 0.2 across;
    1 is eighty and is right for everything else here. Flat-shaded by default
    so foliage and smoke keep the set's faceting; the things that are actually
    SMOOTH in life — an egg, a bell — ask for smooth.

    [wobble] pushes the vertices about with the same noise crag() uses, which
    turns a ball into a bush without a second object.
    """
    verts, faces = _icosphere(subdiv)
    out = []
    for v in verts:
        r = 0.5
        if wobble:
            n = _fbm(v.x * 2.2 + seed * 3.7, v.y * 2.2 + seed * 1.9,
                     v.z * 2.2 + seed * 5.3)
        r *= 1.0 + wobble * (n * 2.0 - 1.0) if wobble else 1.0
        out.append((v.x * r * sx, v.y * r * sy, v.z * r * sz))
    me = bpy.data.meshes.new(name)
    me.from_pydata(out, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mtl if mtl is not None else mat(key))
    for p in me.polygons:
        p.use_smooth = smooth
    ob['bevel'] = 0.0
    ob.location = (x, y, z + sz / 2)
    return ob


def crag(name, x, y, z, sx, sy, sz, key='rock', seed=0, relief=0.34,
         subdiv=2, flat_base=True, smooth=False):
    """A rock: a sphere pushed around by noise until it is not one.

    ── Flat-shaded on purpose, and it is not the old flatness ──
    A smooth-shaded displaced sphere is a potato. The reference's stone is
    FACETED — every mass reads as a few big planes meeting at hard edges,
    which is exactly what flat shading on a displaced icosphere gives, and it
    is the opposite of a cuboid: the planes are at angles nothing else on the
    map has. So the style keeps its faceting; what changes is that the facets
    are no longer all at right angles to each other.

    subdiv 2 is 320 triangles, which is the whole point of the budget: enough
    for eight or ten readable planes per rock, few enough that they stay
    planes rather than becoming a surface.
    """
    verts, faces = _icosphere(subdiv)
    out = []
    for v in verts:
        n = _fbm(v.x * 1.6 + seed * 7.3, v.y * 1.6 + seed * 3.1,
                 v.z * 1.6 + seed * 5.7)
        r = 0.5 * (1.0 + relief * (n * 2.0 - 1.0))
        out.append([v.x * r * sx, v.y * r * sy, v.z * r * sz])
    if flat_base:
        # A rock sits ON the ground. A sphere touches it at one point and
        # every shadow under it comes out wrong.
        low = min(p[2] for p in out)
        cut = low + sz * 0.2
        for p in out:
            if p[2] < cut:
                p[2] = cut
    low = min(p[2] for p in out)
    for p in out:
        p[2] -= low
    ob = _mesh(name, [tuple(p) for p in out], faces, key, smooth=smooth,
               bevel=0.0)
    ob.location = (x, y, z)
    ob.rotation_euler = (0, 0, _hash01(f'{name}rot{seed}') * 6.283)
    return ob


def _ring_of(r, sides, ang0=0.0):
    return [(r * math.cos(2 * math.pi * i / sides + ang0),
             r * math.sin(2 * math.pi * i / sides + ang0), 0.0)
            for i in range(sides)]


def cyl(name, x, y, z, r, h, sides=16, key='oak', axis='z', taper=1.0,
        smooth=True, caps=True):
    """A cylinder — a pole, a spar, a shaft, a drum, a wheel.

    Smooth-shaded round the side and flat across the ends, which is what a
    turned or barked round thing actually looks like and what sixteen sides
    can carry. Below about twelve it reads as a prism again.
    """
    bot = _ring_of(r, sides)
    top = _ring_of(r * taper, sides)
    verts = [(a, b, 0.0) for a, b, _ in bot] + [(a, b, h) for a, b, _ in top]
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i)
             for i in range(sides)]
    if caps:
        faces.append(tuple(range(sides - 1, -1, -1)))
        faces.append(tuple(range(sides, 2 * sides)))
    ob = _mesh(name, verts, faces, key, smooth=smooth, bevel=0.0)
    if not smooth:
        pass
    elif caps:
        # The two end discs must stay flat or the whole thing looks inflated.
        for p in ob.data.polygons[-2:]:
            p.use_smooth = False
    ob.location = (x, y, z)
    if axis == 'x':
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == 'y':
        ob.rotation_euler = (-math.pi / 2, 0, 0)
    return ob


def ring(name, x, y, z, r, tube, key='steel', sides=20, tube_sides=8,
         axis='z'):
    """A torus — an iron band, a hoop, a tyre. What went round a post before
    this was a flat box, and a flat box round a round post is a collar of
    cardboard."""
    verts, faces = [], []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        cx, cy = r * math.cos(a), r * math.sin(a)
        for j in range(tube_sides):
            b = 2 * math.pi * j / tube_sides
            rr = tube * math.cos(b)
            verts.append((cx + rr * math.cos(a), cy + rr * math.sin(a),
                          tube * math.sin(b)))
    for i in range(sides):
        for j in range(tube_sides):
            a0 = i * tube_sides + j
            a1 = i * tube_sides + (j + 1) % tube_sides
            b0 = ((i + 1) % sides) * tube_sides + j
            b1 = ((i + 1) % sides) * tube_sides + (j + 1) % tube_sides
            faces.append((a0, a1, b1, b0))
    ob = _mesh(name, verts, faces, key, smooth=True, bevel=0.0)
    ob.location = (x, y, z)
    if axis == 'x':
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == 'y':
        ob.rotation_euler = (-math.pi / 2, 0, 0)
    return ob


def tube(name, pts, r=0.03, sides=7, key='root'):
    """A swept tube along a polyline: a rope, a chain, a cable, a hose.

    Every rope on the map is currently a column of little boxes, and a column
    of little boxes is the single most obvious tell in the whole render — real
    rope is round and it SAGS, and both of those are free here.
    """
    pts = [Vector(p) for p in pts]
    verts, faces = [], []
    up = Vector((0, 0, 1))
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
        if d.length < 1e-6:
            d = Vector((0, 0, 1))
        d.normalize()
        side = d.cross(up)
        if side.length < 1e-4:
            side = d.cross(Vector((1, 0, 0)))
        side.normalize()
        other = d.cross(side).normalized()
        for j in range(sides):
            a = 2 * math.pi * j / sides
            verts.append(tuple(p + side * (r * math.cos(a))
                               + other * (r * math.sin(a))))
    for i in range(len(pts) - 1):
        for j in range(sides):
            a0 = i * sides + j
            a1 = i * sides + (j + 1) % sides
            b0 = (i + 1) * sides + j
            b1 = (i + 1) * sides + (j + 1) % sides
            faces.append((a0, a1, b1, b0))
    return _mesh(name, verts, faces, key, smooth=True, bevel=0.0)


def catenary(name, p0, p1, sag=0.3, r=0.03, key='root', steps=9, sides=7):
    """A tube that hangs between two points instead of running straight.

    The sag is the whole point: a straight line between two posts is a wire,
    and everything in a quarry that is not a wire hangs.
    """
    a, b = Vector(p0), Vector(p1)
    pts = []
    for i in range(steps):
        f = i / (steps - 1)
        p = a.lerp(b, f)
        p.z -= sag * math.sin(math.pi * f)
        pts.append(p)
    return tube(name, pts, r=r, sides=sides, key=key)


def lathe(name, x, y, z, profile, sides=18, key='oak', smooth=True):
    """A revolved profile — a barrel, a pot, a drum, a bell, a wheel hub.

    [profile] is a list of (radius, height) going up. Everything round in the
    kit that is not a straight cylinder is one of these, and stacking slabs to
    fake it was costing four objects and still reading as a wedding cake.
    """
    verts, faces = [], []
    for r, hz in profile:
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append((r * math.cos(a), r * math.sin(a), hz))
    rings = len(profile)
    for k in range(rings - 1):
        for i in range(sides):
            a0 = k * sides + i
            a1 = k * sides + (i + 1) % sides
            b0 = (k + 1) * sides + i
            b1 = (k + 1) * sides + (i + 1) % sides
            faces.append((a0, a1, b1, b0))
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range((rings - 1) * sides, rings * sides)))
    ob = _mesh(name, verts, faces, key, smooth=smooth, bevel=0.0)
    for p in ob.data.polygons[-2:]:
        p.use_smooth = False
    ob.location = (x, y, z)
    return ob


# ── Joinery: the evidence that somebody built it ───────────
# Grain says what a thing is made of; these say that it was MADE. A beam with
# nothing holding it on is a shape the size of a beam — at map scale that reads
# as one solid mass however good the surface on it is, because the eye counts
# PARTS before it reads texture.
#
# Sized against the pieces they fasten, not against the map: a strap on a
# 0.11 spar is 0.14 across, and the bolt head on it is 0.04. Anything smaller
# than about 0.03 stops resolving and becomes render noise.


def strut(name, p0, p1, w=0.07, key='oak', d=None):
    """A member between two points in the x-z plane, at a fixed y.

    Everything braced is diagonal, and computing each brace's angle and centre
    by hand is how the first quarry ended up with its stays pointing at the
    sky. Give it the two ends it actually joins.
    """
    (x0, y0, z0), (x1, y1, z1) = p0, p1
    dx, dz = x1 - x0, z1 - z0
    length = math.hypot(dx, dz)
    ob = box(name, 0, 0, 0, length, d or w, w, mat(key))
    return _at(ob, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2,
               0, -math.atan2(dz, dx), 0)


def bolt(name, x, y, z, r=0.045, facing='y', key='steel_dark'):
    """One bolt head and its washer. Two boxes, and a strap stops being a
    painted stripe."""
    bw, bd = ((r * 2.4, r * 1.2) if facing == 'y' else (r * 1.2, r * 2.4))
    box(f'{name}_w', x, y, z, bw, bd, r * 2.4, mat('steel'))
    box(f'{name}_h', x, y, z + r * 0.4, r * 1.6, r * 1.6, r * 1.6, mat(key))


def strap(name, x, y, z, sx, sy, h=0.055, bolts=2, key='steel',
          round_=None):
    """An iron band right round a timber, with its bolts.

    The single most useful piece in the kit: it is what makes a stack of spars
    read as a bundle rather than as one fat post.

    Square by default, because most of what it goes round is sawn. Pass a
    radius and it becomes a real hoop instead — a flat box round a round post
    is a collar of cardboard, which is exactly what the crane's mast wore.
    """
    if round_:
        ring(f'{name}_r', x, y, z + h / 2, round_, h * 0.55, key=key)
        for i in range(max(2, bolts * 2)):
            a = 2 * math.pi * i / max(2, bolts * 2)
            bolt(f'{name}_bo{i}', x + round_ * math.cos(a),
                 y + round_ * math.sin(a), z + h / 2)
        return
    box(f'{name}_b', x, y, z, sx, sy, h, mat(key))
    box(f'{name}_s', x, y, z - 0.012, sx * 1.06, sy * 1.06, 0.014,
        mat('steel_dark'))
    for i in range(bolts):
        t = -sx / 2 + sx * (i + 0.5) / bolts
        bolt(f'{name}_bo{i}', x + t, y - sy / 2, z + h / 2)
    for i in range(bolts):
        t = -sy / 2 + sy * (i + 0.5) / bolts
        bolt(f'{name}_bx{i}', x + sx / 2, y + t, z + h / 2, facing='x')


def peg(name, x, y, z, r=0.05, facing='y', key='oak_light'):
    """A driven peg, proud of the face it went into. What holds timber to
    timber before anyone had bolts, and the reason a joint reads as a joint."""
    bw, bd = ((r * 1.5, r * 2.6) if facing == 'y' else (r * 2.6, r * 1.5))
    box(f'{name}_p', x, y, z, bw, bd, r * 1.5, mat(key))
    box(f'{name}_e', x, y - (r * 1.2 if facing == 'y' else 0),
        z, r * 1.7, r * 1.7, r * 1.7, mat('oak'))


def gusset(name, x, y, z, s=0.16, key='steel'):
    """The plate at a lattice node, with its four bolts. A truss without them
    is a pile of sticks that happen to touch."""
    for sy_ in (-1, 1):
        box(f'{name}_p{sy_}', x, y + sy_ * s * 0.42, z, s, 0.03, s, mat(key))
        for i, (ox, oz) in enumerate(((-0.28, -0.28), (0.28, -0.28),
                                      (0.0, 0.3))):
            box(f'{name}_b{sy_}{i}', x + ox * s, y + sy_ * s * 0.48,
                z + oz * s, 0.035, 0.03, 0.035, mat('steel_dark'))


def lashing(name, x, y, z, sx, sy, turns=4, key='straw'):
    """Rope wound round a joint. The other way timber is held together, and
    the only one that reads as SOFT against all that iron."""
    for i in range(turns):
        f = 1.0 + 0.05 * (i % 2)
        box(f'{name}_t{i}', x, y, z + i * 0.045, sx * f, sy * f, 0.038,
            mat(key if i % 2 else 'root'))


def sheave(name, x, y, z, r=0.13, key='oak_light'):
    """A pulley block: two cheeks, a grooved wheel between them, a pin.

    Every rope on the map currently ends in a box. A block is what a rope runs
    OVER, and it is the difference between a hanging line and lifting gear.
    """
    for s_ in (-1, 1):
        box(f'{name}_ch{s_}', x, y + s_ * (r * 0.5), z, r * 1.5, r * 0.3,
            r * 2.1, mat('oak'))
        box(f'{name}_st{s_}', x, y + s_ * (r * 0.52), z + r * 0.75,
            r * 1.6, r * 0.16, 0.05, mat('steel'))
    wheel = lathe(f'{name}_w', x, y, z + r,
                  [(r * 0.2, -r * 0.24), (r * 0.98, -r * 0.2),
                   (r * 0.82, 0.0), (r * 0.98, r * 0.2),
                   (r * 0.2, r * 0.24)], sides=18, key=key)
    wheel.rotation_euler = (math.pi / 2, 0, 0)
    box(f'{name}_pin', x, y, z + r * 0.92, 0.05, r * 1.5, 0.05,
        mat('steel_dark'))
    box(f'{name}_hook', x, y, z - r * 0.5, 0.06, 0.06, r * 0.7,
        mat('steel_dark'))
    box(f'{name}_bar', x, y, z - r * 0.72, r * 0.9, 0.06, 0.06,
        mat('steel_dark'))


def winch(name, x, y, z, r=0.2, wide=0.5, key='oak'):
    """A drum, its ratchet, its pawl and a crank — the machine, not a barrel.

    A quarry crane's whole point is that one person can lift a block, and the
    ratchet is what says so: it is the part that means the load stays up when
    they let go.
    """
    for s_ in (-1, 1):
        box(f'{name}_bear{s_}', x, y + s_ * (wide / 2 + 0.09), z, 0.2, 0.14,
            r * 2.1, mat('oak'))
        box(f'{name}_cap{s_}', x, y + s_ * (wide / 2 + 0.09), z + r * 1.7,
            0.24, 0.18, 0.07, mat('steel'))
    # The drum: staves, not a cylinder, because it is a barrel of oak.
    for i in range(12):
        a = 2 * math.pi * i / 12
        _at(box(f'{name}_st{i}', 0, 0, 0, 2 * math.pi * r / 12 * 1.15,
                wide, 0.055, mat(key if i % 2 else 'oak_light')),
            x + r * 0.86 * math.cos(a), y, z + r + r * 0.86 * math.sin(a),
            0, _tan_y(a), 0)
    for s_ in (-1, 1):
        for i in range(12):
            a = 2 * math.pi * i / 12
            _at(box(f'{name}_fl{s_}{i}', 0, 0, 0,
                    2 * math.pi * r / 12 * 1.2, 0.05, 0.06, mat('steel')),
                x + r * math.cos(a), y + s_ * wide / 2, z + r + r * math.sin(a),
                0, _tan_y(a), 0)
    # The rope, in visible turns across the drum.
    for i in range(7):
        t = -wide / 2 + wide * (i + 0.5) / 7
        ring(f'{name}_rp{i}', x, y + t, z + r, r * 1.0, wide / 7 * 0.42,
             key='root' if i % 2 else 'straw', axis='y', sides=16,
             tube_sides=6)
    # The ratchet wheel and the pawl that holds it.
    rw = r * 0.72
    for i in range(11):
        a = 2 * math.pi * i / 11
        _at(box(f'{name}_tooth{i}', 0, 0, 0, 0.09, 0.06, 0.07,
                mat('steel')),
            x + rw * math.cos(a), y - wide / 2 - 0.05,
            z + r + rw * math.sin(a), 0, _tan_y(a), 0)
    box(f'{name}_rdisc', x, y - wide / 2 - 0.05, z + r - rw * 0.7,
        rw * 1.3, 0.05, rw * 1.4, mat('steel_dark'))
    pawl = box(f'{name}_pawl', x + rw * 0.9, y - wide / 2 - 0.09,
               z + r + rw * 0.5, 0.28, 0.06, 0.06, mat('steel_dark'))
    pawl.rotation_euler = (0, 0.7, 0)
    box(f'{name}_pivot', x + rw * 1.5, y - wide / 2 - 0.09, z + r + rw * 1.0,
        0.07, 0.07, 0.07, mat('steel'))
    # The crank: a shaft, an offset arm and a grip worn smooth.
    box(f'{name}_shaft', x, y, z + r, 0.07, wide + 0.5, 0.07,
        mat('steel_dark'))
    box(f'{name}_arm', x + 0.13, y + wide / 2 + 0.2, z + r, 0.3, 0.07, 0.07,
        mat('steel'))
    box(f'{name}_grip', x + 0.26, y + wide / 2 + 0.2, z + r - 0.11, 0.08,
        0.08, 0.24, mat('oak_light'))



# ── Quarry: living rock, and the gear that eats it ─────────
# A different vocabulary from the rest of the file on purpose. Everything else
# here is BUILT — courses, beams, bays, all of it regular because somebody laid
# it. Rock is the one material nobody laid, so none of the regular kit applies:
# no coursing, no joints, no repeated module. What replaces them is size
# variation and a hard dark seam wherever two masses meet.


def boulder(name, x, y, z, sx, sy, sz, key='rock', seed=0):
    """One irregular mass — a displaced solid, and its shadow on the ground.

    ── Was six boxes, is one rock (user 2026-08-12) ──
    "Das Bild zeigt ein Realismus, du machst Pixelart mit Klötzen."

    The old version stacked a core, a second mass turned the other way, two
    cap plates and a weathered patch — five cuboids arranged to fake an
    outline no cuboid has. It worked as far as silhouette and could never
    work any further, because every surface in it was still a face of a box.

    crag() is the actual shape: an icosphere pushed around by three octaves of
    noise, flat-shaded so the style keeps its facets, but facets at angles
    nothing square can produce. One object instead of five, and it holds up at
    a zoom the stack never survived.

    The name stays because eight builders call it.
    """
    skirt = box(f'{name}_g', x, y, z, sx * 1.1, sy * 1.1, 0.05,
                mat('rock_deep'))
    skirt.rotation_euler = (0, 0, (_hash01(f'{name}a{seed}') - 0.5) * 0.9)
    core = crag(f'{name}_c', x, y, z + 0.03, sx * 1.1, sy * 1.1, sz * 1.12,
                key=key, seed=seed, relief=0.36)
    if seed % 4 == 0:
        # Every fourth mass weathered warm, so the face is not one colour.
        crag(f'{name}_w', x + (_hash01(f'{name}b{seed}') - 0.5) * sx * 0.4,
             y - sy * 0.3, z + sz * 0.3, sx * 0.5, sy * 0.42, sz * 0.5,
             key='rock_warm', seed=seed + 50, relief=0.42)
    return core


def rock_wall(name, pts, key='rock'):
    """A run of boulders along a line of (x, y, width, depth, height) points.

    Authored as a list rather than a formula: the whole point of a quarry face
    is that no two masses are the same, and a loop with a sine in it makes a
    wave, not a cliff.
    """
    for i, (bx, by, bw, bd, bh) in enumerate(pts):
        boulder(f'{name}{i}', bx, by, 0, bw, bd, bh,
                key='rock_shade' if i % 3 == 2 else key, seed=i)
        # A second, smaller mass leaning on the first. One displaced solid is
        # still convex, and the deep shadow in a quarry face lives in the
        # re-entrant corner between two masses that no single solid has.
        j = _hash01(f'{name}two{i}')
        crag(f'{name}x{i}', bx + (j - 0.5) * bw * 0.62,
             by + (_hash01(f'{name}thr{i}') - 0.5) * bd * 0.5, 0.02,
             bw * 0.72, bd * 0.78, bh * (0.6 + 0.34 * j),
             key='rock_shade' if i % 3 != 2 else key, seed=i + 120,
             relief=0.4)


def cave_mouth(name, x, y, z, w=1.5, hh=1.25, depth=0.9):
    """The hole the stone comes out of, timbered the way a heading is.

    The dark is the point — nothing else on the map is allowed to be this
    black. What holds it open is a set: two legs on sole plates, wedges driven
    under them, a cap across, and lagging boards behind the cap taking the
    weight of the roof. A prop with none of that is a stick near a hole.
    """
    box(f'{name}_dark', x, y, z, w, depth, hh, mat('rock_deep'))
    box(f'{name}_void', x, y + 0.1, z, w * 0.86, depth, hh * 0.94, mat('dark'))
    for s_ in (-1, 1):
        px = x + s_ * (w / 2 - 0.09)
        py = y - depth / 2 + 0.06
        box(f'{name}_sole{s_}', px, py, z, 0.32, 0.34, 0.09, mat('oak_light'))
        for k in (-1, 1):
            wg = box(f'{name}_wg{s_}{k}', px + k * 0.09, py, z + 0.09, 0.14,
                     0.26, 0.06, mat('oak'))
            wg.rotation_euler = (0, k * 0.16, 0)
        box(f'{name}_prop{s_}', px, py, z + 0.15, 0.19, 0.24, hh * 0.88,
            mat('oak'))
        for i in range(3):
            strap(f'{name}_pb{s_}{i}', px, py, z + 0.35 + i * hh * 0.28,
                  0.24, 0.28, h=0.05, bolts=1)
        box(f'{name}_head{s_}', px, py, z + 0.15 + hh * 0.88, 0.3, 0.3, 0.1,
            mat('oak_light'))
        peg(f'{name}_hp{s_}', px, py - 0.16, z + 0.2 + hh * 0.88)
    cap_z = z + 0.25 + hh * 0.88
    box(f'{name}_cap', x, y - depth / 2 + 0.04, cap_z, w + 0.38, 0.28, 0.19,
        mat('oak'))
    box(f'{name}_cap2', x, y - depth / 2 - 0.05, cap_z + 0.19, w + 0.18, 0.2,
        0.12, mat('oak_light'))
    for i in range(4):
        bolt(f'{name}_cb{i}', x - w / 2 + (i + 0.5) * w / 4,
             y - depth / 2 - 0.15, cap_z + 0.06)
    # Lagging: the boards behind the cap that actually hold the roof up.
    for i in range(5):
        box(f'{name}_lag{i}', x - w / 2 + (i + 0.5) * w / 5, y + 0.04,
            cap_z + 0.31, w / 5 * 0.86, depth * 0.8, 0.09,
            mat('oak_light' if i % 2 else 'oak'))
    for i in range(3):
        box(f'{name}_peg{i}', x - w / 2 + (i + 0.7) * w / 3,
            y - depth / 2 - 0.12, cap_z + 0.34, 0.09, 0.09, 0.17,
            mat('steel'))












def rails(name, x, y, z, span, axis='y', ties=7):
    """Sleepers and two rails. The one thing in the picture that says the stone
    LEAVES on something, and it costs two boxes a sleeper."""
    for i in range(ties):
        t = -span / 2 + span * (i + 0.5) / ties
        tx, ty = ((x + t, y) if axis == 'x' else (x, y + t))
        tw, td = ((span / ties * 0.5, 0.72) if axis == 'x'
                  else (0.72, span / ties * 0.5))
        box(f'{name}_tie{i}', tx, ty, z, tw, td, 0.07,
            mat('oak' if i % 2 else 'oak_light'))
    for s in (-1, 1):
        rx, ry = ((x, y + s * 0.24) if axis == 'x' else (x + s * 0.24, y))
        rw, rd = ((span, 0.07) if axis == 'x' else (0.07, span))
        box(f'{name}_r{s}', rx, ry, z + 0.07, rw, rd, 0.07, mat('steel'))


def mine_cart(name, x, y, z, axis='y', load='rock'):
    """A tub on four wheels, heaped and rimmed.

    The wheels have to be WHEELS. At 0.1 across they were four dark specks and
    the cart read as a crate lying in the dirt; a quarter-unit disc under each
    corner is what makes it a thing that moves, which is the only reason the
    rails underneath mean anything.
    """
    bw, bd = ((0.52, 0.78) if axis == 'y' else (0.78, 0.52))
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            wx = x + sx_ * (bw / 2 + 0.03)
            wy = y + sy_ * (bd / 2 - 0.14)
            for i in range(8):
                a = 2 * math.pi * i / 8
                _at(box(f'{name}_w{sx_}{sy_}{i}', 0, 0, 0, 0.05, 0.1, 0.07,
                        mat('steel' if i % 2 else 'steel_dark')),
                    wx, wy + 0.13 * math.cos(a), z + 0.13 + 0.13 * math.sin(a),
                    _tan_x(a), 0, 0)
            box(f'{name}_hub{sx_}{sy_}', wx, wy, z + 0.09, 0.09, 0.11, 0.09,
                mat('steel_dark'))
    box(f'{name}_axle', x, y, z + 0.11, bw + 0.14, bd * 0.6, 0.06,
        mat('steel_dark'))
    box(f'{name}_frame', x, y, z + 0.2, bw + 0.08, bd + 0.06, 0.09,
        mat('oak'))
    for i, (f, hz) in enumerate(((0.96, 0.22), (1.14, 0.2))):
        box(f'{name}_tub{i}', x, y, z + 0.29 + i * 0.22, bw * f, bd * f, hz,
            mat('oak_light' if i % 2 else 'oak'))
    box(f'{name}_rim', x, y, z + 0.7, bw * 1.2, bd * 1.2, 0.06, mat('steel'))
    box(f'{name}_dark', x, y, z + 0.66, bw * 1.0, bd * 1.0, 0.05, mat('dark'))
    for i in range(4):
        j = _hash01(f'{name}{i}')
        box(f'{name}_load{i}', x + (j - 0.5) * bw * 0.66,
            y + (_hash01(f'{name}q{i}') - 0.5) * bd * 0.66, z + 0.7,
            0.19 + 0.1 * j, 0.18 + 0.09 * j, 0.13 + 0.1 * j,
            mat('rock_light' if i % 2 else load))


def jib_crane(name, x, y, z, hh=2.6, reach=1.5, load='rock', foot=True,
             flag=True):
    """A treadle-less quarry derrick, built the way one is built.

    ── Twenty-five boxes was not a crane (user 2026-08-12) ──
    "Der Kran besteht aus wenigen Einzelteilen. Dies sollte viel viel
    detaillierter sein."

    A mast, a stick and a barrel gave the right silhouette and nothing else:
    at any zoom close enough to see the grain, there was nothing for the grain
    to be ON — no spars, no bands, no joints, no gear. The eye counts PARTS
    before it reads texture, so a smooth surface on a shape with four parts
    reads as one solid mass however good the surface is.

    Built now the way a timber derrick actually is: four spars banded into a
    mast, raking braces pegged into a laid stone pad, a lattice jib with a
    gusset at every node, a head block with a real sheave, and a winch with a
    ratchet and a pawl — because the ratchet is the part that says one person
    can lift a block and let go of the handle.

    ── foot (user 2026-08-16) ──
    False drops everything that assumes the crane plants into open ground —
    the stone pad, the raking braces pegged into it, the winch a ground crew
    would turn, the guy wires staked to rock anchors. For a crane mounted on
    a rooftop turret ("es braucht nur den oberen Teil des Krans und nicht
    alles") none of that has anything to stand IN; only the mast up, the
    jib, and the counterweight tail belong there.

    ── flag (user 2026-08-16) ──
    False drops the banner at the mast's own midpoint ("Kran ohne Flagge").
    """
    ang = 0.44                                   # the jib's rake
    top = z + 0.2 + hh
    spread = 0.1

    if foot:
        # ── The pad: laid blocks, and it is what the whole thing stands on
        for i, (ox, oy) in enumerate(((-0.3, -0.3), (0.3, -0.3),
                                      (-0.3, 0.3), (0.3, 0.3))):
            box(f'{name}_pad{i}', x + ox, y + oy, z, 0.56, 0.56, 0.2,
                mat('rock_light' if i % 2 else 'rock'))
            box(f'{name}_pads{i}', x + ox, y + oy, z, 0.6, 0.6, 0.04,
                mat('rock_deep'))

    # ── The mast: FOUR spars, banded ──
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            box(f'{name}_sp{sx_}{sy_}', x + sx_ * spread, y + sy_ * spread,
                z + 0.2, 0.115, 0.115, hh,
                mat('oak' if sx_ * sy_ > 0 else 'oak_light'))
    for i in range(7):
        bz = z + 0.34 + i * (hh - 0.3) / 6
        strap(f'{name}_bd{i}', x, y, bz, 0.34, 0.34, bolts=2)
    box(f'{name}_cap', x, y, top - 0.04, 0.42, 0.42, 0.1, mat('oak'))
    strap(f'{name}_cbd', x, y, top - 0.12, 0.4, 0.4, h=0.07, bolts=3)

    if foot:
        # ── The braces: raking, into the pad, pegged at both ends ──
        for i, (dx_, dy_) in enumerate(((-1, 0), (1, 0), (0, -1), (0, 1))):
            foot_pt = (x + dx_ * 0.62, y + dy_ * 0.62, z + 0.2)
            head = (x + dx_ * 0.16, y + dy_ * 0.16, z + 0.2 + hh * 0.52)
            if dy_:
                # A y-facing brace is drawn in its own plane, so it needs
                # the rotation the x-z helper cannot give it.
                length = math.hypot(0.46, hh * 0.52)
                ob = box(f'{name}_br{i}', 0, 0, 0, 0.09, length, 0.09,
                         mat('oak_light'))
                _at(ob, (foot_pt[0] + head[0]) / 2, (foot_pt[1] + head[1]) / 2,
                    (foot_pt[2] + head[2]) / 2,
                    dy_ * math.atan2(hh * 0.52, 0.46) - dy_ * math.pi / 2, 0,
                    0)
            else:
                strut(f'{name}_br{i}', foot_pt, head, w=0.09, key='oak_light')
            box(f'{name}_shoe{i}', foot_pt[0], foot_pt[1], z + 0.2, 0.2, 0.2,
                0.14, mat('steel'))
            peg(f'{name}_pg{i}', foot_pt[0], foot_pt[1] - 0.11, z + 0.28,
                facing='y' if dx_ else 'x')
            lashing(f'{name}_ls{i}', head[0], head[1], head[2] - 0.08, 0.2,
                    0.2, turns=3)

    # ── The jib: a lattice, not a stick ──
    def along(t, off=0.0):
        """A point t along the jib, off perpendicular to it."""
        return (x - t * math.cos(ang) - off * math.sin(ang), y,
                top + t * math.sin(ang) + off * math.cos(ang))

    # Short enough that the load hangs over open floor: at 1.55 the jib
    # swung it into the middle of the rock face, where a lifted block is
    # indistinguishable from a boulder.
    length = reach * 1.2
    for sy_ in (-1, 1):
        yy = y + sy_ * 0.1
        for off, w_ in ((0.13, 0.075), (-0.11, 0.075)):
            a0, a1 = along(0.05, off), along(length, off)
            strut(f'{name}_ch{sy_}{off}',
                  (a0[0], yy, a0[2]), (a1[0], yy, a1[2]), w=w_)
    # The web: diagonals, alternating, with a plate at every node.
    nodes = 6
    for i in range(nodes):
        t0 = 0.1 + (length - 0.2) * i / nodes
        t1 = 0.1 + (length - 0.2) * (i + 1) / nodes
        hi, lo = (0.13, -0.11) if i % 2 else (-0.11, 0.13)
        for sy_ in (-1, 1):
            yy = y + sy_ * 0.1
            p0, p1 = along(t0, hi), along(t1, lo)
            strut(f'{name}_web{sy_}{i}', (p0[0], yy, p0[2]),
                  (p1[0], yy, p1[2]), w=0.055, key='oak')
        px, _, pz = along(t0, hi)
        gusset(f'{name}_gu{i}', px, y, pz, s=0.15)
        # Cross-ties between the two side frames, so it reads as a box truss.
        cx_, _, cz_ = along(t0, -0.11)
        box(f'{name}_tie{i}', cx_, y, cz_, 0.055, 0.24, 0.055,
            mat('oak_light'))

    # ── The head: a block, a sheave, and the rope over it ──
    hx_, _, hz_ = along(length, 0.0)
    box(f'{name}_headb', hx_, y, hz_ - 0.02, 0.26, 0.3, 0.2, mat('oak'))
    strap(f'{name}_headbd', hx_, y, hz_ + 0.16, 0.28, 0.32, bolts=2)
    sheave(f'{name}_hsh', hx_ - 0.02, y, hz_ - 0.28, r=0.11)

    # ── The tail: a counterweight of rubble in a slung crate ──
    tx_, _, tz_ = along(-reach * 0.62, 0.0)
    strut(f'{name}_tail', (x - 0.08, y, top - 0.1), (tx_, y, tz_), w=0.1,
          key='oak')
    for sy_ in (-1, 1):
        box(f'{name}_cw{sy_}', tx_, y + sy_ * 0.16, tz_ - 0.3, 0.36, 0.05,
            0.34, mat('oak_light'))
    box(f'{name}_cwb', tx_, y, tz_ - 0.46, 0.4, 0.36, 0.06, mat('oak'))
    strap(f'{name}_cwbd', tx_, y, tz_ - 0.2, 0.38, 0.36, bolts=2)
    for i in range(4):
        j = _hash01(f'{name}cw{i}')
        boulder(f'{name}_cwr{i}', tx_ + (j - 0.5) * 0.22,
                y + (_hash01(f'{name}cx{i}') - 0.5) * 0.22, tz_ - 0.42,
                0.16 + 0.06 * j, 0.15 + 0.05 * j, 0.13 + 0.06 * j, seed=60 + i)
    for s_ in (-1, 1):
        strut(f'{name}_stay{s_}', (x + s_ * 0.02, y, top + 0.14),
              (tx_, y, tz_ + 0.06), w=0.045, key='steel')

    # ── The fall: rope, hook block, and whatever is in the sling ──
    # One rope is ONE rope: it used to alternate 'straw'/'root' every
    # segment, which read as a barber pole rather than a single line
    # (user 2026-08-16: "Das Seil soll durchgehend sein und in der gleichen
    # Farbe"). And the load hangs closer to the head now — 'lift' raises
    # the whole hook/sling/cargo assembly off the ground it used to sit
    # almost on top of (user 2026-08-16: "Den Stein bitte etwas höher
    # nehmen, welcher am Seil hängt").
    lift = 0.55
    fall_bot = z + 0.9 + lift
    fall_top = hz_ - 0.36
    for i in range(6):
        box(f'{name}_fall{i}', hx_ - 0.02, y, fall_bot + i * (fall_top - fall_bot) / 6,
            0.05, 0.05, (fall_top - fall_bot) / 6 * 0.9, mat('root'))
    sheave(f'{name}_bsh', hx_ - 0.02, y, z + 0.62 + lift, r=0.1)
    # ── What is on the hook: the same derrick lifts a boulder in the quarry
    # and a trunk in the yard — only the sling's cargo says which ──
    if load == 'log':
        cyl(f'{name}_load', hx_ - 0.02, y, z + 0.2 + lift, 0.2, 0.7, sides=10,
            axis='x', key='oak')
        for s_ in (-1, 1):
            ring(f'{name}_loadb{s_}', hx_ - 0.02 + s_ * 0.24, y, z + 0.2 + lift,
                 0.205, 0.022, key='root', sides=10, tube_sides=5, axis='x')
    else:
        boulder(f'{name}_load', hx_ - 0.02, y, z + 0.2 + lift, 0.46, 0.44, 0.4,
                seed=7)
    for s_ in (-1, 1):
        strut(f'{name}_sl{s_}', (hx_ - 0.02, y + s_ * 0.05, z + 0.56 + lift),
              (hx_ - 0.02 + s_ * 0.2, y + s_ * 0.22, z + 0.24 + lift), w=0.04,
              key='root')

    if foot:
        # ── The winch, at the foot, where a person can reach it ──
        winch(f'{name}_win', x + 0.04, y - 0.62, z + 0.24, r=0.2, wide=0.46)
        for s_ in (-1, 1):
            strut(f'{name}_wl{s_}', (x + s_ * 0.26, y - 0.62, z + 0.2),
                  (x + s_ * 0.16, y - 0.34, z + 0.62), w=0.07, key='oak')

        # ── Guys to ground anchors, because a derrick is stayed ──
        for i, (gx_, gy_) in enumerate(((0.95, -0.5), (0.55, 0.9))):
            ax_, ay_ = x + gx_, y + gy_
            strut(f'{name}_guy{i}', (x + 0.06, y, top - 0.2),
                  (ax_, ay_, z + 0.3), w=0.04, key='root')
            box(f'{name}_anch{i}', ax_, ay_, z, 0.24, 0.24, 0.26, mat('rock'))
            peg(f'{name}_gp{i}', ax_, ay_ - 0.14, z + 0.24)
    if flag:
        banner(f'{name}_flag', x, y - 0.24, z + 0.2 + hh * 0.5, 0.34, 0.62,
               key='cloth_blue')


def ladder(name, x, y, z, hh=1.6, lean=0.22, axis='y', rungs=6):
    """Two stiles and some rungs, leaned against something. Every level of the
    reference is reachable, and that is what makes it read as WORKED."""
    for s in (-1, 1):
        sx_, sy_ = ((x + s * 0.19, y) if axis == 'y' else (x, y + s * 0.19))
        st = box(f'{name}_st{s}', sx_, sy_, z, 0.08, 0.08, hh, mat('oak'))
        st.rotation_euler = ((lean, 0, 0) if axis == 'y' else (0, -lean, 0))
    for i in range(rungs):
        f = (i + 0.5) / rungs
        rx = x + (0 if axis == 'y' else math.sin(lean) * hh * (f - 0.5))
        ry = y - (math.sin(lean) * hh * (f - 0.5) if axis == 'y' else 0)
        rw, rd = ((0.44, 0.06) if axis == 'y' else (0.06, 0.44))
        box(f'{name}_r{i}', rx, ry, z + hh * f, rw, rd, 0.05,
            mat('oak_light'))


def stage(name, x, y, z, sx, sy, posts=True, key='oak'):
    """A plank platform on posts. The reference has three of them at three
    heights, and stacking the work is what gives a flat hole a section."""
    n = max(3, int(sx / 0.26))
    for i in range(n):
        box(f'{name}_p{i}', x - sx / 2 + sx * (i + 0.5) / n, y, z,
            sx / n * 0.88, sy, 0.09,
            mat('oak_light' if i % 2 else key))
    box(f'{name}_beam', x, y - sy / 2 + 0.06, z - 0.1, sx + 0.16, 0.14, 0.14,
        mat(key))
    box(f'{name}_rail', x, y - sy / 2, z + 0.42, sx, 0.07, 0.07,
        mat('oak_light'))
    for i in range(3):
        box(f'{name}_bal{i}', x - sx / 2 + sx * (i + 0.5) / 3, y - sy / 2,
            z + 0.09, 0.08, 0.08, 0.36, mat(key))
    if posts:
        for s in (-1, 1):
            box(f'{name}_post{s}', x + s * (sx / 2 - 0.12), y, z - 0.1, 0.16,
                0.16, -z + 0.1 if z > 0.2 else 0.2, mat(key))


# ── The buildings ──────────────────────────────────────────
# Each preset gets the footprint it has in the roster and builds itself inside
# it. NOTHING may cross the base except a roof overhang — the same rule the art
# contract states, here enforced by the modelling rather than hoped for.
def egg(name, x, y, z, r, mat):
    """An egg. Was the last builder in the file still calling bpy.ops — and
    the Hatchery draws nine of them, each one an undo step and a full scene
    re-evaluation for a shape orb() makes from vertices."""
    ob = orb(name, x, y, z, r * 2, r * 2, r * 2.7, smooth=True, subdiv=2,
             mtl=mat)
    ob.rotation_euler = (0, math.radians(9), 0)
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
                   course=0.0763, block=0.149)
    half_timber('hlow', hx, hy, base_h, hw, hd, floor_h, bays=5)
    jetty('hjet', hx, hy, base_h + floor_h, hw, hd, out=0.17)
    up_w, up_d = hw + 0.34, hd + 0.34
    half_timber('hup', hx, hy, base_h + floor_h + 0.1, up_w, up_d, upper_h,
                bays=5)
    roof_z = base_h + floor_h + 0.1 + upper_h
    shingle_gable('hroof', hx, hy, roof_z, up_w, up_d, 1.24, overhang=0.26,
                  rows=24, ridge_along='y')
    moss('hmoss', hx, hy, roof_z, up_w * 0.8, up_d * 0.8, 0.7,
         overhang=0.0, patches=12)
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
               planks=7)
    steps('hsteps', door_x, low_face - 0.12, 0, 0.9, count=3, rise=0.09)
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
                   course=0.0713, block=0.139)
    half_timber('wlow', wx, wy, 0.26, ww, wd, 1.02, bays=4)
    w_roof_z = 1.28
    shingle_gable('wroof', wx, wy, w_roof_z, ww, wd, 0.86, overhang=0.24,
                  rows=18, ridge_along='x')
    moss('wmoss', wx, wy, w_roof_z, ww * 0.8, wd * 0.8, 0.5, overhang=0.0,
         patches=8)
    w_face = wy - wd / 2
    doorway('wdoor', wx + 0.1, w_face, 0.26, 0.5, 0.62, rim=0.13)
    plank_door('wleaf', wx + 0.1, w_face - 0.05, 0.28, 0.44, 0.36, planks=5)
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
               0.44, 0.4, planks=5)
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

    # ── Eigenleben (user 2026-08-09) ──
    # This is where the creatures come FROM, and until now the only sign of
    # that was a heap of straw. A pen with something in it, a nest with an egg
    # in it, and the fire that keeps both warm.
    for i, (ox, oy, k, sc) in enumerate(((0.55, -half + 0.85, 0, 1.0),
                                         (1.15, -half + 0.6, 2, 0.72),
                                         (-0.15, -half + 0.55, 1, 0.62))):
        critter(f'bcrit{i}', ox, oy, 0, angle=0.4 + i * 1.7, kind=k, scale=sc)
    for i in range(2):
        fowl(f'bfowl{i}', -half + 0.75 + i * 0.5, -half + 1.5, 0,
             angle=0.8 + i * 2.1, kind=i)
    # A pen the young are kept in — withies, straw, a trough and a nest.
    px_, py_ = half - 1.05, -half + 1.15
    withy_fence('bpen0', px_, py_ - 0.62, 0, 1.5, h=0.42, axis='x')
    withy_fence('bpen1', px_ + 0.75, py_, 0, 1.25, h=0.42, axis='y')
    straw_scatter('bpenstraw', px_, py_, 0, 0.6, n=14)
    nest('bpennest', px_ - 0.25, py_ + 0.2, 0, 0.24)
    egg('bpenegg', px_ - 0.25, py_ + 0.2, 0.02, 0.16, mat('egg_uncommon'))
    trough('bpentr', px_ + 0.3, py_ - 0.3, 0, 0.42, 0.24, key='oak')
    critter('bpenpup', px_ + 0.1, py_ + 0.55, 0, angle=2.4, kind=1, scale=0.55)
    washing('bwash', -half + 1.35, half - 0.95, 0, 1.5, axis='x', h=0.95)
    basket('bbask0', -0.35, -half + 0.5, 0, fill='straw')
    basket('bbask1', -0.72, -half + 0.62, 0, r=0.14, h=0.22, fill='leaf')
    beehive('bbee', -half + 0.6, 0.55, 0)
    # Accent: PINK and WHITE — the house the creatures come from.
    flower_bed('bbed0', -half + 0.62, -half + 2.1, 0, 0.66, 0.42,
               bloom='bloom_pink', n=7)
    flower_bed('bbed1', half - 0.65, half - 0.6, 0, 0.55, 0.36,
               bloom='bloom_white', n=5)
    window_box('bwb', hx + 0.35, hy - hd / 2 - 0.1, base_h + 0.62,
               0.5, bloom='bloom_pink')
    for i, ty in enumerate((0.3, 1.1)):
        perch_bird(f'bbird{i}', hx + 0.3 - i * 0.6, hy - hd / 2 - 0.22,
                   roof_z + 1.1 + (i % 2) * 0.06, kind=i)


# The footprint every number in _main_hall_plan is measured against. The
# builder's own comment picked it ("6 x 6 rather than 5 x 5, and the extra tile
# goes into HEIGHT") and then nothing ever passed it: castle was called with
# the def's 5 x 5 and drew a 6 x 6 castle on it.
MAIN_HALL_PLAN = 6.0


def castle(w, h):
    """The Keep, drawn to its own plan and scaled onto the tile it is given.

    See MAIN_HALL_PLAN. Everything below is authored at 6 x 6; a settlement
    whose main building is 5 x 5 gets the same castle at five sixths, rather
    than the same castle overflowing by a sixth.
    """
    _main_hall_plan(MAIN_HALL_PLAN, MAIN_HALL_PLAN)
    k = min(w, h) / MAIN_HALL_PLAN
    if abs(k - 1.0) > 1e-6:
        scale_all(k)


def _main_hall_plan(w, h):
    """The Keep: the settlement's stronghold, and the middle of its map.

    ── Why it is a CASTLE and not a big house (user 2026-08-04) ──
    The first version was the Hatchery's kit at twice the size, and that is
    exactly how it read: a large half-timbered house. Scale alone does not make
    a landmark, because every building on the map is the same style and the eye
    has nothing to measure against except the others.

    Four changes carry it, in order of how much work they do:

      * STONE, not timber. A frame says farm; coursed ashlar says fortress, and
        it is the same ashlar_courses the Hatchery uses for its plinth — the
        material is shared, the amount of it is not.
      * BATTLEMENTS. Nothing else says fortress so cheaply: a wall is a wall
        until its top is notched.
      * TWO towers flanking a GATEHOUSE. One tower is a manor; a pair with a
        gate between them is the front of a castle, and the gap is what the
        eye reads as "the way in".
      * ARROW SLITS instead of windows. Narrow is not only fiction: at 256 px a
        slit is a dark line that reads as a slit, where a shrunken leaded
        window is a smudge.

    What is deliberately kept from the Hatchery: the palette, the shingles, the
    oak trim, the moss, the tufts of grass. A castle in a DIFFERENT colour
    family would be a second world again — the thing that was just cleaned up.
    """
    half = w / 2.0

    # ── The keep ──
    # ── BIGGER AND GRANDER (user 2026-08-04) ──
    # 6 x 6 rather than 5 x 5, and the extra tile goes into HEIGHT more than
    # width: a castle that spreads reads as a compound, one that rises reads as
    # a stronghold. The keep's wall alone is now taller than the whole
    # Hatchery, which is the comparison that does the work on the map.
    # Wider and one step taller again: the woodpile's corner and the slack
    # around the bailey go into the KEEP, which is the only part of this
    # building whose size a player reads from across the map.
    kx, ky = -0.1, 1.45
    kw, kd = 4.35, 3.1
    wall_h = 3.45
    ashlar_courses('kbase', kx, ky, 0, kw + 0.2, kd + 0.2, 0.36,
                   course=0.0922, block=0.1786)
    ashlar_courses('kwall', kx, ky, 0.36, kw, kd, wall_h,
                   course=0.1073, block=0.2088)
    # A string course two thirds up: the same trick as the Hatchery's, and the
    # only thing that stops three metres of masonry reading as one grey slab.
    string_course('kband', kx, ky, 0.36 + wall_h * 0.62, kw + 0.02, kd + 0.02)
    battlements('kcrown', kx, ky, 0.36 + wall_h, kw, kd, h=0.34)

    roof_z = 0.36 + wall_h + 0.44
    shingle_gable('kroof', kx, ky, roof_z, kw - 0.5, kd - 0.5, 1.05,
                  overhang=0.18, rows=24, ridge_along='x')
    moss('kmoss', kx, ky, roof_z, kw * 0.7, kd * 0.7, 0.6, overhang=0.0,
         patches=12)
    chimney('kchim', kx - 1.15, ky + 0.55, 0, 0.42, roof_z + 1.15)

    face_y = ky - kd / 2
    for i, ox in enumerate((-1.0, -0.35, 0.35, 1.0)):
        arrow_slit(f'ks{i}', kx + ox, face_y, 1.5, 0.58)
    for i, oy in enumerate((-0.55, 0.25)):
        arrow_slit(f'kse{i}', kx + kw / 2, ky + oy, 1.5, 0.58, facing='x')
    for i, ox in enumerate((-0.7, 0.7)):
        arrow_slit(f'ksb{i}', kx + ox, ky + kd / 2, 1.5, 0.58)
    # One real window, high and central: the hall behind it is where the
    # settlement is run from, and a keep with NO glass reads as a ruin.
    leaded_window('kwin', kx, face_y, 2.05, 0.36, 0.44)
    banner('kflag', kx, face_y - 0.02, 0.36 + wall_h - 0.18, 0.36, 0.62)

    # ── The two towers, and the gate between them ──
    tw, tower_h = 1.15, 4.5
    gate_y = face_y - 0.85
    for s in (-1, 1):
        tx = kx + s * (kw / 2 - 0.1)
        ty = gate_y + 0.1
        ashlar_courses(f'tow{s}', tx, ty, 0, tw, tw, tower_h,
                       course=0.0972, block=0.1692)
        box(f'towband{s}', tx, ty, tower_h * 0.5, tw + 0.08, tw + 0.08, 0.09,
            mat('limestone'))
        battlements(f'towcrown{s}', tx, ty, tower_h, tw, tw, h=0.3,
                    merlon=0.1239, gap=0.0958)
        shingle_gable(f'towroof{s}', tx, ty, tower_h + 0.42, tw * 0.72,
                      tw * 0.72, 1.0, overhang=0.14, rows=14, ridge_along='y')
        box(f'towfin{s}', tx, ty, tower_h + 1.42, 0.09, 0.09, 0.2, mat('gold'))
        arrow_slit(f'tows{s}', tx, ty - tw / 2, 1.35, 0.55)
        arrow_slit(f'towsu{s}', tx, ty - tw / 2, 2.3, 0.55)
        arrow_slit(f'towsx{s}', tx + s * tw / 2, ty, 1.8, 0.55, facing='x')
        # ── ABOVE the upper slit, not over it (user 2026-08-09: "Banner sollen
        #    keine Fenster verdecken") ──
        # It hung at 2.95 with 0.46 of cloth plus tails, and the slit it was
        # covering runs 2.30–2.85 up the same centre line: the banner ate the
        # only opening on that face. A tower is 1.15 wide, so there is no room
        # beside a centred slit — the free wall is the band between the slit and
        # the parapet, and that is where the cloth goes.
        banner(f'towflag{s}', tx, ty - tw / 2 - 0.02, 3.62, 0.28, 0.46)
        lantern(f'towlamp{s}', tx - s * 0.1, ty - tw / 2 - 0.16, 1.05,
                drop=0.14)

    # The gatehouse itself: a deep arch between the towers, with a portcullis
    # in it. The grid is what makes the opening read as a GATE rather than as a
    # doorway — a hole you could ride through, that someone can close.
    gw = kw - tw - 0.5
    ashlar_courses('gate', kx, gate_y, 0, gw, 0.9, 2.5, course=0.1022, block=0.1987)
    battlements('gatecrown', kx, gate_y, 2.5, gw, 0.9, h=0.28, merlon=0.1239,
                gap=0.0958)
    doorway('gatearch', kx, gate_y - 0.45, 0.08, 1.15, 1.5, rim=0.2)
    # ── A STUDDED DOOR, not a portcullis (user 2026-08-04) ──
    # The grid was a lattice of thin bars in front of a dark hole, and at any
    # size a lattice is a texture rather than a shape: it filled the one opening
    # in the facade with noise. A boarded door is one solid silhouette with
    # rivets on it — the same read at 256 px as at 1000, and the rivets are the
    # part that says a smith worked on it.
    # ── The gate, built as ONE thing (user 2026-08-06) ──
    # It was plank_door() — a house door with its own ledges and studs — and
    # then a second grid of studs laid over the top. Two patterns on one surface
    # is why it read as busy: the planks say one rhythm, the rivets say another,
    # and neither wins.
    # ── And ROUND (user 2026-08-09) ──
    # The stone above it had been an arch since the beginning; the door under it
    # was a rectangle, so the whole opening read square. See arched_door: it is
    # the dark shape that carries the curve, not the pale one round it.
    arched_door('gdoor', kx, gate_y - 0.6, 0.1, 1.08, 1.44, boards=12)
    for s in (-1, 1):
        sconce(f'gatelamp{s}', kx + s * 0.78, gate_y - 0.45, 1.75)

    # ── The bailey: a walled yard, not an open square ──
    yx0, yx1 = -half + 0.22, half - 0.22
    yy0, yy1 = -half + 0.22, gate_y - 1.15
    yxc, yyc = (yx0 + yx1) / 2, (yy0 + yy1) / 2
    yw, yd = yx1 - yx0, yy1 - yy0
    box('bailey', yxc, yyc, 0, yw, yd, 0.1, mat('ashlar'))
    paving('paving', yxc, yyc, 0.1, yw - 0.2, yd - 0.2,
           key_a='limestone', key_b='ashlar', tile=0.1785)
    # A low curtain wall with its own battlements, open at the near corner so
    # the yard is still walkable rather than a box.
    for s in (-1, 1):
        ashlar_courses(f'curt{s}', yxc + s * (yw / 2 - 0.09), yyc, 0.1,
                       0.18, yd * 0.8, 0.62, course=0.0821, block=0.149)
        battlements(f'curtc{s}', yxc + s * (yw / 2 - 0.09), yyc, 0.72, 0.18,
                    yd * 0.8, h=0.2, merlon=0.1125, gap=0.0897)

    # The well: the one shape in a bailey nobody has to be told the meaning of.
    # ── SMALLER, AND NO PALE LID (user 2026-08-04) ──
    # It was nearly as wide as the gate and capped in limestone, which made a
    # bright horizontal plate sitting in the middle of the bailey — the lightest
    # thing in the picture, on the least important object in it. A well is
    # furniture; it may say "someone lives here" and nothing louder.
    #
    # The coping is the same ashlar as the shaft now, one course proud, so the
    # rim reads as the top of a wall rather than as a lid laid on one.
    wx, wy = yxc - 1.2, yyc + 0.2
    ashlar_courses('well', wx, wy, 0.1, 0.52, 0.52, 0.36, course=0.0662,
                   block=0.125)
    box('well_rim', wx, wy, 0.46, 0.58, 0.58, 0.06, mat('ashlar_dark'))
    box('well_dark', wx, wy, 0.43, 0.38, 0.38, 0.05, mat('dark'))
    for s in (-1, 1):
        box(f'well_post{s}', wx + s * 0.22, wy, 0.5, 0.09, 0.09, 0.5,
            mat('oak'))
    box('well_beam', wx, wy, 0.98, 0.6, 0.1, 0.1, mat('oak'))
    box('well_rope', wx, wy, 0.76, 0.035, 0.035, 0.22, mat('iron'))
    box('well_bucket', wx, wy, 0.68, 0.16, 0.16, 0.13, mat('oak_light'))
    shingle_gable('well_roof', wx, wy, 1.04, 0.6, 0.6, 0.28, overhang=0.13,
                  rows=8, ridge_along='x')

    # Garrison clutter: what a bailey actually has in it.
    for i, (ox, oy) in enumerate(((1.2, 0.3), (1.55, -0.15))):
        pot(f'kpot{i}', yxc + ox, yyc + oy, 0.1, r=0.15, h=0.4)
    straw_bale('kbale', yxc + 0.6, yy0 + 0.32, 0.1, 0.44, 0.3, 0.28)
    trough('ktrough', yx1 - 0.36, yyc + 0.55, 0.1, 0.26, 0.6, key='oak')
    for i, ox in enumerate((-1.75, 1.75)):
        plant(f'kplant{i}', yxc + ox, yy0 + 0.36, 0.1)
    # No woodpile (user 2026-08-04: "das kleine Holzelement entfernen"). It sat
    # at the far left of the bailey, past the curtain wall's line, and a loose
    # stack of timber on the ground is farmyard clutter — right for the
    # Hatchery, wrong for the seat of the settlement. Its corner goes into the
    # keep, which is the only part of this building whose size a player reads
    # from across the map.

    # ── The donjon: the tallest thing on the map ──
    # A pair of matched towers is a gate. What makes a castle read as a SEAT
    # rather than as a fortification is one tower that is plainly the master of
    # the others — so this one is taller, wider, and set BEHIND the keep, where
    # its height is the only part of it you see over the roof. Height read
    # against a roof you can measure is what makes it feel high; a tall thing
    # standing alone just looks close.
    dx_, dy_ = kx + 0.55, ky + kd / 2 - 0.15
    dw, don_h = 1.55, 5.6
    ashlar_courses('don', dx_, dy_, 0, dw, dw, don_h, course=0.1123, block=0.1987)
    for f in (0.34, 0.66):
        box(f'donband{f}', dx_, dy_, don_h * f, dw + 0.09, dw + 0.09, 0.1,
            mat('limestone'))
    # ── The parapet STOPS at the bartizans (user 2026-08-09) ──
    # It used to run straight through them: four spires standing in the same
    # space as four merlons, with 0.16 of shingle inside the stone. A real
    # wall-head does the opposite — the turret is the corner, and the parapet is
    # the stretch of wall BETWEEN two of them. The inset is sized so even the
    # widest part of a bartizan clears the corbel.
    battlements('doncrown', dx_, dy_, don_h, dw, dw, h=0.38, merlon=0.1125,
                gap=0.073, inset=0.44)
    # Bartizans — the little turrets corbelled off the corners. Four small
    # shapes, and they are most of the difference between a tall box and a
    # castle: they break the vertical line exactly where it is longest.
    #
    # Their heights are stacked from ONE base rather than measured back from
    # don_h one magic offset at a time — that is how the crown ended up level
    # with the donjon's own. The rule the stack has to keep: everything stone
    # finishes below the donjon's corbel, and only the SPIRE rises past it.
    bart_z = don_h - 1.0
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            bx = dx_ + sx_ * (dw / 2 + 0.04)
            by = dy_ + sy_ * (dw / 2 + 0.04)
            box(f'bart{sx_}{sy_}', bx, by, bart_z, 0.34, 0.34, 0.12,
                mat('limestone'))
            ashlar_courses(f'bartb{sx_}{sy_}', bx, by, bart_z + 0.12, 0.4, 0.4,
                           0.6, course=0.0763, block=0.125)
            battlements(f'bartc{sx_}{sy_}', bx, by, bart_z + 0.72, 0.4, 0.4,
                        h=0.16, merlon=0.085, gap=0.065)
            shingle_gable(f'bartr{sx_}{sy_}', bx, by, bart_z + 1.02, 0.32, 0.32,
                          0.55, overhang=0.1, rows=8, ridge_along='y')
    shingle_gable('donroof', dx_, dy_, don_h + 0.5, dw * 0.78, dw * 0.78, 1.5,
                  overhang=0.18, rows=18, ridge_along='y')
    box('donfin', dx_, dy_, don_h + 2.0, 0.12, 0.12, 0.3, mat('gold'))
    for s in (-1, 1):
        arrow_slit(f'dons{s}', dx_ + s * 0.4, dy_ - dw / 2, don_h - 2.2, 0.6)
        arrow_slit(f'donsu{s}', dx_ + s * 0.4, dy_ - dw / 2, don_h - 1.3, 0.6)
    arrow_slit('donsx', dx_ + dw / 2, dy_, don_h - 1.7, 0.6, facing='x')
    banner('donflag', dx_, dy_ - dw / 2 - 0.02, don_h - 0.55, 0.42, 0.72)

    # ── Eigenleben (user 2026-08-09) ──
    # The middle of the map, and until now nobody lived in it. A castle is a
    # HOUSEHOLD before it is a fortification: the kitchen is lit, the washing
    # is out, there are birds on the battlements and something is asleep in the
    # sun by the gate.
    brazier('kkfire', yxc + 1.5, yyc - 0.35, 0.1)
    for i, (ox, oy, k, sc) in enumerate(((-0.75, -0.55, 0, 1.0),
                                         (1.65, 0.9, 2, 0.85),
                                         (-1.85, 0.35, 1, 0.7))):
        critter(f'kcrit{i}', yxc + ox, yyc + oy, 0.1, angle=0.6 + i * 1.9,
                kind=k, scale=sc)
    for i in range(3):
        fowl(f'kfowl{i}', yxc - 0.4 + i * 0.42, yyc - 0.75, 0.1,
             angle=0.5 + i * 1.7, kind=i)
    washing('kwash', yxc - 0.55, yyc + 0.95, 0.1, 1.8, axis='x', h=1.0,
            items=5)
    # The gate is a place people wait at: a bench, baskets, a signpost.
    box('kbench', kx + 1.05, gate_y - 0.55, 0, 0.9, 0.28, 0.36, mat('oak'))
    box('kbencht', kx + 1.05, gate_y - 0.55, 0.36, 1.0, 0.36, 0.08,
        mat('oak_light'))
    basket('kbask0', kx + 1.65, gate_y - 0.5, 0, fill='leaf')
    basket('kbask1', kx - 1.6, gate_y - 0.5, 0, r=0.15, h=0.24, fill='gold')
    signpost('ksignp', kx - 1.9, gate_y - 0.95, 0, arms=2)
    # Birds along the wall-head, where a castle always has them.
    for i, ox in enumerate((-1.3, -0.2, 1.15)):
        perch_bird(f'kbird{i}', kx + ox, face_y - 0.06,
                   0.36 + wall_h + 0.44 + (i % 2) * 0.05, kind=i)
    perch_bird('kdbird', dx_ - 0.4, dy_ - dw / 2 - 0.08, don_h + 0.5, kind=1)
    # The bell every seat of government has, and the woodpile that feeds the
    # kitchen behind it.
    # Accent: RED and GOLD — the settlement's own colours, at its seat.
    bunting('kbunt', kx, gate_y - 0.42, 2.35, gw + 0.4, axis='x', n=11)
    # INSIDE the bailey, not below it: the yard is a shallow strip between the
    # gate and the plinth's edge, and a bed hung off its outer side lands on the
    # neighbour's ground.
    for i, ox in enumerate((-1.45, 1.45)):
        flower_bed(f'kbed{i}', yxc + ox, yyc + 0.1, 0.1, 0.6, 0.34,
                   bloom='bloom_red' if i else 'bloom_white', n=7)
    window_box('kwb', kx, face_y - 0.09, 1.82, 0.5)
    bell('kbell', yx1 - 0.5, yyc + 1.15, 0.1, r=0.2)
    firewood('kwood', yxc - 1.55, yy0 + 0.5, 0.1, w=1.0, rows=7)
    beehive('kbee', yx0 + 0.55, yyc + 1.5, 0.1)

    vine('kvine', kx - kw / 2 - 0.01, ky + 0.3, 0.36, 1.1, facing='x')
    tufts('kgrass', kx, ky, kw + 0.5, kd + 0.5)


# want them. Anything that has no caller AND no plausible one should go.
# ── The era-I roster (user 2026-08-09) ─────────────────────
# "jetzt müssen die anderen Gebäude designt werden im genau gleichen Stil …
#  du kannst die Grundfläche frei wählen, gleicher Detaillierungsgrad"
# and then, on seeing the first cut:
# "ich möchte, dass es mittelalterliche fantasy gebäude sind, welche zusätzlich
#  stärker verziert sein sollen (mehr Details)"
#
# ── What the second note changed ──
# The first cut leaned Roman wherever a building was civic: shallow hipped
# roofs, colonnades, pediments, friezes. Two things wrong with that, and the
# second is the important one. It is the wrong century — but it is also the
# wrong AMOUNT, because a Roman building is severe by design and severity is
# the opposite of what was asked for. Ornament is not a coat of paint here; it
# is what the style IS.
#
# So the vocabulary is medieval throughout: steep shingled roofs, crested
# ridges, pointed doors, jettied oriels, dagged bargeboards, turrets with
# spires, carved posts and heads, hanging signs, weathervanes.
#
# The FOOTPRINTS are still the roster's, not free choices. The art contract is
# that a building's base is exactly gridW × gridH cells wide, so a model built
# to a different plan arrives on the map standing on ground it does not own.
#
# The recipe all of them share:
#
#   * a stone plinth or base course — nothing stands straight on soil;
#   * ORNAMENT ON THE SKYLINE FIRST. At map size a building is read by its
#     outline, so a spire, a crest and a vane are worth more than any amount of
#     carving on a wall, and they cost three boxes each;
#   * detail on the TOP and on the two faces this camera can see (−y and +x),
#     and nowhere else, because nothing else is ever rendered;
#   * and one object that says WHAT IT IS at a glance — the woodpile, the
#     anvil, the coin chest, the hanging sign.


def small_house(w, h):
    """Small House — a cottage: one room, one chimney, one garden.

    ── Was a fungus over a den (user 2026-08-12) ──
    "Die Häuser sehen gar nicht wie mittelalterliche Häuser aus." It was
    designed as a Thicket, a habitat rather than a dwelling, and the argument
    behind that ("creatures are not lodged") was reversed when it became the
    Small House. So: cruck frame, wattle panels, deep thatch, a smoking
    chimney and a fenced garden — and the creatures live in the garden, which
    is where a cottager's animals actually lived.
    """
    plinth('shbase', 0, 0, w - 0.3, h - 0.3, 0.14)
    bw, bd = w - 1.15, h - 1.5
    hx, hy = -0.18, h / 2 - bd / 2 - 0.42
    # A rubble sill under the frame: timber rots where it meets the ground, and
    # every cottage in Europe sits on a course of whatever stone was nearest.
    ashlar_courses('shsill', hx, hy, 0.14, bw + 0.14, bd + 0.14, 0.3,
                   course=0.0691, block=0.134, key='ashlar',
                   dark='ashlar_dark')
    half_timber('shwall', hx, hy, 0.44, bw, bd, 1.05, bays=5)
    roof_z = 1.49
    # THATCH, deep and eyebrowed over the door. A cottage roof is half the
    # building and it is the thing you recognise before anything else.
    shingle_gable('shroof', hx, hy, roof_z, bw, bd, 1.16, overhang=0.36,
                  rows=26, key='thatch', dark='thatch_dark', ridge_along='x')
    box('shridge', hx, hy, roof_z + 1.12, bw + 0.5, 0.22, 0.14, mat('root'))
    for i in range(7):
        # The pegged spars that hold a thatch ridge down.
        box(f'shspar{i}', hx - bw / 2 + (i + 0.5) * bw / 7, hy,
            roof_z + 1.2, 0.07, 0.34, 0.07, mat('root_dark'))
    moss('shmoss', hx, hy, roof_z, bw * 0.6, bd * 0.6, 0.5, overhang=0.0,
         patches=7)
    face = hy - bd / 2
    dagged('shdag', hx, face - 0.36, roof_z, bw + 0.6, key='oak')
    chimney('shchim', hx + bw / 2 - 0.3, hy + 0.34, 0, 0.3, roof_z + 1.05)
    smoke('shsmoke', hx + bw / 2 - 0.3, hy + 0.34, roof_z + 1.12, h=0.85)
    gothic_door('shdoor', hx - 0.3, face, 0.44, 0.5, 0.76)
    plank_door('shleaf', hx - 0.3, face - 0.06, 0.46, 0.44, 0.6, planks=5)
    window('shwin', hx + 0.42, face, 0.86, 0.36, 0.32, 0.1)
    leaded_window('shwinx', hx + bw / 2, hy + 0.1, 0.8, 0.28, 0.3, facing='x')
    lantern('shlamp', hx - 0.72, face - 0.08, 1.24, drop=0.14)
    # ── The garden: a cottage IS its garden ──
    withy_fence('shfen0', 0, -h / 2 + 0.34, 0.14, w - 0.7, h=0.42, axis='x')
    withy_fence('shfen1', -w / 2 + 0.34, -0.45, 0.14, h - 1.5, h=0.42,
                axis='y')
    for i in range(3):
        flower_bed(f'shbed{i}', -w / 2 + 0.85 + i * 0.62, -h / 2 + 0.85,
                   0.14, 0.5, 0.36,
                   bloom=('bloom_red', 'bloom_white', 'bloom_blue')[i], n=5)
    for i in range(4):
        plant(f'shherb{i}', w / 2 - 0.55, -h / 2 + 0.7 + i * 0.42, 0.14,
              r=0.11, key='herb' if i % 2 else 'leaf')
    firewood('shwood', -w / 2 + 0.62, h / 2 - 0.85, 0.14, w=0.6, rows=4)
    barrel('shbar', w / 2 - 0.5, h / 2 - 0.6, 0.14, r=0.17, h=0.36)
    box('shbench', hx - 0.1, face - 0.5, 0.14, 0.8, 0.24, 0.3, mat('oak'))
    basket('shbask', hx + 0.6, face - 0.46, 0.14, fill='leaf')
    beehive('shbee', w / 2 - 0.52, -0.15, 0.14)
    washing('shwash', -0.1, -h / 2 + 1.35, 0.14, 1.3, axis='x', h=0.85,
            items=4)
    # ── And who lives here ──
    nest('shnest', -w / 2 + 0.8, -h / 2 + 1.5, 0.14, 0.2)
    egg('shegg', -w / 2 + 0.8, -h / 2 + 1.5, 0.16, 0.12, mat('egg_common'))
    critter('shcrit0', -0.55, -h / 2 + 0.7, 0.14, angle=0.6, kind=0)
    critter('shcrit1', 0.35, -h / 2 + 1.1, 0.14, angle=2.4, kind=2, scale=0.7)
    fowl('shfowl', 0.75, -h / 2 + 0.6, 0.14, angle=1.4)
    perch_bird('shbird', hx + 0.3, face - 0.3, roof_z + 1.24)
    window_box('shwb', hx + 0.42, face - 0.09, 0.7, 0.4, bloom='bloom_red')
    tufts('shtuft', 0, 0, w - 0.5, h - 0.5)


def large_house(w, h):
    """Large House — a longhouse: dwelling at one end, byre at the other.

    2 x 5 is a corridor, which was a bad shape for the avenue it used to be and
    is the RIGHT shape for the one medieval house that is long by definition.
    One ridge the whole way, a cross-passage in the middle with a door on each
    side, people at the near end and animals at the far one — and the smoke
    coming out of the people's half is what tells you which is which.
    """
    plinth('lhbase', 0, 0, w - 0.24, h - 0.24, 0.14)
    bw, bd = w - 0.7, h - 0.9
    ashlar_courses('lhsill', 0, 0, 0.14, bw + 0.14, bd + 0.14, 0.32,
                   course=0.0691, block=0.134, key='ashlar',
                   dark='ashlar_dark')
    half_timber('lhwall', 0, 0, 0.46, bw, bd, 1.12, bays=12)
    roof_z = 1.58
    shingle_gable('lhroof', 0, 0, roof_z, bw, bd, 1.05, overhang=0.3,
                  rows=30, key='thatch', dark='thatch_dark', ridge_along='y')
    box('lhridge', 0, 0, roof_z + 1.01, 0.22, bd + 0.4, 0.14, mat('root'))
    for i in range(11):
        box(f'lhspar{i}', 0, -bd / 2 + (i + 0.5) * bd / 11, roof_z + 1.09,
            0.34, 0.07, 0.07, mat('root_dark'))
    moss('lhmoss', 0, 0, roof_z, bw * 0.6, bd * 0.6, 0.5, overhang=0.0,
         patches=9)
    face = -bw / 2
    # The cross-passage: a door each side, halfway along. It is what makes a
    # longhouse a longhouse rather than a very long shed.
    for s_ in (-1, 1):
        gothic_door(f'lhdoor{s_}', s_ * bw / 2, -0.2, 0.46, 0.5, 0.78,
                    facing='x')
    plank_door('lhleaf', -bw / 2 - 0.06, -0.2, 0.48, 0.44, 0.62, facing='x',
               planks=5)
    for i, ty in enumerate((-bd / 2 + 0.7, -bd / 2 + 1.5)):
        window(f'lhwin{i}', -bw / 2, ty, 0.9, 0.32, 0.3, 0.1, facing='x')
    leaded_window('lhwing', -bw / 2, bd / 2 - 0.9, 0.9, 0.3, 0.34,
                  facing='x')
    # The byre end: bigger opening, no glass, and a hurdle across it.
    box('lhbyre', -bw / 2 + 0.05, bd / 2 - 0.55, 0.46, 0.1, 0.72, 0.86,
        mat('dark'))
    withy_fence('lhhurdle', -bw / 2 - 0.12, bd / 2 - 0.55, 0.14, 0.7, h=0.44,
                axis='y')
    chimney('lhchim', 0, -bd / 2 + 0.6, 0, 0.32, roof_z + 1.0)
    smoke('lhsmoke', 0, -bd / 2 + 0.6, roof_z + 1.06, h=0.9)
    dagged('lhdag', 0, -bd / 2 - 0.3, roof_z, bw + 0.5, key='oak')
    for s_ in (-1, 1):
        corbel_head(f'lhhead{s_}', s_ * (bw / 2 - 0.08), -bd / 2 + 0.1, 1.4)
    lantern('lhlamp', -bw / 2 - 0.1, -0.62, 1.3, drop=0.14)
    hanging_sign('lhsign', -bw / 2 + 0.04, 0.35, 1.3, w=0.2, facing='x')
    # ── The strip of yard the plot leaves ──
    withy_fence('lhpen', w / 2 - 0.22, 0.9, 0.14, h - 2.4, h=0.44, axis='y')
    firewood('lhwood', w / 2 - 0.4, -h / 2 + 0.85, 0.14, w=0.5, rows=5)
    for i in range(2):
        barrel(f'lhbar{i}', -w / 2 + 0.3, -h / 2 + 0.7 + i * 0.5, 0.14,
               r=0.15, h=0.34)
    straw_bale('lhbale', w / 2 - 0.36, 1.5, 0.14, 0.4, 0.28, 0.26)
    trough('lhtr', w / 2 - 0.32, 0.55, 0.14, 0.24, 0.6, key='oak')
    nest('lhnest', -w / 2 + 0.34, 1.7, 0.14, 0.2)
    for i, r in enumerate((0.12, 0.1)):
        egg(f'lhegg{i}', -w / 2 + 0.3 + i * 0.2, 1.7, 0.16, r,
            mat('egg_common' if i % 2 else 'egg_uncommon'))
    critter('lhcrit0', w / 2 - 0.34, 1.05, 0.14, angle=1.3, kind=1, scale=0.9)
    critter('lhcrit1', -w / 2 + 0.36, -1.3, 0.14, angle=2.6, kind=0,
            scale=0.75)
    fowl('lhfowl', -w / 2 + 0.34, 0.3, 0.14, angle=0.8)
    washing('lhwash', -w / 2 + 0.32, -0.55, 0.14, 1.1, axis='y', h=0.9)
    flower_bed('lhbed', -w / 2 + 0.34, -h / 2 + 1.6, 0.14, 0.42, 0.32,
               bloom='bloom_white', n=5)
    window_box('lhwb', -bw / 2 - 0.08, -bd / 2 + 0.7, 0.74, 0.36, facing='x',
               bloom='bloom_red')
    perch_bird('lhbird', 0, -bd / 2 - 0.16, roof_z + 1.06)
    tufts('lhtuft', 0, 0, w - 0.4, h - 0.4)


def wood_camp(w, h):
    """Small Wood Camp — a felling camp, read from its woodpile.

    The one object that survives at map size is the STACK: a wall of log-ends
    is unmistakable from any distance, where a shed is a shed. So the shelter
    is small and pushed back, and the pile takes the near corner.

    The shelter earns its keep with a dagged verge and a carved post — a
    lean-to is the humblest thing on the map, and even that gets carved here.
    """
    plinth('wcbase', 0, 0, w - 0.3, h - 0.3, 0.14)
    sx, sy = -w / 2 + 0.95, h / 2 - 0.85
    for s in (-1, 1):
        carved_post(f'wcpost{s}', sx + s * 0.62, sy - 0.5, 0.14, 1.02)
        box(f'wcback{s}', sx + s * 0.62, sy + 0.5, 0.14, 0.14, 0.14, 1.35,
            mat('oak'))
    lean_to('wcroof', sx, sy, 1.35, 1.5, 1.2, 0.16, drop=0.34, key='shingle',
            courses=11)
    dagged('wcdag', sx, sy - 0.66, 1.16, 1.6)
    ridge_crest('wccrest', sx, sy + 0.5, 1.5, 1.5, axis='x')
    box('wcbench', sx, sy - 0.42, 0.14, 1.2, 0.34, 0.4, mat('oak_light'))
    hanging_sign('wcsign', sx + 0.78, sy - 0.5, 1.15, w=0.38)
    lantern('wclamp', sx - 0.72, sy - 0.55, 1.1, drop=0.14)
    # THE WOODPILE, near corner, log-ends towards the camera.
    px, py = w / 2 - 0.85, -h / 2 + 0.72
    for row in range(4):
        for col in range(5):
            if _hash01(f'wc{row}{col}') < 0.12:
                continue
            box(f'wclog{row}{col}', px - 0.62 + col * 0.31,
                py + (row % 2) * 0.04, 0.14 + row * 0.27, 0.27, 0.62, 0.26,
                mat('oak' if (row + col) % 2 else 'oak_light'))
    bx, by = -w / 2 + 0.8, -h / 2 + 0.6
    box('wcblock', bx, by, 0.14, 0.38, 0.38, 0.42, mat('oak'))
    box('wcaxeh', bx + 0.05, by - 0.02, 0.56, 0.06, 0.06, 0.44,
        mat('oak_light'))
    ah = box('wcaxe', bx + 0.05, by - 0.02, 0.94, 0.22, 0.08, 0.16, mat('iron'))
    ah.rotation_euler = (0, 0.5, 0)
    straw_scatter('wcchip', bx, by + 0.4, 0.14, 0.4, n=12, key='oak_light')
    for i, (ox, oy) in enumerate(((0.1, 0.9), (-1.0, 0.2))):
        plant(f'wcplant{i}', ox, oy, 0.14)
    if w >= 4:
        # A saw-horse with a log on it, a second short stack, and the felled
        # trunk they came off. The pile alone said "wood"; this says "felling".
        hx2, hy2 = -w / 2 + 0.85, -h / 2 + 0.62
        for s_ in (-1, 1):
            for t_ in (-1, 1):
                leg = box(f'wchl{s_}{t_}', hx2 + s_ * 0.26, hy2 + t_ * 0.16,
                          0.14, 0.09, 0.09, 0.5, mat('oak'))
                leg.rotation_euler = (t_ * 0.2, -s_ * 0.2, 0)
        box('wchtop', hx2, hy2, 0.62, 0.72, 0.16, 0.1, mat('oak_light'))
        box('wchlog', hx2, hy2, 0.7, 0.9, 0.3, 0.28, mat('oak'))
        for row in range(2):
            for col in range(3):
                box(f'wcst2{row}{col}', w / 2 - 1.55 + col * 0.3,
                    h / 2 - 0.55, 0.14 + row * 0.27, 0.27, 0.6, 0.26,
                    mat('oak_light' if (row + col) % 2 else 'oak'))
        trunk = box('wctrunk', 0.35, h / 2 - 0.42, 0.14, 1.5, 0.36, 0.34,
                    mat('oak'))
        trunk.rotation_euler = (0, 0, 0.12)

    # ── A camp that SHIPS timber has a cart in it ──
    cart('wccart', 0.15, -h / 2 + 1.55, 0.14, angle=0.35, load='log')
    tool_rack('wctools', -w / 2 + 0.55, 0.55, 0.14, w=0.7, facing='x')
    barrel('wcbar', w / 2 - 0.45, h / 2 - 0.5, 0.14, r=0.18, h=0.38)
    sack_pile('wcsack', -w / 2 + 0.6, -h / 2 + 1.5, 0.14, n=2)
    for i in range(3):
        box(f'wcbranch{i}', -0.5 + i * 0.4, h / 2 - 0.4, 0.14, 0.7, 0.14,
            0.12, mat('leaf' if i % 2 else 'moss'))
    # ── Eigenleben: the fire is lit and the axe is down ──
    brazier('wcfire', -w / 2 + 1.55, h / 2 - 1.25, 0.14)
    critter('wccrit', 0.55, -h / 2 + 0.55, 0.14, angle=2.5, kind=0)
    firewood('wcsplit', -w / 2 + 1.9, -h / 2 + 0.45, 0.14, w=0.85)
    basket('wcbask', -w / 2 + 0.5, -0.15, 0.14, fill='oak_light')
    perch_bird('wcbird', -w / 2 + 0.95, h / 2 - 1.55, 1.75)
    # Accent: GOLD cloth over the bench, and a bed by the door.
    curtain('wccurt', sx, sy - 0.72, 0.62, 1.0, 0.46, key='cloth_gold')
    flower_bed('wcbed', w / 2 - 0.5, h / 2 - 0.5, 0.14, 0.6, 0.4,
               bloom='bloom_red', n=6)
    bunting('wcbunt', sx, sy - 0.66, 1.35, 1.5, axis='x', n=7,
            a='cloth_gold', b='cloth_red')
    # ── SIGNATURE: the spar tree ──
    spar_tree('wcspar', -w / 2 + 0.52, h / 2 - 0.6, 0.14, hgt=2.75)

def stone_camp(w, h):
    """The quarry: a horseshoe of living rock round a cave mouth.

    ── A style test (user 2026-08-12) ──
    Built against a reference, and what the reference does that the rest of
    this file does not:

      * It is NOT A BUILDING. There is no wall, no roof and no door. A cliff
        with a hole in it, and the timber, the rails and the crane are bolted
        into the rock rather than standing next to it.
      * BIG masses, few of them. Nine boulders carry the whole face where the
        old version had five coursed panels and nine bits of spoil — and the
        new one reads from further away, which is the entire argument for
        "nicht ganz so detailliert".
      * The darkest tone in the picture is the subject. The cave mouth is the
        only true black on the map and the eye goes to it first.
      * Cool rock against warm timber. Two families, and the join between them
        is most of what makes it look painted rather than modelled.

    The composition, front to back: the cut blocks stacked at the near left,
    the loaded cart on its rails running out of the mouth, the mouth itself
    dead centre with its props, the face closing round it, and the crane
    standing off to the right where it breaks the skyline against nothing.
    """
    # A quarry floor is not a plinth: it is trodden rock dust with the bedrock
    # showing through, so it is flat, pale and dirty rather than laid.
    box('scfloor', 0, 0, 0, w - 0.3, h - 0.3, 0.12, mat('rock_shade'))
    # Pale dust trodden over the bedrock: the timber, the rails and the
    # cart are all dark, and they need something to be dark AGAINST.
    box('scfloor2', 0, -0.1, 0.12, w - 0.9, h - 0.9, 0.025, mat('sand'))
    straw_scatter('scgrit', 0, -0.2, 0.14, min(w, h) * 0.5, n=22, key='rock')

    hw, hh_ = w / 2, h / 2
    # ── WHICH WAY IS WHICH ──
    # Both grid axes run DOWN the screen: +x to the lower right, +y to the
    # lower left. So the far side of the picture is -x AND +y together, and
    # its right-hand side is +x and +y together. Getting this wrong once put
    # the crane in the middle of the yard with its jib across the mouth.
    def back(d):
        return (-d * 0.7, d * 0.7)

    def right(d):
        return (d * 0.7, d * 0.7)

    # ── THE FACE ──
    # Authored, not looped: a quarry face where every mass is the same size is
    # a garden wall, and the variation IS the material.
    #
    # Sized off the reference: one boulder is about a sixth of the picture
    # across and is a CHUNK — as wide as it is high. Height comes from putting
    # a second one on top, never from stretching one, which is what turned the
    # first pass into a row of filing cabinets.
    rock_wall('scback', [
        (-hw + 0.5, hh_ - 0.45, 0.78, 0.7, 0.66),
        (-hw + 1.2, hh_ - 0.4, 0.68, 0.6, 0.86),
        (-hw + 1.85, hh_ - 0.48, 0.66, 0.66, 0.58),
        (hw - 1.75, hh_ - 0.42, 0.7, 0.62, 0.74),
        (hw - 1.05, hh_ - 0.38, 0.74, 0.58, 0.92),
        (hw - 0.55, hh_ - 0.5, 0.66, 0.66, 0.62),
    ])
    rock_wall('scleft', [
        (-hw + 0.45, hh_ - 1.15, 0.68, 0.7, 0.8),
        (-hw + 0.42, hh_ - 1.85, 0.62, 0.66, 0.56),
        (-hw + 0.46, hh_ - 2.5, 0.58, 0.6, 0.4),
    ])
    rock_wall('scright', [
        (hw - 0.52, hh_ - 1.2, 0.68, 0.66, 0.72),
        (hw - 0.46, hh_ - 1.9, 0.6, 0.62, 0.48),
    ])
    # The second course, where the face has to be tall: stacked, not stretched.
    for i, (bx, by, bw_, bd_, bh_) in enumerate((
            (-hw + 1.2, hh_ - 0.45, 0.56, 0.5, 0.6),
            (hw - 1.05, hh_ - 0.44, 0.6, 0.48, 0.66),
            (-hw + 0.48, hh_ - 1.18, 0.54, 0.56, 0.5))):
        boulder(f'scup{i}', bx, by, {0: 0.86, 1: 0.92, 2: 0.8}[i], bw_, bd_,
                bh_, key='rock_shade', seed=40 + i)

    # ── THE MOUTH ──
    # Dead centre of the BACK, which is -x and +y together. The darkest thing
    # in the picture has to be seen, and a hole tucked behind a boulder is a
    # hole nobody finds.
    bx_, by_ = back(1.15)
    mx, my = bx_, by_
    cave_mouth('scmouth', mx, my, 0.12, w=1.3, hh=1.05, depth=0.8)
    boulder('scover', mx - 0.15, my + 0.3, 1.32, 1.4, 0.72, 0.42, seed=11)

    # ── THE TIMBER, bolted INTO the rock ──
    stage('scstage', mx - 0.08, my - 0.8, 1.46, 1.7, 0.56)
    ladder('sclad0', mx + 0.9, my - 0.98, 0.12, hh=1.45, axis='y', rungs=5)
    box('scwalk', mx - 0.08, my - 1.06, 1.38, 1.95, 0.12, 0.12,
        mat('oak_light'))

    # ── THE RAILS, out of the mouth and down the screen ──
    # -y is the lower LEFT, which is where the reference's track runs.
    # Short enough to stay ON the tile: the track ran to the plot's edge and
    # the cart at its end hung a quarter cell off the far side.
    rails('scrail', mx + 0.1, my - 1.4, 0.145, min(h - 1.9, 2.3),
          axis='y', ties=8)
    mine_cart('sccart', mx + 0.1, my - 1.85, 0.19, axis='y')

    # ── THE CRANE, on the RIGHT (+x AND +y), against the sky ──
    cx_, cy_ = right(1.2)
    jib_crane('sccrane', cx_ + 0.15, cy_ - 0.35, 0.12, hh=1.85, reach=0.92)

    # ── THE LARGE CAMP: the same hole, worked twice ──
    # "Large Stone Camp soll wirklich auch ein grösserer Steinbruch sein"
    # (user 2026-08-12). Not a masons' lodge at a bigger size — the same
    # quarry with a second face cut into the left-hand wall, its own mouth,
    # its own crane and its own track. What makes a big quarry big is that
    # two gangs are working it.
    if w >= 4 and h >= 4:
        b2x, b2y = back(-0.15)
        rock_wall('sc2', [
            (-hw + 0.58, hh_ - 3.1, 0.66, 0.62, 0.8),
            (-hw + 0.56, hh_ - 3.75, 0.6, 0.58, 0.55),
            (hw - 0.58, hh_ - 3.2, 0.64, 0.6, 0.72),
        ])
        m2x, m2y = -hw + 1.15, -hh_ + 1.85
        cave_mouth('sc2mouth', m2x, m2y, 0.12, w=1.0, hh=0.85, depth=0.7)
        ladder('sc2lad', m2x + 0.72, m2y - 0.85, 0.12, hh=1.15, axis='y',
               rungs=4)
        rails('sc2rail', m2x, m2y - 0.95, 0.145, 1.15, axis='y', ties=5)
        mine_cart('sc2cart', m2x, m2y - 1.2, 0.19, axis='y',
                  load='rock_warm')
        jib_crane('sc2crane', -hw + 1.15, hh_ - 1.9, 0.12, hh=1.5,
                  reach=0.62)
        for i in range(3):
            for k in range(2):
                box(f'sc2blk{i}{k}', -0.35 + i * 0.6, -hh_ + 0.62,
                    0.12 + k * 0.25, 0.5, 0.44, 0.24,
                    mat('rock_light' if k % 2 else 'rock'))
        box('sc2hut', hw - 1.0, -hh_ + 0.8, 0.12, 0.85, 0.7, 0.55,
            mat('oak'))
        shingle_gable('sc2hutr', hw - 1.0, -hh_ + 0.8, 0.67, 0.85, 0.7, 0.4,
                      overhang=0.16, rows=10, ridge_along='x')
        tool_rack('sc2tools', hw - 1.0, -hh_ + 0.35, 0.12, w=0.6)
        critter('sc2crit', -0.9, -hh_ + 1.15, 0.12, angle=2.2, kind=0,
                scale=0.85)

    # ── THE YIELD: cut blocks, squared, so the rock reads as raw ──
    for i, (ox, oy, n) in enumerate(((-hw + 0.75, -hh_ + 0.68, 3),
                                     (0.85, -hh_ + 0.6, 2))):
        for k in range(n):
            box(f'scblk{i}{k}', ox + (k % 2) * 0.05, oy, 0.12 + k * 0.25,
                0.54, 0.46, 0.24,
                mat('rock_light' if k % 2 else 'rock'))
            box(f'scblks{i}{k}', ox + (k % 2) * 0.05, oy, 0.12 + k * 0.25,
                0.58, 0.5, 0.04, mat('rock_deep'))
    for i in range(5):
        j = _hash01(f'scr{i}')
        bx2, by2 = back(-0.5 - i * 0.28)
        boulder(f'scrub{i}', bx2 - 0.6 + j * 0.3, by2 + 0.4 - j * 0.4, 0.12,
                0.26 + 0.14 * j, 0.24 + 0.12 * j, 0.2 + 0.12 * j,
                seed=20 + i)

    # ── The tools, and that somebody is using them ──
    box('scbank', -hw + 0.85, -0.35, 0.12, 0.8, 0.6, 0.44, mat('oak'))
    boulder('scwork', -hw + 0.85, -0.35, 0.56, 0.62, 0.46, 0.28, seed=31)
    for k in range(4):
        box(f'scwedge{k}', -hw + 0.63 + k * 0.14, -0.43, 0.84, 0.07,
            0.11, 0.13, mat('steel'))
    tool_rack('sctools', hw - 0.5, -0.4, 0.12, w=0.7, facing='x')
    barrel('scbar', 0.35, -hh_ + 1.35, 0.12, r=0.18, h=0.38)
    brazier('scfire', -0.55, -hh_ + 0.85, 0.12)
    critter('sccrit', 0.15, -hh_ + 0.95, 0.12, angle=1.2, kind=2)
    basket('scbask', -0.95, -hh_ + 0.75, 0.12, fill='rock_light')
    for i, (ox, oy) in enumerate(((-hw + 0.5, -hh_ + 1.5),
                                  (hw - 0.55, hh_ - 2.7))):
        plant(f'scplant{i}', ox, oy, 0.12)
    # The one saturated thing that is not the crane's flag: a bed of blooms in
    # the dust, because a quarry with nothing growing in it reads as a ruin.
    flower_bed('scbed', -hw + 0.55, -hh_ + 2.15, 0.12, 0.6, 0.36,
               bloom='bloom_white', n=6)


def wood_works(w, h):
    """Large Wood Camp — a felling camp worked up: the shed thatched and open
    on every side, the yield stacked with its end-grain to the camera, and a
    timber gantry to swing the trunks too big for one man to shift.

    ── Built against a reference (user 2026-08-16) ──
    The reference is not a hall with a door — it is a working YARD: an
    open-sided shelter over the bench, squared log stacks, and beside them a
    raking timber crane with a pulley and a blue flag at its head. So the
    wall and the sawpit that used to stand here are gone; what is here
    instead is four posts and a thatched roof over a bench, because a lumber
    camp is read by its PILES, not by a facade.

    The derrick is [[jib_crane]] — the same machine the quarry stands up,
    because a raking timber crane is the same rig whether what it lifts is a
    boulder or a trunk. Only the load on the hook says which, so jib_crane
    now takes one.
    """
    plinth('wwbase', 0, 0, w - 0.3, h - 0.3, 0.16)
    z0 = 0.16

    # ── THE SHED: four carved posts and a thatched roof, walls none. Small
    # and in its own back-left corner — every other prop's placement below
    # is chosen to leave OPEN GROUND between it and this roof's edge, because
    # a raking crane and a soft thatch roof read as broken the moment their
    # silhouettes touch on screen. ──
    hx, hy = -w / 2 + 1.05, h / 2 - 1.05
    sw, sd = 1.1, 1.1
    post_h = 0.85
    for sxs in (-1, 1):
        for sys in (-1, 1):
            carved_post(f'wwpost{sxs}{sys}', hx + sxs * (sw / 2 - 0.13),
                        hy + sys * (sd / 2 - 0.13), z0, post_h)
    roof_z = z0 + post_h
    shingle_gable('wwroof', hx, hy, roof_z, sw, sd, 0.72, overhang=0.24,
                  rows=14, key='thatch', dark='thatch_dark', ridge_along='x')
    box('wwridgecap', hx, hy, roof_z + 0.68, sw + 0.34, 0.18, 0.1, mat('root'))
    for i in range(5):
        box(f'wwspar{i}', hx - sw / 2 + (i + 0.5) * sw / 5, hy,
            roof_z + 0.73, 0.05, 0.22, 0.05, mat('root_dark'))
    ridge_crest('wwcrest', hx, hy, roof_z + 0.78, sw + 0.15, axis='x')
    moss('wwmoss', hx, hy, roof_z, sw * 0.6, sd * 0.6, 0.28, patches=6)
    face = hy - sd / 2
    dagged('wwdag', hx, face - 0.2, roof_z, sw + 0.34)
    bunting('wwbunt', hx, face - 0.04, roof_z - 0.13, sw + 0.1, axis='x',
            n=6, a='cloth_blue', b='cloth')

    # ── Under the roof: the bench they work at ──
    box('wwbench', hx, hy - 0.08, z0 + 0.3, 0.72, 0.36, 0.055,
        mat('oak_light'))
    for s in (-1, 1):
        box(f'wwbleg{s}', hx + s * 0.32, hy - 0.08, z0 + 0.15, 0.06, 0.28,
            0.3, mat('oak'))
    tool_rack('wwtools', hx + sw / 2 - 0.15, hy + sd / 2 - 0.14, z0, w=0.42,
              facing='x')
    hanging_sign('wwsign', hx, face, roof_z - 0.05, w=0.32, board='cloth_blue')
    lantern('wwlamp', hx - sw / 2 + 0.12, face + 0.1, roof_z - 0.38, drop=0.12)
    crate('wwcrate', hx + sw / 2 - 0.18, hy - sd / 2 + 0.2, z0, s=0.28)

    # ── THE YARD: one neat stack, log-ends to the camera, out in the open
    # in front of the shed — big enough to be the first thing the eye lands
    # on, which is what a felling camp's pile has to be ──
    px, py = -0.15, -h / 2 + 1.05
    firewood('wwstack', px, py, z0, w=1.3, rows=6)
    loose = cyl('wwlog0', px - 0.35, py - 0.55, z0 + 0.09, 0.09, 0.85,
               sides=10, key='oak_light')
    loose.rotation_euler = (0, math.pi / 2, -0.2)
    straw_scatter('wwchip', px, py - 0.5, z0, 0.4, n=8, key='oak_light')

    # ── THE CRANE: signature, stood off to the back-right — its (x + y) has
    # to clear the shed's by a wide margin, or a tall raking jib and a soft
    # thatch roof read as one tangle on screen however far apart their
    # footprints actually are in x and y alone ──
    crx, cry = w / 2 - 1.1, h / 2 - 1.05
    jib_crane('wwcrane', crx, cry, z0, hh=1.25, reach=0.42, load='log')

    # ── Eigenleben: a cart at the gate, and something alive in the yard ──
    cart('wwcart', hx + 0.5, face - 0.55, z0, angle=0.5, load='log')
    critter('wwcrit', w / 2 - 1.6, -h / 2 + 0.55, z0, angle=2.3, kind=1)
    perch_bird('wwbird', hx, hy + sd / 2 + 0.1, roof_z + 0.72)
    flower_bed('wwbed', w / 2 - 0.55, -h / 2 + 0.5, z0, 0.5, 0.34,
               bloom='bloom_blue', n=6)


def stone_works(w, h):
    """Large Stone Camp — the masons' lodge.

    ── Was a Roman shed, is now a lodge (2026-08-09) ──
    A shallow tiled hip roof over coursed stone is a villa outbuilding. The
    masons of this world cut pointed arches and carve heads onto their own
    corbels, so the lodge shows both: a gothic door, an oriel over the yard,
    heads at the corners, and a steep shingled roof with a crest on it.
    """
    plinth('swbase', 0, 0, w - 0.3, h - 0.3, 0.2)
    hx, hy = -0.35, 0.5
    hw, hd = w - 1.5, h - 1.9
    ashlar_courses('swwall', hx, hy, 0.2, hw, hd, 1.42, course=0.1022, block=0.1987)
    string_course('swband', hx, hy, 1.62, hw + 0.02, hd + 0.02)
    roof_z = 1.72
    # STONE SLATES, matching the walls the lodge cuts. Grey where the
    # carpenters' hall next door is brown, which is the whole point.
    shingle_gable('swroof', hx, hy, roof_z, hw, hd, 1.25, overhang=0.3,
                  rows=28, key='limestone', dark='limestone_shade',
                  ridge_along='x')
    ridge_crest('swcrest', hx, hy, roof_z + 1.21, hw + 0.5, axis='x')
    moss('swmoss', hx, hy, roof_z, hw * 0.7, hd * 0.7, 0.6, overhang=0.0,
         patches=9)
    face = hy - hd / 2
    dagged('swdag', hx, face - 0.32, roof_z, hw + 0.6)
    gable_boards('swgab', hx, face - 0.28, roof_z, hw + 0.55, 1.15, axis='x')
    rose_window('swrose', hx, face - 0.3, roof_z + 0.3, 0.24)
    weathervane('swvane', hx + hw / 2 + 0.1, hy, roof_z + 1.25, 0.48)
    gothic_door('swdoor', hx - 0.34, face, 0.2, 0.7, 1.0, rim=0.2)
    box('swleaf', hx - 0.34, face - 0.08, 0.22, 0.6, 0.08, 0.72, mat('oak'))
    for k in range(3):
        box(f'swband{k}', hx - 0.34, face - 0.13, 0.34 + k * 0.22, 0.5, 0.05,
            0.07, mat('iron'))
    oriel('swor', hx + 0.66, face, 0.85, 0.5, 0.46)
    for s in (-1, 1):
        corbel_head(f'swhead{s}', hx + s * (hw / 2 - 0.12), face, 1.5)
        sconce(f'swlamp{s}', hx - 0.34 + s * 0.62, face, 1.2)
    leaded_window('swwinx', hx + hw / 2, hy + 0.2, 0.8, 0.34, 0.42, facing='x')
    hanging_sign('swsign', hx + hw / 2 + 0.12, hy - 0.3, 1.4, w=0.4,
                 facing='x')
    # The banker: the bench a mason works a block on, half-dressed.
    bx, by = 0.7, -h / 2 + 0.95
    for s in (-1, 1):
        box(f'swtr{s}', bx + s * 0.38, by, 0.2, 0.18, 0.6, 0.5, mat('ashlar'))
    box('swbench', bx, by, 0.7, 1.1, 0.72, 0.14, mat('oak'))
    box('swblock', bx, by, 0.84, 0.66, 0.5, 0.42, mat('limestone'))
    for k in range(4):
        box(f'swcut{k}', bx - 0.24 + k * 0.16, by - 0.26, 0.9, 0.1, 0.06, 0.24,
            mat('limestone_shade'))
    box('swmall', bx + 0.42, by - 0.2, 0.84, 0.16, 0.16, 0.2, mat('oak_light'))
    # A finished carving, standing where it can be admired.
    box('swpiece', -w / 2 + 0.8, -h / 2 + 0.8, 0.2, 0.44, 0.44, 0.3,
        mat('limestone_shade'))
    corbel_head('swshow', -w / 2 + 0.8, -h / 2 + 0.8, 0.5)
    straw_scatter('swgrit', bx, by + 0.6, 0.2, 0.45, n=10, key='limestone')

    # ── A finished piece, a cart, and the tools that made both ──
    cart('swcart', -w / 2 + 1.05, -h / 2 + 0.8, 0.2, angle=0.45, load='stone')
    tool_rack('swtools', -w / 2 + 0.55, h / 2 - 1.5, 0.2, w=0.7,
              facing='x')
    for i in range(2):
        crate(f'swcrate{i}', -w / 2 + 0.6, h / 2 - 0.7 - i * 0.45, 0.2,
              s=0.36)
    barrel('swbar', -w / 2 + 0.6, 0.5, 0.2, r=0.18, h=0.38)
    sack_pile('swsack', -w / 2 + 0.65, -0.3, 0.2, n=2)
    # ── Eigenleben: the lodge is at work ──
    chimney('swchim', hx - hw / 2 + 0.28, hy + 0.45, 0.2, 0.3, roof_z + 1.15)
    anvil('swanv', -w / 2 + 0.7, 1.15, 0.2)
    basket('swbask', 1.5, -h / 2 + 0.5, 0.2, fill='limestone')
    perch_bird('swbird', hx, hy - hd / 2 - 0.24, roof_z + 1.3, kind=1)
    washing('swwash', 0.4, h / 2 - 0.45, 0.2, 1.4, axis='x', h=0.85, items=3)
    # Accent: BLUE, against the grey slate roof.
    window_box('swwb', hx + 0.66, face - 0.08, 0.72, 0.46, bloom='bloom_blue')
    curtain('swcurt', hx - 0.34, face - 0.12, 0.24, 0.6, 0.7, key='cloth_blue')
    flower_bed('swbed', -w / 2 + 0.6, -h / 2 + 0.6, 0.2, 0.7, 0.42,
               bloom='bloom_white', n=7)
    # ── SIGNATURE: the traceried window, finished and standing ──
    tracery('swtrac', 0.95, 0.15, 0.2, w=0.78, hh=1.25)

def storehouse(w, h):
    """Storehouse — a granary on staddle stones, with a dovecote in the gable.

    Raised, and that is the whole design: a store standing clear of the ground
    on mushroom-shaped stones is a shape with one meaning, and it gives the
    building a band of shadow nothing else on the map has. The dovecote is the
    ornament that also does a job — every medieval granary had one.
    """
    plinth('sthbase', 0, 0, w - 0.4, h - 0.4, 0.12)
    bw, bd = w - 1.1, h - 1.1
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            px, py = sx_ * (bw / 2 - 0.16), sy_ * (bd / 2 - 0.16)
            box(f'stst{sx_}{sy_}', px, py, 0.12, 0.24, 0.24, 0.34,
                mat('ashlar'))
            box(f'stcap{sx_}{sy_}', px, py, 0.46, 0.42, 0.42, 0.12,
                mat('limestone'))
    floor_z = 0.58
    box('stfloor', 0, 0, floor_z, bw + 0.2, bd + 0.2, 0.12, mat('oak'))
    half_timber('stwall', 0, 0, floor_z + 0.12, bw, bd, 1.05, bays=4)
    roof_z = floor_z + 1.17
    # THATCH, and it is the identification: a straw roof is the loudest the
    # palette can make, and a granary you can find from across the map is worth
    # more than any amount of detail on one you cannot.
    shingle_gable('stroof', 0, 0, roof_z, bw, bd, 1.05, overhang=0.3, rows=26,
                  key='thatch', dark='thatch_dark', ridge_along='y')
    ridge_crest('stcrest', 0, 0, roof_z + 1.01, bd + 0.5, axis='y')
    moss('stmoss', 0, 0, roof_z, bw * 0.7, bd * 0.7, 0.5, overhang=0.0,
         patches=8)
    face = -bd / 2
    dagged('stdag', bw / 2 + 0.3, 0, roof_z, bd + 0.6, axis='y')
    dovecote('stdove', 0, 0, roof_z + 0.62, 0.42, 0.44, holes=3)
    weathervane('stvane', 0, bd / 2 + 0.16, roof_z + 0.9, 0.44)
    gothic_door('stdoor', 0, face, floor_z + 0.12, 0.56, 0.8)
    plank_door('stleaf', 0, face - 0.07, floor_z + 0.14, 0.5, 0.56, planks=7)
    # The floor is 0.46 above the ground and four risers of 0.17 climb
    # 0.68, so the flight stood a quarter of a metre proud of the door it
    # leads to. The rise is the gap divided by the count, always.
    steps('ststeps', 0, face - 0.2, 0.12, 0.8, count=4,
          rise=(floor_z - 0.12) / 4, tread=0.115)
    for s in (-1, 1):
        corbel_head(f'sthead{s}', s * (bw / 2 - 0.1), face, floor_z + 1.0)
        sconce(f'stlamp{s}', s * 0.46, face, floor_z + 0.78)
    hanging_sign('stsign', bw / 2 + 0.1, -0.3, floor_z + 0.9, w=0.36,
                 facing='x')
    grille('stvent', bw / 2, 0.25, floor_z + 0.62, 0.3, 0.3, facing='x')
    for i, (ox, oy, r) in enumerate(((w / 2 - 0.62, -h / 2 + 0.6, 0.2),
                                     (w / 2 - 0.66, -h / 2 + 1.1, 0.17))):
        pot(f'stbar{i}', ox, oy, 0.12, r=r, h=0.44, key='oak')
    for i in range(3):
        s = 0.34 + 0.08 * (i % 2)
        box(f'stsack{i}', -w / 2 + 0.6 + i * 0.3, -h / 2 + 0.62, 0.12,
            s, s * 0.8, 0.3, mat('straw' if i % 2 else 'sand'))
    tufts('sttuft', 0, 0, w - 0.6, h - 0.6)

    # ── What a store is FULL of, standing outside it ──
    cart('stcart', -w / 2 + 0.95, -h / 2 + 0.9, 0.12, angle=0.4, load='sack')
    sack_pile('stheap', w / 2 - 0.7, h / 2 - 0.7, 0.12, n=4)
    for i in range(2):
        barrel(f'stbar{i}', -w / 2 + 0.5, h / 2 - 0.6 - i * 0.44, 0.12,
               r=0.18, h=0.4)
    crate('stcrate', w / 2 - 0.6, -h / 2 + 1.35, 0.12, s=0.38)
    box('stscale', 0.5, -h / 2 + 0.5, 0.12, 0.08, 0.08, 0.5, mat('iron'))
    box('stpan', 0.5, -h / 2 + 0.5, 0.62, 0.34, 0.24, 0.05, mat('iron'))
    # ── Eigenleben: a store is a place people come to ──
    critter('stcrit', -w / 2 + 1.5, -h / 2 + 0.5, 0.12, angle=0.3, kind=2)
    for i in range(2):
        fowl(f'stfowl{i}', w / 2 - 1.15 + i * 0.42, -h / 2 + 0.42, 0.12,
             angle=1.2 + i * 1.6, kind=i)
    basket('stbask', 0.15, -h / 2 + 1.0, 0.12, fill='gold')
    signpost('stsign2', -w / 2 + 0.42, -h / 2 + 1.5, 0.12)
    perch_bird('stbird', 0, bd / 2 + 0.2, roof_z + 0.96)
    # Accent: RED under the thatch — the two loudest things on the building,
    # and between them nothing else on the map looks like it.
    window_box('stwb', 0, face - 0.09, floor_z + 0.62, 0.5)
    bunting('stbunt', 0, face - 0.28, roof_z + 0.05, bw + 0.3, axis='x', n=7)
    flower_bed('stbed', -w / 2 + 0.6, h / 2 - 0.5, 0.12, 0.66, 0.4,
               bloom='bloom_red', n=6)
    # ── SIGNATURE: the gable hoist ──
    hoist('sthoist', 0, face - 0.04, roof_z + 0.86, out=0.32)

def gold_vault(w, h):
    """Gold Vault — a strongbox with a spire on it.

    2 × 2 and almost all wall, which is the point: a vault is a building that
    is mostly its own thickness. What lifts it out of being a box is the
    SPIRE — the smallest footprint on the map gets the sharpest skyline, and
    the gold is spent once, at the very top, so it reads as treasure.
    """
    ashlar_courses('gvbase', 0, 0, 0, w - 0.24, h - 0.24, 0.28,
                   course=0.0713, block=0.139)
    bw, bd = w - 0.5, h - 0.5
    ashlar_courses('gvwall', 0, 0, 0.28, bw, bd, 1.25, course=0.0972, block=0.1786)
    string_course('gvband', 0, 0, 1.42, bw + 0.02, bd + 0.02)
    battlements('gvcrown', 0, 0, 1.53, bw, bd, h=0.24, merlon=0.1125, gap=0.0897)
    # BLACK IRON. Every other roof on the map is something you grow, quarry
    # or fire; this one is plated, because a vault is a box with a lid.
    spire('gvsp', 0, 0, 1.87, bw * 0.66, 1.15, sides=8, key='iron',
          dark='dark')
    finial('gvfin', 0, 0, 3.02, 0.34)
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            turret(f'gvt{sx_}{sy_}', sx_ * (bw / 2 + 0.02),
                   sy_ * (bd / 2 + 0.02) + 0.0, 1.1, 0.16, 0.5,
                   spire_h=0.42)
    face = -bd / 2
    gothic_door('gvdoor', 0, face, 0.28, 0.48, 0.72, rim=0.18)
    box('gvleaf', 0, face - 0.07, 0.3, 0.42, 0.08, 0.58, mat('iron'))
    for k in range(3):
        box(f'gvriv{k}', 0, face - 0.12, 0.42 + k * 0.16, 0.28, 0.05, 0.06,
            mat('gold'))
    arrow_slit('gvslit', 0, face, 1.08, 0.3)
    arrow_slit('gvslitx', bw / 2, 0.1, 1.08, 0.3, facing='x')
    for s in (-1, 1):
        corbel_head(f'gvhead{s}', s * (bw / 2 - 0.1), face, 1.36)
        sconce(f'gvlamp{s}', s * 0.42, face, 1.05)
    banner('gvflag', 0, face - 0.02, 1.34, 0.24, 0.36)
    cx, cy = w / 2 - 0.5, -h / 2 + 0.42
    box('gvchest', cx, cy, 0, 0.44, 0.34, 0.26, mat('oak'))
    box('gvlid', cx, cy + 0.14, 0.26, 0.44, 0.1, 0.2, mat('oak_light'))
    box('gvcoin', cx, cy - 0.02, 0.24, 0.32, 0.22, 0.08, mat('gold'))
    box('gvlock', cx, cy - 0.18, 0.12, 0.12, 0.05, 0.12, mat('iron'))

    # ── GOLD, and enough of it to see (user 2026-08-09) ──
    gold_pile('gvgold', -w / 2 + 0.52, -h / 2 + 0.5, 0, r=0.24)
    for k in range(4):
        box(f'gvbar{k}', -w / 2 + 0.5 + (k % 2) * 0.22, -h / 2 + 1.0,
            k // 2 * 0.09, 0.3, 0.15, 0.09, mat('gold'))
    brazier('gvbraz', w / 2 - 0.42, -h / 2 + 1.05, 0)
    box('gvspear', -w / 2 + 0.28, -h / 2 + 1.35, 0, 0.06, 0.06, 0.9,
        mat('oak'))
    box('gvhead', -w / 2 + 0.28, -h / 2 + 1.35, 0.9, 0.09, 0.09, 0.2,
        mat('iron'))
    # ── Eigenleben: it is GUARDED ──
    critter('gvcrit', -w / 2 + 0.5, -h / 2 + 1.85, 0, angle=1.4, kind=1,
            scale=0.85)
    basket('gvbask', w / 2 - 0.5, -h / 2 + 1.72, 0, fill='gold')
    perch_bird('gvbird', 0, -bd / 2 - 0.1, 1.6, kind=1)
    # Accent: PLUM against all that gold — the one colour gold does not fight.
    curtain('gvcurt', 0, face - 0.1, 0.32, 0.44, 0.62, key='cloth_plum')
    flower_bed('gvbed', -w / 2 + 0.45, -h / 2 + 1.2, 0, 0.5, 0.36,
               bloom='bloom_white', n=5)
    # ── SIGNATURE: the chain, and the lock ──
    chain_wrap('gvchain', 0, 0, 0.95, bw + 0.06, bd + 0.06, per=5)
    portcullis('gvport', 0, face - 0.02, 0.3, 0.44, 0.66, bars=4)

def _timbered_wing(prefix, cx, cy, sx, sy, ridge_along, bays=5, jetty_out=0.16):
    """One jettied, two-storey, timber-framed volume — the repeating unit an
    L-shaped house is built from. Returns the roof's z, for whatever stands
    on it (a chimney, a crest) to key off.

    ── Two storeys means a JETTY, not a taller box (user 2026-08-16) ──
    A single wall stretched twice as high is a warehouse; what says the
    upper floor is a SEPARATE storey is the line breaking outward partway
    up, on brackets, the way an overhanging jetty actually sits on the
    frame below it.

    ── Stone, then back to Fachwerk (user 2026-08-16) ──
    A same-day all-stone version came and went ("bitte wieder Fachwerk") —
    half-timbering is what the whole style is built on, so this reverts to
    exactly the jettied timber-frame construction it had before that.
    """
    # ── Block and course sized for THIS wall, not left at the kit's default
    # (user's rebuild pushed a wing over 4 units long) ──
    # ashlar_courses's per-stone cost is roughly (span / block) per course
    # per side — fine at the 0.134 default on a 1-2 unit cottage wall, but
    # wing B's sill alone came out to ~700 individual stones at that size,
    # which is what was silently blowing past this scene's actual object
    # budget and losing unrelated props (see the 2026-08-16 investigation:
    # isolating the crane/props alone rendered fine at 64 objects; adding
    # this sill back in at its default block size was what broke it at
    # ~1700+). Bigger blocks read as the same coursed-stone sill at a third
    # of the object count.
    ashlar_courses(f'{prefix}sill', cx, cy, 0.0, sx + 0.14, sy + 0.14, 0.3,
                   course=0.15, block=0.42)
    half_timber(f'{prefix}wall0', cx, cy, 0.3, sx, sy, 1.0, bays=bays)
    jz = 1.3
    jetty(f'{prefix}jetty', cx, cy, jz, sx, sy, out=jetty_out, count=4)
    usx, usy = sx + jetty_out * 2, sy + jetty_out * 2
    half_timber(f'{prefix}wall1', cx, cy, jz + 0.1, usx, usy, 0.9, bays=bays)
    roof_z = jz + 0.1 + 0.9
    shingle_gable(f'{prefix}roof', cx, cy, roof_z, usx, usy, 0.85,
                  overhang=0.26, rows=10, ridge_along=ridge_along)
    span = (usx if ridge_along == 'x' else usy) + 0.3
    ridge_crest(f'{prefix}crest', cx, cy, roof_z + 0.8, span, axis=ridge_along)
    moss(f'{prefix}moss', cx, cy, roof_z, usx * 0.55, usy * 0.55, 0.35,
         patches=6)
    return roof_z


def builder_camp(w, h):
    """Builder Camp — an L-shaped, two-storey, half-timbered house wrapped
    around a big workshop courtyard.

    ── Rebuilt again, bigger, jettied, cornered (user 2026-08-16) ──
    Three changes from the single-wing version: no plinth — the building
    stands straight on the tile, the way the app's own floor already reads
    as ground, so a second stone slab under it was redundant; no baked
    smoke — the chimney is geometry only, and [[building-art-no-baseplate-
    no-baked-smoke]] is what wires it into the app's own animated
    ChimneySmoke (kChimneyAnchor in building_definitions.dart) instead;
    and the house itself is now an L, not a single block — one wing along
    the back, one down the right side, meeting at a corner post, which
    frees the whole front-left of the plot as one continuous courtyard
    running down to the plot's own front corner. Everything unfinished —
    the crane, the stone, the timber — happens in that L's elbow.
    """
    z0 = 0.0
    _before = set(bpy.data.objects)
    # The L is built left-heavy (the yard hangs off the west side of the
    # back wing) — X0 recentres the whole composition in the DECLARED
    # footprint, which nothing here otherwise references. Found by rendering
    # with --guides once and reading how far the content sat off from the
    # marked plate; not derived, so re-check it if the layout changes.
    X0 = 0.8
    # h shrank 7→6 to cut the unused margin the deleted forward stone piles
    # used to sit in (user 2026-08-16). ay is h-derived and moves on its
    # own; every hand-placed absolute y below has to move with it or it
    # drifts out of the composition it was tuned against.
    Y0 = -0.5

    # ── THE HOUSE: two jettied wings meeting at a corner ──
    aw, ad = 3.2, 1.05
    ax, ay = -0.55 + X0, h / 2 - 0.75 - ad / 2
    roof_a = _timbered_wing('bcA', ax, ay, aw, ad, 'x', bays=4)
    face_a = ay - ad / 2

    bw, bd = 1.7, 3.6
    bx, by = ax + aw / 2 - bw / 2 + 0.35, face_a - bd / 2
    roof_b = _timbered_wing('bcB', bx, by, bw, bd, 'y', bays=5)
    face_b = bx - bw / 2

    dagged('bcdagA', ax, face_a - 0.28, roof_a, aw + 0.5)
    dagged('bcdagB', face_b - 0.28, by, roof_b, bd + 0.5, axis='y')
    chimney('bcchim', ax + aw / 2 - 0.35, ay + 0.3, 0.3, 0.28, roof_a + 0.95)
    door_h = 0.85
    plank_door('bcdoor', ax - 0.6, face_a, 0.34, 0.42, door_h, planks=5)
    # A proper flight, not steps() as-is: that shared helper's tallest box
    # (the one nearest the door) both widens AND overshoots the threshold
    # by a full extra riser — fine on a shallow porch, but ugly and
    # clipping into the wall here (user 2026-08-16: "Die Treppe gefällt mir
    # nicht"). Built by hand instead: narrow at the top, flaring wide at
    # the ground, and its top riser lands EXACTLY on the threshold (0.34)
    # rather than past it.
    # Three steps, not four (user 2026-08-16: "Die Treppe bitte mit nur 3
    # Stufen").
    step_n, step_rise, step_tread = 3, 0.34 / 3, 0.2
    for i in range(step_n):
        si = step_n - 1 - i
        box(f'bcstep{i}', ax - 0.6, face_a - 0.12 - si * step_tread, 0,
            0.46 + si * 0.11, step_tread + 0.02, (i + 1) * step_rise,
            mat('limestone'))

    # ── Windows: breeding_hut's OWN window, unmodified (user 2026-08-17:
    # "übernimm einfach die Fenster vom breeding_hut. Ich will genau
    # diese") — every attempt at redesigning this (open shutters, a lit
    # pane, a relit olive lattice) got rejected in turn, so this drops
    # every override back to leaded_window()'s plain defaults and even
    # breeding_hut's own w/h (0.3 x 0.38 ground floor, unchanged from the
    # 0.36 this building had been using) — the exact call breeding_hut
    # itself makes, not a lookalike. Ground floor sits sill-height + 0.4 up
    # its own wall, same margin from the sill/head plates breeding_hut
    # uses. Upper floor is NOT at the same x as the ground floor: the
    # jetty pushes that whole wall out by jetty_out, and windows placed at
    # the ground floor's face were landing INSIDE the upper wall's timber,
    # invisible. ──
    # All open now (user 2026-08-17: "jetzt alle Fenster immer offen
    # haben"), all on leaded_window()'s plain default direction — an
    # out=-1 flip tried on a theory about face_a's true exterior turned
    # out to swing the shutters the WRONG way, toward the camera and
    # across the glass (confirmed with an isolated render: out=1 stands
    # them cleanly beside the opening, out=-1 folds them back over it,
    # which is exactly "still closed"). Every window stays on the same
    # default the south gable pair already used correctly.
    #
    # The first cause, found with a marker dropped exactly on bcwinA's own
    # glass and an object-distance scan of the built scene: wing B's own
    # wall studs (bcBwall0_stud*) sat a bare 0.095 units from it. bcwinA's
    # old x (ax+0.9 = 1.15) falls INSIDE wing B's own span (face_b..bx+bw/2
    # = 0.5..2.2) — that window was never on the open face_a wall at all,
    # it was crowded into the elbow where wing B's studs pass right in
    # front of it.
    #
    # A second, wider version of the SAME bug (user 2026-08-17, three more
    # photos: shutters missing, shutters "wrong way round with dark wood
    # covering the window") turned up on a full scan of every window on
    # this building: half_timber() plants a stud down the middle of EVERY
    # bay it isn't told to avoid, and every window here was hand-placed by
    # eye without checking bay centres — most landed within 0.1-0.15 units
    # of a stud, which reads as exactly what the photos show (a stud, or
    # the shutter fighting for the same space as one, printing over the
    # opening). Re-centred on each wall's actual bay midpoints instead of
    # eyeballed offsets. Wing A: bays=4 on a 3.2 span → studs at
    # ax+{-1.6,-.8,0,.8,1.6}, bay centres at ax+{-1.2,-.4,.4,1.2}. Wing B's
    # long faces: bays=5 on a 3.6 span, corner studs excluded → studs at
    # by+{-1.08,-.36,.36,1.08}, bay centres at by+{-1.44,-.72,0,.72,1.44}.
    #
    # bcwinA is deleted outright rather than re-centred (user 2026-08-17:
    # "Fenster unten löschen") — two windows stacked this close to the door
    # read as one too many once bcwinA2 has a clean bay to itself.
    # bcwinA2 pulled from the bay next to the door over to the bay closer
    # to the elbow's own middle (user 2026-08-17, with a photo of this
    # corner: "Das linke Fenster mehr in die Mitte der Wand") — ax-0.4 sat
    # nearer the door than the true midpoint between it and the corner.
    jout = 0.16
    leaded_window('bcwinA2', ax + 0.4, face_a - jout, 1.64, 0.28, 0.34,
                  open=True)
    # bcwinAback sits on the wing's MAX-y face (ay+ad/2), and bcwinB/2/3/4
    # sit on face_b, wing B's MIN-x face — both are the "backwards" side of
    # at()'s sign convention (see leaded_window's own docstring), so their
    # glass was built half a centimetre INSIDE the solid wall panel,
    # invisible behind it. out=-1 corrects just these four.
    leaded_window('bcwinAback', ax - 0.4, ay + ad / 2, 0.7, 0.3, 0.38,
                  open=True, out=-1)
    # bcwinB/3 pulled one bay south, off the bay right against the elbow
    # (user 2026-08-17, same photo: "Die beiden rechten Fenster etwas nach
    # rechts verschieben").
    leaded_window('bcwinB', face_b, by + 0.72, 0.7, 0.3, 0.38, facing='x',
                  open=True, out=-1)
    leaded_window('bcwinB2', face_b, by - 0.72, 0.7, 0.3, 0.38, facing='x',
                  open=True, out=-1)
    leaded_window('bcwinB3', face_b - jout, by + 0.72, 1.64, 0.28, 0.34,
                  facing='x', open=True, out=-1)
    leaded_window('bcwinB4', face_b - jout, by - 0.72, 1.64, 0.28, 0.34,
                  facing='x', open=True, out=-1)
    leaded_window('bcwinBout', bx + bw / 2, by - 1.44, 0.7, 0.28, 0.34,
                  facing='x', open=True)
    # Its own upper floor was bare (user 2026-08-17, a photo of this wall:
    # "setze an dieser Wand oben in die Mitte ein Fenster") — same bay,
    # jettied out like every other upper-floor window, but +jout rather
    # than -jout: this wall's outward is +X, the opposite of face_b's.
    leaded_window('bcwinBoutU', bx + bw / 2 + jout, by - 1.44, 1.64, 0.28,
                  0.34, facing='x', open=True)
    # ── And on the narrow gable end too, which had no window at all (user
    # 2026-08-16: "Bitte an den schmalen Seiten auch noch ein Fenster
    # hinzufügen") — wing B's south gable only now. Wing A's west gable
    # pair (bcwinAgab/2) is deleted: that end butts straight into the shed
    # annex, and the window there clipped into it (user 2026-08-17: "Das
    # Fenster, welches in den Anbau clippt, will ich gelöscht haben"). The
    # south-gable pair itself was deleted for one round on a wrong guess
    # about which window was bad and is restored here (user 2026-08-17:
    # "Diese die du gelöscht hast, sind genau diese, welche als einzige
    # richtig ausgesehen haben"). ──
    # Centred on the gable's own middle bay (bx+0) rather than bx-0.1 —
    # half_timber() draws corner-to-corner studs on the gable FACE too
    # (the axis=0 run, all 6 kept since only axis=1 skips its corners), and
    # -0.1 sat 0.07 units from one of them, the same stud-crowding bug as
    # every other window on this building.
    gb_y = by - bd / 2
    leaded_window('bcwinBgab', bx, gb_y, 0.7, 0.3, 0.38, open=True)
    leaded_window('bcwinBgab2', bx, gb_y - jout, 1.64, 0.28, 0.34,
                  open=True)
    lantern('bclamp', ax - 1.1, face_a - 0.06, 1.15, drop=0.14)
    # Moved to the house's LEFT (west) corner, by the door (user
    # 2026-08-16: "Das Schild soll an der Linken Hausecke sein") — it used
    # to hang off wing B, the far opposite end of the L.
    hanging_sign('bcsign', ax - aw / 2 + 0.22, face_a, 1.32, w=0.36)

    # The shed's own centre, needed before the fence: the yard's fenced
    # boundary has to run wide enough to include the shed annex, not just
    # the house. Flush with the BACK wall (user 2026-08-16: "weiter nach
    # hinten schieben, so dass es mit der hinteren Wand bündig ist") — its
    # own back edge (lean_to's undropped, high side) lands exactly on wing
    # A's own rear wall line.
    wx, wy = ax - aw / 2 - 0.6, (ay + ad / 2) - 0.375

    # ── THE FENCE: tied to the house's own wall lines, not to a separately
    # guessed yard size — the left run ends exactly at wing A's front-left
    # corner and the front run ends exactly at wing B's own front wall, so
    # there is no gap left unfenced where the yard meets the building
    # (user 2026-08-16: "Zaun bitte bis zum Gebäude, damit es abgeschlossen
    # ist"). The left run starts past the shed, so the annex sits INSIDE
    # the fenced yard rather than outside it. ──
    x_left = wx - 0.65
    y_front = by - bd / 2
    withy_fence('bcfenceL', x_left, (face_a + y_front) / 2, z0,
               face_a - y_front, h=0.5, axis='y')
    gate_w = 0.6
    front_span = face_b - x_left
    seg = (front_span - gate_w) / 2
    withy_fence('bcfenceF0', x_left + seg / 2, y_front, z0, seg, h=0.5,
               axis='x')
    withy_fence('bcfenceF1', face_b - seg / 2, y_front, z0, seg, h=0.5,
               axis='x')
    # Plain posts, not carved_post() — its built-in decorative arm brackets
    # (two raking struts near the cap) read as a crossed X of sticks once
    # the lintel between them was gone (user 2026-08-16: "Die 'X' Hölzer
    # löschen"). A bare turned shaft plus one straight beam across both
    # tops reads as a gate frame with none of that clutter (user 2026-08-16:
    # "dafür einen Balken oben über die beiden Säulen, damit diese
    # verbunden werden").
    gx, gy, gh = x_left + seg + gate_w / 2, y_front, 0.85
    for s in (-1, 1):
        px = gx + s * (gate_w / 2 - 0.05)
        cyl(f'bcgatep{s}', px, gy, z0, 0.062, gh, sides=12, taper=0.9,
            key='oak')
        ring(f'bcgatep{s}col', px, gy, z0 + gh * 0.62, 0.072, 0.026,
             key='oak_light', sides=12, tube_sides=6)
    box('bcgatebeam', gx, gy, z0 + gh - 0.03, gate_w + 0.14, 0.09, 0.09,
        mat('oak'))

    # ── THE WORKSHOP: attached to the house's LEFT end, not standing loose
    # in the yard — an annex, the way a real lean-to is built off an
    # existing gable rather than parked in open ground (user 2026-08-16:
    # "Den Unterstand bitte links als Anbau des Gebäudes, nicht in der
    # Mitte des Platzes") ──
    # lean_to() builds its own four corner posts already — the extra pair
    # here were meant as front supports but stood taller than the sloped
    # roof actually reaches at that point, poking through the shingles
    # (user 2026-08-16: "Zwei Holzstützen clippen durch das Dach des
    # Unterstands"). Redundant given the built-in posts; dropped rather
    # than re-measured.
    lean_to('bcshed', wx, wy, z0, 0.95, 0.75, 1.0, drop=0.24, key='shingle',
           courses=3)
    box('bcbench', wx, wy - 0.05, z0 + 0.34, 0.78, 0.42, 0.06,
        mat('oak_light'))
    for s in (-1, 1):
        box(f'bcbleg{s}', wx + s * 0.32, wy - 0.05, z0 + 0.17, 0.06, 0.34,
            0.34, mat('oak'))
    tool_rack('bctools', wx + 0.46, wy + 0.34, z0, w=0.5, facing='x')
    # Sawhorse pulled back toward the shed (x offset 0.55→0.15) — it used
    # to stand right where the steps come down, close enough that the
    # table top, the barrel and the bottom stair tier all read as one
    # tangle from this camera angle (user 2026-08-18, a photo of exactly
    # this corner: "einige Sachen ineinanderclippen").
    sh_x = wx + 0.15
    for s_ in (-1, 1):
        for t_ in (-1, 1):
            leg = box(f'bchl{s_}{t_}', sh_x + s_ * 0.55, wy - 0.6 + t_ * 0.13,
                      z0, 0.06, 0.06, 0.38, mat('oak'))
            leg.rotation_euler = (t_ * 0.2, -s_ * 0.2, 0)
    box('bchtop', sh_x + 0.55, wy - 0.6, z0 + 0.36, 0.55, 0.14, 0.07,
        mat('oak_light'))
    saw = box('bcsaw', sh_x + 0.55, wy - 0.7, z0 + 0.42, 0.45, 0.03, 0.22,
             mat('iron'))
    saw.rotation_euler = (0, 0.08, 0)
    straw_scatter('bcchip', sh_x - 0.05, wy - 0.35, z0, 0.4, n=9,
                  key='oak_light')

    # ── THE MATERIALS: cut stone, kept INSIDE the fence and clear of the
    # steps — down to ONE pile and no plank stack any more (user 2026-08-16:
    # "Den Hof etwas aufräumen, d.h weniger Elemente"), the same tidy-up
    # that also dropped the crate below. x pulled well clear of face_b
    # (0.5): at its old x it sat on the WRONG side of the yard's own wall
    # line, inside wing B's footprint rather than in front of it.
    for k in range(3):
        box(f'bcstn0{k}', -1.6 + (k % 2) * 0.04, -1.6, z0 + k * 0.25,
            0.46, 0.4, 0.22, mat('limestone' if k % 2 else 'limestone_shade'))
        box(f'bcstns0{k}', -1.6 + (k % 2) * 0.04, -1.6, z0 + k * 0.25,
            0.5, 0.44, 0.03, mat('limestone_shade'))
    # Turned 90° and moved off the steps' own approach — running from the
    # shed toward the saw table instead of sitting across the front of the
    # house (user 2026-08-17: "Der Balken vor der Treppe soll um 90°
    # gedreht aus dem Schuppen in Richtung Kreissäge liegen").
    box('bcbeam', -1.85, 0.6, z0 + 0.14, 0.16, 1.3, 0.16, mat('oak'))

    # ── SIGNATURE: the crane, on its own wall-bracketed gantry — an Anbau
    # off the house, not a structure on or in the roof at all (user
    # 2026-08-18: "kannst du den Kran nicht als Anbau an das Haus
    # machen?"). Every earlier version — stone turret, then a wooden
    # scaffold, then one built into the roof as a dormer — was still
    # roof-mounted; this drops that whole idea and hangs the platform off
    # face_b instead, the way a real warehouse hoist projects from an
    # upper floor on cantilevered beams and raking braces, the same
    # bracket language jetty() already uses for the floors themselves,
    # just sized to carry a crane instead of a wall. ──
    # Pulled back in close to the wall (deck_out 1.1→0.4) rather than kept
    # clear of the roof above it — the mast is meant to pass back up
    # through the eave now, not duck under it (user 2026-08-18: "jetzt das
    # ganze aber aus dem Dach ragen lassen"): the bracket is still what
    # holds it, but the crane itself is meant to stick out through the
    # roof, the way the roof-mounted versions did, just launched off this
    # wall gantry instead of a dormer.
    # deck_z raised from 1.85 (window-band height — the beam was crossing
    # right through bcwinB3) up past the eave (roof_z=2.3): the platform
    # itself needs to read as coming out of the ROOF, not the wall, which
    # a window-height deck can't do regardless of how tall the mast above
    # it is (user 2026-08-19, a photo of exactly this: "Die Plattform soll
    # doch aus dem Dach kommen und nicht aus der Wand/Fenster").
    gan_x, gan_y = face_b, -1.1
    deck_z = 2.55
    deck_out = 0.4
    deck_cx = gan_x - deck_out
    hw = 0.32
    # The wall plate the beams key into, so the bracket reads as fixed TO
    # the timber frame rather than floating off it.
    box('bcganplate', gan_x - 0.03, gan_y, deck_z - 0.14, 0.06, hw * 2 + 0.1,
        0.16, mat('oak'))
    for s in (-1, 1):
        by_ = gan_y + s * hw
        # The cantilever beam itself, wall to the deck's outer edge.
        strut(f'bcganbeam{s}', (gan_x, by_, deck_z - 0.05),
              (deck_cx - 0.45, by_, deck_z - 0.05), w=0.06, key='oak')
        # The raking brace underneath, carrying the beam's own load back
        # into the wall lower down — this is the part that makes it read
        # as BUILT, not just glued on.
        strut(f'bcganbrace{s}', (gan_x, by_, deck_z - 0.55),
              (deck_cx - 0.45, by_, deck_z - 0.05), w=0.05, key='oak_light')
        strap(f'bcganbd{s}', deck_cx - 0.45, by_, deck_z - 0.05, 0.16, 0.16,
              bolts=2)
    # The deck itself: planks across the two beams.
    for i in range(5):
        py = gan_y - hw + hw * 2 * (i + 0.5) / 5
        box(f'bcgandeck{i}', deck_cx, py, deck_z - 0.03, 0.85, hw * 2 / 5
            - 0.02, 0.05, mat('oak_light' if i % 2 else 'oak'))
    crane_x, crane_y = deck_cx, gan_y
    crane_top = deck_z
    # Full-height mast again: the shorter hh=0.7 that once kept the whole
    # thing tucked under the eave is exactly what this round undoes. Still
    # no foot (no ground pad, winch or guy-wires — nothing here to plant
    # them in) and no flag (user 2026-08-16: "Kran ohne Flagge").
    jib_crane('bccrane', crane_x, crane_y, crane_top - 0.2, hh=1.3,
              reach=1.0, foot=False, flag=False)

    # ── A second, dedicated saw — a circular blade on its own bench, not
    # the hand-saw already leaning at the shed's workbench (user
    # 2026-08-16: "Bitte eine Kreissäge auf einem Tisch beim Hof
    # platzieren"). Moved into the corner the washing line, the cart and
    # the sack pile used to crowd together in by the steps — cleared out
    # and given to the saw table instead (user 2026-08-16, with a picture
    # of that exact corner: "Wäscheleine und die anderen Elemente hier
    # löschen. Die Kreissäge dafür an diesen Ort stellen"). ──
    sawtable_x, sawtable_y = -1.7, 0.0
    for s_ in (-1, 1):
        for t_ in (-1, 1):
            box(f'bcstleg{s_}{t_}', sawtable_x + s_ * 0.26,
                sawtable_y + t_ * 0.16, z0, 0.06, 0.06, 0.42, mat('oak'))
    box('bcsttop', sawtable_x, sawtable_y, z0 + 0.42, 0.6, 0.4, 0.06,
        mat('oak_light'))
    # A cyl(axis='y') is a disc standing in the XZ plane, centred where it's
    # placed — bottom edge lands 0.14 below the tabletop (0.48), so the
    # blade reads as poking up through a slot rather than floating.
    blade_z = z0 + 0.48
    cyl('bcsawblade', sawtable_x, sawtable_y, blade_z, 0.16, 0.02, sides=20,
        axis='y', key='steel')
    for i in range(16):
        a = math.pi * 2 * i / 16
        tooth = box(f'bcsawtooth{i}', sawtable_x + math.cos(a) * 0.16,
                    sawtable_y, blade_z + math.sin(a) * 0.16, 0.03, 0.02,
                    0.03, mat('iron'))
        tooth.rotation_euler = (0, 0, a)

    # ── Eigenleben and the one accent colour. No animals (user 2026-08-16,
    # for every building from here on). No crate any more — one fewer
    # element in the tidy-up (user 2026-08-16: "Den Hof etwas aufräumen").
    # Cart, sack pile and washing line are gone too, cleared out of the
    # corner by the steps that the saw table now occupies instead (see
    # above). Barrels stand clear of the shed, beside its open front
    # rather than through its posts. bcbar0 went through two rounds still
    # crowding something in the gap between the bench and the sawhorse —
    # first the sawhorse table, then the steps, then the sawhorse's own
    # diagonal leg brace once the steps issue was fixed — so it's given up
    # entirely on that gap and moved to the open ground behind the bench
    # instead (user 2026-08-18, a photo of this exact corner: "einige
    # Sachen ineinanderclippen").
    # bcbar1 turned out to be the real culprit for the crowded-steps look
    # (user 2026-08-18) — a marker dropped on it landed almost exactly on
    # the steps' own x (-0.88 vs -0.875), just 0.75 short of them in y, so
    # it read as sitting right against the bottom tier. Pulled back to
    # beside bcbar0's new spot instead.
    # x_left (the fence's own west run) sits at wx-0.65 — the first try at
    # this spot (wx-0.75) put bcbar0 past it, clipping the fence rail; both
    # pulled back inside it and spaced apart from each other too.
    barrel('bcbar0', wx - 0.45, wy - 0.45, z0, r=0.17, h=0.36)
    barrel('bcbar1', wx - 0.1, wy - 0.75, z0, r=0.17, h=0.36)
    basket('bcbask', wx - 0.55, wy + 0.15, z0, fill='oak_light')
    bunting('bcbunt', ax, face_a - 0.05, roof_a - 0.1, aw + 0.15, axis='x',
            n=9, a='cloth_red', b='cloth_gold')
    flower_bed('bcbed', ax - aw / 2 + 0.35, face_a - 0.15, z0, 0.5, 0.3,
               bloom='bloom_red', n=6)

    # ── Turned 90° (user 2026-08-16: "die Rotation soll in die andere
    # Richtung sein") ──
    # Also the fix for the missing-prop investigation above: at the
    # DEFAULT camera azimuth the far side of this L put enough geometry
    # between the camera and the courtyard props that a chunk of them
    # rendered as if absent (confirmed by testing --azimuth -90, which
    # showed everything). Turning the building itself means the shipped,
    # azimuth-0 render is the angle that actually works, rather than
    # shipping a camera azimuth this one building needs and no other does.
    for ob in set(bpy.data.objects) - _before:
        x, y = ob.location.x, ob.location.y
        ob.location.x, ob.location.y = -y, x
        ob.rotation_euler.z += math.pi / 2


def healing_hut(w, h):
    """Healing Hut — herbs, steam and a sign you can read.

    The drying rack names it: bunches hung under an open eave say apothecary
    where a symbol would say nothing at thirty pixels. The spore lamps are the
    fantasy note — this world's herbalist grows things that glow.
    """
    plinth('hhbase', 0, 0, w - 0.2, h - 0.2, 0.16)
    bw, bd = w - 0.62, h - 0.9
    hx, hy = 0, 0.25
    ashlar_courses('hhsill', hx, hy, 0.16, bw + 0.12, bd + 0.12, 0.26,
                   course=0.0662, block=0.1289)
    half_timber('hhwall', hx, hy, 0.42, bw, bd, 1.0, bays=4)
    roof_z = 1.42
    # TURF, with flowers in it — the apothecary's roof is part of the
    # apothecary's stock, and it is the only green roof on the map.
    turf_roof('hhroof', hx, hy, roof_z, bw, bd, 1.05, ridge_along='x',
              overhang=0.32)
    ridge_crest('hhcrest', hx, hy, roof_z + 1.01, bw + 0.5, axis='x')
    moss('hhmoss', hx, hy, roof_z, bw * 0.7, bd * 0.7, 0.5, overhang=0.0,
         patches=8)
    chimney('hhchim', hx - bw / 2 + 0.2, hy + 0.42, 0, 0.3, roof_z + 0.95)
    face = hy - bd / 2
    dagged('hhdag', hx, face - 0.34, roof_z, bw + 0.62)
    gable_boards('hhgab', hx, face - 0.3, roof_z, bw + 0.55, 0.95, axis='x')
    weathervane('hhvane', hx + bw / 2 + 0.06, hy, roof_z + 1.05, 0.42)
    gothic_door('hhdoor', hx + 0.2, face, 0.42, 0.48, 0.72)
    plank_door('hhleaf', hx + 0.2, face - 0.06, 0.44, 0.42, 0.5, planks=5)
    oriel('hhor', hx - 0.42, face, 0.78, 0.44, 0.42)
    leaded_window('hhwinx', hx + bw / 2, hy + 0.2, 0.75, 0.28, 0.34,
                  facing='x')
    hanging_sign('hhsign', hx + 0.72, face, 1.24, w=0.36)
    # ── THE FLAG (user 2026-08-12) ──
    # "Healing Hut braucht eine Fahne mit einem roten Kreuz auf weissem
    # Grund." It is the strongest identifier the building has: a drying rack
    # says herbs, a still says laboratory, and only the cross says INFIRMARY.
    cross_flag('hhflag', hx - bw / 2 - 0.16, face + 0.1, 1.05, w=0.36,
               h=0.52)
    lantern('hhlamp', hx - 0.66, face - 0.1, 1.2, drop=0.16)
    for s in (-1, 1):
        corbel_head(f'hhhead{s}', hx + s * (bw / 2 - 0.1), face, 1.3)
    # THE RACK, under the eave.
    rx, ry = hx, face - 0.46
    for s in (-1, 1):
        carved_post(f'hhrp{s}', rx + s * (bw / 2 - 0.08), ry, 0.16, 1.02)
    box('hhrail', rx, ry, 1.08, bw - 0.06, 0.08, 0.08, mat('oak_light'))
    for k in range(5):
        t = -bw / 2 + 0.3 + k * (bw - 0.6) / 4
        box(f'hhbunch{k}', rx + t, ry, 0.74, 0.16, 0.13, 0.34,
            mat('leaf' if k % 2 else 'moss'))
    spore_lamp('hhspore0', -w / 2 + 0.36, -h / 2 + 0.5, 0.16, h=0.5)
    spore_lamp('hhspore1', w / 2 - 0.34, -h / 2 + 0.9, 0.16, h=0.42)
    for i in range(3):
        plant(f'hhherb{i}', -w / 2 + 0.36, -h / 2 + 0.95 + i * 0.42, 0.16)
    brazier('hhbraz', w / 2 - 0.4, -h / 2 + 0.5, 0.16)
    tufts('hhtuft', 0, -h / 2 + 0.9, w - 0.8, 0.6)

    # ── The apothecary's own things ──
    cauldron('hhcaul', w / 2 - 0.5, -h / 2 + 1.35, 0.16, r=0.24)
    for i in range(4):
        box(f'hhvial{i}', -w / 2 + 0.3 + i * 0.16, -h / 2 + 1.5, 0.16,
            0.11, 0.11, 0.2 + 0.08 * (i % 2),
            mat('glow' if i % 2 else 'gold'))
    box('hhmort', 0.55, -h / 2 + 0.42, 0.16, 0.2, 0.2, 0.16,
        mat('limestone'))
    box('hhpest', 0.6, -h / 2 + 0.42, 0.3, 0.05, 0.05, 0.18, mat('oak_light'))
    sack_pile('hhherbs', -w / 2 + 0.34, h / 2 - 0.5, 0.16, n=2, key='leaf')
    barrel('hhbar', w / 2 - 0.4, h / 2 - 0.55, 0.16, r=0.16, h=0.34)
    # ── Eigenleben: the fire is under the pot ──
    critter('hhcrit', -w / 2 + 0.75, -h / 2 + 0.55, 0.16, angle=0.5, kind=2,
            scale=0.85)
    beehive('hhbee', w / 2 - 0.48, h / 2 - 0.5, 0.16)
    washing('hhwash', -0.1, h / 2 - 0.4, 0.16, 1.5, axis='x', h=0.9, items=4)
    basket('hhbask', 0.9, -h / 2 + 0.42, 0.16, fill='leaf')
    # Accent: the roof is already the accent. Beds of the same herbs below it,
    # so the green reads as GROWN rather than as a paint choice.
    flower_bed('hhbed0', -w / 2 + 0.55, -h / 2 + 0.75, 0.16, 0.62, 0.4,
               bloom='bloom_white', n=8)
    flower_bed('hhbed1', w / 2 - 0.52, -h / 2 + 0.55, 0.16, 0.5, 0.36,
               bloom='bloom_blue', n=6)
    window_box('hhwb', hx - 0.42, face - 0.1, 0.72, 0.42, bloom='bloom_pink')
    # ── SIGNATURE: the still ──
    still('hhstill', w / 2 - 0.62, -h / 2 + 1.28, 0.16)

def scout_post(w, h):
    """Scout Post — a watchtower, and the only building whose job is HEIGHT.

    Four legs and the air between them: a stack of boxes is a pillar, and the
    bracing is what makes it a tower. The spire and the pennants are what make
    it a tower somebody in this world built rather than a fire lookout.
    """
    ashlar_courses('spbase', 0, 0, 0, w - 0.36, h - 0.36, 0.34,
                   course=0.0821, block=0.149)
    top = 2.5
    spread = 0.62
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            bx, by = sx_ * spread, sy_ * spread + 0.05
            leg = box(f'spleg{sx_}{sy_}', bx, by, 0.34, 0.15, 0.15, top,
                      mat('oak'))
            leg.rotation_euler = (sy_ * 0.1, -sx_ * 0.1, 0)
    for lift, lz in enumerate((1.0, 1.85)):
        for sy_ in (-1, 1):
            box(f'sprl{lift}{sy_}', 0, sy_ * spread * (1 - lz * 0.13) + 0.05,
                lz, spread * 2, 0.1, 0.1, mat('oak_light'))
        for sx_ in (-1, 1):
            box(f'sprx{lift}{sx_}', sx_ * spread * (1 - lz * 0.13), 0.05,
                lz, 0.1, spread * 2, 0.1, mat('oak_light'))
    for s in (-1, 1):
        br = box(f'spbr{s}', 0, -spread + 0.05, 0.5, 0.1, 0.1, 1.7,
                 mat('oak_light'))
        br.rotation_euler = (0, s * 0.55, 0)
    plat_z = 0.34 + top
    box('spplat', 0, 0.05, plat_z, 1.62, 1.62, 0.12, mat('oak_light'))
    box('spdeck', 0, 0.05, plat_z + 0.12, 1.4, 1.4, 0.06, mat('oak'))
    for i in range(4):
        box(f'sppp{i}', -0.66 + i * 0.44, -0.76, plat_z + 0.18, 0.1, 0.1, 0.4,
            mat('oak'))
        box(f'sppx{i}', 0.76, -0.61 + i * 0.44, plat_z + 0.18, 0.1, 0.1, 0.4,
            mat('oak'))
    box('sprail', 0, -0.76, plat_z + 0.56, 1.6, 0.09, 0.09, mat('oak_light'))
    box('sprailx', 0.76, 0.05, plat_z + 0.56, 0.09, 1.6, 0.09,
        mat('oak_light'))
    for s in (-1, 1):
        carved_post(f'sproofp{s}', s * 0.6, 0.05, plat_z + 0.18, 0.62)
    spire('spsp', 0, 0.05, plat_z + 0.82, 0.9, 1.1, sides=8)
    finial('spfin', 0, 0.05, plat_z + 1.92, 0.32)
    weathervane('spvane', 0.76, 0.05, plat_z + 0.65, 0.5)
    banner('sppen', 0, -0.78, plat_z + 0.62, 0.28, 0.42)
    banner('sppen2', 0.5, -0.78, plat_z + 0.58, 0.2, 0.32)
    lantern('splant', -0.5, -0.78, plat_z + 0.52, drop=0.14)
    # ── The ladder was one stile with rungs drifting off it ──
    # A single post cannot be climbed and the rungs walked sideways as they
    # rose, because both were positioned by hand. ladder() has done this
    # properly since the joinery pass: two stiles, through-pegged rungs, iron
    # shoes, and a lashing where it leans on the platform.
    ladder('spladder', -0.2, -h / 2 + 0.62, 0, hh=plat_z + 0.24, lean=0.16,
           axis='y', rungs=9)
    box('spcrate', -w / 2 + 0.4, -h / 2 + 0.46, 0, 0.34, 0.3, 0.26,
        mat('oak_light'))
    box('spbarrel', w / 2 - 0.42, -h / 2 + 0.5, 0, 0.28, 0.28, 0.34,
        mat('oak'))
    tufts('sptuft', 0, 0, w - 0.7, h - 0.7)

    # ── A watch has a fire, a table and something to throw ──
    brazier('spbeacon', 0.0, 0.62, plat_z + 0.18)
    box('sptable', -w / 2 + 0.62, -h / 2 + 1.15, 0, 0.5, 0.36, 0.36,
        mat('oak'))
    box('spmap', -w / 2 + 0.62, -h / 2 + 1.15, 0.36, 0.44, 0.3, 0.03,
        mat('cloth'))
    tool_rack('spspears', w / 2 - 0.42, h / 2 - 0.75, 0, w=0.6, facing='x')
    brazier('spfire', w / 2 - 0.55, -h / 2 + 1.2, 0)
    sack_pile('sppack', -w / 2 + 0.45, h / 2 - 0.6, 0, n=2)
    # ── Eigenleben: somebody is on watch ──
    critter('spcrit', -w / 2 + 0.5, -h / 2 + 0.5, 0, angle=1.1, kind=0,
            scale=0.9)
    perch_bird('spbird', 0.76, -0.6, plat_z + 0.62, kind=1)
    washing('spwash', 0.15, h / 2 - 0.42, 0, 1.1, axis='x', h=0.8, items=3)
    # Accent: TEAL pennants — a watch flies its own colours.
    bunting('spbunt', 0, -0.78, plat_z + 0.52, 1.5, axis='x', n=7,
            a='cloth_teal', b='cloth_gold')
    flower_bed('spbed', -w / 2 + 0.5, h / 2 - 0.5, 0, 0.5, 0.34,
               bloom='bloom_red', n=5)
    # ── SIGNATURE: the beacon, lit ──
    beacon('spbcn', -0.48, 0.5, plat_z + 0.18, mast=1.05, r=0.22)

def trade_center(w, h):
    """Trade Center — a timber market hall on carved posts.

    ── Was a Roman colonnade, is now a market hall (2026-08-09) ──
    Columns and a frieze made it a small temple, and a temple is not where you
    haggle. The medieval answer is better anyway: an open timber arcade with a
    steep tiled roof and a LOUVRE TURRET on the ridge — the little lantern
    every market hall has, and the one shape that makes it read as a hall
    rather than as a shed.

    Still no walls. That is what a market is, and at map size an open frame
    reads instantly against a map full of closed boxes.
    """
    plinth('tcbase', 0, 0, w - 0.3, h - 0.2, 0.2)
    paving('tcfloor', 0, 0, 0.2, w - 0.9, h - 0.9, key_a='sand',
           key_b='ashlar_dark', tile=0.1995)
    # The HALL is a fixed span; the plot's extra width becomes stalls beside
    # it. A market hall that grows with its plot is just a bigger roof, and a
    # bigger roof is the one thing this building did not need.
    bw, bd = min(2.5, w - 1.1), h - 1.1
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            carved_post(f'tcp{sx_}{sy_}', sx_ * bw / 2, sy_ * bd / 2, 0.2, 1.2)
    for s in (-1, 1):
        carved_post(f'tcpm{s}', s * bw / 2, 0, 0.2, 1.2)
    for s in (-1, 1):
        box(f'tcbeam{s}', 0, s * bd / 2, 1.4, bw + 0.3, 0.15, 0.15,
            mat('oak'))
        box(f'tcbeamx{s}', s * bw / 2, 0, 1.4, 0.15, bd + 0.3, 0.15,
            mat('oak'))
    # Curved braces between post and beam: the arcade's arches, in timber.
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            br = box(f'tcbr{sx_}{sy_}', sx_ * (bw / 2 - 0.28), sy_ * bd / 2,
                     1.05, 0.1, 0.12, 0.5, mat('oak_light'))
            br.rotation_euler = (0, sx_ * 0.72, 0)
    roof_z = 1.55
    shingle_gable('tcroof', 0, 0, roof_z, bw + 0.4, bd + 0.4, 0.95,
                  overhang=0.4, rows=19, ridge_along='x', key='tile_mid',
                  dark='tile_dark')
    dagged('tcdag', 0, -bd / 2 - 0.42, roof_z, bw + 1.1)
    # The louvre: a little turret over the middle, where the smoke goes.
    box('tclouv', 0, 0, roof_z + 0.86, 0.5, 0.5, 0.3, mat('oak'))
    for s in (-1, 1):
        box(f'tclv{s}', s * 0.26, 0, roof_z + 0.86, 0.06, 0.5, 0.3,
            mat('oak_light'))
    spire('tclsp', 0, 0, roof_z + 1.16, 0.42, 0.55, sides=6, key='tile_mid',
          dark='tile_dark')
    finial('tclfin', 0, 0, roof_z + 1.71, 0.3)
    weathervane('tcvane', bw / 2 + 0.2, 0, roof_z + 0.3, 0.5)
    banner('tcflag', 0, -bd / 2 - 0.1, 1.34, 0.34, 0.5)
    for s in (-1, 1):
        lantern(f'tclamp{s}', s * (bw / 2 - 0.05), -bd / 2 + 0.06, 1.26,
                drop=0.16)
    hanging_sign('tcsign', bw / 2 + 0.16, -bd / 2 + 0.4, 1.3, w=0.42,
                 facing='x')
    # The stall under it.
    box('tccount', 0.1, -0.35, 0.2, bw - 0.5, 0.34, 0.44, mat('oak'))
    box('tcctop', 0.1, -0.35, 0.64, bw - 0.36, 0.44, 0.08, mat('oak_light'))
    for i in range(3):
        box(f'tccrate{i}', -bw / 2 + 0.4 + i * 0.42, 0.42, 0.2,
            0.34, 0.32, 0.3, mat('oak' if i % 2 else 'oak_light'))
    for i, r in enumerate((0.16, 0.13)):
        pot(f'tcpot{i}', bw / 2 - 0.3, 0.3 - i * 0.4, 0.2, r=r, h=0.36)
    box('tcscale', 0.1 + bw / 2 - 0.5, -0.35, 0.72, 0.1, 0.1, 0.3, mat('iron'))
    box('tcpan', 0.1 + bw / 2 - 0.5, -0.35, 1.02, 0.34, 0.08, 0.05,
        mat('gold'))

    # ── A market is its GOODS ──
    awning('tcaw0', -bw / 2 + 0.6, -bd / 2 - 0.26, 1.15, 0.95, 0.62)
    awning('tcaw1', bw / 2 - 0.6, -bd / 2 - 0.26, 1.15, 0.95, 0.62)
    for i in range(3):
        box(f'tcbolt{i}', -bw / 2 + 0.45 + i * 0.24, -bd / 2 - 0.3, 0.2,
            0.2, 0.44, 0.3,
            mat('cloth_stripe' if i % 2 else 'cloth'))
    for i in range(3):
        box(f'tcfruit{i}', bw / 2 - 0.75 + i * 0.24, -bd / 2 - 0.3, 0.2,
            0.22, 0.22, 0.18, mat('gold' if i % 2 else 'leaf'))
    sack_pile('tcsack', -bw / 2 + 0.4, 0.5, 0.2, n=3)
    for i in range(2):
        barrel(f'tcbar{i}', bw / 2 - 0.4, 0.35 - i * 0.45, 0.2, r=0.17,
               h=0.36)
    crate('tccr', -0.1, bd / 2 - 0.35, 0.2, s=0.36)
    gold_pile('tccoin', 0.55, -0.32, 0.72, r=0.11, bars=False)
    cart('tccart', -w / 2 + 0.62, h / 2 - 0.85, 0.2, angle=1.6,
         load='barrel')
    # The stalls the extra ground bought: a second awning down the near side,
    # a cloth merchant's bench, and a pen of pots.
    if w >= 4:
        awning('tcaw2', w / 2 - 0.75, -0.15, 1.25, 1.15, 0.7, facing='x')
        box('tcbench', w / 2 - 0.72, -0.15, 0.2, 0.44, 1.0, 0.42, mat('oak'))
        box('tcbtop', w / 2 - 0.72, -0.15, 0.62, 0.56, 1.15, 0.08,
            mat('oak_light'))
        for i in range(3):
            box(f'tcware{i}', w / 2 - 0.72, -0.55 + i * 0.4, 0.7,
                0.3, 0.28, 0.24,
                mat('cloth_stripe' if i % 2 else 'cloth'))
        for i in range(2):
            pot(f'tcpot2{i}', w / 2 - 0.66, h / 2 - 0.6 - i * 0.4, 0.2,
                r=0.16, h=0.34)
        sack_pile('tcsack2', -w / 2 + 0.6, -h / 2 + 0.55, 0.2, n=2)
    # ── Eigenleben: a market has customers ──
    critter('tccrit0', -w / 2 + 0.72, -h / 2 + 0.6, 0.2, angle=0.7, kind=0)
    critter('tccrit1', 0.35, -h / 2 + 0.5, 0.2, angle=2.3, kind=2,
            scale=0.85)
    for i in range(2):
        fowl(f'tcfowl{i}', -0.5 + i * 0.5, bd / 2 + 0.15, 0.2,
             angle=1.0 + i * 2.0, kind=i)
    basket('tcbask0', -bw / 2 + 0.15, -bd / 2 - 0.55, 0.2, fill='leaf')
    basket('tcbask1', bw / 2 - 0.15, -bd / 2 - 0.55, 0.2, fill='gold')
    signpost('tcsignp', -w / 2 + 0.45, h / 2 - 0.5, 0.2, arms=2)
    perch_bird('tcbird', 0, 0, roof_z + 1.02)
    # Accent: bunting the length of the hall. A market is the one building
    # allowed to be loud, and the stalls are already striped.
    bunting('tcbunt', 0, -bd / 2 - 0.16, 1.32, bw + 0.5, axis='x', n=11)
    curtain('tccurt', bw / 2 + 0.04, 0.3, 0.72, 0.7, 0.5, facing='x',
            key='cloth_teal')
    for i, ox in enumerate((-1, 1)):
        flower_bed(f'tcbed{i}', ox * (w / 2 - 0.45), -h / 2 + 0.6, 0.2, 0.5,
                   0.34, bloom='bloom_pink' if i else 'bloom_white', n=5)
    # ── SIGNATURE: the great balance ──
    scales('tcscales', -w / 2 + 0.75, -0.15, 0.2, span=0.95, h=1.3)

def caravanserai(w, h):
    """Caravanserai — a yard something arrived in.

    3 x 2 is shallow, so a hall would be a slab. A COURT is the right answer: a
    turreted gate on one side, a low range along the back, and the middle left
    OPEN.

    ── The open middle is the design (user 2026-08-09) ──
    "Caravanserai braucht Wagen und ev. Kamele". The first pass had a gate and
    two ranges and there was nowhere left to put them — twenty props ended up
    over the tile's edge, one of them a whole cell out. A building whose entire
    subject is arrival cannot spend its floor on architecture: the camels and
    the wagon ARE the building, and the walls are what they stand against.
    """
    plinth('csbase', 0, 0, w - 0.24, h - 0.24, 0.18)
    paving('csyard', 0.25, -0.1, 0.18, w - 1.5, h - 0.7, key_a='sand',
           key_b='limestone_shade', tile=0.1785)
    # The gate, pushed into the far-left corner so it frames rather than fills.
    gx_, gy_ = -w / 2 + 0.62, h / 2 - 0.42
    ashlar_courses('csgate', gx_, gy_, 0.18, 1.05, 0.55, 1.25,
                   course=0.0922, block=0.1692)
    battlements('csgcrown', gx_, gy_, 1.43, 1.05, 0.55, h=0.2, merlon=0.1011,
                gap=0.0844)
    for s_ in (-1, 1):
        turret(f'cstur{s_}', gx_ + s_ * 0.52, gy_, 1.25, 0.15, 0.36,
               spire_h=0.44)
    gothic_door('csarch', gx_, gy_ - 0.28, 0.18, 0.6, 0.85, rim=0.16)
    sconce('cslamp', gx_ + 0.42, gy_ - 0.28, 1.0)
    banner('csflag', gx_, gy_ - 0.3, 1.36, 0.26, 0.4)
    # One low range along the back, and nothing else built.
    rx, ry, rw, rd = 0.75, h / 2 - 0.4, w - 2.0, 0.55
    ashlar_courses('csr', rx, ry, 0.18, rw, rd, 0.82, course=0.0821, block=0.149)
    # PANTILES: the only southern roof, on the only building whose subject
    # is somewhere else. Everything under it arrived from a warmer map.
    shingle_gable('csrr', rx, ry, 1.0, rw, rd, 0.55, overhang=0.22, rows=18,
                  key='tile', dark='tile_dark', ridge_along='x')
    ridge_crest('csrc', rx, ry, 1.53, rw + 0.3, axis='x')
    dagged('csrd', rx, ry - rd / 2 - 0.24, 1.0, rw + 0.35)
    leaded_window('cswin', rx, ry - rd / 2, 0.5, 0.28, 0.32)
    hanging_sign('cssign', rx + rw / 2 - 0.1, ry - rd / 2 + 0.05, 0.95, w=0.34)
    # ── AND NOW THE YARD ──
    pack_beast('cscam0', -0.35, -h / 2 + 0.72, 0.18, angle=0.12)
    pack_beast('cscam1', 0.95, -h / 2 + 0.66, 0.18, angle=-0.3)
    if w >= 4:
        pack_beast('cscam2', w / 2 - 0.75, 0.35, 0.18, angle=1.5, hump=False)
    # At least one WAGON, and where it can be seen (user 2026-08-12).
    cart('cswag', -0.62, -h / 2 + 1.35, 0.18, angle=0.32, load='sack')
    for i in range(3):
        crate(f'cscr{i}', -w / 2 + 0.95 + i * 0.34, -0.35, 0.18, s=0.3)
    sack_pile('cssack', w / 2 - 0.4, 0.35, 0.18, n=2)
    barrel('csbar', w / 2 - 0.42, -0.25, 0.18, r=0.16, h=0.34)
    trough('cstrough', 0.35, -h / 2 + 0.32, 0.18, 0.24, 0.7, key='ashlar')
    box('cswater', 0.35, -h / 2 + 0.32, 0.32, 0.16, 0.58, 0.04, mat('water'))
    brazier('csfire', -w / 2 + 0.42, -h / 2 + 0.42, 0.18)
    if w >= 4:
        # A second wagon drawn up by the wall, and the fodder for the beasts.
        cart('cswag2', w / 2 - 1.0, h / 2 - 1.15, 0.18, angle=-1.4,
             load='barrel')
        for i in range(3):
            straw_bale(f'csbale{i}', -w / 2 + 1.5 + i * 0.5, -h / 2 + 0.42,
                       0.18, 0.42, 0.3, 0.26)

    # ── Eigenleben: the caravan has stopped for the night ──
    critter('cscrit', -w / 2 + 1.15, 0.5, 0.18, angle=0.9, kind=0,
            scale=0.9)
    for i in range(2):
        fowl(f'csfowl{i}', 0.2 + i * 0.45, 0.1, 0.18, angle=0.4 + i * 2.2,
             kind=i)
    washing('cswash', -w / 2 + 1.25, h / 2 - 0.5, 0.18, 1.3, axis='x', h=0.9,
            items=3)
    basket('csbask', w / 2 - 0.45, -h / 2 + 0.55, 0.18, fill='straw')
    # Accent: PLUM and TEAL — the colours a caravan brings from elsewhere.
    curtain('cscurt', gx_, gy_ - 0.3, 0.18, 0.55, 0.8, key='cloth_plum')
    bunting('csbunt', 0.5, -h / 2 + 1.6, 1.15, 1.8, axis='x', n=9,
            a='cloth_plum', b='cloth_teal')
    flower_bed('csbed', -w / 2 + 0.55, h / 2 - 1.15, 0.18, 0.55, 0.36,
               bloom='bloom_red', n=5)
    # ── SIGNATURE: the pavilion ──
    tent('cstent', 0.55, 0.35, 0.18, r=0.66, h=0.9, key='cloth',
         stripe='cloth_plum')

def hatchery(w, h):
    """Hatchery — the warm room, under a spire.

    The Breeding Hut is where a pairing happens and this is where the result is
    kept, so the two must not look alike: no half-timbering here, no jetty.

    ── The dome became a spire (2026-08-09) ──
    Stepped rings read as a Roman rotunda, which is the wrong world. A tall
    faceted cone over a round stone chamber is the same idea in this one, and
    it gives the smallest civic building a skyline worth seeing.
    """
    plinth('hybase', 0, 0, w - 0.3, h - 0.3, 0.18)
    # FIXED, not a fraction of w: the chamber is a round tower and a round
    # tower does not get wider because the plot did. At w - 1.1 the spire came
    # out two and a half cells across and read as a parasol.
    bw, bd = min(2.1, w - 1.1), min(1.9, h - 1.3)
    cx, cy = -w / 2 + bw / 2 + 0.42, h / 2 - bd / 2 - 0.4
    ashlar_courses('hywall', cx, cy, 0.18, bw, bd, 1.0, course=0.0922,
                   block=0.1692)
    string_course('hyband', cx, cy, 1.18, bw + 0.02, bd + 0.02)
    box('hycorb', cx, cy, 1.28, bw + 0.16, bd + 0.16, 0.1, mat('limestone'))
    # ── A DOME, not a cone (user 2026-08-12: "Hatchery anderes Dach") ──
    # Five buildings ended in a faceted cone and this was the fifth. A hatchery
    # is a warm round room, so it gets the one roof shape nothing else on the
    # map has: a shell-white dome, ribbed, with a louvre on top for the heat to
    # leave by. The dome is also the egg — which is the joke the building has
    # been waiting for.
    lathe('hydome', cx, cy, 1.32, [
        (bw * 0.74, 0.0), (bw * 0.72, 0.16), (bw * 0.64, 0.42),
        (bw * 0.48, 0.66), (bw * 0.27, 0.84), (bw * 0.1, 0.94),
    ], sides=16, key='stucco', smooth=True)
    for i in range(8):
        a_ = 2 * math.pi * i / 8
        for k, (rf, hz) in enumerate(((0.73, 0.06), (0.63, 0.44),
                                      (0.42, 0.72))):
            box(f'hyrib{i}{k}', cx + bw * rf * math.cos(a_),
                cy + bw * rf * math.sin(a_), 1.32 + hz, 0.09, 0.09, 0.07,
                mat('stucco_shade'))
    ring('hyband', cx, cy, 1.36, bw * 0.735, 0.035, key='limestone_shade',
         sides=16, tube_sides=6)
    # The louvre: a hatchery must vent, and it is what stops the dome being
    # a bald hemisphere.
    cyl('hylouv', cx, cy, 2.26, bw * 0.16, 0.24, sides=10, key='oak')
    for i in range(6):
        a_ = 2 * math.pi * i / 6
        box(f'hylv{i}', cx + bw * 0.16 * math.cos(a_),
            cy + bw * 0.16 * math.sin(a_), 2.26, 0.05, 0.05, 0.24,
            mat('oak_light'))
    lathe('hylcap', cx, cy, 2.5, [(bw * 0.24, 0.0), (bw * 0.18, 0.12),
                                  (bw * 0.06, 0.2)], sides=10, key='stucco')
    finial('hyfin', cx, cy, 2.7, 0.3)
    smoke('hyvent', cx, cy, 2.72, h=0.55, puffs=3)
    for s in (-1, 1):
        turret(f'hyt{s}', cx + s * (bw / 2 + 0.02), cy + bd / 2 - 0.1, 0.9,
               0.15, 0.42, spire_h=0.44)
    face = cy - bd / 2
    gothic_arch('hymouth', cx, face, 0.18, 0.62, 0.8, 0.3)
    box('hyglow', cx, face + 0.14, 0.2, 0.46, 0.1, 0.5, mat('gold'))
    corbel_head('hyhead', cx, face, 1.06)
    for s in (-1, 1):
        sconce(f'hylamp{s}', cx + s * (bw / 2 - 0.14), face, 0.9)
    leaded_window('hywinx', cx + bw / 2, cy + 0.2, 0.72, 0.26, 0.32,
                  facing='x')
    banner('hyflag', cx, face - 0.02, 1.14, 0.26, 0.4)
    # The clutch, on straw where the camera can see it. THE label.
    nx, ny = w / 2 - 1.35, -h / 2 + 0.9
    straw_scatter('hystraw', nx, ny, 0.18, 0.62, n=16)
    for i, (ox, oy, r, key) in enumerate((
            (-0.3, 0.06, 0.19, 'egg_common'),
            (0.06, -0.12, 0.22, 'egg_legendary'),
            (0.36, 0.1, 0.17, 'egg_common'))):
        egg(f'hyegg{i}', nx + ox, ny + oy, 0.18, r, mat(key))
    brazier('hybraz', -w / 2 + 0.5, -h / 2 + 0.6, 0.18)
    box('hycrate', w / 2 - 0.5, -h / 2 + 0.55, 0.18, 0.36, 0.3, 0.26,
        mat('oak_light'))

    # ── More clutch than one nest: this is a HATCHERY ──
    for i, (ox, oy, r, key) in enumerate((
            (-1.05, 0.25, 0.15, 'egg_uncommon'),
            (-0.95, -0.15, 0.13, 'egg_common'),
            (1.05, 0.3, 0.15, 'egg_rare'),
            (1.15, -0.1, 0.12, 'egg_common'))):
        nest(f'hyn{i}', nx + ox, ny + oy, 0.18, r * 1.5)
        egg(f'hyec{i}', nx + ox, ny + oy, 0.2, r, mat(key))
        straw_scatter(f'hyst{i}', nx + ox, ny + oy, 0.18, r * 1.5, n=6)
    for i in range(2):
        box(f'hyrack{i}', -w / 2 + 0.52, 0.35 - i * 0.5, 0.18, 0.34, 0.4,
            0.22, mat('oak'))
        egg(f'hyre{i}', -w / 2 + 0.52, 0.35 - i * 0.5, 0.4, 0.11,
            mat('egg_common'))
    box('hyshell', nx + 0.62, ny - 0.28, 0.18, 0.2, 0.2, 0.08,
        mat('egg_common'))
    cauldron('hycaul', w / 2 - 0.55, -0.5, 0.18, r=0.2)
    # ── Eigenleben: something has already hatched ──
    critter('hycrit0', nx - 0.1, ny - 0.62, 0.18, angle=1.5, kind=0,
            scale=0.62)
    critter('hycrit0', nx - 0.1, ny - 0.62, 0.18, angle=1.5, kind=0,
            scale=0.62)
    critter('hycrit1', nx + 0.75, ny - 0.5, 0.18, angle=2.4, kind=2,
            scale=0.55)
    fowl('hyfowl', -w / 2 + 0.95, -h / 2 + 0.5, 0.18, angle=0.6)
    basket('hybask', -w / 2 + 0.5, -h / 2 + 1.0, 0.18, fill='straw')
    perch_bird('hybird', cx, cy - bd / 2 - 0.12, 1.3, kind=1)
    # Accent: PINK and WHITE, the colours of the eggs it is named for.
    flower_bed('hybed', -w / 2 + 0.55, 0.55, 0.18, 0.62, 0.4,
               bloom='bloom_pink', n=7)
    curtain('hycurt', cx, face - 0.12, 0.2, 0.5, 0.66, key='cloth_plum')
    bunting('hybunt', nx, ny + 0.85, 0.95, 1.6, axis='x', n=9,
            a='bloom_pink', b='bloom_white')
    # ── SIGNATURE: the great egg, in its cradle ──
    cradle_egg('hygreat', 1.12, 0.5, 0.18, r=0.4)

def fish_hut(w, h):
    """Fish Hut (luxury) — racks, a boat, and a sign with a fish on it.

    A luxury building has to say what it TRADES, and split fish on rails does
    that in one shape. The hut is small and pushed back; the racks and the boat
    take the front, because those are the readable parts.
    """
    plinth('fhbase', 0, 0, w - 0.24, h - 0.24, 0.14)
    bw, bd = 1.15, 0.95
    hx, hy = -w / 2 + 0.85, h / 2 - 0.62
    half_timber('fhwall', hx, hy, 0.14, bw, bd, 0.85, bays=4)
    roof_z = 0.99
    # SLATE: the only cold roof in the settlement, which is what a building
    # standing in water should have.
    shingle_gable('fhroof', hx, hy, roof_z, bw, bd, 0.78, overhang=0.26,
                  rows=22, key='slate', dark='slate_dark', ridge_along='x')
    ridge_crest('fhcrest', hx, hy, roof_z + 0.74, bw + 0.4, axis='x')
    dagged('fhdag', hx, hy - bd / 2 - 0.28, roof_z, bw + 0.5)
    weathervane('fhvane', hx + bw / 2 + 0.06, hy, roof_z + 0.78, 0.4)
    gothic_door('fhdoor', hx, hy - bd / 2, 0.14, 0.42, 0.6)
    leaded_window('fhwin', hx + bw / 2, hy, 0.5, 0.24, 0.3, facing='x')
    hanging_sign('fhsign', hx + 0.72, hy - bd / 2 + 0.1, 0.86, w=0.36)
    lantern('fhlamp', hx - 0.66, hy - bd / 2 + 0.05, 0.86, drop=0.14)
    for i in range(2):
        ry = -h / 2 + 0.5 + i * 0.55
        for s in (-1, 1):
            carved_post(f'fhp{i}{s}', 0.5 + s * 0.75, ry, 0.14, 0.82)
        box(f'fhrail{i}', 0.5, ry, 0.9, 1.6, 0.07, 0.07, mat('oak_light'))
        for k in range(5):
            # Split fish on a rail: a body, a tail and a head, all round.
            # Boxes on a line read as pegged laundry (user 2026-08-12).
            fx_ = 0.5 - 0.6 + k * 0.3
            orb(f'fhfish{i}{k}', fx_, ry, 0.5, 0.19, 0.1, 0.3,
                key='slate' if k % 2 else 'stucco_shade', subdiv=1,
                wobble=0.12, seed=k + i * 3)
            orb(f'fhhead{i}{k}', fx_, ry, 0.74, 0.13, 0.09, 0.12,
                key='slate' if k % 2 else 'stucco_shade', subdiv=0)
            tl = box(f'fhtail{i}{k}', fx_, ry, 0.46, 0.16, 0.04, 0.14,
                     mat('linen'))
            tl.rotation_euler = (0, 0.4, 0)
    bx, by = 0.45, -h / 2 + 0.58
    hull = box('fhboat', bx, by, 0.06, 1.15, 0.44, 0.2, mat('oak'))
    hull.rotation_euler = (0, 0, 0.16)
    box('fhkeel', bx, by, 0.26, 1.1, 0.12, 0.07, mat('oak_light'))
    for k in range(2):
        box(f'fhthwart{k}', bx - 0.24 + k * 0.48, by, 0.24, 0.16, 0.4, 0.05,
            mat('oak_light'))
    oar = box('fhoar', bx - 0.3, by - 0.28, 0.3, 0.9, 0.07, 0.05,
              mat('oak_light'))
    oar.rotation_euler = (0, 0, 0.5)
    box('fhmast', bx + 0.34, by, 0.26, 0.07, 0.07, 0.8, mat('oak'))
    box('fhsail', bx + 0.34, by, 0.5, 0.05, 0.36, 0.5, mat('cloth'))
    for i in range(2):
        box(f'fhcrate{i}', -w / 2 + 0.45, -h / 2 + 0.5 + i * 0.36, 0.14,
            0.3, 0.28, 0.22, mat('oak_light'))
    box('fhnet', -0.6, h / 2 - 0.42, 0.14, 0.5, 0.5, 0.16, mat('straw'))

    # ── WATER AND A BOAT (user 2026-08-09) ──
    # The boat was already here and it was standing on grass, which is the one
    # place a boat says nothing. Cut the dock into the plinth, float the hull
    # in it, and put a pier over the edge — now every part of the yard is about
    # the same thing.
    water_patch('fhdock', 0.35, -h / 2 + 0.62, 2.1, 1.0, z=0.14)
    pier('fhpier', 0.35, -h / 2 + 1.2, 0.16, 1.7, axis='x')
    for i in range(2):
        box(f'fhbol{i}', w / 2 - 1.5 + i * 1.1, -h / 2 + 1.25, 0.16,
            0.12, 0.12, 0.26, mat('oak'))
    net_frame('fhnet0', -w / 2 + 0.5, -h / 2 + 0.7, 0.14, w=0.62, h=0.66)
    net_frame('fhnet1', -w / 2 + 0.5, h / 2 - 0.6, 0.14, w=0.62, h=0.6)
    for i in range(3):
        crate(f'fhcr{i}', -0.35 + i * 0.42, -h / 2 + 0.5, 0.14, s=0.32)
        box(f'fhcatch{i}', -0.35 + i * 0.42, -h / 2 + 0.5, 0.4, 0.22, 0.16,
            0.07, mat('stucco_shade'))
    barrel('fhbar', 0.15, h / 2 - 0.5, 0.14, r=0.18, h=0.38)
    for i in range(3):
        box(f'fhfloat{i}', w / 2 - 1.45 + i * 0.4, -h / 2 + 1.55, 0.14,
            0.16, 0.16, 0.14, mat('cloth_stripe' if i % 2 else 'straw'))
    # ── Eigenleben: the catch is in and the gulls know ──
    chimney('fhchim', hx - bw / 2 + 0.15, hy + 0.3, 0.14, 0.24,
            roof_z + 0.7)
    for i in range(3):
        perch_bird(f'fhgull{i}', w / 2 - 1.4 + i * 0.55, -h / 2 + 1.22, 0.3,
                   kind=i % 2)
    critter('fhcrit', -w / 2 + 0.55, h / 2 - 1.1, 0.14, angle=0.8, kind=2,
            scale=0.8)
    basket('fhbask', -0.5, -h / 2 + 1.6, 0.14, fill='stucco_shade')
    washing('fhwash', -w / 2 + 1.2, h / 2 - 0.45, 0.14, 1.3, axis='x', h=0.85,
            items=3)
    # Accent: BLUE, and sailcloth over the dock — the roof is already cold.
    window_box('fhwb', hx, hy - bd / 2 - 0.09, 0.62, 0.42, bloom='bloom_blue')
    awning('fhsail', 0.35, -h / 2 + 1.62, 0.95, 1.5, 0.8, key='linen',
           stripe='cloth_blue')
    flower_bed('fhbed', -w / 2 + 0.55, h / 2 - 1.4, 0.14, 0.5, 0.34,
               bloom='bloom_white', n=5)
    # ── SIGNATURE: the net, slung and full ──
    hung_net('fhhang', w / 2 - 0.42, -0.35, 0.14, span=1.5, mast=1.3,
             axis='y')

def fur_lodge(w, h):
    """Fur Lodge (luxury) — pelts on hoops, and a smoking fire.

    Same job as the Fish Hut and it must not look like it: the racks there are
    horizontal rails, the frames here are upright, and the material is fur
    rather than fish. Two luxuries that read alike are one luxury drawn twice.
    """
    plinth('flbase', 0, 0, w - 0.24, h - 0.24, 0.14)
    bw, bd = 1.2, 1.0
    hx, hy = w / 2 - 0.85, h / 2 - 0.65
    ashlar_courses('flsill', hx, hy, 0.14, bw + 0.1, bd + 0.1, 0.24,
                   course=0.0648, block=0.125)
    half_timber('flwall', hx, hy, 0.38, bw, bd, 0.84, bays=4)
    roof_z = 1.22
    # HIDES pegged over the shingles — the lodge is roofed in its own trade.
    shingle_gable('flroof', hx, hy, roof_z, bw, bd, 0.85, overhang=0.26,
                  rows=22, key='hide_dark', dark='root_dark',
                  ridge_along='x')
    ridge_crest('flcrest', hx, hy, roof_z + 0.81, bw + 0.4, axis='x')
    dagged('fldag', hx, hy - bd / 2 - 0.28, roof_z, bw + 0.5)
    chimney('flchim', hx + bw / 2 - 0.2, hy + 0.28, 0, 0.26, roof_z + 0.72)
    weathervane('flvane', hx - bw / 2 - 0.06, hy, roof_z + 0.85, 0.4)
    gothic_door('fldoor', hx, hy - bd / 2, 0.38, 0.44, 0.6)
    oriel('flor', hx - bw / 2, hy, 0.72, 0.4, 0.38, facing='x')
    hanging_sign('flsign', hx - 0.74, hy - bd / 2 + 0.1, 1.1, w=0.36)
    lantern('fllamp', hx + 0.68, hy - bd / 2 + 0.05, 1.06, drop=0.14)
    corbel_head('flhead', hx, hy - bd / 2, 1.12)
    for i in range(3):
        if i == 1:
            continue        # the great hoop stands here now
        fx = -w / 2 + 0.62 + i * 0.62
        for s in (-1, 1):
            box(f'flp{i}{s}', fx + s * 0.26, -h / 2 + 0.62, 0.14,
                0.07, 0.07, 0.98, mat('root'))
        box(f'fltop{i}', fx, -h / 2 + 0.62, 1.06, 0.6, 0.07, 0.07,
            mat('root_dark'))
        box(f'flknob{i}', fx, -h / 2 + 0.62, 1.13, 0.12, 0.12, 0.1,
            mat('oak_light'))
        box(f'flpelt{i}', fx, -h / 2 + 0.63, 0.34, 0.44, 0.06, 0.62,
            mat('oak' if i % 2 else 'root'))
    # ── The yard was a jumble (user 2026-08-12: "Sieht unaufgeräumt aus") ──
    # Six separate heaps of brown stood in front of the door, all at prop
    # scale and all the same tone. A tannery is a place of ORDER — the whole
    # trade is racks and lines and bales in rows — so the rolls go onto one
    # rack against the back wall and the front of the house is left clear.
    box('flrack', -w / 2 + 1.24, h / 2 - 0.42, 0.14, 1.3, 0.3, 0.4,
        mat('oak'))
    box('flracktop', -w / 2 + 1.24, h / 2 - 0.42, 0.54, 1.42, 0.38, 0.07,
        mat('oak_light'))
    for i in range(3):
        cyl(f'flroll{i}', -w / 2 + 0.78 + i * 0.46, h / 2 - 0.42, 0.61,
            0.11, 0.34, sides=10, axis='y',
            key='hide' if i % 2 else 'hide_dark')
    brazier('flbraz', -w / 2 + 0.5, -h / 2 + 1.15, 0.14)
    if h >= 3:
        # A drying line across the new depth, and the trapper's pack under it.
        for s_ in (-1, 1):
            box(f'flline{s_}', -w / 2 + 0.45 + (s_ + 1) * 0.9, 0.55, 0.14,
                0.08, 0.08, 1.0, mat('root'))
        box('fllinet', -w / 2 + 1.35, 0.55, 1.12, 1.9, 0.06, 0.06,
            mat('root_dark'))
        for i in range(3):
            box(f'flhang{i}', -w / 2 + 0.75 + i * 0.6, 0.56, 0.55,
                0.42, 0.05, 0.56,
                mat('hide' if i % 2 else 'hide_dark'))
        sack_pile('flpack', -w / 2 + 0.5, -h / 2 + 0.5, 0.14, n=2)

    # ── A tannery works: a vat, bales, and a cart to take them ──
    cauldron('flvat', -w / 2 + 0.55, h / 2 - 0.55, 0.14, r=0.26)
    cart('flcart', w / 2 - 0.95, -h / 2 + 1.6, 0.14, angle=-0.35,
         load='sack')
    for i in range(3):
        straw_bale(f'flbale{i}', -w / 2 + 0.62, -h / 2 + 0.6 + i * 0.34, 0.14,
                   0.36, 0.26, 0.24, key='hide' if i % 2 else 'hide_dark')
    tool_rack('fltools', -w / 2 + 0.35, -0.2, 0.14, w=0.6, facing='x')
    crate('flcr', w / 2 - 0.45, -h / 2 + 0.5, 0.14, s=0.34)
    # ── Eigenleben: the vat is on and the dog is out ──
    critter('flcrit', -w / 2 + 1.05, -h / 2 + 0.55, 0.14, angle=0.4, kind=1)
    fowl('flfowl', w / 2 - 1.5, h / 2 - 0.5, 0.14, angle=2.6)
    basket('flbask', -w / 2 + 0.45, 0.55, 0.14, fill='hide')
    perch_bird('flbird', hx, hy - bd / 2 - 0.2, roof_z + 0.9, kind=1)
    # Accent: PLUM against the hide roof.
    window_box('flwb', hx, hy - bd / 2 - 0.09, 0.7, 0.44, bloom='bloom_plum'
               if False else 'bloom_pink')
    curtain('flcurt', hx, hy - bd / 2 - 0.12, 0.38, 0.44, 0.55,
            key='cloth_plum')
    flower_bed('flbed', w / 2 - 0.5, h / 2 - 0.5, 0.14, 0.5, 0.34,
               bloom='bloom_red', n=5)
    # ── SIGNATURE: the bear on its hoop, and the rack over the door ──
    hoop_pelt('flhoop', -0.3, -h / 2 + 0.66, 0.14, r=0.5, post=0.7)
    antlers('flrack', 0.72, -h / 2 + 0.55, 0.14, span=0.34, post=1.05)

def church(w, h):
    """Church — a nave five cells long with a tower at its west end.

    ── 3 x 5 with a tower (user 2026-08-12) ──
    It was 5 x 5 and called the Grand Works: a square block with four corner
    turrets, which reads as a keep. What makes a church a church from above is
    the PROPORTION — a long narrow ridge with one thing standing at the end of
    it — so the plot went long and narrow and everything else followed.

    The tower is at +y, the far end, so the nave runs down towards the camera
    and the tower rises clear behind it against nothing.
    """
    plinth('chbase', 0, 0, w - 0.2, h - 0.2, 0.18)
    tw = min(1.5, w - 1.1)
    ty = h / 2 - tw / 2 - 0.4
    bw, bd = w - 1.0, h - tw - 1.1
    by = -h / 2 + bd / 2 + 0.5
    # ── The nave ──
    ashlar_courses('chnave', 0, by, 0.18, bw, bd, 1.7, course=0.0972,
                   block=0.1786)
    string_course('chband', 0, by, 1.5, bw + 0.02, bd + 0.02)
    for s_ in (-1, 1):
        for i in range(4):
            byy = by - bd / 2 + 0.55 + i * (bd - 1.1) / 3
            box(f'chbut{s_}{i}', s_ * (bw / 2 + 0.13), byy, 0.18, 0.28, 0.3,
                1.35, mat('ashlar'))
            box(f'chbutc{s_}{i}', s_ * (bw / 2 + 0.13), byy, 1.53, 0.34, 0.36,
                0.1, mat('limestone'))
            box(f'chbutp{s_}{i}', s_ * (bw / 2 + 0.13), byy, 1.63, 0.14, 0.14,
                0.24, mat('limestone_shade'))
            leaded_window(f'chwin{s_}{i}', s_ * bw / 2, byy + 0.42, 0.72, 0.26,
                          0.66, facing='x', shutters=False)
    roof_z = 1.88
    shingle_gable('chroof', 0, by, roof_z, bw + 0.16, bd + 0.16, 1.2,
                  overhang=0.3, rows=28, key='verdigris',
                  dark='verdigris_dark', ridge_along='y')
    ridge_crest('chcrest', 0, by, roof_z + 1.16, bd + 0.6, axis='y')
    face = by - bd / 2
    dagged('chdag', 0, face - 0.32, roof_z, bw + 0.7)
    gable_boards('chgab', 0, face - 0.28, roof_z, bw + 0.6, 1.1, axis='x')
    rose_window('chrose', 0, face - 0.3, roof_z + 0.34, 0.32)
    gothic_door('chdoor', 0, face, 0.18, 0.72, 1.15, rim=0.2)
    box('chleaf', 0, face - 0.08, 0.2, 0.62, 0.08, 0.86, mat('oak'))
    for k in range(3):
        box(f'chband{k}', 0, face - 0.13, 0.34 + k * 0.26, 0.52, 0.05, 0.07,
            mat('iron'))
    for s_ in (-1, 1):
        sconce(f'chlamp{s_}', s_ * 0.56, face, 1.0)
        corbel_head(f'chhead{s_}', s_ * (bw / 2 - 0.1), face, 1.42)
    # ── The tower ──
    ashlar_courses('chtow', 0, ty, 0.18, tw, tw, 3.1, course=0.1022,
                   block=0.1886)
    for f in (0.34, 0.68):
        string_course(f'chtb{f}', 0, ty, 0.18 + 3.1 * f, tw + 0.04, tw + 0.04)
    for s_ in (-1, 1):
        arrow_slit(f'chsl{s_}', s_ * 0.3, ty - tw / 2, 1.15, 0.5)
        arrow_slit(f'chsl2{s_}', s_ * 0.3, ty - tw / 2, 2.0, 0.5)
    # The belfry stage: openings you can see through, which is what makes a
    # tower a bell tower rather than a chimney.
    for s_ in (-1, 1):
        gothic_arch(f'chbel{s_}', 0, ty + s_ * tw / 2, 2.5, tw - 0.5, 0.62,
                    0.16)
        gothic_arch(f'chbex{s_}', s_ * tw / 2, ty, 2.5, tw - 0.5, 0.62, 0.16,
                    facing='x')
    battlements('chcrown', 0, ty, 3.28, tw, tw, h=0.3, merlon=0.115,
                gap=0.09)
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            turret(f'chpin{sx_}{sy_}', sx_ * (tw / 2 - 0.02),
                   ty + sy_ * (tw / 2 - 0.02), 3.28, 0.13, 0.5, spire_h=0.55)
    spire('chsp', 0, ty, 3.58, tw * 0.62, 1.5, sides=8, key='verdigris',
          dark='verdigris_dark')
    finial('chfin', 0, ty, 5.08, 0.34)
    bell('chbell', 0, ty, 2.42, r=0.17)
    banner('chflag', 0, ty - tw / 2 - 0.02, 2.3, 0.28, 0.5)
    # ── The churchyard ──
    steps('chsteps', 0, -h / 2 + 0.42, 0, 1.4, count=3, rise=0.06,
          tread=0.14, key='limestone')
    for s_ in (-1, 1):
        # A churchyard cross and a few graves: consecrated ground is what a
        # church stands in, and it costs six boxes.
        cyl(f'chcr{s_}', s_ * (w / 2 - 0.4), -h / 2 + 1.3, 0.18, 0.05, 0.55,
            sides=8, key='limestone')
        box(f'chcra{s_}', s_ * (w / 2 - 0.4), -h / 2 + 1.3, 0.6, 0.24, 0.06,
            0.06, mat('limestone'))
        for i in range(2):
            gr = box(f'chgr{s_}{i}', s_ * (w / 2 - 0.42),
                     -h / 2 + 2.1 + i * 0.5, 0.18, 0.2, 0.06, 0.24,
                     mat('limestone_shade'))
            gr.rotation_euler = (0.1 * (i - 0.5), 0, 0.08)
    brazier('chbraz', -w / 2 + 0.42, -h / 2 + 0.6, 0.18)
    critter('chcrit', 0.5, -h / 2 + 0.62, 0.18, angle=1.1, kind=0, scale=0.85)
    for i in range(3):
        perch_bird(f'chbird{i}', -0.5 + i * 0.5, face - 0.3,
                   roof_z + 0.06 + (i % 2) * 0.06, kind=i)
    flower_bed('chbed', 0, -h / 2 + 1.05, 0.18, 0.8, 0.34,
               bloom='bloom_white', n=7)
    tufts('chtuft', 0, 0, w - 0.5, h - 0.5)


def marketplace(w, h):
    """Marketplace — a PLACE, not a building.

    ── "soll ein Platz sein, nicht ein Gebäude" (user 2026-08-12) ──
    It was the Primitive Treasury: a strongtower with a hoard on its steps. A
    market is the opposite idea — it is the empty ground that everything is
    carried into, so nothing here is roofed in anything but cloth, and the one
    permanent thing on it is the CROSS: the stone every market in Europe was
    held around, and the thing that makes bare paving read as a market square
    rather than as a yard.
    """
    plinth('mkbase', 0, 0, w - 0.2, h - 0.2, 0.14)
    paving('mkfloor', 0, 0, 0.14, w - 0.5, h - 0.5, key_a='ashlar',
           key_b='ashlar_dark', tile=0.17)
    # ── The market cross ──
    for k, (r_, hz) in enumerate(((0.85, 0.1), (0.68, 0.1), (0.52, 0.1))):
        lathe(f'mkstep{k}', 0, 0.15, 0.14 + k * 0.1,
              [(r_, 0.0), (r_ * 0.97, hz)], sides=8, key='limestone',
              smooth=False)
    cyl('mkshaft', 0, 0.15, 0.44, 0.075, 1.15, sides=8, taper=0.86,
        key='limestone')
    for i in range(4):
        a = 3.1416 / 2 * i + 0.4
        box(f'mkcorb{i}', 0.14 * math.cos(a), 0.15 + 0.14 * math.sin(a), 1.5,
            0.12, 0.12, 0.12, mat('limestone_shade'))
    lathe('mkhead', 0, 0.15, 1.56, [(0.16, 0.0), (0.2, 0.12), (0.14, 0.26)],
          sides=8, key='limestone')
    finial('mkfin', 0, 0.15, 1.82, 0.26)
    # ── The stalls: cloth, trestles, and what is on them ──
    stalls = ((-w / 2 + 0.85, h / 2 - 0.75, 'y'), (w / 2 - 0.85, h / 2 - 0.8, 'y'),
              (-w / 2 + 0.8, -h / 2 + 1.15, 'x'), (w / 2 - 0.8, -h / 2 + 1.1, 'x'))
    for i, (sx_, sy_, ax) in enumerate(stalls):
        for t in (-1, 1):
            px = sx_ + (t * 0.42 if ax == 'x' else 0)
            py = sy_ + (0 if ax == 'x' else t * 0.42)
            cyl(f'mkp{i}{t}', px, py, 0.14, 0.036, 1.0, sides=8, key='oak')
        bw_, bd_ = ((0.95, 0.5) if ax == 'x' else (0.5, 0.95))
        box(f'mkbench{i}', sx_, sy_, 0.14, bw_, bd_, 0.44, mat('oak'))
        box(f'mktop{i}', sx_, sy_, 0.58, bw_ + 0.12, bd_ + 0.12, 0.06,
            mat('oak_light'))
        awning(f'mkaw{i}', sx_, sy_ - (0.28 if ax == 'x' else 0), 1.0,
               bw_ + 0.2, bd_ + 0.2, facing='y' if ax == 'x' else 'x',
               stripe=('cloth_red', 'cloth_teal', 'cloth_plum',
                       'cloth_blue')[i])
        for k in range(3):
            ox = (-0.3 + k * 0.3) if ax == 'x' else 0.0
            oy = 0.0 if ax == 'x' else (-0.3 + k * 0.3)
            if i == 0:
                basket(f'mkw{i}{k}', sx_ + ox, sy_ + oy, 0.64, r=0.14,
                       h=0.2, fill='leaf')
            elif i == 1:
                pot(f'mkw{i}{k}', sx_ + ox, sy_ + oy, 0.64, r=0.11, h=0.28)
            elif i == 2:
                box(f'mkw{i}{k}', sx_ + ox, sy_ + oy, 0.64, 0.22, 0.2, 0.16,
                    mat('cloth_stripe' if k % 2 else 'cloth'))
            else:
                orb(f'mkw{i}{k}', sx_ + ox, sy_ + oy, 0.64, 0.2, 0.2, 0.16,
                    key='gold' if k % 2 else 'banner', wobble=0.25, seed=k)
    # ── The money changer: the gold this building is for ──
    mx, my = 0.95, -0.7
    box('mktable', mx, my, 0.14, 0.7, 0.5, 0.42, mat('oak'))
    box('mktabletop', mx, my, 0.56, 0.82, 0.6, 0.07, mat('oak_light'))
    scales('mkscales', mx - 0.05, my, 0.63, span=0.5, h=0.42)
    gold_pile('mkgold', mx + 0.24, my - 0.02, 0.63, r=0.16, bars=False)
    box('mkchest', mx - 0.02, my + 0.42, 0.14, 0.44, 0.3, 0.26, mat('oak'))
    ring('mkchesth', mx - 0.02, my + 0.42, 0.28, 0.2, 0.02, key='iron',
         axis='y', sides=10, tube_sides=5)
    # ── Everything else a market has ──
    well('mkwell', -w / 2 + 0.9, -0.5, 0.14, r=0.3)
    for s_ in (-1, 1):
        cyl(f'mkbpost{s_}', s_ * (w / 2 - 0.42), 0.55, 0.14, 0.05, 1.5,
            sides=8, key='oak')
    bunting('mkbunt', 0, 0.55, 1.62, w - 0.84, axis='x', n=13)
    signpost('mksign', -w / 2 + 0.45, h / 2 - 0.5, 0.14, arms=2)
    cart('mkcart', 0.15, h / 2 - 0.95, 0.14, angle=1.5, load='barrel')
    for i in range(2):
        barrel(f'mkbar{i}', -0.85, -h / 2 + 0.6 + i * 0.5, 0.14, r=0.17,
               h=0.36)
    crate('mkcr', -1.35, -h / 2 + 0.55, 0.14, s=0.34)
    sack_pile('mksack', 1.5, h / 2 - 1.4, 0.14, n=3)
    straw_scatter('mkstraw', 0.4, -h / 2 + 0.5, 0.14, 0.5, n=12)
    # ── A market is PEOPLE ──
    for i, (ox, oy, k, sc) in enumerate(((-0.55, -1.15, 0, 1.0),
                                         (0.35, -1.35, 2, 0.8),
                                         (-1.2, 0.75, 1, 0.9),
                                         (1.25, 0.95, 0, 0.85))):
        critter(f'mkcrit{i}', ox, oy, 0.14, angle=0.4 + i * 1.6, kind=k,
                scale=sc)
    for i in range(3):
        fowl(f'mkfowl{i}', -0.2 + i * 0.45, 0.05, 0.14, angle=0.6 + i * 2.0,
             kind=i % 2)
    for i in range(2):
        perch_bird(f'mkbird{i}', -0.1 + i * 0.3, 0.15, 1.9, kind=i)
    flower_bed('mkbed', -w / 2 + 0.5, h / 2 - 1.4, 0.14, 0.5, 0.34,
               bloom='bloom_pink', n=5)


def clay_refinery(w, h):
    """Clay Refinery — the framing floor, and the clay that fills it.

    It crafts TIMBER FRAME out of clay and wood, eight workers at a time, and
    that is a real medieval yard with a real shape: the ABBUNDPLATZ, a level
    timber floor on which a frame is laid out flat, fitted, numbered and taken
    apart again before it is ever raised. Beside it the pug mill and the
    puddling pit that make the daub for its panels.

    So the building is a FLOOR with a half-built frame lying on it — the one
    silhouette on the map that is horizontal on purpose.
    """
    plinth('crbase', 0, 0, w - 0.3, h - 0.3, 0.16)
    hw, hh_ = w / 2, h / 2

    # ── THE FRAMING FLOOR ──
    fx, fy = -0.35, hh_ - 1.5
    fw, fd = w - 1.5, 1.9
    for i in range(9):
        box(f'crfl{i}', fx, fy - fd / 2 + (i + 0.5) * fd / 9, 0.16,
            fw, fd / 9 * 0.9, 0.07,
            mat('oak' if i % 2 else 'oak_light'))
    # The frame itself, lying flat: sill, posts, tie beam, braces — the shape
    # a wall is before anybody stands it up.
    box('crsill', fx, fy - 0.62, 0.23, fw - 0.3, 0.16, 0.11, mat('oak'))
    box('crplate', fx, fy + 0.62, 0.23, fw - 0.3, 0.16, 0.11, mat('oak'))
    for i in range(4):
        px = fx - (fw - 0.3) / 2 + (i + 0.5) * (fw - 0.3) / 4
        box(f'crpost{i}', px, fy, 0.23, 0.13, 1.2, 0.1, mat('oak_light'))
        peg(f'crpg{i}', px, fy - 0.62, 0.34)
        peg(f'crpg2{i}', px, fy + 0.62, 0.34)
    for s_ in (-1, 1):
        br = box(f'crbr{s_}', fx + s_ * (fw / 2 - 0.55), fy, 0.24, 0.62, 0.1,
                 0.09, mat('oak'))
        br.rotation_euler = (0, 0, s_ * 0.72)
    # The panels that go in it, woven and waiting.
    for i in range(3):
        withy_fence(f'crpan{i}', fx - 0.7 + i * 0.7, fy + 1.15, 0.16, 0.6,
                    h=0.5, axis='x')

    # ── THE PUG MILL: a beast walks it, and that is why it is round ──
    mx, my = hw - 1.15, -hh_ + 1.25
    lathe('crtrough', mx, my, 0.16, [(0.86, 0.0), (0.9, 0.1), (0.72, 0.12),
                                     (0.7, 0.02)], sides=16, key='ashlar')
    box('crclay', mx, my, 0.2, 1.3, 1.3, 0.06, mat('dirt'))
    cyl('crpost', mx, my, 0.16, 0.075, 1.15, sides=12, key='oak')
    for i in range(3):
        strap(f'crband{i}', mx, my, 0.4 + i * 0.32, 0.2, 0.2, bolts=1,
              round_=0.095)
    arm = box('crarm', mx - 0.5, my, 1.16, 1.5, 0.11, 0.11, mat('oak_light'))
    arm.rotation_euler = (0, 0, 0.2)
    for i in range(4):
        a = 2 * math.pi * i / 4 + 0.3
        blade = box(f'crblade{i}', mx + 0.5 * math.cos(a),
                    my + 0.5 * math.sin(a), 0.24, 0.34, 0.08, 0.28,
                    mat('steel'))
        blade.rotation_euler = (0, 0, a + 0.6)
    pack_beast('crbeast', mx - 1.05, my + 0.42, 0.16, angle=1.4, hump=False)
    tube('crtrace', [(mx - 1.28, my - 0.1, 0.16 + 0.5),
                     (mx - 0.62, my + 0.02, 1.14)], r=0.022, key='root')

    # ── THE PIT: where the clay comes from ──
    px_, py_ = -hw + 0.95, -hh_ + 1.05
    # water_patch() drew a clear blue pond, which is what a DOCK wants and the
    # opposite of what a puddling pit is: the whole point of the thing is that
    # the water is full of clay. Cut into the plinth, filled with slurry, with
    # a wet sheen only where it has been worked.
    box('crcut', px_, py_, 0.02, 1.5, 1.3, 0.14, mat('root_dark'))
    box('crslurry', px_, py_, 0.14, 1.34, 1.14, 0.05, mat('dirt'))
    box('crwet', px_ + 0.1, py_ - 0.05, 0.19, 0.8, 0.6, 0.02,
        mat('root'))
    for i in range(3):
        j = _hash01(f'crw{i}')
        orb(f'crbub{i}', px_ - 0.4 + i * 0.36, py_ + 0.1 + j * 0.3, 0.19,
            0.16 + 0.08 * j, 0.14, 0.04, key='dirt', subdiv=0)
    for i in range(4):
        j = _hash01(f'cr{i}')
        crag(f'crlump{i}', px_ - 0.4 + i * 0.3, py_ - 0.62 - j * 0.2, 0.16,
             0.3 + 0.14 * j, 0.28, 0.2 + 0.1 * j, key='dirt', seed=30 + i)
    box('crspade', px_ + 0.55, py_ + 0.3, 0.16, 0.06, 0.06, 0.85, mat('oak'))
    box('crblade', px_ + 0.55, py_ + 0.3, 0.16, 0.2, 0.16, 0.22, mat('steel'))

    # ── THE SHELTER over the finished work ──
    sx, sy = -hw + 1.15, hh_ - 0.85
    for s_ in (-1, 1):
        carved_post(f'crsp{s_}', sx + s_ * 0.72, sy - 0.42, 0.16, 1.25)
        box(f'crsb{s_}', sx + s_ * 0.72, sy + 0.42, 0.16, 0.13, 0.13, 1.55,
            mat('oak'))
    lean_to('crroof', sx, sy, 1.55, 1.75, 1.1, 0.2, drop=0.34, key='shingle',
            courses=12)
    dagged('crdag', sx, sy - 0.6, 1.34, 1.8)
    for i in range(3):
        for k in range(2):
            box(f'crstack{i}{k}', sx - 0.5 + i * 0.5, sy, 0.16 + k * 0.16,
                0.42, 0.9, 0.14, mat('oak_light' if k % 2 else 'oak'))

    # ── The work is WORK ──
    tool_rack('crtools', hw - 0.5, hh_ - 1.0, 0.16, w=0.7, facing='x')
    barrel('crbar', hw - 0.5, 0.35, 0.16, r=0.18, h=0.38)
    for i in range(2):
        crate(f'crcr{i}', -hw + 0.55, hh_ - 2.5 - i * 0.45, 0.16, s=0.34)
    sack_pile('crsack', 0.55, -hh_ + 0.55, 0.16, n=3)
    brazier('crfire', -0.65, -hh_ + 0.5, 0.16)
    critter('crcrit0', 0.15, -hh_ + 1.05, 0.16, angle=1.2, kind=1)
    critter('crcrit1', -hw + 1.9, hh_ - 0.6, 0.16, angle=2.5, kind=0,
            scale=0.85)
    fowl('crfowl', hw - 1.5, hh_ - 2.6, 0.16, angle=0.7)
    washing('crwash', -hw + 0.5, 0.4, 0.16, 1.2, axis='y', h=0.9, items=3)
    banner('crflag', sx, sy - 0.64, 1.6, 0.28, 0.46)
    flower_bed('crbed', hw - 0.55, hh_ - 2.0, 0.16, 0.5, 0.34,
               bloom='bloom_white', n=5)
    tufts('crtuft', 0, 0, w - 0.5, h - 0.5)


def training_grounds(w, h):
    """Training Grounds — a fighting RING, because the fighters are monsters.

    ── Not a drill yard (user 2026-08-12) ──
    "diese haben keine Waffen, Daher mehr einen Kampfring machen." The first
    draft had a pell, a butt and a quintain; all three are human weapons and
    all three are gone.

    A creature trains on something to spar with, something that swings back,
    something heavy to drag and something to jump — inside a rope ring on
    beaten sand, which is the only circle drawn on the ground anywhere on the
    map.
    """
    box('tgfloor', 0, 0, 0, w - 0.3, h - 0.3, 0.14, mat('dirt'))
    hw, hh_ = w / 2, h / 2
    rx, ry, rr = -0.1, 0.15, min(w, h) / 2 - 0.62

    # ── THE RING ──
    # Pale sand against the dark yard, and proud of it: the ring is the
    # building, and at 0.04 above a dirt floor it simply did not read.
    lathe('tgsand', rx, ry, 0.12, [(rr + 0.24, 0.0), (rr + 0.2, 0.09),
                                   (rr + 0.16, 0.11)],
          sides=22, key='sand', smooth=False)
    lathe('tgworn', rx, ry, 0.23, [(rr * 0.66, 0.0), (rr * 0.64, 0.015)],
          sides=18, key='dirt', smooth=False)
    straw_scatter('tgscuff', rx, ry, 0.245, rr * 0.85, n=16,
                  key='sand')
    posts = 8
    for i in range(posts):
        a0 = 2 * math.pi * i / posts + 0.2
        a1 = 2 * math.pi * (i + 1) / posts + 0.2
        px, py = rx + rr * math.cos(a0), ry + rr * math.sin(a0)
        nx, ny = rx + rr * math.cos(a1), ry + rr * math.sin(a1)
        cyl(f'tgpost{i}', px, py, 0.22, 0.06, 0.78, sides=8, taper=0.86,
            key='oak')
        lathe(f'tgcap{i}', px, py, 0.9, [(0.085, 0.0), (0.055, 0.06)],
              sides=8, key='oak_light')
        for k, hz in enumerate((0.4, 0.68)):
            catenary(f'tgrope{i}{k}', (px, py, 0.22 + hz),
                     (nx, ny, 0.22 + hz), sag=0.05, r=0.022,
                     key='straw' if k else 'root')

    # ── THE SPARRING DUMMY: something with a BODY, to be bitten ──
    dx, dy = rx + rr * 0.52, ry + rr * 0.42
    cyl('tgdpost', dx, dy, 0.22, 0.07, 0.72, sides=10, key='oak')
    orb('tgdbody', dx, dy, 0.62, 0.46, 0.4, 0.5, key='straw', wobble=0.22,
        seed=2)
    orb('tgdhead', dx, dy - 0.12, 1.02, 0.28, 0.26, 0.26, key='straw',
        wobble=0.24, seed=5)
    for s_ in (-1, 1):
        orb(f'tgdear{s_}', dx + s_ * 0.1, dy - 0.1, 1.2, 0.1, 0.09, 0.13,
            key='root', subdiv=0)
        orb(f'tgdarm{s_}', dx + s_ * 0.26, dy - 0.05, 0.78, 0.16, 0.15, 0.3,
            key='hide', wobble=0.2, seed=7 + s_)
    for k in range(3):
        ring(f'tgdband{k}', dx, dy, 0.5 + k * 0.2, 0.24 - k * 0.03, 0.022,
             key='root', sides=10, tube_sides=5)
    # Straw hanging out of it is the whole story: it has been BITTEN.
    for i in range(5):
        j = _hash01(f'tgd{i}')
        tuft = box(f'tgdtear{i}', dx + (j - 0.5) * 0.44, dy - 0.2 - j * 0.06,
                   0.55 + j * 0.4, 0.16, 0.06, 0.05, mat('straw'))
        tuft.rotation_euler = (0, 0.5 * (j - 0.5), j * 3.0)
    straw_scatter('tgdfloor', dx, dy - 0.3, 0.16, 0.4, n=10)

    # ── THE HANGING LOG: it swings back, which is the point ──
    lx, ly = rx - rr * 0.5, ry + rr * 0.5
    for s_ in (-1, 1):
        leg = cyl(f'tglleg{s_}', lx + s_ * 0.34, ly, 0.22, 0.055, 1.35,
                  sides=8, key='oak')
        leg.rotation_euler = (0, -s_ * 0.2, 0)
    cyl('tglbeam', lx, ly, 1.42, 0.055, 0.8, sides=8, axis='x',
        key='oak_light')
    for s_ in (-1, 1):
        catenary(f'tglrope{s_}', (lx + s_ * 0.2, ly, 1.42),
                 (lx + s_ * 0.16, ly, 0.82), sag=0.02, r=0.02, key='root')
    log = cyl('tglog', lx, ly, 0.72, 0.14, 0.7, sides=10, axis='x', key='oak')
    log.rotation_euler = (0, 0, 0.12)
    for k in range(2):
        ring(f'tglband{k}', lx - 0.2 + k * 0.4, ly, 0.72, 0.145, 0.02,
             key='steel', axis='x', sides=10, tube_sides=5)

    # ── THE DRAG STONE and the JUMP: strength, then agility ──
    sx_, sy_ = rx - rr * 0.55, ry - rr * 0.55
    crag('tgstone', sx_, sy_, 0.22, 0.52, 0.46, 0.36, key='rock', seed=11)
    ring('tgsring', sx_ + 0.2, sy_ - 0.2, 0.3, 0.1, 0.022, key='steel',
         axis='x', sides=12, tube_sides=5)
    catenary('tgdrag', (sx_ + 0.24, sy_ - 0.24, 0.3),
             (sx_ + 0.8, sy_ - 0.5, 0.18), sag=0.06, r=0.022, key='root')
    jx, jy = rx + rr * 0.15, ry - rr * 0.78
    for s_ in (-1, 1):
        cyl(f'tgjp{s_}', jx + s_ * 0.5, jy, 0.22, 0.05, 0.85, sides=8,
            key='oak')
        for k in range(3):
            box(f'tgjn{s_}{k}', jx + s_ * 0.5, jy - 0.06, 0.34 + k * 0.2,
                0.05, 0.09, 0.05, mat('steel'))
    cyl('tgbar', jx, jy, 0.78, 0.038, 1.05, sides=8, axis='x',
        key='oak_light')

    # ── The yard around it ──
    withy_fence('tgfen0', 0, -hh_ + 0.26, 0.14, w - 0.7, h=0.44, axis='x')
    withy_fence('tgfen1', -hw + 0.26, -0.4, 0.14, h - 1.5, h=0.44, axis='y')
    box('tgbench', hw - 0.5, hh_ - 1.15, 0.14, 0.3, 0.95, 0.3, mat('oak'))
    box('tgbtop', hw - 0.5, hh_ - 1.15, 0.44, 0.4, 1.05, 0.07,
        mat('oak_light'))
    trough('tgtr', -hw + 0.5, hh_ - 0.75, 0.14, 0.26, 0.62, key='oak')
    box('tgwater', -hw + 0.5, hh_ - 0.75, 0.28, 0.18, 0.5, 0.04, mat('water'))
    basket('tgfeed', -hw + 0.5, hh_ - 1.5, 0.14, fill='straw')
    straw_bale('tgbale', hw - 0.55, -hh_ + 0.6, 0.14, 0.4, 0.28, 0.26)
    # Harness and collars, not weapons: the only rack a monster yard has.
    cyl('tghp0', hw - 0.45, -hh_ + 1.2, 0.14, 0.04, 0.95, sides=8, key='oak')
    cyl('tghp1', hw - 0.45, -hh_ + 1.8, 0.14, 0.04, 0.95, sides=8, key='oak')
    cyl('tghbar', hw - 0.45, -hh_ + 1.5, 1.05, 0.035, 0.7, sides=8, axis='y',
        key='oak_light')
    for i in range(3):
        ring(f'tgcollar{i}', hw - 0.45, -hh_ + 1.26 + i * 0.24, 0.86, 0.1,
             0.022, key='hide', axis='y', sides=10, tube_sides=5)
    for s_ in (-1, 1):
        cyl(f'tgbp{s_}', rx + s_ * (rr + 0.42), ry + 0.1, 0.14, 0.05, 1.45,
            sides=8, key='oak')
        banner(f'tgflag{s_}', rx + s_ * (rr + 0.42), ry - 0.02, 1.15, 0.26,
               0.44)
    bunting('tgbunt', rx, ry - rr - 0.32, 1.0, rr * 1.5, axis='x', n=9,
            a='cloth_red', b='cloth_gold')

    # ── And two of them going at it ──
    critter('tgfight0', rx - 0.34, ry - 0.12, 0.18, angle=0.9, kind=0)
    critter('tgfight1', rx + 0.36, ry + 0.06, 0.18, angle=3.9, kind=1)
    critter('tgwait', hw - 0.75, hh_ - 1.15, 0.14, angle=2.4, kind=2,
            scale=0.8)
    fowl('tgfowl', -hw + 1.1, -hh_ + 0.6, 0.14, angle=1.6)
    tufts('tgtuft', 0, 0, w - 0.4, h - 0.4)


def workshop(w, h):
    """Workshop — a master's shed, and the ring of stones it is named for.

    ONE worker at first, one more each level, crafting `research`. So it is
    not a manufactory: it is one person's bench, and what it shows is THINKING
    made physical — a drawing board with a plan pinned to it, a pole lathe, a
    half-built mechanism of gears that is plainly not finished.

    The id is `thinker_circle`, which is older than the name and better than
    it. The ring of low stones outside is that name kept: somewhere to sit and
    work a problem, which is the other half of the trade.
    """
    plinth('wsbase', 0, 0, w - 0.24, h - 0.24, 0.15)
    hw, hh_ = w / 2, h / 2
    bw, bd = w - 1.2, h - 1.75
    hx, hy = -0.15, hh_ - bd / 2 - 0.4

    ashlar_courses('wssill', hx, hy, 0.15, bw + 0.12, bd + 0.12, 0.26,
                   course=0.0662, block=0.1289)
    half_timber('wswall', hx, hy, 0.41, bw, bd, 1.05, bays=5)
    roof_z = 1.46
    shingle_gable('wsroof', hx, hy, roof_z, bw, bd, 1.0, overhang=0.3,
                  rows=24, ridge_along='x')
    ridge_crest('wscrest', hx, hy, roof_z + 0.96, bw + 0.5, axis='x')
    moss('wsmoss', hx, hy, roof_z, bw * 0.6, bd * 0.6, 0.5, overhang=0.0,
         patches=7)
    face = hy - bd / 2
    dagged('wsdag', hx, face - 0.32, roof_z, bw + 0.6)
    gable_boards('wsgab', hx, face - 0.28, roof_z, bw + 0.55, 0.92, axis='x')
    weathervane('wsvane', hx + bw / 2 + 0.06, hy, roof_z + 1.0, 0.42)
    chimney('wschim', hx - bw / 2 + 0.22, hy + 0.34, 0, 0.28, roof_z + 0.9)
    smoke('wssmoke', hx - bw / 2 + 0.22, hy + 0.34, roof_z + 0.96, h=0.7)
    # OPEN-FRONTED: you have to be able to see the bench, or the building is
    # a shed with a weathervane.
    box('wsdark', hx, face + 0.14, 0.41, bw - 0.55, 0.1, 1.0, mat('dark'))
    for s_ in (-1, 1):
        carved_post(f'wsp{s_}', hx + s_ * (bw / 2 - 0.16), face, 0.41, 1.05)
    box('wslint', hx, face, 1.44, bw - 0.06, 0.2, 0.14, mat('oak_light'))
    leaded_window('wswinx', hx + bw / 2, hy + 0.14, 0.78, 0.26, 0.32,
                  facing='x')
    hanging_sign('wssign', hx + bw / 2 + 0.1, hy - 0.28, 1.25, w=0.34,
                 facing='x')
    for s_ in (-1, 1):
        sconce(f'wslamp{s_}', hx + s_ * (bw / 2 - 0.3), face, 1.16)

    # ── THE DRAWING BOARD: a plan, pinned, at an angle ──
    dx, dy = hx + 0.5, face - 0.02
    for s_ in (-1, 1):
        cyl(f'wsdl{s_}', dx + s_ * 0.26, dy - 0.1, 0.15, 0.035, 0.62,
            sides=8, key='oak')
    board = box('wsboard', dx, dy - 0.14, 0.72, 0.66, 0.5, 0.05,
                mat('oak_light'))
    board.rotation_euler = (0.62, 0, 0)
    plan = box('wsplan', dx, dy - 0.17, 0.78, 0.54, 0.4, 0.02, mat('linen'))
    plan.rotation_euler = (0.62, 0, 0)
    for i in range(3):
        ln = box(f'wsline{i}', dx - 0.16 + i * 0.16, dy - 0.19, 0.8, 0.02,
                 0.3, 0.01, mat('steel_dark'))
        ln.rotation_euler = (0.62, 0, 0)

    # ── THE POLE LATHE: a springy pole, a cord, a treadle ──
    lx, ly = hx - 0.62, face - 0.06
    for s_ in (-1, 1):
        cyl(f'wsll{s_}', lx + s_ * 0.32, ly, 0.15, 0.045, 0.52, sides=8,
            key='oak')
    box('wsbed', lx, ly, 0.66, 0.85, 0.24, 0.09, mat('oak'))
    cyl('wswork', lx, ly, 0.75, 0.07, 0.62, sides=10, axis='x',
        key='oak_light')
    pole = box('wspole', lx, ly + 0.1, 1.5, 0.05, 0.05, 1.15, mat('root'))
    pole.rotation_euler = (0.34, 0, 0)
    catenary('wscord', (lx, ly - 0.16, 1.52), (lx, ly - 0.06, 0.5), sag=0.04,
             r=0.014, key='straw')
    box('wstreadle', lx, ly - 0.18, 0.15, 0.5, 0.14, 0.05, mat('oak_light'))
    straw_scatter('wsshav', lx, ly - 0.34, 0.15, 0.34, n=10, key='oak_light')

    # ── THE MECHANISM: gears, and plainly not finished ──
    gx, gy = hw - 0.62, -hh_ + 1.15
    box('wstable', gx, gy, 0.15, 0.62, 0.5, 0.4, mat('oak'))
    box('wstabletop', gx, gy, 0.55, 0.74, 0.6, 0.06, mat('oak_light'))
    for i, (ox, oy, r_) in enumerate(((-0.12, 0.0, 0.15), (0.14, 0.06, 0.1))):
        wheel = lathe(f'wsgear{i}', gx + ox, gy + oy, 0.61,
                      [(r_ * 0.24, 0.0), (r_, 0.02), (r_, 0.05),
                       (r_ * 0.24, 0.07)], sides=12, key='steel')
        for k in range(9):
            a = 2 * math.pi * k / 9
            _at(box(f'wstooth{i}{k}', 0, 0, 0, 0.045, 0.035, 0.05,
                    mat('steel_dark')),
                gx + ox + r_ * 1.06 * math.cos(a),
                gy + oy + r_ * 1.06 * math.sin(a), 0.645, 0, 0, a)
        _ = wheel
    cyl('wsaxle', gx - 0.12, gy, 0.61, 0.022, 0.2, sides=6, key='steel_dark')
    box('wscal', gx + 0.26, gy - 0.16, 0.61, 0.2, 0.06, 0.03, mat('gold'))

    # ── THE THINKER CIRCLE: what the id remembers ──
    cx_, cy_ = -hw + 0.85, -hh_ + 0.95
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.4
        crag(f'wsring{i}', cx_ + 0.62 * math.cos(a), cy_ + 0.62 * math.sin(a),
             0.15, 0.26, 0.24, 0.3 + 0.1 * _hash01(f'ws{i}'), key='rock',
             seed=40 + i)
    paving('wscpav', cx_, cy_, 0.15, 1.0, 1.0, key_a='ashlar',
           key_b='ashlar_dark', tile=0.16)
    lathe('wsdial', cx_, cy_, 0.16, [(0.2, 0.0), (0.18, 0.1)], sides=10,
          key='limestone')
    gn = box('wsgnomon', cx_, cy_, 0.26, 0.05, 0.16, 0.22, mat('steel'))
    gn.rotation_euler = (0.5, 0, 0)

    # ── Somebody works here ──
    for i in range(2):
        box(f'wsshelf{i}', hx - bw / 2 + 0.28, hy + 0.2, 0.6 + i * 0.34,
            0.34, 0.6, 0.06, mat('oak_light'))
        for k in range(3):
            cyl(f'wsscroll{i}{k}', hx - bw / 2 + 0.28, hy + 0.02 + k * 0.18,
                0.66 + i * 0.34, 0.04, 0.28, sides=7, axis='x', key='linen')
    tool_rack('wstools', hx + bw / 2 + 0.04, hy + 0.5, 0.15, w=0.6,
              facing='x')
    barrel('wsbar', hw - 0.45, hh_ - 0.6, 0.15, r=0.16, h=0.34)
    crate('wscr', -hw + 0.45, hh_ - 0.55, 0.15, s=0.32)
    basket('wsbask', gx - 0.5, gy - 0.42, 0.15, fill='oak_light')
    lantern('wslamp', hx, face - 0.16, 1.32, drop=0.14)
    critter('wscrit', -0.15, -hh_ + 0.45, 0.15, angle=1.9, kind=2, scale=0.8)
    perch_bird('wsbird', hx + 0.35, face - 0.24, roof_z + 1.0)
    window_box('wswb', hx + bw / 2 + 0.02, hy + 0.14, 0.7, 0.4, facing='x',
               bloom='bloom_blue')
    flower_bed('wsbed', hw - 0.5, hh_ - 1.5, 0.15, 0.46, 0.32,
               bloom='bloom_pink', n=5)
    tufts('wstuft', 0, 0, w - 0.4, h - 0.4)


# ── Roads ──────────────────────────────────────────────────
# A road cell is not a building: it has no silhouette of its own and its whole
# job is to JOIN. So it is not modelled once — it is modelled sixteen times, one
# for each combination of neighbours it might have, and the game picks. Straight
# runs, corners, tees and a crossroads all fall out of that; nothing has to be
# authored per junction and nothing can be laid the wrong way round.
#
# ── Which way is which ──
# The mask arrives in the GAME's directions (see road_tiles.dart), and the
# game's +y is not Blender's. Under this camera +x runs down-right and +y runs
# UP-right, while the Dart projection has +y running down-LEFT — so the game's
# +y is Blender's −y. Flipped once, here, rather than at sixteen call sites.
_ROAD_DIRS = ((1, 0), (0, -1), (-1, 0), (0, 1))   # game +x, +y, −x, −y

ROAD_HALF_WIDTH = 0.28    # carriageway, in tiles: 0.56 wide, kerbs outside it
ROAD_COBBLE = 0.046       # one stone — ~16 px at the shipping scale
ROAD_KERB_H = 0.038
ROAD_SURFACE_H = 0.03


def _road_covers(px, py, mask, hw=ROAD_HALF_WIDTH):
    """Is (px, py) — tile coordinates, −0.5 to 0.5 — on the road?

    The one shape worth spelling out is the CORNER. Two arms meeting at right
    angles give an L with a hard inside corner, and an L is not what a road
    does: a cart cannot turn one. So a cell with exactly two neighbours at right
    angles is drawn as the ARC that joins the two edge midpoints — centred on
    the tile corner between them, radius half a tile, which is precisely the
    curve that arrives square at both edges and therefore joins whatever comes
    next.

    Everything else is the union of arms from the centre plus a square pad, so a
    tee and a crossroads need no cases of their own, and a dead end gets a blunt
    stub instead of a point.
    """
    dirs = [d for i, d in enumerate(_ROAD_DIRS) if mask >> i & 1]
    if len(dirs) == 2 and dirs[0][0] * dirs[1][0] + dirs[0][1] * dirs[1][1] == 0:
        (ax, ay), (bx, by) = dirs
        ox, oy = px - (ax + bx) / 2, py - (ay + by) / 2
        # Inside the quarter the arc actually sweeps, not the whole ring.
        if ox * ax + oy * ay > 0 or ox * bx + oy * by > 0:
            return False
        return abs(math.hypot(ox, oy) - 0.5) <= hw
    if max(abs(px), abs(py)) <= hw:
        return True
    for dx, dy in dirs:
        along, across = px * dx + py * dy, px * -dy + py * dx
        if 0 <= along <= 0.5 and abs(across) <= hw:
            return True
    return False


def road_tile(mask):
    """One road cell, shaped by which of its four neighbours are roads.

    Laid as a grid of stones over a dark bed, keeping only the stones that fall
    on the road. That is what makes the arc above cost nothing: the shape is a
    predicate, and the cobbles, the bed and the kerb all read it. A curve needs
    no curved geometry, only stones that know they are on one.
    """
    n = int(round(1.0 / ROAD_COBBLE))
    step = 1.0 / n

    def centre(ix, iy):
        return -0.5 + step * (ix + 0.5), -0.5 + step * (iy + 0.5)

    for iy in range(n):
        for ix in range(n):
            px, py = centre(ix, iy)
            if not _road_covers(px, py, mask):
                continue
            # The BED first. Without it the joints between the stones show the
            # map's grass, and a road becomes a scatter of rocks on a lawn.
            box(f'bed{ix}_{iy}', px, py, 0.0, step, step, 0.014,
                mat('ashlar_dark'))
            j = _hash01(f'cob{mask}:{ix}:{iy}')
            k = _hash01(f'jit{mask}:{ix}:{iy}')
            ob = box(f'cob{ix}_{iy}',
                     px + (j - 0.5) * step * 0.16,
                     py + (k - 0.5) * step * 0.16,
                     0.010, step * 0.86, step * 0.86,
                     ROAD_SURFACE_H * (0.8 + j * 0.4),
                     mat('cobble' if j < 0.66 else 'ashlar'))
            # Hand-laid, not machine-laid: a few degrees each, from the same
            # stable hash, so the render is repeatable.
            ob.rotation_euler = (0, 0, (k - 0.5) * 0.32)

    # ── The kerb finds itself ──
    # A stone is a kerb when it is NOT on the road but touches something that
    # is. Written that way it follows any shape the predicate makes — including
    # the arc — and it opens itself at a junction, because the ground beside one
    # arm is the middle of another. Eight-way, so convex corners close up.
    around = ((1, 0), (-1, 0), (0, 1), (0, -1),
              (1, 1), (1, -1), (-1, 1), (-1, -1))
    for iy in range(n):
        for ix in range(n):
            px, py = centre(ix, iy)
            if _road_covers(px, py, mask):
                continue
            if not any(_road_covers(px + dx * step, py + dy * step, mask)
                       for dx, dy in around):
                continue
            # limestone_shade, not limestone: the kerb is a LINE, not the
            # subject. In the palette's brightest stone it out-shouted the road
            # it edges, and a map full of roads became a map full of bright
            # outlines with something grey inside them.
            box(f'kerb{ix}_{iy}', px, py, 0.0, step * 0.88, step * 0.88,
                ROAD_KERB_H, mat('limestone_shade'))


def _road_preset(mask):
    return lambda w, h: road_tile(mask)


PRESETS = {
    'breeding_hut': (breeding_hut, 4, 4),
    # 5 x 5, because that is what the DEF says. It was 6 x 6 here and
    # nowhere else, so the art was framed for a base a cell wider than the
    # tile it has to stand on — harmless while the picture was only ever
    # looked at, and wrong the moment it is bundled and placed.
    'castle': (castle, 5, 5),
    # ── The era-I roster, on the footprints the game already gives them ──
    # The name on the left is the building_defs id, so `--preset hut` renders
    # what `hut` will show on the map and the upload has nowhere to go wrong.
    'small_house': (small_house, 3, 3),
    'large_house': (large_house, 2, 5),
    'small_wood_camp': (wood_camp, 4, 3),
    'small_stone_camp': (stone_camp, 4, 3),
    'large_wood_camp': (wood_works, 4, 4),
    # The LARGE quarry: the same hole, bigger, with a second face.
    'large_stone_camp': (stone_camp, 4, 4),
    'storehouse': (storehouse, 4, 3),
    'gold_vault': (gold_vault, 3, 3),
    'builder_camp': (builder_camp, 6, 6),
    'healing_hut': (healing_hut, 3, 3),
    'scout_post': (scout_post, 2, 2),
    'trading_post': (trade_center, 4, 3),
    'caravanserai': (caravanserai, 4, 3),
    'hatchery': (hatchery, 4, 3),
    'lux_fish': (fish_hut, 3, 3),
    'lux_fur': (fur_lodge, 3, 3),
    'church': (church, 3, 5),
    'marketplace': (marketplace, 4, 4),
    'refinery_e2': (clay_refinery, 4, 4),
    'training_grounds': (training_grounds, 3, 3),
    'thinker_circle': (workshop, 3, 3),
    # The crossroads stands for the set in the line-up and in --preset. All
    # sixteen are rendered by tool/blender/roads.py, which is the only thing
    # that needs them one at a time.
    'road': (_road_preset(15), 1, 1),
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
    # The palette caches point at the materials just deleted. Leaving them
    # holding freed datablocks is not a slow leak — the very next mat() hands
    # back a dead pointer and Blender raises "StructRNA of type Material has
    # been removed", which is why building a SECOND preset in one session died
    # while building one always worked.
    _MATS.clear()
    _VARIANTS.clear()


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
    # ── Softer since the material pass (user 2026-08-12) ──
    # A 2.2-degree sun draws a shadow edge one pixel wide, which is right for
    # a flat-shaded sprite and wrong for a surface that now has relief on it:
    # the grain reads as grain only if the light falling across it has some
    # width to it. Still nowhere near a gradient.
    sun.data.angle = math.radians(6.5)
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
    # Deeper and further-reaching than before: with grain and relief on the
    # surfaces there is finally something for occlusion to catch, and the
    # crevices between rocks are where the reference does most of its work.
    ev.fast_gi_distance = 0.9
    ev.fast_gi_ray_count = 8
    ev.fast_gi_step_count = 24
    # Doubled, because a bump map and a soft sun both alias.
    ev.taa_render_samples = 192
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
    bg.inputs['Color'].default_value = (0.56, 0.54, 0.60, 1)
    bg.inputs['Strength'].default_value = 0.30


def frame(w, h, px_per_tile, headroom, azimuth=0.0, fit=True):
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

    # ── The picture GROWS to hold the building (user 2026-08-09) ──
    # headroom was a fixed multiple of the base's width, and the Scout Post's
    # spire simply was not in the render: at 1.25 the frame stopped below it
    # and nothing said so. A taller image costs the app nothing — artPlacement
    # anchors art by its FOOT and scales it by its WIDTH, so the height is free
    # — where a cropped spire costs the spire.
    #
    # Only ever taller: [headroom] stays the minimum, so nothing that fitted
    # before changes, and the terrain (which must be exactly the grid's
    # bounding box) opts out with fit=False.
    # The frame, in the camera's own axes. It starts as exactly the base and
    # is then opened out until the whole model is inside it.
    fx0, fx1 = min(xs), max(xs)
    fy0, fy1 = min(ys), min(ys) + span_x * headroom

    if fit:
        bpy.context.view_layer.update()
        mx0 = mx1 = my0 = my1 = None
        for ob in bpy.data.objects:
            if ob.type != 'MESH':
                continue
            for corner in ob.bound_box:
                v = ob.matrix_world @ Vector(corner)
                a, b = v.dot(right), v.dot(up)
                mx0 = a if mx0 is None else min(mx0, a)
                mx1 = a if mx1 is None else max(mx1, a)
                my0 = b if my0 is None else min(my0, b)
                my1 = b if my1 is None else max(my1, b)
        if mx0 is not None:
            # ── Sideways too, not only up (user 2026-08-12) ──
            # This used to grow the height and nothing else, because the only
            # failure anyone had hit was a cropped spire. A castle wing leaning
            # a cell and a half past its own footprint is the same failure
            # lying down, and it read on the map as the building being sliced
            # off against a straight vertical edge.
            pad = span_x * 0.015
            fx0 = min(fx0, mx0 - pad)
            fx1 = max(fx1, mx1 + pad)
            fy0 = min(fy0, my0 - pad)
            fy1 = max(fy1, my1 + (my1 - fy0) * 0.04 + pad)

    span_y = fy1 - fy0
    width = fx1 - fx0
    ppu = base_px / span_x                       # pixels per unit, never moves
    scene.render.resolution_x = max(2, int(round(width * ppu)))
    scene.render.resolution_y = max(2, int(round(span_y * ppu)))
    cam.data.ortho_scale = max(width, span_y)

    # ── Where the FOOTPRINT ended up in the picture ──
    # Not the same thing as the picture any more, which is the whole point of
    # opening the frame out. artPlacement() puts the art back by these.
    frame.art_box = (
        round(span_x / width, 5),                             # artBaseWidth
        round(((max(xs) + min(xs)) / 2 - fx0) / width, 5),    # artAnchorX
        round((min(ys) - fy0) / width, 5),                    # artLift
    )

    aim_x = (fx1 + fx0) / 2
    aim_y = (fy1 + fy0) / 2
    # ── The clip planes still cut, even in ortho (2026-08-09) ──
    # Distance does not change an orthographic picture, so the camera sat at a
    # fixed 60 with a 200-deep clip range and that was fine for everything the
    # size of a building. The TERRAIN is 226 units across, and its far corner
    # lands 285 units in front of the camera — past clip_end, so it was not
    # drawn at all. It read as a grey band across the bottom of the map, which
    # looks like missing ground rather than like a clipped camera.
    #
    # Scaled to what is being framed, so this cannot come back for the next
    # thing that is bigger than a house.
    reach = max(width, span_y) * 3 + 60
    cam.location = right * aim_x + up * aim_y + back * reach
    cam.data.clip_start = 0.1
    cam.data.clip_end = reach * 2 + 200


_VARIANTS = {}


def scale_all(k):
    """Scale everything built so far, uniformly, about the world origin.

    For a model whose layout is authored at one size and used at another. The
    factor goes into the VERTICES and the object's location, not into
    ob.scale — a leftover scale would be a second thing bevel_everything and
    the exporter each have to remember to apply, and neither of them does.

    Uniform only: a non-uniform scale does not commute with the rotations the
    kit puts on braces, sails and cart wheels, and those would shear.
    """
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        ob.location = ob.location * k
        for v in ob.data.vertices:
            v.co = v.co * k


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


def bevel_everything(viewport=True):
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
        # ── Not everything wants a chamfer (user 2026-08-12) ──
        # One width was right while everything was a box. A displaced rock is
        # already all edges and a bevel eats the crags; a cylinder has no hard
        # edge to cut. Both ask for 0 through ob['bevel'], and asking for zero
        # means skipping the modifier entirely rather than adding a dead one.
        want = ob.get('bevel', BEVEL_WIDTH)
        if want <= 0:
            continue
        m = ob.modifiers.new('facets', 'BEVEL')
        m.width = want
        m.segments = BEVEL_SEGMENTS
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(30)
        m.use_clamp_overlap = True
        m.harden_normals = False
        # ── OFF in the viewport when asked (user 2026-08-06: "blender bleibt
        #    immer hängen") ──
        # A castle is several thousand boxes and every one of them carries this
        # modifier. Blender re-evaluates the lot on every navigation frame, so
        # the window locks up while you try to turn it — for an effect that is
        # a few pixels wide and only matters in the final image.
        #
        # show_render stays on, so what is RENDERED is unchanged. This only
        # buys back the interactivity of a scene you are looking at rather
        # than shooting.
        m.show_viewport = viewport


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
                    # MATERIAL, not RENDERED. Rendered shading re-runs EEVEE
                    # every time the view moves; material preview draws the
                    # same flat colours without the lighting solve, which is
                    # the whole difference between a scene you can turn and one
                    # that locks up while you try.
                    space.shading.type = 'MATERIAL'
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
    ap.add_argument('--glb', help='also export the model to this .glb — the '
                                  'geometry itself, for a 3D renderer')
    args = ap.parse_args(argv)

    build, w, h = PRESETS[args.preset]
    clear()
    build(w, h)
    if args.guides:
        guide_plane(w, h)
    vary_tones()
    if not args.no_bevel:
        # Same deal as all_buildings.py: --no-render means you are about to LOOK
        # at this, and a live bevel on a few thousand boxes is re-evaluated on
        # every navigation frame. The modifier stays on for the render either
        # way, so nothing that ships changes.
        bevel_everything(viewport=not args.no_render)
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

    if args.glb:
        # ── The model itself, not a picture of it ──
        # export_apply bakes the modifiers, which for this kit means the bevel:
        # without it every edge comes out sharp and the export looks like a
        # different building from the render.
        #
        # No camera and no lights. They are decisions about how to PHOTOGRAPH
        # this thing, and a model that carries its own lighting fights whatever
        # engine loads it.
        bpy.ops.export_scene.gltf(
            filepath=os.path.abspath(args.glb),
            export_format='GLB',
            export_apply=True,
            export_cameras=False,
            export_lights=False,
        )
        print(f'exported {args.glb}')
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


# Guarded so another script can IMPORT this one for its parts — the palette,
# box(), the presets — without also rendering a building. Blender runs a
# --python file as __main__, so nothing changes for the normal path.
if __name__ == '__main__':
    main()
