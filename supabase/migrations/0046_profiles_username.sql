-- Social feature (user 2026-09-15: "bitte eine social tab hinzufügen").
-- Freunde-Suche braucht einen öffentlich suchbaren Namen — `profiles` hat
-- bisher keinen. Additiv und NULLABLE, denn `profiles` ist mit der Fitness-
-- App (BoddyQuest) geteilt: bestehende Zeilen dort setzen nie ein Username,
-- der partielle Unique-Index ignoriert NULL also folgenlos für sie.
--
-- Kein Default/Backfill nötig (anders als intro_step/battles_cleared) — ein
-- fehlender Username bedeutet einfach "noch nicht gesetzt", nicht "falscher
-- Wert für Bestandsspieler".

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'username'
  ) then
    alter table public.profiles
      add column username text;
  end if;
end $$;

create unique index if not exists profiles_username_key
  on public.profiles (lower(username))
  where username is not null;

comment on column public.profiles.username is
  'Öffentlicher, eindeutiger Anzeigename für die Freundessuche (BøddyGame). '
  'NULL = noch nicht gesetzt (u.a. jede bestehende BoddyQuest-Zeile).';
