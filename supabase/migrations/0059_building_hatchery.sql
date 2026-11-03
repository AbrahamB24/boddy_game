-- Fachwerk rebuild (2026-11-03): the Hatchery, remodelled in
-- tool/blender/buildings/hatchery.py.
--
-- Footprint 4 x 3 — the size the new model is rendered for. The app reads
-- building defs from this table, so a row with any other footprint stretches
-- the picture over the wrong ground and puts the entrance in the wrong cell
-- (the app falls back to the old any-side road rule until this has run; see
-- kModelFootprint in lib/features/settlement/data/building_model.dart).
--
-- image_url goes to null: the bundled picture always wins over an uploaded
-- one (data/building_art.dart), so a URL left here is never drawn.
update public.building_defs
   set grid_w = 4,
       grid_h = 3,
       image_url = null
 where id = 'hatchery';
