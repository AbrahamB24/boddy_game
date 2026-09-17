-- ═══════════════════════════════════════════════════════════════════════════
-- Rarity stat-budget re-curve (user 2026-09-07)
--
-- The per-rarity stat budget was flat: total base 270/275/280/285/290, only
-- +7% common->legendary, even though encounter rarity (60x) and catch
-- difficulty (up to 4x hits, 2x catch rate) already scale hard with rarity.
-- Re-curved to an accelerating ladder that reaches +30% common->legendary
-- (an initial +40% proposal was pulled back to +30% per user).
--
--   total:   270 / 284 / 302 / 324 / 351   (was 270/275/280/285/290)
--   vs common: -- / +5% / +12% / +20% / +30%
--
-- Only combatBase/workBase/combatGrowth/workGrowth per rarity change (growth
-- stays base/30, same as before). Attribute caps (combatMaxBase etc.),
-- catchRate, breed/hatch/heal timings and encounter weights are UNTOUCHED.
--
-- This merges into whatever the live 'species_balance' game_config row
-- already holds (jsonb_set on just these 4 keys per rarity), so any other
-- dev-tuned fields on that row (caps, catch rate, timings, ...) survive
-- untouched. If no row exists yet, the insert seeds an empty one first so the
-- merge below has something to write into -- the code defaults already cover
-- everything else in that case.
--
-- Run once in the Supabase SQL editor. Idempotent (plain assignment, not a
-- delta).
-- ═══════════════════════════════════════════════════════════════════════════

begin;

insert into public.game_config (key, value)
values ('species_balance', '{}'::jsonb)
on conflict (key) do nothing;

update public.game_config
set value = value
  || jsonb_build_object(
    'common', coalesce(value->'common', '{}'::jsonb) || jsonb_build_object(
      'combatBase', 131.3513513514,
      'workBase', 138.6486486486,
      'combatGrowth', 4.3783783784,
      'workGrowth', 4.6216216216
    ),
    'uncommon', coalesce(value->'uncommon', '{}'::jsonb) || jsonb_build_object(
      'combatBase', 138.1621621622,
      'workBase', 145.8378378378,
      'combatGrowth', 4.6054054054,
      'workGrowth', 4.8612612613
    ),
    'rare', coalesce(value->'rare', '{}'::jsonb) || jsonb_build_object(
      'combatBase', 146.9189189189,
      'workBase', 155.0810810811,
      'combatGrowth', 4.8972972973,
      'workGrowth', 5.1693693694
    ),
    'epic', coalesce(value->'epic', '{}'::jsonb) || jsonb_build_object(
      'combatBase', 157.6216216216,
      'workBase', 166.3783783784,
      'combatGrowth', 5.2540540541,
      'workGrowth', 5.5459459459
    ),
    'legendary', coalesce(value->'legendary', '{}'::jsonb) || jsonb_build_object(
      'combatBase', 170.7567567568,
      'workBase', 180.2432432432,
      'combatGrowth', 5.6918918919,
      'workGrowth', 6.0081081081
    )
  )
where key = 'species_balance';

commit;

-- Control: base totals per rarity, should read 270 / 284 / 302 / 324 / 351.
select
  r as rarity,
  round(((value -> r ->> 'combatBase')::numeric + (value -> r ->> 'workBase')::numeric), 2) as base_total
from public.game_config, unnest(array['common','uncommon','rare','epic','legendary']) as r
where key = 'species_balance';
