-- ── Wo die Grundfläche im Bild sitzt (user 2026-08-01) ───────
-- "Ich habe das Bild jetzt als Quadrat, aber die Grundfläche ist natürlich
--  kleiner und weiter vorne … So ist das Gebäude zu weit hinten"
--
-- The map assumed a sprite's ground base filled the image's width and touched
-- its bottom edge. Generated art never does: it comes back square with the
-- building somewhere inside it. Matching the IMAGE to the tiles then puts the
-- BUILDING wherever the generator happened to leave it.
--
-- These three describe the picture, not the building, and are tuned in Dev Mode
-- next to the upload. The defaults are the old assumption exactly, so every
-- existing row keeps behaving as it did.
alter table public.building_defs
  add column if not exists art_base_width double precision not null default 1.0,
  add column if not exists art_anchor_x   double precision not null default 0.5,
  add column if not exists art_lift       double precision not null default 0.0;

comment on column public.building_defs.art_base_width is
  'How much of the image width the ground base spans (0..1). See artRect.';
