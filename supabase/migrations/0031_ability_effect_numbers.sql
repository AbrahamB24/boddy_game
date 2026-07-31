-- Per-ABILITY duration and magnitude for its effects (user 2026-07-30: "Effekt
-- wählen (alle effekte in einer Liste), Dauer (0 default, falls es nicht auf
-- Zeit ist), Wert des Effekts (bsp wieviel HP burn verursacht)").
--
-- Until now the numbers lived in code as game-wide constants
-- (status_effects.dart), so every burn in the game was the same burn: two fire
-- moves could differ in power and in nothing else.
--
-- 0 = THE CATALOG DEFAULT, for every column below. That is what makes this a
-- pure addition: every existing ability row keeps behaving exactly as it did,
-- with no backfill, and a number typed in Dev Mode is visibly a decision
-- somebody made rather than a copy of the default.
--
-- The *_value columns hold a POSITIVE FRACTION of "how much" — damage per turn
-- for burn/poison, speed lost for frost, chance to lose the turn for fear,
-- accuracy lost for blind, the stat gained for a buff. Never a multiplier; see
-- AbilityEffectKind.valueLabel for the per-effect meaning.

alter table public.ability_defs
  add column if not exists inflict_main_turns integer not null default 0,
  add column if not exists inflict_main_value double precision not null default 0,
  add column if not exists inflict_debuff_turns integer not null default 0,
  add column if not exists inflict_debuff_value double precision not null default 0,
  add column if not exists self_buff_turns integer not null default 0,
  add column if not exists self_buff_value double precision not null default 0;
