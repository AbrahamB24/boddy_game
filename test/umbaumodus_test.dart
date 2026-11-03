import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

/// Umbaumodus (user 2026-09-22): "ich kann alle Gebäude 'zurücknehmen' und
/// dann einzeln frei platzieren. Ich kann aber auch Gebäude verschieben wie
/// bis anhin. […] wenn ich es schliesse, bevor ich fertig bin, dann soll
/// einfach alles rückgängig gemacht werden." — the FoE-style rearrange
/// tool, built on one new flag, [PlacedBuilding.isStored], and one snapshot,
/// [SettlementController.hasRecallInProgress].
///
/// These pin serialization, the spatial rules (a stored building must never
/// block a spot or catch a hit-test), the effect rules (a stored building's
/// housing/production pause exactly the way an unconnected one's already
/// do) — and the recall/cancel round trip itself, through [run]: no test in
/// this suite otherwise calls a Supabase-backed controller method without a
/// live/mocked client, since `SettlementController._svc` reaches a real
/// `supabase.from(...)` that asserts without `Supabase.initialize`. Each of
/// [SettlementController.recallAllBuildings]/[SettlementController
/// .moveBuilding]/[SettlementController.cancelRecall] mutates its LOCAL
/// state and calls `notifyListeners()` BEFORE its one `await` on that
/// network call — a Dart `async` function runs synchronously up to its
/// first `await` — so the state under test is already settled by the time
/// [run] swallows that expected failure.
Future<void> run(Future<void> Function() f) async {
  try {
    await f();
  } catch (_) {
    // The expected "Supabase not initialized" failure — see the doc comment
    // above. By this point the local state it guards has already landed.
  }
}

PlacedBuilding _b(
  String id,
  String type,
  int x,
  int y, {
  bool isStored = false,
}) => PlacedBuilding(
  id: id,
  settlementId: 's',
  buildingTypeId: type,
  gridX: x,
  gridY: y,
  level: 1,
  constructionSecondsRequired: 0,
  constructionSecondsBuilt: 0,
  isComplete: true,
  isStored: isStored,
  placedAt: DateTime(2026),
);

/// The road that connects a Small House at (8,10) below the 10x10 hall: its
/// ENTRANCE (user 2026-11-03) is the east side's southern cell, so the road
/// runs from (10,9) — touching the hall's edge — down to (10,11), in front
/// of that cell.
List<PlacedBuilding> _entranceRoads() => [
  _b('road1', 'road', 10, 9),
  _b('road2', 'road', 10, 10),
  _b('road3', 'road', 10, 11),
];

