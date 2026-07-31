import 'dart:math' as math;

import '../models/creature_enums.dart';
import '../models/species_balance.dart';
import '../models/species_def.dart';

// Stat-budget validator (balancing tool 3) — audits a species' stat curves
// against the docs/balancing.md §3 framework: every species spends the SAME
// budget (rarity grants a flat, deliberate bump), archetypes only shift how
// it's distributed. The species editor shows this audit live so content is
// balanced at authoring time instead of discovered broken in play.

/// Default combat/work SPLIT anchors (a ratio, not absolute totals any more):
/// a species' base budget defaults to combat:work = 180:190. Combat dropped
/// 240 → 180 when `energy` left and `catchRate` moved out (user 2026-07-17);
/// non-combat rose 160 → 190 to absorb `catchRate`. The combat archetype
/// weights sum to [kCombatBudgetTarget], so they're relative and get scaled to
/// whatever the actual combat base works out to.
const double kCombatBudgetTarget = 180;
const double kNonCombatBudgetTarget = 190;

/// The default combat FRACTION of the base/growth budget (180 / 370).
const double kDefaultCombatShare =
    kCombatBudgetTarget / (kCombatBudgetTarget + kNonCombatBudgetTarget);

/// Growth per level as a fraction of the base budget (linear). The user's
/// per-rarity growth totals (9/10/11/12/13) are exactly base ÷ 30, so the rate
/// is a flat 1/30 across every rarity.
const double kGrowthPerLevelTarget = 1 / 30;

/// The automatic per-evolution-stage base bump (see the species editor's "Auto
/// Evo-Sprung"). Evolving raises each stat's socket by this fraction per stage
/// — S2 = S1·(1+p), S3 = S1·(1+p)² — while growth is unchanged. THE one source
/// both the editor toggle and the dev "re-roll all" action read.
const double kEvoBumpPct = 0.25;

/// Returns [stats] with the standard multiplicative evolution bump applied to
/// every stat's stage-2/3 base (the archetype distribution is preserved, since
/// every stage scales from the same stage-0 base). Growth is left untouched.
Map<CreatureStat, StatCurve> withEvoBumps(
  Map<CreatureStat, StatCurve> stats, {
  double pct = kEvoBumpPct,
}) => {
  for (final e in stats.entries)
    e.key: StatCurve(
      stageBase: [
        e.value.stageBase[0],
        e.value.stageBase[0] * (1 + pct),
        e.value.stageBase[0] * (1 + pct) * (1 + pct),
      ],
      growth: e.value.growth,
    ),
};

/// Allowed relative deviation before a line is flagged.
const double kBudgetTolerance = 0.10;

/// TOTAL base budget a species spends, by rarity — the TIER-1 spec. Rarer =
/// slightly more points, a flat +10 per step (user 2026-07-17: "seltene nur ein
/// bisschen besser" — the spread was DELIBERATELY compressed 270→310 from the
/// earlier 270→390, so almost every monster stays useful). Growth = base ÷ 30
/// (see kGrowthPerLevelTarget). Tier 2+ gets its own numbers later; until then
/// every tier uses these tier-1 values (no ×multiplier region-gate).
///
/// ⚠️ Power scales ~cubically with the base (a bigger budget raises HP, attack,
/// defense AND speed at once), so even this tight 1.15× legendary/common spread
/// is ~1.5× combat power. Re-run the combat Monte-Carlo (⚗️ Combat Lab) after
/// ANY change here.
const Map<CreatureRarity, double> kBaseBudgetByRarity = {
  // Compressed AGAIN (user 2026-07-22: "die Unterschiede sollen nicht so
  // gross sein"): +5 per step, was +10. Legendary/common is now 1.074× budget
  // ≈ ~1.24× combat power under the cubic law — rarity is flavour and a catch
  // trophy, level is the power axis.
  CreatureRarity.common: 270,
  CreatureRarity.uncommon: 275,
  CreatureRarity.rare: 280,
  CreatureRarity.epic: 285,
  CreatureRarity.legendary: 290,
};

// ── Archetypes (docs/balancing.md §3) ───────────────────────
// Every species spends the SAME budget for its rarity/tier — archetypes only
// decide HOW it's split. That's what makes species differ meaningfully
// ("Spezialisten"): a Carrier hauls 4× what a generalist does, a Scholar
// out-researches everyone, a Tank soaks hits — none of them is stronger
// overall. The species editor applies these; the Monte-Carlo builds standard
// combatants from the combat table.

