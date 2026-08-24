"""Glimmergnaw — a monster rendered in the building kit's own low-poly style.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background `
        --python tool/blender/render_monster.py -- `
        --preset glimmergnaw_s1 --out docs/renders/glimmergnaw_s1.png

── Why Blender, when every other monster in this game is a flat AI-drawn
   sprite (see docs/monster_art_prompt.md) ──
No image-generation tool is available in this environment, and the user
asked for this one specifically as a "Renderdatei" — a rendered file, the
building kit's own word for what it produces. So Glimmergnaw is built the
way a BUILDING is: procedural low-poly geometry, the same palette-and-facet
discipline, photographed by the same orthographic rig. It will not look
like the other (2D, hand-drawn-style) monsters — that mismatch is a known,
accepted trade the user chose over not being able to produce this at all.

Reused wholesale from render_building.py rather than reinvented: box(),
orb() (the faceted icosphere — a body and a head read far better built from
these than from boxes), spire() (a crystal shard is just a very short,
very angular version of the same cone a tower's roof already is), cyl(),
mat()/glow_mat()/PALETTE, and the whole clear()/vary_tones()/
bevel_everything()/light()/frame() scene pipeline — a monster's photograph
should look like it was taken with the same camera as the buildings it
shares a map with.

Reference: OneDrive Bøddy/BøddyQuest/Assets/Monster/Glimmergnaw — six
concept images, roughly three evolution stages (a chubby sitting rodent
with a shoulder crystal cluster; a bipedal bear-ish adolescent with a
chest crystal plate and a small head-crown; a huge maned, clawed final
form) each haloed in the same warm amber glow. Stage 1 is the only one
built so far — see the module docstring above main() for the plan on 2/3.
"""
import bpy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_building as rb  # noqa: E402

box = rb.box
orb = rb.orb
cyl = rb.cyl
spire = rb.spire
mat = rb.mat
glow_mat = rb.glow_mat
PALETTE = rb.PALETTE

# ── Glimmergnaw's own palette: one warm fur hue in four steps (the same
# "four to six tones out of one hue" discipline the file's own PALETTE
# comment already sets aside for monsters), one warm tan for the paws/
# snout/inner-ear, and one amber for the crystal — lit, not painted, via
# glow_mat so it is the one genuinely emissive thing on the model, same as
# a lit window is the one emissive thing on a building. ──
PALETTE.setdefault('gnaw_fur', (0.40, 0.25, 0.15))
PALETTE.setdefault('gnaw_fur_light', (0.56, 0.38, 0.24))
PALETTE.setdefault('gnaw_fur_dark', (0.24, 0.14, 0.08))
PALETTE.setdefault('gnaw_paw', (0.72, 0.47, 0.28))
PALETTE.setdefault('gnaw_crystal', (1.0, 0.72, 0.22))


def shard(name, x, y, z, r, h, tilt=(0.0, 0.0, 0.0), sides=5):
    """One angular crystal spike: a single-ring spire (a plain N-sided
    cone), tilted, in the emissive amber. rings=1 is the whole trick — the
    normal spire() rings up smoothly toward a point over many segments,
    which reads as round; one segment, flat-shaded, is a gem facet."""
    spire(name, x, y, z, r, h, sides=sides, rings=1, key='gnaw_glow',
          dark='gnaw_glow')
    ob = bpy.data.objects.get(f'{name}_0')
    if ob is not None:
        ob.rotation_euler = tilt
    return ob


