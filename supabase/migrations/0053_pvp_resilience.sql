-- Social feature (user 2026-09-17): PvP-Robustheit gegen Verbindungsabbruch.
--
-- Ein Timer für alles: `waiting_on` (wer ist dran) + `turn_deadline_at` (bis
-- wann) decken sowohl "Gegner ist nur langsam" als auch "Gegner hat die
-- Verbindung verloren" ab — beides löst sich gleich auf: Deadline
-- verstrichen -> der andere Spieler darf pvp_claim_timeout_win() aufrufen.
--
-- Alle neuen Funktionen sind SECURITY DEFINER: sie greifen bewusst an der
-- "kein Update nach finished"-RLS aus 0050 vorbei (die würde sonst auch eine
-- legitime Timeout-Entscheidung blockieren), prüfen die Business-Regeln aber
-- explizit selbst nach, statt der Tabelle pauschal mehr Update-Rechte zu
-- geben.

alter table public.pvp_matches
  add column if not exists last_seen_a timestamptz,
  add column if not exists last_seen_b timestamptz,
  add column if not exists waiting_on uuid references auth.users (id),
  add column if not exists turn_deadline_at timestamptz,
  add column if not exists lobby_expires_at timestamptz,
  add column if not exists abandon_reason text
    check (abandon_reason in ('timeout', 'desync', 'lobby_expired'));

comment on column public.pvp_matches.waiting_on is
  'uuid des Spielers, dessen Entscheidung gerade aussteht (Zug ODER '
  'Reconnect nach Verbindungsabbruch -- beides läuft über denselben Timer).';
comment on column public.pvp_matches.turn_deadline_at is
  'Deadline für waiting_on. Verstrichen -> der ANDERE Spieler darf '
  'pvp_claim_timeout_win() aufrufen.';

create index if not exists pvp_matches_active_deadline_idx
  on public.pvp_matches (status, turn_deadline_at)
  where status = 'active';

create index if not exists pvp_matches_lobby_expiry_idx
  on public.pvp_matches (status, lobby_expires_at)
  where status = 'accepted';

-- Reines Telemetrie-Logging für den (seltenen) Fall, dass zwei Clients trotz
-- identischer, deterministischer Engine unterschiedliche Zustände berechnen.
create table if not exists public.pvp_desync_reports (
  id            uuid primary key default gen_random_uuid(),
  match_id      uuid not null references public.pvp_matches (id) on delete cascade,
  reporter_id   uuid not null references auth.users (id) on delete cascade,
  seq           int not null,
  my_hash       text not null,
  expected_hash text,
  created_at    timestamptz not null default now()
);

alter table public.pvp_desync_reports enable row level security;

drop policy if exists "insert own desync report" on public.pvp_desync_reports;
create policy "insert own desync report" on public.pvp_desync_reports
  for insert with check (auth.uid() = reporter_id);

drop policy if exists "read own desync report" on public.pvp_desync_reports;
create policy "read own desync report" on public.pvp_desync_reports
  for select using (auth.uid() = reporter_id);

-- ── RPCs ─────────────────────────────────────────────────────────

