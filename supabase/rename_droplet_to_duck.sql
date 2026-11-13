-- The duck (voxel art in assets/images/monsters/duck_s0..2) takes over the species id 'droplet'.
-- The id stays, so every owned monster, ability and image URL keeps working; only the names change.
update public.species_defs
set name = 'Quackling',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Quackling"'), '{1,name}', '"Paddlewing"'), '{2,name}', '"Stormduck"')
where id = 'droplet';
