"""Pack rendered art for the app: PNG in, WebP out.

    python tool/pack_art.py "docs/renders/*.png" assets/images/buildings
    python tool/pack_art.py "docs/renders/roads/*.png" assets/images/roads -q 90

── Why this replaced the palette quantiser (user 2026-08-12) ──
tool/shrink_png.py argues, correctly for what it was written against:

    "Everything this pipeline produces is FLAT COLOUR. A building is a few
     dozen palette entries with hard edges between them and no gradients
     anywhere ... A photograph would fall apart at 128 colours; a faceted
     low-poly render loses nothing the eye can find."

That stopped being true the moment the materials got grain and relief. Every
surface is now a continuous ramp of its own tone, and a 200-colour palette
cannot hold one — it dithers, and the fine even grain that made the stone look
like stone comes back as coarse speckle. Measured on the quarry: the
quantised version is visibly mottled at 1:1 where the source is smooth.

WebP is the right answer and it is not even a trade:

    palette PNG, 200 colours   103 KB   grain destroyed
    WebP, quality 88            54 KB   mean error 2.2/255, 1.9 % over 8/255

Half the size AND it keeps the picture, because a lossy continuous-tone codec
is built for exactly the thing a palette is worst at. Alpha survives — WebP
carries a full alpha channel, which is why this is not JPEG.

Quality 88 rather than 80: at 80 the file is a third smaller again and the
flat faces start showing block edges where two large single-tone areas meet,
which is the one artefact this art has nowhere to hide.
"""
import argparse
import glob
import pathlib

from PIL import Image

QUALITY = 88

# ── The APP does not need the archive's resolution (user 2026-08-12) ──
# The renders are authored around 1024-1372 px because that is what makes a
# readable contact sheet. The map draws a five-cell building about 320 logical
# px wide, and decoded at source the twenty assets need 80 MB of RGBA against
# Flutter's 100 MB image cache — which on CanvasKit came out as "memory access
# out of bounds" inside the wasm heap rather than as a clean eviction.
#
# 640 is chosen against the DEVICE pixels, not against taste: the widest
# building is drawn 320 logical px across, and on a 2x screen at map zoom 1
# that is exactly 640 — so the art lands 1:1 and every pixel shipped is a
# pixel used. Zooming past 1x softens it, which a stylised sprite survives;
# shipping four times the pixels for that case is what broke the web build.
# docs/renders keeps the full-size pictures; only what SHIPS is capped.
APP_MAX_WIDTH = 640


def pack(src: pathlib.Path, dst_dir: pathlib.Path, quality: int,
         dry: bool, max_width: int = 0) -> tuple[int, int]:
    before = src.stat().st_size
    dst = dst_dir / (src.stem + '.webp')
    im = Image.open(src).convert('RGBA')
    if max_width and im.width > max_width:
        im = im.resize((max_width, round(im.height * max_width / im.width)),
                       Image.LANCZOS)
    if not dry:
        dst_dir.mkdir(parents=True, exist_ok=True)
        # method=6 is the slowest and smallest search. This runs twenty times
        # after a render that took four minutes; the seconds are free.
        im.save(dst, 'WEBP', quality=quality, method=6)
    after = dst.stat().st_size if dst.exists() else 0
    return before, after


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('pattern', help='glob of source PNGs, quoted')
    ap.add_argument('out', help='directory to write .webp into')
    ap.add_argument('-q', '--quality', type=int, default=QUALITY)
    ap.add_argument('-w', '--max-width', type=int, default=0,
                    help=f'downscale to this width; {APP_MAX_WIDTH} for app assets')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    files = sorted(pathlib.Path(p) for p in glob.glob(a.pattern))
    if not files:
        raise SystemExit(f'nothing matched {a.pattern!r}')
    out = pathlib.Path(a.out)
    tot_b = tot_a = 0
    for f in files:
        b, c = pack(f, out, a.quality, a.dry_run, a.max_width)
        tot_b += b
        tot_a += c
        print(f'{f.name:30s} {b // 1024:6d} KB -> {c // 1024:6d} KB')
    pct = 100 - (tot_a * 100 // max(1, tot_b))
    print(f'{"TOTAL":30s} {tot_b // 1024:6d} KB -> {tot_a // 1024:6d} KB '
          f'({pct} % smaller)')


if __name__ == '__main__':
    main()
