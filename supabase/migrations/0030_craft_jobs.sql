-- The Workshop's BENCHES and its QUEUE (user 2026-07-30: "workshop effekt
-- hinzufügen, wieviele items gleichzeitig produziert werden können und eine
-- warteschlange hinzufügen. Beides will ich pro Level einstellen können").
--
-- Crafting held exactly one recipe — `active_craft_id` plus the seconds accrued
-- toward it — and repeated it forever. There was nothing to put a second item
-- into and nowhere for a third to wait, so neither of the two new building
-- effects (craftSlots / craftQueue) would have had anything to govern.
--
-- ONE jsonb column, not a table. A craft job has no identity worth keeping: it
-- is an item id and the seconds banked toward it, it lives for minutes, and it
-- is only ever read together with the rest of the settlement. `items` (0011)
-- and `goods` (0006) already work exactly this way, and both avoided a join on
-- the hottest read in the game.
--
--   [{"item": "torch", "seconds": 12.5}, {"item": "torch", "seconds": 0}]
--
-- ORDER IS THE QUEUE. The first `craftSlots` entries are on a bench and
-- accruing; the rest are waiting, in the order the player added them. That is
-- the same rule the Healing Hut's line follows.
--
-- No backfill: SettlementModel folds a legacy `active_craft_id` into the first
-- job on read, so a settlement mid-craft keeps its progress and the column is
-- simply empty until the next save.
alter table public.settlements
  add column if not exists craft_jobs jsonb not null default '[]'::jsonb;

comment on column public.settlements.craft_jobs is
  'Ordered craft jobs: [{"item": <item_def id>, "seconds": <accrued>}]. The '
  'first craftSlots entries are being made; the rest are queued, in order. '
  'Replaces the single active_craft_id/craft_seconds_built pair, which is kept '
  'for older clients and read as a one-job list.';
