"""Animate a faceted monster and bake it to sprite sheets.

    blender --background --python tool/blender/monster_anim.py -- \
        --monster tidelord --view front --out docs/renders/monsters/tidelord_s0

Pipeline: build the monster from its parts (tidelord_sprite.build), pose it per
frame with small procedural moves (no armature: the parts are rigid facets, and
rigid parts are what this low-poly style wants), render each frame with the
sprite's toon materials, crop to one common frame, and pack every animation into
a single sheet. Also writes meta.json (frame size, fps, anchor) for Flutter.

Poses are functions of t in [0, 1): idle loops, attack and hurt play once.
"""
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tidelord_sprite as sp  # noqa: E402

RES = 640                       # render canvas, square
K = RES / sp.CANVAS
X0, X1, Y0, Y1 = 60, 620, 165, 613      # crop, in RES pixels (560 x 448)
FW, FH = X1 - X0, Y1 - Y0
COLS = 8


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def curve(t, keys):
    """Piecewise smoothstep through (t, value) keys."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            return v0 + (v1 - v0) * smooth((t - t0) / (t1 - t0))
    return keys[-1][1]


ALIAS = {}          # pose name -> object name, for rigs that name parts differently


class Rig:
    """Neutral transforms of every part, so a pose is a set of deltas."""

    def __init__(self):
        self.base = {}
        for ob in bpy.data.objects:
            self.base[ob.name] = (ob.location.copy(), Vector(ob.rotation_euler),
                                  ob.scale.copy())
        self.eyes = [o for o in bpy.data.objects if o.name.startswith('eye')]
        self.lights = [o for o in bpy.data.objects if o.name.startswith('catch')]
        self.brows = [o for o in bpy.data.objects if o.name.startswith('brow')]
        if ON_RIG:
            ON_RIG()

    def reset(self):
        for n, (l, r, s) in self.base.items():
            ob = bpy.data.objects.get(n)
            if ob:
                ob.location = l
                ob.rotation_euler = Euler(r)
                ob.scale = s

    def move(self, name, d=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
        name = ALIAS.get(name, name)
        ob = bpy.data.objects.get(name)
        if ob is None:
            return
        l, r, s = self.base[name]
        ob.location = l + Vector(d)
        ob.rotation_euler = Euler((r.x + math.radians(rot[0]),
                                   r.y + math.radians(rot[1]),
                                   r.z + math.radians(rot[2])))
        if NO_SCALE:
            scale = (1, 1, 1)         # rigid blocks only ever move and turn
        ob.scale = Vector((s.x * scale[0], s.y * scale[1], s.z * scale[2]))

    def blink(self, k):
        """k = 0 open .. 1 closed."""
        for ob in self.eyes + self.lights:
            l, r, s = self.base[ob.name]
            ob.scale = Vector((s.x, s.y, s.z * (1.0 - 0.92 * k)))

    def flash(self, v):
        for m in bpy.data.materials:
            if m.use_nodes and 'flash' in m.node_tree.nodes:
                m.node_tree.nodes['flash'].inputs[0].default_value = v


# ── poses ────────────────────────────────────────────────────
def pose_idle(rig, t):
    s = 2 * math.pi * t
    breath = math.sin(s)
    rig.move('seal', d=(0, 0, 0.008 * breath))
    rig.move('body', scale=(1 + 0.012 * breath, 1 + 0.012 * breath, 1 + 0.035 * breath))
    rig.move('belly', scale=(1, 1, 1 + 0.03 * breath))
    rig.move('head', d=(0, 0, 0.012 * math.sin(s + 0.7)),
             rot=(0, 2.0 * math.sin(s + 1.2), 4.0 * math.sin(s)))
    rig.move('fl_near', rot=(0, 0, 6 * math.sin(s + 0.4)))
    rig.move('fl_far', rot=(0, 0, -6 * math.sin(s + 1.4)))
    rig.move('tail', rot=(0, 0, 5 * math.sin(s + 0.9)))
    rig.move('fl_rear_near', rot=(0, 4 * math.sin(s + 1.0), 8 * math.sin(s + 0.9)))
    rig.move('fl_rear_far', d=(0, 0, 0.012 * math.sin(s + 1.3)),
             rot=(0, 0, -7 * math.sin(s + 0.9)))
    rig.blink(1.0 if abs(t - 0.65) < 0.08 else 0.0)


def pose_walk(rig, t):
    """A pup's waddle: hunch, push off a flipper, slide, repeat â€” in place."""
    s = 2 * math.pi * t
    hop = abs(math.sin(s))                    # two bumps per cycle = two steps
    push = math.sin(s)
    rig.move('seal', d=(0, 0, 0.03 * hop), rot=(0, 0, 5 * math.sin(s)))
    rig.move('body', scale=(1 + 0.06 * math.cos(2 * s), 1, 1 - 0.04 * math.cos(2 * s)))
    rig.move('head', d=(0.012 * math.cos(2 * s), 0, 0.012 * hop),
             rot=(0, 5 * math.cos(2 * s), -6 * math.sin(s)))
    rig.move('fl_near', rot=(0, -6 * hop, 34 * push))
    rig.move('fl_far', rot=(0, -6 * hop, 34 * push))
    rig.move('fl_rear_near', rot=(0, 5 * hop, 9 * math.sin(s + 1.2)))
    rig.move('fl_rear_far', rot=(0, 5 * hop, -9 * math.sin(s + 1.2)))
    rig.blink(0.0)

