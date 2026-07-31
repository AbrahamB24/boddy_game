import '../../settlement/data/goods_definitions.dart';
import '../models/creature_enums.dart' show CreatureRarity;
import '../models/creature_instance.dart';
import '../models/heal_balance.dart';
import '../models/species_balance.dart';

export '../models/heal_balance.dart' show HealConfig, kHealBalance;

// What healing costs (user design 2026-07-16).
//
// ── Why healing is THE sink ──
// Creature HP is persistent and never regenerates, so every fight — capture
// battles, tech trials, dungeon runs — drains it permanently. Healing is
// therefore the single most frequent thing a player does, which is exactly
// what a resource that must be "regelmässig benutzt" needs.
//
// It was also FREE and instant: one tap on the Healing Hut restored the whole
// collection. That made every HP cost in the game meaningless — including the
// ~55% per trial that docs/balancing.md §4b uses as a balance anchor. Pricing
// it is what turns those measurements back into real costs.
//
// ── Why it scales ──
// The cost is paid in the CURRENT ERA's goods (goodsForEra), never in a
// hardcoded 'fish'/'fur'. A later era that introduces a resource gets it spent
// here automatically, with no change to this file.

/// Real seconds of treatment per point of missing HP (user 2026-07-16:
/// "Heilen darf nicht sofort sein, sondern muss abhängig von den zu heilenden
/// HP dauern").
///
/// An instant heal made the cost the only brake, and goods are easy to gather
/// — so a wipe cost you a trip, not a decision. TIME is what makes retreating
/// with 30% HP different from pushing on and losing: the monster is out of
/// action while it mends, and you have to plan around that.
///
/// Sized against the anchors: a trial costs a ~60 HP monster ~55% of its
/// health (docs/balancing.md §4b) → ~33 HP → **~14 minutes** for a COMMON. A
/// full knockout of the same monster, with [kHealKoMultiplier], is
/// **~50 minutes** — a real afternoon-changing penalty, which is the point of
/// not fainting. A legendary takes ~3× as long.
///
/// PER RARITY and dev-authored since 2026-07-26 (Species-Budget → 🩹 Heilung),
/// read off [kSpeciesBalance] — a rare monster that recovered exactly as fast
/// as a common made rarity a pure stat difference.
double healSecondsPerHp(CreatureRarity rarity) =>
    kSpeciesBalance.of(rarity).healSecondsPerHp;

/// Goods per point of missing HP. Deliberately small: a scratch should be
/// pocket change and a wipe should hurt.
///
/// Sized against the era-I economy (docs/balancing.md §2): a 3-team of ~60 HP
/// each losing 55% of its health — one trial — costs ~10 goods total, against
/// a gather trip that brings home dozens. So routine fighting is affordable
/// and a bad run is felt.
double healGoodsPerHp(CreatureRarity rarity) =>
    kSpeciesBalance.of(rarity).healGoodsPerHp;

/// The ERA whose luxury goods pay for [c]'s treatment (user 2026-07-26: "es
/// werden immer die Luxusressourcen benötigt, welche der Ära des Monsters
/// entsprechen"). A species' region tier IS its era — region N is era N — so a
/// starter is always mended with era-I supplies however far the settlement has
/// come, and a region-3 catch demands region-3 goods.
///
/// Falls back to era 1 for a creature whose species def hasn't loaded: the
/// cheapest, always-available bill, so a missing def can never make a monster
/// unhealable.
int creatureHealEra(CreatureInstance c) => c.species?.tier ?? 1;

/// Multiplier on a K.O.'d creature's heal — BOTH its price and its duration.
/// Reviving is not the same as bandaging: without this, being knocked out
/// costs exactly as much as surviving on 1 HP, and there'd be no reason to
/// retreat.
double get kHealKoMultiplier => kHealBalance.koMultiplier;

