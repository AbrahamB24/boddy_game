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
      expect(_cells('small_house'), lessThan(_cells('small_wood_camp')));
      expect(_cells('small_house'), lessThan(_cells('small_stone_camp')));
      expect(_cells('large_house'), lessThan(_cells('large_stone_camp')));
      expect(_cells('large_house'), lessThan(_cells('castle')));
    });

    test('the upgrade of a worksite is bigger than the worksite', () {
      expect(_cells('large_wood_camp'), greaterThan(_cells('small_wood_camp')));
      expect(_cells('large_stone_camp'), greaterThan(_cells('small_stone_camp')));
    });

    test('only buildings that need no YARD take less ground than a dwelling',
        () {
      // ── This rule was "the hut is the smallest building" (2026-08-09) ──
      // It stopped being true when footprints stopped being fixed and the
      // The Small House grew to 3 × 3 to hold a den, a fungus and a nest. What
      // was really guarding is still guarded: an earlier pass flattened nearly
      // everything to 2 × 2 to fit a cramped plot, and the map read as a
      // village of identical sheds.
      //
      // So the invariant is now about WHY something is small. A watchtower is
      // four legs and the air between them; a store is a box. Neither has
      // anything to stand outside it, and a dwelling does. Anything else this
      // small is the old flattening coming back.
      //
      // The Gold Vault LEFT this set on 2026-08-12: at 2 x 3 it was a
      // strongbox you cannot walk round, and the user gave it 3 x 3 so the
      // chain, the padlock and the hoard have a yard to be guarded in. That
      // is a building with something outside it, so it belongs with the
      // dwellings rather than with the boxes.
      final smaller = kFallbackBuildingDefs.values
          .where((d) => d.gridW * d.gridH < _cells('small_house'))
          .map((d) => d.id)
          .toSet();
      expect(smaller, {'road', 'scout_post', 'warehouse', 'smokehouse'});
      expect(_cells('road'), lessThan(_cells('small_house')));
    });

    test('the Castle is the landmark — nothing outgrows it', () {
      // The 2026-07-24 roster caps every footprint at the hall's 5×5 (the Grand
      // Works ties it, nothing exceeds it).
      final bigger = kFallbackBuildingDefs.values
          .where((d) => d.gridW * d.gridH > _cells('castle'))
          .map((d) => d.id)
          .toList();
      expect(bigger, isEmpty);
    });

    test('the longhouse is long, not just large', () {
      final d = kFallbackBuildingDefs['large_house']!;
      expect(d.gridH, greaterThanOrEqualTo(d.gridW * 2));
    });
  });

  group('starting plot', () {
    test('the Castle is centred in it and fully inside', () {
      final hall = kFallbackBuildingDefs['castle']!;
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
      final core = _cells('castle') +
          _cells('small_house') +
          _cells('small_wood_camp') +
          _cells('small_stone_camp') +
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
