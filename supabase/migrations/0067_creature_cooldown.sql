-- Legendaries rest after every battle (user 2026-11-07); the length shrinks
-- with their building level. Null for everything else.
alter table public.creatures
  add column if not exists cooldown_until timestamptz;
