-- ═══════════════════════════════════════════════════════════════════════════
-- lux_fish -> fish_shop, lux_meat -> butcher_shop
--
-- Im Supabase SQL-Editor als EIN Skript ausführen. Danach App komplett neu
-- starten.
--
-- ── Warum (user 2026-09-06) ──
-- Die Blender-Quelldateien heissen jetzt fish_shop.blend / butcher_shop.blend
-- (vorher lux_fish.blend / lux_fur.blend — nur die .blend1-Backups tragen noch
-- die alten Namen) statt lux_fish.blend / lux_meat.blend. Code und DB müssen
-- der gleichen id folgen. Die ANZEIGENAMEN bleiben unverändert ("🐟 Fish
-- Shop", "🥩 Butcher Shop") — nur die interne id ändert sich.
--
-- Reine Gebäude-id-Umbenennung, wie rename_small_quarry.sql — NICHT wie
-- rename_fur_to_meat.sql, das zusätzlich die RESSOURCE fur->meat umbenannte
-- (gather_defs/item_defs/area_defs.spots/resources.goods). Hier bleiben die
-- Ressourcen fish/meat unverändert, nur die Gebäude-id ändert sich.
--
-- ── Warum kopieren-umhängen-löschen ──
-- Ein `update building_defs set id = ...` scheitert an einem Fremdschlüssel
-- aus placed_buildings, sobald Zeilen daran hängen. Erst die neue Def
-- anlegen, dann die Kinder umhängen, dann die alte löschen — see
-- rename_small_quarry.sql, gleiches Muster, hier für beide ids.
--
-- Idempotent: ein zweiter Lauf meldet null Zeilen.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  m   record;
  col record;
begin
  for m in
    select * from (values
      ('lux_fish', 'fish_shop'),
      ('lux_meat', 'butcher_shop')
    ) as t(alt, neu)
  loop
    -- 1. Die Def unter der neuen id anlegen, falls sie noch fehlt.
    execute format($f$
      insert into public.building_defs
      select (rec).*
        from (
          select jsonb_populate_record(
                   null::public.building_defs,
                   to_jsonb(b) || jsonb_build_object('id', %L)
                 ) as rec
            from public.building_defs b
           where b.id = %L
        ) t
      on conflict (id) do nothing
    $f$, m.neu, m.alt);

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
        col.table_name, col.column_name, m.neu, col.column_name, m.alt);
    end loop;

    -- 3. Erst jetzt, wo nichts mehr darauf zeigt, die alte Def entfernen.
    execute format(
      'delete from public.building_defs where id = %L', m.alt);
  end loop;
end $$;

commit;

-- ── Kontrolle ──
-- Muss LEER zurückkommen: keine alte id ist irgendwo übrig.
select 'def' as wo, id as alte_id
  from public.building_defs
 where id in ('lux_fish', 'lux_meat')
union all
select 'platziert', building_type_id
  from public.placed_buildings
 where building_type_id in ('lux_fish', 'lux_meat');

-- Und die hier zeigt die neuen Defs mit ihrer Grösse.
select id, name, grid_w || 'x' || grid_h as groesse
  from public.building_defs
 where id in ('fish_shop', 'butcher_shop')
 order by id;
