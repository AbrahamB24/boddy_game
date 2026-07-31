-- ── Ein generiertes Gebäude wirklich löschen (user 2026-07-31) ──
-- "ich kann von dir erstellte gebäude wie z.b primitive wood camp nicht
--  löschen, das möchte ich aber können"
--
-- The roster is BUNDLED CODE plus DB overrides (GameDefsController._merge), so
-- deleting a row only removed the override — the generated def came straight
-- back on the next load. There was no way to say "this one is gone" because
-- absence is how the base state is expressed.
--
-- A TOMBSTONE says it: a row that exists for the sole purpose of subtracting.
-- The merge drops any id whose row is retired, so a bundled def can finally be
-- removed, and un-retiring it (clear the flag) brings it back — which is why
-- this is a flag rather than a delete. A dev action that cannot be undone is a
-- dev action nobody dares use.
alter table public.building_defs
  add column if not exists retired boolean not null default false;

comment on column public.building_defs.retired is
  'Tombstone: true removes this def from the game even if the app bundles a '
  'fallback for it. See GameDefsController._merge.';
