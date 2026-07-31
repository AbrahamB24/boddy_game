-- Two-phase breeding → egg → hatch (user 2026-07-24). Breeding no longer rolls
-- the child directly: a finished mating lays an EGG that sits free (parents
-- released), and the player must later place that egg into a Hatchery, where
-- stationed breeders incubate it a second time before it hatches.
--
-- One column carries the whole lifecycle on the existing breeding_jobs row:
--   'breeding' — parents locked, incubating in the Breeding Hut (ready_at = lay)
--   'egg'      — laid, parents freed, waiting for a Hatchery slot (no timer)
--   'hatching' — placed in the Hatchery, incubating again (ready_at = hatch)
-- Existing rows default to 'breeding', i.e. their old meaning, so nothing in
-- flight is lost by the migration.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'breeding_jobs'
      and column_name = 'status'
  ) then
    alter table public.breeding_jobs
      add column status text not null default 'breeding';
  end if;
end $$;
