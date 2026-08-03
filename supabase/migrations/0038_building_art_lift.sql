-- Rename the third art number: it measures a LIFT above the image's bottom
-- edge, in fractions of the image WIDTH — not a fraction of its height.
--
-- Why width: the sprite is drawn width-first (natural height, overflowing
-- upward), so its height is unknown until the picture has loaded. Measuring in
-- heights would need a number the code cannot have when it places the image.
--
-- 0037 shipped the old name; this corrects it in place rather than leaving two
-- columns where one is a lie.
alter table public.building_defs
  rename column art_anchor_y to art_lift;

alter table public.building_defs
  alter column art_lift set default 0.0;

update public.building_defs set art_lift = 0.0 where art_lift = 1.0;
