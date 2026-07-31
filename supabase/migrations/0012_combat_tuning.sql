-- Live combat-formula dials, editable in Dev Mode ▸ Balance (user request
-- 2026-07-17: tune attack power vs. defense, and simulate duels).
--
-- ONE global row (id = 'global') — this is a game-wide balance dial, not a
-- per-account setting. CombatEngine reads it on every hit; the dev tool
-- edits it. Loading tolerates the table being absent (see CombatTuning.load),
-- so applying this migration is what turns persistence on; before it, edits
-- are session-only.

create table if not exists public.combat_tuning (
  id text primary key,
  -- Global damage multiplier (was CombatEngine.damageScale = 0.55).
  damage_scale double precision not null default 0.55,
  -- Strength of defense mitigation in atk/(atk + def·w). 1.0 = calibrated
  -- default; >1 defense matters more; <1 attack dominates.
  defense_weight double precision not null default 1.0,
  updated_at timestamptz not null default now()
);

-- Seed the single row so the first load has something to read.
insert into public.combat_tuning (id) values ('global')
  on conflict (id) do nothing;

-- Same trusted-single-author model as the def tables: readable by everyone,
-- writable only by a dev account (profiles.is_dev). Mirrors the RLS the
-- building_defs/tech_defs tables use.
alter table public.combat_tuning enable row level security;

drop policy if exists combat_tuning_read on public.combat_tuning;
create policy combat_tuning_read on public.combat_tuning
  for select using (true);

drop policy if exists combat_tuning_write on public.combat_tuning;
create policy combat_tuning_write on public.combat_tuning
  for all
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_dev = true
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_dev = true
  ));
