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
         win_dz=None, wins_up=(), extra_holes=(), mid_through=False):
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
    # each opening with ITS width, shutters included by wall_frame, so no post
    # or brace ever crosses a shutter (user 2026-11-09: never, in any building)
    for lst, dims in ((wins, DIM['window']), (wins_up, DIM['window_up'])):
        for f, a, _s, _g, *rest in lst:
            dd = DIM['window_small'] if len(rest) > 1 and rest[1] == 'small' else dims
            holes[f].append((a, F.window_w(dd[0])))
    for f, a, w in extra_holes:         # openings the caller draws itself (a balcony door, a bay)
        holes[f].append((a, w))
    for f, (fx, a0, a1) in faces.items():
        nb = max(2, round((a1 - a0) / 0.3))
        F.wall_frame(M, f, fx, a0, a1, zpl, eave, nb, braces=(0, nb - 1), mid=mid,
                     holes=holes[f], mid_through=mid_through)
    for f, a, w, h in doors:
        F.door(M, f, faces[f][0], a, w, h, zpl)
        if lanterns:
            F.lantern(M, f, faces[f][0], a + w / 2 + 0.09, zpl + h - 0.06)
    zc = zpl + (win_dz if win_dz is not None else min(0.36, (eave - zpl) * 0.55))
    # A window entry is (face, a, shut, glow[, dz[, 'small']]): dz lifts or
    # lowers it so the windows need not all sit in one row (user 2026-11-09).
    def _win(w, zbase, dims):
        f, a, shut, glow, *rest = w
        dz = rest[0] if rest else 0.0
        d = DIM['window_small'] if len(rest) > 1 and rest[1] == 'small' else dims
        F.window(M, f, faces[f][0], a, zbase + dz, *d, shut, glow)

    for w in wins:
        _win(w, zc, DIM['window'])
    # a second storey (wins_up): the same windows, a floor higher, above the
    # mid rail that mid=True draws
    for w in wins_up:
        _win(w, zpl + (eave - zpl) * 0.5 + 0.30, DIM['window_up'])
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


# ═══ GOLD-STANDARD PARTS (the Hospital, approved 2026-11-09) ═══════════════
# See docs/building_gold_standard.md. Use these; do not hand-roll them.
import random
from pro_kit import plain, tex_mat


def vivid(M):
    """The city reference's palette, over the shared one."""
    M['roof'] = tex_mat('roof_v', 'clay_roof_tiles_02', 1.55, tint=(1.32, 0.76, 0.52),
                        sat=1.5, val=1.32, nstr=1.5, vary=0.05)
    M['roof2'] = tex_mat('roof2_v', 'clay_roof_tiles_02', 1.55, tint=(1.25, 0.72, 0.5),
                         sat=1.5, val=1.2, nstr=1.5, vary=0.05)
    M['plaster'] = tex_mat('plaster_v', 'white_plaster_rough_01', 1.0,
                           tint=(1.0, 0.94, 0.80), sat=0.22, val=2.2, rough=1.0,
                           nstr=0.9, vary=0.05)
    M['timber'] = tex_mat('timber_v', 'dark_wood', 0.8, tint=(0.9, 0.58, 0.38), sat=1.25,
                          val=0.9, nstr=0.8, vary=0.12)
    M['teal'] = plain('teal_v', '#1fa89c', rough=0.7, vary=0.08)
    M['red'] = plain('red_v', '#e0402a', rough=0.7, vary=0.08)
    M['leaf'] = plain('leaf_v', '#4fb01e', rough=0.7, bump=0.5, bump_scale=70, vary=0.2,
                      speck='#74c82e')
    M['leaf2'] = plain('leaf2_v', '#7cc934', rough=0.7, bump=0.5, bump_scale=70, vary=0.2,
                       speck='#a2da44')
    M['pine'] = plain('pine_v', '#2a8c3a', rough=0.8, bump=0.5, bump_scale=60, vary=0.15,
                      speck='#3aa24a')
    M['pine2'] = plain('pine2_v', '#46a838', rough=0.8, bump=0.5, bump_scale=60, vary=0.15,
                       speck='#62bd44')
    M['flag_w'] = plain('flag_w', '#fbf8f0', rough=0.95, bump=0.15, bump_scale=120, vary=0.03)
    M['flag_r'] = plain('flag_r', '#e32a2a', rough=0.85, bump=0.1, vary=0.04)
    return M



