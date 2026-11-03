-- Turning buildings (user 2026-11-03: "Gebäude um 90° drehen").
--
-- Quarter turns clockwise, 0..3. An odd turn swaps the footprint's width and
-- depth (BuildingDef.rotated); the picture is the model rendered from that
-- side (assets/images/buildings/<id>_r1..3.webp).
--
-- The app writes this column on its own, guarded
-- (SettlementService.setBuildingRotation): until this has run, buildings
-- still place and move — they just cannot remember a turn.
alter table public.placed_buildings
  add column if not exists rotation smallint not null default 0
    check (rotation between 0 and 3);
