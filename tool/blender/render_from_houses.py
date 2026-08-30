"""Render every building from the user's OWN saved .blend, not the script.

    blender --background --python tool/blender/render_from_houses.py -- \\
        --houses "C:/Users/olivi/OneDrive - gibb Berufsfachschule Bern/Bøddy/BøddyQuest/Assets/Houses" \\
        --out docs/renders

Every other render entry point (render_building.py's own --preset, and
all_buildings.py) starts from clear() + the PRESET FUNCTION — the procedural
recipe, not whatever the user has since hand-edited in Blender itself. That is
right for iterating on the recipe, and wrong the moment the goal is "ship what
is actually sitting in Houses/*.blend" — those files carry hand edits
(re-tucked beams, a moved prop, a whole cart nobody scripted) that a fresh
build() would silently discard.

So this script OPENS each building's .blend instead of building it, and never
writes back to it — no save_mainfile call anywhere below. The only things it
adds are camera and lights, and only after deleting whatever camera/light
objects the file already had, in memory, for this render alone:

  * light() and frame() both ADD a new object every call (light_add /
    camera_add) rather than reusing one — correct for a fresh clear()+build()
    scene, wrong for a file that may already carry a camera/sun/sky from its
    last save. Skipping the delete would double-light or leave the OLD
    camera as scene.camera racing the new one for whichever was added last.
  * Bevel modifiers are left exactly as saved. bevel_everything() is not
    idempotent either (ob.modifiers.new always adds another 'facets'), and
    unlike camera/light there is no cheap "remove what we're about to
    replace" — the file's own modifier state is the correct one to trust,
    since it reflects whatever bevel pass (if any) the last edit script
    actually ran over the geometry that is there now.

frame() still needs (w, h) to solve the camera from — that comes from
PRESETS, matched by filename stem, so the framing always agrees with
building_roster.sql's grid_w/grid_h.
"""
import argparse
import importlib.util
import os
import sys

import bpy

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    'render_building', os.path.join(_HERE, 'render_building.py'))
rb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rb)

# Never rendered from a hand file this way — a stand-in file for the whole
# roster, not one building, and the per-preset road tiles live in roads.py.
SKIP = {'all_buildings', 'road'}


def render_one(path, name, w, h, scale, headroom):
    bpy.ops.wm.open_mainfile(filepath=path)

    for ob in list(bpy.data.objects):
        if ob.type in ('CAMERA', 'LIGHT'):
            bpy.data.objects.remove(ob, do_unlink=True)

    rb.light()
    rb.frame(w, h, scale, headroom)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if eng in engines:
            scene.render.engine = eng
            break

    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    out_path = os.path.abspath(os.path.join(ARGS.out, f'{name}.png'))
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print(f'  {name}: wrote {out_path}  '
          f'{scene.render.resolution_x}x{scene.render.resolution_y}')


def main():
    global ARGS
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--houses', required=True,
                    help='folder holding the hand-edited .blend files')
    ap.add_argument('--out', default='docs/renders')
    ap.add_argument('--scale', type=int, default=rb.SCALE)
    ap.add_argument('--headroom', type=float, default=1.25)
    ap.add_argument('--only', nargs='*',
                    help='render only these preset names, not the whole folder')
    ARGS = ap.parse_args(argv)

    os.makedirs(ARGS.out, exist_ok=True)
    names = sorted(
        n for n in os.listdir(ARGS.houses)
        if n.endswith('.blend') and not n.endswith('.blend1')
    )

    done = skipped = 0
    for fname in names:
        name = fname[:-len('.blend')]
        if name in SKIP:
            continue
        if ARGS.only and name not in ARGS.only:
            continue
        if name not in rb.PRESETS:
            print(f'  {name}: no PRESETS entry, skipped')
            skipped += 1
            continue
        _, w, h = rb.PRESETS[name]
        render_one(os.path.join(ARGS.houses, fname), name, w, h,
                   ARGS.scale, ARGS.headroom)
        done += 1

    print(f'{done} rendered, {skipped} skipped')


main()
