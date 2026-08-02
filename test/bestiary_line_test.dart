import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';

// ── Die ganze Linie, nicht nur die erste Stufe (user 2026-08-01) ──
// "beim bestiary will ich alle Monster haben, nicht nur stufe 1. Bitte immer
//  alle drei nebeneinander"
//
// The screen needs a loaded controller to pump, so what is pinned is the data
// its row rests on: the row asks every species for stages 0, 1 and 2
// unconditionally, and the completion figure adds one to the best stage owned.
// Both must hold for a species whose author filled in fewer stages than three —
// the roster is Dev-Mode content and nothing enforces the count at write time.
SpeciesDef species(List<SpeciesStage> stages) => SpeciesDef(
  id: 'x',
  name: 'X',
  element: CreatureElement.fire,
  rarity: CreatureRarity.common,
  stats: const {},
  stages: stages,
);

void main() {
  test('the three stages come back in order', () {
    final s = species(const [
      SpeciesStage(name: 'Kit'),
      SpeciesStage(name: 'Hound'),
      SpeciesStage(name: 'Warg'),
    ]);
    expect([for (var i = 0; i < 3; i++) s.stageAt(i).name],
        ['Kit', 'Hound', 'Warg']);
  });

  test('an out-of-range stage clamps rather than throwing', () {
    // The completion readout is `bestStage + 1`, and a species caught at its
    // final form must not walk off the end of the list.
    final s = species(const [
      SpeciesStage(name: 'a'),
      SpeciesStage(name: 'b'),
      SpeciesStage(name: 'c'),
    ]);
    expect(s.stageAt(-1).name, 'a');
    expect(s.stageAt(7).name, 'c');
  });

  test('a half-authored species still fills three tiles', () {
    // Dev Mode can save a species with one stage. The row draws three either
    // way — it must repeat the last one, not crash the whole page.
    final s = species(const [SpeciesStage(name: 'only')]);
    expect([for (var i = 0; i < 3; i++) s.stageAt(i).name],
        ['only', 'only', 'only']);
  });
}
