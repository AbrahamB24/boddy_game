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
