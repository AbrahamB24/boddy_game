-- Linear-path progression (user 2026-07-24): the overworld is now ONE line of
-- numbered battles. `battles_cleared` is how far along that line the player has
-- won — it replaces the coarse dungeon_max_stage (region 1/2/3) as the fine
-- progress counter that drives party size (partySizeForBattle) and, later,
-- building/legendary unlocks by map milestone.
--
-- `profiles` is shared with the fitness app and already holds real players, so
-- default 0 backfills every existing row as "no campaign battles won yet" — the
-- correct starting state for everyone. dungeon_max_stage stays for now as the
-- era/region counter until the linear rebuild fully retires it.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'battles_cleared'
  ) then
    alter table public.profiles
      add column battles_cleared int not null default 0;
  end if;
end $$;
