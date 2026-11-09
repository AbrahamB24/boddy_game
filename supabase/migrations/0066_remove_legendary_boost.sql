-- The general "legendary boost" workshop post is gone (user 2026-11-07):
-- legendaries now work like any other creature, through their own fixed work
-- stats. Strip the post out of every building's effect list.
update public.building_defs
   set effects = coalesce(
         (select jsonb_agg(e)
            from jsonb_array_elements(effects) as e
           where not (e->>'type' = 'workshop'
                  and e->>'resource' = 'legendary_boost')),
         '[]'::jsonb)
 where effects @> '[{"resource":"legendary_boost"}]'::jsonb;
