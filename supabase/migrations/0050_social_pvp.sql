-- Social feature (user 2026-09-15): Echtzeit-6v6-PvP gegen Freunde.
--
-- pvp_stats: Rating/Bilanz, bewusst NICHT auf `profiles` (das ist mit der
-- Fitness-App geteilt und Rating ändert sich häufig) sondern eine eigene,
-- kleine Tabelle. Quelle für die Freundes-Rangliste.
--
-- pvp_matches: ein Match wird persistiert (Seed + Team-Snapshots + ein
-- append-only action_log), nicht rein per ephemerem Realtime-Broadcast
-- gehalten — ein Verbindungsabbruch mitten im Kampf darf das Match nicht für
-- beide verlieren. Die Zeile ist ein Checkpoint für Reconnect, nicht der
-- Live-Transportweg (der bleibt Realtime-Broadcast).

create table if not exists public.pvp_stats (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  rating     int not null default 1000,
  wins       int not null default 0,
  losses     int not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.pvp_stats enable row level security;

-- Ratings sind nicht sensibel — jeder eingeloggte Spieler darf die Rangliste
-- lesen (gefiltert wird clientseitig auf den eigenen Freundeskreis).
drop policy if exists "read pvp stats" on public.pvp_stats;
create policy "read pvp stats" on public.pvp_stats
  for select using (auth.role() = 'authenticated');

drop policy if exists "write own pvp stats" on public.pvp_stats;
create policy "write own pvp stats" on public.pvp_stats
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.pvp_matches (
  id          uuid primary key default gen_random_uuid(),
  player_a    uuid not null references auth.users (id) on delete cascade,
  player_b    uuid not null references auth.users (id) on delete cascade,
  status      text not null default 'pending'
                check (status in ('pending', 'active', 'finished', 'abandoned')),
  seed        bigint,
  team_a      jsonb,
  team_b      jsonb,
  action_log  jsonb not null default '[]'::jsonb,
  winner_id   uuid,
  created_at  timestamptz not null default now(),
  finished_at timestamptz,
  check (player_a <> player_b)
);

create index if not exists pvp_matches_player_a_idx on public.pvp_matches (player_a);
create index if not exists pvp_matches_player_b_idx on public.pvp_matches (player_b);

alter table public.pvp_matches enable row level security;

drop policy if exists "see own matches" on public.pvp_matches;
create policy "see own matches" on public.pvp_matches
  for select using (auth.uid() in (player_a, player_b));

drop policy if exists "create challenge" on public.pvp_matches;
create policy "create challenge" on public.pvp_matches
  for insert with check (auth.uid() in (player_a, player_b));

-- Sobald ein Match 'finished' ist, sperrt die USING-Klausel (prüft die ALTE
-- Zeile) weitere Updates — verhindert nachträgliches Manipulieren von
-- action_log/winner_id nach Kampfende.
drop policy if exists "update active match" on public.pvp_matches;
create policy "update active match" on public.pvp_matches
  for update
  using (auth.uid() in (player_a, player_b) and status <> 'finished')
  with check (auth.uid() in (player_a, player_b));

comment on column public.pvp_matches.action_log is
  'Append-only Liste der relayten Kampfaktionen (Fähigkeit/Angriff/Wechsel + '
  'Ziel + Zugnummer). Checkpoint für Reconnect: ein neu verbundener Client '
  'spielt sie gegen eine frische CombatEngine(rng: Random(seed)) durch.';
