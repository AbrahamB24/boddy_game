import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

/// Why roads were undeletable, pinned so it can't come back.
///
/// Reported from a real run: "Strassen können aktuell nicht gelöscht werden".
/// The cause was not the delete path — it was the HOUSING guard in
/// `SettlementController.deleteBuilding`, which refuses any demolition that
/// drops housing capacity below the number of creatures you own. Capacity only
/// counts road-CONNECTED buildings, so pulling out almost any road disconnects
/// a hut and collapses capacity — and the guard then refused, silently,
/// because the caller dropped the returned error.
///
/// These tests demonstrate the mechanism (a road carries capacity) so the
/// exemption in deleteBuilding reads as deliberate rather than sloppy.
PlacedBuilding _b(String id, String type, int x, int y) => PlacedBuilding(
  id: id,
  settlementId: 's',
  buildingTypeId: type,
  gridX: x,
  gridY: y,
  constructionSecondsRequired: 0,
  constructionSecondsBuilt: 0,
  isComplete: true,
  placedAt: DateTime(2026),
  level: 1,
);

void main() {
  setUp(() {
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
  });

  test('a hut only shelters anyone while a road reaches the hall', () {
    // The hall is 5x5 at (0,0), so it fills x 0..4. One road cell at (5,0)
    // touches its edge, and the hut at (6,0) touches that road.
    final hall = _b('hall', 'castle', 0, 0);
    final road = _b('road1', 'road', 5, 0);
    final hut = _b('hut1', 'small_house', 6, 0);

    final connected = GameEngine.housingCapacity([hall, road, hut]);
    final severed = GameEngine.housingCapacity([hall, hut]);

    expect(
      connected,
      greaterThan(severed),
      reason: 'the road is what makes the hut count',
    );
  });

  test('THE trap: removing a road looks exactly like destroying housing', () {
    // This is the whole bug in one assertion. The guard compares capacity
    // before/after and cannot tell "you demolished a hut" from "you pulled up
    // a road and the hut is momentarily cut off" — so roads must be exempt,
    // because a road destroys nothing, it only disconnects, and the player is
    // mid-edit and about to reconnect it.
    final hall = _b('hall', 'castle', 0, 0);
    final road = _b('road1', 'road', 3, 0);
    final hut = _b('hut1', 'small_house', 4, 0);

    final withoutRoad = GameEngine.housingCapacity([hall, hut]);
    final withoutHut = GameEngine.housingCapacity([hall, road]);

    expect(withoutRoad, withoutHut);
  });

  test('the road def is flagged as a road — the exemption keys off this', () {
    expect(kBuildingDefs['road']!.isRoad, isTrue);
    expect(kBuildingDefs['small_house']!.isRoad, isFalse);
  });
}
