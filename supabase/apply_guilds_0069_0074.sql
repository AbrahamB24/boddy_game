-- ═══════════════════════════════════════════════════════════════
-- Guilds, all stages (2026-11-13): migrations 0069 to 0074 in order.
-- Paste into the Supabase SQL editor and run ONCE. All-or-nothing: it is one
-- transaction, and every statement is safe to run again.
-- ═══════════════════════════════════════════════════════════════
begin;

-- ───── 0069_guilds ─────
-- Guilds, stage 1 (user 2026-11-13): found / join / leave, roles, join
-- requests, guild chat.
--
-- The game stays fully playable without a guild; this only adds. Every rule
-- that must hold (50 members at most, one guild per player, who may promote
-- or remove whom) lives in the functions below, not in the app, so a modified
-- client cannot break it. The app calls them through `supabase.rpc(...)`.
--
-- Later stages (help tips, donations, guild level + bonuses, quests, boss,
-- breeding board) add their own tables and migrations on top of this one.

create table if not exists public.guilds (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 3 and 24),
  description text not null default '' check (char_length(description) <= 280),
  emblem      smallint not null default 0 check (emblem between 0 and 31),
  is_open     boolean not null default true,   -- false = join by request
  leader_id   uuid not null references auth.users (id),
  level       integer not null default 1,      -- raised by stage 4
  points      bigint  not null default 0,      -- contributions, stage 3+
  created_at  timestamptz not null default now()
);
create unique index if not exists guilds_name_key on public.guilds (lower(btrim(name)));

-- One row per player: a player is in at most ONE guild (primary key).
create table if not exists public.guild_members (
  user_id   uuid primary key references auth.users (id) on delete cascade,
  guild_id  uuid not null references public.guilds (id) on delete cascade,
  role      text not null default 'member' check (role in ('leader', 'officer', 'member')),
  joined_at timestamptz not null default now()
);
create index if not exists guild_members_guild_idx on public.guild_members (guild_id);

