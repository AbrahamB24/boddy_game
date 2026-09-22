import 'dart:math' as math;

import '../data/goods_definitions.dart';

// Gold: the currency that buys TIME (user design 2026-07-16, made scarce and
// dear on 2026-09-22).
//
// Gold gates nothing (no building, tech or dungeon costs it), so a player who
// ignores it loses no content — they only wait. It is now EARNED, not farmed:
//
//   daily goals · expeditions · the gold mine  →  gold  →  skip a wait
//
// Selling surplus pays next to nothing any more ([kSellPayoutFactor]) and a
// skipped minute costs ten coins ([kSecondsPerGold]), so a coin means something.
//
// Pure math only, no widgets and no controller: the trade sheet and the three
// speed-up buttons all read from here, so a rate can't drift between them.

// ── Selling ─────────────────────────────────────────────────

/// Trade value, in gold, of a bulk resource (wood, stone): 10 → 1. What barter and
/// the shop price against; a SALE pays a thousandth of it ([kSellPayoutFactor]).
const double kBasicSellRate = 0.1;

/// Gold per unit of a special resource (fish, meat, and whatever later eras
/// add). Worth ~3.5× a log because goods are scarce AND have a real sink —
/// healing. Selling them is meant to be a genuine trade-off, not free money.
const double kGoodsSellRate = 0.35;

/// What one unit of [resource] is WORTH, in gold, when it is traded — the
/// relative value that goods↔goods barter and buying goods with gold are priced
/// on. Gold itself is untradeable.
///
/// This is NOT what selling pays out (see [sellPayoutRate]): since 2026-09-22 a
/// sale pays only a thousandth of it, so a resource is worth its full value to
/// trade with and next to nothing to dump for gold.
///
/// Derived, never a per-resource table: era-scoped goods all price the same, so
/// a resource a later era introduces trades the day it appears with no change
/// here (see goods_definitions.dart).
double sellRate(String resource) {
  if (resource == 'gold') return 0;
  if (kGoodsDefs.containsKey(resource)) return kGoodsSellRate;
  return kBasicSellRate;
}

/// How much of a resource's trade value a SALE pays out (user 2026-09-22: "Holz
/// und Stein etc. können zu noch viel schlechteren Preisen verkauft werden, bsp.
/// 10000 für 1 Gold"). 1/1000: wood and stone go for 10 000 → 🪙 1, a special
/// resource for about 2 900 → 🪙 1.
///
/// The point is that gold must be WORTH something. Turning surplus into gold used
/// to be the easy way to get it (a day of wood ≈ 85 gold); now selling is a
/// drain for stock you cannot store, and gold comes from where it is EARNED —
/// daily goals, expeditions, the gold mine. Trading and buying keep the old
/// values ([sellRate]), so barter and the shop are unchanged.
const double kSellPayoutFactor = 0.001;

/// Gold per unit when SELLING [resource] for gold — [sellRate] cut down by
/// [kSellPayoutFactor].
double sellPayoutRate(String resource) =>
    sellRate(resource) * kSellPayoutFactor;

/// Gold from selling [amount] of [resource]. Floors: selling must never invent
/// a fraction of a coin.
int sellValue(String resource, double amount) =>
    (amount * sellPayoutRate(resource) + 1e-9).floor();

/// The smallest amount of [resource] worth selling — below this it rounds to 0
/// gold and would silently eat the resources.
double minSellable(String resource) {
  final rate = sellPayoutRate(resource);
  return rate <= 0 ? double.infinity : (1 / rate).ceilToDouble();
}

// ── Buying time ─────────────────────────────────────────────

/// Seconds of waiting one gold removes.
///
/// 1 gold ≈ 6 seconds, so a minute costs 10 gold and an hour 600 (user
/// 2026-09-22: "die Zeit abzukürzen ist viel viel teurer als jetzt" — it was 1
/// gold a minute). Gold is EARNED (daily goals and their chest, expeditions, the
/// gold mine), not bought with surplus any more — see [kSellPayoutFactor] — and
/// it is spent on the waits that matter: a day's worth of gold buys a quarter of an
/// hour, not an evening.
const double kSecondsPerGold = 6;

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
