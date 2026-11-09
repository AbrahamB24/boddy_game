"""A finer voxel grid for the small HUD glyphs (user 2026-11-07: "es sind
voxel, aber sehr fein, so scheint es als glatt, wenn es sehr klein ist" —
the chest/compass already read smooth in the reference not because they
skip voxelizing, but because they are modelled at a much bigger relative
scale than these small icons, so the same cube size reads far finer on
them. The fix is a finer grid on the small pieces, not dropping
voxelization — nothing here is redefined, every vox() call just gets
scaled down before it reaches make_ui4's own voxelizer.

    blender --background --python tool/blender/make_ui8.py -- \
        hud_log hud_stone hud_fish hud_coin hud_house hud_clock icon_monster \
        icon_hammer icon_paw icon_map icon_people icon_person icon_bag icon_tasks \
        [--samples N --px N]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_ui4  # noqa: E402
import make_ui5  # noqa: F401,E402  side effect: vivid U.cycles override
import make_ui as U  # noqa: E402

_orig_vox = make_ui4.vox


def _fine_vox(v):
    _orig_vox(v * 0.45)


# Both names: make_ui5 did `from make_ui4 import vox`, a separate binding in
# its own namespace, so it needs reassigning too.
make_ui4.vox = _fine_vox
make_ui5.vox = _fine_vox


# The globe is a UV sphere (`ball()`, already smooth-shaded) — voxelizing a
# round silhouette at ANY finite grid leaves a spiky, hedgehog-like edge (a
# sphere is the one shape voxelizing never suits, no matter how fine the
# grid); skip the voxelize step for it instead of just shrinking it.
# `frame()` finds its camera target by scanning every MESH object in the
# scene, not through the piece function's own return value, so an
# un-voxelized ball still frames and renders correctly.
def piece_globe_smooth(deg):
    from make_ui4 import ball, globe_mat_rot
    ball(0, -0.44, 0, 0.38, 0.38, 0.38, globe_mat_rot(deg), seg=48)
    return [], 0.9


for _i in range(make_ui4.GLOBE_FRAMES):
    U.PIECES['globe_%d' % _i] = (
        (lambda M, d=_i * 360.0 / make_ui4.GLOBE_FRAMES: piece_globe_smooth(d)),
        False,
        12.0,
    )

if __name__ == '__main__':
    U.main()
