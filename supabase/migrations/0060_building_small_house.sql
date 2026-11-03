-- Fachwerk rebuild (2026-11-03): the Small House, remodelled in
-- tool/blender/buildings/small_house.py.
--
-- Footprint 2 x 2 — the size the new model is rendered for. The app reads
-- building defs from this table, so a row with any other footprint stretches
-- the picture over the wrong ground and puts the entrance in the wrong cell
-- (the app falls back to the old any-side road rule until this has run; see
-- kModelFootprint in lib/features/settlement/data/building_model.dart).
--
-- image_url goes to null: the bundled picture always wins over an uploaded
-- one (data/building_art.dart), so a URL left here is never drawn.
update public.building_defs
   set grid_w = 2,
       grid_h = 2,
       image_url = null
 where id = 'small_house';
