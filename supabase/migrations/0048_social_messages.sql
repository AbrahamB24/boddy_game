-- Social feature (user 2026-09-15): 1:1-Nachrichten an Freunde.
-- "DMs nur unter Freunden" wird auf DB-Ebene erzwungen (nicht nur in der
-- UI verhindert) — der insert-check verlangt eine 'accepted'-Zeile in
-- friendships zwischen sender_id und recipient_id.

create table if not exists public.messages (
  id           uuid primary key default gen_random_uuid(),
  sender_id    uuid not null references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 2000),
  created_at   timestamptz not null default now(),
  read_at      timestamptz,
  check (sender_id <> recipient_id)
);

-- Unread-Badge-Query: "meine ungelesenen Nachrichten".
create index if not exists messages_recipient_unread_idx
  on public.messages (recipient_id, read_at);

-- Thread-Laden für ein Paar, chronologisch.
create index if not exists messages_thread_idx
  on public.messages (least(sender_id, recipient_id), greatest(sender_id, recipient_id), created_at);

alter table public.messages enable row level security;

drop policy if exists "see own messages" on public.messages;
create policy "see own messages" on public.messages
  for select using (auth.uid() in (sender_id, recipient_id));

drop policy if exists "send message to friend" on public.messages;
create policy "send message to friend" on public.messages
  for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and least(f.requester_id, f.addressee_id) = least(sender_id, recipient_id)
        and greatest(f.requester_id, f.addressee_id) = greatest(sender_id, recipient_id)
    )
  );

-- Nur der Empfänger darf die eigene Nachricht als gelesen markieren.
drop policy if exists "mark own inbox read" on public.messages;
create policy "mark own inbox read" on public.messages
  for update
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);
