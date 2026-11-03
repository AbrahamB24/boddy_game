"""Fachwerk kit: the shared parts of every building in the Hatchery style.

Every building script in tool/blender/buildings/ builds its smooth model from
THESE parts, and make_building.py turns it into the shipped voxel art. Three
things are fixed here so that no building can drift from another:

  * SCALE. 1 tile = 5 m (the Hatchery's door is 0.40 tiles = 2.0 m). Use m()
    to author in metres; the DIM table holds the norm sizes of doors,
    windows, storeys and the plinth. A building that needs a door uses
    DIM['door'], never a number of its own.
  * MATERIALS. One palette for all (base_materials()); a building adds only
    what is its own (eggs, fish, meat).
  * VOXEL SIZE. VOX is one block's edge in tiles, the same for every
    building (see make_building.voxelize). The Remesh modifier's own depth is
    RELATIVE to the model's size, so at one fixed depth a 10x10 castle would
    come out in blocks 2.5x coarser than a 4x3 hatchery.

Coordinates: x east, y north, z up, in tiles, origin at the footprint's
centre. The camera looks from +x/-y, so the SOUTH ('s', normal -y) and EAST
('e', normal +x) faces are the ones a player sees. Authoring happens with the
yard at z = G (pro_kit's ground height); make_building lowers the whole
scene so the yard lands at z = 0 — the game draws buildings on its own map
ground, without plinth or turf (user 2026-11-03).
"""
import math
import random

from mathutils import Vector

from pro_kit import (G, beam, blade_mat, box, cyl, ellipsoid, plain, rbox,  # noqa: F401
                     strands, tex_mat, tri_prism, blob)
import pro_kit as K

# ── scale ───────────────────────────────────────────────────
TILE_M = 5.0                      # metres per tile


def m(metres):
    """Metres -> tiles."""
    return metres / TILE_M


# Norm sizes, in tiles (metres in the comment). Width x height.
DIM = {
    'door': (m(1.0), m(2.0)),           # 1.0 x 2.0 m house door
    'door_wide': (m(1.4), m(2.2)),      # double door, shop / inn
    'gate': (m(2.6), m(3.0)),           # barn / workshop / wagon gate
    'window': (m(0.85), m(1.1)),        # ground-floor window
    'window_up': (m(1.0), m(1.3)),      # upper-floor window
    'window_small': (m(0.6), m(0.8)),   # loft / gable / stair window
    'plinth': m(0.5),                   # stone base under the timber frame
    'storey': m(3.5),                   # floor-to-floor, joists included
    'timber': m(0.26),                  # post / rail section
    'jetty': m(0.35),                   # upper floor overhang
    'person': m(1.8),                   # the reference figure in lineup.py
}

# One voxel's edge, in tiles: the block size of the shipped Hatchery
# (Remesh depth 8 at scale 0.99 over its 4.1822-tile bounding box, the render
# that was approved on 2026-11-03). 0.0165 tiles = 8.3 cm.
VOX = 4.1822 / (0.99 * 256)

PITCH = 50.0                      # roof pitch, degrees
ROOF_THICK = 0.075                # tile slab thickness (gable_roof's default)
TP = math.tan(math.radians(PITCH))


