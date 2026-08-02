-- ── Gebäude pausieren (user 2026-08-01) ──────────────────────
-- "ich will gebäude pausieren können"
--
-- A refinery eats wood whether you want the planks today or not, and the only
-- way to stop it was to un-staff it — which loses the posting and the monsters'
-- place in it. Pausing is the switch that was missing: the building keeps its
-- workers and its level, and simply stops running.
--
-- What it stops: production and, with it, whatever that production consumes.
-- What it does NOT stop: housing and storage. Those are what a building IS, not
-- what it does; pausing a full storehouse to save nothing and spill everything
-- is not a switch anyone wants.
alter table public.placed_buildings
  add column if not exists is_paused boolean not null default false;

comment on column public.placed_buildings.is_paused is
  'Paused: the building produces and consumes nothing. Housing and storage '
  'still count. See SettlementController.setPaused.';
