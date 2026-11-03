import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/building_effects.dart';

// Upgrading must beat building a second one (user 2026-09-28): every worker post
// grows by a percentage per level, on top of the seats a level unlocks — and a
// row saved back when posts were flat picks the growth up instead of hiding it.
void main() {
  test('every worker post grows per level', () {
    for (final entry in kBuildingEffects.entries) {
      for (final w in entry.value.workshops) {
        expect(
          w.levelScale(10),
          greaterThan(w.levelScale(1)),
          reason: '${entry.key} · ${w.resource}',
        );
      }
    }
  });

  test('a level-10 wood camp is worth 1.05^9 of a level-1 one, per worker', () {
    final w = kBuildingEffects['small_wood_camp']!.workshops.single;
    expect(w.levelScale(1), 1);
    expect(w.levelScale(10), closeTo(1.55133, 0.001));
  });

  test('a flat (1) or missing row factor adopts the code percentage', () {
    for (final f in [null, 1.0]) {
      final merged = reconcileEffects(
        'small_wood_camp',
        dbWorkshops: [
          WorkshopRole(
            stat: CreatureStat.production,
            resource: 'wood',
            mult: 3,
            slots: 1,
            levelFactor: f,
          ),
        ],
        dbEffects: const [],
      ).workshops.single;
      expect(merged.levelFactor, kWorkerLevelGrowth, reason: '$f');
      expect(merged.mult, 3, reason: 'the row still owns the numbers');
    }
  });

  test('a deliberately tuned row factor stays', () {
    final merged = reconcileEffects(
      'small_wood_camp',
      dbWorkshops: [
        WorkshopRole(
          stat: CreatureStat.production,
          resource: 'wood',
          mult: 2,
          slots: 1,
          levelFactor: 1.2,
        ),
      ],
      dbEffects: const [],
    ).workshops.single;
    expect(merged.levelFactor, 1.2);
  });
}
