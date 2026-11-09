# Re-downloads the CC0 Poly Haven textures pro_kit.py uses (textures/ is
# git-ignored, ~115 MB). Run:  python tool/blender/fetch_textures.py
import json
import os
import urllib.request

IDS = ['clay_roof_tiles_02', 'roof_tiles_14', 'thatch_roof_angled',
       'white_plaster_rough_01', 'rough_plaster_brick_02', 'weathered_planks',
       'dark_wood', 'rock_wall_08', 'old_stone_wall', 'leafy_grass',
       'grassy_cobblestone', 'park_dirt', 'reed_roof_03', 'mossy_brick']
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'textures')

# Poly Haven's API 403s the default urllib UA; any honest identifying UA
# passes (not posing as a browser, just not the blank default).
HEADERS = {'User-Agent': 'BoddyGame-asset-fetch/1.0'}


def _get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS))


for tid in IDS:
    d = os.path.join(ROOT, tid)
    os.makedirs(d, exist_ok=True)
    meta = json.load(_get(f'https://api.polyhaven.com/files/{tid}'))
    for m in ('Diffuse', 'Rough', 'nor_gl'):
        url = (meta[m].get('2k') or meta[m]['1k'])['jpg']['url']
        out = os.path.join(d, m + '.jpg')
        if not os.path.exists(out):
            with _get(url) as r, open(out, 'wb') as f:
                f.write(r.read())
    print('ok', tid)
