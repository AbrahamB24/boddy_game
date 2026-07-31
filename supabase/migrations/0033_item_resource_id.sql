-- Which resource a PACKAGE item contains (user 2026-07-30: "ich brauche noch
-- Ressourcenpakete für die Belohnung … Die Pakete kommen ins Inventar und können
-- dann eingelöst werden").
--
-- A resource package is an ordinary item with a new kind (`resourcePack`), and
-- the only thing it needs beyond `magnitude` (how much) is WHICH resource. The
-- bundled packages are code-side content — their sizes are a balancing decision
-- (item_definitions.dart) and a campaign reward must not depend on somebody
-- having seeded a table — so nothing here needs a backfill. The column exists so
-- a package authored or retuned in Dev Mode round-trips like any other item.
--
-- NULL = not a package (every existing row).

alter table public.item_defs
  add column if not exists resource_id text;

comment on column public.item_defs.resource_id is
  'For kind = resourcePack: the ResourceModel key the package opens into '
  '(wood/stone/gold or a good id). NULL for every other kind.';
