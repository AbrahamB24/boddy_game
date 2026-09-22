-- Social feature (user 2026-09-19): die Lobby als Raum, in den man jederzeit
-- hinein- und wieder hinausgehen kann.
--
-- Bisher: Annehmen -> beide sofort in die Lobby, 2 Minuten Zeit, dann
-- 'lobby_expired'. Neu:
--
--  * Man betritt die Lobby, wann man will (auch der Herausforderer, bevor der
--    Gegner angenommen hat), und darf sie MINIMIEREN: zurück zur Siedlung, das
--    Match bleibt offen. Sobald der Gegner die Lobby betritt, bekommt man
--    eine Benachrichtigung (der Client sieht die Änderung dieser Spalten über
--    Realtime).
--  * Dafür braucht die Lobby eine Anwesenheit: `in_lobby_a/b` (bin ich gerade
--    drin) plus einen Herzschlag `lobby_seen_a/b`, damit ein abgestürzter
--    Client nicht für immer als "in der Lobby" gilt (der Client wertet nur
--    Herzschläge der letzten Minute).
--  * Die Lobby lebt jetzt Stunden statt 2 Minuten (der Client setzt
--    `lobby_expires_at` auf 24 h); auch eine unbeantwortete Herausforderung
--    verfällt dann.
--  * Man kann eine Lobby wirklich verlassen, und der Gegner erfährt den Grund:
--    'left' (Lobby verlassen), 'declined' (abgelehnt), 'cancelled'
--    (Herausforderung zurückgezogen).

alter table public.pvp_matches
  add column if not exists in_lobby_a boolean not null default false,
  add column if not exists in_lobby_b boolean not null default false,
  add column if not exists lobby_seen_a timestamptz,
  add column if not exists lobby_seen_b timestamptz;

comment on column public.pvp_matches.in_lobby_a is
  'player_a hat die Lobby offen (nicht minimiert). Wird beim Betreten true, '
  'beim Minimieren/Verlassen false; lobby_seen_a ist der Herzschlag dazu.';
comment on column public.pvp_matches.in_lobby_b is
  'player_b hat die Lobby offen (nicht minimiert). Siehe in_lobby_a.';

-- Der abandon_reason-Check aus 0053 war inline deklariert (kein Name); wie in
-- 0052 wird er über pg_constraint gefunden statt geraten.
do $$
declare
  con record;
begin
  for con in
    select conname from pg_constraint
    where conrelid = 'public.pvp_matches'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%abandon_reason%'
  loop
    execute format('alter table public.pvp_matches drop constraint %I', con.conname);
  end loop;
end $$;

alter table public.pvp_matches
  add constraint pvp_matches_abandon_reason_check
  check (abandon_reason is null or abandon_reason in
    ('timeout', 'desync', 'lobby_expired', 'left', 'declined', 'cancelled'));

-- Anwesenheit setzen: nur der eigene Teil, nur solange die Lobby existiert
-- (pending/accepted). SECURITY DEFINER, damit der Client nicht beliebige
-- Spalten der Zeile schreiben muss.
create or replace function public.pvp_lobby_presence(
  p_match_id uuid,
  p_present boolean
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

  if not found or m.status not in ('pending', 'accepted') then
    return;
  end if;

  if auth.uid() = m.player_a then
    update public.pvp_matches
      set in_lobby_a = p_present,
          lobby_seen_a = case when p_present then now() else lobby_seen_a end
      where id = p_match_id;
  elsif auth.uid() = m.player_b then
    update public.pvp_matches
      set in_lobby_b = p_present,
          lobby_seen_b = case when p_present then now() else lobby_seen_b end
      where id = p_match_id;
  end if;
end;
$$;

grant execute on function public.pvp_lobby_presence(uuid, boolean) to authenticated;

-- Der Lazy-Sweep räumt jetzt auch unbeantwortete Herausforderungen auf, deren
-- Frist verstrichen ist (lobby_expires_at wird schon beim Senden gesetzt).
create or replace function public.pvp_expire_stale()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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
        abandon_reason = 'lobby_expired',
        in_lobby_a = false,
        in_lobby_b = false
    where status in ('pending', 'accepted')
      and lobby_expires_at is not null
      and lobby_expires_at < now();
end;
$$;

grant execute on function public.pvp_expire_stale() to authenticated;

create index if not exists pvp_matches_open_expiry_idx
  on public.pvp_matches (status, lobby_expires_at)
  where status in ('pending', 'accepted');
