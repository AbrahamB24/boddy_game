import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';

int _cells(String id) {
  final d = kFallbackBuildingDefs[id]!;
  return d.gridW * d.gridH;
}

void main() {
  setUp(() {
    // kMainHallStartX/Y read the LIVE map first; keep it seeded from the
    // fallbacks so these tests measure the shipped defs.
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
  });
  tearDown(kBuildingDefs.clear);

  // The footprint ladder (see the comment above kFallbackBuildingDefs). These
  // are the proportions themselves, not incidental numbers: an earlier pass
  // flattened nearly everything to 2x2 to fit a cramped plot, which read as a
  // village of identical sheds.
  group('footprint proportions', () {
    test('a dwelling is smaller than a worksite', () {
      expect(_cells('hut'), lessThan(_cells('wood_camp_e1')));
      expect(_cells('hut'), lessThan(_cells('stone_camp_e1')));
      expect(_cells('house'), lessThan(_cells('stone_works_e1')));
      expect(_cells('house'), lessThan(_cells('main_hall')));
    });

    test('the upgrade of a worksite is bigger than the worksite', () {
      expect(_cells('wood_works_e1'), greaterThan(_cells('wood_camp_e1')));
      expect(_cells('stone_works_e1'), greaterThan(_cells('stone_camp_e1')));
    });

    test('a hut is the smallest real building; only the road is smaller', () {
      final smallest = kFallbackBuildingDefs.values
          .where((d) => !d.isRoad)
          .map((d) => d.gridW * d.gridH)
          .reduce((a, b) => a < b ? a : b);
      expect(_cells('hut'), smallest);
      expect(_cells('road'), lessThan(_cells('hut')));
    });

    test('the Tribal Center is the landmark — nothing outgrows it', () {
      // The 2026-07-24 roster caps every footprint at the hall's 5×5 (the Grand
      // Works ties it, nothing exceeds it).
      final bigger = kFallbackBuildingDefs.values
          .where((d) => d.gridW * d.gridH > _cells('main_hall'))
          .map((d) => d.id)
          .toList();
      expect(bigger, isEmpty);
    });

    test('the longhouse is long, not just large', () {
      final d = kFallbackBuildingDefs['house']!;
      expect(d.gridH, greaterThanOrEqualTo(d.gridW * 2));
    });
  });

  group('starting plot', () {
    test('the Tribal Center is centred in it and fully inside', () {
      final hall = kFallbackBuildingDefs['main_hall']!;
      final leftGap = kMainHallStartX - kInitialPlotX;
      final rightGap =
          (kInitialPlotX + kInitialPlotSize) - (kMainHallStartX + hall.gridW);
      final topGap = kMainHallStartY - kInitialPlotY;
      final bottomGap =
          (kInitialPlotY + kInitialPlotSize) - (kMainHallStartY + hall.gridH);

      // Off by at most one cell, not exactly equal: centring is integer maths,
      // and an odd leftover (plot 10 − hall 5 = 5) can only split 2/3. What
      // this guards is the real failure — the hall drifting to a corner or
      // hanging out of the plot, which is what the old hardcoded `- 3` did.
      expect((leftGap - rightGap).abs(), lessThanOrEqualTo(1));
      expect((topGap - bottomGap).abs(), lessThanOrEqualTo(1));

      expect(leftGap, greaterThanOrEqualTo(0));
      expect(topGap, greaterThanOrEqualTo(0));
      expect(rightGap, greaterThanOrEqualTo(0));
      expect(bottomGap, greaterThanOrEqualTo(0));
    });

    test('it sits on the map, not off the edge', () {
      expect(kInitialPlotX, greaterThanOrEqualTo(0));
      expect(kInitialPlotY, greaterThanOrEqualTo(0));
      expect(kInitialPlotX + kInitialPlotSize, lessThanOrEqualTo(kGridCols));
      expect(kInitialPlotY + kInitialPlotSize, lessThanOrEqualTo(kGridRows));
    });

    test('the era-I core fits, with room left for the roads it needs', () {
      // Buildings are only functional while road-connected (GameEngine
      // .functional), so a plot that fits the footprints exactly fits nothing.
      const plot = kInitialPlotSize * kInitialPlotSize;
      final core = _cells('main_hall') +
          _cells('hut') +
          _cells('wood_camp_e1') +
          _cells('stone_camp_e1') +
          _cells('healing_hut');
      expect(core, lessThan(plot));
      expect(
        plot - core,
        greaterThan(plot * 0.25),
        reason: 'less than a quarter of the plot left over is not enough '
            'for roads and breathing room',
      );
    });

    test('the plot is still a small share of the map — expansion has room', () {
      // Since the 4× enlargement (user request 2026-07-17) the era-I roster
      // fits the starting plot; what keeps Expansion/Building Plots alive as
      // content is that the plot remains a small fraction of the full grid,
      // so there is real territory left to claim.
      const plot = kInitialPlotSize * kInitialPlotSize;
      const grid = kGridCols * kGridRows;
      expect(
        plot,
        lessThanOrEqualTo(grid ~/ 4),
        reason: 'if the start covers most of the map, Expansion and Building '
            'Plots are dead content',
      );
    });

    test('every building can physically fit the starting plot', () {
      // Not about affording it — a footprint wider than the plot could never
      // be placed at all before Expansion, which would silently soft-lock it.
      for (final d in kFallbackBuildingDefs.values) {
        expect(d.gridW, lessThanOrEqualTo(kInitialPlotSize), reason: d.id);
        expect(d.gridH, lessThanOrEqualTo(kInitialPlotSize), reason: d.id);
      }
    });
  });
}
