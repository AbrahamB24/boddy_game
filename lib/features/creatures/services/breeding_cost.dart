/// What a MATING costs in supplies (user 2026-07-27: "Breeding soll luxuswaren
/// kosten von der ära, aus welcher die Monster stammen").
///
/// Breeding used to be the one creature sink that was free — it cost a hut, a
/// pair and a wait, and nothing else. A hut with an idle slot therefore had no
/// reason ever to sit idle, and the goods economy had no demand from the
/// creature half of the game at all.
///
/// THE ERA IS THE PARENTS', NOT THE SETTLEMENT'S — exactly as healing works
/// (see healing_cost.dart): a species' region tier IS its era, so a starter
/// pair always breeds on era-I supplies however far the settlement has come,
/// and a region-3 pair demands region-3 supplies. Since [goodsForEra] is
/// cumulative, a late-era pair may also be paid in early goods.
///
/// Billed ONCE for the pair, not per parent: one mating, one bill.
library;

import '../../settlement/data/goods_definitions.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/species_balance.dart';
import '../models/species_def.dart';

/// The supplies one mating of [rarity] costs, before the era split.
double breedGoodsFor(CreatureRarity rarity) =>
    kSpeciesBalance.of(rarity).breedGoods;

/// The era whose goods a pair of [species] pays in — its region tier, with era
/// 1 as the fallback for a def that hasn't loaded (the cheapest, always
/// available bill, so a missing def can never make a pair unbreedable).
int breedEra(SpeciesDef? species) => species?.tier ?? 1;

/// The bill for mating [a] and [b], billed against [stock] — a resource map
/// ready for `SettlementController.spendResources`.
///
/// Both parents are always the same species (the pair picker enforces it), so
/// the rarity and era come from whichever def is available. Paid from the goods
/// you HAVE, richest first — see [goodsCost]; that is what keeps the bill from
/// demanding a good the region cannot supply.
Map<String, double> breedCost(
  CreatureInstance a,
  CreatureInstance b,
  Map<String, double> stock,
) {
  final species = a.species ?? b.species;
  final rarity = species?.rarity ?? CreatureRarity.common;
  final total = breedGoodsFor(rarity);
  if (total <= 0) return const {};
  return goodsCost(total, breedEra(species), stock);
}

/// Whether [stock] covers [cost].
bool canAffordBreed(Map<String, double> cost, Map<String, double> stock) =>
    cost.entries.every((e) => (stock[e.key] ?? 0) >= e.value);

/// "🐟 6 · 🦫 4" — names the goods, so a refusal says what to go and gather.
String breedCostLabel(Map<String, double> cost) => cost.entries
    .map((e) => '${kGoodsDefs[e.key]?.emoji ?? e.key} ${e.value.toInt()}')
    .join(' · ');
