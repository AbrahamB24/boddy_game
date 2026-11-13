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
