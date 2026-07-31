-- Per-building level (user design 2026-07-17): every placed building carries
-- a level; higher level costs more and takes longer to build but yields more.
--
-- PlacedBuilding.fromMap already reads a `level` column and the code defaults
-- new buildings to 1, so this only GUARANTEES the column exists (the base
-- placed_buildings table was created outside the tracked migrations). Idempotent
-- and safe to run whatever state the table is in.

alter table public.placed_buildings
  add column if not exists level integer not null default 1;
