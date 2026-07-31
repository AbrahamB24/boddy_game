-- ⚠️ RUN BY HAND, AND ONLY ONCE YOU HAVE CHECKED THE FITNESS APP.
--
-- `public.profiles` is SHARED: the same Supabase project holds this game's tables
-- and BøddyQuest's (workouts, exercises, saved_workouts …). These two columns are
-- leftovers of the game's deleted BP/level system — nothing in Bøddy Game reads
-- them — but if the fitness app still writes or selects them, dropping them
-- breaks that app, and the data does not come back.
--
-- This block used to sit inside migration 0010, i.e. in the path that runs
-- unattended. It was moved out on 2026-07-30 for exactly that reason.
--
-- Check first (in the fitness app's source):  grep -rn "\bbp\b\|'level'" lib/
-- Then, if it is clean:

alter table public.profiles
  drop column if exists bp,
  drop column if exists level;
