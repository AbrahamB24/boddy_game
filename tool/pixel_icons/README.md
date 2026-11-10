# Pixel icons (24x24)

Style of the whole UI icon set (user 2026-11-09, after cyangmou's pixel-fantasy pack: its rules, not its assets):
24x24, dark hue-shifted coloured outline, 4-tone ramps, light from top-left, own cast shadow.

- `pix.py` / `pix2.py`: hand-drawn sprites built from shapes (the HUD icons in assets/images/ui_px/).
- `pixelize.py`: turns the 3D renders (docs/renders/icons/<key>.png, from tool/blender/make_icons.py --voxel 0) into the same style.
  Hand-drawn ones override the converted ones for: wood, stone, fish, coin, house, clock, bolt, paw, map, globe, backpack, tasks, crown, bell, hammer.
