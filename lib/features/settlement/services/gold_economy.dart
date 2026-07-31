import 'dart:math' as math;

import '../data/goods_definitions.dart';

// Gold: the currency that turns SURPLUS into TIME (user design 2026-07-16).
//
// Gold had no sink at all — nothing in the game cost any. It is now the one
// resource you never need and always want:
//
//   sell what you have too much of  →  gold  →  skip a wait
//
// That shape is deliberate. Gold gates nothing (no building, tech or dungeon
// costs it), so a player who ignores it loses no content — they only wait. And
// it gives every surplus a purpose: a woodpile you can't spend is dead weight,
// a woodpile you can sell is a decision.
//
// Pure math only, no widgets and no controller: the trade sheet and the three
// speed-up buttons all read from here, so a rate can't drift between them.

// ── Selling ─────────────────────────────────────────────────

/// Gold per unit of a bulk resource (wood, stone).
///
/// 10 → 1. Against the ~850 wood/day target (docs/balancing.md §2), a day's
/// worth of wood is ~85 gold, which buys roughly an hour and a half of skipping
/// at [kSecondsPerGold]. Enough to matter, nowhere near enough to erase the
/// game's timers.
const double kBasicSellRate = 0.1;

/// Gold per unit of a special resource (fish, fur, and whatever later eras
/// add). Worth ~3.5× a log because goods are scarce AND have a real sink —
/// healing. Selling them is meant to be a genuine trade-off, not free money.
const double kGoodsSellRate = 0.35;

/// What one unit of [resource] fetches. Gold itself is unsellable.
///
/// Derived, never a per-resource table: era-scoped goods all price the same, so
/// a resource a later era introduces sells the day it appears with no change
/// here (see goods_definitions.dart).
double sellRate(String resource) {
  if (resource == 'gold') return 0;
  if (kGoodsDefs.containsKey(resource)) return kGoodsSellRate;
  return kBasicSellRate;
}

/// Gold from selling [amount] of [resource]. Floors: selling must never invent
/// a fraction of a coin.
int sellValue(String resource, double amount) =>
    (amount * sellRate(resource)).floor();

/// The smallest amount of [resource] worth selling — below this it rounds to 0
/// gold and would silently eat the resources.
double minSellable(String resource) {
  final rate = sellRate(resource);
  return rate <= 0 ? double.infinity : 1 / rate;
}

// ── Buying time ─────────────────────────────────────────────

/// Seconds of waiting one gold removes.
///
/// 1 gold ≈ 1 minute. Read together with [kBasicSellRate] this is the whole
/// exchange rate of the game: **100 wood buys 10 minutes.**
const double kSecondsPerGold = 60;

/// Gold to skip [remainingSeconds] of a timer. Always at least 1 for a wait
/// that hasn't finished — a skip is never free.
///
/// Linear in the time remaining, not in the total: paying to skip the last
/// minute of an eight-hour breeding job should cost one minute's worth. It
/// also means letting a timer run down is always the cheaper play, so gold
/// stays a convenience rather than the intended path.
int goldToSkip(Duration remaining) {
  if (remaining.inSeconds <= 0) return 0;
  return math.max(1, (remaining.inSeconds / kSecondsPerGold).ceil());
}