# ── materials ───────────────────────────────────────────────
def base_materials():
    """The shared palette. Building scripts add their own keys to the dict."""
    M = {}
    M['plaster'] = tex_mat('plaster', 'white_plaster_rough_01', 1.0,
                           tint=(1.0, 0.90, 0.72), sat=0.30, val=2.05,
                           rough=1.0, nstr=0.9, vary=0.05)
    M['timber'] = tex_mat('timber', 'dark_wood', 0.8, tint=(0.95, 0.70, 0.52),
                          sat=1.0, val=0.95, nstr=0.8, vary=0.12)
    M['planks'] = tex_mat('planks', 'weathered_planks', 0.7,
                          tint=(1.7, 1.2, 0.8), sat=1.2, val=1.25, nstr=0.9)
    M['roof'] = tex_mat('roof', 'clay_roof_tiles_02', 1.55,
                        tint=(1.12, 0.92, 0.78), sat=1.05, val=1.15,
                        nstr=1.5, vary=0.05)
    M['roof2'] = tex_mat('roof2', 'clay_roof_tiles_02', 1.55,
                         tint=(1.0, 0.80, 0.70), sat=1.1, val=1.0,
                         nstr=1.5, vary=0.05)
    M['stone'] = tex_mat('stone', 'old_stone_wall', 1.2,
                         tint=(1.18, 1.04, 0.88), sat=0.9, val=1.2,
                         nstr=1.2, vary=0.06)
    M['stone_dk'] = tex_mat('stone_dk', 'old_stone_wall', 1.2,
                            tint=(0.95, 0.85, 0.74), sat=0.9, val=0.95,
                            nstr=1.2, vary=0.10)
    M['cobble'] = plain('cobble', '#d2c4a6', rough=0.85, bump=0.55,
                        bump_scale=40, vary=0.14, speck='#a89878')
    M['grass'] = tex_mat('grass', 'leafy_grass', 1.4, tint=(0.88, 1.12, 0.45),
                         sat=1.7, val=1.1, nstr=0.7, vary=0.04)
    M['dirt'] = tex_mat('dirt', 'park_dirt', 1.2, tint=(1.05, 0.88, 0.62),
                        sat=1.0, val=0.95, nstr=0.8, vary=0.08)
    M['soil'] = tex_mat('soil', 'park_dirt', 1.0, tint=(0.75, 0.55, 0.38),
                        sat=1.0, val=0.7, nstr=1.0, vary=0.04)
    M['hay'] = tex_mat('hay', 'reed_roof_03', 0.55, tint=(1.55, 1.2, 0.62),
                       sat=1.3, val=1.4, nstr=1.0, vary=0.10)
    M['straw'] = plain('straw', '#e2b956', rough=0.85, bump=0.0, vary=0.18)
    M['straw_dk'] = plain('straw_dk', '#b8862f', rough=0.9, bump=0.0, vary=0.2)
    M['iron'] = plain('iron', '#3a3633', rough=0.5, metal=1.0, bump=0.05)
    M['gold'] = plain('gold', '#f2b632', rough=0.28, metal=1.0, bump=0.0)
    M['linen'] = plain('linen', '#ecd9ae', rough=0.95, bump=0.25,
                       bump_scale=120, vary=0.05)
    M['awning'] = plain('awning', '#e6cf9e', rough=0.95, bump=0.3,
                        bump_scale=140, vary=0.04)
    M['sack'] = plain('sack', '#c9ac78', rough=0.95, bump=0.35,
                      bump_scale=90, vary=0.12)
    M['leaf'] = plain('leaf', '#4f8a24', rough=0.7, bump=0.5, bump_scale=70,
                      vary=0.2, speck='#6a9a2a')
    M['leaf2'] = plain('leaf2', '#6a9a2a', rough=0.7, bump=0.5, bump_scale=70,
                       vary=0.2, speck='#8aa636')
    M['stem'] = plain('stem', '#4f7a22', rough=0.8, bump=0.0)
    M['teal'] = plain('teal', '#3c7d78', rough=0.7, vary=0.1)
    M['red'] = plain('red', '#a8402c', rough=0.7, vary=0.1)
    M['mustard'] = plain('mustard', '#d09a2a', rough=0.7, vary=0.1)
    M['pane'] = plain('pane', '#15232a', rough=0.12, bump=0.0, vary=0.0)
    M['pane_glow'] = plain('pane_glow', '#ffb14a', rough=0.4, bump=0.0,
                           emit='#ff9a2e', emit_strength=3.0, vary=0.0)
    M['lamp'] = plain('lamp', '#ffd07a', rough=0.3, bump=0.0, emit='#ffc060',
                      emit_strength=9.0, vary=0.0)
    M['blade'] = blade_mat('blade', '#3e6f1b', '#c4cf45')
    M['blade2'] = blade_mat('blade2', '#4f8420', '#e0d654')
    for k, c in {'fl_red': '#d8352c', 'fl_blue': '#4b6fd8', 'fl_white': '#f4f0e6',
                 'fl_pink': '#e982b4', 'fl_yel': '#f2cf3a'}.items():
        M[k] = plain(k, c, rough=0.6, bump=0.0, vary=0.1)
    return M


