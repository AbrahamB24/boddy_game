import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';

// ── Where a settlement-wide screen is reached FROM (user 2026-07-30) ──
// "Worker Verwaltung über Castle und Population über jedes Haus aufrufbar
// machen."
//
// Both were only reachable through the Manage screen's tabs — settlement-wide
// decisions with no door in the settlement itself. The building dialog offers
// them now, and which building offers which is a RULE, not a list of ids: the
// hall runs the workforce because it is the hall, and a dwelling opens the
// housing budget because it is a dwelling. A list would have gone stale at the
// next era's pen.
void main() {
  test('every dwelling in the roster is one, in every era it exists', () {
    // Names the ones that must qualify, so a rule that accidentally stopped
    // matching (e.g. a pen re-authored as an effect instead of the column) fails
    // here rather than by quietly losing its door.
    final dwellings = ['small_house', 'large_house', 'pen_a_e2', 'pen_b_e8'];
    for (final id in dwellings) {
      final def = kFallbackBuildingDefs[id]!;
      expect(
        def.sheltersMonsters(1),
        isTrue,
        reason: '$id (${def.name}) must open the Population screen',
      );
    }
  });

  test('a workplace is not a dwelling', () {
    // The door has to be discriminating or it is not a door: a lumber camp and a
    // store shelter nobody, whatever else they do.
    for (final id in ['small_wood_camp', 'storehouse', 'gold_vault']) {
      final def = kFallbackBuildingDefs[id]!;
      expect(def.sheltersMonsters(1), isFalse, reason: id);
    }
  });

  test('the Castle runs the workforce AND shelters', () {
    final hall = kFallbackBuildingDefs.values.firstWhere(
      (d) => d.isMainBuilding,
    );
    expect(hall.name, 'Castle');
    // Exactly one building is the hall, so exactly one carries the Workers door.
    expect(
      kFallbackBuildingDefs.values.where((d) => d.isMainBuilding).length,
      1,
    );
    // It houses five, so it gets the Population door too — the dialog offers
    // both rather than picking one, which is why _primaryActions returns a list.
    expect(hall.sheltersMonsters(1), isTrue);
  });

  test('the rule is the one the capacity is summed by', () {
    // If these two ever disagree, a building would either shelter monsters with
    // no door to manage them or offer a door onto nothing.
    for (final def in kFallbackBuildingDefs.values) {
      final counts = def.hasEffect('housing', 1)
          ? def.effectAt('housing', '', 1, level: 1) > 0
          : def.housingCapacity > 0;
      expect(def.sheltersMonsters(1), counts, reason: def.id);
    }
  });
}
