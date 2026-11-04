-- Fachwerk rebuild (2026-11-03): the four era-I resource camps, remodelled in
-- tool/blender/buildings/{small_wood_camp,large_wood_camp,small_quarry,
-- large_stone_camp}.py.
--
-- Footprints: small_wood_camp 3 x 3 and large_wood_camp 4 x 4 stay as they
-- were; small_quarry shrinks from 5 x 4 to 3 x 3 and large_stone_camp grows
-- from 4 x 4 to 5 x 4, so the large camp is again the bigger one of each
-- pair. The app reads building defs from this table, so a row with another
-- footprint stretches the picture over the wrong ground and puts the
-- entrance in the wrong cell (the app falls back to the old any-side road
-- rule until this has run; see kModelFootprint in
-- lib/features/settlement/data/building_model.dart).
--
-- image_url goes to null: the bundled picture always wins over an uploaded
-- one (data/building_art.dart), so a URL left here is never drawn.
update public.building_defs
   set grid_w = 3,
       grid_h = 3,
       image_url = null
 where id = 'small_quarry';

update public.building_defs
   set grid_w = 5,
       grid_h = 4,
       image_url = null
 where id = 'large_stone_camp';

update public.building_defs
   set image_url = null
 where id in ('small_wood_camp', 'large_wood_camp');
