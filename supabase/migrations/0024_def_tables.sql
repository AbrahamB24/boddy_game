-- Create-table migrations for the Dev-Mode content tables that were originally
-- created OUTSIDE the migration history (building_defs / era_defs / species_defs
-- / ability_defs). Without these, a DB rebuilt purely from supabase/migrations/
-- has no def tables and the app runs on bundled fallbacks only.
--
-- Columns mirror each model's toDefRow(). Fully idempotent: `create table if not
-- exists` + `add column if not exists`, so running it on the existing DB (which
-- already has these tables) is a no-op. RLS mirrors area_defs: any authenticated
-- user READS content, only a dev (profiles.is_dev) WRITES.

-- ── building_defs ──────────────────────────────────────────
create table if not exists public.building_defs (id text primary key);
alter table public.building_defs
  add column if not exists name               text not null default '',
  add column if not exists image_url          text,
  add column if not exists color              text,
  add column if not exists grid_w             int not null default 1,
  add column if not exists grid_h             int not null default 1,
  add column if not exists resource_cost      jsonb not null default '{}'::jsonb,
  add column if not exists construction_hours double precision not null default 0,
  add column if not exists era_ids            jsonb not null default '[]'::jsonb,
  add column if not exists is_main_building   boolean not null default false,
  add column if not exists is_unique          boolean not null default false,
  add column if not exists is_road            boolean not null default false,
  add column if not exists is_build_plot      boolean not null default false,
  add column if not exists required_tech_id   text,
  add column if not exists population         int not null default 0,
  add column if not exists max_count          int not null default 0,
  add column if not exists effects            jsonb not null default '[]'::jsonb,
  add column if not exists metadata           jsonb not null default '{}'::jsonb;

-- ── era_defs ───────────────────────────────────────────────
create table if not exists public.era_defs (id text primary key);
alter table public.era_defs
  add column if not exists name             text not null default '',
  add column if not exists emoji            text,
  add column if not exists era_order        int not null default 1,
  add column if not exists advancement_cost jsonb not null default '{}'::jsonb,
  add column if not exists grant_resources  jsonb not null default '{}'::jsonb,
  add column if not exists effects          jsonb not null default '[]'::jsonb;

-- ── species_defs ───────────────────────────────────────────
create table if not exists public.species_defs (id text primary key);
alter table public.species_defs
  add column if not exists name        text not null default '',
  add column if not exists description text,
  add column if not exists element     text,
  add column if not exists rarity      text,
  add column if not exists role        text,
  add column if not exists catch_rate  double precision not null default 1,
  add column if not exists evo_level_1 int,
  add column if not exists evo_level_2 int,
  add column if not exists tier        int not null default 1,
  add column if not exists stats       jsonb not null default '{}'::jsonb,
  add column if not exists stages      jsonb not null default '[]'::jsonb,
  add column if not exists abilities   jsonb not null default '[]'::jsonb;

-- ── ability_defs ───────────────────────────────────────────
create table if not exists public.ability_defs (id text primary key);
alter table public.ability_defs
  add column if not exists name                  text not null default '',
  add column if not exists description           text,
  add column if not exists element               text,
  add column if not exists kind                  text,
  add column if not exists target                text,
  add column if not exists power                 int not null default 0,
  add column if not exists priority              int not null default 0,
  add column if not exists heal_pct              double precision not null default 0,
  add column if not exists lifesteal_pct         double precision not null default 0,
  add column if not exists inflict_main          text,
  add column if not exists inflict_main_chance   double precision not null default 0,
  add column if not exists inflict_debuff        text,
  add column if not exists inflict_debuff_chance double precision not null default 0,
  add column if not exists self_buff             text,
  add column if not exists self_penalty_stat     text,
  add column if not exists self_penalty_mult     double precision not null default 0,
  add column if not exists self_penalty_turns    int not null default 0,
  add column if not exists ap_cost               int not null default 0;

-- ── RLS: authenticated read, dev write (mirrors area_defs) ─
do $$
declare t text;
begin
  foreach t in array array['building_defs','era_defs','species_defs','ability_defs']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "%s read" on public.%I', t, t);
    execute format(
      'create policy "%s read" on public.%I for select using (auth.role() = ''authenticated'')',
      t, t);
    execute format('drop policy if exists "%s dev write" on public.%I', t, t);
    execute format(
      'create policy "%s dev write" on public.%I for all '
      'using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_dev = true)) '
      'with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_dev = true))',
      t, t);
  end loop;
end $$;
