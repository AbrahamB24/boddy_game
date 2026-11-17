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
