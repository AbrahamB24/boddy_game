"""Large Quarry — the LEGO-style pass.

    blender --background --python tool/blender/quarry_lego.py -- \
        --out docs/renders/large_quarry_lego.png

── A third style, not a filter on the second one ──
The photoreal pass (quarry_photoreal.py) sculpts a continuous noise-displaced
rock surface and shades it PBR. LEGO is the opposite of continuous: everything
is a VOXEL — one flat-topped block per grid cell, studs on every top surface,
glossy saturated plastic. So this is not "run the same mesh through a
different material" (that reads as a re-skin, not as brick-built); the terrain
is rebuilt as a height-quantised column grid from scratch.

What DOES carry over from the photoreal pass is the LAYOUT logic: a rock wall
pinned to the back-left corner, a lower shoulder at back-right for the crane,
and a broad terraced floor between them — same composition, so the two
renders are recognisably the same building despite matching nothing else.
"""
import argparse
import math
import os
import sys

import bpy
import mathutils

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(os.path.dirname(_HERE))

# ── The same corner layout as quarry_photoreal.py, none of its noise ──
RIDGE = (-2.75, 2.7, 1.9, 3.1)
SHOULDER = (2.85, 2.55, 1.55, 1.85)
ISLAND_R = 3.35
FLOOR_Z = 0.35


def _falloff(dx, dy, r):
    d = math.hypot(dx, dy) / r
    return max(0.0, 1.0 - d) ** 1.8


def height(x, y):
    h = FLOOR_Z
    h += _falloff(x - RIDGE[0], y - RIDGE[1], RIDGE[2]) * RIDGE[3]
    h += _falloff(x - SHOULDER[0], y - SHOULDER[1], SHOULDER[2]) * SHOULDER[3]
    bench = -y * 0.11
    step = 0.34
    h += math.floor(bench / step) * step - bench
    return h


def zone_at(x, y):
    """Which brick colour a column gets: WALL near the ridge, SHOULDER near
    the crane's outcrop, FLOOR everywhere else."""
    on_ridge = _falloff(x - RIDGE[0], y - RIDGE[1], RIDGE[2])
    on_shoulder = _falloff(x - SHOULDER[0], y - SHOULDER[1], SHOULDER[2])
    if on_ridge > 0.15 and on_ridge >= on_shoulder:
        return 'wall'
    if on_shoulder > 0.15:
        return 'shoulder'
    return 'floor'


def ground(x, y):
    """Where a prop's FOOT actually lands: the terrain is a voxel grid, not
    a smooth surface, so anything placed with the smooth height() sinks
    part-way into whichever column it lands on — the stone stacks did
    exactly that, rendering as dark slivers instead of blocks. Every prop
    must stand on the same quantised top build_terrain() actually built."""
    return max(0.14, round(height(x, y) / 0.32) * 0.32)


# ── Mesh kit: boxes, cylinders, struts — same shapes as the photoreal file,
# but every box gets a stud and a gap to its neighbours instead of a bevel.
def box(name, x, y, z, sx, sy, sz, mat):
    verts = [(-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2, 0),
             (sx / 2, sy / 2, 0), (-sx / 2, sy / 2, 0),
             (-sx / 2, -sy / 2, sz), (sx / 2, -sy / 2, sz),
             (sx / 2, sy / 2, sz), (-sx / 2, sy / 2, sz)]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2),
             (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = False
    m = ob.modifiers.new('bevel', 'BEVEL')
    m.width = 0.012
    m.segments = 2
    m.limit_method = 'ANGLE'
    return ob


def cyl(name, x, y, z, r, h, mat, sides=16, axis='z'):
    bot = [(r * math.cos(2 * math.pi * i / sides),
            r * math.sin(2 * math.pi * i / sides), 0) for i in range(sides)]
    top = [(r * math.cos(2 * math.pi * i / sides),
            r * math.sin(2 * math.pi * i / sides), h) for i in range(sides)]
    verts = bot + top
    faces = [(i, (i + 1) % sides, sides + (i + 1) % sides, sides + i)
             for i in range(sides)]
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple(range(sides, 2 * sides)))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    ob.location = (x, y, z)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    if axis == 'x':
        ob.rotation_euler = (0, math.pi / 2, 0)
    elif axis == 'y':
        ob.rotation_euler = (-math.pi / 2, 0, 0)
    return ob


def stud(name, x, y, z, mat, r=0.115, h=0.075):
    """THE tell. A LEGO surface without studs is just a grey box — this one
    small cylinder per cell is what says "brick" before anything else does."""
    cyl(name, x, y, z, r, h, mat, sides=16)


