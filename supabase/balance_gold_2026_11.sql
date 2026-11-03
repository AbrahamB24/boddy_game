-- Gold balance pass 2026-11-02 (user: "Gold bitte ausbalancieren, damit es
-- wirklich eine wichtige Ressource wird").
--
-- Houses produced 1 gold/h each. They are built by the dozen, so this was a
-- ~250 gold/day income for doing nothing, more than daily tasks, chests,
-- stars and bosses together. Cut to a quarter: 0.25/h per house.
--
-- The rest of the pass is code (survival pays full only for record floors,
-- craftable items no longer sell, daily tasks and chest reworked) and needs
-- no SQL.
--
-- Only the gold production line of the two house rows is touched; housing,
-- costs and every other effect stay as they are. Idempotent: running it
-- twice leaves 0.25.

update public.building_defs b
set effects = (
  select jsonb_agg(
    case
      when e->>'type' = 'production' and e->>'key' = 'gold'
        then jsonb_set(e, '{value}', '0.25'::jsonb)
      else e
    end
    order by ord
  )
  from jsonb_array_elements(b.effects) with ordinality as t(e, ord)
)
where b.id in ('small_house', 'large_house')
  and jsonb_array_length(b.effects) > 0;
