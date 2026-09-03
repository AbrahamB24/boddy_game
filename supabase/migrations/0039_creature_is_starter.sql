-- The starter is a permanent companion, never releasable (user 2026-09-02:
-- "Das Startmonster kann aber niemals entlassen werden. D.h beim
-- Startermonster gibt es den Releasebutton nicht"). CreatureDetailScreen
-- hides its Release button when this is true; CreaturesController.
-- adoptStarter is the only writer, setting it once at creation and never
-- touching it again — an evolved or renamed starter is still this same row.
--
-- Existing rows default to false, which is correct for all of them: nobody
-- who already has creatures gets one retroactively marked as the starter
-- (there is no reliable way to tell which pre-migration row that was, and a
-- player who already released their real starter under the old rules should
-- not have a different creature locked down in its place).
alter table public.creatures
  add column if not exists is_starter boolean not null default false;

comment on column public.creatures.is_starter is
  'True for the one creature created via CreaturesController.adoptStarter. '
  'Never releasable — see CreatureDetailScreen''s Release button.';