def pose_attack(rig, t):
    wind = curve(t, [(0, 0), (0.28, 1), (0.40, 0), (1, 0)])
    lunge = curve(t, [(0, 0), (0.28, 0), (0.46, 1), (0.60, 0.9), (1, 0)])
    slap = curve(t, [(0, 0), (0.30, -0.3), (0.50, 1), (0.66, 0.6), (1, 0)])
    rig.move('seal', d=(0.09 * lunge - 0.04 * wind, 0, 0.0))
    rig.move('body', scale=(1 + 0.07 * lunge - 0.03 * wind, 1 - 0.03 * lunge,
                            1 - 0.05 * wind + 0.02 * lunge))
    rig.move('head', d=(0.20 * lunge - 0.07 * wind, 0, 0.04 * wind - 0.03 * lunge),
             rot=(0, 14 * lunge - 8 * wind, 0))
    rig.move('fl_near', rot=(0, 0, -62 * slap))
    rig.move('fl_far', rot=(0, 0, 40 * slap))
    rig.move('tail', rot=(0, 0, -12 * lunge))
    rig.move('fl_rear_near', rot=(0, -10 * wind, 10 * lunge))
    rig.move('fl_rear_far', d=(0, 0, 0.03 * wind))
    rig.blink(0.6 * lunge)


def pose_hurt(rig, t):
    hit = curve(t, [(0, 0), (0.15, 1), (0.40, 0.5), (0.70, 0.12), (1, 0)])
    wob = math.sin(t * 2 * math.pi * 3) * (1 - t)
    rig.move('seal', d=(-0.08 * hit, 0.01 * wob, 0))
    rig.move('body', scale=(1 - 0.05 * hit, 1 + 0.03 * hit, 1 - 0.08 * hit))
    rig.move('head', d=(-0.09 * hit, 0, 0.02 * hit),
             rot=(0, -16 * hit, 12 * wob))
    rig.move('fl_near', rot=(0, 0, 24 * hit))
    rig.move('fl_far', rot=(0, 0, -24 * hit))
    rig.move('fl_rear_near', rot=(0, 14 * hit, 0))
    rig.move('fl_rear_far', d=(0, 0, 0.04 * hit))
    rig.blink(0.85 * min(1.0, hit * 1.6))
    rig.flash(0.85 if t < 0.12 else (0.45 if t < 0.28 else 0.0))


