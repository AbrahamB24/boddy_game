-- The green leaf-winged dragon (voxel art in assets/images/monsters/leafwing_s0..2) takes over the species id 'mossgator'.
-- The id stays, so every owned monster, ability and image URL keeps working; only the names change.
-- The app finds the baked art through the stage image URL ('creature-images/<id>_<stage>.png', see
-- MonsterSheets.forUrl), so every stage gets that URL; the baked sprite wins, the file never has to exist.
update public.species_defs
set name = 'Leafling',
    description = 'A green dragon with leaf wings that grows from a drifting leaf-glider into an upright guardian of the woods.',
    stages = jsonb_build_array(
      jsonb_build_object('name', 'Leafling',
        'image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/mossgator_0.png',
        'back_image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/mossgator_0_back.png'),
      jsonb_build_object('name', 'Leafwing',
        'image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/mossgator_1.png',
        'back_image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/mossgator_1_back.png'),
      jsonb_build_object('name', 'Verdantdrake',
        'image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/mossgator_2.png',
        'back_image_url', 'https://wyvgehzwpslbpibggmea.supabase.co/storage/v1/object/public/creature-images/mossgator_2_back.png'))
where id = 'mossgator';