void main() {
  setUp(() {
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
  });

  // toMap() has no 'placed_at' key (the DB column defaults it on insert), so
  // a round-trip through fromMap needs it added back — this is a property of
  // the model that predates isStored, not something these tests are pinning.
  Map<String, dynamic> row(PlacedBuilding b) =>
      b.toMap()..['placed_at'] = b.placedAt.toIso8601String();

  group('PlacedBuilding.isStored', () {
    test('round-trips through toMap/fromMap', () {
      final stored = _b('a', 'small_house', 5, 5, isStored: true);
      expect(PlacedBuilding.fromMap(row(stored)).isStored, isTrue);
      final placed = _b('b', 'small_house', 6, 6);
      expect(PlacedBuilding.fromMap(row(placed)).isStored, isFalse);
    });

    test('a pre-migration row with no column reads as NOT stored', () {
      final noColumn = row(_b('a', 'small_house', 5, 5))..remove('is_stored');
      expect(PlacedBuilding.fromMap(noColumn).isStored, isFalse);
    });

    test('copyWith can set AND clear the flag', () {
      final placed = _b('a', 'small_house', 5, 5);
      final stored = placed.copyWith(isStored: true);
      expect(stored.isStored, isTrue);
      expect(stored.copyWith(isStored: false).isStored, isFalse);
      // Omitting it entirely keeps whatever it already was.
      expect(stored.copyWith(gridX: 9).isStored, isTrue);
    });
  });

  group('GameEngine — a stored building has no effects', () {
    // Same shape as road_deletion_test.dart's own housing pair: hall at
    // (0,0) is 10x10, so a road/hut sitting right past its edge is a clean
    // "connected" case to take away from.
    test('housing capacity drops exactly like disconnecting it would', () {
      final hall = _b('hall', 'castle', 0, 0);
      final roads = _entranceRoads();
      final hut = _b('hut1', 'small_house', 8, 10);

      final standing = GameEngine.housingCapacity([hall, ...roads, hut]);
      final stored = GameEngine.housingCapacity([
        hall,
        ...roads,
        hut.copyWith(isStored: true),
      ]);
      final removed = GameEngine.housingCapacity([hall, ...roads]);

      expect(stored, lessThan(standing));
      expect(
        stored,
        removed,
        reason: 'stored counts for nothing, same as not being there at all',
      );
    });

    test('connectedBuildingIds excludes it even sitting on a real road', () {
      final hall = _b('hall', 'castle', 0, 0);
      final road = _b('road1', 'road', 10, 0);
      final hut = _b('hut1', 'small_house', 11, 0, isStored: true);
      final connected = GameEngine.connectedBuildingIds([hall, road, hut]);
      expect(connected, isNot(contains('hut1')));
    });
  });

  group('SettlementController.recallableBuildings', () {
    late SettlementController ctrl;
    setUp(() {
      ctrl = SettlementController();
      ctrl.buildings = [];
    });
    tearDown(() => ctrl.buildings = []);

    test('offers ordinary buildings, never the Castle, plots or roads', () {
      final plot = kBuildingDefs.values.firstWhere((d) => d.isBuildPlot).id;
      ctrl.buildings = [
        _b('hall', 'castle', 0, 0),
        _b('road1', 'road', 10, 0),
        _b('plot1', plot, 20, 0),
        _b('hut1', 'small_house', 11, 0),
      ];
      final ids = ctrl.recallableBuildings.map((b) => b.id).toSet();
      expect(ids, {'hut1'});
    });

    test('a building already in the tray is not offered again', () {
      ctrl.buildings = [
        _b('hall', 'castle', 0, 0),
        _b('hut1', 'small_house', 11, 0, isStored: true),
        _b('hut2', 'small_house', 15, 0),
      ];
      expect(
        ctrl.recallableBuildings.map((b) => b.id).toSet(),
        {'hut2'},
      );
    });

    test('recallableRoads offers only roads, none already stored', () {
      ctrl.buildings = [
        _b('hall', 'castle', 0, 0),
        _b('hut1', 'small_house', 11, 0),
        _b('road1', 'road', 10, 0),
        _b('road2', 'road', 10, 1, isStored: true),
      ];
      expect(ctrl.recallableRoads.map((b) => b.id).toSet(), {'road1'});
    });

    test('storedBuildings / hasStoredBuildings read the tray', () {
      expect(ctrl.hasStoredBuildings, isFalse);
      ctrl.buildings = [
        _b('hall', 'castle', 0, 0),
        _b('hut1', 'small_house', 11, 0, isStored: true),
      ];
      expect(ctrl.hasStoredBuildings, isTrue);
      expect(ctrl.storedBuildings.map((b) => b.id), ['hut1']);
    });
  });

  group('SettlementController — a stored footprint never blocks a spot', () {
    late SettlementController ctrl;
    setUp(() {
      ctrl = SettlementController();
      ctrl.buildings = [];
    });
    tearDown(() => ctrl.buildings = []);

    // Inside the starting plot (kInitialPlotX/Y 20,10, size 20) — buildable
    // unconditionally, so isPlacementValid's answer here is ONLY about
    // occupancy, the thing isStored is supposed to change.
    test('isAreaFree ignores a stored building sitting right there', () {
      ctrl.buildings = [_b('hut1', 'small_house', 25, 15, isStored: true)];
      // The same cells the stored hut's stale gridX/gridY still claim.
      expect(ctrl.isAreaFree(25, 15, 2, 2), isTrue);
    });

    test('a NEW building can be placed on a stored one\'s old spot', () {
      ctrl.buildings = [_b('hut1', 'small_house', 25, 15, isStored: true)];
      expect(ctrl.isPlacementValid('small_house', 25, 15), isTrue);
    });

    test('while STANDING, the same building DOES block that spot', () {
      // Control: proves the stored-only exemption above is really about
      // isStored, not some other quirk of this fixture.
      ctrl.buildings = [_b('hut1', 'small_house', 25, 15)];
      expect(ctrl.isPlacementValid('small_house', 25, 15), isFalse);
    });
  });

  group('SettlementController.connectedBuildingIds — cache follows isStored', () {
    late SettlementController ctrl;
    setUp(() {
      ctrl = SettlementController();
      ctrl.buildings = [];
    });
    tearDown(() => ctrl.buildings = []);

    test('recalling a building (new list, same layout) still busts the cache', () {
      final hall = _b('hall', 'castle', 0, 0);
      final roads = _entranceRoads();
      final hut = _b('hut1', 'small_house', 8, 10);
      ctrl.buildings = [hall, ...roads, hut];
      expect(ctrl.connectedBuildingIds, contains('hut1'));

      // A fresh list — same ids, same gridX/gridY — with just the flag
      // flipped, the way recallAllBuildings itself builds one.
      ctrl.buildings = [hall, ...roads, hut.copyWith(isStored: true)];
      expect(
        ctrl.connectedBuildingIds,
        isNot(contains('hut1')),
        reason: 'a stale cache would still say yes — gridX/gridY did not move',
      );
    });
  });

  group('recallAllBuildings / moveBuilding / cancelRecall — the real round trip', () {
    late SettlementController ctrl;
    setUp(() {
      ctrl = SettlementController();
      ctrl.buildings = [];
    });
    tearDown(() async {
      // Drop whatever [run] left mid-flight before the next test's setUp.
      await run(ctrl.cancelRecall);
      ctrl.buildings = [];
    });

    test('recallAllBuildings stores the eligible ones and starts a snapshot', () async {
      ctrl.buildings = [
        _b('hall', 'castle', 0, 0),
        _b('hut1', 'small_house', 25, 15),
        _b('hut2', 'small_house', 30, 15),
      ];
      expect(ctrl.hasRecallInProgress, isFalse);

      await run(ctrl.recallAllBuildings);

      expect(ctrl.hasRecallInProgress, isTrue);
      expect(ctrl.storedBuildings.map((b) => b.id).toSet(), {'hut1', 'hut2'});
      final hall = ctrl.buildings.firstWhere((b) => b.id == 'hall');
      expect(hall.isStored, isFalse, reason: 'the Castle is never recallable');
    });

    test('placing the LAST tray item ends the snapshot — nothing left to cancel', () async {
      ctrl.buildings = [_b('hut1', 'small_house', 25, 15)];
      await run(ctrl.recallAllBuildings);
      expect(ctrl.hasRecallInProgress, isTrue);

      await run(() => ctrl.moveBuilding('hut1', 26, 16));

      expect(ctrl.hasRecallInProgress, isFalse);
      expect(ctrl.hasStoredBuildings, isFalse);
      final hut = ctrl.buildings.single;
      expect((hut.gridX, hut.gridY), (26, 16));
      expect(hut.isStored, isFalse);
    });

    test(
      'closing early reverts EVERYTHING this visit touched — placed or still in the tray',
      () async {
        ctrl.buildings = [
          _b('hut1', 'small_house', 25, 15),
          _b('hut2', 'small_house', 30, 15),
        ];
        await run(ctrl.recallAllBuildings);
        // Finish placing hut1 somewhere new — a real, committed-looking move —
        // while hut2 is still waiting in the tray.
        await run(() => ctrl.moveBuilding('hut1', 26, 16));
        expect(ctrl.hasStoredBuildings, isTrue, reason: 'hut2 is still in the tray');
        expect(ctrl.hasRecallInProgress, isTrue, reason: 'the visit is not finished');

        await run(ctrl.cancelRecall);

        expect(ctrl.hasRecallInProgress, isFalse);
        expect(ctrl.hasStoredBuildings, isFalse);
        final hut1 = ctrl.buildings.firstWhere((b) => b.id == 'hut1');
        final hut2 = ctrl.buildings.firstWhere((b) => b.id == 'hut2');
        expect(
          (hut1.gridX, hut1.gridY),
          (25, 15),
          reason: 'reverted even though it was already placed this visit',
        );
        expect((hut2.gridX, hut2.gridY), (30, 15));
        expect(hut1.isStored, isFalse);
        expect(hut2.isStored, isFalse);
      },
    );

    test('a second recall keeps the FIRST origin, not the one it was just moved to', () async {
      ctrl.buildings = [_b('hut1', 'small_house', 25, 15)];
      await run(ctrl.recallAllBuildings);
      await run(() => ctrl.moveBuilding('hut1', 26, 16));
      expect(ctrl.hasRecallInProgress, isFalse, reason: 'that finished the visit');

      // A brand-new visit: recalling it again must remember 26,16 as ITS
      // origin now, not the original 25,15 from before.
      await run(ctrl.recallAllBuildings);
      await run(ctrl.cancelRecall);

      final hut1 = ctrl.buildings.single;
      expect((hut1.gridX, hut1.gridY), (26, 16));
    });

    test('cancelRecall with nothing recalled is a harmless no-op', () async {
      ctrl.buildings = [_b('hut1', 'small_house', 25, 15)];
      await run(ctrl.cancelRecall);
      final hut1 = ctrl.buildings.single;
      expect((hut1.gridX, hut1.gridY), (25, 15));
      expect(hut1.isStored, isFalse);
    });

    test(
      'recallAllRoads shares the same tray/snapshot as recallAllBuildings',
      () async {
        // user 2026-09-22: "es braucht auch noch einen Button, um alle
        // Strassen aufzuheben" — its own button, but one Umbaumodus visit.
        ctrl.buildings = [
          _b('hut1', 'small_house', 25, 15),
          _b('road1', 'road', 10, 0),
        ];
        await run(ctrl.recallAllBuildings);
        await run(ctrl.recallAllRoads);

        expect(
          ctrl.storedBuildings.map((b) => b.id).toSet(),
          {'hut1', 'road1'},
          reason: 'both tools feed the SAME tray',
        );
        expect(ctrl.hasRecallInProgress, isTrue);

        // Closing early undoes both together, not just the road.
        await run(ctrl.cancelRecall);
        expect(ctrl.hasStoredBuildings, isFalse);
        final hut1 = ctrl.buildings.firstWhere((b) => b.id == 'hut1');
        final road1 = ctrl.buildings.firstWhere((b) => b.id == 'road1');
        expect((hut1.gridX, hut1.gridY), (25, 15));
        expect((road1.gridX, road1.gridY), (10, 0));
      },
    );
  });
}
