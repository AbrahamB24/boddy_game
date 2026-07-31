-- Global game config (single-author dev tuning), one row per key.
-- First use: 'species_balance' — the per-rarity combat/civil point budgets and
-- the per-attribute max base caps the stat-budget system reads (see
-- lib/features/creatures/models/species_balance.dart).
create table if not exists public.game_config (
  key   text primary key,
  value jsonb not null default '{}'::jsonb
);

alter table public.game_config enable row level security;

-- Shared, dev-authored content like the def tables: everyone reads it, the
-- signed-in author writes it (single trusted author, same convention).
drop policy if exists "read game_config" on public.game_config;
create policy "read game_config" on public.game_config
  for select using (true);

drop policy if exists "write game_config" on public.game_config;
create policy "write game_config" on public.game_config
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');
