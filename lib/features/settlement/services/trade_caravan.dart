import 'dart:math' as math;

import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/creature_instance.dart';
import '../data/gather_defs.dart';

// ── The trade caravan (user 2026-07-26) ────────────────────────────────────
//
// "Sobald ich einen trade auswähle, sende ich eine Expedition. Die Zeitdauer
// ist abhängig vom Wert speed, und die maximale Ladekapazität von carry.
// Handelspreise werden durch Trade beeinflusst."
//
// So a trade is no longer a button that resolves over the counter — it is a
// trip, and the three stats each own exactly one of its numbers:
//
//   speed  → how long the caravan is away        (this file)
//   carry  → how much cargo fits in it           (this file)
//   trade  → what the goods are worth            (NOT here: prices stay the
//            Trade Center's business — building level + posted traders, see
//            SettlementController.tradeDiscount. User decision 2026-07-26.)
//
// Pure math, no controller and no widgets, so the sheet's preview and the
// controller's send can never quote different numbers.

/// How long a caravan is away with NOBODY fast in it — the full, uncut trip.
/// Every real caravan is faster; this is the ceiling the speed curve eats into.
const double kTradeBaseHours = 2.0;

/// Summed `speed` that halves the trip. Same shape and the same reason as
/// [buildTimeCut] / [breedingTimeCut]: diminishing, but with NO ceiling, so a
/// faster caravan is always worth building and the trip never reaches zero.
///   100 → −50 %, 400 → −80 %, 900 → −90 %
const double kTradeSpeedForHalfTime = 100.0;

/// Hard ceiling on a single trip, so a caravan of near-zero speed can't quote
/// an absurd wait (defensive — [kTradeBaseHours] already bounds it in practice).
const int kMaxTradeTripSeconds = 24 * 3600;

/// Fraction of [kTradeBaseHours] that [speedPoints] removes.
double tradeTimeCut(double speedPoints) =>
    speedPoints <= 0 ? 0 : speedPoints / (speedPoints + kTradeSpeedForHalfTime);

/// Summed travel stat of a caravan.
int caravanSpeed(List<CreatureInstance> members) =>
    members.fold(0, (sum, c) => sum + c.statValue(CreatureStat.speed));

/// Summed hauling stat of a caravan.
int caravanCarry(List<CreatureInstance> members) =>
    members.fold(0, (sum, c) => sum + c.statValue(CreatureStat.carry));

/// How long [members] need for one round trip.
///
/// [travelMult] is the settlement's scout-post amplifier and [timeScale] the
/// tutorial's jumpstart — caller-supplied scalars, same convention as
/// [planGather], so this stays pure and the balanced constants above are never
/// themselves rewritten for the tutorial.
Duration tradeTripDuration(
  List<CreatureInstance> members, {
  double travelMult = 1.0,
  double timeScale = 1.0,
}) {
  final hours =
      kTradeBaseHours * (1 - tradeTimeCut(caravanSpeed(members).toDouble()));
  final seconds = (hours * 3600 * travelMult * timeScale).round();
  return Duration(seconds: seconds.clamp(0, kMaxTradeTripSeconds));
}

/// How many units of [resource] a caravan of [members] can haul.
///
/// Read through the SAME per-resource dial a gather trip uses
/// (`unitsPerCarry`), because it answers the same question: how much of this
/// particular thing fits on one monster's back. A caravan hauling logs is
/// therefore worth far more units than one hauling gold, exactly as a mining
/// trip is.
///
/// [carryMult] is the settlement's warehouse amplifier.
double tradeCapacity(
  String resource,
  List<CreatureInstance> members, {
  double carryMult = 1.0,
}) =>
    gatherDefFor(resource).loadCap(caravanCarry(members)) * carryMult;

/// The most of [resource] this caravan may take on, given the [available]
/// stock. Floors to whole units — a caravan can't carry 3.7 fish.
double maxTradeAmount(
  String resource,
  List<CreatureInstance> members,
  double available, {
  double carryMult = 1.0,
}) {
  final cap = tradeCapacity(resource, members, carryMult: carryMult);
  return math.max(0, math.min(cap, available)).floorToDouble();
}

/// The largest barter input a caravan may take on, bounded by BOTH legs.
///
/// A barter loads goods out and goods back, so the cargo hold has to cover the
/// heavier of the two. Capping only the outbound leg would let a caravan
/// promise a return it cannot physically haul (100 logs out is nothing, 100
/// gold back is a full load).
///
/// [yieldPerUnit] is how many units of [to] one unit of [from] fetches — the
/// caller's rate, so this file stays out of the pricing business.
double maxBarterInput({
  required String from,
  required String to,
  required double available,
  required double yieldPerUnit,
  required List<CreatureInstance> members,
  double carryMult = 1.0,
}) {
  final out = maxTradeAmount(from, members, available, carryMult: carryMult);
  if (yieldPerUnit <= 0) return out;
  final backCap = tradeCapacity(to, members, carryMult: carryMult);
  return math.min(out, backCap / yieldPerUnit).floorToDouble();
}

/// Whether a caravan can be sent at all: somebody has to carry something.
///
/// Speed 0 is legal (the trip just takes the full [kTradeBaseHours]); carry 0
/// is not, because the caravan would arrive empty and the trade would be a
/// pure waiting tax.
bool caravanCanHaul(List<CreatureInstance> members) =>
    members.isNotEmpty && caravanCarry(members) > 0;
