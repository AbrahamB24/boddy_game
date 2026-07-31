-- ═══════════════════════════════════════════════════════════════════════════
-- Bøddy Game — SQL nachziehen (Stand 2026-07-25, Item-System Phase 1–3)
-- Im Supabase SQL-Editor als EIN Skript ausführen.
--
-- TEIL A (Migrationen 0019–0026) ist vollständig IDEMPOTENT: jede Anweisung ist
--   "if not exists" / "if exists", mehrfaches Ausführen ist ein No-op. Nichts
--   davon löscht Spielerdaten. Die zwei drop-table betreffen nur die toten
--   Tech-Tabellen (Forschung wurde entfernt).
-- TEIL B (Gebäude-Roster) ist NICHT harmlos: es macht zuerst
--   "delete from building_defs" und schreibt den Code-Stand (86 Gebäude,
--   inkl. Handelscenter). Alle im Dev-Tool gemachten Gebäude-Änderungen sind
--   danach durch den Code-Stand ersetzt. Wenn du das nicht willst: nur Teil A
--   ausführen — das Handelscenter funktioniert dann über den Code-Fallback,
--   ist aber nicht in Dev Mode → Gebäude editierbar.
--
-- Für Phase 3 selbst war KEINE neue Migration nötig (Item-Loot liegt in
-- path_nodes.rewards, der trade-Effekt in building_defs.effects — beides jsonb).
-- ═══════════════════════════════════════════════════════════════════════════


-- ███████████████████████████████████████████████████████████████████████████
-- TEIL A — Migrationen 0019 bis 0025
-- ███████████████████████████████████████████████████████████████████████████




-- ───────────────────────────────────────────────────────────────────────────
-- 0019_battles_cleared.sql
-- ───────────────────────────────────────────────────────────────────────────
-- Linear-path progression (user 2026-07-24): the overworld is now ONE line of
-- numbered battles. `battles_cleared` is how far along that line the player has
-- won — it replaces the coarse dungeon_max_stage (region 1/2/3) as the fine
-- progress counter that drives party size (partySizeForBattle) and, later,
-- building/legendary unlocks by map milestone.
--
-- `profiles` is shared with the fitness app and already holds real players, so
-- default 0 backfills every existing row as "no campaign battles won yet" — the
-- correct starting state for everyone. dungeon_max_stage stays for now as the
-- era/region counter until the linear rebuild fully retires it.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'battles_cleared'
  ) then
    alter table public.profiles
      add column battles_cleared int not null default 0;
  end if;
end $$;


-- ───────────────────────────────────────────────────────────────────────────
-- 0020_breeding_status.sql
-- ───────────────────────────────────────────────────────────────────────────
-- Two-phase breeding → egg → hatch (user 2026-07-24). Breeding no longer rolls
-- the child directly: a finished mating lays an EGG that sits free (parents
-- released), and the player must later place that egg into a Hatchery, where
-- stationed breeders incubate it a second time before it hatches.
--
-- One column carries the whole lifecycle on the existing breeding_jobs row:
--   'breeding' — parents locked, incubating in the Breeding Hut (ready_at = lay)
--   'egg'      — laid, parents freed, waiting for a Hatchery slot (no timer)
--   'hatching' — placed in the Hatchery, incubating again (ready_at = hatch)
-- Existing rows default to 'breeding', i.e. their old meaning, so nothing in
-- flight is lost by the migration.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'breeding_jobs'
      and column_name = 'status'
  ) then
    alter table public.breeding_jobs
      add column status text not null default 'breeding';
  end if;
end $$;


-- ───────────────────────────────────────────────────────────────────────────
-- 0021_drop_tech_defs.sql
-- ───────────────────────────────────────────────────────────────────────────
-- Drop the tech system (user 2026-07-25). Techs and the Dev-Mode Tech tab were
-- removed; the feature unlocks they used to gate (evolution / breeding / longer
-- hunts / more expedition slots) are earned by map progress now
-- (progression_unlocks.dart) and will become authored path-node rewards.
--
-- Safe/idempotent: `if exists` so re-running never errors. The legacy
-- `research_unlocks` table is intentionally KEPT — SettlementController still
-- reads it on load so a veteran's already-unlocked features survive; nothing
-- writes it any more.
drop table if exists public.tech_defs cascade;


-- ───────────────────────────────────────────────────────────────────────────
-- 0022_path_nodes.sql
-- ───────────────────────────────────────────────────────────────────────────
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


-- ───────────────────────────────────────────────────────────────────────────
-- 0023_drop_tech_gates.sql
-- ───────────────────────────────────────────────────────────────────────────
-- Drop the dead `tech_gates` table (user 2026-07-25). It backed the old
-- research-trial gates; research is gone (feature unlocks come from map progress
-- / authored path nodes now), and no code reads or writes it any more. The reset
-- flow no longer wipes it either. Idempotent.
drop table if exists public.tech_gates cascade;


-- ───────────────────────────────────────────────────────────────────────────
-- 0024_def_tables.sql
-- ───────────────────────────────────────────────────────────────────────────
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


-- ───────────────────────────────────────────────────────────────────────────
-- 0025_item_defs.sql
-- ───────────────────────────────────────────────────────────────────────────
-- Craftable / tradeable ITEM content, Dev-Mode-editable like building_defs /
-- area_defs / path_nodes (user 2026-07-25). Columns mirror ItemDef.toDefRow().
-- Idempotent. RLS: authenticated read, dev (profiles.is_dev) write.

create table if not exists public.item_defs (
  id            text primary key,
  name          text not null default '',
  emoji         text,
  description   text,
  kind          text not null default 'heal',
  magnitude     double precision not null default 0,
  buff_stat     text,
  battle_usable boolean not null default false,
  -- {goodId: amount} — the concrete luxury ingredients a recipe consumes.
  ingredients   jsonb not null default '{}'::jsonb,
  supply_cost   double precision not null default 0,
  craft_seconds double precision not null default 0,
  buy_price     int not null default 0,
  sell_price    int not null default 0
);

alter table public.item_defs enable row level security;

drop policy if exists "item_defs read" on public.item_defs;
create policy "item_defs read" on public.item_defs
  for select using (auth.role() = 'authenticated');

drop policy if exists "item_defs dev write" on public.item_defs;
create policy "item_defs dev write" on public.item_defs
  for all
  using (exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.is_dev = true))
  with check (exists (select 1 from public.profiles p
                      where p.id = auth.uid() and p.is_dev = true));


-- ───────────────────────────────────────────────────────────────────────────
-- 0026_gather_defs.sql
-- ───────────────────────────────────────────────────────────────────────────
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


