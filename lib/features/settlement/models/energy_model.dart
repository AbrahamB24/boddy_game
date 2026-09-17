import '../data/building_definitions.dart' show energyMultiplierForSteps;

/// Energy is a DAILY STEPS FORMULA now (user 2026-09-14), not a draining
/// pool — [stepsToday] is simply how many steps have been credited since
/// [stepsDayKey]'s midnight, reset the moment a new day starts (see
/// GameEngine.tick / GameEngine.addSteps, the only two writers of both
/// fields). There is no more "current energy that runs out over time": the
/// [multiplier] getter recomputes fresh from [stepsToday] on every read, so
/// closing the app overnight without walking simply means tomorrow starts
/// back at the floor rate, the same as any other zero-step day would.
class EnergyModel {
  final String settlementId;

  /// Steps credited since [stepsDayKey]'s midnight (LOCAL day — steps are a
  /// real-world, local-clock concept, unlike the settlement's own UTC-keyed
  /// daily tasks).
  final int stepsToday;

  /// The Y-M-D key [stepsToday] was counted against — '' for a pre-migration
  /// row or a settlement that has never taken a step yet, which reads as an
  /// always-stale day (any real day key rolls it over to 0 on first credit).
  final String stepsDayKey;

  final DateTime lastUpdatedAt;

  const EnergyModel({
    required this.settlementId,
    this.stepsToday = 0,
    this.stepsDayKey = '',
    required this.lastUpdatedAt,
  });

  factory EnergyModel.fromMap(Map<String, dynamic> m) => EnergyModel(
    settlementId: m['settlement_id'] as String,
    // Pre-migration rows have neither column yet — reads as day 0 of a new
    // settlement, not a crash.
    stepsToday: (m['steps_today'] as num?)?.toInt() ?? 0,
    stepsDayKey: m['steps_day_key'] as String? ?? '',
    lastUpdatedAt: DateTime.parse(m['last_updated_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'settlement_id': settlementId,
    'steps_today': stepsToday,
    'steps_day_key': stepsDayKey,
    'last_updated_at': lastUpdatedAt.toIso8601String(),
  };

  EnergyModel copyWith({
    int? stepsToday,
    String? stepsDayKey,
    DateTime? lastUpdatedAt,
  }) => EnergyModel(
    settlementId: settlementId,
    stepsToday: stepsToday ?? this.stepsToday,
    stepsDayKey: stepsDayKey ?? this.stepsDayKey,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
  );

  /// THE rate every production/construction/etc. figure multiplies by —
  /// 1.0 at the daily step target, ramping down to a floor at 0 steps and
  /// up to a capped bonus past it. See [energyMultiplierForSteps].
  double get multiplier => energyMultiplierForSteps(stepsToday);

  /// [multiplier] as a 0–125-ish percentage, for display.
  double get percent => multiplier * 100.0;
}
