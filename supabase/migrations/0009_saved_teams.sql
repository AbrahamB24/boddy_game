-- Named, reusable battle rosters ("Steinteam"). See lib/features/creatures/
-- models/saved_team.dart for why: battleTeam() used to mean "your oldest N
-- monsters", with no way for the player to say otherwise.

create table if not exists public.saved_teams (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null default 'Team',
  -- Creature ids, in the player's chosen order. Deliberately NOT a foreign
  -- key array: a team is a saved INTENT, and releasing one member shouldn't
  -- cascade-shred the roster. battleTeam() resolves ids on read and skips any
  -- that no longer exist.
  member_ids jsonb not null default '[]'::jsonb,
  -- At most one active team per user, enforced by the partial unique index
  -- below rather than by trusting the client to clear the others.
  is_active  boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists saved_teams_user_idx on public.saved_teams (user_id);

create unique index if not exists saved_teams_one_active_per_user
  on public.saved_teams (user_id) where is_active;

alter table public.saved_teams enable row level security;

-- Same shape as the other per-user tables: a player sees and writes only rows
-- they own, checked on both read and write.
drop policy if exists "own teams" on public.saved_teams;
create policy "own teams" on public.saved_teams
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
