-- Authored overworld PATH content (user 2026-07-25), Dev-Mode-editable like
-- building_defs / era_defs / area_defs. Each row is one battle node on the
-- linear map path: its order, region, boss flag, concrete enemies and rewards.
-- Replaces the pure-formula path (overworld_path.dart). Run in the Supabase SQL
-- editor. Idempotent.
--
-- RLS mirrors the other def tables: any authenticated user READS the content
-- (every player loads the same path), only a dev (profiles.is_dev) may WRITE.

create table if not exists public.path_nodes (
  id          text primary key,
  name        text not null default '',
  node_order  integer not null default 0,
  area_id     text,
  is_boss     boolean not null default false,
  -- [{ "speciesId": "...", "level": N }, ...]  (empty = fall back to formula)
  enemies     jsonb not null default '[]'::jsonb,
  -- { "resources": {...}, "items": {itemId: n}, "buildings": [...],
  --   "features": [...], "expansions": N }   ("items" added 2026-07-25 — jsonb,
  --   so item loot needed no migration of its own)
  rewards     jsonb not null default '{}'::jsonb
);

-- Ordering is the field the editor reorders on; index it for the sorted load.
create index if not exists path_nodes_order_idx on public.path_nodes (node_order);

alter table public.path_nodes enable row level security;

drop policy if exists "path_nodes read" on public.path_nodes;
create policy "path_nodes read" on public.path_nodes
  for select using (auth.role() = 'authenticated');

drop policy if exists "path_nodes dev write" on public.path_nodes;
create policy "path_nodes dev write" on public.path_nodes
  for all
  using (exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.is_dev = true))
  with check (exists (select 1 from public.profiles p
                      where p.id = auth.uid() and p.is_dev = true));
