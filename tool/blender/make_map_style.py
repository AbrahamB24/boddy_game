"""The map's ground and props in the chosen look ("Foto-Voxel+", between the
shipped photo look and the golden-hour one), rendered with the real pipeline.

    blender --background --python tool/blender/make_map_style.py -- \
        --what tiles,trees,stones --out C:/tmp/map --samples 64

Writes RAW pngs (no grade) into --out; tool/blender/map_style_post.py grades
them and ships them as webp into assets/images/terrain/.

  tiles   grass / sand / water swatches (terrain_voxel's own fields)
  trees   prop_conifer_{s,m,l}, prop_broadleaf_{s,m,l}: the chunky voxel trees
          (terrain_voxel.tree_*), each scaled so its picture covers the same
          AREA as the picture it replaces (= the same presence on the map)
  stones  prop_stone_{a..f}: the voxel rocks, same area rule

The light is warmer / brighter than K.lighting's default; the rest of the grade
(saturation, tint) is the post pass.
"""
import math
import os
import random
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402
import terrain_voxel as T  # noqa: E402

SUN = (1.0, 0.83, 0.62)          # between the shipped (1,.86,.66) and golden hour (1,.74,.46)
LIGHT = dict(sun=5.2, sky=1.2, elev=40, swing=-38)


def install_light():
    orig = K.lighting

    def lighting(*a, **k):
        k = dict(k)
        k.update(LIGHT)
        orig(*a, **k)
        for o in bpy.data.objects:
            if o.type == 'LIGHT' and o.data.type == 'SUN' and o.name != 'rim':
                o.data.color = SUN
    K.lighting = lighting


# ── trees: terrain_voxel's own, with a size class ─────────────────────────
def conifer(size, seed):
    r = random.Random(seed)
    v = T.Vox(['#5b3a22', '#2f6b34', '#3b8040', '#27592c', '#4a954a'], T.U)
    v.box(-1, -1, 0, 1, 1, 6, 0)
    tiers = [(8, 5.6, 6), (6, 4.8, 5), (4, 3.8, 5), (2, 2.8, 4), (0, 1.8, 3)]
    if size == 's':
        tiers = tiers[1:]
    elif size == 'l':
        tiers = [(10, 7.0, 7)] + tiers
    z = 5
    for _, rad, hgt in tiers:
        for dz in range(hgt):
            rr = rad * (1 - dz / (hgt + 1.0))
            for x in range(-9, 9):
                for y in range(-9, 9):
                    d = math.hypot(x + 0.5, y + 0.5)
                    if d <= rr + r.uniform(-0.35, 0.35):
                        shade = 1 if (x + y + dz) % 5 else 2
                        if d > rr - 0.9 and dz < hgt - 1:
                            shade = 3
                        v.put(x, y, z + dz, shade)
        z += hgt - 2
    v.put(0, 0, z + 1, 4)
    return v


def broadleaf(size, seed):
    r = random.Random(seed)
    v = T.Vox(['#5b3a22', '#3e8a38', '#4fa343', '#2f7230', '#6bb85a'], T.U)
    k = {'s': 0.78, 'm': 1.0, 'l': 1.2}[size]
    th = int(8 * k)
    v.box(-1, -1, 0, 1, 1, th, 0)
    top = th + 5
    blobs = [(0, 0, top, 7 * k), (-5 * k, 1, top - 2, 4.5 * k),
             (5 * k, -1, top - 2, 4.5 * k), (1, 5 * k, top - 2, 4 * k),
             (-1, -5 * k, top - 1, 4 * k)]
    for bx, by, bz, rad in blobs:
        v.ball(bx, by, bz, rad, rad, rad * 0.85, lambda x, y, z: (
            4 if z > top + 1 and r.random() < 0.5 else
            (3 if z < top - 3 else (2 if r.random() < 0.6 else 1))), r, 0.18)
    return v