ANIMS = {
    # name: (frames, fps, loop, pose)
    'walk': (8, 10, True, pose_walk),
    'idle': (16, 12, True, pose_idle),
    'attack': (14, 16, False, pose_attack),
    'hurt': (10, 14, False, pose_hurt),
}


# ── rendering and packing ────────────────────────────────────
ON_RIG = None         # called once the neutral pose is captured (rigid-voxel build)
NO_SCALE = False      # voxel mode: parts may move and rotate but never stretch
PRE_RENDER = None     # optional hooks: a style (e.g. voxel) that rebuilds the
POST_RENDER = None    # geometry around each frame and puts it back after


def render_frame(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    if PRE_RENDER:
        PRE_RENDER()
    bpy.ops.render.render(write_still=True)
    if POST_RENDER:
        POST_RENDER()


def load_rgba(path):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = 'Non-Color'
    img.alpha_mode = 'STRAIGHT'
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return a


def crop(a):
    h = a.shape[0]
    return a[h - Y1:h - Y0, X0:X1, :]


def save_sheet(frames, path):
    n = len(frames)
    rows = (n + COLS - 1) // COLS
    sheet = np.zeros((rows * FH, COLS * FW, 4), dtype=np.float32)
    for i, f in enumerate(frames):
        r, c = divmod(i, COLS)
        # image rows are bottom-up, so row 0 of the sheet is its LAST band
        y = (rows - 1 - r) * FH
        sheet[y:y + FH, c * FW:(c + 1) * FW, :] = f
    img = bpy.data.images.new('sheet', COLS * FW, rows * FH, alpha=True)
    img.colorspace_settings.name = 'Non-Color'
    img.alpha_mode = 'STRAIGHT'
    img.pixels = sheet.ravel().tolist()
    img.file_format = 'PNG'
    img.filepath_raw = path
    img.save()
    bpy.data.images.remove(img)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--monster', default='tidelord')
    ap.add_argument('--view', default='front', choices=['front', 'back'])
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=16)
    ap.add_argument('--only', help='comma list of animations')
    args = ap.parse_args(argv)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, '_frames')
    os.makedirs(tmp, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    target = Vector((-0.05, 0, 0.25))
    if args.view == 'front':
        cam_loc = Vector((0.80, 1.0, 0.38)) * 4.0 + target
    else:
        cam_loc = Vector((-0.90, 0.55, 0.45)) * 4.0 + target
    light = sp.key_light(cam_loc, target)
    sp.build(light)
    sp.fit_camera(cam_loc, target)
    rig = Rig()

    scene.render.engine = 'CYCLES'
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = False
    scene.cycles.device = 'CPU'
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES
    scene.render.film_transparent = True
    scene.render.filter_size = 0.9
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    meta = {'monster': args.monster, 'view': args.view, 'frame_w': FW,
            'frame_h': FH, 'cols': COLS,
            # where the creature's feet are, in frame pixels
            'anchor': [round(((124 + 544) / 2 - X0) * 1.0), round(552 - Y0)],
            'anims': {}}
    only = set(args.only.split(',')) if args.only else None
    for name, (n, fps, loop, pose) in ANIMS.items():
        if only and name not in only:
            continue
        frames = []
        for i in range(n):
            rig.reset()
            rig.flash(0.0)
            rig.blink(0.0)
            pose(rig, i / n)
            bpy.context.view_layer.update()
            p = os.path.join(tmp, f'{name}_{i:02d}.png')
            render_frame(p)
            frames.append(crop(load_rgba(p)))
            print('frame', name, i)
        sheet = f'{args.view}_{name}.png'
        save_sheet(frames, os.path.join(out, sheet))
        meta['anims'][name] = {'sheet': sheet, 'frames': n, 'fps': fps,
                               'loop': loop}
    with open(os.path.join(out, f'meta_{args.view}.json'), 'w') as f:
        json.dump(meta, f, indent=2)
    print('done', out)


if __name__ == '__main__':
    main()
