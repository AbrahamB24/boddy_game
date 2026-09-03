-- Attack becomes a REAL ability (user 2026-09-03: "attack soll eine normale
-- Fähigkeit sein. Falls es noch andere gibt, bitte auch diese als echte
-- Fähigkeit aufnehmen"). It used to be entirely hardcoded inside
-- CombatEngine.basicAttack — the one hardcoded special-cased move; nothing
-- else in the combat system worked that way. Now it's a real row here, dev-
-- editable exactly like any other ability, and Combatant._resolveAbilities
-- (lib/features/creatures/models/combatant.dart) puts it on EVERY combatant
-- automatically, ahead of its species' own moves.
--
-- power 40 / apCost 0 (auto-derive) is the exact anchor the whole ability
-- cost scale is calibrated against (AbilityDef._derivedApCost) — it prices
-- out to kBasicAttackApCost by construction, so this row tracks that live
-- dial rather than freezing today's number into an explicit ap_cost.
--
-- Combatant.dart also carries a Dart-side fallback with these same numbers
-- for the gap before this row (or this migration) has loaded — "an attack
-- is always available" cannot depend on network state.
insert into public.ability_defs (id, name, description, element, kind, target, power, priority, ap_cost)
values (
  'attack',
  'Attack',
  'A basic, typeless hit every monster can throw — no species has to learn it.',
  'neutral',
  'damage',
  'enemy',
  40,
  0,
  0
)
on conflict (id) do nothing;
