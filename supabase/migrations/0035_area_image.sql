-- ── Ein Kampfplatz statt einer Typ-Kachel (user 2026-07-31) ──
-- "Jetzt kann der Hintergrund nicht mehr der Typ sein, da es mehrere haben
--  kann. Welche Lösung gibt es?" → die Szene sagt WO du kämpfst.
--
-- The battle screen used to tile each half with the lead monster's ELEMENT. A
-- rank of three can hold three elements, so the tile was picking one of them and
-- calling it the world. The background now belongs to the REGION, and the type
-- moved to a plate under each monster where it can be true for all three.
alter table public.area_defs
  add column if not exists image_url text;

comment on column public.area_defs.image_url is
  'Battlefield scene for fights in this area. Null = the era gradient fallback.';
