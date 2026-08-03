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
PALETTE = {
    'tile': (0.72, 0.28, 0.16),        # terracotta pantile — the loudest note
    'tile_dark': (0.55, 0.20, 0.12),   # its shadow side and the ridge
    'stucco': (0.90, 0.85, 0.74),      # lime render, the wall default
    'travertine': (0.82, 0.75, 0.62),  # cut stone, a shade warmer and darker
    'ashlar': (0.58, 0.55, 0.50),      # the plinth and any heavy masonry
    'oak': (0.35, 0.22, 0.13),         # beams, doors, shutters
    'oak_light': (0.50, 0.34, 0.20),   # posts catching the sun
    'iron': (0.24, 0.24, 0.27),        # fittings, hinges, grilles
    'gold': (0.85, 0.66, 0.22),        # finials — a few square pixels, no more
    'dark': (0.11, 0.08, 0.07),        # an opening, read as depth
    'banner': (0.62, 0.13, 0.20),      # the one saturated cloth per building
    'sand': (0.84, 0.74, 0.56),        # trodden ground inside a court
}


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
             overhang=0.3, pitch=0.16):
    """Tile courses running down a hip roof's two long slopes.

    The roof is the largest surface on any of these buildings, and flat it is a
    plate of colour. Ribbed, it is a roof.

    Each rib is SHORTENED by how far out it sits, because a hip roof's slope is
    a trapezoid: a rib of full length out near the corner would hang off the
    side. Solving for that per rib is also what makes the tiling converge
    towards the ridge the way a real hip roof does.
    """
    sx += overhang * 2
    sy += overhang * 2
    r = sx * ridge / 2
    run = sy / 2
    length = math.hypot(run, h)
    alpha = math.atan2(h, run)                 # the pitch, off horizontal

    n = max(3, int(sx / pitch) // 2)
    for i in range(n + 1):
        rx = -sx / 2 + sx * i / n
        # How far up this rib may go before the trapezoid narrows past it.
        span = sx / 2 - r
        frac = 1.0 if span <= 0 else ((sx / 2 - abs(rx)) / span)
        frac = max(0.0, min(1.0, frac))
        if frac < 0.05:
            continue
        ell = length * frac
        for sign in (-1, 1):
            ob = box(f'{name}_{i}_{sign}', 0, 0, 0,
                     pitch * 0.42, ell, 0.05, mat(key))
            ob.rotation_euler = (sign * alpha, 0, 0)
            ob.location = (
                x + rx,
                y + sign * (-sy / 2 + (ell / 2) * math.cos(alpha)),
                z + (ell / 2) * math.sin(alpha) + 0.03,
            )


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

    roof_z = 0.22 + wall_h
    hip_roof('roof', 0, body_y, roof_z, body_w, body_d, 0.85)
    pantiles('tiles', 0, body_y, roof_z, body_w, body_d, 0.85)
    antefixes('antefix', 0, body_y, roof_z - 0.02, body_w + 0.6, body_d + 0.6)

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

    # ── The court ──
    court_d = h - body_d - 0.35
    court_y = body_y - body_d / 2 - court_d / 2
    court_w = w - 0.35
    box('sand', 0, court_y, 0, court_w - 0.3, court_d - 0.3, 0.16,
        mat('sand'))
    # Low walls, not a fence: masonry on three sides, open to the front so the
    # eggs are visible. Capped in travertine so the top edge catches light.
    for sx in (-1, 1):
        box('court_wall', sx * (court_w / 2 - 0.09), court_y, 0,
            0.18, court_d, 0.46, mat('ashlar'))
        box('court_cap', sx * (court_w / 2 - 0.09), court_y, 0.46,
            0.24, court_d, 0.07, mat('travertine'))
    front_y = court_y - court_d / 2 + 0.09
    for sx in (-1, 1):
        box('gatepost', sx * (court_w / 2 - 0.09), front_y, 0,
            0.26, 0.26, 0.72, mat('travertine'))
        box('finial', sx * (court_w / 2 - 0.09), front_y, 0.72,
            0.12, 0.12, 0.1, mat('gold'))
    # The threshold between the posts stays LOW: the eggs are what the building
    # says about itself, and nothing may stand in front of them.
    box('threshold', 0, front_y, 0, court_w - 0.5, 0.18, 0.2, mat('ashlar'))

    egg('egg_a', -0.42, court_y + 0.20, 0.16, 0.23, mat('stucco'))
    egg('egg_b', 0.34, court_y + 0.32, 0.16, 0.26, mat('stucco'))
    egg('egg_c', 0.06, court_y - 0.26, 0.16, 0.21, mat('stucco'))


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
    sun.data.energy = 2.1
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
    # Cool fill against a warm sun, but weak: the fill lands hardest on exactly
    # the faces the sun misses, so a strong one greys out the shadow side.
    bg.inputs['Color'].default_value = (0.66, 0.72, 0.82, 1)
    bg.inputs['Strength'].default_value = 0.32


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
