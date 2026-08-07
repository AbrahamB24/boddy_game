"""Quantise a render to a palette PNG — same picture, a fraction of the bytes.

    python tool/shrink_png.py docs/renders/main_hall.png
    python tool/shrink_png.py docs/renders/*.png --colors 128

── Why this works so well HERE and would not elsewhere ──
Everything this pipeline produces is FLAT COLOUR. A building is a few dozen
palette entries with hard edges between them and no gradients anywhere, which
is exactly the case a 24-bit PNG is worst at and an 8-bit palette is best at.
A photograph would fall apart at 128 colours; a faceted low-poly render loses
nothing the eye can find.

FASTOCTREE, not the default: it is the one Pillow method that keeps the alpha
channel, and every building render is transparent outside its own silhouette.
MEDIANCUT would flatten the cut-out to a rectangle.

── The check ──
It refuses to write a file it made BIGGER, which happens on an image that was
already indexed. Quietly growing a file you were asked to shrink is worse than
doing nothing, because nobody looks twice at a tool that reported success.
"""
import argparse
import glob
import pathlib

from PIL import Image


def shrink(path: pathlib.Path, colors: int, dry: bool) -> tuple[int, int]:
    before = path.stat().st_size
    img = Image.open(path)
    had_alpha = img.mode in ('RGBA', 'LA') or 'transparency' in img.info
    img = img.convert('RGBA' if had_alpha else 'RGB')
    out = img.quantize(colors=colors, method=Image.Quantize.FASTOCTREE)

    tmp = path.with_suffix('.quant.png')
    out.save(tmp, optimize=True)
    after = tmp.stat().st_size
    if after >= before:
        tmp.unlink()
        return before, before
    if dry:
        tmp.unlink()
    else:
        tmp.replace(path)
    return before, after


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('paths', nargs='+')
    ap.add_argument('--colors', type=int, default=192,
                    help='palette size. 192 is invisible on this art; 96 is '
                         'still clean and roughly half again the saving.')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    files = []
    for p in args.paths:
        files.extend(pathlib.Path(f) for f in glob.glob(p))
    total_before = total_after = 0
    for f in sorted(set(files)):
        if f.suffix.lower() != '.png':
            continue
        b, a = shrink(f, args.colors, args.dry_run)
        total_before += b
        total_after += a
        mark = '=' if a == b else '→'
        print(f'{f.name:28s} {b // 1024:6d} KB {mark} {a // 1024:6d} KB')
    if total_before:
        cut = 100 * (1 - total_after / total_before)
        print(f'{"TOTAL":28s} {total_before // 1024:6d} KB → '
              f'{total_after // 1024:6d} KB  ({cut:.0f} % smaller)')


main()
