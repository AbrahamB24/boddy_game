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
