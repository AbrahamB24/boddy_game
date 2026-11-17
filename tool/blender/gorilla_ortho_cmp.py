"""Compare my gorilla.py renders (views ofront/oback/oside/otop) with the user's orthographic sheet, per stage.

    blender --background --python tool/blender/gorilla_ortho_cmp.py -- <sheet.png> <render dir> <stage 0..2> <out.png>

One row per view: reference | mine | overlay (reference red, mine green, both yellow); prints the silhouette IoU per view.
Scale: the reference is resized so that its FRONT silhouette has the same height as mine (proportions between views stay honest);
horizontal alignment by bbox centre, vertical by the feet.
"""
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gorilla_ortho_masks as om  # noqa: E402

sheet, rdir, stage, outp = sys.argv[sys.argv.index('--') + 1:][:4]
stage = int(stage)
SIZE = 400
px = om.load(sheet)


def load_rgba(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]


def bbox(m):
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def resize(a, s):
    h, w = a.shape[:2]
    nh, nw = max(1, int(round(h * s))), max(1, int(round(w * s)))
    yy = np.minimum(((np.arange(nh) + .5) / s).astype(int), h - 1)
    xx = np.minimum(((np.arange(nw) + .5) / s).astype(int), w - 1)
    return a[yy][:, xx]


mine = {}
for v in ('front', 'back', 'side', 'top'):
    rgba = load_rgba(os.path.join(rdir, 'gorilla_s%d_o%s.png' % (stage, v)))
    mine[v] = (rgba[..., :3] * 255.0, rgba[..., 3] > .5)

ref = {}
for name, (x0, y0, x1, y1) in zip(om.NAMES, om.PANELS[stage]):
    reg = px[y0:y1, x0:x1]
    m, bg = om.mask_of(reg, 24.0 if np.median(reg) > 60 else 11.0)
    bx0, by0, bx1, by1 = bbox(m)
    ref[name] = (reg[by0:by1, bx0:bx1], m[by0:by1, bx0:bx1])

mb = bbox(mine['front'][1])
s = (mb[3] - mb[1]) / ref['front'][1].shape[0]                       # my px per reference px
print('scale mine/ref', round(float(s), 3))

rows = []
for v in ('front', 'back', 'side', 'top'):
    rgb_r, m_r = ref[v]
    rgb_r, m_r = resize(rgb_r, s), resize(m_r.astype(np.uint8), s).astype(bool)
    mine_rgb, mine_m = mine[v]
    mb = bbox(mine_m)
    canvas_rgb = np.zeros((SIZE, SIZE, 3), np.float32)
    canvas_m = np.zeros((SIZE, SIZE), bool)
    h, w = m_r.shape
    cx = (mb[0] + mb[2]) // 2
    x0 = int(np.clip(cx - w // 2, 0, max(SIZE - w, 0)))
    y1 = mb[3] if v != 'top' else (mb[1] + mb[3]) // 2 + h // 2          # feet aligned (front/back/side), top view centred
    y0 = y1 - h
    ys0, xs0 = max(y0, 0), x0
    sub_h, sub_w = min(h, SIZE - ys0), min(w, SIZE - xs0)
    canvas_rgb[ys0:ys0 + sub_h, xs0:xs0 + sub_w] = rgb_r[:sub_h, :sub_w]
    canvas_m[ys0:ys0 + sub_h, xs0:xs0 + sub_w] = m_r[:sub_h, :sub_w]
    inter = (canvas_m & mine_m).sum()
    union = (canvas_m | mine_m).sum()
    print(v, 'IoU', round(float(inter / max(union, 1)), 3))
    if v in ('front', 'side'):                                   # extent per height: ref L..R vs mine L..R in world units (1 unit = SIZE/1.5 px), 0 = image centre
        ppu = SIZE / 1.5
        top_y, bot_y = mb[1], mb[3]
        line = []
        for f in (.95, .85, .75, .65, .55, .45, .35, .25, .15, .06):
            yy = int(bot_y - f * (bot_y - top_y))
            rr = np.where(canvas_m[yy])[0]
            mm_ = np.where(mine_m[yy])[0]
            fmt = lambda a: ('%+.2f..%+.2f' % ((a.min() - SIZE / 2) / ppu, (a.max() - SIZE / 2) / ppu)) if len(a) else '   -   '
            line.append('z%.2f ref %s mine %s' % (f * (bot_y - top_y) / ppu, fmt(rr), fmt(mm_)))
        print('   ' + '\n   '.join(line))
    ov = np.zeros((SIZE, SIZE, 3), np.float32)
    ov[..., 0] = canvas_m * 255
    ov[..., 1] = mine_m * 255
    shown_mine = np.where(mine_m[..., None], mine_rgb, 40.0)
    rows.append(np.concatenate([np.where(canvas_m[..., None], canvas_rgb, 40.0), shown_mine, ov], axis=1))
sheetimg = np.concatenate(rows, axis=0) / 255.0
o = bpy.data.images.new('cmp', sheetimg.shape[1], sheetimg.shape[0], alpha=False)
rgba = np.ones((sheetimg.shape[0], sheetimg.shape[1], 4), np.float32)
rgba[..., :3] = sheetimg
o.pixels = rgba[::-1].reshape(-1)
o.filepath_raw = outp
o.file_format = 'PNG'
o.save()
