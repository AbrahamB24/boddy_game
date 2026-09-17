-- Social feature (user 2026-09-15): Freunde suchen/hinzufügen.
-- Eine Zeile pro Freundschaft(sanfrage), gerichtet (wer hat angefragt) aber
-- mit einem ungerichteten Unique-Constraint auf dem sortierten Paar, damit
-- A→B und B→A nie als zwei separate Zeilen existieren können.

create table if not exists public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references auth.users (id) on delete cascade,
  addressee_id  uuid not null references auth.users (id) on delete cascade,
  status        text not null default 'pending'
                  check (status in ('pending', 'accepted', 'declined', 'blocked')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  check (requester_id <> addressee_id)
);

-- Verhindert doppelte/gespiegelte Zeilen zwischen demselben Paar, unabhängig
-- davon wer zuerst angefragt hat.
create unique index if not exists friendships_pair_key
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create index if not exists friendships_requester_idx on public.friendships (requester_id);
create index if not exists friendships_addressee_idx on public.friendships (addressee_id);

alter table public.friendships enable row level security;

-- Beide Beteiligten sehen die Zeile und können eine neue Anfrage anlegen.
drop policy if exists "see own friendships" on public.friendships;
create policy "see own friendships" on public.friendships
  for select using (auth.uid() in (requester_id, addressee_id));

drop policy if exists "send friend request" on public.friendships;
create policy "send friend request" on public.friendships
  for insert with check (auth.uid() = requester_id);

-- Nur die/der Angefragte darf annehmen/ablehnen; nur der Anfragende darf eine
-- noch offene Anfrage zurückziehen (delete, siehe Policy unten).
drop policy if exists "respond to friend request" on public.friendships;
create policy "respond to friend request" on public.friendships
  for update
  using (auth.uid() = addressee_id)
  with check (auth.uid() = addressee_id);

drop policy if exists "withdraw own request" on public.friendships;
create policy "withdraw own request" on public.friendships
  for delete using (auth.uid() in (requester_id, addressee_id));

comment on column public.friendships.status is
  'pending: wartet auf addressee. accepted: beide sind Freunde. declined: '
  'von addressee abgelehnt. blocked: v1 nicht in der UI, Spalte für später.';
