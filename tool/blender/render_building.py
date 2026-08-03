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
    """A hut at the back, an open nesting yard at the front, eggs in it.

    The read has to survive being 224 px wide on a phone, so the identity is
    carried by SILHOUETTE and one accent colour, not by detail: a deep roof over
    a dark opening, and three pale eggs sitting in bright straw where nothing
    else competes for attention.
    """
    timber = flat('timber', (0.36, 0.20, 0.10))
    beam = flat('beam', (0.52, 0.32, 0.16))
    thatch = flat('thatch', (0.72, 0.50, 0.18))
    straw = flat('straw', (0.88, 0.72, 0.30))
    shell = flat('shell', (0.96, 0.93, 0.85))
    dark = flat('dark', (0.13, 0.09, 0.07))   # the opening, read as depth
    rose = flat('rose', (0.86, 0.20, 0.44))   # the one accent

    wall_h = 1.05
    body_d = h * 0.55
    body_w = w - 0.4
    body_y = h / 2 - body_d / 2 - 0.2          # pushed to the back

    box('body', 0, body_y, 0, body_w, body_d, wall_h, timber)
    box('mouth', 0, body_y - body_d / 2 + 0.06, 0.05,
        body_w * 0.55, 0.1, wall_h * 0.72, dark)
    gable('roof', 0, body_y, wall_h, body_w, body_d, 0.95, thatch)

    for sx in (-1, 1):
        for sy in (-1, 1):
            box('post', sx * (body_w / 2 - 0.09), body_y + sy * (body_d / 2 - 0.09),
                0, 0.2, 0.2, wall_h, beam)

    # The nesting yard: a straw bed, sunk between four low kerbs so it reads as
    # a pen and not as a rug someone dropped.
    yard_d = h - body_d - 0.4
    yard_y = body_y - body_d / 2 - yard_d / 2
    yard_w = w - 0.4
    box('bed', 0, yard_y, 0, yard_w - 0.3, yard_d - 0.3, 0.14, straw)
    for sx in (-1, 1):
        box('kerb', sx * (yard_w / 2 - 0.08), yard_y, 0, 0.16, yard_d, 0.3, beam)
    box('kerb_front', 0, yard_y - yard_d / 2 + 0.08, 0, yard_w, 0.16, 0.3, beam)
    # The gate is a LOW rail, and that is the whole point: the eggs are what the
    # building says about itself, so nothing may stand in front of them. A
    # full-height gate in the accent colour reads first and hides the message.
    gate_y = yard_y - yard_d / 2 + 0.08
    for sx in (-1, 1):
        box('gatepost', sx * (yard_w / 2 - 0.08), gate_y, 0, 0.2, 0.2, 0.42,
            rose)
    box('rail', 0, gate_y, 0.28, yard_w, 0.14, 0.1, rose)

    egg('egg_a', -0.42, yard_y + 0.20, 0.14, 0.23, shell)
    egg('egg_b', 0.34, yard_y + 0.32, 0.14, 0.26, shell)
    egg('egg_c', 0.06, yard_y - 0.26, 0.14, 0.21, shell)


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
    sun.data.energy = 2.6
    sun.data.angle = 0  # hard-edged shadows; a soft one is a gradient
    # From the upper front-left, so the two visible walls get clearly different
    # amounts of it and the roof gets the most. That difference IS the shading.
    sun.rotation_euler = (math.radians(48), 0, math.radians(-35))

    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.62, 0.70, 0.82, 1)  # cool sky fill…
    bg.inputs['Strength'].default_value = 0.45                # …against a warm sun


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


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--preset', required=True, choices=sorted(PRESETS))
    ap.add_argument('--out', required=True)
    ap.add_argument('--scale', type=int, default=SCALE)
    ap.add_argument('--headroom', type=float, default=1.25,
                    help='image height as a multiple of the base width')
    ap.add_argument('--guides', action='store_true',
                    help='mark the footprint, to check the framing')
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
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    # Blender resolves a relative path against the .blend file, and in
    # --background there is none — it lands on the drive root. Always absolute.
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


main()
