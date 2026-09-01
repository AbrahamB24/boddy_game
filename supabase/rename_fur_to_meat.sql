-- ═══════════════════════════════════════════════════════════════════════════
-- fur -> meat
--
-- Im Supabase SQL-Editor als EIN Skript ausführen. Danach App komplett neu
-- starten.
--
-- ── Warum (user 2026-08-31) ──
-- "Ab jetzt ist es nicht mehr fur sondern meat. Daher ist es auch nicht mehr
-- fur ludge, dafür butcher shop" — die Ressource heisst jetzt `meat`, ihr
-- Gebäude "🥩 Butcher Shop" statt "🦫 Fur Lodge" (id lux_meat statt lux_fur).
-- Code und DB müssen der gleichen id folgen.
--
-- ── Was betroffen ist ──
--   1. building_defs / placed_buildings  — lux_fur -> lux_meat (Fremdschlüssel,
--      gleiches Muster wie rename_small_quarry.sql: kopieren, umhängen, löschen)
--   2. gather_defs, item_defs            — reine id-Umbenennung, keine
--      Fremdschlüssel zeigen auf diese Tabellen
--   3. item_defs.ingredients             — jsonb-Schlüssel {"fur": n} -> {"meat": n}
--   4. area_defs.spots                   — jsonb-Array, jedes Element mit
--      "resource":"fur" -> "resource":"meat" (nur Zeilen, die ein Dev je
--      überschrieben hat — die meisten Spieler laufen hier auf dem Dart-
--      Fallback, der schon umbenannt ist)
--   5. resources.goods                   — jsonb-Schlüssel "fur" -> "meat" für
--      JEDE Siedlung; zusätzlich werden Zeilen ohne "fur" in `goods`, aber mit
--      einem alten `fur`-Spaltenwert (pre-0006-Zeilen) nachgezogen
--
-- Die LEGACY-Spalte `resources.fur` selbst bleibt unangetastet (migration 0006
-- liess sie bewusst stehen, siehe deren Kommentar) — `meat` schreibt nur noch
-- in die goods-jsonb-Spalte, nie in eine eigene Spalte.
--
-- Idempotent: ein zweiter Lauf meldet null Zeilen.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ── 1. building_defs / placed_buildings ──────────────────────────────────
do $$
declare
  col record;
begin
  insert into public.building_defs
  select (rec).*
    from (
      select jsonb_populate_record(
               null::public.building_defs,
               to_jsonb(b) || jsonb_build_object('id', 'lux_meat')
             ) as rec
        from public.building_defs b
       where b.id = 'lux_fur'
    ) t
  on conflict (id) do nothing;

  for col in
    select c.table_name, c.column_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema
       and tb.table_name   = c.table_name
     where c.table_schema = 'public'
       and tb.table_type  = 'BASE TABLE'
       and c.data_type in ('text', 'character varying')
       and c.column_name in ('building_type_id', 'building_id', 'target_id')
       and c.table_name <> 'building_defs'
  loop
    execute format(
      'update public.%I set %I = %L where %I = %L',
      col.table_name, col.column_name, 'lux_meat', col.column_name,
      'lux_fur');
  end loop;

  delete from public.building_defs where id = 'lux_fur';
end $$;

-- ── 2. gather_defs / item_defs — plain id rename, no FK points at either ──
update public.gather_defs set id = 'meat' where id = 'fur';
update public.item_defs   set id = 'meat' where id = 'fur';

-- ── 3. item_defs.ingredients — jsonb key rename ──────────────────────────
update public.item_defs
   set ingredients = (ingredients - 'fur')
                      || jsonb_build_object('meat', ingredients->'fur')
 where ingredients ? 'fur';

-- ── 4. area_defs.spots — rename inside the jsonb array ───────────────────
-- Only rows a dev has actually saved (bundled areas live in Dart and are
-- already renamed there); most players read the Dart fallback and this
-- updates zero rows for them, which is expected.
update public.area_defs
   set spots = (
     select jsonb_agg(
              case when s->>'resource' = 'fur'
                   then jsonb_set(s, '{resource}', '"meat"'::jsonb)
                   else s
              end
            )
       from jsonb_array_elements(spots) as s
   )
 where spots @> '[{"resource":"fur"}]'::jsonb;

-- ── 5. resources.goods — the live jsonb every settlement stores in ───────
-- Rows that already migrated to goods jsonb: rename the key in place.
update public.resources
   set goods = (goods - 'fur') || jsonb_build_object('meat', goods->'fur')
 where goods ? 'fur';

-- Rows that never got a `goods` migration at all (pre-0006, goods = '{}' and
-- the legacy fur column still holds the real number) — carry it across now
-- instead of leaving it stranded in a column nothing reads any more.
update public.resources
   set goods = goods || jsonb_build_object('meat', coalesce(fur, 0))
 where goods = '{}'::jsonb
   and coalesce(fur, 0) <> 0;

commit;

-- ── Kontrolle ──
-- Muss LEER zurückkommen: keine alte id/kein alter Schlüssel ist irgendwo übrig.
select 'building_def' as wo, id as alt
  from public.building_defs where id = 'lux_fur'
union all
select 'placed', building_type_id from public.placed_buildings
 where building_type_id = 'lux_fur'
union all
select 'gather_def', id from public.gather_defs where id = 'fur'
union all
select 'item_def', id from public.item_defs where id = 'fur'
union all
select 'item ingredient', id from public.item_defs
 where ingredients ? 'fur'
union all
select 'area spot', id from public.area_defs
 where spots @> '[{"resource":"fur"}]'::jsonb
union all
select 'resources.goods', settlement_id from public.resources
 where goods ? 'fur';

-- Und die hier zeigt die neue Def mit ihrem Namen.
select id, name from public.building_defs where id = 'lux_meat';
