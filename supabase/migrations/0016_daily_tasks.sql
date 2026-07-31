-- Daily tasks (user 2026-07-21): three rotating per-day goals with claimable
-- rewards. One jsonb blob on the settlement — the state is small ({date,
-- tasks[3]}) and never queried server-side, so a table would be ceremony.
alter table settlements
  add column if not exists daily_tasks jsonb;
