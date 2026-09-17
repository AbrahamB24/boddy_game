"""Boost every material's saturation in the CURRENTLY OPEN .blend, in place.

User 2026-09-07: "passe die Farben von den Blenderdateien so an, dass sie zum
UI passen -> kraeftigere Farben." Every building material's true colour lives
in one of two places (see render_building.py's flat()):

  * an UNLINKED Principled BSDF 'Base Color' (materials with no grain, e.g.
    guide_grid), or
  * a ColorRamp ('ashlar', 'oak', ... all the textured ones) whose two stops
    are a darker/lighter version of the SAME hue+saturation, feeding Base
    Color through noise.

Boosting HSV saturation on whichever of those two holds the real colour (and
leaving hue/value alone) makes every material punchier without touching the
light/dark relationship the grain ramp depends on, and without needing to
know which PALETTE key a material came from -- vary_tones()'s per-instance
copies ('ashlar_-1', 'ashlar_1', ...) go through the exact same two shapes,
so this generic walk (not a name lookup) already covers them.

Also boosts Emission Color the same way, for the handful of materials built
via glow_mat() (a lit window, a lamp) whose Emission Color is a real hue, not
Blender's neutral-white default.

── Why "close the gap to full saturation by a FRACTION", not "multiply S" ──
This palette is already deliberately high-saturation by design (see
render_building.py's own PALETTE comment: "everything is saturated"). A
straight multiplicative boost (tried first at x1.4) clips most of it straight
to S=1.0 — at S=1.0 HSV forces the weakest channel to exactly 0, so
'tile' (0.80,0.30,0.13, S=0.84) came out (0.80,0.20,0.00): flat, neon,
no undertone left. Nudging S toward 1 by a fixed FRACTION of its remaining
headroom instead gives already-vivid colours only a gentle lift (0.84 -> 0.88
at k=0.25) while giving the few deliberately-muted utility tones (iron,
smoke, rock, steel — S around 0.02-0.4) the real richness push the "kein
Grau" design principle already wants for everything else.

    blender --background <file.blend> --python tool/blender/_boost_saturation.py -- --amount 0.25
"""
import argparse
import colorsys
import sys

import bpy

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument('--amount', type=float, default=0.25,
                 help='fraction of the remaining headroom to 1.0 saturation '
                      'to close, e.g. 0.25 takes S=0.6 to S=0.7')
ap.add_argument('--dry-run', action='store_true')
ARGS = ap.parse_args(argv)


def boosted(rgba, amount):
    r, g, b = rgba[0], rgba[1], rgba[2]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    # A TRUE neutral (r==g==b, e.g. PALETTE's 'rock') has no real hue at all
    # -- colorsys still reports one (H defaults to 0, i.e. red) purely as an
    # artifact of the maths, and boosting S from exactly 0 would paint that
    # phantom red into a colour that was deliberately plain grey. Leave an
    # exact neutral alone; anything with even a faint real tint (smoke at
    # S=0.02, say) still gets richened, same as everything else.
    if s < 1e-4:
        return rgba
    s = min(1.0, s + (1.0 - s) * amount)
    nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
    return (nr, ng, nb, rgba[3] if len(rgba) > 3 else 1.0)


touched_materials = 0
touched_stops = 0
skipped = []

for mat in bpy.data.materials:
    if not mat.use_nodes or not mat.node_tree:
        continue
    nt = mat.node_tree
    bsdf = nt.nodes.get('Principled BSDF')
    if bsdf is None:
        continue

    for input_name in ('Base Color', 'Emission Color'):
        inp = bsdf.inputs.get(input_name)
        if inp is None:
            continue
        if not inp.is_linked:
            inp.default_value = boosted(inp.default_value, ARGS.amount)
            touched_materials += 1
            continue
        src = inp.links[0].from_node
        if src.type == 'VALTORGB':  # ColorRamp
            for el in src.color_ramp.elements:
                el.color = boosted(el.color, ARGS.amount)
                touched_stops += 1
            touched_materials += 1
        else:
            # Unexpected topology (not the flat()/ramp shape) -- leave it
            # alone rather than guess, and report it so it can be checked
            # by hand.
            skipped.append(f'{mat.name}.{input_name} <- {src.type}')

print(f'{bpy.data.filepath}: boosted {touched_materials} material inputs '
      f'({touched_stops} ramp stops), amount={ARGS.amount}')
if skipped:
    print('  SKIPPED (unexpected node graph, check by hand):')
    for s in skipped:
        print(f'    {s}')

if not ARGS.dry_run:
    bpy.ops.wm.save_mainfile()
