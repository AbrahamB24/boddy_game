-- Two more Pokémon-flavoured effects an ability can carry (user 2026-07-30:
-- "Gerne darfst du noch weitere Effekte hinzufügen, welche an Pokemon angelehnt
-- sind, aber die aktuellen Monster noch gar nicht verwenden").
--
--   REGENERATION — heals the user a share of its max HP at the end of each of
--                  its own turns, for a while (Wish / Leech). The mirror image
--                  of a damage-over-time, and it ticks in the same upkeep.
--   RECOIL       — the user takes a share of the damage it just dealt
--                  (Double-Edge). Not timed; it happens with the hit, and it
--                  CAN knock the user out, which is what makes it a real cost.
--
-- Everything else added the same day needed no columns: SLEEP is a new value of
-- the existing `inflict_main`, and WEAKEN / EXPOSE (attack-down, defense-down)
-- are new values of `inflict_debuff`.
--
-- 0 = the move does not have it. No backfill, no behaviour change for any
-- existing ability.

alter table public.ability_defs
  add column if not exists regen_value double precision not null default 0,
  add column if not exists regen_turns integer not null default 0,
  add column if not exists recoil_value double precision not null default 0;