/// Total goods a single creature's heal costs, before being split across its
/// era's goods. 0 for a creature at full health.
double healGoodsFor(CreatureInstance c) {
  // `hp`, never the raw `currentHp`: the field uses -1 as a sentinel for
  // "full", so reading it directly would bill a brand-new creature for
  // maxHp + 1 points of damage it hasn't taken.
  final missing = c.maxHp - c.hp;
  if (missing <= 0) return 0;
  final base =
      missing * healGoodsPerHp(c.species?.rarity ?? CreatureRarity.common);
  return c.isKo ? base * kHealKoMultiplier : base;
}

/// The cost of healing [creatures], billed against [stock] — a resource map
/// ready for ResourceModel.deduct.
///
/// Per creature and proportional to MISSING HP (user's choice): only the hurt
/// cost anything, and they cost what they're actually missing — so there's no
/// reason to hoard damage and heal in one lump, which a flat price would
/// reward.
///
/// EACH MONSTER IS BILLED IN ITS OWN ERA'S GOODS (user 2026-07-26), not in the
/// settlement's: a region-1 catch always costs region-1 supplies, a region-3
/// one costs region-3 supplies. Since [goodsForEra] is cumulative, a late-era
/// monster may also be paid in early goods — which is why the bill is settled
/// LOWEST ERA FIRST: those creatures have the fewest goods to choose from, and
/// billing them last would let a late-era monster eat the fish they need.
///
/// Grouped per era rather than per creature because [goodsCost] rounds a bill
/// UP to whole units: three scratched monsters would otherwise pay three
/// rounded-up bills instead of one.
///
/// [stock] is what makes it un-deadlockable: the bill is paid from the goods
/// you HAVE rather than demanding one of each (see goodsCost). Healing is the
/// game's most frequent action and the thing every fight leads to — it must
/// never be the thing you can't do.
Map<String, double> healCost(
  List<CreatureInstance> creatures,
  Map<String, double> stock, {
  double costMult = 1.0,
}) {
  final byEra = <int, double>{};
  for (final c in creatures) {
    final goods = healGoodsFor(c) * costMult;
    if (goods <= 0) continue;
    final era = creatureHealEra(c);
    byEra[era] = (byEra[era] ?? 0) + goods;
  }
  if (byEra.isEmpty) return const {};

  // A working copy so two eras can't both spend the same fish. It may go
  // negative on an unaffordable bill, which simply makes those goods
  // unavailable to the next era — goodsCost skips a non-positive holding.
  final left = Map<String, double>.from(stock);
  final bill = <String, double>{};
  final eras = byEra.keys.toList()..sort();
  for (final era in eras) {
    goodsCost(byEra[era]!, era, left).forEach((id, amount) {
      bill[id] = (bill[id] ?? 0) + amount;
      left[id] = (left[id] ?? 0) - amount;
    });
  }
  return bill;
}

/// Whether [stock] covers [cost].
bool canAfford(Map<String, double> cost, Map<String, double> stock) =>
    cost.entries.every((e) => (stock[e.key] ?? 0) >= e.value);

/// How long [c]'s treatment takes. Zero for a creature at full health.
///
/// Per creature, not per batch: sending three monsters to the hut heals them
/// in PARALLEL, each finishing when its own wounds are mended. A shared timer
/// would mean one scratched monster waits on a K.O.'d one, which is the
/// opposite of the decision this is meant to create.
Duration healDuration(CreatureInstance c) {
  final missing = c.maxHp - c.hp;
  if (missing <= 0) return Duration.zero;
  final base =
      missing * healSecondsPerHp(c.species?.rarity ?? CreatureRarity.common);
  final seconds = c.isKo ? base * kHealKoMultiplier : base;
  return Duration(seconds: seconds.round());
}

/// Longest treatment in [creatures] — what "heal all" will actually take.
Duration healDurationFor(List<CreatureInstance> creatures) => creatures.fold(
  Duration.zero,
  (longest, c) {
    final d = healDuration(c);
    return d > longest ? d : longest;
  },
);
