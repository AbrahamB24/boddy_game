-- The Healing Hut's QUEUE (user 2026-07-27: "treat all sollte nicht
-- funktionieren, da ich aktuell keine Warteschlange habe. Diese soll direkt
-- eingebaut werden").
--
-- The hut treats only `healSlots` monsters at a time. "Treat all" therefore
-- either refused outright when the slots were full, or silently treated the
-- three worst and left the rest hurt with nothing on screen saying so — the
-- overflow had nowhere to wait.
--
-- One nullable timestamp on the creature, exactly like `healing_until` (0007):
-- being IN LINE is a state of a creature, not an entity of its own. NULL = not
-- queued, which is also what every existing row means, so there is no backfill.
--
-- It carries the ORDER as well as the flag — a queue without an order is a set,
-- and the player's answer to "who goes next" is precisely the order they put
-- them in. CreaturesController pulls the OLDEST entry into a freeing slot.
alter table public.creatures
  add column if not exists heal_queued_at timestamptz;

comment on column public.creatures.heal_queued_at is
  'When this monster was put in line for the Healing Hut. NULL = not queued. '
  'Cleared the moment its treatment starts (healing_until is set instead).';

-- The controller asks for "this user''s queue, oldest first" on every resolve.
create index if not exists creatures_heal_queue_idx
  on public.creatures (user_id, heal_queued_at)
  where heal_queued_at is not null;
