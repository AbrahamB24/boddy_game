-- Multi-hit content (user 2026-09-08: "mehr Abwechslung... nicht nur 1
-- gegner treffen sondern 2 oder 3. Mehrere Attacken zu gewisser Chance (mit
-- jedem Treffer sinkt die Chance, noch einen Treffer zu landen)").
--
-- Two new columns on an EXISTING damage move, not a new AbilityKind: a move
-- either lands once (extra_hit_chance = 0, today's every move) or has a
-- chance to land one/two more hits. extra_hit_same_target picks which of the
-- two move types the user asked for as SEPARATE moves: true = a classic
-- multi-hit repeating on the one target (Serienangriff), false = a cleave
-- spreading onto a different living enemy each time.
--
-- 0 / false = the move behaves exactly as it does today. No backfill, no
-- behaviour change for any existing ability.

alter table public.ability_defs
  add column if not exists extra_hit_chance double precision not null default 0,
  add column if not exists extra_hit_same_target boolean not null default false;
