import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/building_model.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

/// Turning buildings by 90° (user 2026-11-03).
PlacedBuilding _b(String id, String type, int x, int y, {int rotation = 0}) =>
    PlacedBuilding(
      id: id,
      settlementId: 's',
      buildingTypeId: type,
      gridX: x,
      gridY: y,
      level: 1,
      constructionSecondsRequired: 0,
      constructionSecondsBuilt: 0,
      isComplete: true,
      rotation: rotation,
      placedAt: DateTime.utc(2026),
    );

void main() {
  setUp(() {
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
  });
  tearDown(kBuildingDefs.clear);

  test('an odd turn swaps the footprint, an even one does not', () {
    final base = kBuildingDefs['hatchery']!;
    expect((base.gridW, base.gridH), (4, 3));
    for (final r in [1, 3]) {
      final d = defRotated('hatchery', r)!;
      expect((d.gridW, d.gridH), (3, 4), reason: 'turn $r');
      expect(d.artId, 'hatchery_r$r');
    }
    final d2 = defRotated('hatchery', 2)!;
    expect((d2.gridW, d2.gridH), (4, 3));
    expect(defRotated('hatchery', 4), same(base), reason: 'a full turn is none');
  });

  test('every turn of a turnable building ships its picture and tables', () {
    for (final id in ['small_house', 'hatchery']) {
      expect(kBuildingDefs[id]!.canRotate, isTrue, reason: id);
      for (var r = 1; r < 4; r++) {
        final d = defRotated(id, r)!;
        expect(kModelFootprint[d.artId], (d.gridW, d.gridH), reason: d.artId);
        expect(kBuildingEntrance[d.artId], isNotNull, reason: d.artId);
      }
    }
  });

  test('a building without turned pictures cannot turn', () {
    final old = kBuildingDefs['warehouse']!;
    expect(old.canRotate, isFalse);
    expect(defRotated('warehouse', 1), same(old));
  });

  test('the entrance turns with the building', () {
    // Small House at (8,10) below the 10x10 hall, turned once: its entrance
    // now faces the map's lower-left edge.
    const hx = 8, hy = 10;
    final turned = defRotated('small_house', 1)!;
    final e = entrancesFor(turned.artId, turned.gridW, turned.gridH)!.single;
    final (rx, ry) = entranceRoadCell(e, hx, hy);
    final hall = _b('hall', 'castle', 0, 0);
    final hut = _b('hut', 'small_house', hx, hy, rotation: 1);
    // Around the house: down from the hall's corner at x = 10, then along
    // the row of the road cell to it.
    expect((rx, ry), (8, 12));
    final roads = [
      for (var y = 4; y <= ry; y++) _b('a$y', 'road', 10, y),
      for (var x = rx; x < 10; x++) _b('b$x', 'road', x, ry),
    ];
    expect(
      GameEngine.connectedBuildingIds([hall, hut, ...roads]),
      contains('hut'),
      reason: 'road cell ($rx,$ry)',
    );
    // The UNturned entrance's road cell no longer connects it.
    final e0 = kBuildingEntrance['small_house']!.single;
    final (ox, oy) = entranceRoadCell(e0, hx, hy);
    final wrong = [
      for (var y = 9; y <= oy; y++) _b('w$y', 'road', ox, y),
    ];
    expect(
      GameEngine.connectedBuildingIds([hall, hut, ...wrong]),
      isNot(contains('hut')),
    );
  });

  test('a turn survives a round trip through the database row', () {
    final row = {
      'id': 'x',
      'settlement_id': 's',
      'building_type_id': 'hatchery',
      'grid_x': 1,
      'grid_y': 2,
      'level': 1,
      'construction_seconds_required': 0,
      'construction_seconds_built': 0,
      'is_complete': true,
      'placed_at': '2026-11-03T00:00:00Z',
      'rotation': 3,
    };
    final b = PlacedBuilding.fromMap(row);
    expect(b.rotation, 3);
    expect(placedDefOf(b)!.artId, 'hatchery_r3');
    // A database without the column yet reads as unturned.
    expect(PlacedBuilding.fromMap(row..remove('rotation')).rotation, 0);
  });
}
