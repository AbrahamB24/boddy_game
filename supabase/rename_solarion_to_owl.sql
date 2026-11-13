-- The owl (voxel art in assets/images/monsters/owl_s0..2) takes over the legendary light species 'solarion'
-- (user 2026-11-13). The id stays, so owned monsters, abilities, the dungeon boss and the image URLs keep working;
-- only the names change. Element (light), rarity (legendary), stats and abilities are untouched.
-- Names are my proposal (the user did not name them): change them here before running if you want others.
-- Safe to run more than once.

update public.species_defs
set name = 'Dawnpip',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Dawnpip"'), '{1,name}', '"Glimmowl"'), '{2,name}', '"Aurowl"')
where id = 'solarion';

-- Check:
select id, name, element, rarity, stages::jsonb -> 0 ->> 'name' as s0, stages::jsonb -> 1 ->> 'name' as s1, stages::jsonb -> 2 ->> 'name' as s2
from public.species_defs
where id = 'solarion';
