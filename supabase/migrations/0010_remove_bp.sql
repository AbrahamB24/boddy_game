-- Remove BP (user decision, 2026-07-16).
--
-- Research is no longer bought and no longer waited out: winning a tech's
-- overworld trial unlocks it on the spot. That deletes the currency AND the
-- research countdown, and with them:
--   • profiles.bp / profiles.level — `level` was only ever derived from bp
--     (bpToLevel) and was never displayed or gated on anywhere.
--   • settlements.active_research_id / research_seconds_built — nothing can
--     ever set them again.
--   • tech_gates — a cleared gate and an unlocked tech are now the same fact,
--     so research_unlocks IS the record.
--   • tech_defs.research_seconds — no tech takes time.
--
-- DELIBERATELY KEPT: tech_defs.bp_cost. The column now stores TechDef
-- .trialDifficulty — how hard a tech's trial is relative to its era's other
-- techs (techTrialLevel ranks on it). It stopped being a price and became what
-- it always effectively was; the column keeps its name so every tech row
-- already tuned in Dev Mode survives.
--
-- ⚠️ profiles is SHARED with the fitness app. If that app still reads bp/level,
-- run everything except the `profiles` block below and drop those two columns
-- only once it no longer does. Nothing in this game reads them either way.

-- ── settlements ─────────────────────────────────────────────
alter table public.settlements
  drop column if exists active_research_id,
  drop column if exists research_seconds_built;

-- ── tech_defs ───────────────────────────────────────────────
-- `if exists`: 0021 drops the whole table later, so a replay from 0001 reaches
-- this line with nothing to alter (fixed 2026-07-30).
alter table if exists public.tech_defs
  drop column if exists research_seconds;

-- ── tech_gates ──────────────────────────────────────────────
drop table if exists public.tech_gates;

-- ── profiles ────────────────────────────────────────────────
-- MOVED OUT OF THE AUTOMATIC PATH (2026-07-30). `public.profiles` is shared with
-- the fitness app, and this game cannot know whether that app still reads `bp`
-- and `level` — so a migration that runs unattended must not drop them. Nothing
-- in Bøddy Game reads either column, so leaving them costs this project nothing.
--
-- To clean them up once the fitness app is confirmed not to need them, run
-- supabase/manual/drop_shared_profile_columns.sql by hand.
