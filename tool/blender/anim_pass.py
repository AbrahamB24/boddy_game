"""The moving parts of a building: extra render passes, cut out and packed.

make_building.py calls this after the FULL picture is rendered. Three kinds of
pass, all through the same camera so every layer lands on the picture exactly:

  BASE   the picture with every swaying group hidden from the camera (it still
         casts its shadow) -> <id>_base.webp, what the map draws underneath.
  GROUP  one per fw_kit.anim group: only that group visible, everything else a
         HOLDOUT (punches alpha where it stands in front), so the layer is
         exactly the part's visible pixels.
  LIGHT  one per emissive material present (GLOW_LAYERS): every other material
         swapped for a holdout, so the layer is that light and nothing else;
         the app ADDS it on top with a breathing or flickering strength.

Each layer is cropped to its pixels, scaled to the shipping density and
stacked into <id>_anim.webp; its rectangles and pivot go into kBuildingAnim
(lib/features/settlement/data/building_model.dart), as fractions of the
picture so the app can draw them at any decode size.
"""
import os
import re

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

import pro_kit as K

# material key -> (kind, amp, period). Windows breathe; flames flicker.
GLOW_LAYERS = {
    'pane_glow': ('glow', 0.45, 6.0),
    'lamp': ('flicker', 0.7, 1.0),
    'egg_glow': ('glow', 0.6, 3.2),
    'mote': ('flicker', 0.9, 1.0),
}


# ── image helpers (Blender is the only image tool on this machine) ──
def load_rgba(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)[::-1].copy()          # top row first


def _to_image(arr, name='tmp'):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(arr[::-1].astype(np.float32).ravel())
    return img


def resize(arr, w, h):
    img = _to_image(arr)
    img.scale(max(1, w), max(1, h))
    out = np.empty(img.size[0] * img.size[1] * 4, np.float32)
    img.pixels.foreach_get(out)
    out = out.reshape(img.size[1], img.size[0], 4)[::-1].copy()
    bpy.data.images.remove(img)
    return out


def save_webp(arr, dst, quality):
    sc = bpy.context.scene
    vs = sc.view_settings
    keep = (vs.view_transform, vs.look, vs.exposure)
    vs.view_transform, vs.look, vs.exposure = 'Standard', 'None', 0.0
    st = sc.render.image_settings
    st.file_format, st.color_mode, st.quality = 'WEBP', 'RGBA', quality
    img = _to_image(arr, os.path.basename(dst))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save_render(dst, scene=sc)
    bpy.data.images.remove(img)
    vs.view_transform, vs.look, vs.exposure = keep
    st.file_format = 'PNG'
    print('SHIPPED', dst, f'{arr.shape[1]}x{arr.shape[0]}', os.path.getsize(dst),
          'bytes')


def alpha_box(arr, pad=3, thr=0.01):
    ys, xs = np.nonzero(arr[:, :, 3] > thr)
    if not len(xs):
        return None
    h, w = arr.shape[:2]
    return (max(0, xs.min() - pad), max(0, ys.min() - pad),
            min(w, xs.max() + 1 + pad), min(h, ys.max() + 1 + pad))


# ── scene helpers ──
def project(pt_world):
    """World point -> (x, y) as fractions of the picture, from its top-left."""
    sc = bpy.context.scene
    bpy.context.view_layer.update()
    u, v, _ = world_to_camera_view(sc, sc.camera, Vector(pt_world))
    return (u, 1.0 - v)


def _border_around(obs, margin=0.02):
    """Render only the screen box the objects cover (+ margin) — a group pass
    that would otherwise trace the whole empty frame."""
    sc = bpy.context.scene
    us, vs = [], []
    for o in obs:
        for c in o.bound_box:
            u, v, _ = world_to_camera_view(sc, sc.camera, o.matrix_world @ Vector(c))
            us.append(u)
            vs.append(v)
    r = sc.render
    r.use_border = True
    r.use_crop_to_border = False
    r.border_min_x = max(0.0, min(us) - margin)
    r.border_max_x = min(1.0, max(us) + margin)
    r.border_min_y = max(0.0, min(vs) - margin)
    r.border_max_y = min(1.0, max(vs) + margin)


def _no_border():
    bpy.context.scene.render.use_border = False


def _holdout_material():
    m = bpy.data.materials.get('_holdout')
    if m:
        return m
    m = bpy.data.materials.new('_holdout')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    ho = nt.nodes.new('ShaderNodeHoldout')
    nt.links.new(ho.outputs[0], out.inputs['Surface'])
    return m


def _phase(name):
    return (sum(ord(c) * (i + 1) for i, c in enumerate(name)) % 628) / 100.0


