"""Animate the photoreal (building-style) Tidelord and bake sprite sheets.

    blender --background --python tool/blender/monster_anim_pro.py -- \
        --view front --out docs/renders/monsters/tidelord_pro [--only idle] [--samples 48]

Same poses, camera framing and sheet layout as monster_anim.py (so Flutter
reads both identically); the difference is the look: fur, wet eyes, golden-hour
sun, real shadows, AgX. Lighting is physically consistent, so shading changes
smoothly as parts move instead of stepping between flat colours.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import monster_anim as ma  # noqa: E402
import tidelord_sprite as sp  # noqa: E402
import tidelord_pro as tp  # noqa: E402
import pro_kit as K  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--view', default='front', choices=['front', 'back', 'sidel', 'sider'])
    ap.add_argument('--out', required=True)
    ap.add_argument('--samples', type=int, default=48)
    ap.add_argument('--only')
    ap.add_argument('--still', help='render only the neutral pose to this png')
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
    elif args.view == 'sidel':
        # SIDE VIEW battle (2026-11-05): my monster stands at the LEFT of the
        # field and faces right, a little toward the lens so the face reads.
        cam_loc = Vector((0.86, -0.50, 0.30)) * 4.0 + target
    elif args.view == 'sider':
        # ...the enemy stands at the right and faces left (own lighting, not a
        # mirrored sheet, so the sun stays upper-left on both).
        cam_loc = Vector((-0.37, 0.93, 0.30)) * 4.0 + target
    else:
        cam_loc = Vector((-0.90, 0.55, 0.45)) * 4.0 + target

    stage = int(os.environ.get('MV_STAGE', '0'))
    if stage:
        import tidelord_evo as evo
        evo.build(stage)
    else:
        tp.build(yaw=0.0)
    # sun from the upper-left-front of the lens, the building rig's colour
    K.lighting(sky=0.85, sun=5.5)
    L = sp.key_light(cam_loc, target)
    for ob in bpy.data.objects:
        if ob.type == 'LIGHT' and ob.data.type == 'SUN':
            ob.rotation_euler = (-L).to_track_quat('-Z', 'Y').to_euler()
    # a cool rim light from behind-right of the lens
    cdir = (Vector(target) - cam_loc).normalized()
    right = cdir.cross(Vector((0, 0, 1))).normalized()
    K.rim_light((-cdir * 0.7 + right * 0.45 + Vector((0, 0, 0.6))).normalized())
    sp.fit_camera(cam_loc, target)

    scene.render.engine = 'CYCLES'
    cy = scene.cycles
    cy.device = 'CPU'
    cy.samples = args.samples
    cy.use_adaptive_sampling = True
    cy.use_denoising = True
    try:
        cy.denoiser = 'OPENIMAGEDENOISE'
    except TypeError:
        pass
    cy.max_bounces = 6
    scene.render.resolution_x = ma.RES
    scene.render.resolution_y = ma.RES
    scene.render.film_transparent = True
    scene.render.filter_size = 0.9
    vs = scene.view_settings
    vs.view_transform = 'AgX'
    for want in ('AgX - Medium High Contrast', 'Medium High Contrast'):
        if want in vs.bl_rna.properties['look'].enum_items.keys():
            vs.look = want
            break
    vs.exposure = 0.55
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'

    ma.ALIAS.update({'seal': 'seal_root', 'fl_rear_near': 'fl_rear_a',
                     'fl_rear_far': 'fl_rear_b'})
    rig = ma.Rig()

    if args.still:
        ma.render_frame(os.path.abspath(args.still))
        return

    meta = {'monster': 'tidelord', 'style': 'pro', 'view': args.view,
            'frame_w': ma.FW, 'frame_h': ma.FH, 'cols': ma.COLS,
            'anchor': [round((124 + 544) / 2 - ma.X0), round(552 - ma.Y0)],
            'anims': {}}
    only = set(args.only.split(',')) if args.only else None
    for name, (n, fps, loop, pose) in ma.ANIMS.items():
        if only and name not in only:
            continue
        frames = []
        for i in range(n):
            rig.reset()
            rig.blink(0.0)
            pose(rig, i / n)
            bpy.context.view_layer.update()
            p = os.path.join(tmp, f'{name}_{i:02d}.png')
            ma.render_frame(p)
            frames.append(ma.crop(ma.load_rgba(p)))
            print('frame', name, i, flush=True)
        sheet = f'{args.view}_{name}.png'
        ma.save_sheet(frames, os.path.join(out, sheet))
        meta['anims'][name] = {'sheet': sheet, 'frames': n, 'fps': fps,
                               'loop': loop}
    with open(os.path.join(out, f'meta_{args.view}.json'), 'w') as f:
        json.dump(meta, f, indent=2)
    ma.report_cuts(args.view)
    print('done', out)


if __name__ == '__main__':
    main()
