# Building gold standard (the Hospital, `healing_hut.py`, approved 2026-11-09)

Every other era-I building is held to what the Hospital taught. Build it right
the first time with this list; the review (`make_building.py <id> --sheet`) then
only has to catch taste, not defects.

## 0. Workflow (what made the Hospital slow)
1. Build from `civic_kit.hall()` + `fw_kit`; do not hand-roll walls, windows, doors.
2. Render the review sheet (`--sheet --samples 24`): 2x2 views, **tile grid drawn on it** (review only, never in the real render).
3. User reviews one building at a time and sends close-up crops. Fix **every instance** of a defect, not the one shown ("alle kontrollieren, immer gleich machen").
4. Only after approval: register footprint, full render with animation passes.
5. `python` is not on the Bash PATH (Store alias). Edit files with Edit/sed; run Blender via `"/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P make_building.py -- <id> --sheet`.

## 1. The voxel grid decides everything (the biggest lesson)
`fw_kit.VOX = 0.0165` tile (8 cm). The voxeliser is **world-aligned** and gives
each block the material of the nearest surface, so anything not on the grid
aliases (half-lit panes, lit rims, dotted barrel hoops).
- Keep every detail >= 2 voxels (0.033 tile) wide and clearly proud (>= 1.2 voxel) of what is behind it.
- Details that must read as a closed shape (hoops, rings, bars): make them **whole, wide, proud**: radius +0.02, height 0.035, seg 24. Never thin single bands.
- Two surfaces coplanar = a tie = wrong material. Inset the one that should not show (pane stops at the frame's inner edge).
- **Windows** are `fw_kit.window()`: grid-built, 12 voxels wide, frame 2, cross 2, panes 3, pane one layer deep, frame two proud. Small windows: one pane, no cross. Lit and unlit windows both allowed, but every lit one must be identical in construction. Never put your own window geometry in a building file.
- Barrel / bucket: hoops follow the real taper profile, 4 per barrel, 2 per bucket.

## 2. Nothing may hide anything
- Posts, braces, rails keep out of the **whole opening incl. shutters** (`wall_frame` uses `window_w()` and the shutter width); holes get each window's own width (`hall` already does).
- Storey rail is continuous (`mid_through=True`) when there are upper windows.
- Roof planes either join in a real valley (lean-to roofs run on into the neighbour, the higher plane wins) or stay apart. Never a gap, never a z-fight.
- Lanterns hang **between** posts (bay midpoints), on a chain under the roof, never inside a post or roof.
- Flag cloths hang on the pole with a top and bottom rod; poles stand **in the ridge cap** (take the ridge height from `hall()`'s return value), pole thickness `0.012 + 0.035 * cloth width`.

## 3. Plot layout
- Footprint W x H grows if needed; parts never shrink. Proportions identical everywhere (`TREE_S`).
- Outer wall on the footprint's outer tile line (`WALL_* = edge - 0.07`), 0.26 high, 0.15 corner pillars.
- Trees: standard model, **big** (Hospital corners use s = 2.2; realistic, taller than the wall), in the corners inside the wall, clear of roofs, wall and each other. Back trees near the corner, not against the building.
- Ivy/moss: patchy, small leaves (r 0.026-0.042), ~one patch per 0.3 tile, **both faces** of the wall, moss on the cap on ~30%. Neither none nor a curtain.
- Yard is used, not empty: herb beds, flower patches, bushes along the wall, stock (barrels, sack, crate), one purposeful prop (the patients' cart).

## 4. Gate and walkway (user rule, all buildings with room)
- Gate stands **open**, nothing across the passage at monster height: no lintel, leaves swung back along the wall.
- Material per building (Hospital: wrought-iron grid, round top, R 0.25, bars every 3 voxels, 2 rails, ball ornaments).
- One **straight** stone path from the gate through the yard; nothing on it (well and cart stand on opposite sides of it, beds leave the 1-tile centre strip free).
- `WALKWAY_TO = [(cell)]` in the module so `make_building` writes the walkways + depth map: monsters walk in like at the castle.
- Road apron only up to the gate (`depth=0.11`); no road under the yard path.
- Entrance is `ENTRANCE = ('s', k)`; the path begins at the wall line.

## 5. Roofs, chimneys, signs
- At least **one chimney per wing** (Hospital: 4). Smoke anchor (`CHIMNEY`) is one point only.
- One flag per wing plus the huge one on the gate pillar (exaggerate the sign on purpose).
- Arcade posts: evenly spaced, one **exactly at each end**.

## 6. Animation prep (later in the app)
- Every lantern is its own `F.anim` sway group (different amplitude/period) and lit by one of six flicker materials (`LAMP_GLOW`), so they flicker weakly and out of step. Done in the kit.
- Flags, washing line, bushes, flower patches, trees already sway through `F.anim`.
- Night light (variant C) is built in; emission pass at the full render.

## 7. Defect checklist before showing a building
- [ ] every window built by `F.window`, no lit rims, shutters never covered
- [ ] all hoops/bars closed shapes, >= 2 voxels
- [ ] no lantern in a post, no roof gap, no coplanar tie
- [ ] gate open, path straight, `WALKWAY_TO` set, nothing in the 1-tile strip
- [ ] >= 1 chimney per wing, flags seated, trees big and not in the building
- [ ] ivy on both wall faces, patchy
- [ ] four views at 24 samples with grid

## 8. Kit parts to reuse (`tool/blender/civic_kit.py`, section "GOLD-STANDARD PARTS")
Call these instead of rebuilding them; the Hospital's `build()` is the worked example.

| Part | Call |
|---|---|
| city palette | `M = vivid(mats()); lamp_mats(M)` |
| lanterns | `reset_lamps()` first, then `sway_lamp(M, x, y, z_under)` at bay midpoints; `GLOW = {'pane_glow': ('glow', 0.45, 6.0), **LAMP_GLOW}` in the module |
| outer wall + gate pillars | `plot_wall(M, wall_x, wall_y_south, wall_y_north)` |
| open iron gate, round top | `iron_gate(M, wall_y_south)` |
| ivy + moss, both faces | `wall_ivy(M, wall_x, wall_y_south, wall_y_north)` |
| well with gable roof + bucket | `well(M, x, y)` |
| flag on a pole | `cross_flag(M, x, y, z0, h, w)` (pole seated in the ridge: `z0 = ridge + 0.05`) |
| herb bed | `herb_bed(M, x0, x1, y0, y1, seed)` |
| windows | via `hall()` only (`fw_kit.window`) |

Lanterns flicker weakly and out of step: six emissive materials (`lampA`-`lampF`), each its own glow layer with its own amplitude and period (`LAMP_GLOW`). Door lanterns keep `lamp`.

## 9. Registering a building (what the Hospital needed; make_building does most of it)
- Full render: `blender -b -P make_building.py -- <id>` (about 45 minutes with 46 anim layers). It writes by itself: kModelFootprint, kBuildingEntrance, kBuildingWalkways (from `WALKWAY_TO`), kBuildingAnim, art box, chimney anchor, depth map, the shipped webps (all 4 rotations).
- By hand: `gridW/gridH` in the def (`building_definitions.dart`) + `building_roster.sql` + a `supabase/<id>_<w>x<h>.sql` for the live DB; display strings; tests that name the building.
- A bigger footprint can break the **tutorial spot** (`kTutorialRoadY`, `kTutorialHealingHutY`): road + building must fit the Castle's clearance in the starting plot. The Hospital 7x6 grew the plot 20 -> 24 (same top-left corner, because the west coast is water).
