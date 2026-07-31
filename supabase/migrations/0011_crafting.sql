-- Crafting: the Workshop makes items (potions) from era goods.
--
-- This is what the repurposed crafting stat does. The stat was `research`
-- until BP and the research countdown were deleted (0010); the Thinker Circle
-- became the Workshop rather than leaving a purposeless building standing.
--
-- Note the symmetry with what 0010 removed: research used to be the thing that
-- took time and cost a currency, and it now takes neither. Crafting takes both.
-- The columns below are deliberately the same shape the research ones had —
-- an active job plus accrued work-seconds — because it is the same mechanic,
-- just attached to something worth waiting for.

alter table public.settlements
  -- The recipe the Workshop is making, or null when it's idle.
  add column if not exists active_craft_id text,
  -- Crafting-seconds accrued toward it. Reset to 0 when an item lands; the
  -- recipe stays selected and immediately starts the next one, so a workshop
  -- left alone keeps producing.
  add column if not exists craft_seconds_built double precision not null default 0;

-- The player's bag: {"minor_potion": 3, …}. jsonb rather than a table because
-- items are a plain count per id with no per-instance state — the same reason
-- `resources` is columns and not rows. Counts are never stored at 0 (the
-- client drops the key), so a key present means a usable item.
alter table public.settlements
  add column if not exists items jsonb not null default '{}'::jsonb;
