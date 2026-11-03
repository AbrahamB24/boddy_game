import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/building_model.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

/// What the Blender models say about a building beyond its picture — its
/// ENTRANCE and its moving parts (user 2026-11-03). Both tables are written
/// by tool/blender/make_building.py; these tests hold them to the rules the
/// map relies on.
/// The def a PICTURE id belongs to (`<id>` or a turn `<id>_r1`..`_r3`).
BuildingDef? _artDef(String artId) {
  final m = RegExp(r'^(.*)_r([1-3])$').firstMatch(artId);
  return m == null
      ? kFallbackBuildingDefs[artId]
      : kFallbackBuildingDefs[m[1]]?.rotated(int.parse(m[2]!));
}

PlacedBuilding _b(String id, String type, int x, int y) => PlacedBuilding(
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

void main() {
  setUp(() {
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
  });

  group('kBuildingEntrance', () {
    test('every entrance is a footprint cell on the edge, facing out', () {
      for (final MapEntry(key: id, value: es) in kBuildingEntrance.entries) {
        for (final e in es) {
        final maybe = _artDef(id);
        expect(maybe, isNotNull, reason: '$id has an entrance but no def');
        final def = maybe!;
        final (cx, cy, dx, dy) = e;
        expect(cx >= 0 && cx < def.gridW && cy >= 0 && cy < def.gridH, isTrue,
            reason: '$id: entrance cell ($cx,$cy) is off its footprint');
        expect(dx.abs() + dy.abs(), 1, reason: '$id: one step, no diagonal');
        final (ox, oy) = (cx + dx, cy + dy);
        expect(
          ox < 0 || oy < 0 || ox >= def.gridW || oy >= def.gridH,
          isTrue,
          reason: '$id: the road cell would lie INSIDE the building',
        );
        }
      }
    });

    test('only a road in front of the entrance connects the building', () {
      final e = kBuildingEntrance['small_house']?.single;
      expect(e, isNotNull);
      // The 10x10 hall at (0,0); the house below it at (8,10). Its road
      // cell, then a run up the hall's east side to touch the hall.
      const hx = 8, hy = 10;
      final (rx, ry) = entranceRoadCell(e!, hx, hy);
      final hall = _b('hall', 'castle', 0, 0);
      final hut = _b('hut', 'small_house', hx, hy);
      final toEntrance = [
        for (var y = 4; y <= ry; y++) _b('r$y', 'road', rx, y),
      ];
      expect(
        GameEngine.connectedBuildingIds([hall, hut, ...toEntrance]),
        contains('hut'),
      );
      // A road along the house's WEST side, touching the hall too: the old
      // any-side rule would have counted it; the entrance rule does not.
      final pastTheBack = [
        for (var y = 10; y <= hy + 1; y++) _b('w$y', 'road', hx - 1, y),
      ];
      expect(
        GameEngine.connectedBuildingIds([hall, hut, ...pastTheBack]),
        isNot(contains('hut')),
      );
    });
  });

  group('the Castle\'s gates (user 2026-11-03: "mehrere Tore")', () {
    test('it has a gate on every side, the south one where the intro '
        'lays its road', () {
      final gates = kBuildingEntrance['castle']!;
      expect(gates, hasLength(4));
      expect({for (final (_, _, dx, dy) in gates) (dx, dy)},
          {(0, 1), (1, 0), (0, -1), (-1, 0)});
      final hall = kFallbackBuildingDefs['castle']!;
      expect(
        gates.map((e) => entranceRoadCell(e, 0, 0)),
        contains((hall.gridW ~/ 2, hall.gridH)),
        reason: 'kTutorialRoadX/Y is the Castle\'s x + w/2, just below it',
      );
    });

    test('the road network starts in front of a gate, not anywhere on the '
        'wall', () {
      final hall = _b('hall', 'castle', 0, 0);
      // A Large House (no model of its own yet: any-side rule) beside a
      // single road cell below the Castle's south wall.
      final atGate = [_b('r', 'road', 5, 10), _b('h', 'large_house', 6, 10)];
      expect(GameEngine.connectedBuildingIds([hall, ...atGate]), contains('h'));
      final atWall = [_b('r', 'road', 2, 10), _b('h', 'large_house', 3, 10)];
      expect(
        GameEngine.connectedBuildingIds([hall, ...atWall]),
        isNot(contains('h')),
        reason: 'a road against the wall is not at a gate',
      );
    });
  });

  group('kModelFootprint', () {
    test('every model was made for the footprint the code ships', () {
      for (final MapEntry(key: id, value: f) in kModelFootprint.entries) {
        final def = _artDef(id)!;
        expect((def.gridW, def.gridH), f, reason: id);
      }
    });

    test('a database row cannot give a rebuilt building another footprint',
        () {
      // The live Small House row was still 3x3 on 2026-11-03.
      final row = kFallbackBuildingDefs['small_house']!.toDefRow()
        ..['grid_w'] = 3
        ..['grid_h'] = 3;
      final def = BuildingDef.fromDefRow(row);
      expect((def.gridW, def.gridH), kModelFootprint['small_house']);
      expect(entrancesFor(def.id, def.gridW, def.gridH), isNotNull);
      expect(animFor(def.id, def.gridW, def.gridH), isNotNull);
    });

    test('a database row with an old footprint gets neither entrance nor '
        'moving parts', () {
      // The live Small House row was still 3x3 on 2026-11-03.
      expect(entrancesFor('small_house', 3, 3), isNull);
      expect(animFor('small_house', 3, 3), isNull);
      expect(entrancesFor('small_house', 2, 2), isNotNull);
    });
  });

  group('kBuildingAnim', () {
    test('every moving building ships its base and its atlas', () {
      for (final MapEntry(key: id, value: spec) in kBuildingAnim.entries) {
        expect(File(spec.baseAsset(id)).existsSync(), isTrue,
            reason: spec.baseAsset(id));
        expect(File(BuildingAnimSpec.atlasAsset(id)).existsSync(), isTrue,
            reason: BuildingAnimSpec.atlasAsset(id));
        expect(spec.layers, isNotEmpty);
      }
    });

    test('every layer lands on the picture', () {
      for (final MapEntry(key: id, value: spec) in kBuildingAnim.entries) {
        for (final l in spec.layers) {
          expect(l.l >= 0 && l.t >= 0 && l.l + l.w <= 1.0001 && l.t + l.h <= 1.0001,
              isTrue, reason: '$id: a layer reaches past the picture');
          expect(l.sw > 0 && l.sh > 0 && l.period > 0, isTrue, reason: id);
        }
      }
    });
  });
}
