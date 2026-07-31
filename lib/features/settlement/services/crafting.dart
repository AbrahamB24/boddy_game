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
Map<String, double> craftCost(ItemDef def, int eraOrder, Map<String, double> stock) {
  if (def.ingredients.isNotEmpty) return Map.of(def.ingredients);
  return goodsCost(def.supplyCost, eraOrder, stock);
}

/// Real seconds one craft of [def] takes at [craftPowerPerHour].
///
/// Returns null when nobody is crafting — the caller must say "post a monster
/// in the Workshop" rather than show a bar that never moves. That exact
/// failure (a silent, motionless progress bar reading as a bug) is why the old
/// research screen had to spell out "nobody is researching".
double? craftSecondsAt(ItemDef def, double craftPowerPerHour, {double timeScale = 1.0}) {
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
Map<String, int> addItem(Map<String, int> inventory, String itemId, [int n = 1]) =>
    {...inventory, itemId: (inventory[itemId] ?? 0) + n};

/// Removes one [itemId], returning a new map — or null when there is none to
/// remove, so a caller can't spend an item it doesn't have by ignoring a bool.
Map<String, int>? removeItem(Map<String, int> inventory, String itemId) {
  final have = inventory[itemId] ?? 0;
  if (have <= 0) return null;
  final next = {...inventory};
  if (have == 1) {
    next.remove(itemId); // don't leave a 0 behind — it would show as a bag entry
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
bool canUseOn(ItemDef def, double missingHp) =>
    def.isHeal && missingHp > 0;

Map<String, int> inventoryFromJson(Map<dynamic, dynamic>? json) => {
  for (final e in (json ?? const {}).entries)
    if ((e.value as num?)?.toInt() case final int n when n > 0)
      e.key as String: n,
};
