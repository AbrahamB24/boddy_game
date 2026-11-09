"""Vivid-colour re-render of the chest/compass medal faces, the two badge
medals, and the globe's 48 frames (user 2026-11-07: matching the AI reference
image's "deutlich hellere und knalligere Farben") — the same `_vivid_cycles`
override make_ui5.py already uses for hud_log/hud_coin/etc., applied to the
pieces that still carry make_ui4's older, muted AgX grade.

    blender --background --python tool/blender/make_ui6.py -- \
        chest chest_nr compass compass_nr \
        badge_bolt badge_bolt_bare badge_knot badge_knot_bare \
        globe_0 globe_1 ... globe_47 [--samples N --px N]

Reuses make_ui4's/make_ui5's own piece functions — nothing is redefined here.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_ui4  # noqa: F401,E402  registers chest/compass/badge_*/globe_* into U.PIECES
import make_ui5  # noqa: F401,E402  registers chest_nr/compass_nr into U.PIECES
import make_ui as U  # noqa: E402

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
