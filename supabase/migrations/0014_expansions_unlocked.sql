-- Expansion unlocks: how many Building Plots the player has EARNED as a reward
-- (user 2026-07-17: build plots are no longer a tech — they unlock one at a
-- time from "expansion points" cleared on the map). buildPlotLimit reads this;
-- SettlementController.unlockExpansion() increments it.
--
-- `profiles` is shared with the fitness app and already holds real players, so
-- default 0 backfills every existing row as "no expansions earned yet" — the
-- correct starting state for everyone.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'expansions_unlocked'
  ) then
    alter table public.profiles
      add column expansions_unlocked int not null default 0;
  end if;
end $$;