def strut(name, p0, p1, r, mat, sides=10):
    p0, p1 = mathutils.Vector(p0), mathutils.Vector(p1)
    d = p1 - p0
    length = d.length
    if length < 1e-5:
        return None
    ob = cyl(name, p0.x, p0.y, p0.z, r, length, mat, sides=sides)
    rot = mathutils.Vector((0, 0, 1)).rotation_difference(d.normalized())
    ob.rotation_euler = rot.to_euler()
    return ob


def lerp(p0, p1, t):
    return tuple(a + (b - a) * t for a, b in zip(p0, p1))


# ── Material: glossy injection-moulded plastic, one flat saturated colour
# per part — no procedural grain. A LEGO brick's colour does not vary; that
# UNIFORMITY is as much the style as the studs are.
def plastic(name, rgb, roughness=0.18, coat=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Specular IOR Level'].default_value = 0.6
    bsdf.inputs['Coat Weight'].default_value = coat
    bsdf.inputs['Coat Roughness'].default_value = 0.08
    return mat


# ── The classic LEGO palette (Bley grey, Dark Tan, Reddish Brown, Yellow,
# Black) — swapped in for the photoreal file's earthy, noise-driven browns.
PALETTE = {
    'floor': (0.62, 0.63, 0.62),      # Light Bluish Grey
    'shoulder': (0.55, 0.56, 0.54),   # a shade darker, still grey
    'wall': (0.36, 0.34, 0.31),       # Dark Bluish Grey, the cliff
    'wood': (0.62, 0.42, 0.16),       # Medium Nougat / warm brown beam
    'wood_dark': (0.40, 0.24, 0.10),  # Reddish Brown
    'stud_top': (0.70, 0.71, 0.70),
    'stone': (0.85, 0.85, 0.83),      # White-ish cut stone
    'iron': (0.09, 0.09, 0.10),       # Black
    'accent': (0.92, 0.73, 0.10),     # Yellow — the one loud colour
}


def build_terrain(mats, cell=0.34, extent=4.0):
    n = int(2 * extent / cell)
    gap = cell * 0.05
    made = 0
    for j in range(n):
        for i in range(n):
            x = -extent + cell * (i + 0.5)
            y = -extent + cell * (j + 0.5)
            if math.hypot(x, y) > ISLAND_R:
                continue
            h = ground(x, y)
            zone = zone_at(x, y)
            b = box(f'col{i}_{j}', x, y, 0.0, cell - gap, cell - gap, h,
                   mats[zone])
            stud(f'col{i}_{j}_s', x, y, h, mats['stud_top'])
            made += 1
    print(f'  {made} terrain columns')


def build_crane(x, y, mats, hh=3.0):
    base_z = ground(x, y)
    top = (x - 0.35, y - 0.25, base_z + hh)
    leg_a0 = (x + 0.55, y + 0.65, ground(x + 0.55, y + 0.65))
    leg_b0 = (x + 0.95, y - 0.25, ground(x + 0.95, y - 0.25))
    strut('crane_legA', leg_a0, top, 0.11, mats['iron'])
    strut('crane_legB', leg_b0, top, 0.11, mats['iron'])
    for t in (0.32, 0.58, 0.82):
        strut(f'crane_brace{t}', lerp(leg_a0, top, t), lerp(leg_b0, top, t),
              0.05, mats['accent'])
    back0 = (x - 1.1, y - 1.05, ground(x - 1.1, y - 1.05))
    strut('crane_back', back0, top, 0.095, mats['iron'])
    cyl('crane_pulley', top[0], top[1] + 0.02, top[2] - 0.06, 0.15, 0.09,
        mats['accent'], sides=16, axis='x')
    rope_end = (top[0] + 0.15, top[1], base_z + 0.4)
    strut('crane_rope', (top[0], top[1] + 0.02, top[2] - 0.06), rope_end,
          0.02, mats['iron'], sides=6)
    box('crane_hook', rope_end[0], rope_end[1], rope_end[2] - 0.12, 0.15,
        0.1, 0.16, mats['accent'])


def build_leanto(name, x, y, mats, w=1.1, d=0.9, h=1.0, drop=0.3):
    base_z = ground(x, y)
    for sx_ in (-1, 1):
        for sy_ in (-1, 1):
            px, py = x + sx_ * (w / 2 - 0.06), y + sy_ * (d / 2 - 0.06)
            ph = h - (drop if sy_ < 0 else 0)
            strut(f'{name}_p{sx_}{sy_}', (px, py, ground(px, py)),
                  (px, py, ground(px, py) + ph), 0.05, mats['wood_dark'],
                  sides=8)
    roof = box(f'{name}_roof', x, y, base_z + h - drop * 0.35, w + 0.14,
              d + 0.14, 0.09, mats['wood'])
    roof.rotation_euler = (math.atan2(drop, d), 0, 0)


def build_stone_stack(name, x, y, mats, n=6, spread=0.6, cell=0.3):
    for i in range(n):
        j = ((i * 37 + 11) % 97) / 97.0
        k = ((i * 53 + 29) % 97) / 97.0
        bx = x + (round((j - 0.5) * spread / cell)) * cell
        by = y + (round((k - 0.5) * spread / cell)) * cell
        gz = ground(bx, by)
        b = box(f'{name}{i}', bx, by, gz, cell * 0.9, cell * 0.9,
               cell * 0.9, mats['stone'])
        stud(f'{name}{i}_s', bx, by, gz + cell * 0.9, mats['stud_top'],
             r=0.09, h=0.05)


def build_rails(name, p0, p1, mats, gauge=0.32, ties=9):
    p0v, p1v = mathutils.Vector(p0[:2]), mathutils.Vector(p1[:2])
    d = p1v - p0v
    perp = mathutils.Vector((-d.y, d.x)).normalized() * gauge / 2
    for s in (-1, 1):
        n = 10
        pts = []
        for i in range(n + 1):
            c = p0v.lerp(p1v, i / n) + perp * s
            pts.append((c.x, c.y, ground(c.x, c.y) + 0.05))
        for i in range(n):
            strut(f'{name}_r{s}_{i}', pts[i], pts[i + 1], 0.026,
                  mats['iron'], sides=8)
    for i in range(ties):
        t = (i + 0.5) / ties
        c = p0v.lerp(p1v, t)
        gz = ground(c.x, c.y) + 0.02
        a = (c - perp * 1.3).to_tuple()
        b_ = (c + perp * 1.3).to_tuple()
        strut(f'{name}_tie{i}', (a[0], a[1], gz), (b_[0], b_[1], gz), 0.06,
              mats['wood_dark'], sides=8)


def sky_world(strength=1.15):
    """Bright, even, near-shadowless — a toy catalogue shot, not a mood."""
    world = bpy.data.worlds.new('sky')
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.86, 0.87, 0.9, 1)
    bg.inputs['Strength'].default_value = strength