# ── the passes ──
def render_layers(bid, groups, glow, tmp_dir, samples):
    """groups: {name: (voxel_object, spec)}; glow: {mat_key: (kind, amp, period)}.
    Returns the list of rendered layer files with their metadata."""
    sc = bpy.context.scene
    vox = [o for o in bpy.data.objects if o.type == 'MESH']
    layers = []
    base_png = None

    if groups:
        for g, _ in groups.values():
            g.visible_camera = False
        base_png = os.path.join(tmp_dir, f'{bid}__base.png')
        K.render(base_png)
        for g, _ in groups.values():
            g.visible_camera = True

        for name, (g, spec) in groups.items():
            for o in vox:
                o.is_holdout = o is not g
            _border_around([g])
            path = os.path.join(tmp_dir, f'{bid}__g_{name}.png')
            K.render(path)
            _no_border()
            pv = spec['pivot']
            layers.append(dict(path=path, kind=spec['kind'], amp=spec['amp'],
                               period=spec['period'], phase=_phase(name),
                               pivot=project((pv[0], pv[1], pv[2] - K.G))))
        for o in vox:
            o.is_holdout = False

    present = {s.material.name for o in vox for s in o.material_slots if s.material}
    hold = _holdout_material()
    keep_samples = sc.cycles.samples
    sc.cycles.samples = max(16, samples // 4)
    for key, (kind, amp, period) in glow.items():
        if key not in present:
            continue
        saved = []
        for o in vox:
            for i, s in enumerate(o.material_slots):
                if s.material and s.material.name != key:
                    saved.append((o, i, s.material))
                    s.material = hold
        path = os.path.join(tmp_dir, f'{bid}__l_{key}.png')
        K.render(path)
        for o, i, m in saved:
            o.material_slots[i].material = m
        layers.append(dict(path=path, kind=kind, amp=amp, period=period,
                           phase=_phase(key), pivot=(0.5, 0.5)))
    sc.cycles.samples = keep_samples
    return base_png, layers


def pack(bid, full_png, base_png, layers, assets_dir, ship_w_of, quality):
    """Ship <id>.webp, <id>_base.webp, <id>_anim.webp; return the Dart spec
    line's values (or None when nothing moves)."""
    full = load_rgba(full_png)
    ih, iw = full.shape[:2]
    sw = ship_w_of(iw)
    f = sw / iw
    sh = max(1, round(ih * f))
    save_webp(resize(full, sw, sh), os.path.join(assets_dir, f'{bid}.webp'), quality)
    if base_png is None and not layers:
        for suffix in ('_base', '_anim'):
            p = os.path.join(assets_dir, f'{bid}{suffix}.webp')
            if os.path.exists(p):
                os.remove(p)
        return None
    if base_png:
        save_webp(resize(load_rgba(base_png), sw, sh),
                  os.path.join(assets_dir, f'{bid}_base.webp'), quality)
    else:
        p = os.path.join(assets_dir, f'{bid}_base.webp')
        if os.path.exists(p):
            os.remove(p)

    crops = []
    for L in layers:
        arr = load_rgba(L['path'])
        box = alpha_box(arr)
        if box is None:
            print('LAYER EMPTY', L['path'])
            continue
        x0, y0, x1, y1 = box
        cut = arr[y0:y1, x0:x1]
        cw, ch = max(1, round((x1 - x0) * f)), max(1, round((y1 - y0) * f))
        crops.append((L, (x0, y0, x1, y1), resize(cut, cw, ch)))
    if not crops:
        return None
    gap = 2
    aw = max(c[2].shape[1] for c in crops)
    ah = sum(c[2].shape[0] for c in crops) + gap * (len(crops) - 1)
    atlas = np.zeros((ah, aw, 4), np.float32)
    y = 0
    out = []
    for L, (x0, y0, x1, y1), img in crops:
        h_, w_ = img.shape[:2]
        atlas[y:y + h_, 0:w_] = img
        out.append(dict(kind=L['kind'], src=(0, y, w_, h_),
                        dst=(x0 / iw, y0 / ih, (x1 - x0) / iw, (y1 - y0) / ih),
                        pivot=L['pivot'], amp=L['amp'], period=L['period'],
                        phase=L['phase']))
        y += h_ + gap
    save_webp(atlas, os.path.join(assets_dir, f'{bid}_anim.webp'), quality)
    return dict(aspect=ih / iw, has_base=base_png is not None, layers=out)


# ── Dart ──
def _rw(path, fn):
    with open(path, 'rb') as fh:
        raw = fh.read().decode('utf-8')
    crlf = '\r\n' in raw
    text = fn(raw.replace('\r\n', '\n'))
    if crlf:
        text = text.replace('\n', '\r\n')
    with open(path, 'wb') as fh:
        fh.write(text.encode('utf-8'))


def _set_map_entry(path, map_name, bid, entry):
    def fn(t):
        m = re.search(r'const Map<String, [^\n]+?> ' + map_name
                      + r' = \{\n(.*?)\};', t, re.S)
        body = m.group(1)
        body = re.sub(r"^  '" + re.escape(bid) + r"':[^\n]*\n", '', body, flags=re.M)
        if entry is not None:
            body += entry + '\n'
        return t[:m.start(1)] + body + t[m.end(1):]
    _rw(path, fn)


def write_anim(path, bid, spec):
    if spec is None:
        _set_map_entry(path, 'kBuildingAnim', bid, None)
        return

    def n(v):
        return f'{v:.5f}'.rstrip('0').rstrip('.') if isinstance(v, float) else str(v)
    parts = []
    for L in spec['layers']:
        vals = [*L['src'], *L['dst'], *L['pivot'], L['amp'], L['period'], L['phase']]
        parts.append('BuildingAnimLayer(AnimKind.' + L['kind'] + ', '
                     + ', '.join(n(float(v)) for v in vals) + ')')
    entry = (f"  '{bid}': BuildingAnimSpec({n(spec['aspect'])}, "
             f"{'true' if spec['has_base'] else 'false'}, [" + ', '.join(parts) + ']),')
    _set_map_entry(path, 'kBuildingAnim', bid, entry)
    print('ANIM', bid, len(spec['layers']), 'layers')


def write_entrance(path, bid, ents):
    """ents: a list of (cx, cy, dx, dy) — every door, every gate."""
    entry = None if not ents else (
        f"  '{bid}': [" + ', '.join(f'({e[0]}, {e[1]}, {e[2]}, {e[3]})' for e in ents)
        + '],')
    ents = ents or None
    _set_map_entry(path, 'kBuildingEntrance', bid, entry)
    print('ENTRANCE', bid, ents)
