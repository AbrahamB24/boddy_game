-- Hospital (id bleibt healing_hut): Name + Grundfläche 7x6 in der Live-DB nachziehen.
-- Im Supabase SQL-Editor ausführen. Idempotent. Bereits platzierte Hospitäler
-- behalten ihre Zellen nicht automatisch: das Bild ist 7x6 (Render 2026-11-09),
-- alte 5x4-Platzierungen müssen einmal neu gesetzt werden (Dev Mode).
update building_defs
   set name = 'Hospital', grid_w = 7, grid_h = 6
 where id = 'healing_hut';
