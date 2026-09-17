-- ═══════════════════════════════════════════════════════════════════════════
-- Ability power/ap_cost rebalance (user 2026-09-07)
--
-- "Passe die AP kosten an, damit die Power und AP uebereinstimmen. Dort wo
--  die AP Kosten ueber 8 steigen wuerden, bitte die Power/Effekte anpassen."
--
-- Every ability's ap_cost below is the honestly-derived cost for its power +
-- effects (damage power, heal/lifesteal/status/debuff/self-buff/self-penalty
-- effect power, priority), using the same formula the app already applies to
-- auto-derived (ap_cost = 0) abilities -- reimplemented here so EVERY ability
-- gets an explicit, correct cost instead of only the ones that were unset.
--
-- 15 abilities would have landed above the 8-AP ceiling on their old power
-- alone; those had their `power` column reduced (effects/status values
-- untouched) so the honest cost lands exactly at 8. All other abilities keep
-- their old power and simply get their ap_cost corrected to match it.
--
-- Companion change (already applied in code, not here): AP capacity by stage
-- stays 4/6/8; AP regen by stage is now 2/3/4 (was 3/4/5).
--
-- Run once in the Supabase SQL editor. Idempotent (plain assignment, not a
-- delta). Review against abilities.xlsx before running.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

update public.ability_defs set power = 95,  ap_cost = 8 where id = 'inferno';         -- Inferno (power 359 -> 95)
update public.ability_defs set power = 10,  ap_cost = 2 where id = 'kampfrausch';     -- Battle Rage
update public.ability_defs set power = 85,  ap_cost = 8 where id = 'wurzelgriff';     -- Root Grip (power 144 -> 85)
update public.ability_defs set power = 115, ap_cost = 8 where id = 'gaia_zorn';       -- Gaia's Wrath (power 199 -> 115)
update public.ability_defs set power = 100, ap_cost = 8 where id = 'spritzer';        -- Splash (power 108 -> 100)
update public.ability_defs set power = 100, ap_cost = 8 where id = 'sonnenzorn';      -- Sun's Wrath (power 221 -> 100)
update public.ability_defs set power = 85,  ap_cost = 7 where id = 'schattenkralle';  -- Shadow Claw
update public.ability_defs set power = 0,   ap_cost = 5 where id = 'regeneration';    -- Regeneration
update public.ability_defs set power = 10,  ap_cost = 2 where id = 'zeitdruck';       -- Haste
update public.ability_defs set power = 95,  ap_cost = 8 where id = 'dunkelpuls';      -- Dark Pulse (power 266 -> 95)
update public.ability_defs set power = 100, ap_cost = 8 where id = 'nachtschwinge';   -- Night Wing (power 108 -> 100)
update public.ability_defs set power = 100, ap_cost = 8 where id = 'finsternis';      -- Darkness (power 221 -> 100)
update public.ability_defs set power = 77,  ap_cost = 6 where id = 'fokus_schlag';    -- Focus Strike
update public.ability_defs set power = 80,  ap_cost = 8 where id = 'tsunami';         -- Tsunami (power 373 -> 80)
update public.ability_defs set power = 100, ap_cost = 8 where id = 'blattsturm';      -- Leaf Storm (power 150 -> 100)
update public.ability_defs set power = 80,  ap_cost = 8 where id = 'aderlass';        -- Bloodletting (power 114 -> 80)
update public.ability_defs set power = 76,  ap_cost = 6 where id = 'biss';            -- Bite
update public.ability_defs set power = 37,  ap_cost = 2 where id = 'panzerung';       -- Armor Up
update public.ability_defs set power = 22,  ap_cost = 2 where id = 'funke';           -- Spark
update public.ability_defs set power = 51,  ap_cost = 4 where id = 'flammenstoss';    -- Flame Burst
update public.ability_defs set power = 40,  ap_cost = 3 where id = 'attack';          -- Attack
update public.ability_defs set power = 85,  ap_cost = 8 where id = 'aquastrahl';      -- Aqua Beam (power 182 -> 85)
update public.ability_defs set power = 95,  ap_cost = 8 where id = 'glutwelle';       -- Ember Wave (power 266 -> 95)
update public.ability_defs set power = 100, ap_cost = 8 where id = 'rankenhieb';      -- Vine Strike (power 109 -> 100)
update public.ability_defs set power = 77,  ap_cost = 6 where id = 'flutwelle';       -- Tidal Wave
update public.ability_defs set power = 51,  ap_cost = 4 where id = 'lichtblitz';      -- Light Flash
update public.ability_defs set power = 89,  ap_cost = 7 where id = 'kraftakt';        -- Power Surge
update public.ability_defs set power = 61,  ap_cost = 5 where id = 'strahlenstoss';   -- Ray Burst
update public.ability_defs set power = 100, ap_cost = 8 where id = 'prisma_strahl';   -- Prism Beam (power 266 -> 100)

commit;

-- Control: sorted by ap_cost, so the new curve is easy to eyeball end to end.
select ap_cost, power, id, name from public.ability_defs order by ap_cost, power desc;
