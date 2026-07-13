import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

void main() {
  group('civilian stats', () {
    test('there are 6 combat + 8 civilian stats, cleanly split', () {
      expect(kCombatStats.length, 6);
      expect(kCivilianStats.length, 8);
      expect(CreatureStat.values.length, 14);
      for (final s in kCombatStats) {
        expect(s.isCombat, isTrue, reason: '${s.name} should be combat');
      }
      for (final s in kCivilianStats) {
        expect(s.isCivilian, isTrue, reason: '${s.name} should be civilian');
      }
    });
  });

  group('breeding stat effects', () {
    test('favored-gene chance starts at a coin flip and rises toward 1', () {
      expect(breedingFavoredChance(0), closeTo(0.5, 1e-9));
      final low = breedingFavoredChance(20);
      final high = breedingFavoredChance(120);
      expect(low, greaterThan(0.5));
      expect(high, greaterThan(low));
      expect(high, lessThan(1.0));
    });

    test('incubation time shrinks with breeding stat but never past half', () {
      expect(breedingHours(10, 0), closeTo(10, 1e-9));
      final some = breedingHours(10, 40);
      final lots = breedingHours(10, 100000);
      expect(some, lessThan(10));
      expect(some, greaterThan(5));
      expect(lots, greaterThanOrEqualTo(5.0)); // cut caps at 50%
    });

    test('favoredChance drives which parent gene wins', () {
      final rng = math.Random(3);
      final a = {for (final s in CreatureStat.values) s: 10.0};
      final b = {for (final s in CreatureStat.values) s: 2.0};
      final alwaysBest =
          CreatureInstance.inheritGenes(a, b, rng, favoredChance: 1.0);
      final alwaysWorst =
          CreatureInstance.inheritGenes(a, b, rng, favoredChance: 0.0);
      for (final s in CreatureStat.values) {
        expect(alwaysBest[s], 10.0);
        expect(alwaysWorst[s], 2.0);
      }
    });
  });

  group('BuildingDef workshop roles', () {
    test('housing capacity aliases the population field', () {
      const def = BuildingDef(
        id: 'x',
        name: 'X',
        color: Color(0xFF000000),
        gridW: 1,
        gridH: 1,
        population: 12,
      );
      expect(def.housingCapacity, 12);
    });

    test('workshop roles survive a toDefRow → fromDefRow round-trip', () {
      const def = BuildingDef(
        id: 'lumber',
        name: 'Lumber',
        color: Color(0xFF000000),
        gridW: 2,
        gridH: 2,
        population: 0,
        workshops: [
          WorkshopRole(
            stat: CreatureStat.woodcutting,
            resource: 'wood',
            mult: 0.5,
            slots: 6,
          ),
          WorkshopRole(
            stat: CreatureStat.research,
            resource: WorkshopRole.kResearch,
            mult: 40,
            slots: 3,
          ),
        ],
      );
      final restored = BuildingDef.fromDefRow(def.toDefRow());
      expect(restored.workshops.length, 2);
      final wood = restored.workshops.firstWhere((w) => w.resource == 'wood');
      expect(wood.stat, CreatureStat.woodcutting);
      expect(wood.mult, 0.5);
      expect(wood.slots, 6);
      final research = restored.workshops
          .firstWhere((w) => w.resource == WorkshopRole.kResearch);
      expect(research.stat, CreatureStat.research);
      expect(research.producesResource, isFalse);
    });
  });

  group('CreatureInstance work assignment + gene backfill', () {
    CreatureInstance make() => CreatureInstance(
      id: 'c',
      userId: 'u',
      speciesId: 'unknown_species', // no def → statValue falls back to 10/1
      gender: CreatureGender.male,
      level: 1,
      statBase: {for (final s in kCombatStats) s: 20.0}, // civilian missing
      statSlope: {for (final s in kCombatStats) s: 2.0},
    );

    test('a legacy row (combat genes only) reports needing backfill', () {
      final c = make();
      expect(c.needsGeneBackfill, isTrue);
      // Unknown species → backfill can't sample, so it stays incomplete.
      expect(c.backfillGenes(math.Random(1)), isFalse);
    });

    test('assignment fields round-trip through toRow/fromRow', () {
      final c = make()
        ..assignedBuildingId = 'b1'
        ..assignedStat = CreatureStat.mining;
      final row = c.toRow();
      expect(row['assigned_building_id'], 'b1');
      expect(row['assigned_stat'], 'mining');
      final restored = CreatureInstance.fromRow({
        ...row,
        'id': 'c',
        'user_id': 'u',
      });
      expect(restored.assignedBuildingId, 'b1');
      expect(restored.assignedStat, CreatureStat.mining);
      expect(restored.isAssigned, isTrue);
    });
  });
}
