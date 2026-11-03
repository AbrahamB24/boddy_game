import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/services/work_overview.dart';

// The Work page (user 2026-09-19): who sits where, what each seat is worth, what
// a building makes in total — and the sorting and the "fill empty seats" plan on
// top. These pin the arithmetic against the economy's own formula
// (stat × mult × level factor) and the ordering rules.
void main() {
  BuildingDef def(String id, String name, {int slots = 2, double mult = 0.1}) =>
      BuildingDef(
        id: id,
        name: name,
        color: const Color(0xFF000000),
        gridW: 1,
        gridH: 1,
        workshops: [
          WorkshopRole(
            stat: CreatureStat.gathering,
            resource: 'wood',
            mult: mult,
            slots: slots,
          ),
        ],
      );

  PlacedBuilding placed(String id, String type, {int level = 1}) =>
      PlacedBuilding(
        id: id,
        settlementId: 's',
        buildingTypeId: type,
        gridX: 0,
        gridY: 0,
        level: level,
        constructionSecondsRequired: 0,
        constructionSecondsBuilt: 0,
        isComplete: true,
        placedAt: DateTime(2026),
      );

  CreatureInstance mon(
    String id, {
    double gathering = 20,
    String? at,
    bool post = true,
  }) => CreatureInstance(
    id: id,
    userId: 'u',
    speciesId: 's',
    gender: CreatureGender.male,
    statBase: {CreatureStat.gathering: gathering},
    statSlope: const {},
    assignedBuildingId: post ? at : null,
    assignedStat: post && at != null ? CreatureStat.gathering : null,
  );

  final wood = def('wood', 'Wood Camp', slots: 3);
  final stone = def('stone', 'Stone Camp', slots: 2, mult: 0.2);
  final defs = {'wood': wood, 'stone': stone};
  BuildingDef? lookup(String id) => defs[id];

  List<WorkSite> sites(
    List<CreatureInstance> creatures, {
    double energy = 1.0,
  }) => buildWorkSites(
    buildings: [placed('b1', 'wood'), placed('b2', 'stone')],
    creatures: creatures,
    connectedIds: {'b1', 'b2'},
    isWorking: (c) => c.isAssigned,
    absenceOf: (_) => null,
    era: 1,
    energy: energy,
    defOf: lookup,
  );

  group('a site', () {
    test('has one seat per slot, staffed or empty', () {
      final s = sites([
        mon('a', at: 'b1'),
      ]).firstWhere((x) => x.def.id == 'wood');
      expect(s.cap, 3);
      expect(s.staffed, 1);
      expect(s.empty, 2);
    });

    test('each seat figure is stat x mult, and the total is their sum', () {
      // 30 and 20 gathering at x0.1 -> 3.0 + 2.0 per hour at level 1.
      final s = sites([
        mon('a', gathering: 30, at: 'b1'),
        mon('b', gathering: 20, at: 'b1'),
      ]).firstWhere((x) => x.def.id == 'wood');
      expect(s.resources['wood'], closeTo(5.0, 1e-9));
      // Highest producer first.
      expect(s.seats.first.creature!.id, 'a');
      expect(s.seats.first.figure, startsWith('+3.0/h'));
      expect(s.totalParts.first, startsWith('+5.0/h'));
    });

    test('todays energy scales the total the way the building dialog does', () {
      final s = sites([
        mon('a', gathering: 40, at: 'b1'),
      ], energy: 0.5).firstWhere((x) => x.def.id == 'wood');
      expect(s.resources['wood'], closeTo(2.0, 1e-9)); // 4.0 x 0.5
    });

    test('a monster that is away holds its seat but adds nothing', () {
      final away = buildWorkSites(
        buildings: [placed('b1', 'wood')],
        creatures: [mon('a', gathering: 40, at: 'b1')],
        connectedIds: {'b1'},
        isWorking: (_) => false,
        absenceOf: (_) => 'away',
        era: 1,
        energy: 1,
        defOf: lookup,
      ).single;
      expect(away.staffed, 1);
      expect(away.seats.first.absence, 'away');
      expect(away.resources['wood'] ?? 0, 0);
    });

    test('a building no road reaches is not listed, but is reported', () {
      final buildings = [placed('b1', 'wood'), placed('b2', 'stone')];
      final listed = buildWorkSites(
        buildings: buildings,
        creatures: const [],
        connectedIds: {'b1'},
        isWorking: (_) => false,
        absenceOf: (_) => null,
        era: 1,
        energy: 1,
        defOf: lookup,
      );
      expect(listed.map((s) => s.def.id), ['wood']);
      final lost = disconnectedWorkshops(
        buildings: buildings,
        connectedIds: {'b1'},
        defOf: lookup,
      );
      expect(lost.map((x) => x.def.id), ['stone']);
    });

    test('a building in storage is neither listed nor "cut off"', () {
      final buildings = [
        placed('b1', 'wood'),
        placed('b2', 'stone').copyWith(isStored: true),
      ];
      final listed = buildWorkSites(
        buildings: buildings,
        creatures: const [],
        connectedIds: {'b1', 'b2'},
        isWorking: (_) => false,
        absenceOf: (_) => null,
        era: 1,
        energy: 1,
        defOf: lookup,
      );
      expect(listed.map((s) => s.def.id), ['wood']);
      expect(
        disconnectedWorkshops(
          buildings: buildings,
          connectedIds: {'b1'},
          defOf: lookup,
        ),
        isEmpty,
      );
    });
  });

  group('the summary adds every site up', () {
    test('seats and production', () {
      final all = sites([
        mon('a', gathering: 30, at: 'b1'),
        mon('b', gathering: 10, at: 'b2'),
      ]);
      final sum = WorkSummary.of(all);
      expect(sum.cap, 5);
      expect(sum.staffed, 2);
      expect(sum.empty, 3);
      // Both camps make wood here: 30 x 0.1 = 3, and 10 x 0.2 = 2.
      expect(sum.resources['wood'], closeTo(5.0, 1e-9));
    });
  });

  group('sorting', () {
    final all = sites([
      mon('a', gathering: 30, at: 'b1'),
      mon('b', gathering: 10, at: 'b2'),
      mon('c', gathering: 10, at: 'b2'),
    ]);

    test('Need: the emptiest building first', () {
      expect(sortedSites(all, WorkSort.need).map((s) => s.def.id), [
        'wood',
        'stone',
      ]);
    });

    test('Output: the biggest producer first, and reversing flips it', () {
      // wood: 3.0; stone: 2 x (10 x 0.2) = 4.0
      expect(sortedSites(all, WorkSort.output).map((s) => s.def.id), [
        'stone',
        'wood',
      ]);
      expect(
        sortedSites(all, WorkSort.output, reversed: true).map((s) => s.def.id),
        ['wood', 'stone'],
      );
    });

    test('Name: A to Z', () {
      expect(sortedSites(all, WorkSort.name).map((s) => s.def.name), [
        'Stone Camp',
        'Wood Camp',
      ]);
    });
  });

  group('fill empty seats', () {
    test('the best free monster takes the seat it is worth most in', () {
      final all = sites(const []);
      final plan = planFill(
        sites: all,
        free: [
          mon('weak', gathering: 10, post: false),
          mon('strong', gathering: 50, post: false),
        ],
      );
      expect(plan, hasLength(2));
      // Stone pays x0.2, wood x0.1: the strong one goes to stone first.
      expect(plan.first.creature.id, 'strong');
      expect(plan.first.building.id, 'b2');
    });

    test('never more monsters than seats, nor more seats than monsters', () {
      final all = sites(const []);
      expect(planFill(sites: all, free: const []), isEmpty);
      final plan = planFill(
        sites: all,
        free: [for (var i = 0; i < 9; i++) mon('m$i', post: false)],
      );
      expect(plan, hasLength(5)); // 3 + 2 seats
      expect({for (final p in plan) p.creature.id}, hasLength(5));
    });
  });
}
