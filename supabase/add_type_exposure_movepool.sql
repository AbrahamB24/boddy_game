-- Type-exposure status effects + a full move pool for them (user 2026-09-15):
-- "für alle Typen einen Angriffseffekt... das getroffene Monster hat nun die
-- Schwächen des eigenen Typs und die Schwächen des [Angreifer-]Typs", plus a
-- broad ask to raise attack variety (multi-hit, sleep, deevolution, confusion,
-- petrify, poison, freeze, …) balanced across the WHOLE AP range, not just at
-- the top.
--
-- The engine side (new MainStatusKind values freeze/petrify/paralysis/soaked/
-- dazzled/confusion, the Regression secondary debuff, the exposure mechanic
-- and its escalating early-cure chance) is code — see status_effects.dart,
-- ability_effects.dart, combatant.dart and combat_engine.dart. This file is
-- the CONTENT half: it's the only thing that makes those mechanics reachable
-- in play.
--
-- It also plugs a real gap the existing roster had: Ice, Lightning and Stone
-- had ZERO trainable moves before this (only the universal neutral ones and
-- Attack) — every type now has a genuine stage 0→1→2 curve.
--
-- Every row leans on the SAME power÷13 auto-pricing every existing move
-- uses (ap_cost left unset) — see AbilityDef._derivedApCost. Explicit chances
-- and low/no power on the cheap ones are what actually lands them at 1-3 AP;
-- nothing here hardcodes an AP number. inflict_main_turns/inflict_main_value
-- are left at 0 throughout so every move inherits status_effects.dart's own
-- catalog numbers rather than freezing a duplicate copy of them here.
--
-- REQUIRES migrations 0041 (unlock_stage) and 0043 (extra_hit_chance/
-- extra_hit_same_target) to already be applied — run those first if they
-- haven't been.
--
-- Run once against Supabase. Idempotent (on conflict do nothing).

insert into public.ability_defs
  (id, name, description, element, kind, target, power, unlock_stage,
   inflict_main, inflict_main_chance)