# ── face helpers ────────────────────────────────────────────
# ALL FOUR SIDES are modelled (user 2026-11-03: "alle Seiten gleich
# modelliert, damit später Drehungen möglich sein würden"): 's' south
# (normal -y), 'n' north (+y), 'e' east (+x), 'w' west (-x). `fixed` is the
# wall plane's y (s, n) or x (e, w); `a` runs along the wall.
OUT = {'s': (0, -1), 'n': (0, 1), 'e': (1, 0), 'w': (-1, 0)}


def P(face, fixed, a, z, off=0.0):
    """A point on a wall: `a` runs along it, `off` pushes it outward."""
    ox, oy = OUT[face]
    if face in ('s', 'n'):
        return Vector((a, fixed + oy * off, z))
    return Vector((fixed + ox * off, a, z))


def D(face, along, depth, h):
    """Box dimensions for something lying flat on a wall."""
    return (along, depth, h) if face in ('s', 'n') else (depth, along, h)


def wall_frame(M, face, fixed, a0, a1, z0, z1, nb, braces=(), t=0.052,
               mid=False, holes=()):
    """The half-timber: sill, plate, posts and diagonal braces on one wall.

    holes = [(a, w)] - openings (windows, doors) on this wall. Posts, braces
    and the mid rail keep out of them, so no timber ever crosses a pane.
    Rails stop at the outer post's centre and posts stop at the rails'
    centres, so no two end faces sit coplanar (that z-fights as black squares).
    """
    xs = [a0 + (a1 - a0) * i / nb for i in range(nb + 1)]
    off = 0.012
    spans = [(a - (w / 2 + w * 0.36 + 0.02), a + (w / 2 + w * 0.36 + 0.02))
             for a, w in holes]
    pspans = [(a - (w / 2 + 0.03), a + (w / 2 + 0.03)) for a, w in holes]

    def hit(lo, hi):
        return any(hi > l and lo < h for l, h in spans)
    beam(P(face, fixed, a0, z0 + t / 2, off),
         P(face, fixed, a1, z0 + t / 2, off), t, M['timber'])
    beam(P(face, fixed, a0, z1 - t / 2, off),
         P(face, fixed, a1, z1 - t / 2, off), t, M['timber'])
    if mid:
        zm = (z0 + z1) / 2
        segs = []
        cur = a0
        for l, h in sorted(spans):
            if l > cur + 0.05:
                segs.append((cur, min(l, a1)))
            cur = max(cur, h)
        if a1 > cur + 0.05:
            segs.append((cur, a1))
        # A rail runs from post to post: snapped inward to the nearest posts
        # left standing, so it never stops in the middle of a plaster panel
        # (beside a door it did, user 2026-11-03).
        posts = [a for i, a in enumerate(xs)
                 if not (any(l < a < h for l, h in pspans) and 0 < i < nb)]
        for l, h in segs:
            inside = [a for a in posts if l - 1e-6 <= a <= h + 1e-6]
            if len(inside) < 2:
                continue
            beam(P(face, fixed, inside[0], zm, off),
                 P(face, fixed, inside[-1], zm, off), t * 0.85, M['timber'])
    for i, a in enumerate(xs):
        if any(l < a < h for l, h in pspans) and 0 < i < nb:
            continue
        beam(P(face, fixed, a, z0 + t / 2, off),
             P(face, fixed, a, z1 - t / 2, off), t, M['timber'])
    for i in braces:
        if hit(xs[i], xs[i + 1]):
            continue
        sgn = 1 if i % 2 == 0 else -1
        pa = P(face, fixed, xs[i], z0 + t / 2 if sgn > 0 else z1 - t / 2, off * 0.6)
        pb = P(face, fixed, xs[i + 1], z1 - t / 2 if sgn > 0 else z0 + t / 2, off * 0.6)
        beam(pa, pb, t * 0.8, M['timber'])
    return xs


