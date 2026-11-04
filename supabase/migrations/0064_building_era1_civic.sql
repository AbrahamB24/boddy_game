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
