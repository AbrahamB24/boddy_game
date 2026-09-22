import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/services/housing_overview.dart';

// The Housing half of the Work page (user 2026-09-20): which buildings give
// monsters a roof, how many rooms each gives, and the ordering of the list.
void main() {
  BuildingDef def(
    String id,
    String name, {
    int population = 0,
    double bonus = 0,
  }) => BuildingDef(
    id: id,
    name: name,
    color: const Color(0xFF000000),
    gridW: 1,
    gridH: 1,
    population: population,
    populationBonus: bonus,
  );

  PlacedBuilding placed(String id, String type, {int level = 1}) =>
      PlacedBuilding(
        id: id,
        settlementId: 's',
        buildingTypeId: type,
        gridX: 0,
        gridY: 0,
        level: level,
        constructionSecondsRequired: 0,
        constructionSecondsBuilt: 0,
        isComplete: true,
        placedAt: DateTime(2026),
      );

  final defs = {
    'house': def('house', 'House', population: 3),
    'castle': def('castle', 'Castle', population: 6),
    'camp': def('camp', 'Camp'), // shelters nobody
    'inn': def('inn', 'Inn', bonus: 0.5), // no rooms of its own, +50 % to all
  };

  List<HouseRow> rows(
    List<PlacedBuilding> buildings, {
    bool Function(PlacedBuilding)? functional,
  }) => buildHouseRows(
    buildings: buildings,
    functional: functional ?? (_) => true,
    era: 1,
    defOf: (id) => defs[id],
  );

  test('only dwellings are listed', () {
    final r = rows([placed('a', 'house'), placed('b', 'camp')]);
    expect(r.map((x) => x.def.id), ['house']);
  });

  test('rooms grow with the level', () {
    final l1 = rows([placed('a', 'house', level: 1)]).single.rooms;
    final l3 = rows([placed('a', 'house', level: 3)]).single.rooms;
    expect(l1, closeTo(3, 1e-9));
    expect(l3, greaterThan(l1));
  });

  test('a building nobody can use (no road, unfinished) does not count', () {
    final r = rows([
      placed('a', 'house'),
      placed('b', 'house'),
    ], functional: (b) => b.id == 'a');
    expect(r.map((x) => x.building.id), ['a']);
  });

  test('the settlement-wide population bonus lifts every dwelling', () {
    final plain = rows([placed('a', 'house')]).single.rooms;
    final boosted = rows([placed('a', 'house'), placed('i', 'inn')]);
    expect(boosted.single.rooms, closeTo(plain * 1.5, 1e-9));
  });

  group('sorting', () {
    final all = rows([
      placed('a', 'house', level: 1),
      placed('b', 'castle', level: 4),
      placed('c', 'house', level: 3),
    ]);

    test('Rooms: the biggest first, and reversing flips it', () {
      expect(sortedHouses(all, HouseSort.rooms).map((h) => h.building.id), [
        'b',
        'c',
        'a',
      ]);
      expect(
        sortedHouses(
          all,
          HouseSort.rooms,
          reversed: true,
        ).map((h) => h.building.id),
        ['a', 'c', 'b'],
      );
    });

    test('Level: the highest first', () {
      expect(sortedHouses(all, HouseSort.level).map((h) => h.building.id), [
        'b',
        'c',
        'a',
      ]);
    });

    test('Name: A to Z, equal names by rooms', () {
      final byName = sortedHouses(all, HouseSort.name);
      expect(byName.first.def.name, 'Castle');
    });
  });
}
