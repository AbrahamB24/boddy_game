/// Dev-authorable HEALING tuning that is NOT per rarity (user 2026-07-26).
///
/// The two prices themselves — seconds and goods per missing HP — live in
/// [RarityConfig], because a legendary's recovery is meant to differ from a
/// common's ("die Seltenheitsstufen haben unterschiedliche Heildauern"). What
/// is left here applies to every monster alike.
///
/// Same contract as [XpConfig]: its own `game_config` row ('heal_balance'), its
/// own live global [kHealBalance], read through services/healing_cost.dart so a
/// saved change takes effect at once.
///
/// What it does NOT decide is WHICH goods are billed: those are the luxury
/// supplies of the MONSTER's own era (its species tier) — see healCost.
class HealConfig {
  /// Multiplier on a K.O.'d creature's heal — BOTH its price and its duration.
  /// 1.0 makes fainting cost exactly as much as surviving on 1 HP, so there
  /// would be no reason to ever retreat.
  final double koMultiplier;

  const HealConfig({this.koMultiplier = 2.0});

  HealConfig copyWith({double? koMultiplier}) =>
      HealConfig(koMultiplier: koMultiplier ?? this.koMultiplier);

  Map<String, dynamic> toJson() => {'koMultiplier': koMultiplier};

  factory HealConfig.fromJson(Map<String, dynamic> j) => HealConfig(
    koMultiplier:
        (j['koMultiplier'] as num?)?.toDouble() ?? const HealConfig().koMultiplier,
  );
}

/// The LIVE healing config every reader consults. Replaced in place on load
/// (CreatureDefsController) / on save (the Species-Budget screen).
HealConfig kHealBalance = const HealConfig();