def herb_bed(M, x0, x1, y0, y1, seed):
    rnd = random.Random(seed)
    box((x0 + x1) / 2, (y0 + y1) / 2, G, x1 - x0, y1 - y0, 0.06, M['planks'], bevel=0.006)
    box((x0 + x1) / 2, (y0 + y1) / 2, G + 0.04, x1 - x0 - 0.05, y1 - y0 - 0.05, 0.03,
        M['soil'], bevel=0.004)
    with F.anim(f'herbs{x0:+.1f}{y0:+.1f}', 'sway', pivot=((x0 + x1) / 2, y0, G + 0.07),
                amp=0.12, period=3.3):
        n = int((x1 - x0) / 0.085)
        for i in range(n):
            for j in range(2):
                x = x0 + 0.06 + i * (x1 - x0 - 0.12) / max(1, n - 1)
                y = y0 + 0.06 + j * (y1 - y0 - 0.12)
                ellipsoid(x, y + rnd.uniform(-0.01, 0.01), G + 0.11, 0.032, 0.032,
                          0.045 + 0.02 * rnd.random(), M['leaf' if (i + j) % 2 else 'leaf2'],
                          seg=8, rings=5)
                if (i * 3 + j) % 5 == 0:
                    ellipsoid(x, y, G + 0.17, 0.016, 0.016, 0.016, M['fl_pink'], seg=6, rings=4)



def well(M, x, y, s=1.8):
    """The court's well; s scales it (user 2026-11-09: it looked too small)."""
    for k in range(8):
        a = k * math.pi / 4
        rbox((x + 0.08 * s * math.cos(a), y + 0.08 * s * math.sin(a), G + 0.05 * s),
             (0.07 * s, 0.04 * s, 0.1 * s), (0, 0, a + math.pi / 2), M['stone'], bevel=0.008)
    cyl(x, y, G + 0.065 * s, 0.07 * s, 0.07 * s, 0.012, M['water'], seg=14)   # a little below the rim (user 2026-11-09)
    for g in (-1, 1):
        beam((x + g * 0.09 * s, y, G), (x + g * 0.09 * s, y, G + 0.33 * s), 0.02 * s, M['timber'])
    beam((x - 0.09 * s, y, G + 0.30 * s), (x + 0.09 * s, y, G + 0.30 * s), 0.022 * s, M['timber'])
    # a GABLE roof (user 2026-11-09): two slabs meeting at a ridge over the beam
    th = 0.55
    for sg in (-1, 1):
        rbox((x, y + sg * 0.062 * s, G + 0.375 * s), (0.27 * s, 0.135 * s, 0.014 * s),
             (-th * sg, 0, 0), M['roof2'], bevel=0.004)
    rbox((x, y, G + 0.415 * s), (0.27 * s, 0.022 * s, 0.022 * s), (0, 0, 0), M['timber'], bevel=0.003)
    # the winch roller, its crank, the rope and the bucket to pull up
    zr = G + 0.245 * s
    beam((x - 0.09 * s, y, zr), (x + 0.09 * s, y, zr), 0.02 * s, M['timber'], bevel=0.004)
    beam((x + 0.09 * s, y, zr), (x + 0.12 * s, y + 0.045 * s, zr + 0.02 * s), 0.01 * s, M['iron'], bevel=0)
    zb = G + 0.12 * s                                    # bucket bottom, above the water
    bh = 0.075 * s
    cyl(x, y, zb, 0.034 * s, 0.042 * s, bh, M['planks'], seg=20)
    for fz in (0.2, 0.75):                               # whole proud rings, as on the barrels
        rr = (0.034 + 0.008 * fz) * s + 0.014
        cyl(x, y, zb + bh * fz - 0.016, rr, rr, 0.032, M['iron'], seg=20)
    beam((x - 0.042 * s, y, zb + bh), (x, y, zb + bh + 0.03 * s), 0.008 * s, M['iron'], bevel=0)
    beam((x + 0.042 * s, y, zb + bh), (x, y, zb + bh + 0.03 * s), 0.008 * s, M['iron'], bevel=0)
    beam((x, y, zb + bh + 0.03 * s), (x, y, zr), 0.008 * s, M['iron'], bevel=0)


