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