def glimmergnaw_stage1():
    """Stage 1 — the reference's sitting, cheek-pouched rodent: round,
    low, harmless, one shoulder crystal cluster. Built facing -y (the
    camera's own front), the same convention every building in this kit
    faces.
    """
    glow_mat('gnaw_glow', PALETTE['gnaw_crystal'], strength=3.2)

    # ── THE BODY: round and upright, SITTING — not the stretched log the
    # first pass came out as (user 2026-08-23, side by side with the
    # reference: "ich sehe noch sehr viele Unterschiede. Bitte 1:1 so
    # umsetzen"). The reference reads as one compact rounded mass with the
    # head riding high on top of it, not a ball-head bolted to a long low
    # barrel — so bd shrinks toward bw/bh instead of dominating them. ──
    bw, bd, bh = 0.76, 0.70, 0.66
    orb('gnbody', 0, 0.04, 0, bw, bd, bh, key='gnaw_fur', subdiv=1)
    orb('gnbelly', 0, -0.06, 0, bw * 0.86, bd * 0.66, bh * 0.62,
        key='gnaw_fur_light', subdiv=1)

    # ── THE HEAD: riding high on the body, only just forward of it — no
    # neck, and this time no GAP either. Raised and pulled back in close
    # (was hz=0.13, hy=-0.60; the low, far-forward head is what made the
    # first pass read as lying down instead of sitting up). ──
    hx, hy, hz = 0.0, -0.42, 0.26
    hr = 0.46
    orb('gnhead', hx, hy, hz, hr, hr * 0.98, hr * 0.94, key='gnaw_fur',
        subdiv=1)

    # ── THE SNOUT: a smaller, paler, forward-pushed orb ──
    # ── Offsets stay SMALL here on purpose ──
    # This camera's screen-x is driven by (world x + world y) together (the
    # same 45°-rotated-iso relationship the castle's own gate towers were
    # measured against) — an x offset and a y offset in the SAME direction
    # do not partially cancel the way they would head-on, they ADD. A
    # 0.2/0.28 offset that looked like a modest "just in front of the head"
    # nudge in plan view threw the eye a third of the head's own width
    # sideways on screen. Every offset below was cut once, empirically,
    # against exactly that.
    sx, sy, sz = hx, hy - 0.17, hz + 0.02
    orb('gnsnout', sx, sy, sz, 0.23, 0.24, 0.19, key='gnaw_paw', subdiv=1)
    box('gnnose', sx, sy - 0.125, sz + 0.12, 0.055, 0.022, 0.045, mat('dark'))

    # ── THE TEETH: two small crystal wedges under the snout — the
    # signature that says GNAW, not just RODENT ──
    for s in (-1, 1):
        shard(f'gntooth{s}', sx + s * 0.04, sy - 0.06, sz - 0.05, 0.024,
              0.09, tilt=(0.2, 0, s * 0.06), sides=4)

    # ── THE EARS: two small dark rounds, nestled INTO the head's own
    # top rather than perched above it ──
    for s in (-1, 1):
        orb(f'gnear{s}', hx + s * 0.11, hy + 0.03, hz + 0.36, 0.13, 0.09,
            0.14, key='gnaw_fur_dark', subdiv=0)

    # ── THE EYE: one round dark orb with a bright chip for the highlight.
    # Placed by the head's OWN surface maths this time, not by guessing an
    # offset and hoping it clears — every earlier attempt at an offset
    # ended up either buried (only the highlight poking through) or so far
    # out it read as a separate floating shape. A point at head_centre +
    # unit_direction * radius * 1.15 is guaranteed to sit just proud of the
    # surface regardless of how lopsided the head's own radii are. ──
    _hcx, _hcy, _hcz = hx, hy, hz + hr * 0.94 / 2
    _hrx, _hry, _hrz = hr / 2, hr * 0.98 / 2, hr * 0.94 / 2
    _nx, _ny, _nz = -0.55, -0.75, 0.36
    ex = _hcx + _nx * _hrx * 1.15
    ey = _hcy + _ny * _hry * 1.15
    ecz = _hcz + _nz * _hrz * 1.15
    orb('gneye', ex, ey, ecz - 0.08, 0.16, 0.12, 0.17, key='dark', subdiv=0)
    orb('gneyehl', ex - 0.04, ey - 0.05, ecz + 0.02, 0.05, 0.032, 0.055,
        key='stucco', subdiv=0)

    # ── THE PAWS: two small tan front paws, sat on the ground right at
    # the head/body seam so they actually touch both — each one tipped
    # with a small crystal claw, the way the reference always shows them ──
    for s in (-1, 1):
        orb(f'gnpaw{s}', hx + s * 0.14, hy + 0.24, -0.02, 0.18, 0.20, 0.20,
            key='gnaw_paw', subdiv=0)
        shard(f'gnclaw{s}', hx + s * 0.14, hy + 0.24 - 0.11, 0.10, 0.032,
              0.10, tilt=(0.55, 0, s * 0.15), sides=4)
    # ── THE FEET: barely visible, tucked under the body's own bulk ──
    for s in (-1, 1):
        orb(f'gnfoot{s}', s * 0.14, 0.20, -0.02, 0.18, 0.20, 0.16,
            key='gnaw_fur_dark', subdiv=0)

    # ── THE TAIL: small, flat, low, right at the body's own back edge ──
    tail = orb('gntail', 0, 0.42, 0, 0.10, 0.16, 0.08, key='gnaw_fur_dark',
               subdiv=0)
    tail.rotation_euler = (0.35, 0, 0)

    # ── A SECOND crystal, small, on the head by the near ear — the
    # reference keeps the growth on more than just the shoulder. ──
    shard('gnheadcrys', hx - 0.20, hy + 0.10, hz + 0.34, 0.045, 0.16,
          tilt=(-0.15, 0.35, 0), sides=5)

    # ── THE CRYSTAL CLUSTER: the signature — a jagged amber growth on the
    # left shoulder, the one part of the reference held identical across
    # every image regardless of pose. Sized and angled by hand, not
    # looped, the same way the castle's own ornament is: a crystal patch
    # where every shard is the same size is a comb, not a growth. ──
    cx, cy, cz = 0.08, -0.16, 0.48
    for nm, dx, dy, dz, r, h, tx_, ty_ in (
        ('a', 0.00, 0.00, 0.02, 0.09, 0.38, -0.10, -0.10),
        ('b', -0.13, 0.05, -0.02, 0.07, 0.30, -0.05, 0.10),
        ('c', 0.15, 0.03, -0.04, 0.062, 0.26, -0.12, -0.25),
        ('d', -0.03, -0.12, -0.06, 0.054, 0.22, -0.22, 0.05),
        ('e', 0.08, 0.13, -0.04, 0.050, 0.20, 0.05, -0.15),
        ('f', -0.20, -0.05, -0.10, 0.038, 0.15, -0.08, 0.20),
    ):
        shard(f'gncrys{nm}', cx + dx, cy + dy, cz + dz, r, h,
              tilt=(tx_, ty_, 0.0))


