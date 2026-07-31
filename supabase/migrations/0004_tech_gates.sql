-- Region-progression redesign: techs are locked behind a mini-dungeon on the
-- map. This table records which tech GATES a settlement has cleared (a tech
-- becomes researchable only after its gate is cleared; research itself still
-- costs BP + time and lives in research_unlocks). Mirrors research_unlocks.
-- Idempotent.

create table if not exists public.tech_gates (
  settlement_id uuid not null references public.settlements (id) on delete cascade,
  tech_id       text not null,
  cleared_at    timestamptz not null default now(),
  primary key (settlement_id, tech_id)
);

alter table public.tech_gates enable row level security;

-- Owner access via the settlement's owner (same shape research_unlocks uses).
drop policy if exists "own tech gates" on public.tech_gates;
create policy "own tech gates" on public.tech_gates
  for all
  using (exists (select 1 from public.settlements s
                 where s.id = tech_gates.settlement_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.settlements s
                      where s.id = tech_gates.settlement_id and s.user_id = auth.uid()));