def cross_flag(M, x, y, z0, h, w):
    """Pole with a white cloth carrying a red cross, facing south."""
    pt = 0.012 + 0.035 * w                  # a sturdier pole (user 2026-11-09)
    beam((x, y, z0), (x, y, z0 + h), pt, M['timber'], bevel=0.002)
    ellipsoid(x, y, z0 + h + 0.012, pt * 0.8, pt * 0.8, pt * 0.8, M['gold'], seg=8, rings=5)
    cw, ch = w, w * 1.25
    # the cloth is hung ON the pole by a top and a bottom rod, so it never floats
    cx, cz = x + cw / 2, z0 + h - ch / 2 - 0.02
    for rz in (z0 + h - 0.02, z0 + h - ch - 0.02):
        beam((x, y, rz), (x + cw, y, rz), 0.014, M['timber'], bevel=0.002)
    rbox((cx, y, cz), (cw, 0.012, ch), (0, 0, 0), M['flag_w'], bevel=0.002)
    rbox((cx, y - 0.02, cz), (cw * 0.26, 0.02, ch * 0.9), (0, 0, 0), M['flag_r'], bevel=0.001)
    rbox((cx, y - 0.02, cz + ch * 0.06), (cw * 0.9, 0.02, ch * 0.24), (0, 0, 0),
         M['flag_r'], bevel=0.001)
    # the same cross on the back, so no view shows a blank cloth
    rbox((cx, y + 0.02, cz), (cw * 0.26, 0.02, ch * 0.9), (0, 0, 0), M['flag_r'], bevel=0.001)
    rbox((cx, y + 0.02, cz + ch * 0.06), (cw * 0.9, 0.02, ch * 0.24), (0, 0, 0),
         M['flag_r'], bevel=0.001)



# ── lanterns: hang on a chain under a roof; each is its own wind group, and
#    their light is split over six materials so they flicker out of step ──
LAMP_KEYS = ['lampA', 'lampB', 'lampC', 'lampD', 'lampE', 'lampF']
# (kind, amp, period): weak flicker, a different rhythm each (user 2026-11-09)
LAMP_GLOW = {
    'lamp': ('flicker', 0.30, 1.0),
    'lampA': ('flicker', 0.22, 0.85), 'lampB': ('flicker', 0.34, 1.30),
    'lampC': ('flicker', 0.26, 1.05), 'lampD': ('flicker', 0.38, 0.70),
    'lampE': ('flicker', 0.24, 1.55), 'lampF': ('flicker', 0.32, 1.15),
}
_LAMPS = [0]


def lamp_mats(M):
    """Call once after the palette: the six emissive lantern materials."""
    for k in LAMP_KEYS:
        M[k] = plain(k, '#ffd07a', rough=0.3, bump=0.0, emit='#ffc060',
                     emit_strength=9.0, vary=0.0)


def reset_lamps():
    _LAMPS[0] = 0


def hang_lamp(M, x, y, z_under, key='lamp'):
    """A lantern on a short chain from the roof's UNDERSIDE, its top clear of the slab."""
    ztop = z_under - 0.015
    beam((x, y, ztop), (x, y, ztop - 0.09), 0.008, M['iron'], bevel=0)
    cyl(x, y, ztop - 0.105, 0.045, 0.028, 0.022, M['iron'], seg=8)             # cap
    box(x, y, ztop - 0.19, 0.07, 0.07, 0.085, M[key], bevel=0.004)             # the flame
    cyl(x, y, ztop - 0.208, 0.04, 0.04, 0.018, M['iron'], seg=8)               # base


def sway_lamp(M, x, y, z_under):
    """One lantern as its OWN swaying group, lit by one of six flicker materials."""
    i = _LAMPS[0]
    _LAMPS[0] += 1
    with F.anim(f'lamp{i}', 'sway', pivot=(x, y, z_under), amp=0.05 + 0.025 * ((i * 7) % 4),
                period=2.3 + 0.37 * ((i * 5) % 6)):
        hang_lamp(M, x, y, z_under, LAMP_KEYS[i % len(LAMP_KEYS)])


# ── ivy / moss, the outer wall and its gate ─────────────────────────────────
def ivy(M, x0, y0, x1, y1, inward, seed, top=0.26, density=0.2, skip=0.4):
    """Patchy ivy on a stretch of wall: small leaf clusters hanging from the cap
    on the `inward` face, moss on the cap. (x, y) run along the wall's centre line."""
    rnd = random.Random(seed)
    L = math.hypot(x1 - x0, y1 - y0)
    n = max(3, int(L / density))
    for i in range(n):
        if rnd.random() < skip:
            continue
        t = (i + rnd.uniform(0.1, 0.9)) / n
        px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        hang = rnd.uniform(0.05, 0.17)
        for k in range(rnd.randint(2, 4)):
            z = G + top - 0.01 - hang * k / 3
            r = rnd.uniform(0.026, 0.042)
            ellipsoid(px + inward[0] * 0.05 + rnd.uniform(-0.03, 0.03) * abs(inward[1]),
                      py + inward[1] * 0.05 + rnd.uniform(-0.03, 0.03) * abs(inward[0]),
                      z, r, r, r * 0.9, M['leaf2' if k % 2 else 'leaf'], seg=8, rings=6)
        if rnd.random() < 0.3:
            ellipsoid(px, py, G + top + 0.03, 0.04, 0.04, 0.014, M['leaf2'], seg=8, rings=5)