STONES = {
    'a': (11, [(0, 0, 2, 3, 3, 2)]),
    'b': (12, [(0, 0, 3, 4, 3.5, 3), (4, 1, 2, 2.5, 2.5, 2)]),
    'c': (13, [(0, 0, 1.5, 8, 5, 1.8), (6, 3, 1, 3.5, 2.5, 1.2)]),
    'd': (14, [(0, 0, 5, 6.5, 6, 5), (-5, 3, 2, 2.5, 2.5, 2)]),
    'e': (15, [(0, 0, 3, 5, 4, 3), (5, 2, 2, 3, 3, 2), (-4, 3, 2, 3, 2.5, 2),
               (2, -4, 2, 3, 2, 2)]),
    'f': (16, [(-2, 0, 1, 2, 1.5, 1), (1, 2, 1, 1.8, 1.5, 1), (3, -1, 1, 1.5, 1.2, 1)]),
}


def shapes():
    out = {}
    for s, seed in (('s', 31), ('m', 32), ('l', 33)):
        out['conifer_' + s] = lambda s=s, seed=seed: conifer(s, seed)
        out['broadleaf_' + s] = lambda s=s, seed=seed: broadleaf(s, seed + 10)
    for k, (seed, blobs) in STONES.items():
        out['stone_' + k] = lambda seed=seed, blobs=blobs: T._stone(seed, blobs)
    return out


def render_shape(name, make, outdir, samples):
    """Like terrain_voxel.render_prop, but the picture is kept big and the foot's
    pixel is written next to it; the post pass crops symmetric about the foot
    (the app anchors a prop at its picture's bottom centre) and resizes."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    K._mats.clear()
    vox = make()
    xs = [k[0] for k in vox.v]
    ys = [k[1] for k in vox.v]
    cx, cy = (min(xs) + max(xs) + 1) / 2, (min(ys) + max(ys) + 1) / 2
    ob = T.build_mesh(vox)
    ob.location = (-cx * vox.u, -cy * vox.u, 0)
    K.lighting()
    cam, right, up, back = T.fit_iso_camera()
    bpy.context.view_layer.update()
    pts = []
    for v in ob.data.vertices:
        p = ob.matrix_world @ v.co
        pts.append((p.dot(right), p.dot(up)))
    x0, x1 = min(p[0] for p in pts), max(p[0] for p in pts)
    y0, y1 = min(p[1] for p in pts), max(p[1] for p in pts)
    w, h = x1 - x0, y1 - y0
    pad = 0.06 * max(w, h)
    big = max(w + 2 * pad, h + 2 * pad)
    ppu = 1400 / big
    ow, oh = max(8, int((w + 2 * pad) * ppu)), max(8, int((h + 2 * pad) * ppu))
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = ow, oh
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(w + 2 * pad, h + 2 * pad)
    cam.data.shift_x = cam.data.shift_y = 0
    ax, ay = (x0 + x1) / 2, (y0 + y1) / 2
    cam.location = right * ax + up * ay + back * 60
    cam.data.clip_start, cam.data.clip_end = 0.1, 200
    T.setup_cycles(scene, samples, transparent=True)
    path = os.path.join(outdir, f'prop_{name}.png')
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    # where the origin (the foot) lands, in px
    foot_x = ow / 2 + (0 - ax) * ppu
    with open(path[:-4] + '.foot', 'w') as f:
        f.write(f'{foot_x}')
    print('PROP', name, ow, 'x', oh, flush=True)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--what', default='tiles,trees,stones')
    ap.add_argument('--only', default='')
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=64)
    a = ap.parse_args(argv)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    install_light()
    what = a.what.split(',')
    only = a.only.split(',') if a.only else None
    if 'tiles' in what:
        for n in ('grass', 'sand', 'water'):
            if only and n not in only:
                continue
            bpy.ops.wm.read_factory_settings(use_empty=True)
            K._mats.clear()
            if n == 'grass':
                T.render_tile(out, a.samples)
            else:
                T.render_flat(out, a.samples, n)
            print('done', n, flush=True)
    for name, make in shapes().items():
        kind = name.split('_')[0]
        if not ((kind in ('conifer', 'broadleaf') and 'trees' in what) or
                (kind == 'stone' and 'stones' in what)):
            continue
        if only and name not in only:
            continue
        render_shape(name, make, out, a.samples)


if __name__ == '__main__':
    main()
