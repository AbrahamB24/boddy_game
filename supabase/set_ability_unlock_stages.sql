-- ═══════════════════════════════════════════════════════════════════════════
-- Ability unlock_stage assignment (user 2026-09-06)
--
-- "sobald ich eine Evolution habe, dann stehen mir die naechsten Faehigkeiten
--  dieser Evolutionsstufe frei zum erlernen" -- unlock_stage already exists as a
-- column (ability_defs, migration 0040/0041) and already gates learnableAbilitiesFor
-- (see lib/features/creatures/models/ability_def.dart), but every row currently
-- reads 0, so no evolution actually unlocks anything move-wise yet.
--
-- Values derived from the OLD per-species SpeciesAbility.unlockStage lists across
-- the 14 species this session had data for: every element's roster split 3/1/1
-- across stage 0/1/2 with only a handful of ties, broken toward the "Ultimate X
-- attack" move in each element landing on stage 2. Ties (flutwelle, regeneration)
-- broken toward the lower stage. Review against abilities.xlsx before running --
-- this is a judgement call on incomplete species data (14 of however many exist),
-- not a mechanical export.
--
-- Run once in the Supabase SQL editor. Idempotent (plain assignment, not a delta).
-- ═══════════════════════════════════════════════════════════════════════════

begin;

update public.ability_defs set unlock_stage = 0 where id = 'kampfrausch';  -- Battle Rage
update public.ability_defs set unlock_stage = 0 where id = 'spritzer';  -- Splash
update public.ability_defs set unlock_stage = 0 where id = 'schattenkralle';  -- Shadow Claw
update public.ability_defs set unlock_stage = 0 where id = 'regeneration';  -- Regeneration
update public.ability_defs set unlock_stage = 0 where id = 'zeitdruck';  -- Haste
update public.ability_defs set unlock_stage = 0 where id = 'nachtschwinge';  -- Night Wing
update public.ability_defs set unlock_stage = 0 where id = 'rempler';  -- Tackle
update public.ability_defs set unlock_stage = 0 where id = 'fokus_schlag';  -- Focus Strike
update public.ability_defs set unlock_stage = 0 where id = 'blattsturm';  -- Leaf Storm
update public.ability_defs set unlock_stage = 0 where id = 'biss';  -- Bite
update public.ability_defs set unlock_stage = 0 where id = 'panzerung';  -- Armor Up
update public.ability_defs set unlock_stage = 0 where id = 'funke';  -- Spark
update public.ability_defs set unlock_stage = 0 where id = 'flammenstoss';  -- Flame Burst
update public.ability_defs set unlock_stage = 0 where id = 'attack';  -- Attack
update public.ability_defs set unlock_stage = 0 where id = 'aquastrahl';  -- Aqua Beam
update public.ability_defs set unlock_stage = 0 where id = 'rankenhieb';  -- Vine Strike
update public.ability_defs set unlock_stage = 0 where id = 'lichtblitz';  -- Light Flash
update public.ability_defs set unlock_stage = 0 where id = 'kraftakt';  -- Power Surge
update public.ability_defs set unlock_stage = 0 where id = 'strahlenstoss';  -- Ray Burst
update public.ability_defs set unlock_stage = 1 where id = 'wurzelgriff';  -- Root Grip
update public.ability_defs set unlock_stage = 1 where id = 'dunkelpuls';  -- Dark Pulse
update public.ability_defs set unlock_stage = 1 where id = 'aderlass';  -- Bloodletting
update public.ability_defs set unlock_stage = 1 where id = 'glutwelle';  -- Ember Wave
update public.ability_defs set unlock_stage = 1 where id = 'flutwelle';  -- Tidal Wave
update public.ability_defs set unlock_stage = 1 where id = 'prisma_strahl';  -- Prism Beam
update public.ability_defs set unlock_stage = 2 where id = 'inferno';  -- Inferno
update public.ability_defs set unlock_stage = 2 where id = 'gaia_zorn';  -- Gaia's Wrath
update public.ability_defs set unlock_stage = 2 where id = 'sonnenzorn';  -- Sun's Wrath
update public.ability_defs set unlock_stage = 2 where id = 'finsternis';  -- Darkness
update public.ability_defs set unlock_stage = 2 where id = 'tsunami';  -- Tsunami

commit;

-- Control: grouped by stage, so a quick eyeball catches anything that landed
-- somewhere unexpected.
select unlock_stage, id, name from public.ability_defs order by unlock_stage, id;
