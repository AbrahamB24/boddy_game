import '../data/building_definitions.dart';
import '../models/placed_building.dart';

/// The numbers behind the Housing half of the Work page (user 2026-09-20,
/// "Variante 1, Zwei Reiter"): every complete, road-connected building that
/// gives monsters a roof, and how many rooms it gives.
///
/// The same rule the housing budget sums by ([GameEngine.housingCapacity]) — a
/// per-era `housing` effect, else the flat population column, scaled by the
/// level, plus the settlement-wide population bonus other buildings grant. It
/// was the body of the old Housing screen; it lives here so it can be tested.
///
/// Pure: everything comes in as arguments.

/// One dwelling and what it gives.
class HouseRow {
  final PlacedBuilding building;
  final BuildingDef def;

  /// Rooms this building gives, the settlement's population bonus included.
  final double rooms;

  const HouseRow({
    required this.building,
    required this.def,
    required this.rooms,
  });
}

/// How the house list is ordered (a tap on the same one flips it).
enum HouseSort {
  rooms('Rooms'),
  level('Level'),
  name('Name');

  final String label;
  const HouseSort(this.label);
}

/// One row per building, NOT grouped by type — two Houses at different levels
/// give different amounts, which grouping would hide.
///
/// [functional] says whether a building counts at all (complete and reached by a
/// road); [defOf] resolves a building's definition (the live table in the app).
List<HouseRow> buildHouseRows({
  required List<PlacedBuilding> buildings,
  required bool Function(PlacedBuilding) functional,
  required int era,
  BuildingDef? Function(String id)? defOf,
}) {
  BuildingDef? lookup(String id) => (defOf ?? (i) => kBuildingDefs[i])(id);
  final live = buildings.where(functional).toList();

  // A settlement-wide "+15 % population" from any functional building.
  var bonus = 0.0;
  for (final b in live) {
    final def = lookup(b.buildingTypeId);
    if (def != null) {
      bonus += def.populationBonus * buildingYieldFactor(b.level);
    }
  }

  final rows = <HouseRow>[];
  for (final b in live) {
    final def = lookup(b.buildingTypeId);
    if (def == null || !def.sheltersMonsters(era)) continue;
    final base = def.hasEffect('housing', era)
        ? def.effectAt('housing', '', era, level: b.level)
        : def.housingCapacity * buildingYieldFactor(b.level);
    if (base <= 0) continue;
    rows.add(HouseRow(building: b, def: def, rooms: base * (1 + bonus)));
  }
  return rows;
}

/// [rows] ordered by [sort] — the biggest first, or A to Z, unless [reversed].
List<HouseRow> sortedHouses(
  Iterable<HouseRow> rows,
  HouseSort sort, {
  bool reversed = false,
}) {
  final list = rows.toList();
  list.sort((a, b) {
    final cmp = switch (sort) {
      // Biggest first; the name breaks ties so the order is stable.
      HouseSort.rooms => b.rooms.compareTo(a.rooms),
      HouseSort.level => b.building.level.compareTo(a.building.level),
      HouseSort.name => a.def.name.compareTo(b.def.name),
    };
    return cmp != 0 ? cmp : a.def.name.compareTo(b.def.name);
  });
  return reversed ? list.reversed.toList() : list;
}
