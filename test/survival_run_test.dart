import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/survival_run.dart';

SpeciesDef _species(String id) => SpeciesDef(
  id: id,
  name: id,
  element: CreatureElement.fire,
  rarity: CreatureRarity.common,
  stats: const {},
  stages: const [
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
    SpeciesStage(name: 's'),
  ],
);

void main() {
  setUp(() {
    kSpeciesDefs
      ..clear()
      ..addAll({'mouse': _species('mouse'), 'wolf': _species('wolf')});
  });

  tearDown(() => kSpeciesDefs.clear());

  group('isSurvivalBossFloor', () {
    test('every Nth floor is a boss, default every 5', () {
      expect(isSurvivalBossFloor(1), isFalse);
      expect(isSurvivalBossFloor(4), isFalse);
      expect(isSurvivalBossFloor(5), isTrue);
      expect(isSurvivalBossFloor(10), isTrue);
      expect(isSurvivalBossFloor(11), isFalse);
    });
  });

  group('survivalEnemyLevel', () {
    test('rises roughly +1 every two floors, independent of campaign state',
        () {
      expect(survivalEnemyLevel(1), 1);
      expect(survivalEnemyLevel(3), 2);
      expect(survivalEnemyLevel(5) > survivalEnemyLevel(3), isTrue);
    });

    test('a boss floor fights above its line position', () {
      // Floor 5 is a boss (default dial) — its level must exceed a
      // same-position non-boss floor would have gotten.
      final bossLevel = survivalEnemyLevel(5);
      final nonBossSameSpot = 1 + (5 - 1) ~/ 2;
      expect(bossLevel, greaterThan(nonBossSameSpot));
    });
  });

  group('buildFloorSquad', () {
    test('a boss floor is always a lone elite', () {
      final squad = buildFloorSquad(5, rng: math.Random(1));
      expect(squad, hasLength(1));
      expect(squad.single.isBoss, isTrue);
    });

    test('enemy count grows across floors, never past kFieldSlots', () {
      final early = buildFloorSquad(1, rng: math.Random(1)).length;
      final later =
          buildFloorSquad(30, rng: math.Random(1)).length;
      expect(early, greaterThanOrEqualTo(1));
      expect(later, greaterThanOrEqualTo(early));
      expect(later, lessThanOrEqualTo(3)); // kFieldSlots' own default
    });

    test('empty species catalog yields an empty (not crashing) squad', () {
      kSpeciesDefs.clear();
      expect(buildFloorSquad(1), isEmpty);
    });
  });

  group('goldRewardForFloors', () {
    test('nothing for a run that cleared no floor', () {
      expect(goldRewardForFloors(0), 0);
      expect(goldRewardForFloors(-3), 0);
    });

    test('triangular, not linear — floor 3 pays more than 3x floor 1', () {
      final one = goldRewardForFloors(1);
      final three = goldRewardForFloors(3);
      expect(three, greaterThan(one * 3));
    });

    test('monotonically increasing with floors cleared', () {
      for (var f = 1; f < 20; f++) {
        expect(goldRewardForFloors(f + 1), greaterThan(goldRewardForFloors(f)));
      }
    });
  });
}
