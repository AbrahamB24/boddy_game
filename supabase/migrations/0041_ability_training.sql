-- Combat School: ability training (user 2026-09-05).
--
-- Evolution no longer grants a move by itself. What a creature knows is now
-- trained by hand at the Combat School and stays known forever
-- (learned_ability_ids); only up to 6 of those are battle-usable at once
-- (equipped_ability_ids). What a move may be learned FROM is now a property
-- of the move itself (unlock_stage on ability_defs), replacing the old
-- per-species SpeciesAbility.unlockStage.
--
-- learned_ability_ids/equipped_ability_ids are left NULL here on purpose —
-- that NULL is the "needs backfill" sentinel CreatureInstance.
-- needsAbilityBackfill checks. A one-time Dart-side pass (CreaturesController
-- ._backfillAbilities, called from load()) fills every existing creature in
-- with exactly what the OLD species+stage rule already granted it, so
-- nobody's team goes silent the moment this ships. No SQL-side backfill is
-- possible here — that content lives in kSpeciesDefs/kAbilityDefs, not in
-- SQL.

alter table ability_defs add column if not exists unlock_stage int not null default 0;

alter table creatures add column if not exists learned_ability_ids jsonb;
alter table creatures add column if not exists equipped_ability_ids jsonb;
alter table creatures add column if not exists training_ability_id text;
alter table creatures add column if not exists training_until timestamptz;
alter table creatures add column if not exists train_queued_at timestamptz;