-- ███████████████████████████████████████████████████████████████████████████
-- TEIL B — Gebäude-Roster (86 Gebäude, generiert aus kFallbackBuildingDefs)
-- ACHTUNG: löscht zuerst ALLE building_defs-Zeilen. Nur ausführen, wenn der
-- Code-Roster gewinnen soll. Stand 2026-07-25: enthält die neuen Arbeitsplätze
-- (Heilhütte→medicine, Handelscenter→trade, Lager→carry, Späher→speed, Räucherei→gathering)
-- und die Produktionsgebäude auf dem neuen `production`-Stat. Deine eigenen
-- Dev-Mode-Änderungen an Gebäuden gehen dabei verloren.
-- ███████████████████████████████████████████████████████████████████████████
-- ═══════════════════════════════════════════════════════════════════════════
-- Bøddy — building roster, generated from kFallbackBuildingDefs.
-- Paste into the Supabase SQL editor. REPLACES every building def.
-- 86 buildings.
-- ═══════════════════════════════════════════════════════════════════════════
-- Ensure every column toDefRow() writes exists (idempotent — mirrors migration
-- 0024_def_tables.sql). Fixes "column metadata does not exist".
alter table public.building_defs
  add column if not exists image_url          text,
  add column if not exists color              text,
  add column if not exists grid_w             int  not null default 1,
  add column if not exists grid_h             int  not null default 1,
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

begin;
delete from public.building_defs;
insert into public.building_defs
  (id, name, image_url, color, grid_w, grid_h, resource_cost, construction_hours, era_ids, is_main_building, is_unique, is_road, is_build_plot, required_tech_id, population, max_count, effects, metadata)
