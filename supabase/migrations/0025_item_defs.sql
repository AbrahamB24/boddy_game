-- Craftable / tradeable ITEM content, Dev-Mode-editable like building_defs /
-- area_defs / path_nodes (user 2026-07-25). Columns mirror ItemDef.toDefRow().
-- Idempotent. RLS: authenticated read, dev (profiles.is_dev) write.

create table if not exists public.item_defs (
  id            text primary key,
  name          text not null default '',
  emoji         text,
  description   text,
  kind          text not null default 'heal',
  magnitude     double precision not null default 0,
  buff_stat     text,
  battle_usable boolean not null default false,
  -- {goodId: amount} — the concrete luxury ingredients a recipe consumes.
  ingredients   jsonb not null default '{}'::jsonb,
  supply_cost   double precision not null default 0,
  craft_seconds double precision not null default 0,
  buy_price     int not null default 0,
  sell_price    int not null default 0
);

alter table public.item_defs enable row level security;

drop policy if exists "item_defs read" on public.item_defs;
create policy "item_defs read" on public.item_defs
  for select using (auth.role() = 'authenticated');

drop policy if exists "item_defs dev write" on public.item_defs;
create policy "item_defs dev write" on public.item_defs
  for all
  using (exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.is_dev = true))
  with check (exists (select 1 from public.profiles p
                      where p.id = auth.uid() and p.is_dev = true));
