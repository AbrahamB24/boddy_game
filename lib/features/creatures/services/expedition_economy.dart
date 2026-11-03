import '../models/area.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import 'capture_math.dart';
import '../../settlement/data/gather_defs.dart';
import 'gather_math.dart';

// Pure per-day estimators for the EXPEDITION economy — the balance
// simulator's counterpart to BalanceSimulator (buildings). Checked against
// the targets in docs/balancing.md (~60% of income should come from here).
//
// Deliberately built ON TOP of the real trip math (planGather, perilRatio,
// groupCatchPower) via synthetic creatures instead of re-deriving formulas,
// so these numbers can't silently drift from what the game actually does.
// Simplifications (documented, fine for balancing): every trip starts at
// full spot stock (real depletion makes later trips smaller), the gather
// player re-dispatches after [reactionHours], and the capture estimator
// assumes a fixed steps/day rate ([kAssumedStepsPerDay]) since hunts run on
// real steps now and a day-rate simulator can't observe those.

/// A stand-in creature with exact stats (level 1, growth 0) so estimators can
/// feed the real group math. One synthetic carrying the GROUP's summed stats
/// is equivalent to the group itself for every Σ-based formula.
CreatureInstance syntheticCreature(
  Map<CreatureStat, double> stats, {
  String id = 'synthetic',
}) => CreatureInstance(
  id: id,
  userId: 'balance',
  speciesId: 'synthetic',
  gender: CreatureGender.male,
  statBase: {
    // Zero out everything not given — statValue defaults absent stats to 10,
    // which would smuggle phantom power into the estimate.
    for (final s in CreatureStat.values) s: 0,
    ...stats,
  },
  statSlope: const {},
);

// ── Gathering ───────────────────────────────────────────────

class GatherDayEstimate {
  final Duration tripDuration;

  /// Haul of one trip at full stock (carry- and capacity-capped).
  final double haulPerTrip;

  /// Trips one dedicated slot manages per 24h, including re-dispatch delay.
  final double tripsPerDay;

  /// Day-1 ceiling: stored stock + a day's regen, capped by trip throughput.
  final double burstDayYield;

  /// Steady-state yield/day once the spot is farmed continuously — capped by
  /// what the spot regenerates, however fast the group hauls.
  final double sustainableYield;

  const GatherDayEstimate({
    required this.tripDuration,
    required this.haulPerTrip,
    required this.tripsPerDay,
    required this.burstDayYield,
    required this.sustainableYield,
  });
}

GatherDayEstimate estimateGatherDay({
  required AreaDef area,
  required ResourceSpotDef spot,
  required List<CreatureInstance> members,
  double reactionHours = 1,
}) {
  // Capacity / regen come from the resource dials now (Dev Mode → Resources),
  // not from the spot.
  final dials = gatherDefFor(spot.resource);
  final plan = planGather(
    area: area,
    spot: spot,
    members: members,
    availableStock: dials.spotCapacity,
  );
  final tripHours = plan.duration.inSeconds / 3600.0;
  final cycleHours = tripHours + reactionHours;
  final tripsPerDay = plan.isViable && cycleHours > 0 ? 24 / cycleHours : 0.0;
  final demandPerDay = plan.amount * tripsPerDay;
  final regenPerDay = dials.regenPerHour * 24;
  return GatherDayEstimate(
    tripDuration: plan.duration,
    haulPerTrip: plan.amount,
    tripsPerDay: tripsPerDay,
    burstDayYield: demandPerDay.clamp(0, dials.spotCapacity + regenPerDay),
    sustainableYield: demandPerDay.clamp(0, regenPerDay),
  );
}

// ── Capturing ───────────────────────────────────────────────

/// Assumed real-world steps a player walks in a day — for THIS ESTIMATOR
/// only (user 2026-10-02: hunts moved from a wall clock to real steps,
/// which a pure day-rate simulator has no way to observe by itself). Never
/// used to gate or pace anything live; tune freely without touching
/// gameplay.
const double kAssumedStepsPerDay = 6000;

class CaptureDayEstimate {
  final int huntSteps;
  final double huntsPerDay;
  final double findsPerDay;

  /// findsPerDay × assumed QTE success rate.
  final double catchesPerDay;

  const CaptureDayEstimate({
    required this.huntSteps,
    required this.huntsPerDay,
    required this.findsPerDay,
    required this.catchesPerDay,
  });
}

CaptureDayEstimate estimateCaptureDay({
  required CaptureHuntOption option,
  double qteSuccess = 0.85,
}) {
  final huntsPerDay = option.steps > 0
      ? kAssumedStepsPerDay / option.steps
      : 0.0;
  final findsPerDay = huntsPerDay * option.finds;
  return CaptureDayEstimate(
    huntSteps: option.steps,
    huntsPerDay: huntsPerDay,
    findsPerDay: findsPerDay,
    catchesPerDay: findsPerDay * qteSuccess.clamp(0.0, 1.0),
  );
}