PRESETS = {
    'glimmergnaw_s1': glimmergnaw_stage1,
}


def main():
    import argparse
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument('--preset', required=True, choices=sorted(PRESETS))
    ap.add_argument('--out', help='PNG to write (not needed with --no-render)')
    ap.add_argument('--scale', type=int, default=rb.SCALE * 2)
    ap.add_argument('--headroom', type=float, default=1.1)
    ap.add_argument('--azimuth', type=float, default=0.0)
    ap.add_argument('--guides', action='store_true')
    ap.add_argument('--no-render', action='store_true')
    ap.add_argument('--blend')
    args = ap.parse_args(argv)

    rb.clear()
    PRESETS[args.preset]()
    if args.guides:
        rb.guide_plane(1.0, 1.0)
    rb.vary_tones()
    rb.bevel_everything(viewport=not args.no_render)
    rb.light(args.azimuth)
    rb.frame(1.0, 1.0, args.scale, args.headroom, args.azimuth, fit=True)

    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    for name in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        if name in engines:
            scene.render.engine = name
            break

    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args.blend))
    if args.no_render:
        rb.show_in_viewport()
        return
    if not args.out:
        ap.error('--out is required unless --no-render is given')
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = os.path.abspath(args.out)
    bpy.ops.render.render(write_still=True)
    print(f'wrote {args.out}  {scene.render.resolution_x}x'
          f'{scene.render.resolution_y}')


if __name__ == '__main__':
    main()
