-- Survival Mode (user 2026-09-06): an endless battle mode, separate from the
-- linear campaign — pick a full 6-monster party, fight floor after floor
-- with no return to base between them, until wiped or you retreat. This
-- column is purely a high score (SettlementController.survivalBestFloor):
-- nothing reads it to gate anything, it only ever grows. Default 0 backfills
-- every existing row as "no run banked yet" — correct for everyone, same as
-- battles_cleared's own backfill in migration 0019.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'survival_best_floor'
  ) then
    alter table public.profiles
      add column survival_best_floor int not null default 0;
  end if;
end $$;
