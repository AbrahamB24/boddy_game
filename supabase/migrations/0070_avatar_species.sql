-- Player picture (user 2026-11-13): a portrait of a monster from the player's
-- bestiary, stored as "<species id>:<stage>", e.g. 'blazeling:1'. The app falls
-- back to the letter avatar for anything it does not know, so no value in here
-- can break a screen.
--
-- Additive and NULLABLE like `username` (0046): `profiles` is shared with the
-- fitness app, whose rows never set it. It is READ through the same "search
-- profiles by username" policy that already exposes `username` (0051) and WRITTEN
-- through the owner policy.

alter table public.profiles add column if not exists avatar_species text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_avatar_species_shape'
  ) then
    alter table public.profiles
      add constraint profiles_avatar_species_shape
      check (avatar_species is null or char_length(avatar_species) between 3 and 60);
  end if;
end $$;

comment on column public.profiles.avatar_species is
  'Portrait for the player (BøddyGame): "<species id>:<stage 0-2>". NULL = letter avatar.';

-- Only matters if the first avatar idea (a character creator, column `avatar`) was
-- ever applied: it was dropped again and the column is unused.
alter table public.profiles drop constraint if exists profiles_avatar_shape;
alter table public.profiles drop column if exists avatar;
