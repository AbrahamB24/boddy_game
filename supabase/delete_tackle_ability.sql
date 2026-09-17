-- ═══════════════════════════════════════════════════════════════════════════
-- Delete Tackle / rempler (user 2026-09-07)
--
-- "wo ist der unterschied zwischen tackle und attack?" -- none: same element
-- (neutral), same kind (damage), same power (40), same ap_cost (3), no
-- effects. `attack` is the free basic hit every creature already knows for
-- free (hardcoded fallback in combatant.dart); `rempler` (Tackle) was just a
-- learnable duplicate of it in the ability catalog. "lösche tackle" -> remove
-- it outright rather than keep a pointless second entry.
--
-- Checked species_export.json (the 15 species this session has data for):
-- none list 'rempler' as a learnable ability, so nothing needs re-pointing
-- there. The three per-CREATURE fields that could still reference it
-- (learned_ability_ids / equipped_ability_ids / training_ability_id, added in
-- migration 0041) are cleaned up below too, even though the app already
-- degrades gracefully if they aren't (equipped resolution silently drops
-- unknown ids; a stale training_ability_id just falls back to showing the
-- raw id string) -- this is just tidiness, not a required safety step.
--
-- Run once in the Supabase SQL editor. Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- Drop it from anyone who already trained/equipped/was mid-training on it.
update public.creatures
set learned_ability_ids = coalesce(learned_ability_ids, '[]'::jsonb) - 'rempler'
where learned_ability_ids @> '["rempler"]'::jsonb;

update public.creatures
set equipped_ability_ids = coalesce(equipped_ability_ids, '[]'::jsonb) - 'rempler'
where equipped_ability_ids @> '["rempler"]'::jsonb;

update public.creatures
set training_ability_id = null, training_until = null, train_queued_at = null
where training_ability_id = 'rempler';

delete from public.ability_defs where id = 'rempler';

commit;

-- Control: should return zero rows.
select id, name from public.ability_defs where id = 'rempler';
