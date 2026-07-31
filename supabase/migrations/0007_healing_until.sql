-- Healing takes real time now (user 2026-07-16: "Heilen darf nicht sofort
-- sein, sondern muss abhängig von den zu heilenden HP dauern").
--
-- One nullable timestamp on the creature rather than a `healing_jobs` table:
-- being treated is a STATE of a creature, not an entity of its own, and it has
-- no payload beyond "until when". A creature is unavailable while it mends;
-- the heal resolves lazily on read, so one that finishes while the app is
-- closed is simply done next launch — same rule as expeditions and breeding.
--
-- NULL = not being healed, which is also what every existing row means. No
-- backfill needed.

alter table public.creatures
  add column if not exists healing_until timestamptz;
