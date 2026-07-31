import 'dart:math' as math;

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

void main() {
  group('civilian stats', () {
    test('5 combat + 8 work-role + carry, cleanly split', () {
      // The work roles were rebuilt around WHERE a monster works, not which
      // era-I trade it learned (user 2026-07-25): gathering, production,
      // construction, crafting, breeding, medicine, trade — and `logistics`
      // since 2026-07-30, which works in the stores.
      expect(kCombatStats.length, 5);
      expect(kCivilianStats.length, 8);
      // 5 combat + 8 work-role + carry = 14.
      expect(CreatureStat.values.length, 14);
      for (final s in kCombatStats) {
        expect(s.isCombat, isTrue, reason: '${s.name} should be combat');
      }
      for (final s in kCivilianStats) {
        expect(s.isCivilian, isTrue, reason: '${s.name} should be civilian');
        expect(s.isWorkRole, isTrue, reason: '${s.name} is a work role');
      }
    });

    test('carry is non-combat but not a work role; catchRate is combat', () {
      expect(CreatureStat.carry.isCombat, isFalse);
      expect(CreatureStat.carry.isCivilian, isTrue);
      expect(CreatureStat.carry.isWorkRole, isFalse);
      expect(kCivilianStats, isNot(contains(CreatureStat.carry)));
      // Catch Rate is a combat capability now (budget only — it still just
      // drives catching).
      expect(CreatureStat.catchRate.isCombat, isTrue);
      expect(kCombatStats, contains(CreatureStat.catchRate));
    });

    test('retired stat names still resolve (DB rows say fishing/hunting)', () {
      expect(CreatureStat.fromName('fishing'), CreatureStat.production);
      expect(CreatureStat.fromName('hunting'), CreatureStat.production);
    });
  });


  group('breeding stat effects', () {
    test('the favored-gene chance is flat — the parents do not move it', () {
      // User 2026-07-27: "Der Breedingwert ist irrelevant dafür … ändere die
      // Chance auf 60%". It used to scale with the parents' average breeding
      // stat, which was the only thing that stat did and could not be trained.
      // Breeding SPEED still comes from the breeders posted in the hut.
      expect(breedingFavoredChance(), closeTo(0.60, 1e-9));
      expect(breedingFavoredChance(), kBreedingFavoredChance);
    });

    test('incubation time shrinks with breeding power, without a floor', () {
      // The −50 % ceiling was removed 2026-07-26: past kBreedingK the curve
      // keeps paying, just at a worse rate, and the duration tends to zero
      // without ever getting there.
      expect(breedingHours(10, 0), closeTo(10, 1e-9));
      expect(breedingHours(10, kBreedingK), closeTo(5, 1e-9));
      final some = breedingHours(10, 40);
      final lots = breedingHours(10, 100000);
      expect(some, lessThan(10));
      expect(some, greaterThan(5));
      expect(lots, lessThan(0.1));
      expect(lots, greaterThan(0));
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
            stat: CreatureStat.production,
            resource: 'wood',
            mult: 0.5,
            slots: 6,
          ),
          WorkshopRole(
            stat: CreatureStat.crafting,
            resource: WorkshopRole.kCrafting,
            mult: 40,
            slots: 3,
          ),
        ],
      );
      final restored = BuildingDef.fromDefRow(def.toDefRow());
      expect(restored.workshops.length, 2);
      final wood = restored.workshops.firstWhere((w) => w.resource == 'wood');
      expect(wood.stat, CreatureStat.production);
      expect(wood.mult, 0.5);
      expect(wood.slots, 6);
      final crafting = restored.workshops
          .firstWhere((w) => w.resource == WorkshopRole.kCrafting);
      expect(crafting.stat, CreatureStat.crafting);
      expect(crafting.producesResource, isFalse);
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
        ..assignedStat = CreatureStat.production;
      final row = c.toRow();
      expect(row['assigned_building_id'], 'b1');
      expect(row['assigned_stat'], 'production');
      final restored = CreatureInstance.fromRow({
        ...row,
        'id': 'c',
        'user_id': 'u',
      });
      expect(restored.assignedBuildingId, 'b1');
      expect(restored.assignedStat, CreatureStat.production);
      expect(restored.isAssigned, isTrue);
    });
  });

  group('building levels (user design 2026-07-17)', () {
    test('level 1 is the unscaled baseline', () {
      expect(buildingYieldFactor(1), 1.0);
      expect(buildingCostFactor(1), 1.0);
      expect(buildingTimeFactor(1), 1.0);
      final def = kFallbackBuildingDefs['wood_camp_e1']!;
      expect(def.resourceCostAt(1), def.resourceCost);
      expect(def.constructionSecondsAt(1), def.constructionSeconds);
    });

    test('yield grows linearly, cost/time grow faster (a real trade)', () {
      // L5: yield ×3, cost/time ×6.55 — upgrading buys density, not free
      // scaling.
      expect(buildingYieldFactor(5), closeTo(3.0, 1e-9));
      expect(buildingCostFactor(5), greaterThan(buildingYieldFactor(5)));
      // Monotonic.
      for (var l = 2; l <= kMaxBuildingLevel; l++) {
        expect(buildingYieldFactor(l), greaterThan(buildingYieldFactor(l - 1)));
        expect(buildingCostFactor(l), greaterThan(buildingCostFactor(l - 1)));
      }
    });

    test('a level scales the concrete cost of a real building', () {
      // The 2026-07-24 roster prices per era band × the def's OWN costFactor
      // (level 3 is still in the era-1 band, whose first level is 1).
      final def = kFallbackBuildingDefs['wood_camp_e1']!;
      final base = def.resourceCost['wood']!;
      expect(
        def.resourceCostAt(3)['wood'],
        closeTo(base * def.costFactor * def.costFactor, 1e-6),
      );
    });

    test('the first five levels need no research', () {
      expect(kFreeBuildingLevelCap, 5);
      expect(kMaxBuildingLevel, greaterThanOrEqualTo(kFreeBuildingLevelCap));
    });
  });
}
