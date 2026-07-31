-- Intro / jumpstart progress for new players.
-- See lib/features/onboarding/intro_flow.dart — the value is IntroStep.index,
-- 0 = pickStarter ... 5 = done.
--
-- The add/backfill/default dance below matters: `profiles` is shared with the
-- fitness app and already holds real players. Adding the column with default 5
-- backfills every EXISTING row as "intro already done" (they are — they have
-- been playing for months), and only then is the default lowered to 0 so that
-- rows inserted from here on start at step 0 and get the guided flow.
--
-- Wrapped in the existence check so re-running the migration can never reset a
-- genuinely-new player who is mid-intro back to done.

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'intro_step'
  ) then
    -- Backfills all existing rows to IntroStep.done.
    alter table public.profiles
      add column intro_step int not null default 5;

    -- ...but every new account starts at IntroStep.pickStarter.
    alter table public.profiles
      alter column intro_step set default 0;
  end if;
end $$;
