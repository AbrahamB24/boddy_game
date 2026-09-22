import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// ── The ghost's name tag says WHY a spot is refused (user 2026-09-19) ──────
// placementProblem only NAMES the first rule isPlacementValid fails, so the two
// must never disagree: a spot the game accepts has no problem, and every spot it
// refuses has one. The tag prints the words — except for an overlap, whose red
// footprint speaks for itself.
void main() {
  PlacedBuilding placed(String id, String type, int x, int y) => PlacedBuilding(
    id: id,
    settlementId: 's',
    buildingTypeId: type,
    gridX: x,
    gridY: y,
    level: 1,
    constructionSecondsRequired: 0,
    constructionSecondsBuilt: 0,
    isComplete: true,
    placedAt: DateTime.utc(2026),
  );

  late SettlementController ctrl;

  setUp(() {
    ctrl = SettlementController();
    ctrl.buildings = [];
  });

  tearDown(() => ctrl.buildings = []);

  test('a spot the game accepts has no problem', () {
    final spot = ctrl.firstFreeSpotFor('small_house')!;
    expect(ctrl.isPlacementValid('small_house', spot.$1, spot.$2), isTrue);
    expect(ctrl.placementProblem('small_house', spot.$1, spot.$2), isNull);
  });

  test('standing on another building is an overlap, with no words', () {
    final spot = ctrl.firstFreeSpotFor('small_house')!;
    ctrl.buildings = [placed('a', 'small_house', spot.$1, spot.$2)];
    expect(ctrl.isPlacementValid('small_house', spot.$1, spot.$2), isFalse);
    final problem = ctrl.placementProblem('small_house', spot.$1, spot.$2);
    expect(problem, PlacementProblem.overlap);
    expect(problem!.label, isNull);
  });

  test('a building being MOVED does not overlap itself', () {
    final spot = ctrl.firstFreeSpotFor('small_house')!;
    ctrl.buildings = [placed('a', 'small_house', spot.$1, spot.$2)];
    expect(
      ctrl.placementProblem(
        'small_house',
        spot.$1,
        spot.$2,
        excludeId: 'a',
      ),
      isNull,
    );
  });

  test('off the map, and outside your land, are told apart — in words', () {
    final offMap = ctrl.placementProblem('small_house', kGridCols, 0);
    expect(offMap, PlacementProblem.offMap);
    expect(offMap!.label, 'Outside the map');
    // Inside the map, but far from the starting plot.
    final far = ctrl.placementProblem(
      'small_house',
      kGridCols - 10,
      kGridRows - 10,
    );
    expect(far, PlacementProblem.outsideLand);
    expect(far!.label, 'Outside your land');
  });
}
