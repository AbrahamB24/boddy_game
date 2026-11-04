-- Fachwerk rebuild (2026-11-04): building plot, workshop (potter's) and
-- training grounds, remodelled in tool/blender/buildings/{building_plot,
-- thinker_circle,training_grounds}.py. Footprints stay (5 x 5, 3 x 3, 3 x 3).
-- image_url goes to null: the bundled picture always wins over an uploaded one.
update public.building_defs
   set image_url = null
 where id in ('building_plot', 'thinker_circle', 'training_grounds');
