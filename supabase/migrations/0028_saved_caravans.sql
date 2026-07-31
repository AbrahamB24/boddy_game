-- Saved caravans (user 2026-07-27: "zudem muss ich caravanen speichern können
-- und schnellladen aus diesem menü heraus").
--
-- A caravan is a named, reusable roster — exactly what `saved_teams` already
-- is. Rather than a second table with the same three columns and the same RLS,
-- the existing one grows a KIND, and the Market filters on it.
--
-- 'battle'  the rosters battleTeam() reads — everything already in the table.
-- 'caravan' the Market's haulers, quick-loaded into the trade slot.
--
-- The default is 'battle' precisely because every existing row IS one; no
-- backfill, and battleTeam() keeps reading exactly what it read yesterday.
alter table public.saved_teams
  add column if not exists kind text not null default 'battle';

comment on column public.saved_teams.kind is
  'battle = a fighting roster (battleTeam), caravan = a Market hauling party.';

-- The list the Market and the Teams screen each read is "this user's rows of
-- one kind", so that is the index.
create index if not exists saved_teams_user_kind_idx
  on public.saved_teams (user_id, kind);

-- NOTE on `saved_teams_one_active_per_user`: it stays exactly as it was, a
-- partial unique index over (user_id) where is_active. Caravans are never
-- active — "active" means "the team battleTeam() picks", which a caravan has no
-- equivalent of; the Market loads one by tapping it. CreaturesController
-- enforces that on insert, so a caravan can never take the battle team's slot.
