-- Status-remedy items (user 2026-09-15: "für alle Debuffs soll es ein
-- Gegenmittel geben"). Two new ItemKind values (cureStatus/cureDebuffs) need
-- no schema change — they reuse `magnitude` as their cure CHANCE — except
-- cureStatus's TARGET, which is new: which main status it cures, or NULL
-- for the universal Full Heal/Full Restore line.
--
-- Mirrors migration 0033's resource_id column exactly (same "NULL for every
-- other kind" shape).

alter table public.item_defs
  add column if not exists cure_main_status text;

comment on column public.item_defs.cure_main_status is
  'For kind = cureStatus: the MainStatusKind name this item cures '
  '(burn/frost/freeze/poison/fear/sleep/petrify/paralysis/soaked/dazzled/'
  'confusion). NULL cures ANY main status (the universal remedy). NULL for '
  'every other kind.';
