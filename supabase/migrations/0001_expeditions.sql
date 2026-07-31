-- Expedition system (Phase 3: gather) — see docs / [[expedition-overworld-redesign]].
-- Run this in the Supabase SQL editor (or via the CLI) before using expeditions.
-- Safe to re-run: everything is IF NOT EXISTS / idempotent.
--
-- NOTE: no change to the `creatures` table. A creature's expedition lock is
-- DERIVED at load time from active rows here (member_ids), not stored on the
-- creature — so existing creature saves keep working with or without this
-- migration applied.

-- ── expeditions ─────────────────────────────────────────────
-- One away-mission (gather/capture/battle). Only timed types (gather/capture)
-- are persisted as running jobs; battle is played inline and never stored.
create table if not exists public.expeditions (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  type             text not null,                 -- 'gather' | 'capture' | 'battle'
  area_id          text not null,
  target_id        text,                          -- spot id / species id / node id
  member_ids       jsonb not null default '[]'::jsonb,
  started_at       timestamptz not null default now(),
  duration_seconds integer not null default 0,
  state            text not null default 'active',
  payload          jsonb not null default '{}'::jsonb
);

create index if not exists expeditions_user_idx on public.expeditions (user_id);

alter table public.expeditions enable row level security;

drop policy if exists "own expeditions" on public.expeditions;
create policy "own expeditions" on public.expeditions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── resource_spot_states ────────────────────────────────────
-- Per-player depletion state of an area's resource spots. Only the mutable
-- stock + timestamp live here; capacity/regen come from the AreaDef content.
-- Regeneration is applied lazily on read (stock += regen_per_hour * elapsed,
-- clamped to capacity). A missing row means the spot is at full capacity.
create table if not exists public.resource_spot_states (
  user_id         uuid not null references auth.users (id) on delete cascade,
  spot_id         text not null,
  stock           double precision not null default 0,
  last_updated_at timestamptz not null default now(),
  primary key (user_id, spot_id)
);

alter table public.resource_spot_states enable row level security;

drop policy if exists "own spot states" on public.resource_spot_states;
create policy "own spot states" on public.resource_spot_states
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
