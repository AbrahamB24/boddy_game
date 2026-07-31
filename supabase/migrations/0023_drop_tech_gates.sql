-- Drop the dead `tech_gates` table (user 2026-07-25). It backed the old
-- research-trial gates; research is gone (feature unlocks come from map progress
-- / authored path nodes now), and no code reads or writes it any more. The reset
-- flow no longer wipes it either. Idempotent.
drop table if exists public.tech_gates cascade;
