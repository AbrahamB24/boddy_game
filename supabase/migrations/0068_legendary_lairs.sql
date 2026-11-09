-- Legendary lairs + trainers (user 2026-11-07).
--
-- A legendary lives in a lair whose level IS the monster's level. Raising it
-- costs the species' region luxury (paid up front, by the owner's client) and
-- then runs on a clock; up to five legendaries of OTHER players can train it
-- to speed that clock up, and are paid the luxury + gold when it completes.
--
-- Same trusted-client model as the rest of the game: the client decides every
-- number (work seconds, trainer power, reward shares — all Dials) and hands
-- it to these functions; the SERVER owns only what must not be forged by the
-- other player: who is a trainer, the clock, and the payout.

alter table public.species_defs
  add column if not exists trainer_power numeric not null default 0.5;

create table if not exists public.legendary_lairs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  creature_id  uuid not null unique,
  species_id   text not null,
  level        int  not null default 1,
  upgrading    boolean not null default false,
  work_total   double precision not null default 0,   -- base-rate seconds
  work_done    double precision not null default 0,
  rate         double precision not null default 1,   -- 1 + sum(trainer effect)
  last_update  timestamptz not null default now(),
  paid_good    text,
  paid_amount  double precision not null default 0,
  paid_gold    double precision not null default 0,
  shares       jsonb not null default '[0.4,0.25,0.18,0.1,0.07]'::jsonb,
  created_at   timestamptz not null default now()
);
create index if not exists legendary_lairs_user_idx on public.legendary_lairs (user_id);

create table if not exists public.lair_trainers (
  lair_id            uuid not null references public.legendary_lairs (id) on delete cascade,
  trainer_creature_id uuid not null unique,   -- one job at a time
  trainer_user_id    uuid not null references auth.users (id) on delete cascade,
  slot_order         int  not null,
  effect             double precision not null,
  joined_at          timestamptz not null default now(),
  primary key (lair_id, slot_order)
);

