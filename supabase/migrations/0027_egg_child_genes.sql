-- ── The egg carries its own child (user 2026-07-26) ────────────────────────
-- "Bitte ei als Item bezeichnen und somit in den Bag senden können."
--
-- An egg is an ITEM the player holds, so it has to be a thing in its own right
-- — and it was not: hatching rolled the child from the two PARENTS' current
-- genes, read live at hatch time. That made an egg a promise about two other
-- creatures rather than an object, and it had a real bug in it: release a
-- parent before the egg hatched and the child silently fell back to a fresh
-- roll off the species curve instead of inheriting anything.
--
-- The genes are frozen when the egg is LAID (breeding → egg) and stored here.
-- Hatching reads them and needs no parent at all.
--
-- Both columns are jsonb maps of stat name → value, the same shape
-- `creatures.stat_base` / `stat_slope` use, so CreatureInstance's own readers
-- parse them unchanged.
--
-- NULL means "laid before this migration": those rows keep the old
-- read-the-parents behaviour, so nothing in flight is lost.
alter table breeding_jobs
  add column if not exists child_base  jsonb,
  add column if not exists child_slope jsonb;

comment on column breeding_jobs.child_base is
  'Child genes frozen when the egg was laid (stat name -> base). NULL = a '
  'pre-0027 row, hatched from the parents instead.';
comment on column breeding_jobs.child_slope is
  'Child per-level growth frozen when the egg was laid (stat name -> slope).';