/// Combat archetypes over the 5 combat stats — catchRate joined the combat
/// budget (user 2026-07-22) with a flat 20-weight in every archetype: every
/// monster catches a little, none is a catch specialist by archetype (rarity
/// and species drive that). Weights are RELATIVE (normalised on distribute),
/// so the flat add simply dilutes HP/ATK/DEF/SPD evenly by ~10%. A richer set
/// (user 2026-07-17): the four ISOLATED single-stat focuses plus balanced and
/// two-stat MIXED forms, so a re-rolled roster gets real variety.
enum CombatArchetype {
  allrounder('Allrounder'),
  // Isolated — one dominant stat.
  bulwark('Bulwark (HP)'),
  berserker('Berserker (ATK)'),
  guardian('Guardian (DEF)'),
  sprinter('Sprinter (SPD)'),
  // Mixed — two-stat leans.
  tank('Tank (HP+DEF)'),
  bruiser('Bruiser (HP+ATK)'),
  glassCannon('Glass Cannon (ATK+SPD)'),
  skirmisher('Skirmisher (fast attacker)'),
  duelist('Duelist (DEF+SPD)');

  final String label;
  const CombatArchetype(this.label);
}

const Map<CombatArchetype, Map<CreatureStat, double>> kCombatArchetypeWeights = {
  CombatArchetype.allrounder: {
    CreatureStat.hp: 60,
    CreatureStat.attack: 40,
    CreatureStat.defense: 40,
    CreatureStat.speed: 40,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.bulwark: {
    CreatureStat.hp: 90,
    CreatureStat.attack: 30,
    CreatureStat.defense: 40,
    CreatureStat.speed: 20,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.berserker: {
    CreatureStat.hp: 40,
    CreatureStat.attack: 90,
    CreatureStat.defense: 25,
    CreatureStat.speed: 25,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.guardian: {
    CreatureStat.hp: 45,
    CreatureStat.attack: 25,
    CreatureStat.defense: 90,
    CreatureStat.speed: 20,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.sprinter: {
    CreatureStat.hp: 40,
    CreatureStat.attack: 30,
    CreatureStat.defense: 20,
    CreatureStat.speed: 90,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.tank: {
    CreatureStat.hp: 75,
    CreatureStat.attack: 25,
    CreatureStat.defense: 60,
    CreatureStat.speed: 20,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.bruiser: {
    CreatureStat.hp: 65,
    CreatureStat.attack: 65,
    CreatureStat.defense: 30,
    CreatureStat.speed: 20,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.glassCannon: {
    CreatureStat.hp: 35,
    CreatureStat.attack: 70,
    CreatureStat.defense: 20,
    CreatureStat.speed: 55,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.skirmisher: {
    CreatureStat.hp: 45,
    CreatureStat.attack: 55,
    CreatureStat.defense: 25,
    CreatureStat.speed: 55,
    CreatureStat.catchRate: 20,
  },
  CombatArchetype.duelist: {
    CreatureStat.hp: 45,
    CreatureStat.attack: 30,
    CreatureStat.defense: 60,
    CreatureStat.speed: 45,
    CreatureStat.catchRate: 20,
  },
};

/// Non-combat archetypes: one focus stat takes [kCivilFocusShare] of the
/// budget, the rest spreads evenly. `generalist` spreads everything evenly.
enum CivilArchetype {
  generalist,
  carrier,
  // One per work-role stat since the 2026-07-25 rework. lumberjack / miner /
  // prospector / provisioner are gone with the four era-I trade stats they
  // focused: a species is a GATHERER or a PRODUCER now, not a woodcutter.
  //
  // `quartermaster` went with the `logistics` stat it focused (2026-07-26) and
  // came BACK with it on 2026-07-30, when logistics became the stores' stat —
  // this time it has a building to be good at (the Storehouse, the Gold Vault)
  // instead of naming three posts that read other stats.
  gatherer,
  producer,
  artisan,
  builder,
  breeder,
  medic,
  trader,
  quartermaster,
}

/// Share of the non-combat budget a specialist pours into its focus stat.
const double kCivilFocusShare = 0.40;

/// The stat a civil archetype specialises in (null = generalist).
CreatureStat? civilFocusStat(CivilArchetype a) => switch (a) {
  CivilArchetype.generalist => null,
  CivilArchetype.carrier => CreatureStat.carry,
  CivilArchetype.gatherer => CreatureStat.gathering,
  CivilArchetype.producer => CreatureStat.production,
  CivilArchetype.artisan => CreatureStat.crafting,
  CivilArchetype.builder => CreatureStat.construction,
  CivilArchetype.breeder => CreatureStat.breeding,
  CivilArchetype.medic => CreatureStat.medicine,
  CivilArchetype.trader => CreatureStat.trade,
  CivilArchetype.quartermaster => CreatureStat.logistics,
};

/// All non-combat stats (the 8 work roles + carry).
List<CreatureStat> get kNonCombatStats =>
    CreatureStat.values.where((s) => s.isCivilian).toList();

/// Weights for a civil archetype, summing to [kNonCombatBudgetTarget].
Map<CreatureStat, double> civilArchetypeWeights(CivilArchetype a) {
  final stats = kNonCombatStats;
  final focus = civilFocusStat(a);
  if (focus == null) {
    final each = kNonCombatBudgetTarget / stats.length;
    return {for (final s in stats) s: each};
  }
  final focusPoints = kNonCombatBudgetTarget * kCivilFocusShare;
  final rest = (kNonCombatBudgetTarget - focusPoints) / (stats.length - 1);
  return {for (final s in stats) s: s == focus ? focusPoints : rest};
}

// ── Prioritised work role (user design 2026-07-17) ──────────
// Instead of one civil archetype = one focus stat, a species picks UP TO 3
// work stats in PRIORITY order. The 1st gets the biggest share of the work
// budget, the 2nd less, the 3rd less again; every other work stat keeps a
// small even base. Empty list = the even generalist spread.

/// Relative weight of each priority slot (1st, 2nd, 3rd).
const List<double> kWorkPriorityWeights = [3.0, 1.8, 1.0];

/// Base weight every work stat keeps even when it isn't a priority.
const double kWorkBaseWeight = 0.4;

/// Non-combat budget weights for up to 3 prioritised work stats.
Map<CreatureStat, double> workRoleWeights(List<CreatureStat> priorities) {
  final stats = kNonCombatStats;
  // Dedupe while keeping order, cap at 3.
  final picks = <CreatureStat>[];
  for (final s in priorities) {
    if (!picks.contains(s) && picks.length < 3) picks.add(s);
  }
  if (picks.isEmpty) {
    final each = kNonCombatBudgetTarget / stats.length;
    return {for (final s in stats) s: each};
  }
  final w = {for (final s in stats) s: kWorkBaseWeight};
  for (var i = 0; i < picks.length; i++) {
    w[picks[i]] = (w[picks[i]] ?? 0) + kWorkPriorityWeights[i];
  }
  final total = w.values.fold(0.0, (a, b) => a + b);
  return {for (final s in stats) s: kNonCombatBudgetTarget * w[s]! / total};
}

/// Best-matching combat archetype for a stat table (user 2026-07-24): compares
/// the normalised stage-0 combat spread to each [kCombatArchetypeWeights] entry
/// and returns the nearest. Used by the dev tools to COUNT / spread roles even
/// though the archetype itself isn't stored on the species.
CombatArchetype inferCombatArchetype(Map<CreatureStat, StatCurve> stats) {
  final vals = {
    for (final s in kCombatStats) s: stats[s]?.stageBase.first ?? 0.0,
  };
  final total = vals.values.fold(0.0, (a, b) => a + b);
  if (total <= 0) return CombatArchetype.allrounder;
  final norm = {for (final e in vals.entries) e.key: e.value / total};
  var best = CombatArchetype.allrounder;
  var bestDist = double.infinity;
  for (final a in CombatArchetype.values) {
    final w = kCombatArchetypeWeights[a]!;
    final wt = w.values.fold(0.0, (x, y) => x + y);
    var dist = 0.0;
    for (final s in kCombatStats) {
      final d = norm[s]! - (w[s] ?? 0) / wt;
      dist += d * d;
    }
    if (dist < bestDist) {
      bestDist = dist;
      best = a;
    }
  }
  return best;
}

/// The work stats a table clearly specialises in — those whose stage-0 base is
/// meaningfully above the even spread (≥1.3× the work mean), highest first, up
/// to [max]. Empty for a generalist. Used for the dev "priority" counts.
List<CreatureStat> inferWorkPriorities(
  Map<CreatureStat, StatCurve> stats, {
  int max = 3,
}) {
  final work = kNonCombatStats;
  final vals = {for (final s in work) s: stats[s]?.stageBase.first ?? 0.0};
  if (vals.isEmpty) return const [];
  final mean = vals.values.reduce((a, b) => a + b) / vals.length;
  final picks = vals.entries.where((e) => e.value > mean * 1.3).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in picks.take(max)) e.key];
}

/// Species' catch-rate modifier (slipperiness), per rarity — set globally in
/// the Species-dev config (user 2026-07-24), no longer authored per species.
double catchRateForRarity(CreatureRarity rarity) =>
    kSpeciesBalance.of(rarity).catchRate;

/// The configured hard MAX BASE for [stat] at [rarity] — the per-category limit
/// (user 2026-07-24), shown in the editor. Null when uncapped.
double? statBaseMax(CreatureStat stat, CreatureRarity rarity) =>
    kSpeciesBalance.of(rarity).maxBaseFor(stat);

/// Builds a complete, exactly-on-budget stat table for an archetype pair at the
/// given rarity/tier. All three evolution stages start equal — raising stage
/// 2/3 bases is the author's job (that delta IS the evo bonus).
Map<CreatureStat, StatCurve> buildArchetypeCurves({
  required CombatArchetype combat,
  required CivilArchetype civil,
  required CreatureRarity rarity,
  int tier = 1,
}) {
  final b = defaultBudget(rarity: rarity, tier: tier);
  return {
    ..._distribute(kCombatArchetypeWeights[combat]!, b.combatBase,
        b.combatGrowth),
    ..._distribute(civilArchetypeWeights(civil), b.workBase, b.workGrowth),
  };
}

// ── Editable budgets (user design 2026-07-17) ───────────────
// The four budget TOTALS a species spends are no longer fixed at 240/160 ×
// rarity — the author sets them (or rolls them), so monsters can differ in
// overall power, not just in how a shared budget is split. Rarity/tier only
// supplies the DEFAULT suggestion.

/// The four budget totals: combat base + growth, work base + growth.
typedef BudgetTargets = ({
  double combatBase,
  double combatGrowth,
  double workBase,
  double workGrowth,
});

/// The rarity default budget (the per-rarity totals, split combat/work by
/// [kDefaultCombatShare]) — used to seed the editor's fields.
BudgetTargets defaultBudget({required CreatureRarity rarity, int tier = 1}) {
  // Per-CATEGORY base AND growth come straight from the live config (user
  // 2026-07-24: combat/civil points and growth are set per rarity).
  final c = kSpeciesBalance.of(rarity);
  return (
    combatBase: c.combatBase,
    combatGrowth: c.combatGrowth,
    workBase: c.workBase,
    workGrowth: c.workGrowth,
  );
}

/// Total base points a species spends (combat + work), by rarity — the TIER-1
/// spec (user 2026-07-17). FIXED per rarity; only the combat/work SPLIT is
/// free. Tier is ignored until tier 2 is specified.
double budgetBaseTotal({required CreatureRarity rarity, int tier = 1}) =>
    kSpeciesBalance.baseTotal(rarity);

/// Total growth/Lv a species spends (combat + work), per rarity — set in the
/// config now (user 2026-07-24), no longer forced to base ÷ 30.
double budgetGrowthTotal({required CreatureRarity rarity, int tier = 1}) =>
    kSpeciesBalance.growthTotal(rarity);

/// A budget with the given combat SHARE of the fixed totals ([baseShare] and
/// [growthShare] are the combat fraction, 0..1; work gets the rest).
BudgetTargets budgetFromSplit({
  required CreatureRarity rarity,
  int tier = 1,
  required double baseShare,
  required double growthShare,
}) {
  final tb = budgetBaseTotal(rarity: rarity, tier: tier);
  final tg = budgetGrowthTotal(rarity: rarity, tier: tier);
  final bs = baseShare.clamp(0.0, 1.0);
  final gs = growthShare.clamp(0.0, 1.0);
  return (
    combatBase: tb * bs,
    combatGrowth: tg * gs,
    workBase: tb * (1 - bs),
    workGrowth: tg * (1 - gs),
  );
}

/// The combat/work split is FIXED (user 2026-07-22: "alle Monster pro
/// Seltenheitsstufe sollen die gleiche Verteilung von Kampf zu zivil haben"):
/// every species of every rarity uses [kDefaultCombatShare]. The old rolled
/// 45–60% band is gone — species now differ WITHIN each half (archetypes and
/// work priorities), never in how much of the budget is martial. rollBudget
/// keeps its signature (the editor's "roll" path calls it) but is
/// deterministic now.
BudgetTargets rollBudget({
  required CreatureRarity rarity,
  required math.Random rng,
  int tier = 1,
}) => defaultBudget(rarity: rarity, tier: tier);

/// The budget a species' current curves actually spend — seeds the editor
/// fields when opening an existing species.
BudgetTargets budgetFromStats(Map<CreatureStat, StatCurve> stats) {
  double baseSum(bool Function(CreatureStat) w) => CreatureStat.values
      .where(w)
      .fold(0.0, (s, st) => s + (stats[st]?.baseAt(0) ?? 0));
  double growthSum(bool Function(CreatureStat) w) => CreatureStat.values
      .where(w)
      .fold(0.0, (s, st) => s + (stats[st]?.growth ?? 0));
  return (
    combatBase: baseSum((s) => s.isCombat),
    combatGrowth: growthSum((s) => s.isCombat),
    workBase: baseSum((s) => s.isCivilian),
    workGrowth: growthSum((s) => s.isCivilian),
  );
}

/// Distributes [weights] so they sum to [baseTotal] (stage 0) and [growthTotal].
Map<CreatureStat, StatCurve> _distribute(
  Map<CreatureStat, double> weights,
  double baseTotal,
  double growthTotal,
) {
  final sum = weights.values.fold(0.0, (a, b) => a + b);
  return {
    for (final e in weights.entries)
      e.key: StatCurve(
        stageBase: List.filled(3, sum > 0 ? e.value / sum * baseTotal : 0),
        growth: sum > 0 ? e.value / sum * growthTotal : 0,
      ),
  };
}

/// Exactly-on-budget curves from a combat archetype + up to 3 prioritised
/// work stats, distributed across the given [budget] (the editor's "Apply").
Map<CreatureStat, StatCurve> buildCurves({
  required CombatArchetype combat,
  required List<CreatureStat> workPriorities,
  required BudgetTargets budget,
}) => {
  ..._distribute(
    kCombatArchetypeWeights[combat]!,
    budget.combatBase,
    budget.combatGrowth,
  ),
  ..._distribute(
    workRoleWeights(workPriorities),
    budget.workBase,
    budget.workGrowth,
  ),
};

/// Like [buildCurves] but RANDOMISED (user request: press "Roll" again for a
/// different monster). Weights are jittered ±[jitter] then re-normalised to
/// the same [budget] — so every roll spends exactly the budget but the split,
/// and thus the monster, differs.
///
/// BASE AND GROWTH ARE ROLLED SEPARATELY (user 2026-07-27: "dann soll nicht
/// automatisch der Anstieg und der Startwert hoch sein. Es soll komplett
/// zufällig sein"). One jittered weight vector used to drive BOTH halves, which
/// made the two perfectly correlated: whatever the roll pushed up started high
/// AND grew fast, so a rolled monster was simply good or bad at a stat, never
/// a late bloomer or a strong starter that plateaus.
///
/// Two independent draws from the SAME archetype weights fix that. The
/// archetype still sets the mean of both — a Bulwark keeps its HP lean at every
/// level, which a fully random growth split would throw away (growth dominates
/// the stat past ~Lv 30) — but whether a given stat's base and its slope both
/// land high is now chance.
Map<CreatureStat, StatCurve> rollCurves({
  required CombatArchetype combat,
  required List<CreatureStat> workPriorities,
  required BudgetTargets budget,
  required math.Random rng,
  double jitter = 0.35,
}) {
  Map<CreatureStat, double> jit(Map<CreatureStat, double> w) => {
    for (final e in w.entries)
      e.key:
          e.value * (1 + (rng.nextDouble() * 2 - 1) * jitter).clamp(0.15, 2.0),
  };
  final combatW = kCombatArchetypeWeights[combat]!;
  final workW = workRoleWeights(workPriorities);
  return {
    // Note the FOUR jit() calls: one per half, per curve. Hoisting any of them
    // into a shared variable is what re-couples base to growth.
    ..._distributeSplit(
      jit(combatW),
      jit(combatW),
      budget.combatBase,
      budget.combatGrowth,
    ),
    ..._distributeSplit(
      jit(workW),
      jit(workW),
      budget.workBase,
      budget.workGrowth,
    ),
  };
}

/// [_distribute] with a SEPARATE weighting for the growth line: [baseWeights]
/// spend [baseTotal] over the stage bases, [growthWeights] spend [growthTotal]
/// over the slopes. Both still land exactly on their budget.
Map<CreatureStat, StatCurve> _distributeSplit(
  Map<CreatureStat, double> baseWeights,
  Map<CreatureStat, double> growthWeights,
  double baseTotal,
  double growthTotal,
) {
  final baseSum = baseWeights.values.fold(0.0, (a, b) => a + b);
  final growthSum = growthWeights.values.fold(0.0, (a, b) => a + b);
  return {
    for (final e in baseWeights.entries)
      e.key: StatCurve(
        stageBase: List.filled(
          3,
          baseSum > 0 ? e.value / baseSum * baseTotal : 0,
        ),
        growth: growthSum > 0
            ? (growthWeights[e.key] ?? 0) / growthSum * growthTotal
            : 0,
      ),
  };
}

/// Rescales [stats] so every audited budget line lands exactly on its
/// target (user request 2026-07-17: "passe die Stats der Monster allgemein
/// an — einige sind noch im roten Bereich"), while preserving what makes
/// the species ITSELF: its distribution across stats (the archetype flavor)
/// and its stage-1/2 evolution bumps, which scale by the same factor as the
/// stage-0 base. Combat and non-combat groups scale independently, base and
/// growth each to their own target.
///
/// A group with no points at all can't be scaled onto a positive target —
/// it gets the even generalist spread instead.
Map<CreatureStat, StatCurve> normalizeStatBudget({
  required Map<CreatureStat, StatCurve> stats,
  required CreatureRarity rarity,
  int tier = 1,
  BudgetTargets? targets,
}) {
  final t = targets ?? defaultBudget(rarity: rarity, tier: tier);
  final result = <CreatureStat, StatCurve>{};

  void scaleGroup(
    List<CreatureStat> members,
    double baseTarget,
    double growthTarget,
  ) {
    final present = members.where((s) => stats[s] != null).toList();
    final baseSum = present.fold(0.0, (sum, s) => sum + stats[s]!.baseAt(0));
    if (present.isEmpty || baseSum <= 0) {
      final each = baseTarget / members.length;
      final eachGrowth = growthTarget / members.length;
      for (final s in members) {
        result[s] = StatCurve(
          stageBase: List.filled(3, each),
          growth: eachGrowth,
        );
      }
      return;
    }
    final baseScale = baseTarget / baseSum;
    final growthSum = present.fold(0.0, (sum, s) => sum + stats[s]!.growth);
    for (final s in present) {
      final curve = stats[s]!;
      final scaledBases = [
        for (var stage = 0; stage < 3; stage++)
          curve.baseAt(stage) * baseScale,
      ];
      // Keep each stat's share of the group's growth; a zero-growth group
      // re-derives growth from the scaled base so the growth line reaches
      // its target instead of staying stuck at zero.
      final growth = growthSum > 0
          ? curve.growth * (growthTarget / growthSum)
          : scaledBases[0] * kGrowthPerLevelTarget;
      result[s] = StatCurve(stageBase: scaledBases, growth: growth);
    }
  }

  scaleGroup(
    CreatureStat.values.where((s) => s.isCombat).toList(),
    t.combatBase,
    t.combatGrowth,
  );
  scaleGroup(kNonCombatStats, t.workBase, t.workGrowth);
  return result;
}

/// One audited line (e.g. "combat base"): actual vs target.
class BudgetLine {
  final String label;
  final double actual;
  final double target;
  const BudgetLine({
    required this.label,
    required this.actual,
    required this.target,
  });

  /// Signed relative deviation from the target (0.1 = 10% over budget).
  double get deviation => target == 0 ? 0 : (actual - target) / target;
  bool get withinTolerance => deviation.abs() <= kBudgetTolerance;
}

class StatBudgetReport {
  final List<BudgetLine> lines;

  /// Combat-base sums per evolution stage (stage bumps are informational —
  /// the doc doesn't budget them yet).
  final List<double> combatBaseByStage;

  const StatBudgetReport({
    required this.lines,
    required this.combatBaseByStage,
  });

  bool get isWithinTolerance => lines.every((l) => l.withinTolerance);
}

/// Audits [stats] (stage-0 bases + growth) against a budget. Uses [targets]
/// when given (the editor's editable/rolled budget), else the rarity/tier
/// default — so existing callers/tests keep the fixed-budget behaviour.
StatBudgetReport auditStatBudget({
  required Map<CreatureStat, StatCurve> stats,
  required CreatureRarity rarity,
  int tier = 1,
  BudgetTargets? targets,
}) {
  final t = targets ?? defaultBudget(rarity: rarity, tier: tier);

  double baseSum(bool Function(CreatureStat) where, int stage) =>
      CreatureStat.values
          .where(where)
          .fold(0.0, (sum, s) => sum + (stats[s]?.baseAt(stage) ?? 0));
  double growthSum(bool Function(CreatureStat) where) => CreatureStat.values
      .where(where)
      .fold(0.0, (sum, s) => sum + (stats[s]?.growth ?? 0));

  return StatBudgetReport(
    lines: [
      BudgetLine(
        label: 'Combat base',
        actual: baseSum((s) => s.isCombat, 0),
        target: t.combatBase,
      ),
      BudgetLine(
        label: 'Combat growth/Lv',
        actual: growthSum((s) => s.isCombat),
        target: t.combatGrowth,
      ),
      BudgetLine(
        label: 'Non-combat base',
        actual: baseSum((s) => s.isCivilian, 0),
        target: t.workBase,
      ),
      BudgetLine(
        label: 'Non-combat growth/Lv',
        actual: growthSum((s) => s.isCivilian),
        target: t.workGrowth,
      ),
    ],
    combatBaseByStage: [
      for (var stage = 0; stage < 3; stage++)
        baseSum((s) => s.isCombat, stage),
    ],
  );
}

// ── Total-budget check (combat/work split is a free axis) ───
// The combat/work SPLIT is an authored design axis now (a fighter vs a worker),
// so "is this species on budget?" is no longer "does it match the 60/40 split"
// but "does it spend the full rarity/tier TOTAL, however it divides it" (user
// 2026-07-17). The dev list flag and its fix button use these; the editor's own
// panel still audits against the author's chosen split.

double _totalBaseOf(Map<CreatureStat, StatCurve> stats) => CreatureStat.values
    .fold(0.0, (s, st) => s + (stats[st]?.baseAt(0) ?? 0));
double _totalGrowthOf(Map<CreatureStat, StatCurve> stats) => CreatureStat.values
    .fold(0.0, (s, st) => s + (stats[st]?.growth ?? 0));

/// Whether [stats] spend the full rarity/tier budget in TOTAL (stage-0 base and
/// growth), regardless of the combat/work split.
bool isOnTotalBudget({
  required Map<CreatureStat, StatCurve> stats,
  required CreatureRarity rarity,
  int tier = 1,
  double tolerance = kBudgetTolerance,
}) {
  bool ok(double actual, double target) =>
      target == 0 ? actual == 0 : (actual - target).abs() / target <= tolerance;
  return ok(_totalBaseOf(stats), budgetBaseTotal(rarity: rarity, tier: tier)) &&
      ok(_totalGrowthOf(stats), budgetGrowthTotal(rarity: rarity, tier: tier));
}

/// Rescales [stats] so the TOTAL base and growth hit the rarity/tier targets
/// while PRESERVING the species' combat/work split, its per-stat distribution
/// and its evo bumps — a uniform scale, so a fighter stays a fighter and a
/// worker stays a worker (unlike [normalizeStatBudget], which forces the split).
Map<CreatureStat, StatCurve> normalizeToTotalBudget({
  required Map<CreatureStat, StatCurve> stats,
  required CreatureRarity rarity,
  int tier = 1,
}) {
  final baseSum = _totalBaseOf(stats);
  final growthSum = _totalGrowthOf(stats);
  final baseScale = baseSum > 0
      ? budgetBaseTotal(rarity: rarity, tier: tier) / baseSum
      : 1.0;
  final growthScale = growthSum > 0
      ? budgetGrowthTotal(rarity: rarity, tier: tier) / growthSum
      : 1.0;
  return {
    for (final e in stats.entries)
      e.key: StatCurve(
        stageBase: [for (final b in e.value.stageBase) b * baseScale],
        growth: e.value.growth * growthScale,
      ),
  };
}
