-- The griffin (voxel art in assets/images/monsters/griffin_s0..2) takes over the rare lightning species 'voltglider'
-- (my choice 2026-11-14, the user named no species: it is the one winged, gliding hunter in the roster). The id stays, so
-- owned monsters, abilities and the image URLs keep working; only the names change. Element, rarity, stats and abilities
-- are untouched. Names are my proposal: change them here before running if you want others.
-- Safe to run more than once.

update public.species_defs
set name = 'Gryphlet',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Gryphlet"'), '{1,name}', '"Gryphwing"'), '{2,name}', '"Stormgryph"')
where id = 'voltglider';

-- Check:
select id, name, element, rarity, stages::jsonb -> 0 ->> 'name' as s0, stages::jsonb -> 1 ->> 'name' as s1, stages::jsonb -> 2 ->> 'name' as s2
from public.species_defs
where id = 'voltglider';
