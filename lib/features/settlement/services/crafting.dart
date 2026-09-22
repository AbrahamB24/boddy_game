import 'dart:math' as math;

import '../data/goods_definitions.dart';
import '../data/item_definitions.dart';

// Pure crafting maths — no controller, no Supabase, so the rules are testable
// on their own. The stateful half lives in SettlementController.
//
// Shape mirrors construction: a recipe needs [craftSeconds] of work, the
// Workshop's crafting power supplies craft-seconds per hour, and the item lands
// when the two meet. Nothing here reads the clock.

/// What one craft of [def] costs. When the recipe names concrete [ingredients]
/// (user 2026-07-25), those specific goods are charged literally — that is how
/// luxury goods get a purpose. Otherwise it falls back to the legacy abstract
/// [supplyCost], billed against era [eraOrder]'s goods richest-first from what
/// the settlement actually has ([stock]).
Map<String, double> craftCost(
  ItemDef def,
  int eraOrder,
  Map<String, double> stock,
) {
  if (def.ingredients.isNotEmpty) return Map.of(def.ingredients);
  return goodsCost(def.supplyCost, eraOrder, stock);
}

/// Real seconds one craft of [def] takes at [craftPowerPerHour].
///
/// Returns null when nobody is crafting — the caller must say "post a monster
/// in the Workshop" rather than show a bar that never moves. That exact
/// failure (a silent, motionless progress bar reading as a bug) is why the old
/// research screen had to spell out "nobody is researching".
double? craftSecondsAt(
  ItemDef def,
  double craftPowerPerHour, {
  double timeScale = 1.0,
}) {
  if (craftPowerPerHour <= 0) return null;
  return (def.craftSeconds * timeScale) / craftPowerPerHour * 3600;
}

/// Progress 0..1 of [built] craft-seconds against [def]'s requirement.
double craftProgress(ItemDef def, double built, {double timeScale = 1.0}) {
  final needed = def.craftSeconds * timeScale;
  if (needed <= 0) return 1;
  return (built / needed).clamp(0.0, 1.0);
}

/// Whether [built] craft-seconds finish [def].
bool craftComplete(ItemDef def, double built, {double timeScale = 1.0}) =>
    built >= def.craftSeconds * timeScale;

/// Total items held, for "your bag is N items" style readouts.
int itemCount(Map<String, int> inventory) =>
    inventory.values.fold(0, (s, n) => s + n);

/// Adds [n] of [itemId] to [inventory], returning a new map.
Map<String, int> addItem(
  Map<String, int> inventory,
  String itemId, [
  int n = 1,
]) => {...inventory, itemId: (inventory[itemId] ?? 0) + n};

/// Removes one [itemId], returning a new map — or null when there is none to
/// remove, so a caller can't spend an item it doesn't have by ignoring a bool.
Map<String, int>? removeItem(Map<String, int> inventory, String itemId) {
  final have = inventory[itemId] ?? 0;
  if (have <= 0) return null;
  final next = {...inventory};
  if (have == 1) {
    next.remove(
      itemId,
    ); // don't leave a 0 behind — it would show as a bag entry
  } else {
    next[itemId] = have - 1;
  }
  return next;
}

/// HP [def] actually restores to a creature missing [missingHp].
///
/// Capped at what's missing: a 100-HP potion on a monster down 12 HP heals 12.
/// The overflow is simply not granted — but see canUseOn, which is what stops
/// the player from wasting it in the first place.
double healFromItem(ItemDef def, double missingHp) =>
    math.max(0, math.min(def.healHp, missingHp));

/// Whether using [def] on a creature missing [missingHp] does anything at all.
bool canUseOn(ItemDef def, double missingHp) => def.isHeal && missingHp > 0;

Map<String, int> inventoryFromJson(Map<dynamic, dynamic>? json) => {
  for (final e in (json ?? const {}).entries)
    if ((e.value as num?)?.toInt() case final int n when n > 0)
      e.key as String: n,
};

// ── What can be made from what is in store (Crafting page, 2026-09-20) ──────

/// Stands in for "as many as you like" — a recipe that costs nothing.
const int kCraftableCap = 999;

/// The Crafting page's groups of recipes (user 2026-09-20, "Variante 4,
/// Kategorien + Detail"): the rail on the left.
enum CraftGroup {
  heal('Heal'),
  revive('Revive'),
  cures('Cures'),
  boosts('Boosts'),
  packs('Packs');

  final String label;
  const CraftGroup(this.label);
}

/// Which rail button an item of [kind] sits under.
CraftGroup craftGroupOf(ItemKind kind) => switch (kind) {
  ItemKind.heal => CraftGroup.heal,
  ItemKind.revive => CraftGroup.revive,
  ItemKind.cureStatus || ItemKind.cureDebuffs => CraftGroup.cures,
  ItemKind.buff ||
  ItemKind.catchBoost ||
  ItemKind.expeditionYield ||
  ItemKind.breedSpeed => CraftGroup.boosts,
  ItemKind.resourcePack => CraftGroup.packs,
};

/// What [n] crafts of [def] cost against [stock] — the named ingredients times
/// [n], or the abstract supply bill for [n] crafts billed richest-first.
Map<String, double> craftCostFor(
  ItemDef def,
  int eraOrder,
  Map<String, double> stock,
  int n,
) {
  if (def.ingredients.isNotEmpty) {
    return {for (final e in def.ingredients.entries) e.key: e.value * n};
  }
  return goodsCost(def.supplyCost * n, eraOrder, stock);
}

/// How many of [def] the goods in [stock] pay for right now (each craft is
/// billed on completion, so this is "how many could finish today").
int craftableCount(ItemDef def, int eraOrder, Map<String, double> stock) {
  if (def.ingredients.isNotEmpty) {
    var n = kCraftableCap;
    for (final e in def.ingredients.entries) {
      if (e.value <= 0) continue;
      n = math.min(n, ((stock[e.key] ?? 0) / e.value).floor());
    }
    return n;
  }
  if (def.supplyCost <= 0) return kCraftableCap;
  final unit = math.max(1, def.supplyCost.ceil());
  var total = 0;
  for (final g in goodsForRegion(eraOrder)) {
    total += (stock[g.id] ?? 0).floor();
  }
  return total ~/ unit;
}

/// What is missing to make [n] of [def]: good id → how much more you need.
/// Empty when the store covers it.
Map<String, double> craftShortfall(
  ItemDef def,
  int eraOrder,
  Map<String, double> stock, {
  int n = 1,
}) {
  final cost = craftCostFor(def, eraOrder, stock, n);
  return {
    for (final e in cost.entries)
      if ((stock[e.key] ?? 0) < e.value) e.key: e.value - (stock[e.key] ?? 0),
  };
}
