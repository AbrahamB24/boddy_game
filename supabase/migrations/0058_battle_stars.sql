-- Sterne pro Kampf (user 2026-09-28): der beste Stand je Kampf der Kampagne,
-- 1-3 Sterne, als Karte { "<Kampfnummer>": <Sterne> }. Wird nur hochgesetzt:
-- ein schlechterer Wiederholungskampf nimmt nie einen Stern weg.
-- Standard '{}' = "noch keine Sterne" -- richtig fuer alle bestehenden Zeilen.

alter table public.profiles
  add column if not exists battle_stars jsonb not null default '{}'::jsonb;

comment on column public.profiles.battle_stars is
  'Beste Sterne (1-3) je gewonnenem Kampfpfad-Kampf, { "<battle number>": stars }. '
  'Siehe SettlementController.recordBattleStars.';
