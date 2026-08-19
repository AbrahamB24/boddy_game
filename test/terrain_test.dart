import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/water_cells.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

// ── Das Spielfeld (user 2026-08-09) ──────────────────────────
// "Links oben soll das Meer sein mit Strand von welchem aus der Fluss von west
//  nach ost fliesst. Der Fluss ist nicht bebaubar."
//
// water_cells.dart is GENERATED — tool/blender/terrain.py writes it from the
// same classify() that draws the background — so what is worth pinning here is
// not the exact coastline (that is allowed to be retuned) but the things the
// map would be broken WITHOUT, and which a retune could silently take away:
//
//   * the sea is in the west, which is where it was asked for;
//   * the river reaches from there to the far east;
//   * neither can be built on;
//   * and the square the player starts in is dry.
//
// The last one is the one that would ruin a new game rather than merely look
// wrong, so it is stated twice — here and as a hard failure in the generator.
PlacedBuilding _plot(String id, int x, int y) => PlacedBuilding(
  id: id,
  settlementId: 's',
  buildingTypeId: 'building_plot',
  gridX: x,
  gridY: y,
  level: 1,
  constructionSecondsRequired: 0,
  constructionSecondsBuilt: 0,
  isComplete: true,
  placedAt: DateTime.utc(2026),
);

void main() {
  setUp(() {
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
  });

  group('where the water is', () {
    test('there is water at all, and not most of the map', () {
      var wet = 0;
      for (var y = 0; y < kGridRows; y++) {
        for (var x = 0; x < kGridCols; x++) {
          if (isWaterCell(x, y)) wet++;
        }
      }
      expect(wet, greaterThan(500), reason: 'no water — was it generated?');
      expect(wet, lessThan(kGridCols * kGridRows ~/ 3),
          reason: 'the map has drowned');
    });

    test('the sea is in the WEST — the map\'s upper-left edge', () {
      // iso_grid.dart: +x runs down-right, so the x = 0 edge is the one at the
      // top left of the picture. Counting by column is the only way to say
      // "left" about a diamond without hand-waving.
      var west = 0, east = 0;
      for (var y = 0; y < kGridRows; y++) {
        for (var x = 0; x < 10; x++) {
          if (isWaterCell(x, y)) west++;
        }
        for (var x = kGridCols - 10; x < kGridCols; x++) {
          if (isWaterCell(x, y)) east++;
        }
      }
      expect(west, greaterThan(kGridRows), reason: 'no sea along the west rim');
      expect(west, greaterThan(east * 4),
          reason: 'the sea is not where it was asked for');
    });

    test('the river runs from the sea all the way east', () {
      // Water in every tenth of the map's width: a river that stops halfway is
      // a river that leaves half the map without one.
      for (var band = 0; band < 10; band++) {
        final from = kGridCols * band ~/ 10;
        final to = kGridCols * (band + 1) ~/ 10;
        final any = [
          for (var y = 0; y < kGridRows; y++)
            for (var x = from; x < to; x++)
              if (isWaterCell(x, y)) 1,
        ];
        expect(any, isNotEmpty, reason: 'no water in columns $from..$to');
      }
    });

    test('off the map is not water', () {
      // Callers range-check already; answering "water" for a cell that does
      // not exist would turn every out-of-bounds bug into a silent placement
      // refusal instead of something anyone notices.
      expect(isWaterCell(-1, 5), isFalse);
      expect(isWaterCell(5, -1), isFalse);
      expect(isWaterCell(kGridCols + 50, 5), isFalse);
      expect(isWaterCell(5, kGridRows + 50), isFalse);
    });
  });

  group('what you may build on', () {
    test('the starting plot is DRY, every cell of it', () {
      final wet = [
        for (var y = kInitialPlotY; y < kInitialPlotY + kInitialPlotSize; y++)
          for (var x = kInitialPlotX; x < kInitialPlotX + kInitialPlotSize; x++)
            if (isWaterCell(x, y)) (x, y),
      ];
      expect(wet, isEmpty,
          reason: 'a river through the square handed to a new player');
    });

    test('the starting region is the plot MINUS nothing, since it is dry', () {
      final region = GameEngine.buildableRegionCells(const []);
      expect(region, hasLength(kInitialPlotSize * kInitialPlotSize));
    });

    test('a Building Plot laid over water claims only the banks', () {
      // Find a plot-sized square that straddles the river.
      final def = kFallbackBuildingDefs['building_plot']!;
      (int, int)? straddling;
      for (var y = 0; y + def.gridH < kGridRows && straddling == null; y += 5) {
        for (var x = 0; x + def.gridW < kGridCols; x += 5) {
          var wet = 0, dry = 0;
          for (var dy = 0; dy < def.gridH; dy++) {
            for (var dx = 0; dx < def.gridW; dx++) {
              isWaterCell(x + dx, y + dy) ? wet++ : dry++;
            }
          }
          if (wet > 2 && dry > 2) {
            straddling = (x, y);
            break;
          }
        }
      }
      expect(straddling, isNotNull, reason: 'no plot-sized square meets water');

      final (px, py) = straddling!;
      final region = GameEngine.buildableRegionCells([_plot('p', px, py)]);
      var claimedWet = 0, claimedDry = 0;
      for (var dy = 0; dy < def.gridH; dy++) {
        for (var dx = 0; dx < def.gridW; dx++) {
          final key = (py + dy) * kGridCols + px + dx;
          if (!region.contains(key)) continue;
          isWaterCell(px + dx, py + dy) ? claimedWet++ : claimedDry++;
        }
      }
      expect(claimedWet, 0, reason: 'the plot claimed the river itself');
      expect(claimedDry, greaterThan(0), reason: 'the plot claimed nothing');
    });

    test('no cell anywhere is both buildable and water', () {
      // The property, stated once over the whole map rather than per case:
      // whatever grants territory, water is subtracted afterwards.
      final plots = [
        for (var i = 0; i < 6; i++) _plot('p$i', 10 + i * 25, 40 + (i % 3) * 20),
      ];
      final region = GameEngine.buildableRegionCells(plots);
      final wet = region
          .where((k) => isWaterCell(k % kGridCols, k ~/ kGridCols))
          .toList();
      expect(wet, isEmpty);
    });

    test('and the river actually refuses a building', () {
      // The end-to-end version: find a river cell and ask the placement rule.
      int? rx, ry;
      for (var y = 0; y < kGridRows && rx == null; y++) {
        for (var x = 0; x < kGridCols; x++) {
          if (isWaterCell(x, y)) {
            rx = x;
            ry = y;
            break;
          }
        }
      }
      expect(GameEngine.isAreaBuildable(rx!, ry!, 1, 1, const []), isFalse);
    });
  });
}
