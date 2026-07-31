import 'dart:math' as math;

import '../../../core/tuning/game_tuning.dart';
import '../data/goods_definitions.dart';
import '../data/item_definitions.dart';
import 'gold_economy.dart';

// ── The Trade Center (user 2026-07-25, item system Phase 3) ────────────────
//
// Three trades, one building, all priced off ONE anchor — gold_economy's
// [sellRate], so a resource a later era introduces trades the day it appears
// with no change here (same rule the market already followed):
//
//   1. SELL   goods → gold        (unchanged, gold_economy.sellValue)
//   2. SHOP   gold  → items       ← the gold SINK: gold finally buys a thing
//   3. TRADE  gold  → goods  and  goods ↔ goods   ← the surplus valve
//
// Every direction is deliberately LOSSY, and that is the whole design: buying
// back costs [kGoodsBuyMarkup]× what selling paid, a barter keeps only
// (1 − [kBarterFee]) of the value it consumed, and an item always sells back
// for less than it cost. Without that spread the Trade Center would be a money
// pump (sell 100 fish, buy 100 fish, repeat) instead of a convenience.
//
// The building's LEVEL narrows the spread — see [SettlementController
// .tradeDiscount], fed in here as [discount] (0..[kMaxTradeDiscount]) so a
// levelled Trade Center is measurably better without ever reaching par.
//
// Pure math, no widgets and no controller: the sheet and the tests read the
// same functions, so a rate can't drift between them.

/// What buying a resource back costs, as a multiple of what selling it paid.
/// 2.5 → sell 100 fish for 35 gold, buy them back for 88. The round trip is a
/// real loss, so gold-for-goods is an emergency valve (a recipe wants fur and
/// you have only fish), never an income strategy.
/// All three are DIALS since 2026-07-29 (Settlement → Handel) — the spread is
/// the Trade Center's whole balance, and it is the first thing that gets
/// retuned when gold feels too tight or too loose.
double get kGoodsBuyMarkup => GameTuning.i.raw(Dials.goodsBuyMarkup);

/// Cut taken out of a goods↔goods barter. 25% → 100 fish becomes 75 fur.
double get kBarterFee => GameTuning.i.raw(Dials.barterFee);

/// Ceiling on the level discount. Kept well below 1.0 on purpose: at par
/// every trade above becomes free to undo, and free undo is an exploit.
double get kMaxTradeDiscount => GameTuning.i.raw(Dials.tradeMaxDiscount);

double _d(double discount) => discount.clamp(0.0, kMaxTradeDiscount);

// ── Gold → goods ────────────────────────────────────────────

/// Markup actually charged at [discount] — shrinks the SPREAD, never the value:
/// 2.5× at level 1, 1.6× at the discount ceiling.
double goodsBuyMarkup(double discount) =>
    1 + (kGoodsBuyMarkup - 1) * (1 - _d(discount));

/// Gold that buying [amount] units of [resource] costs. Always at least 1 for a
/// non-empty purchase — nothing is ever free.
int goodsBuyCost(String resource, double amount, {double discount = 0}) {
  if (amount <= 0) return 0;
  final rate = sellRate(resource);
  if (rate <= 0) return 0; // gold itself: not buyable with gold
  return math.max(1, (amount * rate * goodsBuyMarkup(discount)).ceil());
}

/// Units of [resource] that [gold] buys (whole units only — a Trade Center that
/// hands out 0.4 fish can neither store nor show it).
double goodsForGold(String resource, int gold, {double discount = 0}) {
  final rate = sellRate(resource);
  if (rate <= 0 || gold <= 0) return 0;
  return (gold / (rate * goodsBuyMarkup(discount))).floorToDouble();
}

// ── Goods ↔ goods ───────────────────────────────────────────

/// Fee actually charged at [discount]: 25% at level 1, 10% at the ceiling.
double barterFee(double discount) => kBarterFee * (1 - _d(discount));

/// Units of [to] you get for [amountFrom] units of [from].
///
/// Value-neutral before the fee, priced through [sellRate] — so 10 wood buys
/// about 2 fish (a good is worth 3.5 logs) and any two goods swap 1:1 minus the
/// fee. Whole units only, and 0 when the trade is too small to pay out at all;
/// the caller must refuse it rather than eat the input for nothing.
double barterYield(
  String from,
  String to,
  double amountFrom, {
  double discount = 0,
}) {
  if (from == to || amountFrom <= 0) return 0;
  final rateFrom = sellRate(from);
  final rateTo = sellRate(to);
  if (rateFrom <= 0 || rateTo <= 0) return 0; // gold is not bartered
  final value = amountFrom * rateFrom * (1 - barterFee(discount));
  return (value / rateTo).floorToDouble();
}

/// Smallest amount of [from] that yields at least one unit of [to].
double minBarterAmount(String from, String to, {double discount = 0}) {
  final rateFrom = sellRate(from);
  final rateTo = sellRate(to);
  if (from == to || rateFrom <= 0 || rateTo <= 0) return double.infinity;
  return (rateTo / (rateFrom * (1 - barterFee(discount)))).ceilToDouble();
}

// ── Gold → items (the sink) ─────────────────────────────────

/// Whether the Trade Center stocks [def] at all (buyPrice 0 = not for sale).
bool itemIsSold(ItemDef def) => def.buyPrice > 0;

/// Gold [def] costs, after the level [discount]. At least 1.
int itemBuyCost(ItemDef def, {double discount = 0}) {
  if (def.buyPrice <= 0) return 0;
  return math.max(1, (def.buyPrice * (1 - _d(discount))).ceil());
}

/// Gold you get for selling [def] back — never more than [itemBuyCost] − 1, so
/// a levelled Trade Center can't turn the shop into an infinite money loop.
int itemSellValue(ItemDef def, {double discount = 0}) {
  if (def.sellPrice <= 0) return 0;
  final raw = (def.sellPrice * (1 + _d(discount))).floor();
  final buy = itemBuyCost(def, discount: discount);
  final capped = buy > 0 ? math.min(raw, buy - 1) : raw;
  return math.max(0, capped);
}

/// The shop's stock, cheapest first — every sold item, whether the player has
/// the recipe or not (buying is the alternative to crafting, not a shortcut
/// through it).
List<ItemDef> shopStock() => kItemDefs.values.where(itemIsSold).toList()
  ..sort((a, b) {
    final byPrice = a.buyPrice.compareTo(b.buyPrice);
    return byPrice != 0 ? byPrice : a.name.compareTo(b.name);
  });

// ── What is tradeable at all ────────────────────────────────

/// Every resource the Trade Center handles in era [eraOrder]: the bulk pair
/// first, then the era's supplies and materials in ladder order.
///
/// Era-scoped on purpose — listing era-VIII Aether in era I is noise the player
/// can neither hold nor use.
List<String> tradeableResources(int eraOrder) => [
  'wood',
  'stone',
  for (final g in goodsForEra(eraOrder)) g.id,
  for (final g in materialsForEra(eraOrder)) g.id,
];
