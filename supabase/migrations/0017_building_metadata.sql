-- Per-building tunables that don't each warrant their own column: the per-era
-- max upgrade level, and the cost/time scaling factors. They all ride a single
-- jsonb `metadata` bag so BuildingDef can grow more per-building config later
-- without another migration (same reason workshops/bonuses ride `effects`).
--
-- Idempotent, mirrors 0008. Default '{}' matches the code's fromDefRow defaults:
-- empty maxLevelPerEra → the flat kMaxBuildingLevel; costFactor/timeFactor → 1.6.
alter table public.building_defs
  add column if not exists metadata jsonb not null default '{}'::jsonb;
