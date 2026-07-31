-- Drop the tech system (user 2026-07-25). Techs and the Dev-Mode Tech tab were
-- removed; the feature unlocks they used to gate (evolution / breeding / longer
-- hunts / more expedition slots) are earned by map progress now
-- (progression_unlocks.dart) and will become authored path-node rewards.
--
-- Safe/idempotent: `if exists` so re-running never errors. The legacy
-- `research_unlocks` table is intentionally KEPT — SettlementController still
-- reads it on load so a veteran's already-unlocked features survive; nothing
-- writes it any more.
drop table if exists public.tech_defs cascade;
