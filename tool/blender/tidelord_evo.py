"""Tidelord's two evolutions, built fresh (not traced from the sprites).

    stage 1  OCEANKING        — a heavier, broader bull: a crown of ice crystals,
                                long tusks, three ice plates down the spine,
                                deeper royal blue.
    stage 2  ABYSSAL TITAN    — a colossus: a tall crystal crown, great tusks,
                                a ridge of five spines, crystal shoulder
                                spurs, near-midnight blue.

Both start from the same rig as the pup (tidelord_pro.build: body, head,
four flippers, eyes — so every pose in monster_anim.py works unchanged) and
then GROW it: the whole creature is scaled up, and armour and crystals are
added. Block size stays the same, so a bigger creature simply has more blocks
(monster_voxel.py takes HALF/DEPTH from MV_HALF / MV_DEPTH for that).

Colours are flat per part, because a block is one colour (see monster_voxel).
"""
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pro_kit as K  # noqa: E402
import tidelord_pro as tp  # noqa: E402

# creature scale in the world, anchor half-size and Remesh depth (same block)
CONFIG = {
    1: {'scale': 1.38, 'half': 2.0, 'depth': 7},
    2: {'scale': 1.78, 'half': 2.0, 'depth': 7},
}
# how much BIGGER than the pup each stage is drawn in the UI (fill multiplier)
UI_SCALE = {1: 1.2, 2: 1.4}

PALETTE = {
    1: {'sk_top': '#2556b8', 'sk_head': '#2f68cc', 'sk_flip': '#3f7bdc',
        'sk_flip_d': '#2556b8', 'sk_belly': '#b4d0f0', 'sk_cream': '#e6d6ae'},
    2: {'sk_top': '#173a82', 'sk_head': '#1f4a9c', 'sk_flip': '#2b5cb4',
        'sk_flip_d': '#173a82', 'sk_belly': '#8fc4e6', 'sk_cream': '#dccaa0'},
}


def _lean(dx, dy, amount):
    """Euler that tips a +z crystal toward (dx, dy)."""
    return (-amount * dy, amount * dx, 0.0)


def build(stage):
    cfg = CONFIG[stage]
    root = tp.build(yaw=0.0)
    head = bpy.data.objects['head']
    ice = K._mats['ice']
    ivory = K._mats['ivory']

    def crystal(parent, x, y, z, r, h, tilt=(0, 0, 0), sides=6):
        c = K.cyl(0, 0, 0, r, 0.004, h, ice, seg=sides, smooth=False)
        c.location = (x, y, z)
        c.rotation_euler = tilt
        c.parent = parent
        return c

    def tusk(sg, r, length, out):
        t = K.cyl(0, 0, 0, r, 0.004, length, ivory, seg=8)
        t.location = (0.30, sg * 0.05, -0.04)
        t.rotation_euler = (math.radians(180 + sg * out), math.radians(-10), 0)
        t.parent = head
        return t

    if stage == 1:
        # crown: five crystals round the horn's foot
        for i in range(5):
            a = math.radians(-90 + i * 45)
            crystal(head, 0.13 + math.cos(a) * 0.075, math.sin(a) * 0.09, 0.205,
                    0.03, 0.12 + 0.03 * (i % 2),
                    _lean(math.cos(a), math.sin(a), 0.30))
        for sg in (-1, 1):
            tusk(sg, 0.024, 0.15, 7)
        for x in (0.04, -0.10, -0.24):
            crystal(root, x, 0.0, 0.40 - (0.06 if x < -0.2 else 0.0),
                    0.055, 0.14, (0, math.radians(-14), 0))
    else:
        for i in range(7):
            a = math.radians(-90 + i * 30)
            crystal(head, 0.12 + math.cos(a) * 0.085, math.sin(a) * 0.105, 0.20,
                    0.034, 0.16 + 0.05 * (i % 3 == 1),
                    _lean(math.cos(a), math.sin(a), 0.34))
        crystal(head, 0.12, 0.0, 0.22, 0.06, 0.30, (0, math.radians(8), 0), 6)
        for sg in (-1, 1):
            tusk(sg, 0.034, 0.26, 9)
        for x, z, h in ((0.12, 0.46, 0.20), (-0.02, 0.45, 0.26),
                        (-0.16, 0.40, 0.28), (-0.29, 0.31, 0.24),
                        (-0.40, 0.26, 0.18)):
            crystal(root, x, 0.0, z, 0.07, h, (0, math.radians(-16), 0))
        # shoulder spurs, pointing out and up
        for sg in (-1, 1):
            crystal(root, 0.10, sg * 0.30, 0.34, 0.045, 0.17,
                    (math.radians(-sg * 55), 0, 0))

    root.scale = (cfg['scale'],) * 3
    return root


if __name__ == '__main__':
    print('library: import build(stage) from the render scripts')
