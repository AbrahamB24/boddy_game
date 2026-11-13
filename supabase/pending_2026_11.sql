-- Offene Migrationen Stand 2026-11-13: im Supabase SQL-Editor als EIN Skript ausfuehren.
-- Alle sieben sind wiederholbar (Updates mit festen Werten), nichts loescht Spielerdaten.

-- ===== rename_droplet_to_duck =====
-- The duck (voxel art in assets/images/monsters/duck_s0..2) takes over the species id 'droplet'.
-- The id stays, so every owned monster, ability and image URL keeps working; only the names change.
update public.species_defs
set name = 'Quackling',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Quackling"'), '{1,name}', '"Paddlewing"'), '{2,name}', '"Stormduck"')
where id = 'droplet';

-- ===== rename_blazeling_to_phoenix =====
-- The fire bird (voxel art in assets/images/monsters/phoenix_s0..2) takes over the species id 'blazeling'.
-- The id stays, so every owned monster, ability and image URL keeps working; only the names change.
update public.species_defs
set name = 'Cinderchick',
    stages = jsonb_set(jsonb_set(jsonb_set(stages::jsonb,
      '{0,name}', '"Cinderchick"'), '{1,name}', '"Flamewing"'), '{2,name}', '"Solarphoenix"')
where id = 'blazeling';

-- ===== rename_cinderhawk_to_dragon =====
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

-- ===== rename_solarion_to_owl =====
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


-- ===== balance_kill_xp_1_8 =====
-- Balance pass 2026-11-02: kill XP exponent 1.3 -> 1.8.
--
-- Why: a campaign probe (every path battle cleared once, XP split across the
-- party, 1.25x average star bonus) showed the team falling further and
-- further behind its enemies with 9 * L^1.3:
--
--   battle   enemy Lv   team Lv @1.3   team Lv @1.8
--     10        5            4              5
--     30       15            9             13
--     57       32           14             21
--     76       41           17             27
--
-- At 1.3 fights in region 2+ cost 60-85 % HP each and the auto-battle starts
-- losing. Battles 1-10 are unchanged by the new value.
--
-- Only the one key is touched; every other XP dial in the row stays as it is.
-- To undo: run the same statement with 1.3, or change it in
-- Dev Mode > Species budget > XP.

update public.game_config
set value = jsonb_set(value, '{killExponent}', '1.8'::jsonb, true)
where key = 'xp_balance';

-- ===== balance_gold_2026_11 =====
-- Gold balance pass 2026-11-02 (user: "Gold bitte ausbalancieren, damit es
-- wirklich eine wichtige Ressource wird").
--
-- Houses produced 1 gold/h each. They are built by the dozen, so this was a
-- ~250 gold/day income for doing nothing, more than daily tasks, chests,
-- stars and bosses together. Cut to a quarter: 0.25/h per house.
--
-- The rest of the pass is code (survival pays full only for record floors,
-- craftable items no longer sell, daily tasks and chest reworked) and needs
-- no SQL.
--
-- Only the gold production line of the two house rows is touched; housing,
-- costs and every other effect stay as they are. Idempotent: running it
-- twice leaves 0.25.

update public.building_defs b
set effects = (
  select jsonb_agg(
    case
      when e->>'type' = 'production' and e->>'key' = 'gold'
        then jsonb_set(e, '{value}', '0.25'::jsonb)
      else e
    end
    order by ord
  )
  from jsonb_array_elements(b.effects) with ordinality as t(e, ord)
)
where b.id in ('small_house', 'large_house')
  and jsonb_array_length(b.effects) > 0;

-- ===== hospital_7x6 =====
-- Hospital (id bleibt healing_hut): Name + Grundfläche 7x6 in der Live-DB nachziehen.
-- Im Supabase SQL-Editor ausführen. Idempotent. Bereits platzierte Hospitäler
-- behalten ihre Zellen nicht automatisch: das Bild ist 7x6 (Render 2026-11-09),
-- alte 5x4-Platzierungen müssen einmal neu gesetzt werden (Dev Mode).
update building_defs
   set name = 'Hospital', grid_w = 7, grid_h = 6
 where id = 'healing_hut';