create table if not exists public.lair_rewards (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  good       text,
  amount     double precision not null default 0,
  gold       double precision not null default 0,
  claimed    boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists lair_rewards_user_idx on public.lair_rewards (user_id, claimed);

alter table public.legendary_lairs enable row level security;
alter table public.lair_trainers  enable row level security;
alter table public.lair_rewards   enable row level security;

-- Lairs and their trainers are public (the marketplace lists other players'
-- open slots). Every WRITE goes through the functions below.
drop policy if exists "read lairs" on public.legendary_lairs;
create policy "read lairs" on public.legendary_lairs
  for select using (auth.role() = 'authenticated');
drop policy if exists "read lair trainers" on public.lair_trainers;
create policy "read lair trainers" on public.lair_trainers
  for select using (auth.role() = 'authenticated');
drop policy if exists "read own rewards" on public.lair_rewards;
create policy "read own rewards" on public.lair_rewards
  for select using (auth.uid() = user_id);

-- ── Helpers ────────────────────────────────────────────────────────────────
-- Brings work_done up to now at the current rate. Caller holds the row lock.
create or replace function public._lair_accrue(p_lair public.legendary_lairs)
returns public.legendary_lairs
language plpgsql as $$
begin
  if p_lair.upgrading then
    p_lair.work_done := least(
      p_lair.work_total,
      p_lair.work_done
        + extract(epoch from (now() - p_lair.last_update)) * p_lair.rate);
  end if;
  p_lair.last_update := now();
  return p_lair;
end $$;

-- Finishes the upgrade if the work is done: level + 1, pay the trainers.
create or replace function public._lair_finish_if_done(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  l public.legendary_lairs;
  n int;
  total_share double precision := 0;
  t record;
  sh double precision;
begin
  select * into l from public.legendary_lairs where id = p_id for update;
  if not found or not l.upgrading then return; end if;
  l := public._lair_accrue(l);
  if l.work_done + 0.5 < l.work_total then
    update public.legendary_lairs
       set work_done = l.work_done, last_update = l.last_update
     where id = p_id;
    return;
  end if;

  -- Normalise the shares over the trainers actually present, so nothing is
  -- lost when fewer than five trained.
  select count(*) into n from public.lair_trainers where lair_id = p_id;
  if n > 0 then
    for t in select slot_order from public.lair_trainers where lair_id = p_id loop
      total_share := total_share + coalesce((l.shares ->> (t.slot_order - 1))::double precision, 0);
    end loop;
    if total_share <= 0 then total_share := n; end if;
    for t in
      select slot_order, trainer_user_id from public.lair_trainers
       where lair_id = p_id order by slot_order loop
      sh := coalesce((l.shares ->> (t.slot_order - 1))::double precision, 1.0 / n)
            / total_share;
      insert into public.lair_rewards (user_id, good, amount, gold)
      values (t.trainer_user_id, l.paid_good, l.paid_amount * sh, l.paid_gold * sh);
    end loop;
  end if;
  -- Nobody trained: the paid luxury is simply gone (user decision).

  delete from public.lair_trainers where lair_id = p_id;
  update public.legendary_lairs
     set level = level + 1, upgrading = false, work_total = 0, work_done = 0,
         rate = 1, last_update = now(), paid_good = null, paid_amount = 0,
         paid_gold = 0
   where id = p_id;
  update public.creatures set level = l.level + 1 where id = l.creature_id;
end $$;

-- ── Public functions ───────────────────────────────────────────────────────
-- A lair per legendary the caller owns; idempotent.
create or replace function public.lair_ensure(p_creature uuid, p_species text, p_level int)
returns public.legendary_lairs
language plpgsql security definer set search_path = public as $$
declare l public.legendary_lairs;
begin
  perform 1 from public.creatures where id = p_creature and user_id = auth.uid();
  if not found then raise exception 'not your creature'; end if;
  insert into public.legendary_lairs (user_id, creature_id, species_id, level)
  values (auth.uid(), p_creature, p_species, greatest(1, p_level))
  on conflict (creature_id) do nothing;
  select * into l from public.legendary_lairs where creature_id = p_creature;
  return l;
end $$;

-- Owner pays (client-side) and starts the clock.
create or replace function public.lair_start_upgrade(
  p_lair uuid, p_work_seconds double precision,
  p_good text, p_amount double precision, p_gold double precision,
  p_shares jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare l public.legendary_lairs;
begin
  select * into l from public.legendary_lairs
   where id = p_lair and user_id = auth.uid() for update;
  if not found then raise exception 'not your lair'; end if;
  if l.upgrading then raise exception 'already upgrading'; end if;
  update public.legendary_lairs
     set upgrading = true, work_total = p_work_seconds, work_done = 0,
         rate = 1, last_update = now(), paid_good = p_good,
         paid_amount = p_amount, paid_gold = p_gold, shares = p_shares
   where id = p_lair;
end $$;

-- Another player's legendary joins as trainer. Cannot leave until done.
create or replace function public.lair_join(
  p_lair uuid, p_creature uuid, p_effect double precision)
returns void
language plpgsql security definer set search_path = public as $$
declare l public.legendary_lairs; n int; r double precision;
begin
  perform public._lair_finish_if_done(p_lair);
  select * into l from public.legendary_lairs where id = p_lair for update;
  if not found or not l.upgrading then raise exception 'not upgrading'; end if;
  if l.user_id = auth.uid() then raise exception 'own lair'; end if;
  perform 1 from public.creatures where id = p_creature and user_id = auth.uid();
  if not found then raise exception 'not your creature'; end if;
  select count(*) into n from public.lair_trainers where lair_id = p_lair;
  if n >= 5 then raise exception 'lair full'; end if;
  l := public._lair_accrue(l);
  insert into public.lair_trainers
    (lair_id, trainer_creature_id, trainer_user_id, slot_order, effect)
  values (p_lair, p_creature, auth.uid(), n + 1, greatest(0, p_effect));
  select 1 + coalesce(sum(effect), 0) into r
    from public.lair_trainers where lair_id = p_lair;
  update public.legendary_lairs
     set work_done = l.work_done, last_update = l.last_update, rate = r
   where id = p_lair;
end $$;

-- Anyone involved can ask for the lair to be settled.
create or replace function public.lair_refresh(p_lair uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public._lair_finish_if_done(p_lair);
end $$;

-- Hands over (and marks) everything owed to the caller.
create or replace function public.lair_claim_rewards()
returns table (good text, amount double precision, gold double precision)
language plpgsql security definer set search_path = public as $$
begin
  return query
    with c as (
      update public.lair_rewards r set claimed = true
       where r.user_id = auth.uid() and not r.claimed
      returning r.good, r.amount, r.gold)
    select c.good, sum(c.amount), sum(c.gold) from c group by c.good;
end $$;

-- The marketplace: open trainer slots in other players' lairs.
create or replace function public.lair_open_slots()
returns table (
  lair_id uuid, owner_id uuid, owner_name text, species_id text, level int,
  trainers int, work_total double precision, work_done double precision,
  rate double precision, last_update timestamptz)
language sql security definer set search_path = public stable as $$
  select l.id, l.user_id, p.username, l.species_id, l.level,
         (select count(*)::int from public.lair_trainers t where t.lair_id = l.id),
         l.work_total, l.work_done, l.rate, l.last_update
    from public.legendary_lairs l
    left join public.profiles p on p.id = l.user_id
   where l.upgrading and l.user_id <> auth.uid()
     and (select count(*) from public.lair_trainers t where t.lair_id = l.id) < 5
   order by l.last_update desc
   limit 100;
$$;

grant execute on function public.lair_ensure(uuid, text, int) to authenticated;
grant execute on function public.lair_start_upgrade(uuid, double precision, text, double precision, double precision, jsonb) to authenticated;
grant execute on function public.lair_join(uuid, uuid, double precision) to authenticated;
grant execute on function public.lair_refresh(uuid) to authenticated;
grant execute on function public.lair_claim_rewards() to authenticated;
grant execute on function public.lair_open_slots() to authenticated;
