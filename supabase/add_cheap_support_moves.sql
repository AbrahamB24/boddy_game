-- Cheaper Attack + real 1-AP support moves (user 2026-09-08: "ich möchte,
-- dass attack so balanciert wird, dass es nur 2 AP kostet. Zudem sollen die
-- Buffs und Debuffs weniger AP kosten, damit es einige mit nur 1 AP gibt,
-- damit man diese auch benutzt").
--
-- Attack: pinned to 2 AP directly (was 3, auto-derived from power ÷
-- powerPerAp — see combat_engine.dart/combatant.dart, now both set an
-- EXPLICIT ap_cost so this row and the app's own fallback can never drift
-- apart again).
--
-- 5 new NEUTRAL moves (same convention as the existing kampfrausch/
-- zeitdruck/panzerung: universal, not tied to one element) — deliberately
-- WEAK (a single turn / low chance / small magnitude) so they auto-price to
-- exactly 1 AP under the unchanged power÷13 formula, sitting ALONGSIDE the
-- existing, stronger, pricier buffs rather than replacing them. Nothing
-- about kampfrausch/zeitdruck/panzerung/glutwelle/etc. changes — this adds
-- a cheap option, it does not touch the existing ones.
--
-- Also lowers 2 Dials (buffApCost, minAbilityApCost) 2→1 so these moves'
-- auto-derived price can actually REACH 1 instead of being floored at 2 —
-- see dials.dart. That is a code change (this file is the content half).

update public.ability_defs set ap_cost = 2 where id = 'attack';

insert into public.ability_defs
  (id, name, description, element, kind, target,
   self_buff, self_buff_value, self_buff_turns)
values
  ('spurt', 'Quick Sprint',
   'A brief burst of speed — small, but nearly free.',
   'neutral', 'buff', 'self', 'haste', 0.20, 1),
  ('deckung', 'Quick Guard',
   'A quick defensive crouch — small, but nearly free.',
   'neutral', 'buff', 'self', 'armor', 0.20, 1),
  ('anheizen', 'Quick Fire-Up',
   'A quick surge of aggression — small, but nearly free.',
   'neutral', 'buff', 'self', 'rage', 0.20, 1)
on conflict (id) do nothing;

insert into public.ability_defs
  (id, name, description, element, kind, target, power,
   inflict_debuff, inflict_debuff_chance, inflict_debuff_turns, inflict_debuff_value)
values
  ('einschuechterung', 'Intimidate',
   'No real hit — just a glare that may weaken the target''s attack.',
   'neutral', 'damage', 'enemy', 0,
   'attackDown', 0.6, 2, 0.20),
  ('stolperfalle', 'Trip',
   'No real hit — just a snag that may slow the target down.',
   'neutral', 'damage', 'enemy', 0,
   'speedDown', 0.6, 2, 0.20)
on conflict (id) do nothing;
