import 'dart:math' as math;

import '../../../core/tuning/game_tuning.dart';

/// Every formula of the legendary lairs in one place (user 2026-11-07). The
/// numbers are all Dials (Dev Mode → Monster → Legendäre) — nothing here is a
/// gameplay constant.
///
/// The shape is ASYMPTOTIC on purpose: a legendary has no level cap, but each
/// level closes only a part of the gap to a maximum, so a very high level is
/// prestige rather than power creep.
class LegendaryMath {
  LegendaryMath._();

  static double get _q => GameTuning.i.raw(Dials.lairQ).clamp(0.01, 0.999);

  /// How close to its maximum a legendary at [level] is: 0 at level 1, → 1.
  static double approach(int level) =>
      1 - math.pow(_q, (level - 1).clamp(0, 100000)).toDouble();

  /// The level a NORMAL monster would need for the same stats — a legendary's
  /// stat is `base + slope × (this − 1)`.
  static double equivalentLevel(int level) =>
      1 + GameTuning.i.raw(Dials.lairMaxEquivLevels) * approach(level);

  /// How much faster ONE trainer of [trainerLevel] makes an upgrade, given the
  /// species' own [trainerPower] (0 for a lesser creature). Added up over the
  /// five slots: the upgrade runs at `1 + Σ`.
  static double trainerEffect(double trainerPower, int trainerLevel) =>
      trainerPower *
      (1 - math.pow(_q, trainerLevel).toDouble()) *
      GameTuning.i.raw(Dials.lairTrainerScale);

  /// The rest after every battle: [Dials.lairCooldownMaxHours] at level 1,
  /// shrinking toward [Dials.lairCooldownMinHours].
  static Duration cooldownAt(int level) {
    final hi = GameTuning.i.raw(Dials.lairCooldownMaxHours);
    final lo = GameTuning.i.raw(Dials.lairCooldownMinHours);
    final hours = lo + (hi - lo) * (1 - approach(level));
    return Duration(seconds: (hours * 3600).round());
  }

  /// Seconds an upgrade FROM [level] takes with no trainer at all.
  static double workSeconds(int level) =>
      GameTuning.i.raw(Dials.lairBaseDays) *
      86400 *
      math.pow(GameTuning.i.raw(Dials.lairTimeGrowth), level - 1).toDouble();

  /// Luxury goods (of the species' region) an upgrade FROM [level] costs.
  static double luxuryCost(int level) =>
      (GameTuning.i.raw(Dials.lairCostBase) *
              math.pow(GameTuning.i.raw(Dials.lairCostGrowth), level - 1))
          .roundToDouble();

  /// Gold an upgrade FROM [level] costs — it goes to the trainers too.
  static double goldCost(int level) =>
      (GameTuning.i.raw(Dials.lairGoldBase) *
              math.pow(GameTuning.i.raw(Dials.lairCostGrowth), level - 1))
          .roundToDouble();

  /// The five reward shares, in join order (1st trainer first).
  static List<double> get shares => [
    GameTuning.i.raw(Dials.lairShare1),
    GameTuning.i.raw(Dials.lairShare2),
    GameTuning.i.raw(Dials.lairShare3),
    GameTuning.i.raw(Dials.lairShare4),
    GameTuning.i.raw(Dials.lairShare5),
  ];

  static const int maxTrainers = 5;
}