def wall_ivy(M, wx, wy, wn, gate=0.32, seed=1):
    """Ivy along the whole plot wall, both faces, patchy; clear of the gate."""
    sides = [(-wx + 0.15, wn, wx - 0.15, wn, (0, -1)),
             (-wx + 0.25, wy, -gate - 0.2, wy, (0, 1)), (gate + 0.2, wy, wx - 0.25, wy, (0, 1)),
             (-wx, wy + 0.25, -wx, wn - 0.25, (1, 0)), (wx, wy + 0.25, wx, wn - 0.25, (-1, 0))]
    for i, (x0, y0, x1, y1, inw) in enumerate(sides):
        ivy(M, x0, y0, x1, y1, inw, seed + i)                              # inner face
        ivy(M, x0, y0, x1, y1, (-inw[0], -inw[1]), seed + 20 + i)          # outer face


def plot_wall(M, wx, wy, wn, gate=0.32, wh=0.26):
    """The low outer wall on the plot's outer tile line: gate gap (+-gate) in the
    south, corner pillars, gate pillars. wx = east/west x, wy = south y, wn = north y."""
    for x0, x1 in ((-wx, -gate), (gate, wx)):
        box((x0 + x1) / 2, wy, G, x1 - x0, 0.1, wh, M['stone'], bevel=0.008)
        box((x0 + x1) / 2, wy, G + wh, x1 - x0 + 0.02, 0.13, 0.03, M['stone_dk'], bevel=0.005)
    box(0, wn, G, 2 * wx, 0.1, wh, M['stone'], bevel=0.008)
    box(0, wn, G + wh, 2 * wx + 0.02, 0.13, 0.03, M['stone_dk'], bevel=0.005)
    ym = (wy + wn) / 2
    for sx in (-1, 1):
        box(sx * wx, ym, G, 0.1, wn - wy, wh, M['stone'], bevel=0.008)
        box(sx * wx, ym, G + wh, 0.13, wn - wy + 0.02, 0.03, M['stone_dk'], bevel=0.005)
        for py in (wy, wn):                                       # corner pillars
            box(sx * wx, py, G, 0.15, 0.15, 0.42, M['stone'], bevel=0.01)
            box(sx * wx, py, G + 0.42, 0.19, 0.19, 0.04, M['stone_dk'], bevel=0.006)
        box(sx * gate, wy, G, 0.14, 0.14, 0.5, M['stone'], bevel=0.01)          # the gate pillars
        box(sx * gate, wy, G + 0.5, 0.18, 0.18, 0.04, M['stone_dk'], bevel=0.006)


def iron_gate(M, wy, half=0.25):
    """The entrance gate: wrought-iron grid, round on top, standing OPEN (nothing
    across the passage, monsters walk in); each leaf swung back along the wall
    inside, hinged at the pillar, its top an arc of radius `half`."""
    R, HS = half, 0.30

    def arc(u):
        return HS + math.sqrt(max(0.0, R * R - (R - u) ** 2))
    for sx in (-1, 1):
        lx = sx * (half - 0.025)
        ys = [wy + 0.0495 * k for k in range(int(R / 0.0495))] + [wy + R]
        for y in ys:                                          # bars, their tops on the arc
            beam((lx, y, G), (lx, y, G + arc(y - wy)), 0.017, M['iron'], bevel=0)
        for z in (0.04, 0.16):                                # bottom and middle rail
            beam((lx, wy, G + z), (lx, wy + R, G + z), 0.019, M['iron'], bevel=0)
        pts = [(wy + R * k / 8, arc(R * k / 8)) for k in range(9)]
        for (y0, z0), (y1, z1) in zip(pts, pts[1:]):          # the round top rail
            beam((lx, y0, G + z0), (lx, y1, G + z1), 0.021, M['iron'], bevel=0)
        for y, z in pts[1:-1:2]:                              # little scroll balls
            ellipsoid(lx, y, G + z + 0.012, 0.016, 0.016, 0.016, M['iron'], seg=8, rings=5)
