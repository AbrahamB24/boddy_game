"""Map sprites: the Tidelord walking and idling in the four map headings.

    blender --background --python tool/blender/monster_walk.py -- \
        --out docs/renders/monsters/tidelord_pro/map [--samples 48] [--only se]

Camera = the buildings' isometric camera (render_building.frame), fixed. The
creature is turned to face each of the four tile directions instead, so a
creature walking along a road reads right with the same light as the houses:

    se = world +x  (down-right on screen)     ne = world +y  (up-right)
    nw = world -x  (up-left)                  sw = world -y  (down-left)

Every direction gets 'walk' (8 frames) and 'idle' (8). One frame size for all,
so a sprite swap never jumps; meta_map.json carries the foot anchor.
"""
import json
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster_anim as ma  # noqa: E402
import tidelord_pro as tp  # noqa: E402
import pro_kit as K  # noqa: E402
import render_building as rb  # noqa: E402

HEADINGS = {'se': 0.0, 'ne': 90.0, 'nw': 180.0, 'sw': 270.0}
ANIMS = {k: ma.ANIMS[k] for k in ('walk', 'idle')}
ANIMS['idle'] = (8, 8, True, ma.pose_idle)
TILES = 1.7          # frame holds a 1.7 x 1.7 tile base: room for the whole pup
SCALE = 5


def setup(heading_yaw, samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    K._mats.clear()          # materials die with read_factory_settings
    # Evolutions (MV_STAGE=1/2) are bigger in the world: the frame widens by
    # the same factor and the pixels per tile shrink by it, so every stage
    # comes out in the SAME frame size with the creature filling it alike —
    # the game draws the later stages bigger itself.
    stage = int(os.environ.get('MV_STAGE', '0'))
    k = 1.0
    if stage:
        import tidelord_evo as evo
        k = evo.CONFIG[stage]['scale']
        evo.build(stage, yaw=heading_yaw, head_yaw=6.0, catcher=3.4 * k)
    else:
        tp.build(yaw=heading_yaw, head_yaw=6.0, catcher=3.4)
    K.lighting(sky=0.85, sun=5.5)
    K.rim_light(Vector((-0.6, 0.5, 0.7)))
    rb.frame(TILES * k, TILES * k, SCALE / k, 0.80, 0.0, fit=False)
    scene.render.engine = 'CYCLES'
    cy = scene.cycles
    cy.device = 'CPU'
    cy.samples = samples
    cy.use_adaptive_sampling = True
    cy.use_denoising = True
    try:
        cy.denoiser = 'OPENIMAGEDENOISE'
    except TypeError:
        pass
    cy.max_bounces = 6
    scene.render.film_transparent = True
    scene.render.filter_size = 0.9
    vs = scene.view_settings
    vs.view_transform = 'AgX'
    for want in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        if want in vs.bl_rna.properties['look'].enum_items.keys():
            vs.look = want
            break
    vs.exposure = 0.3
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    ma.ALIAS.clear()
    ma.ALIAS.update({'seal': 'seal_root', 'fl_rear_near': 'fl_rear_a',
                     'fl_rear_far': 'fl_rear_b'})
    return scene


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=48)
    ap.add_argument('--only', help='comma list of headings')
    ap.add_argument('--anims', help='comma list of animations')
    ap.add_argument('--still', help='render one neutral frame of --only[0] here')
    args = ap.parse_args(argv)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, '_frames')
    os.makedirs(tmp, exist_ok=True)
    heads = args.only.split(',') if args.only else list(HEADINGS)
    anims = args.anims.split(',') if args.anims else list(ANIMS)

    meta = {'monster': 'tidelord', 'style': 'pro', 'view': 'map', 'cols': ma.COLS,
            'headings': {'se': '+x', 'ne': '+y', 'nw': '-x', 'sw': '-y'},
            'anims': {}}
    for h in heads:
        scene = setup(HEADINGS[h], args.samples)
        W, H = scene.render.resolution_x, scene.render.resolution_y
        ma.RES = None
        ma.X0, ma.X1, ma.Y0, ma.Y1 = 0, W, 0, H
        ma.FW, ma.FH = W, H
        meta['frame_w'], meta['frame_h'] = W, H
        base_px = int(TILES * 2 * 32 * SCALE)
        meta['anchor'] = [W // 2, H - base_px // 4]
        if args.still:
            ma.render_frame(os.path.abspath(args.still))
            return
        rig = ma.Rig()
        for name in anims:
            n, fps, loop, pose = ANIMS[name]
            frames = []
            for i in range(n):
                rig.reset()
                rig.blink(0.0)
                pose(rig, i / n)
                bpy.context.view_layer.update()
                p = os.path.join(tmp, f'{h}_{name}_{i:02d}.png')
                ma.render_frame(p)
                frames.append(ma.crop(ma.load_rgba(p)))
                print('frame', h, name, i, flush=True)
            sheet = f'{h}_{name}.png'
            ma.save_sheet(frames, os.path.join(out, sheet))
            meta['anims'].setdefault(h, {})[name] = {
                'sheet': sheet, 'frames': n, 'fps': fps, 'loop': loop}
    with open(os.path.join(out, 'meta_map.json'), 'w') as f:
        json.dump(meta, f, indent=2)
    ma.report_cuts('walk')
    print('done', out)


if __name__ == '__main__':
    main()
