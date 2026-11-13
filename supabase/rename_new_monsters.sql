-- New voxel monsters take over existing species ids (ids stay, so owned monsters,
-- abilities and image URLs keep working; only the names change).
-- Phoenix  (assets/images/monsters/phoenix_s0..2) -> species 'blazeling'
-- Duck     (assets/images/monsters/duck_s0..2)    -> species 'droplet'
-- Safe to run more than once.

update public.species_defs
set name = 'Cinderchick',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Cinderchick"'), '{1,name}', '"Flamewing"'), '{2,name}', '"Solarphoenix"')
where id = 'blazeling';

update public.species_defs
set name = 'Quackling',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Quackling"'), '{1,name}', '"Paddlewing"'), '{2,name}', '"Stormduck"')
where id = 'droplet';

-- Check:
select id, name, stages::jsonb -> 0 ->> 'name' as s0, stages::jsonb -> 1 ->> 'name' as s1, stages::jsonb -> 2 ->> 'name' as s2
from public.species_defs
where id in ('blazeling', 'droplet');
