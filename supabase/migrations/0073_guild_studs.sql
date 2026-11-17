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