def window(M, face, fixed, a, zc, w, h, shut='teal', glow=False, planter=None):
    """A framed window with a cross bar, stone sill, shutters, flower box."""
    t = 0.034
    off = 0.010
    pane = M['pane_glow'] if glow else M['pane']
    rbox(P(face, fixed, a, zc, 0.002), D(face, w, 0.012, h), (0, 0, 0), pane)
    for da in (-w / 2, w / 2):
        beam(P(face, fixed, a + da, zc - h / 2, off),
             P(face, fixed, a + da, zc + h / 2, off), t, M['timber'])
    for dz in (-h / 2, h / 2):
        beam(P(face, fixed, a - w / 2, zc + dz, off),
             P(face, fixed, a + w / 2, zc + dz, off), t, M['timber'])
    beam(P(face, fixed, a, zc - h / 2, off), P(face, fixed, a, zc + h / 2, off),
         0.016, M['timber'])
    beam(P(face, fixed, a - w / 2, zc, off), P(face, fixed, a + w / 2, zc, off),
         0.016, M['timber'])
    sill = P(face, fixed, a, zc - h / 2 - 0.02, 0.03)
    rbox(sill, D(face, w + 0.1, 0.07, 0.03), (0, 0, 0), M['stone'])
    if shut:
        sw = w * 0.36
        for sgn in (-1, 1):
            c = P(face, fixed, a + sgn * (w / 2 + sw / 2 + 0.03), zc, 0.03)
            d = D(face, sw, 0.02, h)
            box(c.x, c.y, c.z - h / 2, d[0], d[1], d[2], M[shut], bevel=0.003)
    if planter:
        c = P(face, fixed, a, zc - h / 2 - 0.075, 0.07)
        rbox(c, D(face, w + 0.04, 0.07, 0.06), (0, 0, 0), M['planks'])
        flowers(face, fixed, a, zc - h / 2 - 0.04, w, planter)


def _flowers(face, fixed, a, z, w, cols):
    rnd = random.Random(int(a * 977) + 3)
    for i in range(7):
        aa = a + (i / 6 - 0.5) * w * 0.9
        p = P(face, fixed, aa, z, 0.07 + rnd.uniform(-0.01, 0.01))
        h = rnd.uniform(0.04, 0.08)
        beam(p, p + Vector((0, 0, h)), 0.006, K._mats['stem'], bevel=0)
        ellipsoid(p.x, p.y, p.z + h, 0.017, 0.017, 0.014,
                  K._mats[rnd.choice(cols)], seg=8, rings=6)
        ellipsoid(p.x, p.y, p.z + 0.02, 0.03, 0.03, 0.03, K._mats['leaf'],
                  seg=8, rings=6)


def door(M, face, fixed, a, w, h, z0):
    """A plank door in a timber case, iron straps, ring handle, stone step."""
    # Every layer stands at least ~1.5 voxels proud of the one behind it:
    # the voxeliser gives each block the material of the NEAREST surface, and
    # a door leaf 5 mm in front of the plaster came out as a patchwork of both.
    t = 0.04
    off = 0.016
    rbox(P(face, fixed, a, z0 + h / 2, 0.006), D(face, w, 0.04, h), (0, 0, 0),
         M['planks'])
    for da in (-w / 2 - t / 2, w / 2 + t / 2):
        beam(P(face, fixed, a + da, z0, off), P(face, fixed, a + da, z0 + h + t / 2, off),
             t, M['timber'])
    beam(P(face, fixed, a - w / 2 - t / 2, z0 + h + t / 2, off),
         P(face, fixed, a + w / 2 + t / 2, z0 + h + t / 2, off), t * 1.1, M['timber'])
    for fz in (0.2, 0.75):
        beam(P(face, fixed, a - w / 2, z0 + h * fz, 0.03),
             P(face, fixed, a + w / 2, z0 + h * fz, 0.03), 0.02, M['iron'],
             bevel=0)
    c = P(face, fixed, a + w * 0.3, z0 + h * 0.5, 0.034)
    ellipsoid(c.x, c.y, c.z, 0.012, 0.012, 0.012, M['iron'], seg=8, rings=6)
    rbox(P(face, fixed, a, z0 - 0.012, 0.09), D(face, w + 0.2, 0.18, 0.045),
         (0, 0, 0), M['stone'])


