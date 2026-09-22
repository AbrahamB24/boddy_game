import '../data/building_definitions.dart'
    show
        energyMultiplierForPercent,
        kEnergyDrainPerHour,
        kEnergyMaxPercent,
        kEnergyStartPercent;

/// Energy is a POOL again (user 2026-09-20: "Energie wieder direktes Feedback"):
/// walking fills it, time empties it. [energyPct] is what is in it, 0 – 125
/// (100 = the settlement runs at its full rate); it falls by
/// [kEnergyDrainPerHour] every real hour and rises when steps are credited —
/// see energyAfterSteps / energyDrain in building_definitions.dart for the exact
/// rules, and GameEngine.tick / GameEngine.addSteps, the only two writers.
///
/// It replaced the 2026-09-14 daily-steps formula (a rate read straight off
/// "steps since midnight"), which gave no feedback: a step changed nothing you
/// could see until the day's total crossed a line. [stepsToday] is still kept,
/// but only as a readout ("N steps today") — it no longer decides anything.
class EnergyModel {
  final String settlementId;

  /// What is in the pool, in percent, as of [lastUpdatedAt] — the tick drains it
  /// forward from there.
  final double energyPct;

  /// Steps credited since [stepsDayKey]'s midnight (LOCAL day — steps are a
  /// real-world, local-clock concept, unlike the settlement's own UTC-keyed
  /// daily tasks). Display only.
  final int stepsToday;

  /// The Y-M-D key [stepsToday] was counted against — '' for a row that has
  /// never taken a step, which reads as an always-stale day.
  final String stepsDayKey;

  final DateTime lastUpdatedAt;

  const EnergyModel({
    required this.settlementId,
    this.energyPct = kEnergyStartPercent,
    this.stepsToday = 0,
    this.stepsDayKey = '',
    required this.lastUpdatedAt,
  });

  factory EnergyModel.fromMap(Map<String, dynamic> m) => EnergyModel(
    settlementId: m['settlement_id'] as String,
    // A row from before the pool existed has no `energy_pct` (migration 0056
    // gives it one): it starts full, the same as a new settlement.
    energyPct: (m['energy_pct'] as num?)?.toDouble() ?? kEnergyStartPercent,
    // Pre-migration rows have neither step column yet — reads as day 0 of a new
    // settlement, not a crash.
    stepsToday: (m['steps_today'] as num?)?.toInt() ?? 0,
    stepsDayKey: m['steps_day_key'] as String? ?? '',
    lastUpdatedAt: DateTime.parse(m['last_updated_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'settlement_id': settlementId,
    'energy_pct': energyPct,
    'steps_today': stepsToday,
    'steps_day_key': stepsDayKey,
    'last_updated_at': lastUpdatedAt.toIso8601String(),
  };

  EnergyModel copyWith({
    double? energyPct,
    int? stepsToday,
    String? stepsDayKey,
    DateTime? lastUpdatedAt,
  }) => EnergyModel(
    settlementId: settlementId,
    energyPct: energyPct ?? this.energyPct,
    stepsToday: stepsToday ?? this.stepsToday,
    stepsDayKey: stepsDayKey ?? this.stepsDayKey,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
  );

  /// THE rate every production/construction/etc. figure multiplies by — the
  /// pool's own fraction (1.0 at 100 %, 1.25 at the ceiling), never below the
  /// floor. See [energyMultiplierForPercent].
  double get multiplier => energyMultiplierForPercent(energyPct);

  /// The pool as a 0–125 percentage, for display.
  double get percent => energyPct.clamp(0.0, kEnergyMaxPercent);

  /// Whether the pool is at its ceiling — steps walked now are lost.
  bool get isFull => percent >= kEnergyMaxPercent - 1e-9;

  /// Whether the pool is empty (the settlement is running at the floor rate).
  bool get isEmpty => percent <= 0;

  /// Real hours until the pool is empty, at the steady drain and with no more
  /// steps — the figure a player can plan a walk around.
  double get hoursLeft => kEnergyDrainPerHour <= 0
      ? double.infinity
      : percent / kEnergyDrainPerHour;
}
