-- The red dragon (voxel art in assets/images/monsters/dragon_s0..2) takes over the species id 'cinderhawk'.
-- The id stays, so every owned monster, ability and image URL keeps working; only the names change.
-- The app finds the baked art through the stage image URL ('creature-images/<id>_<stage>.png', see
-- MonsterSheets.forUrl), so every stage gets that URL; the baked sprite wins, the file never has to exist.
update public.species_defs
set name = 'Emberwhelp',
    description = 'A red dragon that grows from a cuddly hatchling into a winged giant.',
    stages = jsonb_build_array(
      jsonb_build_object('name', 'Emberwhelp',
        'image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/cinderhawk_0.png',
        'back_image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/cinderhawk_0_back.png'),
      jsonb_build_object('name', 'Cinderdrake',
        'image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/cinderhawk_1.png',
        'back_image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/cinderhawk_1_back.png'),
      jsonb_build_object('name', 'Infernodragon',
        'image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/cinderhawk_2.png',
        'back_image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/cinderhawk_2_back.png'))
where id = 'cinderhawk';
