-- ═══════════════════════════════════════════════════════════════════════════
-- Ära-I-ids: den Code auf deine Namensgebung ziehen
--
-- Im Supabase SQL-Editor als EIN Skript ausführen. Danach App komplett neu
-- starten. Ersetzt NICHT building_roster.sql — das braucht es nicht mehr, die
-- Grundflächen holt der Knopf "Renders & Grössen übernehmen" in Dev Mode.
--
-- ── Was hier passiert ──
--     wood_camp_e1          ->  small_wood_camp
--     wood_works_e1         ->  large_wood_camp
--     stone_camp_e1         ->  small_stone_camp
--     stone_works_e1        ->  large_stone_camp
--     special_materials_e1  ->  church
--     special_treasury_e1   ->  marketplace
--     hut                   ->  small_house
--     house                 ->  large_house
--
-- Sieben davon hast du in building_defs schon umbenannt — für die bleibt hier
-- nur das Umhängen der PLATZIERTEN Gebäude, die weiter die alte id tragen.
-- `house` -> `large_house` ist noch offen, deshalb kann das Skript auch die
-- Def selbst umziehen. Beide Fälle laufen durch denselben Block.
--
-- ── Warum kopieren-umhängen-löschen ──
-- Ein `update building_defs set id = ...` scheitert an einem Fremdschlüssel
-- aus placed_buildings, sobald Zeilen daran hängen. Erst die neue Def anlegen,
-- dann die Kinder umhängen, dann die alte löschen — das läuft mit FK, ohne FK
-- und mit ON UPDATE CASCADE gleich.
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
      ('wood_camp_e1',         'small_wood_camp'),
      ('wood_works_e1',        'large_wood_camp'),
      ('stone_camp_e1',        'small_stone_camp'),
      ('stone_works_e1',       'large_stone_camp'),
      ('special_materials_e1', 'church'),
      ('special_treasury_e1',  'marketplace'),
      ('hut',                  'small_house'),
      ('house',                'large_house')
    ) as t(alt, neu)
  loop
    -- 1. Die Def unter der neuen id anlegen, falls sie noch fehlt. Ohne
    --    Spaltenliste, damit das Skript nicht bricht, sobald building_defs
    --    eine Spalte dazubekommt.
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

    -- 2. Alles, was ein Gebäude bei seiner id nennt. Welche Tabellen es gibt,
    --    entscheidet dein Projekt — der Katalog wird gefragt, damit fehlende
    --    Tabellen übersprungen statt zum Fehler werden.
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
 where id in ('wood_camp_e1','wood_works_e1','stone_camp_e1','stone_works_e1',
              'special_materials_e1','special_treasury_e1','hut','house')
union all
select 'platziert', building_type_id
  from public.placed_buildings
 where building_type_id in ('wood_camp_e1','wood_works_e1','stone_camp_e1',
              'stone_works_e1','special_materials_e1','special_treasury_e1',
              'hut','house');

-- Und die hier zeigt, was jetzt ein Bild bekommt: alle 20 müssen dastehen.
select id, name, grid_w || 'x' || grid_h as groesse
  from public.building_defs
 where id in ('castle','breeding_hut','small_house','large_house',
              'small_wood_camp','large_wood_camp','small_stone_camp',
              'large_stone_camp','storehouse','gold_vault','builder_camp',
              'healing_hut','scout_post','trading_post','caravanserai',
              'hatchery','lux_fish','lux_fur','church','marketplace')
 order by id;
