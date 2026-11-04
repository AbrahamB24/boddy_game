
-- ===== migrations/0059_building_hatchery.sql =====
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

-- ===== migrations/0060_building_small_house.sql =====
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

-- ===== migrations/0061_placed_building_rotation.sql =====
-- Turning buildings (user 2026-11-03: "Gebäude um 90° drehen").
--
-- Quarter turns clockwise, 0..3. An odd turn swaps the footprint's width and
-- depth (BuildingDef.rotated); the picture is the model rendered from that
-- side (assets/images/buildings/<id>_r1..3.webp).
--
-- The app writes this column on its own, guarded
-- (SettlementService.setBuildingRotation): until this has run, buildings
-- still place and move — they just cannot remember a turn.
alter table public.placed_buildings
  add column if not exists rotation smallint not null default 0
    check (rotation between 0 and 3);

-- ===== migrations/0062_building_camps.sql =====
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

-- ===== migrations/0063_building_shops_stores.sql =====
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

-- ===== migrations/0064_building_era1_civic.sql =====
-- Fachwerk rebuild (2026-11-04): the remaining era-I civic buildings,
-- remodelled in tool/blender/buildings/{scout_post,large_house,breeding_hut,
-- healing_hut,builder_camp,combat_school,trading_post,caravanserai}.py.
--
-- Footprints stay as they were (scout_post 2 x 2, large_house 2 x 5,
-- breeding_hut 4 x 4, healing_hut 5 x 4, builder_camp 5 x 5, combat_school
-- 5 x 4, trading_post 4 x 3, caravanserai 4 x 3), so nothing in grid_w /
-- grid_h changes and no placed building needs moving.
--
-- image_url goes to null: the bundled picture always wins over an uploaded
-- one (data/building_art.dart), so a URL left here is never drawn.
update public.building_defs
   set image_url = null
 where id in ('scout_post', 'large_house', 'breeding_hut', 'healing_hut',
              'builder_camp', 'combat_school', 'trading_post', 'caravanserai');

-- The legendary buildings (church, marketplace and the per-era "Grand Works" /
-- "Treasury" pairs) are gone from the roster: something new replaces them.
-- Placed ones go with them.
delete from public.placed_buildings
 where building_type_id in (
   'church', 'marketplace',
   'special_materials_e2', 'special_materials_e3', 'special_materials_e4',
   'special_materials_e5', 'special_materials_e6', 'special_materials_e7',
   'special_materials_e8',
   'special_treasury_e2', 'special_treasury_e3', 'special_treasury_e4',
   'special_treasury_e5', 'special_treasury_e6', 'special_treasury_e7',
   'special_treasury_e8');

delete from public.building_defs
 where id in (
   'church', 'marketplace',
   'special_materials_e2', 'special_materials_e3', 'special_materials_e4',
   'special_materials_e5', 'special_materials_e6', 'special_materials_e7',
   'special_materials_e8',
   'special_treasury_e2', 'special_treasury_e3', 'special_treasury_e4',
   'special_treasury_e5', 'special_treasury_e6', 'special_treasury_e7',
   'special_treasury_e8');

-- ===== migrations/0065_building_plot_workshop_training.sql =====
-- Fachwerk rebuild (2026-11-04): building plot, workshop (potter's) and
-- training grounds, remodelled in tool/blender/buildings/{building_plot,
-- thinker_circle,training_grounds}.py. Footprints stay (5 x 5, 3 x 3, 3 x 3).
-- image_url goes to null: the bundled picture always wins over an uploaded one.
update public.building_defs
   set image_url = null
 where id in ('building_plot', 'thinker_circle', 'training_grounds');
