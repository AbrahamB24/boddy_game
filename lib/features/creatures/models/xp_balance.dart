import 'dart:math' as math;

/// Dev-authorable XP tuning for MONSTERS (user 2026-07-26: a Species-Budget tab
/// for the XP). Everything that decides how fast a monster levels lives here:
/// the requirement curve, the two passive earn rates, and the per-era catch-up
/// multiplier.
///
/// Deliberately NOT part of [SpeciesBalance]: those are per-RARITY budgets,
/// these are global rates. It gets its own `game_config` row ('xp_balance') and
/// its own live global, [kXpBalance], which every reader in creature_enums.dart
/// consults — so a saved change takes effect without a restart.
class XpConfig {
  /// The requirement curve: XP from [level] to level+1 = factor · level^exponent
  /// (historically 6 · L^2.5). Raising the exponent steepens the late game;
  /// raising the factor slows every level evenly.
  final double curveFactor;
  final double curveExponent;

  /// XP/h in a Training-Grounds role. A trainee produces nothing, so this is
  /// paid for in economy output.
  final double trainingPerHour;

  /// XP/h a monster earns for HOLDING A POST — in any building that stations
  /// monsters at all (user 2026-07-30: "Jedes Gebäude, welches Monster
  /// «anstellt» soll EP geben. Jedes Gebäude gibt genau gleich viel EP").
  ///
  /// ONE number for every building, deliberately: it used to be a per-building
  /// `xp` effect, which meant ~40 of the ~50 buildings with work posts simply
  /// never paid anything (the effect was authored on eleven era-I buildings and
  /// nowhere else), and the eleven that did could drift apart in Dev Mode. A
  /// single rate cannot do either.
  ///
  /// Work is NOT the primary way to level (user 2026-07-30: "Primäre EP Quelle
  /// soll der Kampf sein oder das Training") — hence 10/h against the Training
  /// Grounds' 250/h and the kill curve. It is the trickle a working settlement
  /// pays, not a route.
  final double workPerHour;

  /// Per-BUILDING-LEVEL growth of [workPerHour]: the rate at building level L is
  /// `workPerHour × workLevelGrowth^(L−1)`.
  ///
  /// Weak on purpose (user 2026-07-30: "wächst mit level, aber nicht sehr
  /// stark") — +5 %/level is ×1.6 at L10 and ×2.9 at L24, where the buildings'
  /// own +50 %/level output curve is ×12 and ×8000. A fully upgraded workshop
  /// pays a little better; it never becomes the way you level.
  final double workLevelGrowth;

  /// XP a DEFEATED monster is worth: factor · level^exponent, summed over the
  /// enemy team and then split across the winning party (user 2026-07-26 —
  /// "wieviel xp besiegte Monster geben nach Stufe"). Historically 9 · L^2.3.
  final double killFactor;
  final double killExponent;

  /// A boss is worth this many times its level's normal kill XP.
  final double bossMultiplier;

  const XpConfig({
    this.curveFactor = 6.0,
    this.curveExponent = 2.5,
    this.trainingPerHour = 250.0,
    this.workPerHour = 10.0,
    this.workLevelGrowth = 1.05,
    this.killFactor = 9.0,
    // Taken over from the author's live config on 2026-07-29 (the 📋 export).
    // The exponent was 2.3 and the boss factor 6: kill XP then outran the
    // 6·L^2.5 requirement curve badly at low level and fell behind at high
    // level. At 1.3 the reward grows far slower than the requirement, so
    // levelling stays a climb rather than a snowball, and a boss is worth 3
    // normal kills instead of 6.
    this.killExponent = 1.3,
    this.bossMultiplier = 3.0,
  });

  /// XP needed to advance FROM [level] to level+1. Never below 1, so a curve
  /// authored down to nothing can't produce an infinite level-up loop.
  int xpToNext(int level) =>
      math.max(1, (curveFactor * math.pow(level, curveExponent)).round());

  /// XP/h a post in a building of [buildingLevel] pays. Every building that
  /// stations monsters pays exactly this — see [workPerHour].
  double workXpAt(int buildingLevel) =>
      workPerHour * math.pow(workLevelGrowth, math.max(0, buildingLevel - 1));

  /// Hours at [ratePerHour] to get from [level] to level+1 — what makes a bare
  /// "+250 XP/h" honest in the UI.
  double hoursToNextLevel(int level, double ratePerHour) =>
      ratePerHour <= 0 ? double.infinity : xpToNext(level) / ratePerHour;

  /// XP one defeated monster of [level] is worth, before the split across the
  /// winning party. A boss pays [bossMultiplier] times that.
  double killXp(int level, {bool boss = false}) {
    final base = killFactor * math.pow(math.max(1, level), killExponent);
    return boss ? base * bossMultiplier : base.toDouble();
  }

  XpConfig copyWith({
    double? curveFactor,
    double? curveExponent,
    double? trainingPerHour,
    double? workPerHour,
    double? workLevelGrowth,
    double? killFactor,
    double? killExponent,
    double? bossMultiplier,
  }) => XpConfig(
    curveFactor: curveFactor ?? this.curveFactor,
    curveExponent: curveExponent ?? this.curveExponent,
    trainingPerHour: trainingPerHour ?? this.trainingPerHour,
    workPerHour: workPerHour ?? this.workPerHour,
    workLevelGrowth: workLevelGrowth ?? this.workLevelGrowth,
    killFactor: killFactor ?? this.killFactor,
    killExponent: killExponent ?? this.killExponent,
    bossMultiplier: bossMultiplier ?? this.bossMultiplier,
  );

  Map<String, dynamic> toJson() => {
    'curveFactor': curveFactor,
    'curveExponent': curveExponent,
    'trainingPerHour': trainingPerHour,
    'workPerHour': workPerHour,
    'workLevelGrowth': workLevelGrowth,
    'killFactor': killFactor,
    'killExponent': killExponent,
    'bossMultiplier': bossMultiplier,
  };

  factory XpConfig.fromJson(Map<String, dynamic> j) {
    const def = XpConfig();
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    return XpConfig(
      curveFactor: d('curveFactor', def.curveFactor),
      curveExponent: d('curveExponent', def.curveExponent),
      trainingPerHour: d('trainingPerHour', def.trainingPerHour),
      workPerHour: d('workPerHour', def.workPerHour),
      workLevelGrowth: d('workLevelGrowth', def.workLevelGrowth),
      killFactor: d('killFactor', def.killFactor),
      killExponent: d('killExponent', def.killExponent),
      bossMultiplier: d('bossMultiplier', def.bossMultiplier),
    );
  }
}

/// The LIVE XP config every reader consults. Replaced in place on load
/// (CreatureDefsController) / on save (the Species-Budget screen).
XpConfig kXpBalance = const XpConfig();
