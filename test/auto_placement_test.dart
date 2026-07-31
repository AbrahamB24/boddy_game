import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// ── Building puts it ON THE MAP (user 2026-07-30) ────────────
// "wenn ich beim app ein gebäude baue, soll dies einfach auf die map kommen,
// damit ich es dann verschieben kann. Aktuell muss ich einen punkt auswählen, um
// es direkt zu bauen, ich will es aber schieben können."
//
// So the purchase needs a spot of its own, and the spot has to be one the game
// would have accepted from the player — otherwise "it just appears" becomes "it
// appears somewhere illegal and then refuses to work".
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

  test('an empty settlement has room, and the spot is a LEGAL one', () {
    final spot = ctrl.firstFreeSpotFor('hut');
    expect(spot, isNotNull);
    // The one rule that matters: the game would have accepted this from a tap.
    expect(ctrl.isPlacementValid('hut', spot!.$1, spot.$2), isTrue);
  });

  test('the spot lands NEAR THE HALL, not in whichever corner scans first', () {
    // It has to appear where the player is already looking — a building dropped
    // in the far corner of the plot reads as "nothing happened".
    final hallDef = kFallbackBuildingDefs.values.firstWhere((d) => d.isMainBuilding);
    ctrl.buildings = [placed('h', hallDef.id, kInitialPlotX + 8, kInitialPlotY + 8)];
    final spot = ctrl.firstFreeSpotFor('hut')!;
    final hutDef = kFallbackBuildingDefs['hut']!;
    final dx = (spot.$1 + hutDef.gridW / 2) - (kInitialPlotX + 8 + hallDef.gridW / 2);
    final dy = (spot.$2 + hutDef.gridH / 2) - (kInitialPlotY + 8 + hallDef.gridH / 2);
    // Adjacent-ish: within a couple of cells of the hall's footprint, not the
    // 20+ cells the plot is wide.
    expect(dx.abs(), lessThan(6), reason: 'dx=$dx');
    expect(dy.abs(), lessThan(6), reason: 'dy=$dy');
  });

  test('it does not overlap what is already standing', () {
    final spot = ctrl.firstFreeSpotFor('hut')!;
    ctrl.buildings = [placed('a', 'hut', spot.$1, spot.$2)];
    final next = ctrl.firstFreeSpotFor('hut')!;
    expect(next, isNot(spot));
    expect(ctrl.isPlacementValid('hut', next.$1, next.$2), isTrue);
  });

  test('a FULL settlement answers null — which is a real answer', () {
    // Paved over: the screen turns this into "no free space — a Building Plot
    // makes room" instead of placing something on top of something else.
    ctrl.buildings = [
      for (var x = kInitialPlotX; x < kInitialPlotX + kInitialPlotSize; x++)
        for (var y = kInitialPlotY; y < kInitialPlotY + kInitialPlotSize; y++)
          placed('r_${x}_$y', 'road', x, y),
    ];
    expect(ctrl.firstFreeSpotFor('hut'), isNull);
  });

  test('a BUILD PLOT is not auto-placed — it has no spot inside the region', () {
    // A plot must go on NEW ground (placeBuilding refuses one inside the region)
    // and can never be moved afterwards, so the screen keeps asking the player
    // where it goes. This pins WHY: scanning the buildable region finds nothing
    // for it, so a caller that forgot the special case gets null, not a wrong
    // spot.
    final plot = kFallbackBuildingDefs.values.firstWhere((d) => d.isBuildPlot);
    expect(ctrl.firstFreeSpotFor(plot.id), isNull);
  });

  test('an unknown type asks for nothing', () {
    expect(ctrl.firstFreeSpotFor('not_a_building'), isNull);
  });
}
