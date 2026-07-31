import 'goods_definitions.dart';

// ── Per-RESOURCE gathering dials (user 2026-07-25) ──────────
//
// Three problems, one table:
//
//  1. **Carry was weight 1:1.** A monster with carry 15 hauled 15 wood, so a
//     whole expedition brought home less than a single tick of the settlement's
//     production ("da ansonsten sich die Expeditionen nicht lohnen"). Carry is
//     now a number of PORTERS, not kilos: what one point holds depends on what
//     is being carried.
//  2. **Bulk and luxury were the same.** Wood and stone should come home by the
//     hundred; luxuries by the handful; gold barely at all. That is exactly the
//     [unitsPerCarry] dial — logs stack, spice does not.
//  3. **Every number lived somewhere else.** Spot capacity, regeneration and
//     yield sat on each ResourceSpotDef inside each area, so tuning "how much
//     wood is a wood spot" meant editing every area. They live here now, once
//     per resource, and the area only says WHICH resource is where (user
//     decision: "Ressourcen-Menü ist die einzige Quelle").
//
// Dev-Mode editable (Dev Mode → Resources, table `gather_defs`), same
// bundled-fallback + DB-override pattern as every other def.

class ResourceGatherDef {
  /// Resource id — 'wood', 'stone', 'gold', or any good id.
  final String resource;

  /// How many units ONE point of the carry stat brings home. The bulk/luxury
  /// split lives here: 20 logs per point, 4 fish, 1 gold.
  final double unitsPerCarry;

  /// How long ONE point of the gather stat needs to mine ONE unit, in seconds.
  /// The direct answer to "wie lange geht es, um 1 Ressource pro Statpunkt
  /// abzubauen" — bigger = slower. Rate = statPoints × 3600 / this.
  final double secondsPerUnitPerStat;

  /// How much a spot of this resource holds when full.
  final double spotCapacity;

  /// How fast an untouched spot refills, per hour.
  final double regenPerHour;

  const ResourceGatherDef({
    required this.resource,
    required this.unitsPerCarry,
    required this.secondsPerUnitPerStat,
    required this.spotCapacity,
    required this.regenPerHour,
  });

  /// Units per hour a group with [gatherPower] summed stat points mines.
  double ratePerHour(num gatherPower) {
    if (secondsPerUnitPerStat <= 0 || gatherPower <= 0) return 0;
    return gatherPower * 3600.0 / secondsPerUnitPerStat;
  }

  /// Units a group with [carryPoints] summed carry stat can haul in one trip.
  double loadCap(num carryPoints) => carryPoints * unitsPerCarry;

  factory ResourceGatherDef.fromDefRow(Map<String, dynamic> row) =>
      ResourceGatherDef(
        resource: row['id'] as String,
        unitsPerCarry: (row['units_per_carry'] as num?)?.toDouble() ?? 1,
        secondsPerUnitPerStat:
            (row['seconds_per_unit_per_stat'] as num?)?.toDouble() ?? 3000,
        spotCapacity: (row['spot_capacity'] as num?)?.toDouble() ?? 0,
        regenPerHour: (row['regen_per_hour'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toDefRow() => {
    'id': resource,
    'units_per_carry': unitsPerCarry,
    'seconds_per_unit_per_stat': secondsPerUnitPerStat,
    'spot_capacity': spotCapacity,
    'regen_per_hour': regenPerHour,
  };

  ResourceGatherDef copyWith({
    double? unitsPerCarry,
    double? secondsPerUnitPerStat,
    double? spotCapacity,
    double? regenPerHour,
  }) => ResourceGatherDef(
    resource: resource,
    unitsPerCarry: unitsPerCarry ?? this.unitsPerCarry,
    secondsPerUnitPerStat:
        secondsPerUnitPerStat ?? this.secondsPerUnitPerStat,
    spotCapacity: spotCapacity ?? this.spotCapacity,
    regenPerHour: regenPerHour ?? this.regenPerHour,
  );
}

/// First-pass values, to be tuned in Dev Mode. The shape is the point:
///
///   BULK (wood/stone)   many per carry point, quick per unit, deep spots
///   LUXURY (fish/fur/…) a handful per point, slower, shallower spots
///   GOLD                one per point, slowest — a trickle, never an income
///
/// Read together with a mid-game group (≈190 summed gather, 15 summed carry):
/// wood → 300 per trip at 228/h (~1h20); fish → 60 at 76/h (~50m); gold → 15
/// at 34/h (~26m).
const Map<String, ResourceGatherDef> kFallbackGatherDefs = {
  'wood': ResourceGatherDef(
    resource: 'wood',
    unitsPerCarry: 20,
    secondsPerUnitPerStat: 3000,
    spotCapacity: 1200,
    regenPerHour: 120,
  ),
  'stone': ResourceGatherDef(
    resource: 'stone',
    unitsPerCarry: 20,
    secondsPerUnitPerStat: 3000,
    spotCapacity: 1000,
    regenPerHour: 100,
  ),
  'gold': ResourceGatherDef(
    resource: 'gold',
    unitsPerCarry: 1,
    secondsPerUnitPerStat: 20000,
    spotCapacity: 120,
    regenPerHour: 12,
  ),
  'fish': ResourceGatherDef(
    resource: 'fish',
    unitsPerCarry: 4,
    secondsPerUnitPerStat: 9000,
    spotCapacity: 300,
    regenPerHour: 30,
  ),
  'fur': ResourceGatherDef(
    resource: 'fur',
    unitsPerCarry: 4,
    secondsPerUnitPerStat: 9000,
    spotCapacity: 240,
    regenPerHour: 24,
  ),
};

/// Live, mutable map — GameDefsController layers `gather_defs` rows onto this
/// per id (mirrors kBuildingDefs / kItemDefs).
final Map<String, ResourceGatherDef> kGatherDefs = Map.of(kFallbackGatherDefs);

/// The dials for [resource] — never null.
///
/// A resource with no row yet (every good a later era introduces) falls back to
/// the LUXURY shape rather than to nothing: a new good then gathers sensibly the
/// day it appears, exactly like the sell rate does, and a dev row can still tune
/// it. Bulk (wood/stone) and gold are always authored above.
ResourceGatherDef gatherDefFor(String resource) {
  final def = kGatherDefs[resource];
  if (def != null) return def;
  final good = kGoodsDefs[resource];
  // A later era's raw/element is a BUILD material — it stacks like bulk.
  final isMaterial = good != null && !good.isSupply;
  return ResourceGatherDef(
    resource: resource,
    unitsPerCarry: isMaterial ? 12 : 4,
    secondsPerUnitPerStat: isMaterial ? 4500 : 9000,
    spotCapacity: isMaterial ? 600 : 300,
    regenPerHour: isMaterial ? 60 : 30,
  );
}

/// Every resource the Dev-Mode editor lists: the authored dials first, then any
/// good that has none yet (so it can be given one).
List<String> gatherTunableResources() => [
  ...kGatherDefs.keys,
  for (final g in kGoodsDefs.keys)
    if (!kGatherDefs.containsKey(g)) g,
];
