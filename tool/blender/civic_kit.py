"""Shared parts of the era-I civic buildings (2026-11-04): one half-timbered hall
with any number of doors, windows and a gable roof, plus a few yard props.

    hall(M, x0, x1, y0, y1, eave, axis, roof, doors=[(face, a, w, h)],
         wins=[(face, a, shut, glow)])  -> ridge height
"""
import math

from fw_kit import *  # noqa: F401,F403
from camp_kit import *  # noqa: F401,F403
import fw_kit as F


def hall(M, x0, x1, y0, y1, eave, axis='y', roof='roof', doors=(), wins=(),
         pitch=F.PITCH, oh=0.1, oe=0.1, lanterns=True, mid=False, z_base=None,
         win_dz=None):
    """A one-storey hall. Ridge along `axis`; its two gables are plain plaster
    triangles with the king-post frame. Doors and windows are cut out of the
    frame so no timber crosses a pane."""
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    zb = G if z_base is None else z_base
    box(xm, ym, zb, x1 - x0 + 0.06, y1 - y0 + 0.06, DIM['plinth'], M['stone_dk'], bevel=0.01)
    zpl = zb + DIM['plinth']
    box(xm, ym, zpl, x1 - x0, y1 - y0, eave - zpl, M['plaster'], bevel=0.008)
    faces = {'s': (y0, x0, x1), 'n': (y1, x0, x1), 'e': (x1, y0, y1), 'w': (x0, y0, y1)}
    holes = {f: [] for f in faces}
    for f, a, w, h in doors:
        holes[f].append((a, w))
    for f, a, *_ in wins:
        holes[f].append((a, DIM['window'][0]))
    for f, (fx, a0, a1) in faces.items():
        nb = max(2, round((a1 - a0) / 0.3))
        F.wall_frame(M, f, fx, a0, a1, zpl, eave, nb, braces=(0, nb - 1), mid=mid,
                     holes=holes[f])
    for f, a, w, h in doors:
        F.door(M, f, faces[f][0], a, w, h, zpl)
        if lanterns:
            F.lantern(M, f, faces[f][0], a + w / 2 + 0.09, zpl + h - 0.06)
    zc = zpl + (win_dz if win_dz is not None else min(0.36, (eave - zpl) * 0.55))
    for f, a, shut, glow in wins:
        F.window(M, f, faces[f][0], a, zc, *DIM['window'], shut, glow)
    if axis == 'y':
        F.gable_wall(M, 's', y0, x0, x1, eave, pitch=pitch)
        F.gable_wall(M, 'n', y1, x0, x1, eave, pitch=pitch)
        return F.gable_roof(M, xm, ym, eave, y1 - y0, x1 - x0, 'y', M[roof], oh=oh, oe=oe,
                            pitch=pitch)
    F.gable_wall(M, 'e', x1, y0, y1, eave, pitch=pitch)
    F.gable_wall(M, 'w', x0, y0, y1, eave, pitch=pitch)
    return F.gable_roof(M, xm, ym, eave, x1 - x0, y1 - y0, 'x', M[roof], oh=oh, oe=oe,
                        pitch=pitch)


def fence_line(M, pts, h=0.17, step=0.1):
    """A post-and-rail fence along a polyline at yard level."""
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i] + (G,)), Vector(pts[i + 1] + (G,))
        n = max(1, int((b - a).length / step))
        for k in range(n + 1):
            p = a + (b - a) * (k / n)
            beam(p, p + Vector((0, 0, h)), 0.022, M['timber'], bevel=0.003)
        for z in (h * 0.4, h * 0.85):
            beam(a + Vector((0, 0, z)), b + Vector((0, 0, z)), 0.015, M['timber'], bevel=0.002)


def trough(M, x, y, length=0.4, rot=0.0, fill='water'):
    """A long plank trough, filled with water or hay."""
    c, s = math.cos(rot), math.sin(rot)
    rbox((x, y, G + 0.05), (length, 0.11, 0.1), (0, 0, rot), M['planks'], bevel=0.006)
    rbox((x, y, G + 0.095), (length - 0.04, 0.07, 0.02), (0, 0, rot), M[fill], bevel=0)
    for g in (-1, 1):
        px, py = x + g * length * 0.38 * c, y + g * length * 0.38 * s
        beam((px, py, G), (px, py, G + 0.05), 0.03, M['timber'])


def flat_emblem(M, face, parts):
    """A custom guild emblem: parts = [(u, v, w, h, rot, mat)] in units of the
    sign's size, drawn flat on the board like camp_kit.emblem does."""
    def draw(c, size):
        for u, v, w, h, rot, mat in parts:
            if face in ('s', 'n'):
                p = Vector((c.x + u * size, c.y, c.z + v * size))
                eul = (0, rot, 0)
            else:
                p = Vector((c.x, c.y + u * size, c.z + v * size))
                eul = (rot, 0, 0)
            rbox(p, D(face, w * size, 0.04, h * size), eul, M[mat], bevel=0.002)
    return draw