create or replace function public.pvp_touch_presence(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m record;
begin
  select player_a, player_b, status into m
  from public.pvp_matches where id = p_match_id;

  if not found or m.status <> 'active' then
    return;
  end if;

  if auth.uid() = m.player_a then
    update public.pvp_matches set last_seen_a = now() where id = p_match_id;
  elsif auth.uid() = m.player_b then
    update public.pvp_matches set last_seen_b = now() where id = p_match_id;
  end if;
end;
$$;

create or replace function public.pvp_advance_turn(
  p_match_id uuid,
  p_waiting_on uuid,
  p_deadline_seconds int default 60
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m record;
begin
  select player_a, player_b, status into m
  from public.pvp_matches where id = p_match_id;

  if not found or m.status <> 'active' then
    return;
  end if;
  if auth.uid() not in (m.player_a, m.player_b) then
    return;
  end if;
  if p_waiting_on not in (m.player_a, m.player_b) then
    return;
  end if;

  update public.pvp_matches
    set waiting_on = p_waiting_on,
        turn_deadline_at = now() + make_interval(secs => p_deadline_seconds)
    where id = p_match_id;
end;
$$;

create or replace function public.pvp_claim_timeout_win(p_match_id uuid)
returns public.pvp_matches
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.pvp_matches;
begin
  select * into m from public.pvp_matches where id = p_match_id for update;

  if not found then
    raise exception 'match not found';
  end if;
  if m.status <> 'active' then
    raise exception 'match not active';
  end if;
  if auth.uid() not in (m.player_a, m.player_b) then
    raise exception 'not a participant';
  end if;
  if m.waiting_on is null or m.waiting_on = auth.uid() then
    raise exception 'not waiting on opponent';
  end if;
  if m.turn_deadline_at is null or m.turn_deadline_at > now() then
    raise exception 'deadline not reached';
  end if;

  update public.pvp_matches
    set status = 'finished',
        winner_id = auth.uid(),
        abandon_reason = 'timeout',
        finished_at = now()
    where id = p_match_id
    returning * into m;

  return m;
end;
$$;

-- Ersetzt PvpService.appendAction's rohes update() (siehe pvp_service.dart):
-- prüft zusätzlich, dass die seq lückenlos anschliesst und kind bekannt ist.
-- Validiert bewusst NICHT die Spielregel-Legalität der Aktion (Schaden,
-- AP-Kosten, ob wirklich diese Person dran war) -- das wäre der volle
-- Server-Nachbau der Engine, den wir laut Absprache nicht bauen (PvP läuft
-- nur unter Freunden, kein anonymes Matchmaking).
create or replace function public.pvp_append_action(p_match_id uuid, p_action jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  m record;
  expected_seq int;
begin
  select player_a, player_b, status, action_log into m
  from public.pvp_matches where id = p_match_id for update;

  if not found then
    raise exception 'match not found';
  end if;
  if m.status <> 'active' then
    raise exception 'match not active';
  end if;
  if auth.uid() not in (m.player_a, m.player_b) then
    raise exception 'not a participant';
  end if;

  expected_seq := jsonb_array_length(m.action_log);
  if (p_action->>'seq')::int <> expected_seq then
    raise exception 'unexpected seq: got %, expected %', p_action->>'seq', expected_seq;
  end if;
  if not (p_action->>'kind' = any (array['attack', 'ability', 'switch', 'endTurn', 'flee'])) then
    raise exception 'unknown action kind: %', p_action->>'kind';
  end if;

  update public.pvp_matches
    set action_log = m.action_log || jsonb_build_array(p_action)
    where id = p_match_id;
end;
$$;

-- Zustandsloser Lazy-Sweep statt Cron/Edge-Function: wird opportunistisch
-- beim Laden von Listen aufgerufen (PvP-Tab, Lobby), räumt verwaiste
-- Matches/Lobbys auf, die sonst für immer offen blieben.
create or replace function public.pvp_expire_stale()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 90s = 60s Client-Timeout + 30s Puffer, falls der gewinnende Client
  -- selbst offline ist und den Sieg nicht sofort selbst beanspruchen kann.
  update public.pvp_matches
    set status = 'finished',
        winner_id = case when waiting_on = player_a then player_b else player_a end,
        abandon_reason = 'timeout',
        finished_at = now()
    where status = 'active'
      and turn_deadline_at is not null
      and turn_deadline_at < now() - interval '90 seconds'
      and waiting_on is not null;

  update public.pvp_matches
    set status = 'abandoned',
        abandon_reason = 'timeout',
        finished_at = now()
    where status = 'active'
      and turn_deadline_at is not null
      and turn_deadline_at < now() - interval '90 seconds'
      and waiting_on is null;

  update public.pvp_matches
    set status = 'abandoned',
        abandon_reason = 'lobby_expired'
    where status = 'accepted'
      and lobby_expires_at is not null
      and lobby_expires_at < now();
end;
$$;

grant execute on function public.pvp_touch_presence(uuid) to authenticated;
grant execute on function public.pvp_advance_turn(uuid, uuid, int) to authenticated;
grant execute on function public.pvp_claim_timeout_win(uuid) to authenticated;
grant execute on function public.pvp_append_action(uuid, jsonb) to authenticated;
grant execute on function public.pvp_expire_stale() to authenticated;
