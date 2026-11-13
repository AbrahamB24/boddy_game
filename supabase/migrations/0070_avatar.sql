-- Player avatar (user 2026-11-13: "Avatarcreator"): the look a player built in the
-- creator, as a small JSON object, e.g.
--   {"v":1,"hair":"short","eyes":"round","mouth":"smile","beard":"none",
--    "top":"tunic","bottom":"trousers","shoes":"boots","hat":"none","extra":"none",
--    "hairC":1,"eyesC":1,"skinC":2,"topC":0,"top2C":2,"bottomC":7,"shoesC":10,"hatC":4,"extraC":3}
-- Part ids and colour indices are defined by the app (lib/features/avatar/); the
-- app falls back to a default for anything it does not know, so no value in here
-- can break a picture.
--
-- Additive and NULLABLE like `username` (0046): `profiles` is shared with the
-- fitness app, whose rows never set it. NULL = "no avatar made yet" (the app shows
-- the letter avatar). It is read through the same "search profiles by username"
-- policy that already exposes `username` (0051), written through the owner policy.

alter table public.profiles add column if not exists avatar jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_avatar_shape'
  ) then
    alter table public.profiles
      add constraint profiles_avatar_shape
      check (avatar is null
             or (jsonb_typeof(avatar) = 'object' and pg_column_size(avatar) < 1024));
  end if;
end $$;

comment on column public.profiles.avatar is
  'Avatar look (BøddyGame): part ids + colour indices, see lib/features/avatar. NULL = none made yet.';
