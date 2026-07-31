-- Goods become a single jsonb blob instead of one column per good.
--
-- WHY: every special resource used to need its own column (`fish`, `fur`),
-- plus matching lines in ResourceModel.fromMap/toMap. That made "a new era
-- introduces a new resource" a schema change + a code change, which is exactly
-- the thing that has to be cheap now that goods are era-scoped and their sinks
-- (healing, dungeon entry) ask for "this era's goods" rather than naming one.
-- See lib/features/settlement/data/goods_definitions.dart.
--
-- The legacy fish/fur columns are deliberately KEPT, not dropped:
--   • a client running older code still reads and writes them,
--   • ResourceModel falls back to them when `goods` is absent,
--   • dropping data is not something a migration should do quietly.
-- They simply stop being written once this ships. Drop them in a later
-- migration, once no old client is out there.
--
-- Idempotent, and the backfill only touches rows that haven't got one yet.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'resources'
      and column_name = 'goods'
  ) then
    alter table public.resources
      add column goods jsonb not null default '{}'::jsonb;

    -- Carry every existing settlement's fish/fur into the blob.
    update public.resources
    set goods = jsonb_build_object(
      'fish', coalesce(fish, 0),
      'fur', coalesce(fur, 0)
    )
    where goods = '{}'::jsonb;
  end if;
end $$;
