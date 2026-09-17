-- Social feature (user 2026-09-15): Aktivitäts-Feed für Freunde.
-- Wird clientseitig an den Momenten geschrieben, die zählen (Freund
-- hinzugefügt, PvP gewonnen, Level-Up) statt per Trigger auf jeder
-- Bestandstabelle nachgerüstet — bewusste v1-Einschränkung, siehe Plan.

create table if not exists public.friend_activity (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  kind       text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists friend_activity_user_idx
  on public.friend_activity (user_id, created_at desc);

alter table public.friend_activity enable row level security;

-- Man schreibt nur die eigene Aktivität...
drop policy if exists "post own activity" on public.friend_activity;
create policy "post own activity" on public.friend_activity
  for insert with check (auth.uid() = user_id);

-- ...aber sieht die eigene UND die der akzeptierten Freunde (der Feed selbst).
drop policy if exists "see own and friends activity" on public.friend_activity;
create policy "see own and friends activity" on public.friend_activity
  for select using (
    auth.uid() = user_id
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and least(f.requester_id, f.addressee_id) = least(auth.uid(), user_id)
        and greatest(f.requester_id, f.addressee_id) = greatest(auth.uid(), user_id)
    )
  );

comment on column public.friend_activity.kind is
  'z.B. friend_added, battle_won, building_upgraded, level_up. '
  'payload trägt die Details fürs jeweilige Feed-Item (z.B. species/building id).';