# ── roofs ────────────────────────────────────────────────────
def gable_roof(M, cx, cy, z0, length, span, axis, mat, oh=0.15, oe=0.16,
               thick=0.075, pitch=PITCH):
    """Two tile slabs meeting at a ridge. z0 = eave height of the WALL top.
    axis = the ridge's direction ('x' or 'y'). Returns the ridge height.

    The slabs SIT ON the walls: their underside runs through the wall top's
    outer edge, so the tiles are one roof-thickness above the plaster. Laid
    with their TOP on that edge (as before 2026-11-03) the wall's top corner
    poked through every eave and voxelised as a pale streak along the roof."""
    tp = math.tan(math.radians(pitch))
    s = span / 2.0
    rise = s * tp
    zr = z0 + rise + thick / math.cos(math.radians(pitch))
    reach = s + oh
    slope = reach / math.cos(math.radians(pitch))
    d = reach / 2.0
    p = math.radians(pitch)
    for sgn in (-1, 1):
        top_c = (zr - d * tp)
        nz, nh = math.cos(p), math.sin(p)
        cz = top_c - thick / 2 * nz
        off = d * sgn - thick / 2 * nh * sgn
        if axis == 'x':
            c = (cx, cy + off, cz)
            eul = (-p * sgn, 0, 0)
            dims = (length + 2 * oe, slope + 0.02, thick)
        else:
            c = (cx + off, cy, cz)
            eul = (0, p * sgn, 0)
            dims = (slope + 0.02, length + 2 * oe, thick)
        rbox(c, dims, eul, mat, bevel=0.012)
    if axis == 'x':
        rbox((cx, cy, zr + 0.012), (length + 2 * oe, 0.1, 0.1),
             (math.radians(45), 0, 0), M['roof2'], bevel=0.01)
    else:
        rbox((cx, cy, zr + 0.012), (0.1, length + 2 * oe, 0.1),
             (0, math.radians(45), 0), M['roof2'], bevel=0.01)
    return zr


def gable_fill(M, face, fixed, a0, a1, z_base, pitch=PITCH, depth=0.07,
               mat='plaster'):
    """The plain plaster triangle of a gable, its sloped edges SUNK a little
    under the roof's top surface. gable_roof lays the tiles' top exactly on
    the triangle's edge, and two coincident faces voxelise as a streak of
    plaster across the roof. Every face builds INWARD from its wall plane."""
    tp = math.tan(math.radians(pitch))
    mid, half = (a0 + a1) / 2, (a1 - a0) / 2
    # up INTO the roof slab (which sits a thickness above the wall line, see
    # gable_roof), but short of its top
    sink = 0.04
    lift = ROOF_THICK / math.cos(math.radians(pitch))
    pts = ((a0, z_base), (a1, z_base), (mid, z_base + half * tp + lift - sink))
    if face == 's':
        tri_prism(*pts, fixed, fixed + depth, M[mat], axis='x')
    elif face == 'n':
        tri_prism(*pts, fixed - depth, fixed, M[mat], axis='x')
    elif face == 'w':
        tri_prism(*pts, fixed, fixed + depth, M[mat], axis='y')
    else:
        tri_prism(*pts, fixed - depth, fixed, M[mat], axis='y')


def gable_wall(M, face, fixed, a0, a1, z_base, pitch=PITCH, depth=0.07,
               king=True, emblem_z=None):
    """The plaster triangle of a gable end on any face, with its king
    post and two rafter braces. Returns the apex height."""
    tp = math.tan(math.radians(pitch))
    mid, half = (a0 + a1) / 2, (a1 - a0) / 2
    rise = half * tp
    gable_fill(M, face, fixed, a0, a1, z_base, pitch, depth)
    if king:
        # A real gable frame (user 2026-11-03: "Balken, welche ins Nichts
        # führen"): two RAFTERS from the apex down into both corners, where
        # they sit on the wall plate; a COLLAR beam between them; and the
        # KING POST standing on the collar up to the apex. The rafters lie
        # just under the tiles — gable_roof lifts the slab a full thickness
        # above this edge, so they cannot poke through it any more.
        apex = z_base + rise
        t = 0.045
        dz = t / 2 + 0.004                   # rafter top flush under the slab
        top = apex - dz / math.cos(math.radians(pitch))
        for sgn in (-1, 1):
            beam(P(face, fixed, mid, top, 0.012),
                 P(face, fixed, mid + sgn * half, z_base, 0.012), t,
                 M['timber'])
        zc = z_base + rise * 0.45
        reach = (top - zc) / tp               # rafter half-width at the collar
        beam(P(face, fixed, mid - reach, zc, 0.014),
             P(face, fixed, mid + reach, zc, 0.014), 0.04, M['timber'])
        beam(P(face, fixed, mid, zc, 0.012), P(face, fixed, mid, top, 0.012),
             0.05, M['timber'])
    return z_base + rise