values
  ('main_hall', 'Tribal Center', NULL, 'FF7C5CBF', 5, 5, '{}'::jsonb, 0.0, '[]'::jsonb, true, true, false, false, NULL, 5, 1, '[{"type":"production","key":"wood","value":6.0},{"type":"production","key":"stone","value":4.0}]'::jsonb, '{"costFactor":1.6,"timeFactor":1.6}'::jsonb),
  ('road', 'Road', NULL, 'FF6B6455', 1, 1, '{}'::jsonb, 0.0, '[]'::jsonb, false, false, true, false, NULL, 0, 0, '[]'::jsonb, '{"costFactor":1.6,"timeFactor":1.6}'::jsonb),
  ('building_plot', 'Building Plot', NULL, 'FF8D6E4A', 5, 5, '{"wood":350.0}'::jsonb, 0.0, '["era_1"]'::jsonb, false, false, false, true, NULL, 0, 0, '[]'::jsonb, '{"costFactor":1.6,"timeFactor":1.6}'::jsonb),
  ('wood_camp_e1', 'Primitive Wood Camp', NULL, 'FF6B8E4E', 3, 3, '{"wood":120.0,"stone":80.0}'::jsonb, 0.1, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"wood","mult":0.5,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"1":10,"2":10,"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":120.0,"stone":80.0},"2":{"wood":168.0,"stone":112.0,"frame":20.0,"clay":10.0},"3":{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0},"4":{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0},"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('wood_works_e1', 'Primitive Wood Works', NULL, 'FF6B8E4E', 4, 4, '{"wood":192.0,"stone":128.0}'::jsonb, 0.16666666666666666, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"wood","mult":0.8,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"1":10,"2":10,"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":192.0,"stone":128.0},"2":{"wood":269.0,"stone":179.0,"frame":32.0,"clay":16.0},"3":{"wood":376.0,"stone":251.0,"daub":29.0,"lime":14.0},"4":{"wood":527.0,"stone":351.0,"plaster":26.0,"ore":13.0},"5":{"wood":738.0,"stone":492.0,"truss":23.0,"coal":12.0},"6":{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0},"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('stone_camp_e1', 'Primitive Stone Camp', NULL, 'FF7A8288', 3, 3, '{"wood":120.0,"stone":80.0}'::jsonb, 0.1, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"stone","mult":0.5,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"1":10,"2":10,"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":120.0,"stone":80.0},"2":{"wood":168.0,"stone":112.0,"frame":20.0,"clay":10.0},"3":{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0},"4":{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0},"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('stone_works_e1', 'Primitive Stone Works', NULL, 'FF7A8288', 4, 4, '{"wood":192.0,"stone":128.0}'::jsonb, 0.16666666666666666, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"stone","mult":0.8,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"1":10,"2":10,"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":192.0,"stone":128.0},"2":{"wood":269.0,"stone":179.0,"frame":32.0,"clay":16.0},"3":{"wood":376.0,"stone":251.0,"daub":29.0,"lime":14.0},"4":{"wood":527.0,"stone":351.0,"plaster":26.0,"ore":13.0},"5":{"wood":738.0,"stone":492.0,"truss":23.0,"coal":12.0},"6":{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0},"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('hut', 'Hut', NULL, 'FF795548', 2, 2, '{"wood":84.0,"stone":56.0}'::jsonb, 0.08333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 12, 0, '[]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":84.0,"stone":56.0},"2":{"wood":118.0,"stone":78.0,"frame":14.0,"clay":7.0},"3":{"wood":165.0,"stone":110.0,"daub":13.0,"lime":6.0},"4":{"wood":230.0,"stone":154.0,"plaster":11.0,"ore":6.0},"5":{"wood":323.0,"stone":215.0,"truss":10.0,"coal":5.0},"6":{"wood":452.0,"stone":301.0,"clinker":9.0,"sand":5.0},"7":{"wood":632.0,"stone":422.0,"glasswork":8.0,"crystal":4.0},"8":{"wood":885.0,"stone":590.0,"vault":7.0,"aether":4.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('house', 'Longhouse', NULL, 'FF795548', 2, 5, '{"wood":132.0,"stone":88.0}'::jsonb, 0.08333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 17, 0, '[]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":132.0,"stone":88.0},"2":{"wood":185.0,"stone":123.0,"frame":22.0,"clay":11.0},"3":{"wood":259.0,"stone":172.0,"daub":20.0,"lime":10.0},"4":{"wood":362.0,"stone":241.0,"plaster":18.0,"ore":9.0},"5":{"wood":507.0,"stone":338.0,"truss":16.0,"coal":8.0},"6":{"wood":710.0,"stone":473.0,"clinker":14.0,"sand":7.0},"7":{"wood":994.0,"stone":663.0,"glasswork":13.0,"crystal":6.0},"8":{"wood":1391.0,"stone":928.0,"vault":12.0,"aether":6.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_fish', '🐟 Fish Hut', NULL, 'FF8D6E4A', 3, 2, '{"wood":108.0,"stone":72.0}'::jsonb, 0.1, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"fish","mult":0.1,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":108.0,"stone":72.0},"2":{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0},"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_fur', '🦫 Fur Lodge', NULL, 'FF8D6E4A', 3, 2, '{"wood":108.0,"stone":72.0}'::jsonb, 0.1, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"fur","mult":0.1,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":108.0,"stone":72.0},"2":{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0},"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e1', 'Primitive Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":360.0,"stone":240.0}'::jsonb, 0.25, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":3.0},{"type":"production","key":"stone","value":3.0}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":360.0,"stone":240.0},"2":{"wood":504.0,"stone":336.0,"frame":60.0,"clay":30.0},"3":{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0},"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e1', 'Primitive Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":360.0,"stone":240.0}'::jsonb, 0.25, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":4.0},{"type":"production","key":"fish","value":1.5},{"type":"production","key":"fur","value":1.5}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":360.0,"stone":240.0},"2":{"wood":504.0,"stone":336.0,"frame":60.0,"clay":30.0},"3":{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0},"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('builder_camp', 'Builder Camp', NULL, 'FF546E7A', 3, 4, '{"wood":144.0,"stone":96.0}'::jsonb, 0.13333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"construction","resource":"construction","mult":30.0,"slots":8},{"type":"queueSlots","value":1.0}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":144.0,"stone":96.0},"2":{"wood":202.0,"stone":134.0,"frame":24.0,"clay":12.0},"3":{"wood":282.0,"stone":188.0,"daub":22.0,"lime":11.0},"4":{"wood":395.0,"stone":263.0,"plaster":19.0,"ore":10.0},"5":{"wood":553.0,"stone":369.0,"truss":17.0,"coal":9.0},"6":{"wood":774.0,"stone":516.0,"clinker":16.0,"sand":8.0},"7":{"wood":1084.0,"stone":723.0,"glasswork":14.0,"crystal":7.0},"8":{"wood":1518.0,"stone":1012.0,"vault":13.0,"aether":6.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('healing_hut', 'Healing Hut', NULL, 'FF4FAE6B', 2, 3, '{"wood":72.0,"stone":48.0}'::jsonb, 0.03333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 1, '[{"type":"workshop","stat":"medicine","resource":"heal_speed","mult":0.003,"slots":2},{"type":"healSlots","value":2.0,"levelSteps":{"3":1.0,"6":1.0}}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":72.0,"stone":48.0},"2":{"wood":101.0,"stone":67.0,"frame":12.0,"clay":6.0},"3":{"wood":141.0,"stone":94.0,"daub":11.0,"lime":5.0},"4":{"wood":198.0,"stone":132.0,"plaster":10.0,"ore":5.0},"5":{"wood":277.0,"stone":184.0,"truss":9.0,"coal":4.0},"6":{"wood":387.0,"stone":258.0,"clinker":8.0,"sand":4.0},"7":{"wood":542.0,"stone":361.0,"glasswork":7.0,"crystal":4.0},"8":{"wood":759.0,"stone":506.0,"vault":6.0,"aether":3.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('trading_post', 'Trade Center', NULL, 'FFC9A227', 3, 3, '{"wood":120.0,"stone":80.0}'::jsonb, 0.08333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 1, '[{"type":"workshop","stat":"trade","resource":"trade_rate","mult":0.002,"slots":2},{"type":"trade","value":5.0}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":120.0,"stone":80.0},"2":{"wood":168.0,"stone":112.0,"frame":20.0,"clay":10.0},"3":{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0},"4":{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0},"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('breeding_hut', 'Breeding Hut', NULL, 'FFE91E63', 3, 4, '{"wood":108.0,"stone":72.0}'::jsonb, 0.08333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 1, '[{"type":"workshop","stat":"breeding","resource":"breeding","mult":1.0,"slots":2},{"type":"breeding","value":1.0},{"type":"xp","value":10.0}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":108.0,"stone":72.0},"2":{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0},"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('hatchery', 'Hatchery', NULL, 'FFF06292', 3, 3, '{"wood":108.0,"stone":72.0}'::jsonb, 0.08333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 1, '[{"type":"workshop","stat":"breeding","resource":"breeding","mult":1.0,"slots":2},{"type":"breeding","value":1.0},{"type":"xp","value":10.0}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":108.0,"stone":72.0},"2":{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0},"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('clay_camp_e2', 'Clay Clay Camp', NULL, 'FFB5651D', 3, 3, '{"wood":168.0,"stone":112.0,"frame":20.0,"clay":10.0}'::jsonb, 0.12, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"clay","mult":0.8,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"2":10,"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":168.0,"stone":112.0,"frame":20.0,"clay":10.0},"3":{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0},"4":{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0},"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('clay_works_e2', 'Clay Clay Works', NULL, 'FFB5651D', 4, 4, '{"wood":269.0,"stone":179.0,"frame":32.0,"clay":16.0}'::jsonb, 0.2, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"clay","mult":1.3,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"2":10,"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":269.0,"stone":179.0,"frame":32.0,"clay":16.0},"3":{"wood":376.0,"stone":251.0,"daub":29.0,"lime":14.0},"4":{"wood":527.0,"stone":351.0,"plaster":26.0,"ore":13.0},"5":{"wood":738.0,"stone":492.0,"truss":23.0,"coal":12.0},"6":{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0},"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('refinery_e2', 'Clay Refinery', NULL, 'FF5C6BC0', 4, 4, '{"wood":235.0,"stone":157.0,"frame":28.0,"clay":14.0}'::jsonb, 0.24, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"frame","mult":0.3,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"2":10,"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":235.0,"stone":157.0,"frame":28.0,"clay":14.0},"3":{"wood":329.0,"stone":220.0,"daub":25.0,"lime":13.0},"4":{"wood":461.0,"stone":307.0,"plaster":23.0,"ore":11.0},"5":{"wood":645.0,"stone":430.0,"truss":20.0,"coal":10.0},"6":{"wood":904.0,"stone":602.0,"clinker":18.0,"sand":9.0},"7":{"wood":1265.0,"stone":843.0,"glasswork":17.0,"crystal":8.0},"8":{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_a_e2', 'Clay Den', NULL, 'FF795548', 3, 4, '{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0}'::jsonb, 0.1, '["era_2"]'::jsonb, false, false, false, false, NULL, 25, 0, '[]'::jsonb, '{"maxLevelPerEra":{"2":3,"3":6,"4":9,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0},"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_b_e2', 'Clay Roost', NULL, 'FF795548', 3, 5, '{"wood":218.0,"stone":146.0,"frame":26.0,"clay":13.0}'::jsonb, 0.1, '["era_2"]'::jsonb, false, false, false, false, NULL, 35, 0, '[]'::jsonb, '{"maxLevelPerEra":{"2":3,"3":6,"4":9,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":218.0,"stone":146.0,"frame":26.0,"clay":13.0},"3":{"wood":306.0,"stone":204.0,"daub":23.0,"lime":12.0},"4":{"wood":428.0,"stone":285.0,"plaster":21.0,"ore":11.0},"5":{"wood":599.0,"stone":400.0,"truss":19.0,"coal":9.0},"6":{"wood":839.0,"stone":559.0,"clinker":17.0,"sand":9.0},"7":{"wood":1175.0,"stone":783.0,"glasswork":15.0,"crystal":8.0},"8":{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_herbs', '🌿 Herbs Garden', NULL, 'FF8D6E4A', 3, 2, '{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0}'::jsonb, 0.12, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"herbs","mult":0.2,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"2":3,"3":6,"4":9,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0},"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_honey', '🍯 Honey Apiary', NULL, 'FF8D6E4A', 3, 2, '{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0}'::jsonb, 0.12, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"honey","mult":0.2,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"2":3,"3":6,"4":9,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":151.0,"stone":101.0,"frame":18.0,"clay":9.0},"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e2', 'Clay Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":504.0,"stone":336.0,"frame":60.0,"clay":30.0}'::jsonb, 0.3, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":4.8,"era":2},{"type":"production","key":"stone","value":4.8,"era":2},{"type":"production","key":"clay","value":3.2,"era":2},{"type":"production","key":"frame","value":2.4,"era":2}]'::jsonb, '{"maxLevelPerEra":{"2":3,"3":6,"4":9,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":504.0,"stone":336.0,"frame":60.0,"clay":30.0},"3":{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0},"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e2', 'Clay Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":504.0,"stone":336.0,"frame":60.0,"clay":30.0}'::jsonb, 0.3, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":6.4,"era":2},{"type":"production","key":"herbs","value":2.4,"era":2},{"type":"production","key":"honey","value":2.4,"era":2}]'::jsonb, '{"maxLevelPerEra":{"2":3,"3":6,"4":9,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":504.0,"stone":336.0,"frame":60.0,"clay":30.0},"3":{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0},"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('thinker_circle', 'Workshop', NULL, 'FF5C6BC0', 3, 3, '{"wood":202.0,"stone":134.0,"frame":24.0,"clay":12.0}'::jsonb, 0.16, '["era_2"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"research","mult":40.0,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"2":3,"3":6,"4":9,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"2":{"wood":202.0,"stone":134.0,"frame":24.0,"clay":12.0},"3":{"wood":282.0,"stone":188.0,"daub":22.0,"lime":11.0},"4":{"wood":395.0,"stone":263.0,"plaster":19.0,"ore":10.0},"5":{"wood":553.0,"stone":369.0,"truss":17.0,"coal":9.0},"6":{"wood":774.0,"stone":516.0,"clinker":16.0,"sand":8.0},"7":{"wood":1084.0,"stone":723.0,"glasswork":14.0,"crystal":7.0},"8":{"wood":1518.0,"stone":1012.0,"vault":13.0,"aether":6.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('scout_post', 'Scout Post', NULL, 'FF7E9E5B', 2, 2, '{"wood":84.0,"stone":56.0}'::jsonb, 0.08333333333333333, '["era_1"]'::jsonb, false, false, false, false, NULL, 0, 2, '[{"type":"workshop","stat":"speed","resource":"exp_travel","mult":0.002,"slots":2},{"type":"huntOptions","value":1.0,"levelSteps":{"2":1.0,"3":1.0,"5":1.0,"7":1.0}},{"type":"expeditionSlots","value":1.0,"levelSteps":{"4":1.0,"8":1.0}}]'::jsonb, '{"maxLevelPerEra":{"1":3,"2":6,"3":9,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"1":{"wood":84.0,"stone":56.0},"2":{"wood":118.0,"stone":78.0,"frame":14.0,"clay":7.0},"3":{"wood":165.0,"stone":110.0,"daub":13.0,"lime":6.0},"4":{"wood":230.0,"stone":154.0,"plaster":11.0,"ore":6.0},"5":{"wood":323.0,"stone":215.0,"truss":10.0,"coal":5.0},"6":{"wood":452.0,"stone":301.0,"clinker":9.0,"sand":5.0},"7":{"wood":632.0,"stone":422.0,"glasswork":8.0,"crystal":4.0},"8":{"wood":885.0,"stone":590.0,"vault":7.0,"aether":4.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lime_camp_e3', 'Terracotta Lime Camp', NULL, 'FFB5651D', 3, 3, '{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0}'::jsonb, 0.144, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"lime","mult":1.3,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0},"4":{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0},"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lime_works_e3', 'Terracotta Lime Works', NULL, 'FFB5651D', 4, 4, '{"wood":376.0,"stone":251.0,"daub":29.0,"lime":14.0}'::jsonb, 0.24, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"lime","mult":2.0,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":376.0,"stone":251.0,"daub":29.0,"lime":14.0},"4":{"wood":527.0,"stone":351.0,"plaster":26.0,"ore":13.0},"5":{"wood":738.0,"stone":492.0,"truss":23.0,"coal":12.0},"6":{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0},"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('refinery_e3', 'Terracotta Refinery', NULL, 'FF5C6BC0', 4, 4, '{"wood":329.0,"stone":220.0,"daub":25.0,"lime":13.0}'::jsonb, 0.288, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"daub","mult":0.5,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"3":10,"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":329.0,"stone":220.0,"daub":25.0,"lime":13.0},"4":{"wood":461.0,"stone":307.0,"plaster":23.0,"ore":11.0},"5":{"wood":645.0,"stone":430.0,"truss":20.0,"coal":10.0},"6":{"wood":904.0,"stone":602.0,"clinker":18.0,"sand":9.0},"7":{"wood":1265.0,"stone":843.0,"glasswork":17.0,"crystal":8.0},"8":{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_a_e3', 'Terracotta Den', NULL, 'FF795548', 3, 4, '{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0}'::jsonb, 0.12, '["era_3"]'::jsonb, false, false, false, false, NULL, 35, 0, '[]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_b_e3', 'Terracotta Roost', NULL, 'FF795548', 3, 5, '{"wood":306.0,"stone":204.0,"daub":23.0,"lime":12.0}'::jsonb, 0.12, '["era_3"]'::jsonb, false, false, false, false, NULL, 49, 0, '[]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":306.0,"stone":204.0,"daub":23.0,"lime":12.0},"4":{"wood":428.0,"stone":285.0,"plaster":21.0,"ore":11.0},"5":{"wood":599.0,"stone":400.0,"truss":19.0,"coal":9.0},"6":{"wood":839.0,"stone":559.0,"clinker":17.0,"sand":9.0},"7":{"wood":1175.0,"stone":783.0,"glasswork":15.0,"crystal":8.0},"8":{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_cheese', '🧀 Cheese Dairy', NULL, 'FF8D6E4A', 3, 2, '{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0}'::jsonb, 0.144, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"cheese","mult":0.3,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_wine', '🍷 Wine Vineyard', NULL, 'FF8D6E4A', 3, 2, '{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0}'::jsonb, 0.144, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"wine","mult":0.3,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e3', 'Terracotta Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0}'::jsonb, 0.36, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":7.7,"era":3},{"type":"production","key":"stone","value":7.7,"era":3},{"type":"production","key":"clay","value":5.1,"era":3},{"type":"production","key":"lime","value":5.1,"era":3},{"type":"production","key":"daub","value":3.8,"era":3}]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0},"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e3', 'Terracotta Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0}'::jsonb, 0.36, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":10.2,"era":3},{"type":"production","key":"cheese","value":3.8,"era":3},{"type":"production","key":"wine","value":3.8,"era":3}]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":706.0,"stone":470.0,"daub":54.0,"lime":27.0},"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('training_grounds', 'Training Grounds', NULL, 'FFD84315', 3, 3, '{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0}'::jsonb, 0.144, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 1, '[{"type":"workshop","stat":"construction","resource":"training","mult":0.0,"slots":4}]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":235.0,"stone":157.0,"daub":18.0,"lime":9.0},"4":{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0},"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('warehouse', 'Warehouse', NULL, 'FF8D6E63', 2, 2, '{"wood":188.0,"stone":125.0,"daub":14.0,"lime":7.0}'::jsonb, 0.12, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 3, '[{"type":"workshop","stat":"carry","resource":"exp_carry","mult":0.003,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":188.0,"stone":125.0,"daub":14.0,"lime":7.0},"4":{"wood":263.0,"stone":176.0,"plaster":13.0,"ore":6.0},"5":{"wood":369.0,"stone":246.0,"truss":12.0,"coal":6.0},"6":{"wood":516.0,"stone":344.0,"clinker":10.0,"sand":5.0},"7":{"wood":723.0,"stone":482.0,"glasswork":9.0,"crystal":5.0},"8":{"wood":1012.0,"stone":675.0,"vault":9.0,"aether":4.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('smokehouse', 'Smokehouse', NULL, 'FFB55E36', 2, 2, '{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0}'::jsonb, 0.12, '["era_3"]'::jsonb, false, false, false, false, NULL, 0, 2, '[{"type":"workshop","stat":"gathering","resource":"exp_goods","mult":0.003,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"3":3,"4":6,"5":9,"6":10,"7":10,"8":10},"costPerEra":{"3":{"wood":212.0,"stone":141.0,"daub":16.0,"lime":8.0},"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('ore_camp_e4', 'Plaster Ore Camp', NULL, 'FFB5651D', 3, 3, '{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0}'::jsonb, 0.1728, '["era_4"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"ore","mult":2.0,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"4":{"wood":329.0,"stone":220.0,"plaster":16.0,"ore":8.0},"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('ore_works_e4', 'Plaster Ore Works', NULL, 'FFB5651D', 4, 4, '{"wood":527.0,"stone":351.0,"plaster":26.0,"ore":13.0}'::jsonb, 0.288, '["era_4"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"ore","mult":3.3,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"4":{"wood":527.0,"stone":351.0,"plaster":26.0,"ore":13.0},"5":{"wood":738.0,"stone":492.0,"truss":23.0,"coal":12.0},"6":{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0},"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('refinery_e4', 'Plaster Refinery', NULL, 'FF5C6BC0', 4, 4, '{"wood":461.0,"stone":307.0,"plaster":23.0,"ore":11.0}'::jsonb, 0.3456, '["era_4"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"plaster","mult":0.8,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"4":10,"5":10,"6":10,"7":10,"8":10},"costPerEra":{"4":{"wood":461.0,"stone":307.0,"plaster":23.0,"ore":11.0},"5":{"wood":645.0,"stone":430.0,"truss":20.0,"coal":10.0},"6":{"wood":904.0,"stone":602.0,"clinker":18.0,"sand":9.0},"7":{"wood":1265.0,"stone":843.0,"glasswork":17.0,"crystal":8.0},"8":{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_a_e4', 'Plaster Den', NULL, 'FF795548', 3, 4, '{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0}'::jsonb, 0.144, '["era_4"]'::jsonb, false, false, false, false, NULL, 50, 0, '[]'::jsonb, '{"maxLevelPerEra":{"4":3,"5":6,"6":9,"7":10,"8":10},"costPerEra":{"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_b_e4', 'Plaster Roost', NULL, 'FF795548', 3, 5, '{"wood":428.0,"stone":285.0,"plaster":21.0,"ore":11.0}'::jsonb, 0.144, '["era_4"]'::jsonb, false, false, false, false, NULL, 70, 0, '[]'::jsonb, '{"maxLevelPerEra":{"4":3,"5":6,"6":9,"7":10,"8":10},"costPerEra":{"4":{"wood":428.0,"stone":285.0,"plaster":21.0,"ore":11.0},"5":{"wood":599.0,"stone":400.0,"truss":19.0,"coal":9.0},"6":{"wood":839.0,"stone":559.0,"clinker":17.0,"sand":9.0},"7":{"wood":1175.0,"stone":783.0,"glasswork":15.0,"crystal":8.0},"8":{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_cloth', '🧵 Cloth Weavery', NULL, 'FF8D6E4A', 3, 2, '{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0}'::jsonb, 0.1728, '["era_4"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"cloth","mult":0.5,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"4":3,"5":6,"6":9,"7":10,"8":10},"costPerEra":{"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_spices', '🌶️ Spices Garden', NULL, 'FF8D6E4A', 3, 2, '{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0}'::jsonb, 0.1728, '["era_4"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"spices","mult":0.5,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"4":3,"5":6,"6":9,"7":10,"8":10},"costPerEra":{"4":{"wood":296.0,"stone":198.0,"plaster":15.0,"ore":7.0},"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e4', 'Plaster Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0}'::jsonb, 0.432, '["era_4"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":12.3,"era":4},{"type":"production","key":"stone","value":12.3,"era":4},{"type":"production","key":"clay","value":8.2,"era":4},{"type":"production","key":"lime","value":8.2,"era":4},{"type":"production","key":"ore","value":8.2,"era":4},{"type":"production","key":"plaster","value":6.1,"era":4}]'::jsonb, '{"maxLevelPerEra":{"4":3,"5":6,"6":9,"7":10,"8":10},"costPerEra":{"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e4', 'Plaster Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0}'::jsonb, 0.432, '["era_4"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":16.4,"era":4},{"type":"production","key":"cloth","value":6.1,"era":4},{"type":"production","key":"spices","value":6.1,"era":4}]'::jsonb, '{"maxLevelPerEra":{"4":3,"5":6,"6":9,"7":10,"8":10},"costPerEra":{"4":{"wood":988.0,"stone":659.0,"plaster":49.0,"ore":24.0},"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('coal_camp_e5', 'Iron Coal Camp', NULL, 'FFB5651D', 3, 3, '{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0}'::jsonb, 0.20736, '["era_5"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"coal","mult":3.3,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"5":10,"6":10,"7":10,"8":10},"costPerEra":{"5":{"wood":461.0,"stone":307.0,"truss":15.0,"coal":7.0},"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('coal_works_e5', 'Iron Coal Works', NULL, 'FFB5651D', 4, 4, '{"wood":738.0,"stone":492.0,"truss":23.0,"coal":12.0}'::jsonb, 0.34559999999999996, '["era_5"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"coal","mult":5.2,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"5":10,"6":10,"7":10,"8":10},"costPerEra":{"5":{"wood":738.0,"stone":492.0,"truss":23.0,"coal":12.0},"6":{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0},"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('refinery_e5', 'Iron Refinery', NULL, 'FF5C6BC0', 4, 4, '{"wood":645.0,"stone":430.0,"truss":20.0,"coal":10.0}'::jsonb, 0.41472, '["era_5"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"truss","mult":1.3,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"5":10,"6":10,"7":10,"8":10},"costPerEra":{"5":{"wood":645.0,"stone":430.0,"truss":20.0,"coal":10.0},"6":{"wood":904.0,"stone":602.0,"clinker":18.0,"sand":9.0},"7":{"wood":1265.0,"stone":843.0,"glasswork":17.0,"crystal":8.0},"8":{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_a_e5', 'Iron Den', NULL, 'FF795548', 3, 4, '{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0}'::jsonb, 0.17279999999999998, '["era_5"]'::jsonb, false, false, false, false, NULL, 70, 0, '[]'::jsonb, '{"maxLevelPerEra":{"5":3,"6":6,"7":9,"8":10},"costPerEra":{"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_b_e5', 'Iron Roost', NULL, 'FF795548', 3, 5, '{"wood":599.0,"stone":400.0,"truss":19.0,"coal":9.0}'::jsonb, 0.17279999999999998, '["era_5"]'::jsonb, false, false, false, false, NULL, 98, 0, '[]'::jsonb, '{"maxLevelPerEra":{"5":3,"6":6,"7":9,"8":10},"costPerEra":{"5":{"wood":599.0,"stone":400.0,"truss":19.0,"coal":9.0},"6":{"wood":839.0,"stone":559.0,"clinker":17.0,"sand":9.0},"7":{"wood":1175.0,"stone":783.0,"glasswork":15.0,"crystal":8.0},"8":{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_salt', '🧂 Salt Works', NULL, 'FF8D6E4A', 3, 2, '{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0}'::jsonb, 0.20736, '["era_5"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"salt","mult":0.8,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"5":3,"6":6,"7":9,"8":10},"costPerEra":{"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_silk', '🧶 Silk Farm', NULL, 'FF8D6E4A', 3, 2, '{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0}'::jsonb, 0.20736, '["era_5"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"silk","mult":0.8,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"5":3,"6":6,"7":9,"8":10},"costPerEra":{"5":{"wood":415.0,"stone":277.0,"truss":13.0,"coal":7.0},"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e5', 'Iron Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0}'::jsonb, 0.5184, '["era_5"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":19.7,"era":5},{"type":"production","key":"stone","value":19.7,"era":5},{"type":"production","key":"clay","value":13.1,"era":5},{"type":"production","key":"lime","value":13.1,"era":5},{"type":"production","key":"ore","value":13.1,"era":5},{"type":"production","key":"coal","value":13.1,"era":5},{"type":"production","key":"truss","value":9.8,"era":5}]'::jsonb, '{"maxLevelPerEra":{"5":3,"6":6,"7":9,"8":10},"costPerEra":{"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e5', 'Iron Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0}'::jsonb, 0.5184, '["era_5"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":26.2,"era":5},{"type":"production","key":"salt","value":9.8,"era":5},{"type":"production","key":"silk","value":9.8,"era":5}]'::jsonb, '{"maxLevelPerEra":{"5":3,"6":6,"7":9,"8":10},"costPerEra":{"5":{"wood":1383.0,"stone":922.0,"truss":44.0,"coal":22.0},"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('sand_camp_e6', 'Forged Sand Camp', NULL, 'FFB5651D', 3, 3, '{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0}'::jsonb, 0.24883199999999994, '["era_6"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"sand","mult":5.2,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"6":10,"7":10,"8":10},"costPerEra":{"6":{"wood":645.0,"stone":430.0,"clinker":13.0,"sand":7.0},"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('sand_works_e6', 'Forged Sand Works', NULL, 'FFB5651D', 4, 4, '{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0}'::jsonb, 0.4147199999999999, '["era_6"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"sand","mult":8.4,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"6":10,"7":10,"8":10},"costPerEra":{"6":{"wood":1033.0,"stone":688.0,"clinker":21.0,"sand":10.0},"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('refinery_e6', 'Forged Refinery', NULL, 'FF5C6BC0', 4, 4, '{"wood":904.0,"stone":602.0,"clinker":18.0,"sand":9.0}'::jsonb, 0.4976639999999999, '["era_6"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"clinker","mult":2.1,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"6":10,"7":10,"8":10},"costPerEra":{"6":{"wood":904.0,"stone":602.0,"clinker":18.0,"sand":9.0},"7":{"wood":1265.0,"stone":843.0,"glasswork":17.0,"crystal":8.0},"8":{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_a_e6', 'Forged Den', NULL, 'FF795548', 3, 4, '{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0}'::jsonb, 0.20735999999999996, '["era_6"]'::jsonb, false, false, false, false, NULL, 95, 0, '[]'::jsonb, '{"maxLevelPerEra":{"6":3,"7":6,"8":9},"costPerEra":{"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_b_e6', 'Forged Roost', NULL, 'FF795548', 3, 5, '{"wood":839.0,"stone":559.0,"clinker":17.0,"sand":9.0}'::jsonb, 0.20735999999999996, '["era_6"]'::jsonb, false, false, false, false, NULL, 133, 0, '[]'::jsonb, '{"maxLevelPerEra":{"6":3,"7":6,"8":9},"costPerEra":{"6":{"wood":839.0,"stone":559.0,"clinker":17.0,"sand":9.0},"7":{"wood":1175.0,"stone":783.0,"glasswork":15.0,"crystal":8.0},"8":{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_chocolate', '🍫 Chocolate Chocolatier', NULL, 'FF8D6E4A', 3, 2, '{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0}'::jsonb, 0.24883199999999994, '["era_6"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"chocolate","mult":1.3,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"6":3,"7":6,"8":9},"costPerEra":{"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_coffee', '☕ Coffee Roastery', NULL, 'FF8D6E4A', 3, 2, '{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0}'::jsonb, 0.24883199999999994, '["era_6"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"coffee","mult":1.3,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"6":3,"7":6,"8":9},"costPerEra":{"6":{"wood":581.0,"stone":387.0,"clinker":12.0,"sand":6.0},"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e6', 'Forged Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0}'::jsonb, 0.6220799999999999, '["era_6"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":31.5,"era":6},{"type":"production","key":"stone","value":31.5,"era":6},{"type":"production","key":"clay","value":21.0,"era":6},{"type":"production","key":"lime","value":21.0,"era":6},{"type":"production","key":"ore","value":21.0,"era":6},{"type":"production","key":"coal","value":21.0,"era":6},{"type":"production","key":"sand","value":21.0,"era":6},{"type":"production","key":"clinker","value":15.7,"era":6}]'::jsonb, '{"maxLevelPerEra":{"6":3,"7":6,"8":9},"costPerEra":{"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e6', 'Forged Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0}'::jsonb, 0.6220799999999999, '["era_6"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":41.9,"era":6},{"type":"production","key":"chocolate","value":15.7,"era":6},{"type":"production","key":"coffee","value":15.7,"era":6}]'::jsonb, '{"maxLevelPerEra":{"6":3,"7":6,"8":9},"costPerEra":{"6":{"wood":1936.0,"stone":1291.0,"clinker":39.0,"sand":20.0},"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('crystal_camp_e7', 'Glass Crystal Camp', NULL, 'FFB5651D', 3, 3, '{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0}'::jsonb, 0.29859839999999993, '["era_7"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"crystal","mult":8.4,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"7":10,"8":10},"costPerEra":{"7":{"wood":904.0,"stone":602.0,"glasswork":12.0,"crystal":6.0},"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('crystal_works_e7', 'Glass Crystal Works', NULL, 'FFB5651D', 4, 4, '{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0}'::jsonb, 0.4976639999999999, '["era_7"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"crystal","mult":13.4,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"7":10,"8":10},"costPerEra":{"7":{"wood":1446.0,"stone":964.0,"glasswork":19.0,"crystal":9.0},"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('refinery_e7', 'Glass Refinery', NULL, 'FF5C6BC0', 4, 4, '{"wood":1265.0,"stone":843.0,"glasswork":17.0,"crystal":8.0}'::jsonb, 0.5971967999999999, '["era_7"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"glasswork","mult":3.4,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"7":10,"8":10},"costPerEra":{"7":{"wood":1265.0,"stone":843.0,"glasswork":17.0,"crystal":8.0},"8":{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_a_e7', 'Glass Den', NULL, 'FF795548', 3, 4, '{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0}'::jsonb, 0.24883199999999994, '["era_7"]'::jsonb, false, false, false, false, NULL, 125, 0, '[]'::jsonb, '{"maxLevelPerEra":{"7":3,"8":6},"costPerEra":{"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_b_e7', 'Glass Roost', NULL, 'FF795548', 3, 5, '{"wood":1175.0,"stone":783.0,"glasswork":15.0,"crystal":8.0}'::jsonb, 0.24883199999999994, '["era_7"]'::jsonb, false, false, false, false, NULL, 175, 0, '[]'::jsonb, '{"maxLevelPerEra":{"7":3,"8":6},"costPerEra":{"7":{"wood":1175.0,"stone":783.0,"glasswork":15.0,"crystal":8.0},"8":{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_porcelain', '🍶 Porcelain Kiln', NULL, 'FF8D6E4A', 3, 2, '{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0}'::jsonb, 0.29859839999999993, '["era_7"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"porcelain","mult":2.0,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"7":3,"8":6},"costPerEra":{"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_tea', '🍵 Tea House', NULL, 'FF8D6E4A', 3, 2, '{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0}'::jsonb, 0.29859839999999993, '["era_7"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"tea","mult":2.0,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"7":3,"8":6},"costPerEra":{"7":{"wood":813.0,"stone":542.0,"glasswork":11.0,"crystal":5.0},"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e7', 'Glass Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0}'::jsonb, 0.7464959999999997, '["era_7"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":50.3,"era":7},{"type":"production","key":"stone","value":50.3,"era":7},{"type":"production","key":"clay","value":33.6,"era":7},{"type":"production","key":"lime","value":33.6,"era":7},{"type":"production","key":"ore","value":33.6,"era":7},{"type":"production","key":"coal","value":33.6,"era":7},{"type":"production","key":"sand","value":33.6,"era":7},{"type":"production","key":"crystal","value":33.6,"era":7},{"type":"production","key":"glasswork","value":25.2,"era":7}]'::jsonb, '{"maxLevelPerEra":{"7":3,"8":6},"costPerEra":{"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e7', 'Glass Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0}'::jsonb, 0.7464959999999997, '["era_7"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":67.1,"era":7},{"type":"production","key":"porcelain","value":25.2,"era":7},{"type":"production","key":"tea","value":25.2,"era":7}]'::jsonb, '{"maxLevelPerEra":{"7":3,"8":6},"costPerEra":{"7":{"wood":2711.0,"stone":1807.0,"glasswork":35.0,"crystal":18.0},"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('aether_camp_e8', 'Crystal Aether Camp', NULL, 'FFB5651D', 3, 3, '{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}'::jsonb, 0.3583180799999999, '["era_8"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"aether","mult":13.4,"slots":6}]'::jsonb, '{"maxLevelPerEra":{"8":10},"costPerEra":{"8":{"wood":1265.0,"stone":843.0,"vault":11.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('aether_works_e8', 'Crystal Aether Works', NULL, 'FFB5651D', 4, 4, '{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}'::jsonb, 0.5971967999999999, '["era_8"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"aether","mult":21.5,"slots":10}]'::jsonb, '{"maxLevelPerEra":{"8":10},"costPerEra":{"8":{"wood":2024.0,"stone":1349.0,"vault":17.0,"aether":9.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('refinery_e8', 'Crystal Refinery', NULL, 'FF5C6BC0', 4, 4, '{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}'::jsonb, 0.7166361599999999, '["era_8"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"crafting","resource":"vault","mult":5.4,"slots":8}]'::jsonb, '{"maxLevelPerEra":{"8":10},"costPerEra":{"8":{"wood":1771.0,"stone":1181.0,"vault":15.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_a_e8', 'Crystal Den', NULL, 'FF795548', 3, 4, '{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}'::jsonb, 0.29859839999999993, '["era_8"]'::jsonb, false, false, false, false, NULL, 165, 0, '[]'::jsonb, '{"maxLevelPerEra":{"8":3},"costPerEra":{"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('pen_b_e8', 'Crystal Roost', NULL, 'FF795548', 3, 5, '{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}'::jsonb, 0.29859839999999993, '["era_8"]'::jsonb, false, false, false, false, NULL, 231, 0, '[]'::jsonb, '{"maxLevelPerEra":{"8":3},"costPerEra":{"8":{"wood":1644.0,"stone":1096.0,"vault":14.0,"aether":7.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_jewelry', '💍 Jewelry Jeweler', NULL, 'FF8D6E4A', 3, 2, '{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}'::jsonb, 0.3583180799999999, '["era_8"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"jewelry","mult":3.2,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"8":3},"costPerEra":{"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('lux_perfume', '🌸 Perfume Perfumery', NULL, 'FF8D6E4A', 3, 2, '{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}'::jsonb, 0.3583180799999999, '["era_8"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"production","resource":"perfume","mult":3.2,"slots":3}]'::jsonb, '{"maxLevelPerEra":{"8":3},"costPerEra":{"8":{"wood":1138.0,"stone":759.0,"vault":10.0,"aether":5.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_materials_e8', 'Crystal Grand Works', NULL, 'FF6D4C41', 5, 5, '{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}'::jsonb, 0.8957951999999998, '["era_8"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"wood","value":80.5,"era":8},{"type":"production","key":"stone","value":80.5,"era":8},{"type":"production","key":"clay","value":53.7,"era":8},{"type":"production","key":"lime","value":53.7,"era":8},{"type":"production","key":"ore","value":53.7,"era":8},{"type":"production","key":"coal","value":53.7,"era":8},{"type":"production","key":"sand","value":53.7,"era":8},{"type":"production","key":"crystal","value":53.7,"era":8},{"type":"production","key":"aether","value":53.7,"era":8},{"type":"production","key":"vault","value":40.3,"era":8}]'::jsonb, '{"maxLevelPerEra":{"8":3},"costPerEra":{"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb),
  ('special_treasury_e8', 'Crystal Treasury', NULL, 'FFC9971A', 4, 4, '{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}'::jsonb, 0.8957951999999998, '["era_8"]'::jsonb, false, false, false, false, NULL, 0, 0, '[{"type":"workshop","stat":"breeding","resource":"legendary_boost","mult":1.0,"slots":1},{"type":"production","key":"gold","value":107.4,"era":8},{"type":"production","key":"jewelry","value":40.3,"era":8},{"type":"production","key":"perfume","value":40.3,"era":8}]'::jsonb, '{"maxLevelPerEra":{"8":3},"costPerEra":{"8":{"wood":3795.0,"stone":2530.0,"vault":32.0,"aether":16.0}},"costFactor":1.3,"timeFactor":1.3}'::jsonb);
commit;

-- ── The egg carries its own child (user 2026-07-26) ────────────────────────
-- "Bitte ei als Item bezeichnen und somit in den Bag senden können."
--
-- An egg is an ITEM the player holds, so it has to be a thing in its own right
-- — and it was not: hatching rolled the child from the two PARENTS' current
-- genes, read live at hatch time. That made an egg a promise about two other
-- creatures rather than an object, and it had a real bug in it: release a
-- parent before the egg hatched and the child silently fell back to a fresh
-- roll off the species curve instead of inheriting anything.
--
-- The genes are frozen when the egg is LAID (breeding → egg) and stored here.
-- Hatching reads them and needs no parent at all.
--
-- Both columns are jsonb maps of stat name → value, the same shape
-- `creatures.stat_base` / `stat_slope` use, so CreatureInstance's own readers
-- parse them unchanged.
--
-- NULL means "laid before this migration": those rows keep the old
-- read-the-parents behaviour, so nothing in flight is lost.
alter table breeding_jobs
  add column if not exists child_base  jsonb,
  add column if not exists child_slope jsonb;

comment on column breeding_jobs.child_base is
  'Child genes frozen when the egg was laid (stat name -> base). NULL = a '
  'pre-0027 row, hatched from the parents instead.';
comment on column breeding_jobs.child_slope is
  'Child per-level growth frozen when the egg was laid (stat name -> slope).';

-- ── Saved caravans (user 2026-07-27) ───────────────────────────────────────
-- "Zudem muss ich caravanen speichern können und schnellladen aus diesem menü
-- heraus."
--
-- A caravan is a named, reusable roster — exactly what `saved_teams` already
-- is — so that table grows a KIND instead of a second table with the same
-- three columns and the same RLS. 'battle' is the default because every
-- existing row IS one: no backfill, and battleTeam() keeps reading what it
-- read yesterday.
--
-- `saved_teams_one_active_per_user` is deliberately left alone. Caravans are
-- never active ("active" means "the team battleTeam() picks", which a caravan
-- has no equivalent of) — CreaturesController.saveCaravan enforces that.
alter table public.saved_teams
  add column if not exists kind text not null default 'battle';

comment on column public.saved_teams.kind is
  'battle = a fighting roster (battleTeam), caravan = a Market hauling party.';

create index if not exists saved_teams_user_kind_idx
  on public.saved_teams (user_id, kind);

-- ── The Healing Hut's queue (user 2026-07-27) ──────────────────────────────
-- "Treat all sollte nicht funktionieren, da ich aktuell keine Warteschlange
-- habe. Diese soll direkt eingebaut werden."
--
-- The hut treats only healSlots monsters at a time, so "treat all" either
-- refused outright or silently treated the worst few and left the rest hurt
-- with nothing on screen saying so. One nullable timestamp per creature, like
-- healing_until (0007): being IN LINE is a state of a creature, and the
-- timestamp carries the ORDER as well as the flag. NULL = not queued, which is
-- what every existing row means — no backfill.
alter table public.creatures
  add column if not exists heal_queued_at timestamptz;

comment on column public.creatures.heal_queued_at is
  'When this monster was put in line for the Healing Hut. NULL = not queued. '
  'Cleared the moment its treatment starts (healing_until is set instead).';

create index if not exists creatures_heal_queue_idx
  on public.creatures (user_id, heal_queued_at)
  where heal_queued_at is not null;
