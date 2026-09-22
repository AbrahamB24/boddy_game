-- ── Umbaumodus: Gebäude zurücknehmen (user 2026-09-22) ───────────────
-- "der Umbaumodus soll so sein wie bei FoE. D.h ich kann alle Gebäude
-- 'zurücknehmen' und dann einzeln frei platzieren."
--
-- A stored building keeps its row — id, level, workers, construction
-- progress — it just isn't standing on the grid right now. gridX/gridY go
-- stale the moment this flips true and are only meaningful again once the
-- building is placed (which clears it, see moveBuilding). Its effects pause
-- exactly the way an unconnected building's already do: GameEngine.
-- connectedBuildingIds skips a stored building the same way it skips an
-- incomplete one, so housing/production need no separate suppression here.
alter table public.placed_buildings
  add column if not exists is_stored boolean not null default false;

comment on column public.placed_buildings.is_stored is
  'In the Umbaumodus tray: recalled from the map, not yet given a new spot. '
  'grid_x/grid_y are stale while this is true. See '
  'SettlementController.recallAllBuildings/moveBuilding.';
