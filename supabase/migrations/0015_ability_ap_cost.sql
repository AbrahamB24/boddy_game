-- Author-set AP cost for abilities (user 2026-07-19: "Im Devmode muss ich
-- angeben können, wieviel AP eine Fähigkeit braucht").
--
-- 0 = AUTO: the game derives the cost from power/effects (the original rule),
-- so every existing row keeps its current cost with no backfill. A value > 0
-- is the exact cost the author wants (clamped 1..7 in code). Starting abilities
-- are additionally capped at 4 AP per unlock stage in Combatant._resolveAbilities,
-- not here.

alter table public.ability_defs
  add column if not exists ap_cost integer not null default 0;