def chimney(M, x, y, z_top_of_roof_base, h=0.62):
    box(x, y, z_top_of_roof_base, 0.22, 0.22, h, M['stone'], bevel=0.01)
    box(x, y, z_top_of_roof_base + h - 0.02, 0.28, 0.28, 0.05, M['stone_dk'],
        bevel=0.008)
    for dx in (-0.05, 0.05):
        cyl(x + dx, y, z_top_of_roof_base + h + 0.03, 0.036, 0.03, 0.1, M['roof2'],
            seg=12)


# ── the guild sign: what makes the purpose readable at a glance ──
def hanging_sign(M, face, fixed, a, z, emblem, size=m(1.4), reach=None,
                 board='planks'):
    """A wrought bracket out of the wall with a board hanging from it.

    emblem(center: Vector, size, normal_off) draws the symbol on the board's
    outer face; it is the building's trade mark (an egg, a fish, a ham) and
    must read as a SILHOUETTE at map scale, so keep it big and in one
    contrasting material. size is the board's width; it is ~1.4 m, larger
    than a real sign, because at 5 m a tile a real one is two voxels wide.
    """
    reach = reach or size * 1.25
    off = 0.02
    sgn = 1
    tip = a + sgn * reach
    beam(P(face, fixed, a, z, off), P(face, fixed, tip, z, off), 0.03, M['timber'])
    beam(P(face, fixed, a, z - reach * 0.6, off),
         P(face, fixed, a + sgn * reach * 0.7, z - 0.01, off), 0.022, M['timber'])
    ca = a + sgn * reach * 0.55
    bh = size * 0.8
    for da in (-size * 0.3, size * 0.3):
        beam(P(face, fixed, ca + da, z, off), P(face, fixed, ca + da, z - 0.06, off),
             0.008, M['iron'], bevel=0)
    c = P(face, fixed, ca, z - 0.06 - bh / 2, off)
    rbox(c, D(face, size, 0.025, bh), (0, 0, 0), M[board])
    emblem(P(face, fixed, ca, z - 0.06 - bh / 2, off + 0.02), size)


# ── yard props ───────────────────────────────────────────────
def barrel(M, x, y, r=0.085, h=0.2, z=None):
    z0 = G if z is None else z
    cyl(x, y, z0, r * 0.88, r, h * 0.5, M['planks'], seg=16)
    cyl(x, y, z0 + h * 0.5, r, r * 0.88, h * 0.5, M['planks'], seg=16)
    for fz in (0.14, 0.5, 0.86):
        rr = r * (0.88 + 0.12 * (1 - abs(fz - 0.5) * 2))
        cyl(x, y, z0 + h * fz - 0.008, rr + 0.004, rr + 0.004, 0.016, M['iron'],
            seg=16)
    cyl(x, y, z0 + h - 0.002, r * 0.86, r * 0.86, 0.006, M['timber'], seg=16)


def sack(M, x, y, s=1.0, rot=0.0, key='sack'):
    ellipsoid(x, y, G + 0.07 * s, 0.075 * s, 0.062 * s, 0.085 * s, M[key], egg=0.35,
              tilt=(0, 0, rot))
    ellipsoid(x, y, G + 0.152 * s, 0.026 * s, 0.026 * s, 0.022 * s, M[key], seg=10,
              rings=6)


def crate(M, x, y, s=0.14, rot=0.0, z=None):
    z0 = G if z is None else z
    rbox((x, y, z0 + s / 2), (s, s, s), (0, 0, rot), M['planks'], bevel=0.008)
    for sg in (-1, 1):
        rbox((x, y, z0 + s / 2), (s + 0.01, 0.014, s + 0.01), (0, 0, rot),
             M['timber'], bevel=0.003)


def hay_bale(M, x, y, z, sx, sy, sz, rot=0.0):
    rbox((x, y, z + sz / 2), (sx, sy, sz), (0, 0, rot), M['hay'], bevel=0.02)
    for f in (-0.28, 0.28):
        c = Vector((f * sx, 0, 0))
        c = Vector((x + c.x * math.cos(rot), y + c.x * math.sin(rot), z + sz / 2))
        rbox(c, (0.014, sy + 0.012, sz + 0.012), (0, 0, rot), M['iron'], bevel=0)


