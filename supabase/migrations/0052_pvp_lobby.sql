-- Social feature (user 2026-09-15): PvP-Lobby.
--
-- Neuer Ablauf: Herausforderung senden (kein Sprung irgendwohin) → Gegner
-- nimmt an (status 'accepted', noch kein Team/Seed) → BEIDE betreten eine
-- Lobby und stellen dort ihr Team zusammen (wie beim normalen
-- Kampf-Vorbereitungsscreen) → sobald beide "Bereit" gedrückt haben, wird
-- der Kampf scharf geschaltet (Seed + Teams stehen jetzt fest).
--
-- Robust gegen den unbekannten Auto-Namen des bestehenden status-Checks aus
-- 0050 (der wurde inline deklariert, nicht benannt) — sucht ihn über
-- pg_constraint statt den Namen zu raten.

do $$
declare
  con record;
begin
  for con in
    select conname from pg_constraint
    where conrelid = 'public.pvp_matches'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%in%'
  loop
    execute format('alter table public.pvp_matches drop constraint %I', con.conname);
  end loop;
end $$;

alter table public.pvp_matches
  add constraint pvp_matches_status_check
  check (status in ('pending', 'accepted', 'active', 'finished', 'abandoned'));

alter table public.pvp_matches
  add column if not exists ready_a boolean not null default false,
  add column if not exists ready_b boolean not null default false;

comment on column public.pvp_matches.status is
  'pending: Anfrage offen. accepted: angenommen, beide bauen ihr Team in der '
  'Lobby. active: beide bereit, Kampf läuft (seed+team_a/b gesetzt). '
  'finished/abandoned: Ende.';

comment on column public.pvp_matches.ready_a is
  'player_a hat in der Lobby sein Team bestätigt (siehe team_a) und ist bereit.';
comment on column public.pvp_matches.ready_b is
  'player_b hat in der Lobby sein Team bestätigt (siehe team_b) und ist bereit.';
