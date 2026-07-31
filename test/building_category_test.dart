import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart'
    show kGoodsDefs;

// The Build menu's drawers are an AUTHORED field now (user 2026-07-26: "hier
// muss ich wählen können, welche typ von Gebäude es ist … diese kategorien so
// auch im Build menü übernehmen").
//
// Two things have to hold at once, and they pull against each other: the author
// must be able to overrule the menu, AND the ~84 bundled buildings that were
// never categorised must not all collapse into one drawer. Hence: an authored
// value wins, a missing one is derived exactly as the menu used to derive it.

BuildingDef _def({
  BuildingCategory? category,
  int population = 0,
  bool isRoad = false,
  bool isBuildPlot = false,
  bool isMainBuilding = false,
  List<WorkshopRole> workshops = const [],
}) => BuildingDef(
  id: 'b',
  name: 'B',
  color: const Color(0xFF000000),
  gridW: 1,
  gridH: 1,
  category: category,
  population: population,
  isRoad: isRoad,
  isBuildPlot: isBuildPlot,
  isMainBuilding: isMainBuilding,
  workshops: workshops,
);

void main() {
  group('an authored category wins over anything derivable', () {
    test('even against what the building plainly does', () {
      // A lumber camp the author files under Civic IS Civic. That is the whole
      // point of the field: the inference is no longer the last word.
      final d = _def(
        category: BuildingCategory.civic,
        workshops: const [
          WorkshopRole(stat: CreatureStat.production, resource: 'wood'),
        ],
      );
      expect(categoryOfBuilding(d), BuildingCategory.civic);
    });

    test('but NOT over road / build plot / main hall', () {
      // These three don't place like a building — a road card enters PAINT
      // mode. An authored category that moved one into Production put a
      // road-painting card in among the camps (user 2026-07-26: "wenn ich
      // primitive stone camp bauen will, baut es eine strasse").
      for (final d in [
        _def(category: BuildingCategory.production, isRoad: true),
        _def(category: BuildingCategory.goods, isBuildPlot: true),
        _def(category: BuildingCategory.civic, isMainBuilding: true),
      ]) {
        expect(categoryOfBuilding(d), BuildingCategory.special);
      }
    });

    test('every category is reachable, including the new Military drawer', () {
      for (final c in BuildingCategory.values) {
        expect(categoryOfBuilding(_def(category: c)), c, reason: c.id);
      }
      expect(BuildingCategory.values.map((c) => c.id), containsAll(
        ['production', 'goods', 'housing', 'civic', 'military', 'special'],
      ));
    });
  });

  group('an un-authored building keeps the drawer it always had', () {
    test('wood/stone workers → Production', () {
      for (final res in ['wood', 'stone']) {
        final d = _def(workshops: [
          WorkshopRole(stat: CreatureStat.production, resource: res),
        ]);
        expect(categoryOfBuilding(d), BuildingCategory.production, reason: res);
      }
    });

    test('gold and era goods → Goods', () {
      final good = kGoodsDefs.keys.first;
      for (final res in ['gold', good]) {
        final d = _def(workshops: [
          WorkshopRole(stat: CreatureStat.production, resource: res),
        ]);
        expect(categoryOfBuilding(d), BuildingCategory.goods, reason: res);
      }
    });

    test('housing capacity → Housing', () {
      expect(categoryOfBuilding(_def(population: 4)), BuildingCategory.housing);
    });

    test('roads, plots and the hall → Special', () {
      expect(categoryOfBuilding(_def(isRoad: true)), BuildingCategory.special);
      expect(
        categoryOfBuilding(_def(isBuildPlot: true)),
        BuildingCategory.special,
      );
      expect(
        categoryOfBuilding(_def(isMainBuilding: true)),
        BuildingCategory.special,
      );
    });

    test('everything else → Civic', () {
      final d = _def(workshops: const [
        WorkshopRole(
          stat: CreatureStat.medicine,
          resource: WorkshopRole.kHealSpeed,
        ),
      ]);
      expect(categoryOfBuilding(d), BuildingCategory.civic);
    });

    test('the whole bundled roster still lands somewhere', () {
      // A building with no drawer would simply vanish from the Build menu.
      for (final d in kFallbackBuildingDefs.values) {
        expect(BuildingCategory.values, contains(categoryOfBuilding(d)),
            reason: d.id);
      }
    });
  });

  group('the choice survives a save', () {
    test('it round-trips through the def row', () {
      final row = _def(category: BuildingCategory.military).toDefRow();
      expect((row['metadata'] as Map)['category'], 'military');
      expect(BuildingDef.fromDefRow(row).category, BuildingCategory.military);
    });

    test('"Automatisch" writes NOTHING, so it stays derivable', () {
      // Persisting a derived value would freeze today's inference into the row
      // and quietly make every future def-change a no-op.
      final row = _def(population: 4).toDefRow();
      expect((row['metadata'] as Map).containsKey('category'), isFalse);
      expect(BuildingDef.fromDefRow(row).category, isNull);
      expect(
        categoryOfBuilding(BuildingDef.fromDefRow(row)),
        BuildingCategory.housing,
      );
    });

    test('an unknown key reads as "derive it", never as a wrong drawer', () {
      final row = _def(population: 4).toDefRow();
      (row['metadata'] as Map)['category'] = 'no_such_category';
      expect(BuildingDef.fromDefRow(row).category, isNull);
      expect(
        categoryOfBuilding(BuildingDef.fromDefRow(row)),
        BuildingCategory.housing,
      );
    });
  });
}
