"""A battle-screen scene rig — the same camera the monsters stand under, with
a built-in guide for exactly how much of it the game actually shows.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background `
        --python tool/blender/render_battle_scene.py -- `
        --out docs/renders/battle_scene_guide.png `
        --blend tool/blender/battle_scene.blend

── user 2026-08-29: "mache mir ein Blenderfile ... Kamera so positioniert,
   dass es den gleichen Winkel hat wie die Monster, und der Abschnitt klar
   gezeigt wird, welcher dann im Spiel sichtbar ist" ──
Two asks in one file:

  1. MATCH THE MONSTERS' CAMERA. render_monster.py photographs Glimmergnaw
     with render_building.py's own rig — orthographic, tipped
     (90 - ELEVATION) off the ground and spun 45 degrees round it (see that
     file's header for the trig). Whatever gets built here uses the exact
     same two numbers, so a monster dropped into this scene sits under the
     same lens that shot it rather than a second, slightly-off "arena camera"
     nobody could tell apart from the first by eye but that would never quite
     agree with it in a screenshot.

  2. SHOW WHAT SURVIVES THE CROP. battle_screen.dart's BattleScene has no
     fixed aspect ratio — it is an Expanded strip filling whatever room is
     left between the header and the command deck: squarish-to-tall on a
     phone, wide on a desktop or browser window. Whatever art eventually
     fills it (AreaDef.imageUrl) gets BoxFit.cover'd in, which crops
     DIFFERENTLY at every aspect ratio the arena can end up. A background
     built here blind has no way to know what stays on screen and what gets
     cut, so this file draws the crop itself, as two camera-facing rectangles
     sitting at the scene's own depth:

       SAFE  — the narrow end (phone). Anything inside this survives on
               every device the game runs on.
       WIDE  — the loose end (desktop/web). The most that is EVER shown; a
               phone crops down to SAFE from inside this.

     Because the camera is ORTHOGRAPHIC, a rectangle facing it dead-on has no
     foreshortening — its edges land exactly where the final render's own
     crop line would, full stop, not an approximation.

     Both aspect ratios are ESTIMATES (--safe-aspect / --wide-aspect) until
     someone measures the real arena on a real device — they are flags for
     exactly that reason, not numbers baked into the geometry.

Reused from render_building.py rather than reinvented: the ELEVATION/45°
camera trig every render in this kit already agrees on, flat()/light()/
clear()/vary_tones()/bevel_everything(), and the centred-cube mesh builder —
see its own header for why bpy.ops is avoided for geometry built in bulk (it
is not, here: a handful of one-off planes and bars, same as guide_plane()).
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_building as rb  # noqa: E402

# How far the guides' bottom edge must clear the ground plane, in world
# units — see place_camera()'s caller in main() for why this can't be a
# fixed depth instead.
_kGroundMargin = 0.4


def centered_box(name, x, y, z, sx, sy, sz, mat):
    """Like rb.box(), but centred on (x, y, z) rather than centre-BOTTOM.

    box() anchors buildings to the ground they stand on; a guide bar has no
    ground — it floats at a chosen depth in front of the camera and must stay
    centred there regardless of its own thickness, so the half-height offset
    box() adds would only misplace it.
    """
    verts = [(cx * sx, cy * sy, cz * sz) for cx, cy, cz in rb._CUBE_CORNERS]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], list(rb._CUBE_FACES))
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat)
    for p in mesh.polygons:
        p.use_smooth = False
    return ob


def build_arena_ground():
    """A stand-in for battle_scene.dart's _ArenaGround — a lawn with a worn
    dirt pitch trodden into the middle — so the guide rectangles below have
    real ground to be checked against instead of floating over a void.

    Placeholder geometry, not final art: swap it for real scenery once
    someone dresses this file, the guides and camera stay exactly as they
    are.
    """
    grass = rb.flat('bs_grass', (0.22, 0.35, 0.19))
    dirt = rb.flat('bs_dirt', (0.45, 0.35, 0.24))

    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
    ground = bpy.context.object
    ground.name = 'arena_ground'
    ground.scale = (16, 16, 1)
    bpy.ops.object.transform_apply(scale=True)
    ground.data.materials.append(grass)
    for p in ground.data.polygons:
        p.use_smooth = False

    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0.01))
    pitch = bpy.context.object
    pitch.name = 'arena_pitch'
    pitch.scale = (8.5, 4.6, 1)
    bpy.ops.object.transform_apply(scale=True)
    pitch.data.materials.append(dirt)
    for p in pitch.data.polygons:
        p.use_smooth = False


def place_camera(frame_half_h, frame_aspect, azimuth=0.0):
    """THE monster/building rig, not a lookalike — same rotation, same
    orthographic projection, same clip-range reasoning as
    render_building.py's frame(). The only difference is what decides the
    framing: frame() solves it from a building's own bound box; this scene
    is handed [frame_half_h]/[frame_aspect] directly, because the thing being
    framed is the WIDE guide (see main()), not a model to fit around.

    Returns the camera plus its own right/up/back axes (from the SAME
    rotation, so nothing computed here can drift from what the camera
    actually looks at) for the guides to build against.
    """
    scene = bpy.context.scene
    bpy.ops.object.camera_add()
    cam = bpy.context.object
    cam.name = 'battle_camera'
    cam.data.type = 'ORTHO'
    cam.rotation_euler = (
        math.radians(90 - rb.ELEVATION), 0, math.radians(45 + azimuth),
    )
    scene.camera = cam

    q = Euler(cam.rotation_euler).to_quaternion()
    right = q @ Vector((1, 0, 0))
    up = q @ Vector((0, 1, 0))
    back = q @ Vector((0, 0, 1))

    reach = frame_half_h * 6 + 40
    cam.location = back * reach
    cam.data.clip_start = 0.1
    cam.data.clip_end = reach * 2 + 100
    # VERTICAL, not the AUTO default — AUTO measures ortho_scale against
    # whichever render dimension comes out LARGER (see render_building.py's
    # frame(), which relies on that same rule for its own, taller-than-wide
    # buildings). This scene is the opposite shape, wide rather than tall, so
    # AUTO would silently switch to measuring the WIDTH and zoom in by the
    # aspect ratio. Pinning to VERTICAL makes ortho_scale always mean the
    # height, matching how [frame_half_h] was actually derived below.
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.ortho_scale = frame_half_h * 2
    scene.render.film_transparent = True

    scene.render.resolution_y = 1600
    scene.render.resolution_x = max(2, int(round(1600 * frame_aspect)))
    return cam, right, up, back


def screen_guide(tag, rot, right, up, back, depth, half_w, half_h, color,
                  thickness=0.05):
    """A camera-FACING rectangle outline, in SCREEN space (the camera's own
    right/up), sitting [depth] units along its view axis — not a footprint
    laid on the ground. An orthographic camera has no foreshortening, so this
    rectangle's edges ARE the render's crop line at that aspect, not a
    stand-in for it.

    Four thin boxes rather than a stroked curve, the same way every other
    guide in this kit is a mesh: one material system, one thing to remember
    to hide_render on ship (see main()'s --hide-guides).
    """
    coll = bpy.data.collections.new(f'Guide_{tag}')
    bpy.context.scene.collection.children.link(coll)
    m = rb.flat(f'guide_{tag}', color)
    node = m.node_tree.nodes['Principled BSDF']
    node.inputs['Emission Strength'].default_value = 2.0
    node.inputs['Emission Color'].default_value = (*color, 1)

    origin = back * depth

    def bar(name, ru, rv, su, sv):
        # (ru, rv): the bar's centre in (right, up) units. (su, sv): its own
        # half-size along those SAME two axes — sz (thickness) runs along
        # `back`, giving the flat-shaded bar a face the camera can see.
        pos = origin + right * ru + up * rv
        ob = centered_box(name, pos.x, pos.y, pos.z, su * 2, sv * 2,
                           thickness, m)
        ob.rotation_euler = rot
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        coll.objects.link(ob)
        return ob

    t = thickness
    bar(f'{tag}_top', 0, half_h, half_w + t, t)
    bar(f'{tag}_bottom', 0, -half_h, half_w + t, t)
    bar(f'{tag}_left', -half_w, 0, t, half_h + t)
    bar(f'{tag}_right', half_w, 0, t, half_h + t)
    return coll


def screen_label(name, text, rot, right, up, back, depth, ru, rv, color,
                  size=0.26):
    """A small camera-facing caption next to a guide, so opening the file
    cold still says which rectangle is which without cross-checking this
    script."""
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = text
    curve.size = size
    curve.align_x = 'LEFT'
    ob = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(ob)
    pos = back * depth + right * ru + up * rv
    ob.location = pos
    ob.rotation_euler = rot
    m = rb.flat(f'{name}_mat', color)
    node = m.node_tree.nodes['Principled BSDF']
    node.inputs['Emission Strength'].default_value = 2.0
    node.inputs['Emission Color'].default_value = (*color, 1)
    curve.materials.append(m)
    return ob


def main():
    import argparse
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', help='PNG to write (not needed with --no-render)')
    ap.add_argument('--blend', help='.blend file to save')
    ap.add_argument(
        '--safe-aspect', type=float, default=1.1,
        help='narrow end (phone arena strip), width / height — an ESTIMATE, '
             'tune to what you actually measure on a device')
    ap.add_argument(
        '--wide-aspect', type=float, default=2.2,
        help='wide end (desktop/web arena strip), width / height — an '
             'ESTIMATE, same caveat')
    ap.add_argument(
        '--guide-height', type=float, default=5.0,
        help='world-unit height shared by both guides — only the WIDTH '
             'differs between them, matching an arena whose height is the '
             'more fixed dimension and whose width is what a resize changes')
    ap.add_argument(
        '--margin', type=float, default=1.35,
        help='how much breathing room the render frame leaves around the '
             'WIDE guide')
    ap.add_argument('--azimuth', type=float, default=0.0)
    ap.add_argument(
        '--hide-guides', action='store_true',
        help='exclude the SAFE/WIDE rectangles and their labels from the '
             'render (they stay in the file, just hide_render=True) — for a '
             'clean export once real scenery replaces the placeholder ground')
    ap.add_argument('--no-render', action='store_true')
    args = ap.parse_args(argv)

    rb.clear()
    build_arena_ground()
    # vary_tones() BEFORE the guides exist: it hand-tints every mesh's own
    # material by a per-object random step, which is exactly right for grass
    # and dirt and exactly wrong for a guide whose whole job is an unambiguous
    # colour. Running it now means the guides (added below) are simply never
    # in its loop, rather than needing to opt out.
    rb.vary_tones()

    half_h = args.guide_height / 2
    wide_half_w = half_h * args.wide_aspect
    safe_half_w = half_h * args.safe_aspect

    frame_half_h = half_h * args.margin
    frame_aspect = (wide_half_w * args.margin) / frame_half_h

    cam, right, up, back = place_camera(frame_half_h, frame_aspect,
                                         args.azimuth)
    rot = cam.rotation_euler
    # SOLVED, not a fixed number — a camera-facing plane tilts partway into
    # the ground the moment the camera is elevated at all, because its own
    # "up" axis has a downward WORLD-Z component (cos(ELEVATION) of it, per
    # unit of screen-up). A fixed depth of 3.0 put the guides' centre only
    # 1.5 world-Z up while the bottom edge dropped 2.165 BELOW that — so the
    # bottom bar sat at world Z ≈ -0.665, under the opaque ground, and the
    # render simply had no bottom edge at all (caught by inspecting the
    # saved .blend directly: the object was there, just underground).
    #
    # depth * sin(ELEVATION) is how far the guide centre rises per unit of
    # depth; half_h * cos(ELEVATION) is how far its own bottom edge then
    # drops from that centre. Solving depth so the bottom edge clears the
    # ground by [[_kGroundMargin]] fixes this for ANY --guide-height, not
    # just today's default.
    elevation_rad = math.radians(rb.ELEVATION)
    depth = (half_h * math.cos(elevation_rad) + _kGroundMargin) / math.sin(
        elevation_rad,
    )

    wide_orange = (1.0, 0.55, 0.15)
    safe_green = (0.25, 0.95, 0.55)
    wide_coll = screen_guide('wide', rot, right, up, back, depth,
                              wide_half_w, half_h, wide_orange)
    safe_coll = screen_guide('safe', rot, right, up, back, depth,
                              safe_half_w, half_h, safe_green)
    wide_label = screen_label(
        'label_wide', 'WIDE - desktop/web crop', rot, right, up, back, depth,
        -wide_half_w, half_h + 0.22, wide_orange,
    )
    safe_label = screen_label(
        'label_safe', 'SAFE - always visible', rot, right, up, back, depth,
        -safe_half_w, half_h + 0.55, safe_green,
    )
    if args.hide_guides:
        for coll in (wide_coll, safe_coll):
            for ob in coll.objects:
                ob.hide_render = True
        for ob in (wide_label, safe_label):
            ob.hide_render = True

    rb.light(args.azimuth)
    rb.bevel_everything(viewport=True)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for name in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if name in engines:
            scene.render.engine = name
            break

    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
    if args.no_render:
        rb.show_in_viewport()
        return
    if not args.out:
        ap.error('--out is required unless --no-render is given')
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


if __name__ == '__main__':
    main()
