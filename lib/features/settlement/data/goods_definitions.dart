class GoodsDef {
  final String id;
  final String name;
  final String emoji;
  // How many units one person consumes per hour, settlement-wide (population
  // * this). Fish/Fur are 0 here deliberately — population doesn't eat these
  // directly, only the specific building that needs them for its own bonus
  // does (Hut/Longhouse's BuildingDef.needConsumptionPerHour) — confirmed by
  // Balancing/Houses.xlsx's Metric block, whose "Fish/Fur consumed Max/h"
  // figures match the building-level consumption exactly, not a
  // population-scaled number.
  final double consumptionPerCapitaPerHour;

  const GoodsDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.consumptionPerCapitaPerHour,
  });
}

// DB column keys must match these ids exactly.
const kGoodsDefs = <String, GoodsDef>{
  'fish': GoodsDef(
    id: 'fish',
    name: 'Fish',
    emoji: '🐟',
    consumptionPerCapitaPerHour: 0,
  ),
  'fur': GoodsDef(
    id: 'fur',
    name: 'Fur',
    emoji: '🦫',
    consumptionPerCapitaPerHour: 0,
  ),
};