values
  -- ── FIRE (burn already has a stage 0→2 curve — one more cheap option) ──
  ('funkenstoss', 'Spark Jab',
   'A quick jab wreathed in fire — cheap, and often enough to ignite.',
   'fire', 'damage', 'enemy', 15, 0, 'burn', 0.50),

  -- ── ICE (was empty) ──────────────────────────────────────────
  ('frostbiss', 'Frostbite',
   'A chilling bite — cheap, and often enough to chill.',
   'ice', 'damage', 'enemy', 20, 0, 'frost', 0.50),
  ('eissturm', 'Blizzard',
   'A raging ice storm.',
   'ice', 'damage', 'enemy', 70, 1, 'frost', 0.40),
  ('ewige_kaelte', 'Absolute Zero',
   'Cold enough to stop a heart, let alone a turn — Ice''s heaviest ailment.',
   'ice', 'damage', 'enemy', 65, 2, 'freeze', 0.35),

  -- ── LIGHTNING (was empty) ────────────────────────────────────
  ('statikschlag', 'Static Shock',
   'A crackling jolt — cheap, and often enough to lock up muscles.',
   'lightning', 'damage', 'enemy', 20, 0, 'paralysis', 0.50),
  ('donnerhieb', 'Thunder Fang',
   'A lightning-charged bite.',
   'lightning', 'damage', 'enemy', 75, 1, 'paralysis', 0.35),
  ('gerichtsblitz', 'Judgment Bolt',
   'A sky-splitting strike — Lightning''s flagship.',
   'lightning', 'damage', 'enemy', 100, 2, 'paralysis', 0.40),

  -- ── STONE (was empty) ────────────────────────────────────────
  ('kieselwurf', 'Pebble Toss',
   'A thrown stone — cheap, and often enough to petrify on a lucky hit.',
   'stone', 'damage', 'enemy', 12, 0, 'petrify', 0.30),
  ('felsbrocken', 'Boulder Crush',
   'A crushing slab of stone.',
   'stone', 'damage', 'enemy', 80, 1, 'petrify', 0.30),
  ('gaias_urteil', 'Gaia''s Judgment',
   'The mountain itself passes judgment — Stone''s flagship.',
   'stone', 'damage', 'enemy', 100, 2, 'petrify', 0.40),

  -- ── PLANT (poison, tied to Plant for the first time) ─────────
  ('sporenwolke', 'Toxic Spores',
   'A cloud of spores — cheap, and often enough to poison.',
   'plant', 'damage', 'enemy', 15, 0, 'poison', 0.50),
  ('giftranke', 'Poison Vine',
   'A venom-laced vine strike.',
   'plant', 'damage', 'enemy', 65, 1, 'poison', 0.35),
  ('naturzorn', 'Nature''s Wrath',
   'The forest''s full fury — Plant''s flagship.',
   'plant', 'damage', 'enemy', 90, 2, 'poison', 0.40),

  -- ── WATER (soaked) ────────────────────────────────────────────
  ('wasserstrahl', 'Water Jet',
   'A pressurised jet of water — cheap, and often enough to soak.',
   'water', 'damage', 'enemy', 20, 0, 'soaked', 0.50),
  ('sintflut', 'Deluge',
   'A drenching downpour.',
   'water', 'damage', 'enemy', 70, 1, 'soaked', 0.35),
  ('mahlstrom', 'Maelstrom',
   'A crushing whirlpool — Water''s flagship.',
   'water', 'damage', 'enemy', 95, 2, 'soaked', 0.40),

  -- ── LIGHT (dazzled) ───────────────────────────────────────────
  ('blitzlicht', 'Flash Bulb',
   'A blinding flash — cheap, and often enough to dazzle.',
   'light', 'damage', 'enemy', 15, 0, 'dazzled', 0.50),
  ('strahlenkranz', 'Radiant Beam',
   'A focused beam of pure light.',
   'light', 'damage', 'enemy', 65, 1, 'dazzled', 0.35),
  ('sonneneruption', 'Solar Flare',
   'A blinding eruption of light — Light''s flagship.',
   'light', 'damage', 'enemy', 90, 2, 'dazzled', 0.40),

  -- ── SHADOW (fear already exists — confusion + the "deevolution" debuff
  -- both live here: dread and creeping corruption are Shadow's whole thing) ──
  ('unheilvoller_blick', 'Unnerving Gaze',
   'A gaze that unravels the mind — cheap, and often enough to confuse.',
   'shadow', 'damage', 'enemy', 15, 0, 'confusion', 0.40),
  ('geistesbeugung', 'Mind Warp',
   'A twisting psychic assault.',
   'shadow', 'damage', 'enemy', 60, 1, 'confusion', 0.35),

  -- No real hit, just a low-chance status — same "einschuechterung"/
  -- "stolperfalle" shape as the existing cheap neutral moves, rounding out
  -- the bottom of the AP range for the two brand-new types.
  ('frostiger_blick', 'Chilling Glare',
   'No real hit — just a cold stare that may chill the target.',
   'ice', 'damage', 'enemy', 0, 0, 'frost', 0.15),
  ('warnendes_grollen', 'Warning Rumble',
   'No real hit — just a tremor that may catch the target off guard.',
   'stone', 'damage', 'enemy', 0, 0, 'petrify', 0.10)
on conflict (id) do nothing;

-- ── The "Deevolution" move — its own insert (a debuff, not a main status) ──
insert into public.ability_defs
  (id, name, description, element, kind, target, power, unlock_stage,
   inflict_debuff, inflict_debuff_chance)
values
  ('fluch_der_regression', 'Curse of Regression',
   'A corrupting curse that unwinds the target''s growth, for a while — '
   'Shadow''s flagship.',
   'shadow', 'damage', 'enemy', 55, 2, 'regression', 0.50)
on conflict (id) do nothing;

-- ── Multi-hit / cleave for the types that had none yet (user's own
-- "Zweifachangriffe" ask; fire/stone/lightning/shadow already got one each
-- via add_ability_variety.sql) ──
insert into public.ability_defs
  (id, name, description, element, kind, target, power, unlock_stage,
   extra_hit_chance, extra_hit_same_target)
values
  ('eissplitter', 'Frost Shards',
   'Ice attack that may strike the same target again.',
   'ice', 'damage', 'enemy', 40, 1, 0.50, true),
  ('samensalve', 'Seed Barrage',
   'Plant attack that may lash out at another enemy too.',
   'plant', 'damage', 'enemy', 40, 1, 0.50, false),
  ('blasenstrahl', 'Bubble Beam',
   'Water attack that may strike the same target again.',
   'water', 'damage', 'enemy', 35, 1, 0.55, true),
  ('prismenschuss', 'Prism Shot',
   'Light attack that may lash out at another enemy too.',
   'light', 'damage', 'enemy', 35, 1, 0.55, false)
on conflict (id) do nothing;