create table if not exists public.guild_join_requests (
  guild_id   uuid not null references public.guilds (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (guild_id, user_id)
);

create table if not exists public.guild_messages (
  id         uuid primary key default gen_random_uuid(),
  guild_id   uuid not null references public.guilds (id) on delete cascade,
  sender_id  uuid not null references auth.users (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists guild_messages_feed_idx
  on public.guild_messages (guild_id, created_at desc);

-- ── helpers ────────────────────────────────────────────────────────────────
-- security definer so the policies below can ask "which guild am I in" without
-- recursing into guild_members' own policy.
create or replace function public.my_guild_id() returns uuid
language sql stable security definer set search_path = public as $$
  select guild_id from public.guild_members where user_id = auth.uid()
$$;

create or replace function public.my_guild_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.guild_members where user_id = auth.uid()
$$;

-- ── row level security ─────────────────────────────────────────────────────
alter table public.guilds enable row level security;
alter table public.guild_members enable row level security;
alter table public.guild_join_requests enable row level security;
alter table public.guild_messages enable row level security;

-- Guilds are public (the browse list); members only see their own guild's roster.
drop policy if exists "guilds readable" on public.guilds;
create policy "guilds readable" on public.guilds for select using (true);

drop policy if exists "roster of my guild" on public.guild_members;
create policy "roster of my guild" on public.guild_members
  for select using (guild_id = public.my_guild_id() or user_id = auth.uid());

-- Member COUNT for the browse list without exposing rosters.
create or replace function public.guild_member_counts()
returns table (guild_id uuid, members integer)
language sql stable security definer set search_path = public as $$
  select guild_id, count(*)::integer from public.guild_members group by guild_id
$$;

-- Requests: the applicant sees their own, officers/leader see their guild's.
drop policy if exists "see join requests" on public.guild_join_requests;
create policy "see join requests" on public.guild_join_requests
  for select using (
    user_id = auth.uid()
    or (guild_id = public.my_guild_id() and public.my_guild_role() in ('leader', 'officer'))
  );

drop policy if exists "read guild chat" on public.guild_messages;
create policy "read guild chat" on public.guild_messages
  for select using (guild_id = public.my_guild_id());

drop policy if exists "write guild chat" on public.guild_messages;
create policy "write guild chat" on public.guild_messages
  for insert with check (sender_id = auth.uid() and guild_id = public.my_guild_id());

-- No direct writes to guilds / members / requests: the functions below do it.

-- ── actions ────────────────────────────────────────────────────────────────
create or replace function public._guild_add_member(p_guild uuid, p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.guild_members where guild_id = p_guild) >= 50 then
    raise exception 'guild_full';
  end if;
  insert into public.guild_members (user_id, guild_id, role) values (p_user, p_guild, p_role);
  delete from public.guild_join_requests where user_id = p_user;
end $$;

create or replace function public.guild_create(
  p_name text, p_description text, p_emblem integer, p_open boolean
) returns uuid language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if exists (select 1 from public.guild_members where user_id = auth.uid()) then
    raise exception 'already_in_guild';
  end if;
  insert into public.guilds (name, description, emblem, is_open, leader_id)
    values (btrim(p_name), coalesce(p_description, ''), coalesce(p_emblem, 0),
            coalesce(p_open, true), auth.uid())
    returning id into g;
  perform public._guild_add_member(g, auth.uid(), 'leader');
  return g;
end $$;

-- Open guild: in at once. Closed guild: leaves a request instead.
-- Returns 'joined' or 'requested'.
create or replace function public.guild_join(p_guild uuid)
returns text language plpgsql security definer set search_path = public as $$
declare g public.guilds;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if exists (select 1 from public.guild_members where user_id = auth.uid()) then
    raise exception 'already_in_guild';
  end if;
  select * into g from public.guilds where id = p_guild;
  if not found then raise exception 'no_such_guild'; end if;
  if g.is_open then
    perform public._guild_add_member(p_guild, auth.uid(), 'member');
    return 'joined';
  end if;
  insert into public.guild_join_requests (guild_id, user_id) values (p_guild, auth.uid())
    on conflict do nothing;
  return 'requested';
end $$;

create or replace function public.guild_cancel_request(p_guild uuid)
returns void language sql security definer set search_path = public as $$
  delete from public.guild_join_requests where guild_id = p_guild and user_id = auth.uid()
$$;

-- Officers and the leader decide on a request.
create or replace function public.guild_decide_request(p_user uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id();
begin
  if g is null or public.my_guild_role() not in ('leader', 'officer') then
    raise exception 'not_allowed';
  end if;
  if not exists (select 1 from public.guild_join_requests where guild_id = g and user_id = p_user) then
    return;
  end if;
  if p_accept then
    if exists (select 1 from public.guild_members where user_id = p_user) then
      delete from public.guild_join_requests where user_id = p_user;
      raise exception 'already_in_guild';
    end if;
    perform public._guild_add_member(g, p_user, 'member');
  else
    delete from public.guild_join_requests where guild_id = g and user_id = p_user;
  end if;
end $$;

-- Leaving. The leader leaving hands the guild to the longest-standing officer,
-- else the longest-standing member; the last one out closes the guild.
create or replace function public.guild_leave()
returns void language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); r text := public.my_guild_role(); heir uuid;
begin
  if g is null then return; end if;
  delete from public.guild_members where user_id = auth.uid();
  if r = 'leader' then
    select user_id into heir from public.guild_members where guild_id = g
      order by (role = 'officer') desc, joined_at asc limit 1;
    if heir is null then
      delete from public.guilds where id = g;
    else
      update public.guild_members set role = 'leader' where user_id = heir;
      update public.guilds set leader_id = heir where id = g;
    end if;
  end if;
end $$;

-- Leader only: member <-> officer, or hand over leadership ('leader').
create or replace function public.guild_set_role(p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id();
begin
  if g is null or public.my_guild_role() <> 'leader' then raise exception 'not_allowed'; end if;
  if p_user = auth.uid() or p_role not in ('leader', 'officer', 'member') then
    raise exception 'bad_request';
  end if;
  if not exists (select 1 from public.guild_members where user_id = p_user and guild_id = g) then
    raise exception 'not_a_member';
  end if;
  if p_role = 'leader' then
    update public.guild_members set role = 'officer' where user_id = auth.uid();
    update public.guilds set leader_id = p_user where id = g;
  end if;
  update public.guild_members set role = p_role where user_id = p_user;
end $$;

-- Leader may remove anyone; an officer only plain members.
create or replace function public.guild_kick(p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); my text := public.my_guild_role(); theirs text;
begin
  if g is null or my not in ('leader', 'officer') or p_user = auth.uid() then
    raise exception 'not_allowed';
  end if;
  select role into theirs from public.guild_members where user_id = p_user and guild_id = g;
  if theirs is null then return; end if;
  if theirs = 'leader' or (my = 'officer' and theirs <> 'member') then
    raise exception 'not_allowed';
  end if;
  delete from public.guild_members where user_id = p_user;
end $$;

-- Leader edits the guild's face.
create or replace function public.guild_update(
  p_description text, p_emblem integer, p_open boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if public.my_guild_role() <> 'leader' then raise exception 'not_allowed'; end if;
  update public.guilds
     set description = coalesce(p_description, description),
         emblem = coalesce(p_emblem, emblem),
         is_open = coalesce(p_open, is_open)
   where id = public.my_guild_id();
end $$;

grant execute on function
  public.my_guild_id(), public.my_guild_role(), public.guild_member_counts(),
  public.guild_create(text, text, integer, boolean), public.guild_join(uuid),
  public.guild_cancel_request(uuid), public.guild_decide_request(uuid, boolean),
  public.guild_leave(), public.guild_set_role(uuid, text), public.guild_kick(uuid),
  public.guild_update(text, integer, boolean)
to authenticated;

-- ───── 0070_guild_help ─────
-- Guilds, stage 3 (user 2026-11-13): help tips.
--
-- A member asks the guild for help with a running timer (a building under
-- construction, an egg being bred or hatched, a monster in the Healing Hut).
-- Each guild mate can help ONCE per request; every help cuts a percentage off
-- the REMAINING time (no minimum — percent only).
--
-- The helper never touches the owner's rows. A help is its own row; the
-- owner's game collects the new ones (guild_take_helps) and shortens its own
-- timer, so the owner's client can never overwrite a help with stale data.
--
-- No table here has a read/write policy on purpose: with RLS on and no policy
-- nothing can be read or written directly — every access goes through the
-- functions below, which check guild membership.

create table if not exists public.guild_help_requests (
  id           uuid primary key default gen_random_uuid(),
  guild_id     uuid not null references public.guilds (id) on delete cascade,
  requester_id uuid not null references auth.users (id) on delete cascade,
  kind         text not null check (kind in ('build', 'breed', 'heal')),
  target_id    text not null,                       -- building / breeding job / creature id
  label        text not null default '' check (char_length(label) <= 60),
  expires_at   timestamptz not null,                -- when the timer would end anyway
  created_at   timestamptz not null default now(),
  unique (requester_id, kind, target_id)
);
create index if not exists guild_help_requests_guild_idx
  on public.guild_help_requests (guild_id, expires_at);

create table if not exists public.guild_helps (
  request_id uuid not null references public.guild_help_requests (id) on delete cascade,
  helper_id  uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  applied_at timestamptz,                            -- set when the owner's game took it
  primary key (request_id, helper_id)
);

alter table public.guild_help_requests enable row level security;
alter table public.guild_helps enable row level security;

-- Ask for help. Asking again for the same target starts a fresh request.
create or replace function public.guild_request_help(
  p_kind text, p_target text, p_label text, p_expires timestamptz
) returns uuid language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); r uuid;
begin
  if g is null then raise exception 'not_in_guild'; end if;
  if p_expires <= now() then raise exception 'already_done'; end if;
  delete from public.guild_help_requests
   where requester_id = auth.uid() and kind = p_kind and target_id = p_target;
  insert into public.guild_help_requests (guild_id, requester_id, kind, target_id, label, expires_at)
    values (g, auth.uid(), p_kind, p_target, left(coalesce(p_label, ''), 60), p_expires)
    returning id into r;
  return r;
end $$;

-- Help one request. Returns 'ok', 'already', 'capped' (10 helps is the most a
-- request takes) or 'expired'. A help is worth a guild point.
create or replace function public.guild_give_help(p_request uuid)
returns text language plpgsql security definer set search_path = public as $$
declare q public.guild_help_requests; n integer;
begin
  select * into q from public.guild_help_requests where id = p_request;
  if not found or q.expires_at <= now() then return 'expired'; end if;
  if q.guild_id is distinct from public.my_guild_id() or q.requester_id = auth.uid() then
    raise exception 'not_allowed';
  end if;
  if exists (select 1 from public.guild_helps where request_id = p_request and helper_id = auth.uid()) then
    return 'already';
  end if;
  select count(*) into n from public.guild_helps where request_id = p_request;
  if n >= 10 then return 'capped'; end if;
  insert into public.guild_helps (request_id, helper_id) values (p_request, auth.uid());
  update public.guilds set points = points + 1 where id = q.guild_id;
  return 'ok';
end $$;

-- What my guild mates are waiting on: not mine, not expired, not full, and not
-- yet helped by me.
create or replace function public.guild_open_requests()
returns table (
  id uuid, requester_id uuid, requester_name text, kind text, label text,
  helps integer, expires_at timestamptz
) language sql stable security definer set search_path = public as $$
  select q.id, q.requester_id, coalesce(p.username, 'Player'), q.kind, q.label,
         (select count(*)::integer from public.guild_helps h where h.request_id = q.id),
         q.expires_at
    from public.guild_help_requests q
    left join public.profiles p on p.id = q.requester_id
   where q.guild_id = public.my_guild_id()
     and q.requester_id <> auth.uid()
     and q.expires_at > now()
     and (select count(*) from public.guild_helps h where h.request_id = q.id) < 10
     and not exists (select 1 from public.guild_helps h
                      where h.request_id = q.id and h.helper_id = auth.uid())
   order by q.created_at
$$;

-- My own live requests and how many helps each has so far.
create or replace function public.guild_my_requests()
returns table (kind text, target_id text, helps integer)
language sql stable security definer set search_path = public as $$
  select q.kind, q.target_id,
         (select count(*)::integer from public.guild_helps h where h.request_id = q.id)
    from public.guild_help_requests q
   where q.requester_id = auth.uid() and q.expires_at > now()
$$;

-- The owner's game collects helps it has not applied yet. Returns one row per
-- target with how many new helps there are, and marks them taken.
create or replace function public.guild_take_helps()
returns table (kind text, target_id text, n integer)
language sql security definer set search_path = public as $$
  with taken as (
    update public.guild_helps h
       set applied_at = now()
      from public.guild_help_requests q
     where h.request_id = q.id and q.requester_id = auth.uid() and h.applied_at is null
    returning q.kind as k, q.target_id as t
  )
  select k, t, count(*)::integer from taken group by k, t
$$;

grant execute on function
  public.guild_request_help(text, text, text, timestamptz),
  public.guild_give_help(uuid), public.guild_open_requests(),
  public.guild_my_requests(), public.guild_take_helps()
to authenticated;

-- ───── 0071_guild_crest ─────
-- Guilds: the crest creator (user 2026-11-13).
--
-- A crest is a few small numbers: shape, pattern, symbol and three colours,
-- e.g. {"s":0,"p":4,"y":2,"c1":5,"c2":0,"c3":2}. The app validates and draws
-- it; a guild with no crest (or one an older client wrote) gets a crest made
-- from its name. The old numeric `emblem` column stays and is no longer used.
--
-- guild_create / guild_update change signature (a crest instead of an emblem
-- number), so the old versions go first.

alter table public.guilds add column if not exists crest jsonb;

alter table public.guilds drop constraint if exists guilds_crest_size;
alter table public.guilds add constraint guilds_crest_size
  check (crest is null or (jsonb_typeof(crest) = 'object' and length(crest::text) <= 120));

drop function if exists public.guild_create(text, text, integer, boolean);
drop function if exists public.guild_update(text, integer, boolean);

create or replace function public.guild_create(
  p_name text, p_description text, p_crest jsonb, p_open boolean
) returns uuid language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if exists (select 1 from public.guild_members where user_id = auth.uid()) then
    raise exception 'already_in_guild';
  end if;
  insert into public.guilds (name, description, crest, is_open, leader_id)
    values (btrim(p_name), coalesce(p_description, ''), p_crest,
            coalesce(p_open, true), auth.uid())
    returning id into g;
  perform public._guild_add_member(g, auth.uid(), 'leader');
  return g;
end $$;

create or replace function public.guild_update(
  p_description text, p_crest jsonb, p_open boolean
) returns void language plpgsql security definer set search_path = public as $$
begin
  if public.my_guild_role() <> 'leader' then raise exception 'not_allowed'; end if;
  update public.guilds
     set description = coalesce(p_description, description),
         crest = coalesce(p_crest, crest),
         is_open = coalesce(p_open, is_open)
   where id = public.my_guild_id();
end $$;

grant execute on function
  public.guild_create(text, text, jsonb, boolean),
  public.guild_update(text, jsonb, boolean)
to authenticated;

-- ───── 0072_guild_level_quests ─────
-- Guilds, stage 4 (user 2026-11-13): guild level and weekly quests.
--
-- Points -> level, with the thresholds below (mirrored in the app's
-- kGuildLevelPoints; change both together):
--   level  1  2   3   4   5    6    7    8    9    10
--   points 0  50  150 350 700  1200 2000 3200 5000 8000
-- Points come from helping (1 each) and from weekly quests (100 each). The
-- level's bonuses live in the app (+build speed, +wood/stone yield, +battle XP,
-- up to 10 % at level 10) — the server only keeps points and level.
--
-- Weekly quests: three per guild per ISO week, goals scaled by member count,
-- created on first look. A quest pays its 100 points once, the moment its
-- goal is reached. Progress is reported by the members' games.

create or replace function public._guild_level_for(p bigint)
returns integer language sql immutable as $$
  select greatest(1, (select count(*)::integer
    from unnest(array[0, 50, 150, 350, 700, 1200, 2000, 3200, 5000, 8000]) t where t <= p))
$$;

create or replace function public._guild_add_points(p_guild uuid, p_n integer)
returns void language sql security definer set search_path = public as $$
  update public.guilds
     set points = points + p_n,
         level  = public._guild_level_for(points + p_n)
   where id = p_guild
$$;

create table if not exists public.guild_quests (
  guild_id uuid not null references public.guilds (id) on delete cascade,
  week     date not null,
  kind     text not null check (kind in ('wins', 'helps', 'builds')),
  goal     integer not null,
  progress integer not null default 0,
  rewarded boolean not null default false,
  primary key (guild_id, week, kind)
);
alter table public.guild_quests enable row level security;   -- functions only

create or replace function public._guild_quests_ensure(p_guild uuid)
returns void language plpgsql security definer set search_path = public as $$
declare w date := date_trunc('week', now())::date;
        m integer := (select count(*) from public.guild_members where guild_id = p_guild);
begin
  insert into public.guild_quests (guild_id, week, kind, goal) values
    (p_guild, w, 'wins',   greatest(10, 3 * m)),
    (p_guild, w, 'helps',  greatest(10, 4 * m)),
    (p_guild, w, 'builds', greatest(5,  2 * m))
  on conflict do nothing;
end $$;

create or replace function public._guild_quest_add(p_guild uuid, p_kind text, p_n integer)
returns void language plpgsql security definer set search_path = public as $$
declare w date := date_trunc('week', now())::date; q public.guild_quests;
begin
  perform public._guild_quests_ensure(p_guild);
  update public.guild_quests
     set progress = least(goal, progress + greatest(p_n, 0))
   where guild_id = p_guild and week = w and kind = p_kind
   returning * into q;
  if found and q.progress >= q.goal and not q.rewarded then
    update public.guild_quests set rewarded = true
     where guild_id = p_guild and week = w and kind = p_kind;
    perform public._guild_add_points(p_guild, 100);
  end if;
end $$;

-- This week's quests for my guild.
create or replace function public.guild_quests_current()
returns table (kind text, goal integer, progress integer, rewarded boolean, ends_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); w date := date_trunc('week', now())::date;
begin
  if g is null then return; end if;
  perform public._guild_quests_ensure(g);
  return query
    select q.kind, q.goal, q.progress, q.rewarded, (w + 7)::timestamptz
      from public.guild_quests q where q.guild_id = g and q.week = w order by q.kind;
end $$;

-- A member's game reports something that counts: 'wins' or 'builds'.
create or replace function public.guild_quest_progress(p_kind text, p_n integer)
returns void language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id();
begin
  if g is null or p_kind not in ('wins', 'builds') then return; end if;
  perform public._guild_quest_add(g, p_kind, least(coalesce(p_n, 1), 20));
end $$;

-- Helping now also moves the guild level and the weekly "helps" quest.
create or replace function public.guild_give_help(p_request uuid)
returns text language plpgsql security definer set search_path = public as $$
declare q public.guild_help_requests; n integer;
begin
  select * into q from public.guild_help_requests where id = p_request;
  if not found or q.expires_at <= now() then return 'expired'; end if;
  if q.guild_id is distinct from public.my_guild_id() or q.requester_id = auth.uid() then
    raise exception 'not_allowed';
  end if;
  if exists (select 1 from public.guild_helps where request_id = p_request and helper_id = auth.uid()) then
    return 'already';
  end if;
  select count(*) into n from public.guild_helps where request_id = p_request;
  if n >= 10 then return 'capped'; end if;
  insert into public.guild_helps (request_id, helper_id) values (p_request, auth.uid());
  perform public._guild_add_points(q.guild_id, 1);
  perform public._guild_quest_add(q.guild_id, 'helps', 1);
  return 'ok';
end $$;

grant execute on function
  public.guild_quests_current(), public.guild_quest_progress(text, integer),
  public.guild_give_help(uuid)
to authenticated;

-- ───── 0073_guild_studs ─────
-- Guilds, stage 5 (user 2026-11-13): the breeding board — monster loans.
--
-- A member lists up to 3 of their monsters. A guild mate can then "borrow" one
-- as the second parent of a mating. Nothing leaves its owner: the borrower only
-- gets a COPY OF THE GENES as they were when it was listed, to breed with one
-- of their own monsters of the same species and the opposite sex.
--
-- Balance rules (all enforced here):
--   * a listed monster rests 12 h after each loan,
--   * one loan per day for the borrower (two from guild level 5),
--   * legendaries cannot be listed,
--   * the borrower pays a gold fee by rarity, which goes to the owner
--     (a transfer, so no gold is created); the guild earns 2 points per loan.
--
-- The owner's game collects the fees it has earned (guild_stud_take_fees), the
-- same pattern as guild helps: nobody writes into anyone else's rows.

create table if not exists public.guild_studs (
  id          uuid primary key default gen_random_uuid(),
  guild_id    uuid not null references public.guilds (id) on delete cascade,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  creature_id text not null,
  species_id  text not null,
  name        text not null default '',
  gender      text not null check (gender in ('male', 'female')),
  level       integer not null default 1,
  rarity      text not null check (rarity in ('common', 'uncommon', 'rare', 'epic')),
  genes       jsonb not null,                       -- {"base": {...}, "slope": {...}}
  ready_at    timestamptz not null default now(),   -- rests until then
  listed_at   timestamptz not null default now(),
  unique (owner_id, creature_id),
  check (length(genes::text) <= 2000)
);
create index if not exists guild_studs_guild_idx on public.guild_studs (guild_id);

create table if not exists public.guild_stud_loans (
  id          uuid primary key default gen_random_uuid(),
  stud_id     uuid references public.guild_studs (id) on delete set null,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  borrower_id uuid not null references auth.users (id) on delete cascade,
  fee         integer not null,
  created_at  timestamptz not null default now(),
  fee_taken_at timestamptz
);
create index if not exists guild_stud_loans_owner_idx on public.guild_stud_loans (owner_id, fee_taken_at);
create index if not exists guild_stud_loans_borrower_idx on public.guild_stud_loans (borrower_id, created_at);

alter table public.guild_studs enable row level security;       -- functions only
alter table public.guild_stud_loans enable row level security;

create or replace function public._guild_stud_fee(p_rarity text) returns integer
language sql immutable as $$
  select case p_rarity when 'common' then 60 when 'uncommon' then 120
                       when 'rare' then 240 when 'epic' then 480 else 60 end
$$;

-- List (or refresh the snapshot of) one of my monsters.
create or replace function public.guild_stud_list(
  p_creature text, p_species text, p_name text, p_gender text,
  p_level integer, p_rarity text, p_genes jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); id_ uuid;
begin
  if g is null then raise exception 'not_in_guild'; end if;
  if p_rarity not in ('common', 'uncommon', 'rare', 'epic') then raise exception 'not_allowed'; end if;
  if not exists (select 1 from public.guild_studs where owner_id = auth.uid() and creature_id = p_creature)
     and (select count(*) from public.guild_studs where owner_id = auth.uid()) >= 3 then
    raise exception 'stud_limit';
  end if;
  insert into public.guild_studs
      (guild_id, owner_id, creature_id, species_id, name, gender, level, rarity, genes)
    values (g, auth.uid(), p_creature, p_species, left(coalesce(p_name, ''), 40),
            p_gender, greatest(p_level, 1), p_rarity, p_genes)
  on conflict (owner_id, creature_id) do update
     set guild_id = excluded.guild_id, species_id = excluded.species_id,
         name = excluded.name, gender = excluded.gender, level = excluded.level,
         rarity = excluded.rarity, genes = excluded.genes
  returning id into id_;
  return id_;
end $$;

create or replace function public.guild_stud_unlist(p_creature text)
returns void language sql security definer set search_path = public as $$
  delete from public.guild_studs where owner_id = auth.uid() and creature_id = p_creature
$$;

-- Everything listed in my guild, mine included (the app tells them apart).
create or replace function public.guild_stud_board()
returns table (
  id uuid, owner_id uuid, owner_name text, creature_id text, species_id text,
  name text, gender text, level integer, rarity text, genes jsonb,
  ready_at timestamptz, fee integer
) language sql stable security definer set search_path = public as $$
  select s.id, s.owner_id, coalesce(p.username, 'Player'), s.creature_id, s.species_id,
         s.name, s.gender, s.level, s.rarity, s.genes, s.ready_at,
         public._guild_stud_fee(s.rarity)
    from public.guild_studs s
    left join public.profiles p on p.id = s.owner_id
   where s.guild_id = public.my_guild_id()
   order by s.listed_at
$$;

-- Borrow one. Returns the fee. The app then spends it and starts the mating;
-- the loan itself (resting time, daily limit, owner's fee) is recorded here.
create or replace function public.guild_stud_borrow(p_stud uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare s public.guild_studs; used integer; lim integer; lvl integer; f integer;
begin
  select * into s from public.guild_studs where id = p_stud;
  if not found then raise exception 'no_such_stud'; end if;
  if s.guild_id is distinct from public.my_guild_id() or s.owner_id = auth.uid() then
    raise exception 'not_allowed';
  end if;
  if s.ready_at > now() then raise exception 'stud_resting'; end if;
  select level into lvl from public.guilds where id = s.guild_id;
  lim := case when lvl >= 5 then 2 else 1 end;
  select count(*) into used from public.guild_stud_loans
   where borrower_id = auth.uid() and created_at >= date_trunc('day', now());
  if used >= lim then raise exception 'loan_limit'; end if;
  f := public._guild_stud_fee(s.rarity);
  update public.guild_studs set ready_at = now() + interval '12 hours' where id = s.id;
  insert into public.guild_stud_loans (stud_id, owner_id, borrower_id, fee)
    values (s.id, s.owner_id, auth.uid(), f);
  perform public._guild_add_points(s.guild_id, 2);
  return f;
end $$;

-- How many loans I have used today and my daily limit — for the app's button.
create or replace function public.guild_stud_allowance()
returns table (used integer, lim integer) language sql stable security definer
set search_path = public as $$
  select (select count(*)::integer from public.guild_stud_loans
           where borrower_id = auth.uid() and created_at >= date_trunc('day', now())),
         case when coalesce((select level from public.guilds where id = public.my_guild_id()), 1) >= 5
              then 2 else 1 end
$$;

-- The owner's game collects the fees it has earned: total gold, then marked.
create or replace function public.guild_stud_take_fees()
returns integer language plpgsql security definer set search_path = public as $$
declare total integer;
begin
  with t as (
    update public.guild_stud_loans set fee_taken_at = now()
     where owner_id = auth.uid() and fee_taken_at is null
     returning fee)
  select coalesce(sum(fee), 0)::integer into total from t;
  return total;
end $$;

grant execute on function
  public.guild_stud_list(text, text, text, text, integer, text, jsonb),
  public.guild_stud_unlist(text), public.guild_stud_board(),
  public.guild_stud_borrow(uuid), public.guild_stud_allowance(),
  public.guild_stud_take_fees()
to authenticated;

-- ───── 0074_guild_boss_ranking ─────
-- Guilds, stage 6 (user 2026-11-13): the weekly guild boss and the ranking.
--
-- One boss per guild per ISO week. Its health bar belongs to the whole guild:
-- every member fights it in a special battle (a normal fight against a strong
-- boss monster that the member's own game builds) and the damage they do — as
-- a percentage of that monster's health, 0..100 — is added to the shared bar.
--
-- Rules, all enforced here:
--   * 3 attempts per member per day. An attempt is used up when the fight
--     BEGINS, so closing the app mid-fight does not give a free retry.
--   * one result per attempt (a "pending" flag), at most 100 points of damage.
--   * the bar is 300 points per member (at least 10 members' worth); when it
--     is emptied the guild gets 150 points, once.
--   * a member's reward is gold: 2 per damage point, +300 if the boss fell. It
--     is claimed once per week, for the current week once the boss has fallen,
--     for a past week always.
-- The ranking lists the guilds by points.

create table if not exists public.guild_bosses (
  guild_id    uuid not null references public.guilds (id) on delete cascade,
  week        date not null,
  species_id  text not null,
  level       integer not null,
  max_hp      integer not null,
  damage      integer not null default 0,
  defeated_at timestamptz,
  primary key (guild_id, week)
);

create table if not exists public.guild_boss_members (
  guild_id     uuid not null,
  week         date not null,
  user_id      uuid not null references auth.users (id) on delete cascade,
  damage       integer not null default 0,
  attempts_day date,
  attempts     integer not null default 0,
  pending      boolean not null default false,
  claimed      boolean not null default false,
  primary key (guild_id, week, user_id),
  foreign key (guild_id, week) references public.guild_bosses (guild_id, week) on delete cascade
);

alter table public.guild_bosses enable row level security;         -- functions only
alter table public.guild_boss_members enable row level security;

-- This week's boss; the first caller of the week chooses its species and level
-- (the app derives them from the week number and the guild level).
create or replace function public.guild_boss_current(p_species text, p_level integer)
returns table (
  species_id text, level integer, max_hp integer, damage integer,
  defeated boolean, my_damage integer, attempts_left integer, ends_at timestamptz
) language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); w date := date_trunc('week', now())::date;
        m integer; b public.guild_bosses; me public.guild_boss_members; left_ integer;
begin
  if g is null then return; end if;
  select count(*) into m from public.guild_members where guild_id = g;
  insert into public.guild_bosses (guild_id, week, species_id, level, max_hp)
    values (g, w, left(p_species, 60), greatest(p_level, 1), 300 * greatest(m, 10))
    on conflict do nothing;
  select * into b from public.guild_bosses where guild_id = g and week = w;
  select * into me from public.guild_boss_members
   where guild_id = g and week = w and user_id = auth.uid();
  left_ := 3 - case when me.attempts_day = current_date then coalesce(me.attempts, 0) else 0 end;
  return query select b.species_id, b.level, b.max_hp, b.damage, b.defeated_at is not null,
                      coalesce(me.damage, 0), greatest(left_, 0), (w + 7)::timestamptz;
end $$;

-- Starts an attempt: uses it up and marks one result as expected.
create or replace function public.guild_boss_begin()
returns void language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); w date := date_trunc('week', now())::date;
        b public.guild_bosses; used integer;
begin
  select * into b from public.guild_bosses where guild_id = g and week = w;
  if g is null or not found then raise exception 'no_boss'; end if;
  if b.defeated_at is not null then raise exception 'boss_defeated'; end if;
  insert into public.guild_boss_members (guild_id, week, user_id)
    values (g, w, auth.uid()) on conflict do nothing;
  select case when attempts_day = current_date then attempts else 0 end into used
    from public.guild_boss_members where guild_id = g and week = w and user_id = auth.uid();
  if used >= 3 then raise exception 'no_attempts'; end if;
  update public.guild_boss_members
     set attempts = used + 1, attempts_day = current_date, pending = true
   where guild_id = g and week = w and user_id = auth.uid();
end $$;

-- The result of the attempt that was begun: damage in points, 0..100.
create or replace function public.guild_boss_hit(p_points integer)
returns void language plpgsql security definer set search_path = public as $$
declare g uuid := public.my_guild_id(); w date := date_trunc('week', now())::date;
        pts integer := least(greatest(coalesce(p_points, 0), 0), 100);
        b public.guild_bosses; was_pending boolean; add_ integer;
begin
  select pending into was_pending from public.guild_boss_members
   where guild_id = g and week = w and user_id = auth.uid();
  if g is null or not coalesce(was_pending, false) then return; end if;
  select * into b from public.guild_bosses where guild_id = g and week = w;
  add_ := least(pts, b.max_hp - b.damage);
  update public.guild_bosses set damage = damage + add_ where guild_id = g and week = w
    returning * into b;
  update public.guild_boss_members
     set damage = damage + add_, pending = false
   where guild_id = g and week = w and user_id = auth.uid();
  if b.damage >= b.max_hp and b.defeated_at is null then
    update public.guild_bosses set defeated_at = now() where guild_id = g and week = w;
    perform public._guild_add_points(g, 150);
  end if;
end $$;

-- Who has done how much this week.
create or replace function public.guild_boss_board()
returns table (user_id uuid, name text, damage integer)
language sql stable security definer set search_path = public as $$
  select m.user_id, coalesce(p.username, 'Player'), m.damage
    from public.guild_boss_members m
    left join public.profiles p on p.id = m.user_id
   where m.guild_id = public.my_guild_id()
     and m.week = date_trunc('week', now())::date and m.damage > 0
   order by m.damage desc limit 50
$$;

-- Collects the gold for every week that is ready: gold, then marked.
create or replace function public.guild_boss_claim()
returns integer language plpgsql security definer set search_path = public as $$
declare total integer;
begin
  with t as (
    update public.guild_boss_members m set claimed = true
      from public.guild_bosses b
     where m.guild_id = b.guild_id and m.week = b.week and m.user_id = auth.uid()
       and m.claimed = false and m.damage > 0
       and (b.defeated_at is not null or m.week < date_trunc('week', now())::date)
     returning m.damage * 2 + case when b.defeated_at is not null then 300 else 0 end as gold)
  select coalesce(sum(gold), 0)::integer into total from t;
  return total;
end $$;

-- The ranking: the 50 best guilds by points.
create or replace function public.guild_ranking()
returns table (
  id uuid, name text, crest jsonb, level integer, points bigint, members integer, rank integer
) language sql stable security definer set search_path = public as $$
  select g.id, g.name, g.crest, g.level, g.points,
         (select count(*)::integer from public.guild_members m where m.guild_id = g.id),
         (row_number() over (order by g.points desc, g.created_at))::integer
    from public.guilds g
   order by g.points desc, g.created_at limit 50
$$;

grant execute on function
  public.guild_boss_current(text, integer), public.guild_boss_begin(),
  public.guild_boss_hit(integer), public.guild_boss_board(),
  public.guild_boss_claim(), public.guild_ranking()
to authenticated;

commit;
