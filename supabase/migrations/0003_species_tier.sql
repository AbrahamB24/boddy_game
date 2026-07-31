-- Region-progression redesign: species belong to a REGION TIER (1 = first
-- region). Tier scales the stat-budget target (+20%/tier) so later regions'
-- monsters are deliberately stronger — the soft gate that makes each region's
-- boss need that region's catches. Idempotent.

alter table public.species_defs
  add column if not exists tier integer not null default 1;
