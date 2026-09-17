-- Ability variety (user 2026-09-08):
--   1) 4 example multi-hit/cleave moves — 2 cleave (spreads onto a
--      different living enemy each extra hit), 2 multi-hit (repeats on the
--      same target) — proving out the new extra_hit_chance/
--      extra_hit_same_target columns (see migration 0043). Any species of
--      that element can already train these at the Combat School the
--      moment it reaches the unlock stage — learnableAbilitiesFor() reads
--      every ability_defs row of its own element, not a per-species list.
--   2) Debuffs added to 8 existing "strong tier" moves, one per element —
--      inflict_debuff was a fully working engine mechanic that NO ability
--      in the game used before this (docs/balancing.md flagged it
--      unused). inflict_debuff_turns/inflict_debuff_value are left at 0 so
--      they inherit the raised Dial defaults (Dials.debuff*Pct/
--      debuffDurationTurns) rather than freezing in the old numbers.
--
-- Run once against Supabase. Idempotent inserts (on conflict do nothing);
-- the debuff updates are plain `update` and safe to re-run.

-- ── 1) Multi-hit / cleave example moves ────────────────────────────
insert into public.ability_defs
  (id, name, description, element, kind, target, power, ap_cost,
   unlock_stage, extra_hit_chance, extra_hit_same_target)
values
  ('flammenpeitsche', 'Flame Lash',
   'Fire attack that may lash out at another enemy too.',
   'fire', 'damage', 'enemy', 55, 0, 1, 0.5, false),
  ('felssturm', 'Rockslide',
   'Stone attack that may crash into another enemy too.',
   'stone', 'damage', 'enemy', 55, 0, 1, 0.5, false),
  ('blitzserie', 'Lightning Barrage',
   'Lightning attack that may strike the same target again.',
   'lightning', 'damage', 'enemy', 35, 0, 1, 0.55, true),
  ('krallenserie', 'Claw Flurry',
   'Shadow attack that may rake the same target again.',
   'shadow', 'damage', 'enemy', 35, 0, 1, 0.55, true)
on conflict (id) do nothing;

-- ── 2) Debuffs on existing moves, one per element ──────────────────
update public.ability_defs set inflict_debuff = 'attackDown', inflict_debuff_chance = 0.30 where id = 'glutwelle';      -- fire: scorched, hits softer
update public.ability_defs set inflict_debuff = 'defenseDown', inflict_debuff_chance = 0.30 where id = 'tsunami';       -- water: current sweeps footing away
update public.ability_defs set inflict_debuff = 'speedDown', inflict_debuff_chance = 0.30 where id = 'blattsturm';      -- plant: tangled in leaves
update public.ability_defs set inflict_debuff = 'blind', inflict_debuff_chance = 0.25 where id = 'sonnenzorn';         -- light: glare
update public.ability_defs set inflict_debuff = 'blind', inflict_debuff_chance = 0.25 where id = 'finsternis';         -- shadow: darkness
update public.ability_defs set inflict_debuff = 'speedDown', inflict_debuff_chance = 0.30 where id = 'gletschersturm'; -- ice: numbing cold
update public.ability_defs set inflict_debuff = 'attackDown', inflict_debuff_chance = 0.30 where id = 'gewittersturm'; -- lightning: stunned muscles
update public.ability_defs set inflict_debuff = 'defenseDown', inflict_debuff_chance = 0.30 where id = 'erdstoss';      -- stone: armor cracked
