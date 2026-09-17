-- Social feature (user 2026-09-15): RLS fix-up.
--
-- `profiles`, `settlements` and `placed_buildings` predate this migrations
-- folder and were created directly in Supabase with an owner-only SELECT
-- policy (`auth.uid() = user_id` / `= id`) — correct for a single-player
-- game, but it silently blocks every new social read path added in
-- 0046-0050: searching another player's username, and loading a FRIEND's
-- settlement for the read-only "visit" screen.
--
-- Postgres RLS OR's multiple permissive policies for the same command
-- together, so these are ADDITIVE — nothing here narrows what a player could
-- already see of their OWN rows, they only widen SELECT to two new cases.

alter table public.profiles enable row level security;
alter table public.settlements enable row level security;
alter table public.placed_buildings enable row level security;

-- Discoverable only by choice: a profile is findable in search once (and
-- only once) its owner has set a username — every BoddyQuest-only row, and
-- every BøddyGame player who hasn't opted in yet, has none and stays
-- invisible to this policy (their OWN row is still visible to themselves via
-- the pre-existing owner policy).
drop policy if exists "search profiles by username" on public.profiles;
create policy "search profiles by username" on public.profiles
  for select using (username is not null);

-- A friend's settlement row, read-only — the "visit city" screen.
drop policy if exists "friends can view settlement" on public.settlements;
create policy "friends can view settlement" on public.settlements
  for select using (
    exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and least(f.requester_id, f.addressee_id) = least(auth.uid(), settlements.user_id)
        and greatest(f.requester_id, f.addressee_id) = greatest(auth.uid(), settlements.user_id)
    )
  );

-- Same, for the buildings on that settlement (keyed by settlement_id, not
-- user_id directly, so this joins through settlements to find the owner).
drop policy if exists "friends can view placed_buildings" on public.placed_buildings;
create policy "friends can view placed_buildings" on public.placed_buildings
  for select using (
    exists (
      select 1 from public.settlements s
      join public.friendships f
        on f.status = 'accepted'
        and least(f.requester_id, f.addressee_id) = least(auth.uid(), s.user_id)
        and greatest(f.requester_id, f.addressee_id) = greatest(auth.uid(), s.user_id)
      where s.id = placed_buildings.settlement_id
    )
  );
