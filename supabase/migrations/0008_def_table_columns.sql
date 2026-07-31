-- Bring the Dev-Mode content tables in line with what the code actually writes.
--
-- WHY: `building_defs` / `tech_defs` / `era_defs` were created outside this
-- repo and no migration here owns them. GameDefsService writes them with a
-- plain `upsert(def.toDefRow())` and NO tolerant fallback, on the stated
-- assumption that "these are new tables deployed in lockstep with this
-- feature". They weren't — the code has grown fields since, and Postgrest
-- rejects the WHOLE row when it meets one unknown column ("Could not find the
-- 'x' column … PGRST204").
--
-- The symptom that found this: editing a building's housing capacity appeared
-- to save and then "fell back to the old value" — the write was being rejected
-- outright, so the live def stayed the bundled fallback.
--
-- Every column below is one that `toDefRow()` emits. All idempotent, so this
-- is safe to run whatever state the tables are already in. Defaults match the
-- code's own defaults in `fromDefRow`, so existing rows keep behaving the same.

-- ── building_defs ───────────────────────────────────────────
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
  -- Housing capacity. The column keeps the historical name `population`
  -- (BuildingDef.housingCapacity aliases it) — creatures ARE the population.
  add column if not exists population         int not null default 0,
  add column if not exists worker_requirement int not null default 0,
  add column if not exists max_laborers       int not null default 0,
  add column if not exists max_count          int not null default 0,
  -- Workshops + bonuses all live in here (see BuildingDef.fromDefRow).
  add column if not exists effects            jsonb not null default '[]'::jsonb;

-- ── tech_defs ───────────────────────────────────────────────
-- `if exists`, because this table was DROPPED again by 0021 (technologies are
-- places on the map now). Replaying the history on a database that is already
-- past 0021 must not abort here — the point of a migration set is that it can be
-- run from the beginning (fixed 2026-07-30, when it aborted exactly here).
alter table if exists public.tech_defs
  add column if not exists emoji            text,
  add column if not exists description      text,
  add column if not exists bp_cost          int not null default 0,
  add column if not exists research_seconds double precision not null default 0,
  add column if not exists era_id           text,
  add column if not exists unlocks_building text,
  add column if not exists effects          jsonb not null default '[]'::jsonb;

-- ── era_defs ────────────────────────────────────────────────
alter table public.era_defs
  add column if not exists emoji             text,
  add column if not exists era_order         int not null default 1,
  add column if not exists advancement_cost  jsonb not null default '{}'::jsonb,
  add column if not exists grant_resources   jsonb not null default '{}'::jsonb,
  add column if not exists effects           jsonb not null default '[]'::jsonb;
