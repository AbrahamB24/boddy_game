"""A real gear/cog badge (user 2026-11-07, comparing against the reference
image): the settings medal needs an actual gear, not the decorative
three-ring "knot" `make_ui4.py`'s `piece_badge_knot` draws — that piece was
built for something else and only ever stood in here because it was the
nearest spare medal lying around when the two badges were first wired up.
Same `medal_ring` frame as `badge_bolt`/`badge_knot`, same vivid grading as
`make_ui6.py`'s re-renders (user 2026-11-07: "kräftigere Farben") — new glyph
only.

    blender --background --python tool/blender/make_ui7.py -- \
        badge_gear badge_gear_bare [--samples N --px N]
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_ui4  # noqa: E402
import make_ui as U  # noqa: E402
from make_ui4 import vox, finish, medal_ring, _bare  # noqa: E402
from icon_lib import box, cyl, ring  # noqa: E402


def piece_badge_gear(M):
    """A gold cog: a toothed ring round a dark hub, face-on (reference image,
    2026-11-07 — gold, not the grey iron the first pass used)."""
    vox(0.034)
    medal_ring(1.0, 0.74, 'timber', 'planks', studs=0, t=0.2)
    y = -0.16  # the same depth badge_bolt's glyph sits at
    ring(0, y, 0, 0.36, 0.13, 'gold', seg=28)
    for k in range(8):
        a = k * math.tau / 8
        box(0.46 * math.sin(a), y, 0.46 * math.cos(a), 0.16, 0.10, 0.16, 'gold_dk', bev=0.0)
    cyl(0, y, 0, 0.16, 0.11, 'iron_dk', axis='y', seg=20)
    finish()
    return [], 2.3


U.PIECES['badge_gear'] = (piece_badge_gear, False, 12.0)
U.PIECES['badge_gear_bare'] = (_bare(piece_badge_gear), False, 12.0)

_cycles = U.cycles


def _vivid_cycles(samples):
    _cycles(samples)
    import bpy
    vs = bpy.context.scene.view_settings
    vs.view_transform = 'Standard'
    vs.look = 'None'
    vs.exposure = 0.25


U.cycles = _vivid_cycles

if __name__ == '__main__':
    U.main()
