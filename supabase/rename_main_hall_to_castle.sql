-- ═══════════════════════════════════════════════════════════════════════════
-- main_hall  ->  castle
--
-- Im Supabase SQL-Editor als EIN Skript ausführen. Danach die App komplett
-- neu starten.
--
-- ── Warum es nötig ist ──
-- Jedes PLATZIERTE Gebäude trägt die id, mit der es gebaut wurde. Die Def
-- heisst jetzt `castle`, die Hallen-Zeile in placed_buildings sagt weiter
-- `main_hall` — also schlägt die Karte eine Def nach, die es nicht mehr gibt,
-- und ein Gebäude ohne Def zeichnet nichts. Das ist das ganze „das
-- Hauptgebäude ist weg": die Burg steht noch da, auf ihren Zellen, fertig,
-- mit Level und Arbeitern. Nur ihr eigener Name für sich selbst ist unter ihr
-- weggezogen.
--
-- ── Kopieren, umhängen, löschen — statt umbenennen ──
-- Ein simples `update building_defs set id = 'castle'` scheitert, sobald
-- placed_buildings einen Fremdschlüssel darauf hat und Zeilen daran hängen
-- (ausser bei ON UPDATE CASCADE, worauf man sich nicht verlassen sollte).
-- Deshalb: erst die Def unter der neuen id ANLEGEN, dann die Kinder umhängen,
-- dann die alte löschen. Das läuft mit FK, ohne FK und mit Cascade gleich.
--
-- ── UPDATE, kein Neusetzen ──
-- placed_buildings trägt Level, Baufortschritt und zugewiesene Arbeiter.
-- Löschen und neu platzieren würfe das weg und würde die Halle neu zentrieren.
--
-- Idempotent: ein zweiter Lauf meldet null Zeilen.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- 1. Die Def unter der neuen id anlegen, als exakte Kopie der alten.
--    Ohne Spaltenliste, damit das Skript nicht bricht, sobald building_defs
--    eine Spalte dazubekommt: die Zeile geht über jsonb, bekommt die neue id
--    aufgeprägt und wird zurück in einen Datensatz gegossen.
insert into public.building_defs
select (rec).*
  from (
    select jsonb_populate_record(
             null::public.building_defs,
             to_jsonb(b) || jsonb_build_object('id', 'castle')
           ) as rec
      from public.building_defs b
     where b.id = 'main_hall'
  ) t
on conflict (id) do nothing;

-- 2. Jede platzierte Halle, in jeder Siedlung.
update public.placed_buildings
   set building_type_id = 'castle'
 where building_type_id = 'main_hall';

-- 3. Alles andere, was ein Gebäude bei seiner id nennt. Welche Tabellen es
--    gibt, entscheidet dein Projekt — die Schleife fragt den Katalog, damit
--    fehlende Tabellen übersprungen statt zum Fehler werden.
do $$
declare
  t record;
begin
  for t in
    select c.table_name, c.column_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema
       and tb.table_name   = c.table_name
     where c.table_schema = 'public'
       and tb.table_type  = 'BASE TABLE'
       and c.data_type in ('text', 'character varying')
       and c.column_name in ('building_type_id', 'building_id', 'target_id')
       and c.table_name not in ('building_defs', 'placed_buildings')
  loop
    execute format(
      'update public.%I set %I = ''castle'' where %I = ''main_hall''',
      t.table_name, t.column_name, t.column_name);
  end loop;
end $$;

-- 4. Erst jetzt, wo nichts mehr darauf zeigt, die alte Def entfernen.
delete from public.building_defs where id = 'main_hall';

commit;

-- ── Kontrolle ──
-- Beide Zeilen müssen 0 zurückgeben.
select 'defs mit alter id'   as was, count(*) as anzahl
  from public.building_defs      where id = 'main_hall'
union all
select 'platzierte mit alter id', count(*)
  from public.placed_buildings   where building_type_id = 'main_hall';

-- Und die hier muss genau 1 zurückgeben: die Burg, wo sie immer stand.
select building_type_id, grid_x, grid_y, level, is_complete
  from public.placed_buildings
 where building_type_id = 'castle';
