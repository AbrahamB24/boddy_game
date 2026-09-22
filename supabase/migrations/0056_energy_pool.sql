-- Energy is a POOL again (user 2026-09-20: "Energie wieder direktes Feedback.
-- Wenn ich Schritte mache, dann soll die Energie hochgehen … und es geht wirklich
-- runter auf 0"): steps fill it, time empties it — 5000 steps = 100 %, up to
-- 125 % at 10 000; 100 % lasts 24 h, so 125 % lasts 30 h. See energyAfterSteps /
-- energyDrain in building_definitions.dart.
--
-- `energy_pct` is what is in the pool as of `last_updated_at` (0 – 125); the
-- app drains it forward from there on every tick, including the catch-up after
-- the app was closed. Every existing settlement starts FULL (one day) — the
-- pool did not exist yesterday, and starting anyone at empty would be a
-- punishment for a change they did not ask for.
--
-- `steps_today` / `steps_day_key` stay: they are the "N steps today" readout now
-- and decide nothing. `current_energy` (dead since 0044) is still left alone.

alter table public.energy_state
  add column if not exists energy_pct double precision not null default 100;