def hay_scatter(M, cx, cy, r, n, seed=1):
    rnd = random.Random(seed)
    lst = []
    for _ in range(n):
        a = rnd.uniform(0, 6.28)
        d = r * math.sqrt(rnd.random())
        p = Vector((cx + math.cos(a) * d, cy + math.sin(a) * d, G + 0.004))
        b = rnd.uniform(0, 6.28)
        L = rnd.uniform(0.05, 0.11)
        q = p + Vector((math.cos(b) * L, math.sin(b) * L, rnd.uniform(0, 0.018)))
        lst.append((p, q, 0.006))
    strands(lst, M['straw'], 'hayscatter')


def _bush(M, x, y, r=0.22, seed=0, flowers_cols=None):
    rnd = random.Random(seed)
    for i in range(6):
        a = rnd.uniform(0, 6.28)
        d = rnd.uniform(0, r * 0.7)
        rr = r * rnd.uniform(0.5, 0.85)
        ellipsoid(x + math.cos(a) * d, y + math.sin(a) * d, G + rr * 0.75,
                  rr, rr, rr * 0.85, M['leaf'] if i % 2 else M['leaf2'], seg=14,
                  rings=10)
    if flowers_cols:
        for i in range(10):
            a = rnd.uniform(0, 6.28)
            d = rnd.uniform(0.3, 1.0) * r
            ellipsoid(x + math.cos(a) * d, y + math.sin(a) * d,
                      G + rnd.uniform(0.12, 0.3), 0.022, 0.022, 0.02,
                      M[rnd.choice(flowers_cols)], seg=8, rings=6)


def _flower_patch(M, cx, cy, n, cols, seed, rx=0.18, ry=0.12):
    rnd = random.Random(seed)
    for _ in range(n):
        x = cx + rnd.uniform(-rx, rx)
        y = cy + rnd.uniform(-ry, ry)
        h = rnd.uniform(0.05, 0.11)
        beam((x, y, G), (x, y, G + h), 0.006, M['stem'], bevel=0)
        ellipsoid(x, y, G + h, 0.02, 0.02, 0.016, M[rnd.choice(cols)], seg=8,
                  rings=6)


def cobble_path(M, pts, seed=5, width=0.27):
    """Rounded cobbles along a polyline [(x, y), ...] at yard level."""
    rnd = random.Random(seed)
    half = width / 2
    for i in range(len(pts) - 1):
        a, b = Vector(pts[i] + (0,)), Vector(pts[i + 1] + (0,))
        L = (b - a).length
        n = int(L / 0.115) + 1
        dirv = (b - a).normalized()
        nrm = Vector((-dirv.y, dirv.x, 0))
        for k in range(n + 1):
            for side in (-half, 0.0, half):
                p = a + dirv * (L * k / max(n, 1)) + nrm * (side + rnd.uniform(-0.03, 0.03))
                p += dirv * rnd.uniform(-0.03, 0.03)
                sx = rnd.uniform(0.085, 0.135)
                sy = rnd.uniform(0.085, 0.125)
                ellipsoid(p.x, p.y, G + 0.004, sx * 0.62, sy * 0.62, 0.03,
                          M['cobble'], seg=12, rings=7,
                          tilt=(0, 0, rnd.uniform(0, 3.14)))


def lantern(M, face, fixed, a, z):
    beam(P(face, fixed, a, z + 0.05, 0.012), P(face, fixed, a, z + 0.05, 0.075),
         0.014, M['iron'], bevel=0)
    c = P(face, fixed, a, z, 0.085)
    ellipsoid(c.x, c.y, c.z, 0.026, 0.026, 0.04, M['lamp'], seg=10, rings=8)


def person(M, x, y, rot=0.0):
    """A 1.8 m reference figure (lineup checks only, never in a building)."""
    h = DIM['person']
    if 'skin' not in M:
        M['skin'] = plain('skin', '#d9a47a', rough=0.6, bump=0.0)
        M['cloth'] = plain('cloth', '#3d5f8f', rough=0.9, bump=0.0)
    cyl(x, y, G, 0.035, 0.03, h * 0.5, M['cloth'], seg=10)
    cyl(x, y, G + h * 0.5, 0.045, 0.04, h * 0.36, M['cloth'], seg=10)
    ellipsoid(x, y, G + h * 0.93, 0.024, 0.024, 0.03, M['skin'], seg=10, rings=8)


