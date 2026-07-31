import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

// Per-building / per-era tunables (user 2026-07-24): max level per era, custom
// cost/time factors, and their round-trip through the `metadata` jsonb bag.
void main() {
  BuildingDef def({
    Map<int, int> maxLevelPerEra = const {},
    double costFactor = 1.6,
    double timeFactor = 1.6,
    Map<String, double> resourceCost = const {},
    double constructionHours = 0,
  }) => BuildingDef(
    id: 'b',
    name: 'B',
    color: const Color(0xFF000000),
    gridW: 2,
    gridH: 2,
    resourceCost: resourceCost,
    constructionHours: constructionHours,
    maxLevelPerEra: maxLevelPerEra,
    costFactor: costFactor,
    timeFactor: timeFactor,
  );

  group('maxBuildingLevelFor', () {
    test('no per-era caps → the flat lifetime cap', () {
      expect(maxBuildingLevelFor(def(), 1), kMaxBuildingLevel);
      expect(maxBuildingLevelFor(def(), 8), kMaxBuildingLevel);
    });

    test('rises with era: the highest reached era key wins', () {
      final d = def(maxLevelPerEra: {1: 3, 3: 5, 8: 10});
      expect(maxBuildingLevelFor(d, 1), 3);
      expect(maxBuildingLevelFor(d, 2), 3);
      expect(maxBuildingLevelFor(d, 3), 5);
      expect(maxBuildingLevelFor(d, 7), 5);
      expect(maxBuildingLevelFor(d, 8), 10);
    });

    test('before the earliest defined era, floors to that earliest cap', () {
      final d = def(maxLevelPerEra: {3: 5, 8: 10});
      expect(maxBuildingLevelFor(d, 1), 5);
    });

    test('an authored cap ABOVE the default is honoured, not clamped', () {
      // kMaxBuildingLevel is the default for a def that authors nothing — not
      // a ceiling over one that does (user 2026-07-26). Clamping it made the
      // Dev-Mode form promise levels the game then refused to grant.
      final d = def(maxLevelPerEra: {1: 21});
      expect(maxBuildingLevelFor(d, 1), 21);
      expect(21, greaterThan(kMaxBuildingLevel));
    });
  });

  group('per-level slot steps run to the top of the def', () {
    WorkshopRole role(Map<int, int> steps) => WorkshopRole(
      stat: CreatureStat.breeding,
      resource: WorkshopRole.kBreeding,
      slots: 1,
      slotSteps: steps,
    );

    test('steps past level 10 are counted, not silently dropped', () {
      // The bug (user 2026-07-26): the form let them author +1 worker on every
      // level up to 21, then showed 8 — effectiveSlots clamped the level to
      // kMaxBuildingLevel while every OTHER per-level effect had no such cap.
      final r = role({for (var l = 2; l <= 21; l++) l: 1});
      expect(effectiveSlots(r, 10), 10);
      expect(effectiveSlots(r, 15), 15);
      expect(effectiveSlots(r, 21), 21);
    });

    test('housing steps and slot steps agree at the same level', () {
      final steps = {for (var l = 2; l <= 21; l++) l: 1};
      final housing = BuildingEffect(
        type: 'housing',
        value: 1,
        levelSteps: {for (final e in steps.entries) e.key: e.value.toDouble()},
      );
      expect(effectiveSlots(role(steps), 21), housing.valueAtLevel(21));
    });

    test('a level below 1 does not underflow', () {
      expect(effectiveSlots(role({2: 5}), 0), 1);
    });
  });

  group('cost/time honour the def factors', () {
    test('costFactor scales the per-level cost', () {
      final d = def(costFactor: 2.0, resourceCost: {'wood': 100});
      expect(d.resourceCostAt(1)['wood'], 100);
      expect(d.resourceCostAt(2)['wood'], 200);
      expect(d.resourceCostAt(3)['wood'], 400);
    });

    test('timeFactor scales the per-level build time', () {
      final d = def(timeFactor: 3.0, constructionHours: 1); // 3600s base
      expect(d.constructionSecondsAt(1), 3600);
      expect(d.constructionSecondsAt(2), closeTo(10800, 1e-6));
    });

    test('default factor is the old 1.6', () {
      final d = def(resourceCost: {'wood': 100});
      expect(d.resourceCostAt(2)['wood'], closeTo(160, 1e-6));
    });
  });

  test('metadata round-trips through toDefRow/fromDefRow', () {
    final original = def(
      maxLevelPerEra: {1: 3, 3: 5, 8: 10},
      costFactor: 1.8,
      timeFactor: 1.4,
    );
    final restored = BuildingDef.fromDefRow(original.toDefRow());
    expect(restored.maxLevelPerEra, {1: 3, 3: 5, 8: 10});
    expect(restored.costFactor, 1.8);
    expect(restored.timeFactor, 1.4);
  });

  test('a row without metadata falls back to the defaults', () {
    final row = def().toDefRow()..remove('metadata');
    final restored = BuildingDef.fromDefRow(row);
    expect(restored.maxLevelPerEra, isEmpty);
    expect(restored.costFactor, 1.6);
    expect(restored.timeFactor, 1.6);
  });

  group('per-era effects', () {
    BuildingDef withEffects(List<BuildingEffect> fx) => BuildingDef(
      id: 'b',
      name: 'B',
      color: const Color(0xFF000000),
      gridW: 2,
      gridH: 2,
      effects: fx,
    );

    test('effectAt: highest reached era wins, inactive eras ignored', () {
      final d = withEffects(const [
        BuildingEffect(type: 'heal', key: 'speed', value: 0.1, era: 1),
        BuildingEffect(type: 'heal', key: 'speed', value: 0.3, era: 3),
      ]);
      expect(d.effectAt('heal', 'speed', 1), 0.1);
      expect(d.effectAt('heal', 'speed', 2), 0.1);
      expect(d.effectAt('heal', 'speed', 3), 0.3);
      expect(d.effectAt('heal', 'speed', 8), 0.3);
      expect(d.effectAt('heal', 'cost', 8), 0); // unset key
    });

    test('hasEffect distinguishes an unset key from a zero value', () {
      final d = withEffects(const [
        BuildingEffect(type: 'housing', value: 0, era: 3),
      ]);
      expect(d.hasEffect('housing', 2), isFalse);
      expect(d.hasEffect('housing', 3), isTrue);
    });

    test('effectKeys lists the distinct resources of a type', () {
      final d = withEffects(const [
        BuildingEffect(type: 'production', key: 'wood', value: 5),
        BuildingEffect(type: 'production', key: 'stone', value: 3, era: 2),
        BuildingEffect(type: 'expedition', key: 'carry', value: 0.1),
      ]);
      expect(d.effectKeys('production'), {'wood', 'stone'});
      expect(d.effectKeys('expedition'), {'carry'});
    });

    test('palette effects round-trip through the effects jsonb', () {
      final original = withEffects(const [
        BuildingEffect(type: 'production', key: 'wood', value: 5, era: 1),
        BuildingEffect(type: 'resource', key: 'all', value: 0.2, era: 3),
        BuildingEffect(type: 'expeditionSlots', value: 1, era: 5),
        BuildingEffect(type: 'housing', value: 40, era: 2),
      ]);
      final restored = BuildingDef.fromDefRow(original.toDefRow());
      expect(restored.effectAt('production', 'wood', 1), 5);
      expect(restored.effectAt('resource', 'all', 3), 0.2);
      expect(restored.effectAt('expeditionSlots', '', 5), 1);
      expect(restored.effectAt('housing', '', 2), 40);
      expect(restored.effectAt('housing', '', 1), 0); // not yet era 2
    });

    test('housing per-level steps: start + explicit increments, round-tripped',
        () {
      // Start 5 seats, +3 at level 2, +4 at level 4 (nothing at 3 or 5).
      final d = withEffects(const [
        BuildingEffect(
          type: 'housing',
          value: 5,
          era: 1,
          levelSteps: {2: 3, 4: 4},
        ),
      ]);
      // effectAt applies the ladder when a level is passed.
      expect(d.effectAt('housing', '', 1, level: 1), 5);
      expect(d.effectAt('housing', '', 1, level: 2), 8);
      expect(d.effectAt('housing', '', 1, level: 3), 8); // no step at 3
      expect(d.effectAt('housing', '', 1, level: 4), 12);
      expect(d.effectAt('housing', '', 1, level: 9), 12); // no step past 4

      // Survives the effects jsonb round-trip.
      final restored = BuildingDef.fromDefRow(d.toDefRow());
      expect(restored.effectAt('housing', '', 1, level: 2), 8);
      expect(restored.effectAt('housing', '', 1, level: 4), 12);
    });

    test('an effect with no levelSteps still scales the old multiplicative way',
        () {
      // Backward-compat: valueAtLevel == value × levelScale when no steps.
      final d = withEffects(const [
        BuildingEffect(type: 'production', key: 'wood', value: 10, era: 1),
      ]);
      final e = d.effectEntry('production', 'wood', 1)!;
      expect(d.effectAt('production', 'wood', 1, level: 3),
          10 * e.levelScale(3));
    });

    test('legacy bonus fields still round-trip separately', () {
      final d = BuildingDef(
        id: 'b',
        name: 'B',
        color: const Color(0xFF000000),
        gridW: 2,
        gridH: 2,
        queueSlotsBonus: 2,
        effects: const [BuildingEffect(type: 'production', key: 'gold', value: 1)],
      );
      final restored = BuildingDef.fromDefRow(d.toDefRow());
      expect(restored.queueSlotsBonus, 2);
      expect(restored.effectAt('production', 'gold', 1), 1);
    });

    test('queueSlots/buildSlots/healSlots/breeding per-level steps round-trip',
        () {
      final d = withEffects(const [
        BuildingEffect(type: 'queueSlots', value: 1, levelSteps: {3: 1}),
        BuildingEffect(type: 'buildSlots', value: 1, levelSteps: {2: 1, 6: 1}),
        BuildingEffect(type: 'healSlots', value: 2, levelSteps: {2: 1, 5: 2}),
        BuildingEffect(type: 'breeding', value: 1, levelSteps: {4: 1}),
      ]);
      // The convenience getters read the explicit per-level ladder.
      expect(d.queueSlotsAt(1), 1);
      expect(d.queueSlotsAt(3), 2);
      expect(d.buildSlotsAt(1), 1);
      expect(d.buildSlotsAt(2), 2);
      expect(d.buildSlotsAt(6), 3);
      expect(d.healSlotsAt(1), 2);
      expect(d.healSlotsAt(2), 3);
      expect(d.healSlotsAt(5), 5);
      expect(d.concurrentJobsAt(4), 2);

      final restored = BuildingDef.fromDefRow(d.toDefRow());
      expect(restored.queueSlotsAt(3), 2);
      expect(restored.buildSlotsAt(6), 3);
      expect(restored.healSlotsAt(5), 5);
      expect(restored.concurrentJobsAt(4), 2);
    });

    test('worker slotSteps round-trip through the effects jsonb', () {
      final d = BuildingDef(
        id: 'b',
        name: 'B',
        color: const Color(0xFF000000),
        gridW: 2,
        gridH: 2,
        workshops: const [
          WorkshopRole(
            stat: CreatureStat.production,
            resource: 'wood',
            slots: 2,
            slotSteps: {3: 1, 5: 2},
          ),
        ],
      );
      expect(effectiveSlots(d.workshops.first, 1), 2);
      expect(effectiveSlots(d.workshops.first, 3), 3);
      expect(effectiveSlots(d.workshops.first, 5), 5);

      final restored = BuildingDef.fromDefRow(d.toDefRow());
      expect(restored.workshops.first.slotSteps, {3: 1, 5: 2});
      expect(effectiveSlots(restored.workshops.first, 5), 5);
    });
  });
}
