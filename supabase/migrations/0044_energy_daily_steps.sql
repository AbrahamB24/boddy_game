-- Energy becomes a DAILY STEPS FORMULA, not a draining pool (user 2026-09-14:
-- "es braucht 5000 Schritte pro Tag für 100%... für 1000 weitere Schritte,
-- gibt es mir 5% Boost auf alles, bis zu einem Maximum von 25%... es wird
-- immer um 00:00 abgerechnet für den nächsten Tag").
--
-- `current_energy` is DEAD from here on — nothing in the app reads or writes
-- it any more (EnergyModel.multiplier is a pure function of `steps_today`,
-- recomputed on every read, no time-based drain left to persist). Left in
-- place rather than dropped, same convention every other renamed/retired
-- column in this app follows (see rename_fur_to_meat.sql's own note) — it
-- costs nothing sitting unread, and dropping a column is not reversible.
--
-- `steps_today`/`steps_day_key` default to a fresh, never-walked-yet day
-- (0 steps, no day key) — every existing settlement reads at the floor rate
-- until it takes its first step under the new system, which is the correct,
-- unsurprising state for "a system that didn't exist yesterday".

alter table public.energy_state
  add column if not exists steps_today integer not null default 0,
  add column if not exists steps_day_key text not null default '';
