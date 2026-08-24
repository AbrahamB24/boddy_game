-- ═══════════════════════════════════════════════════════════════════════════
-- small_stone_camp -> small_quarry
--
-- Im Supabase SQL-Editor als EIN Skript ausführen. Danach App komplett neu
-- starten.
--
-- ── Warum (user 2026-08-23) ──
-- Die Blender-Datei heisst jetzt small_quarry.blend (eine deutlich breitere
-- Steinbruchwand, 5 x 4 statt 4 x 3) statt small_stone_camp.blend — Code und
-- DB müssen der gleichen id folgen.
--
-- ── Warum kopieren-umhängen-löschen ──
-- Ein `update building_defs set id = ...` scheitert an einem Fremdschlüssel
-- aus placed_buildings, sobald Zeilen daran hängen. Erst die neue Def
-- anlegen, dann die Kinder umhängen, dann die alte löschen — see
-- rename_era1_ids.sql, gleiches Muster, hier nur für die eine id.
--
-- Idempotent: ein zweiter Lauf meldet null Zeilen.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  col record;
begin
  -- 1. Die Def unter der neuen id anlegen, falls sie noch fehlt.
  insert into public.building_defs
  select (rec).*
    from (
      select jsonb_populate_record(
               null::public.building_defs,
               to_jsonb(b) || jsonb_build_object('id', 'small_quarry')
             ) as rec
        from public.building_defs b
       where b.id = 'small_stone_camp'
    ) t
  on conflict (id) do nothing;

  -- 2. Alles, was ein Gebäude bei seiner id nennt.
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
      col.table_name, col.column_name, 'small_quarry', col.column_name,
      'small_stone_camp');
  end loop;

  -- 3. Erst jetzt, wo nichts mehr darauf zeigt, die alte Def entfernen.
  delete from public.building_defs where id = 'small_stone_camp';
end $$;

commit;

-- ── Kontrolle ──
-- Muss LEER zurückkommen: keine alte id ist irgendwo übrig.
select 'def' as wo, id as alte_id
  from public.building_defs
 where id = 'small_stone_camp'
union all
select 'platziert', building_type_id
  from public.placed_buildings
 where building_type_id = 'small_stone_camp';

-- Und die hier zeigt die neue Def mit ihrer Grösse.
select id, name, grid_w || 'x' || grid_h as groesse
  from public.building_defs
 where id = 'small_quarry';
