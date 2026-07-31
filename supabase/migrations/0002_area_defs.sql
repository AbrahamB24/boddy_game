-- Overworld AREA content, Dev-Mode-editable like building_defs / tech_defs /
-- era_defs / species_defs (see [[expedition-overworld-redesign]]). Run in the
-- Supabase SQL editor. Idempotent.
--
-- RLS below mirrors the "trusted single author" model used by the other def
-- tables: any authenticated user can READ the content (so every player loads
-- the same overworld), only a dev (profiles.is_dev) may WRITE. If your existing
-- *_defs tables use a different policy, align this one to match them.

create table if not exists public.area_defs (
  id              text primary key,
  name            text not null,
  emoji           text,
  area_order      integer not null default 1,
  description     text,
  battle_stage    integer not null default 1,
  danger_level    integer not null default 1,
  spots           jsonb not null default '[]'::jsonb,
  species_pool    jsonb not null default '[]'::jsonb,
  boss_species_id text
);

alter table public.area_defs enable row level security;

drop policy if exists "area_defs read" on public.area_defs;
create policy "area_defs read" on public.area_defs
  for select using (auth.role() = 'authenticated');

drop policy if exists "area_defs dev write" on public.area_defs;
create policy "area_defs dev write" on public.area_defs
  for all
  using (exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.is_dev = true))
  with check (exists (select 1 from public.profiles p
                      where p.id = auth.uid() and p.is_dev = true));