# ── moving parts (user 2026-11-03: "Kleider wiegen sich im Wind, Blumen
#    wanken, Licht flackert von einer Kerze") ──────────────────────────────
# Everything built inside `with anim(...)` becomes ONE moving layer: it is
# voxelised on its own, cut out of the map's base picture and drawn by the app
# leaning about `pivot` (AnimatedBuildingArt). The pivot is in authoring
# coordinates (yard at z = G): the line a hanging thing hangs from, the ground
# a plant grows out of.
#
# Kinds and their defaults (amp, period in seconds):
#   'sway'  washing, flowers, bushes, a cat's tail: shear about the pivot
#   'bob'   something floating: up and down
# Light needs no group: every emissive material becomes a glow/flicker layer
# by itself (see GLOW_LAYERS in make_building.py).
ANIMS = []
_ANIM_DEFAULTS = {'sway': (0.10, 2.8), 'bob': (0.006, 3.0)}


class anim:
    def __init__(self, name, kind='sway', pivot=(0, 0, 0), amp=None,
                 period=None):
        a, p = _ANIM_DEFAULTS[kind]
        self.spec = dict(name=name, kind=kind, pivot=tuple(pivot),
                         amp=a if amp is None else amp,
                         period=p if period is None else period)

    def __enter__(self):
        import bpy
        self._before = set(bpy.data.objects)
        return self

    def __exit__(self, *exc):
        import bpy
        new = [o for o in bpy.data.objects if o not in self._before]
        for o in new:
            o['anim'] = self.spec['name']
        if new:
            ANIMS.append(self.spec)
        return False


def reset_anims():
    ANIMS.clear()


# ── the entrance (user 2026-11-03) ──────────────────────────
# One whole footprint cell on the edge, where the building's path meets the
# road. ENTRANCE = (face, k): the k-th cell along that face, counted in the
# direction of increasing x (faces s, n) or y (faces e, w).
def entrance_point(W, H, face, k):
    """The middle of the entrance cell's OUTER edge — where the path ends."""
    if face == 's':
        return (-W / 2 + k + 0.5, -H / 2)
    if face == 'n':
        return (-W / 2 + k + 0.5, H / 2)
    if face == 'e':
        return (W / 2, -H / 2 + k + 0.5)
    return (-W / 2, -H / 2 + k + 0.5)


def entrance_grid(W, H, face, k):
    """(cx, cy, dx, dy) for kBuildingEntrance. Grid x = Blender x, but grid y
    runs the other way: Blender SOUTH (-y) is the grid's +y side (the map's
    lower-left edge, the one facing the camera)."""
    if face == 's':
        return (k, H - 1, 0, 1)
    if face == 'n':
        return (k, 0, 0, -1)
    if face == 'e':
        return (W - 1, H - 1 - k, 1, 0)
    return (0, H - 1 - k, -1, 0)


# ── plants move by themselves ───────────────────────────────
# Every flower box, flower patch and bush is its own swaying layer, rooted
# where it grows. On a face the camera does not see the layer comes out empty
# and anim_pass drops it, so the hidden sides cost nothing.
def flowers(face, fixed, a, z, w, cols):
    p = P(face, fixed, a, z, 0.07)
    with anim(f'box_{face}{fixed:+.2f}{a:+.2f}{z:.2f}', 'sway',
              pivot=(p.x, p.y, z), amp=0.25, period=3.1):
        _flowers(face, fixed, a, z, w, cols)


def bush(M, x, y, r=0.22, seed=0, flowers_cols=None):
    with anim(f'bush{x:+.2f}{y:+.2f}', 'sway', pivot=(x, y, G), amp=0.06,
              period=4.4):
        _bush(M, x, y, r, seed, flowers_cols)


def flower_patch(M, cx, cy, n, cols, seed, rx=0.18, ry=0.12):
    with anim(f'patch{cx:+.2f}{cy:+.2f}', 'sway', pivot=(cx, cy, G),
              amp=0.25, period=3.4):
        _flower_patch(M, cx, cy, n, cols, seed, rx, ry)
