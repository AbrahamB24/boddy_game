-- Social feature (user 2026-09-19): abgelaufene PvP-Lobbys und unbeantwortete
-- Herausforderungen selbst aufräumen lassen.
--
-- pvp_expire_stale() (0053, erweitert in 0054) lief bisher nur "faul" — wenn
-- irgendein Client eine Liste öffnete. Der Client ruft es jetzt zusätzlich alle
-- paar Minuten auf, solange die App offen ist; dieser Job ist die
-- Sicherheitsleine für den Fall, dass NIEMAND die App offen hat, und hält die
-- Tabelle auch dann sauber.
--
-- Braucht die Erweiterung pg_cron (Supabase: Dashboard -> Database ->
-- Extensions -> pg_cron einschalten). Ist sie nicht aktiv, tut diese Migration
-- nichts und meldet es nur — alles andere funktioniert ohne sie.

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Idempotent: einen früheren Eintrag gleichen Namens zuerst entfernen.
    perform cron.unschedule(jobid)
      from cron.job
      where jobname = 'pvp_expire_stale';
    perform cron.schedule(
      'pvp_expire_stale',
      '*/5 * * * *',
      $job$select public.pvp_expire_stale();$job$
    );
  else
    raise notice 'pg_cron ist nicht aktiviert: der PvP-Sweep laeuft nur im Client (alle ~3 Minuten bei offener App).';
  end if;
end $$;
