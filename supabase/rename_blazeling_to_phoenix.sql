-- The fire bird (voxel art in assets/images/monsters/phoenix_s0..2) takes over the species id 'blazeling'.
-- The id stays, so every owned monster, ability and image URL keeps working; only the names change.
update public.species_defs
set name = 'Cinderchick',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Cinderchick"'), '{1,name}', '"Flamewing"'), '{2,name}', '"Solarphoenix"')
where id = 'blazeling';
