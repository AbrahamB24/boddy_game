import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';

// ── Dev: Evolution direkt auslösen (user 2026-08-01) ────────
// "einen devbutton, wobmit ich direkt eine evolution auslösen kann (d.h level
//  bis dort steigern unabhängig von der ära)"
//
// The button raises the LEVEL to the threshold and then evolves normally,
// rather than bumping the stage on its own. That distinction is the whole
// design: a stage-2 monster at level 4 has stats no real creature could have,
// and every balance reading taken off it afterwards would be fiction.
//
// devEvolve needs a live Supabase to save, so what is pinned here is the gate
// it opens: canEvolve is purely the level, and raising the level to
// evoLevelFrom is exactly what unlocks it.
void main() {
  // A creature reads its species out of the live table, so the fixture goes in
  // there — the same way every other test in this repo seeds content.
  setUp(() => kSpeciesDefs.clear());
  tearDown(() => kSpeciesDefs.clear());

  SpeciesDef species({int evo1 = 16, int evo2 = 36}) => SpeciesDef(
    id: 'x',
    name: 'X',
    element: CreatureElement.fire,
    rarity: CreatureRarity.common,
    evoLevel1: evo1,
    evoLevel2: evo2,
    stats: const {},
    stages: const [
      SpeciesStage(name: 'Kit'),
      SpeciesStage(name: 'Hound'),
      SpeciesStage(name: 'Warg'),
    ],
  );

  CreatureInstance creature(SpeciesDef s, {int level = 1, int stage = 0}) {
    kSpeciesDefs[s.id] = s;
    return CreatureInstance(
      id: 'c',
      userId: 'u',
      speciesId: s.id,
      nickname: null,
      gender: CreatureGender.male,
      level: level,
      xp: 0,
      stage: stage,
      statBase: const {},
      statSlope: const {},
    );
  }

  test('the level IS the gate, and the threshold is per stage', () {
    final s = species();
    expect(creature(s, level: 15).canEvolve, isFalse);
    expect(creature(s, level: 16).canEvolve, isTrue, reason: 'evoLevel1');
    // Stage 1 waits for the second threshold, not the first.
    expect(creature(s, level: 16, stage: 1).canEvolve, isFalse);
    expect(creature(s, level: 36, stage: 1).canEvolve, isTrue);
  });

  test('the final stage has nothing to jump to', () {
    // Which is why the button is hidden there rather than refusing.
    final s = species();
    expect(creature(s, level: 99, stage: 2).hasNextStage, isFalse);
    expect(creature(s, level: 99, stage: 2).canEvolve, isFalse);
  });

  test('raising the level to the threshold is all it takes', () {
    // What devEvolve does before calling evolve().
    final s = species();
    final c = creature(s, level: 3);
    expect(c.canEvolve, isFalse);
    c.level = s.evoLevelFrom(c.stage);
    expect(c.canEvolve, isTrue,
        reason: 'no era cap, no second gate — the level is the whole rule');
  });
}
