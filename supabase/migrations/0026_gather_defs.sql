-- Per-RESOURCE gathering dials (user 2026-07-25), Dev-Mode-editable like
-- building_defs / item_defs. One row per resource:
--
--   units_per_carry            how many units ONE carry stat point brings home
--                              (bulk stacks, luxuries don't — this is what makes
--                              a wood run worth sending and a gold run a trickle)
--   seconds_per_unit_per_stat  how long ONE gather stat point needs for ONE unit
--   spot_capacity              how much a spot of this resource holds when full
--   regen_per_hour             how fast an untouched spot refills
--
-- These replace three fields that used to sit on EVERY resource spot inside
-- EVERY area (yield_per_hour / capacity / regen_per_hour in area_defs.spots) —
-- those keys are now ignored on read; a spot only says which resource is there.
-- Idempotent. RLS: authenticated read, dev (profiles.is_dev) write.

create table if not exists public.gather_defs (
  id                        text primary key,
  units_per_carry           double precision not null default 1,
  seconds_per_unit_per_stat double precision not null default 3000,
  spot_capacity             double precision not null default 0,
  regen_per_hour            double precision not null default 0
);

alter table public.gather_defs enable row level security;

drop policy if exists "gather_defs read" on public.gather_defs;
create policy "gather_defs read" on public.gather_defs
  for select using (auth.role() = 'authenticated');

drop policy if exists "gather_defs dev write" on public.gather_defs;
create policy "gather_defs dev write" on public.gather_defs
  for all
  using (exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.is_dev = true))
  with check (exists (select 1 from public.profiles p
                      where p.id = auth.uid() and p.is_dev = true));

-- Seed the bundled values so the Dev-Mode table isn't empty on first open.
-- `on conflict do nothing`: an already-tuned row is never overwritten.
insert into public.gather_defs
  (id, units_per_carry, seconds_per_unit_per_stat, spot_capacity, regen_per_hour)
values
  ('wood',  20,  3000, 1200, 120),
  ('stone', 20,  3000, 1000, 100),
  ('gold',   1, 20000,  120,  12),
  ('fish',   4,  9000,  300,  30),
  ('fur',    4,  9000,  240,  24)
on conflict (id) do nothing;