def sun():
    key = bpy.data.lights.new('sun', type='SUN')
    key.energy = 2.6
    key.angle = math.radians(6.0)
    ob = bpy.data.objects.new('sun', key)
    bpy.context.collection.objects.link(ob)
    ob.rotation_euler = (math.radians(55), 0, math.radians(-25))
    bpy.context.collection.objects.link
    fill = bpy.data.lights.new('fill', type='SUN')
    fill.energy = 0.9
    fill.angle = math.radians(12.0)
    ob2 = bpy.data.objects.new('fill', fill)
    bpy.context.collection.objects.link(ob2)
    ob2.rotation_euler = (math.radians(48), 0, math.radians(155))


def camera(dist=15.0, elev=34, azim=-35):
    cam_data = bpy.data.cameras.new('cam')
    cam_data.lens = 32
    ob = bpy.data.objects.new('cam', cam_data)
    bpy.context.collection.objects.link(ob)
    bpy.context.scene.camera = ob
    er, ea = math.radians(elev), math.radians(azim)
    ob.location = (dist * math.cos(er) * math.sin(ea),
                   -dist * math.cos(er) * math.cos(ea),
                   dist * math.sin(er) + 0.5)
    ob.rotation_euler = (math.radians(90 - elev), 0, ea)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='docs/renders/large_quarry_lego.png')
    ap.add_argument('--samples', type=int, default=96)
    ap.add_argument('--width', type=int, default=1200)
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)

    mats = {k: plastic(k, v) for k, v in PALETTE.items()}

    build_terrain(mats)
    build_crane(2.3, 2.0, mats)
    build_leanto('leanto0', -1.4, -0.5, mats, w=1.1, d=0.9, h=1.05)
    build_leanto('leanto1', 0.6, -1.5, mats, w=0.95, d=0.8, h=0.9)
    build_stone_stack('stack0', -0.9, -1.1, mats, n=7)
    build_stone_stack('stack1', 1.4, -0.5, mats, n=6)
    build_stone_stack('stack2', -0.3, 0.4, mats, n=5)
    build_rails('rail0', (-1.6, -2.3), (1.7, 0.6), mats)

    sky_world()
    sun()
    camera()

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'CUDA'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scene.cycles.device = 'GPU'
    except Exception as e:
        print(f'  GPU unavailable, using CPU  ({e})')
        scene.cycles.device = 'CPU'

    scene.render.film_transparent = True
    scene.render.resolution_x = args.width
    scene.render.resolution_y = round(args.width * 0.82)
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'AgX'

    out_path = os.path.abspath(os.path.join(_ROOT, args.out))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print(f'wrote {out_path}')


main()
