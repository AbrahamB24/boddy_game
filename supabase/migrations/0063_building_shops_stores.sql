-- Fachwerk rebuild (2026-11-04): the remaining era-I resource buildings,
-- remodelled in tool/blender/buildings/{fish_shop,butcher_shop,storehouse,
-- gold_vault}.py.
--
-- Footprints stay as they were (fish_shop 3 x 3, butcher_shop 3 x 3,
-- storehouse 4 x 3, gold_vault 4 x 4), so nothing in grid_w / grid_h changes
-- and no placed building needs moving.
--
-- image_url goes to null: the bundled picture always wins over an uploaded
-- one (data/building_art.dart), so a URL left here is never drawn.
update public.building_defs
   set image_url = null
 where id in ('fish_shop', 'butcher_shop', 'storehouse', 'gold_vault');
