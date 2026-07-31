import 'dart:math' as math;

import '../../settlement/data/gather_defs.dart';
import '../models/area.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../../../core/tuning/game_tuning.dart';

// Pure, unit-tested math for gather expeditions (see
// [[expedition-overworld-redesign]]). Keeps the balance in one place and off
// the controller/UI so it can be tested without Supabase.
//
// Model (per the confirmed design): the group's summed GATHER stat sets the
// mining speed, the group's summed CARRY stat caps how much a single trip can
// haul, and a trip returns as soon as the load is full (or the spot runs dry).

/// Travel overhead added to every trip, per area danger level (each way folded
/// in). Keeps far/dangerous areas slower even for a quick haul.
/// PROVISIONAL: halved 600→300 after the first playtest.
double get kTravelSecondsPerDanger =>
    GameTuning.i.raw(Dials.travelSecondsPerDanger);

/// Hard ceiling so a viable trip with a near-zero rate can't compute an
/// absurd duration (defensive — the UI blocks sending a non-viable group).
int get kMaxTripSeconds => GameTuning.i.raw(Dials.maxTripSeconds).round();

/// What a member contributes to mining, whatever the resource is.
///
/// ONE stat for every spot since 2026-07-25 (was woodcutting / mining /
/// prospecting / luxuryProduction — four names for the same gesture, all of
/// them era-I trades). How hard a given resource is to get out of the ground
/// lives in its dials instead (gather_defs.dart's secondsPerUnitPerStat), which
/// is the number that actually differs between wood and gold.
int gatherPowerOf(CreatureInstance c) => c.statValue(CreatureStat.gathering);

class GatherPlan {
  final String resource;

  /// Units mined per hour by the whole group at this spot.
  final double ratePerHour;

  /// Group carry capacity (max haul for one trip).
  final double loadCap;

  /// Units this trip actually hauls — min(loadCap, availableStock).
  final double amount;

  /// Mining time + travel overhead.
  final Duration duration;

  const GatherPlan({
    required this.resource,
    required this.ratePerHour,
    required this.loadCap,
    required this.amount,
    required this.duration,
  });

  /// A group can only gather if it produces some rate and there's something to
  /// haul (non-zero carry and non-empty spot).
  bool get isViable => ratePerHour > 0 && amount > 0;
}

/// Projects a gather trip for [members] at [spot] in [area], given the spot's
/// currently-available [availableStock].
/// [timeScale] shortens the whole trip (mining + travel) — 1.0 is the balanced
/// default; the new-player jumpstart passes kJumpstartTimeScale. Kept as a
/// caller-supplied scalar so this stays pure and so the balanced values above
/// are never themselves rewritten for the tutorial (docs/balancing.md §6).
/// [carryMult]/[travelMult] are the settlement's expedition amplifiers
/// (warehouses raise the group's load cap, scout posts cut travel — see
/// SettlementController.expeditionBonuses). Caller-supplied scalars defaulting
/// to 1.0, same convention as [timeScale], so this stays pure and testable.
GatherPlan planGather({
  required AreaDef area,
  required ResourceSpotDef spot,
  required List<CreatureInstance> members,
  required double availableStock,
  double timeScale = 1.0,
  double carryMult = 1.0,
  double travelMult = 1.0,
}) {
  // Every per-resource number comes from the dials (user 2026-07-25): how much
  // one carry point holds and how long one stat point needs per unit. That is
  // what makes bulk worth a trip while a luxury run stays a handful.
  final dials = gatherDefFor(spot.resource);
  final gatherPower = members.fold<int>(0, (sum, c) => sum + gatherPowerOf(c));
  final carryPoints =
      members.fold<int>(0, (sum, c) => sum + c.statValue(CreatureStat.carry));
  final loadCap = dials.loadCap(carryPoints) * carryMult;

  final ratePerHour = dials.ratePerHour(gatherPower);
  final amount = math.min(loadCap, math.max(0.0, availableStock));

  final travel = kTravelSecondsPerDanger * area.dangerLevel * travelMult;
  final miningSeconds = (ratePerHour > 0 && amount > 0)
      ? (amount / ratePerHour) * 3600.0
      : 0.0;
  final total = ((miningSeconds + travel) * timeScale).round().clamp(
    0,
    kMaxTripSeconds,
  );

  return GatherPlan(
    resource: spot.resource,
    ratePerHour: ratePerHour,
    loadCap: loadCap,
    amount: amount,
    duration: Duration(seconds: total),
  );
}
